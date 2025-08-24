package main

import (
	"archive/zip"
	"bufio"
	"context"
	"fmt"
	"io"
	"math"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// ProcessingStep represents a step in the processing pipeline
type ProcessingStep struct {
	Name        string
	Description string
	Progress    float64
	Status      string
}

// ProcessingUpdate represents a real-time update from the processor
type ProcessingUpdate struct {
	Region       string
	CurrentStep  int
	TotalSteps   int
	Step         ProcessingStep
	OverallProgress float64
	Status       string
	Error        error
}

// RegionProcessor handles the native Go processing of regions
type RegionProcessor struct {
	region      Region
	outputDir   string
	progressCh  chan ProcessingUpdate
	graphhopperJar string
	configFile  string
}

// NewRegionProcessor creates a new processor for a region
func NewRegionProcessor(region Region, outputDir string, progressCh chan ProcessingUpdate) *RegionProcessor {
	return &RegionProcessor{
		region:     region,
		outputDir:  outputDir,
		progressCh: progressCh,
		graphhopperJar: "graphhopper-web-1.0-SNAPSHOT.jar",
		configFile: "config-example.yml",
	}
}

// Process runs the complete processing pipeline for a region
func (p *RegionProcessor) Process(ctx context.Context) error {
	steps := []struct {
		name string
		fn   func(context.Context) error
	}{
		{"download", p.downloadFiles},
		{"import", p.runGraphHopperImport},
		{"organize", p.organizeFiles},
		{"zip", p.createZipFile},
		{"cleanup", p.cleanup},
	}

	totalSteps := len(steps)
	
	for i, step := range steps {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		// Only send step updates for non-download steps (download step handles its own progress)
		if step.name != "download" {
			p.sendUpdate(ProcessingUpdate{
				Region:      p.region.Name,
				CurrentStep: i + 1,
				TotalSteps:  totalSteps,
				Step: ProcessingStep{
					Name:        step.name,
					Description: p.getStepDescription(step.name),
					Progress:    0.0,
					Status:      "starting",
				},
				OverallProgress: float64(i) / float64(totalSteps) * 100,
				Status:         fmt.Sprintf("Step %d/%d: %s", i+1, totalSteps, p.getStepDescription(step.name)),
			})
		}

		if err := step.fn(ctx); err != nil {
			p.sendUpdate(ProcessingUpdate{
				Region: p.region.Name,
				Error:  fmt.Errorf("failed at step %s: %v", step.name, err),
			})
			return err
		}

		// Only send completion updates for non-download steps 
		if step.name != "download" {
			p.sendUpdate(ProcessingUpdate{
				Region:      p.region.Name,
				CurrentStep: i + 1,
				TotalSteps:  totalSteps,
				Step: ProcessingStep{
					Name:        step.name,
					Description: p.getStepDescription(step.name),
					Progress:    100.0,
					Status:      "completed",
				},
				OverallProgress: float64(i+1) / float64(totalSteps) * 100,
				Status:         fmt.Sprintf("Completed: %s", p.getStepDescription(step.name)),
			})
		}
	}

	p.sendUpdate(ProcessingUpdate{
		Region:          p.region.Name,
		CurrentStep:     totalSteps,
		TotalSteps:      totalSteps,
		OverallProgress: 100.0,
		Status:          fmt.Sprintf("✅ %s completed successfully!", p.region.Name),
	})

	return nil
}

func (p *RegionProcessor) getStepDescription(step string) string {
	descriptions := map[string]string{
		"download": "Downloading OSM data files",
		"import":   "Running GraphHopper import",
		"organize": "Organizing files for VNS",
		"zip":      "Creating ZIP archive",
		"cleanup":  "Cleaning up temporary files",
	}
	if desc, exists := descriptions[step]; exists {
		return desc
	}
	return step
}

func (p *RegionProcessor) sendUpdate(update ProcessingUpdate) {
	select {
	case p.progressCh <- update:
	default:
		// Channel full, skip this update
	}
}

func (p *RegionProcessor) downloadFiles(ctx context.Context) error {
	// Create temp directory for downloads
	tempDir := filepath.Join(os.TempDir(), fmt.Sprintf("vns-processing-%s", strings.ReplaceAll(p.region.ID, "/", "-")))
	if err := os.MkdirAll(tempDir, 0755); err != nil {
		return fmt.Errorf("failed to create temp directory: %v", err)
	}

	// Use URLs directly from region data instead of constructing them
	files := []struct {
		name string
		url  string
		required bool
	}{}
	
	// PBF file (required)
	if pbfURL, exists := p.region.URLs["pbf"]; exists {
		pbfFilename := filepath.Base(pbfURL) // Extract filename from URL
		files = append(files, struct {
			name string
			url  string
			required bool
		}{
			name: pbfFilename,
			url:  pbfURL,
			required: true,
		})
	} else {
		return fmt.Errorf("no PBF download URL available for region %s", p.region.ID)
	}
	
	// Try to get POLY and KML files using constructed URLs
	// Extract the region name from the PBF URL for constructing other file URLs
	if pbfURL, exists := p.region.URLs["pbf"]; exists {
		baseURL := pbfURL[:strings.LastIndex(pbfURL, "/")]
		pbfFilename := filepath.Base(pbfURL)
		regionName := strings.TrimSuffix(pbfFilename, "-latest.osm.pbf")
		
		files = append(files, struct {
			name string
			url  string
			required bool
		}{
			name: fmt.Sprintf("%s.poly", regionName),
			url:  fmt.Sprintf("%s/%s.poly", baseURL, regionName),
			required: true,
		})
		
		files = append(files, struct {
			name string
			url  string
			required bool
		}{
			name: fmt.Sprintf("%s.kml", regionName),
			url:  fmt.Sprintf("%s/%s.kml", baseURL, regionName),
			required: false,
		})
	}

	for _, file := range files {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		// Let ProgressReader handle detailed download progress updates
		filePath := filepath.Join(tempDir, file.name)
		if err := p.downloadFile(ctx, file.url, filePath); err != nil {
			if file.required {
				return fmt.Errorf("failed to download required file %s: %v", file.name, err)
			}
			// Skip optional files if they don't exist
			continue
		}
	}

	return nil
}

func (p *RegionProcessor) downloadFile(ctx context.Context, url, filepath string) error {
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return err
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("HTTP %d: %s", resp.StatusCode, resp.Status)
	}

	out, err := os.Create(filepath)
	if err != nil {
		return err
	}
	defer out.Close()

	// Get content length for progress tracking
	contentLength := resp.ContentLength
	if contentLength <= 0 {
		// If no content length, fallback to simple copy
		_, err = io.Copy(out, resp.Body)
		return err
	}

	// Create a progress reader that sends updates
	now := time.Now()
	progressReader := &ProgressReader{
		Reader:        resp.Body,
		Total:         contentLength,
		Downloaded:    0,
		ProgressChan:  p.progressCh,
		Filename:      filepath[strings.LastIndex(filepath, "/")+1:], // Extract filename
		StartTime:     now,
		LastUpdate:    now,
	}

	_, err = io.Copy(out, progressReader)
	return err
}

// ProgressReader wraps an io.Reader to track download progress
type ProgressReader struct {
	Reader       io.Reader
	Total        int64
	Downloaded   int64
	ProgressChan chan ProcessingUpdate
	Filename     string
	StartTime    time.Time
	LastUpdate   time.Time
}

func (pr *ProgressReader) Read(p []byte) (int, error) {
	n, err := pr.Reader.Read(p)
	pr.Downloaded += int64(n)
	
	now := time.Now()
	
	// Calculate progress percentage
	progress := float64(pr.Downloaded) / float64(pr.Total) * 100
	
	// Send progress update (throttle updates to avoid flooding)
	if pr.Downloaded%8192 == 0 || err != nil || now.Sub(pr.LastUpdate) > 500*time.Millisecond {
		pr.LastUpdate = now
		
		// Calculate download speed and ETA
		elapsed := now.Sub(pr.StartTime).Seconds()
		var speedStr, etaStr, sizeStr string
		
		if elapsed > 0 {
			bytesPerSecond := float64(pr.Downloaded) / elapsed
			speedStr = formatBytes(int64(bytesPerSecond)) + "/s"
			
			if bytesPerSecond > 0 && pr.Downloaded < pr.Total {
				remaining := pr.Total - pr.Downloaded
				etaSeconds := float64(remaining) / bytesPerSecond
				etaStr = formatDuration(time.Duration(etaSeconds * float64(time.Second)))
			}
		}
		
		sizeStr = fmt.Sprintf("%s/%s", formatBytes(pr.Downloaded), formatBytes(pr.Total))
		
		// Create detailed description
		description := fmt.Sprintf("Downloading %s (%.1f%%)", pr.Filename, progress)
		if speedStr != "" {
			description += fmt.Sprintf(" • %s", speedStr)
		}
		if etaStr != "" {
			description += fmt.Sprintf(" • %s left", etaStr)
		}
		description += fmt.Sprintf(" • %s", sizeStr)
		
		// Log to file for debugging
		if logFile, err := os.OpenFile("progress-debug.log", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644); err == nil {
			fmt.Fprintf(logFile, "PROGRESS-SEND: %s\n", description)
			logFile.Close()
		}
		
		select {
		case pr.ProgressChan <- ProcessingUpdate{
			Step: ProcessingStep{
				Name:        "download",
				Description: description,
				Progress:    progress,
				Status:      "downloading",
			},
		}:
			// Log successful send
			if logFile, err := os.OpenFile("progress-debug.log", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644); err == nil {
				fmt.Fprintf(logFile, "PROGRESS-SENT-SUCCESS: %s\n", description)
				logFile.Close()
			}
		default:
			// Log channel full
			if logFile, err := os.OpenFile("progress-debug.log", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644); err == nil {
				fmt.Fprintf(logFile, "PROGRESS-CHANNEL-FULL: %s\n", description)
				logFile.Close()
			}
		}
	}
	
	return n, err
}

// formatBytes converts bytes to human-readable format
func formatBytes(bytes int64) string {
	const unit = 1024
	if bytes < unit {
		return fmt.Sprintf("%d B", bytes)
	}
	div, exp := int64(unit), 0
	for n := bytes / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(bytes)/float64(div), "KMGTPE"[exp])
}

// formatDuration converts duration to human-readable format
func formatDuration(d time.Duration) string {
	if d < time.Minute {
		return fmt.Sprintf("%.0fs", d.Seconds())
	}
	if d < time.Hour {
		return fmt.Sprintf("%.0fm%.0fs", d.Minutes(), math.Mod(d.Seconds(), 60))
	}
	return fmt.Sprintf("%.0fh%.0fm", d.Hours(), math.Mod(d.Minutes(), 60))
}

func (p *RegionProcessor) runGraphHopperImport(ctx context.Context) error {
	p.sendUpdate(ProcessingUpdate{
		Region: p.region.Name,
		Step: ProcessingStep{
			Name:        "import",
			Description: "🔄 Initializing GraphHopper import",
			Progress:    0.0,
			Status:      "running",
		},
	})

	// Check if Java is available
	if _, err := exec.LookPath("java"); err != nil {
		return fmt.Errorf("Java is required but not found in PATH. Please install Java 8 or higher")
	}

	// Check if GraphHopper JAR exists
	if _, err := os.Stat(p.graphhopperJar); err != nil {
		return fmt.Errorf("GraphHopper JAR not found at %s", p.graphhopperJar)
	}

	tempDir := filepath.Join(os.TempDir(), fmt.Sprintf("vns-processing-%s", strings.ReplaceAll(p.region.ID, "/", "-")))
	
	// Find the PBF file in temp directory
	var osmFile string
	files, err := os.ReadDir(tempDir)
	if err != nil {
		return fmt.Errorf("failed to read temp directory: %v", err)
	}
	
	for _, file := range files {
		if strings.HasSuffix(file.Name(), ".osm.pbf") {
			osmFile = filepath.Join(tempDir, file.Name())
			break
		}
	}
	
	if osmFile == "" {
		return fmt.Errorf("no PBF file found in temp directory %s", tempDir)
	}

	// Output directory should use a clean name (last part of region ID)
	regionName := p.region.ID
	if strings.Contains(regionName, "/") {
		regionName = regionName[strings.LastIndex(regionName, "/")+1:]
	}
	
	graphDir := filepath.Join(p.outputDir, regionName)

	// Ensure output directory exists
	if err := os.MkdirAll(p.outputDir, 0755); err != nil {
		return fmt.Errorf("failed to create output directory: %v", err)
	}

	// Build GraphHopper command
	args := []string{
		"-Xmx4096m", "-Xms4096m",
		fmt.Sprintf("-Ddw.graphhopper.datareader.file=%s", osmFile),
		fmt.Sprintf("-Ddw.graphhopper.graph.location=%s", graphDir),
		"-jar", p.graphhopperJar,
		"import", p.configFile,
	}

	cmd := exec.CommandContext(ctx, "java", args...)
	cmd.Dir = "." // Run in current directory

	// Use streaming output to provide real-time feedback
	return p.runGraphHopperWithProgress(ctx, cmd)
}

func (p *RegionProcessor) runGraphHopperWithProgress(ctx context.Context, cmd *exec.Cmd) error {
	// Create pipes for stdout and stderr
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return fmt.Errorf("failed to create stdout pipe: %v", err)
	}
	
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return fmt.Errorf("failed to create stderr pipe: %v", err)
	}

	// Start the command
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("failed to start GraphHopper: %v", err)
	}

	// Channel to collect output for error reporting
	outputLines := make([]string, 0)
	
	// Create a combined reader for both stdout and stderr
	combinedReader := io.MultiReader(stdout, stderr)
	scanner := bufio.NewScanner(combinedReader)
	
	// Progress tracking patterns
	patterns := map[string]*regexp.Regexp{
		"reading_osm":    regexp.MustCompile(`(?i)(reading|parsing|processing).*osm`),
		"ways_processed": regexp.MustCompile(`(?i)processed.*?(\d+).*?ways?`),
		"nodes_processed": regexp.MustCompile(`(?i)processed.*?(\d+).*?nodes?`),
		"relations":      regexp.MustCompile(`(?i)processed.*?(\d+).*?relations?`),
		"creating_graph": regexp.MustCompile(`(?i)(creating|building|writing).*?graph`),
		"edges":          regexp.MustCompile(`(?i)edges?.*?(\d+)`),
		"memory":         regexp.MustCompile(`(?i)memory.*?(\d+)`),
		"time_elapsed":   regexp.MustCompile(`(?i)elapsed.*?(\d+(?:\.\d+)?)\s*(s|sec|seconds?|m|min|minutes?)`),
		"finished":       regexp.MustCompile(`(?i)(finished|completed|done|success)`),
	}

	// Track progress state
	progressState := map[string]int{
		"ways":      0,
		"nodes":     0,
		"relations": 0,
		"edges":     0,
	}
	
	currentProgress := 10.0 // Start after initialization
	lastUpdate := time.Now()

	// Process output line by line
	go func() {
		for scanner.Scan() {
			line := strings.TrimSpace(scanner.Text())
			outputLines = append(outputLines, line)
			
			if line == "" {
				continue
			}
			
			// Check for different progress indicators
			description := "🔄 Processing OSM data"
			progressDelta := 0.0
			
			// Parse different types of progress
			if patterns["reading_osm"].MatchString(line) {
				description = "📖 Reading OSM file"
				progressDelta = 5.0
			} else if match := patterns["ways_processed"].FindStringSubmatch(line); len(match) > 1 {
				if count, err := strconv.Atoi(match[1]); err == nil {
					progressState["ways"] = count
					description = fmt.Sprintf("🛣️  Processed %s ways", formatNumber(count))
					progressDelta = 2.0
				}
			} else if match := patterns["nodes_processed"].FindStringSubmatch(line); len(match) > 1 {
				if count, err := strconv.Atoi(match[1]); err == nil {
					progressState["nodes"] = count
					description = fmt.Sprintf("🔵 Processed %s nodes", formatNumber(count))
					progressDelta = 2.0
				}
			} else if match := patterns["relations"].FindStringSubmatch(line); len(match) > 1 {
				if count, err := strconv.Atoi(match[1]); err == nil {
					progressState["relations"] = count
					description = fmt.Sprintf("🔗 Processed %s relations", formatNumber(count))
					progressDelta = 3.0
				}
			} else if patterns["creating_graph"].MatchString(line) {
				description = "🔧 Creating routing graph"
				progressDelta = 10.0
			} else if match := patterns["edges"].FindStringSubmatch(line); len(match) > 1 {
				if count, err := strconv.Atoi(match[1]); err == nil {
					progressState["edges"] = count
					description = fmt.Sprintf("⚡ Generated %s edges", formatNumber(count))
					progressDelta = 5.0
				}
			} else if patterns["finished"].MatchString(line) {
				description = "✅ GraphHopper import completed"
				currentProgress = 100.0
			}
			
			// Update progress (cap at 95% until completion)
			if currentProgress < 95.0 {
				currentProgress += progressDelta
				if currentProgress > 95.0 {
					currentProgress = 95.0
				}
			}
			
			// Send progress update (throttle to avoid flooding)
			now := time.Now()
			if now.Sub(lastUpdate) > 500*time.Millisecond || progressDelta > 0 {
				lastUpdate = now
				
				select {
				case p.progressCh <- ProcessingUpdate{
					Region: p.region.Name,
					Step: ProcessingStep{
						Name:        "import",
						Description: description,
						Progress:    currentProgress,
						Status:      "running",
					},
				}:
				default:
					// Channel full, skip update
				}
			}
		}
	}()

	// Wait for command to complete
	err = cmd.Wait()
	
	// Final validation
	if err != nil {
		// Provide detailed error information
		errorOutput := strings.Join(outputLines[max(0, len(outputLines)-20):], "\n")
		return fmt.Errorf("GraphHopper import failed: %v\nRecent output:\n%s", err, errorOutput)
	}
	
	// Check if GraphHopper actually created the expected files
	regionName := p.region.ID
	if strings.Contains(regionName, "/") {
		regionName = regionName[strings.LastIndex(regionName, "/")+1:]
	}
	graphDir := filepath.Join(p.outputDir, regionName)
	
	expectedFiles := []string{"edges", "geometry", "nodes", "properties"}
	for _, file := range expectedFiles {
		if _, err := os.Stat(filepath.Join(graphDir, file)); err != nil {
			recentOutput := strings.Join(outputLines[max(0, len(outputLines)-10):], "\n")
			return fmt.Errorf("GraphHopper import appears to have failed - missing expected file: %s\nRecent output:\n%s", file, recentOutput)
		}
	}
	
	// Final success update
	p.sendUpdate(ProcessingUpdate{
		Region: p.region.Name,
		Step: ProcessingStep{
			Name:        "import",
			Description: "✅ GraphHopper import completed successfully",
			Progress:    100.0,
			Status:      "completed",
		},
		Status: fmt.Sprintf("GraphHopper created routing graph with %s edges", formatNumber(progressState["edges"])),
	})

	return nil
}

// Helper function to format large numbers with commas
func formatNumber(n int) string {
	if n < 1000 {
		return strconv.Itoa(n)
	}
	
	str := strconv.Itoa(n)
	var result strings.Builder
	
	for i, digit := range str {
		if i > 0 && (len(str)-i)%3 == 0 {
			result.WriteString(",")
		}
		result.WriteRune(digit)
	}
	
	return result.String()
}

// Helper function to get max of two integers
func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func (p *RegionProcessor) organizeFiles(ctx context.Context) error {
	tempDir := filepath.Join(os.TempDir(), fmt.Sprintf("vns-processing-%s", strings.ReplaceAll(p.region.ID, "/", "-")))
	
	// Output directory should use a clean name
	regionName := p.region.ID
	if strings.Contains(regionName, "/") {
		regionName = regionName[strings.LastIndex(regionName, "/")+1:]
	}
	graphDir := filepath.Join(p.outputDir, regionName)

	// Find actual boundary files in temp directory
	files, err := os.ReadDir(tempDir)
	if err != nil {
		return fmt.Errorf("failed to read temp directory: %v", err)
	}
	
	boundaryFiles := []string{}
	for _, file := range files {
		if strings.HasSuffix(file.Name(), ".poly") || strings.HasSuffix(file.Name(), ".kml") {
			boundaryFiles = append(boundaryFiles, file.Name())
		}
	}

	for _, file := range boundaryFiles {
		srcPath := filepath.Join(tempDir, file)
		dstPath := filepath.Join(graphDir, file)

		if _, err := os.Stat(srcPath); err == nil {
			if err := os.Rename(srcPath, dstPath); err != nil {
				// If rename fails, try copy
				if err := p.copyFile(srcPath, dstPath); err != nil {
					return fmt.Errorf("failed to move %s: %v", file, err)
				}
				os.Remove(srcPath)
			}
		}
	}

	// Create timestamp files
	timestamp := time.Now().UTC().Format("2006-01-02T15:04:05Z")
	
	// Generic timestamp file
	if err := os.WriteFile(filepath.Join(graphDir, "timestamp"), []byte(timestamp), 0644); err != nil {
		return fmt.Errorf("failed to create timestamp file: %v", err)
	}

	// Region-specific timestamp file
	regionTimestampFile := filepath.Join(graphDir, fmt.Sprintf("%s.timestamp", regionName))
	if err := os.WriteFile(regionTimestampFile, []byte(timestamp), 0644); err != nil {
		return fmt.Errorf("failed to create region timestamp file: %v", err)
	}

	return nil
}

func (p *RegionProcessor) createZipFile(ctx context.Context) error {
	regionName := p.region.ID
	if strings.Contains(regionName, "/") {
		regionName = regionName[strings.LastIndex(regionName, "/")+1:]
	}
	
	graphDir := filepath.Join(p.outputDir, regionName)
	zipFile := filepath.Join(p.outputDir, fmt.Sprintf("%s.zip", regionName))

	file, err := os.Create(zipFile)
	if err != nil {
		return fmt.Errorf("failed to create zip file: %v", err)
	}
	defer file.Close()

	zipWriter := zip.NewWriter(file)
	defer zipWriter.Close()

	return filepath.Walk(graphDir, func(filePath string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		if info.IsDir() {
			return nil
		}

		relPath, err := filepath.Rel(p.outputDir, filePath)
		if err != nil {
			return err
		}

		zipFile, err := zipWriter.Create(relPath)
		if err != nil {
			return err
		}

		fsFile, err := os.Open(filePath)
		if err != nil {
			return err
		}
		defer fsFile.Close()

		_, err = io.Copy(zipFile, fsFile)
		return err
	})
}

func (p *RegionProcessor) cleanup(ctx context.Context) error {
	tempDir := filepath.Join(os.TempDir(), fmt.Sprintf("vns-processing-%s", strings.ReplaceAll(p.region.ID, "/", "-")))
	return os.RemoveAll(tempDir)
}

func (p *RegionProcessor) copyFile(src, dst string) error {
	source, err := os.Open(src)
	if err != nil {
		return err
	}
	defer source.Close()

	destination, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer destination.Close()

	_, err = io.Copy(destination, source)
	return err
}

func (p *RegionProcessor) getBaseURL() string {
	// Determine the appropriate Geofabrik URL based on region
	if strings.HasPrefix(p.region.ID, "us-") {
		return "http://download.geofabrik.de/north-america/us"
	}
	
	// Use the region's PBF URL to determine base URL
	if pbfURL, exists := p.region.URLs["pbf"]; exists {
		// Extract base URL from PBF URL
		lastSlash := strings.LastIndex(pbfURL, "/")
		if lastSlash > 0 {
			return pbfURL[:lastSlash]
		}
	}
	
	// Fallback: construct URL based on continent/parent
	continent := getContinent(p.region.ID, p.region.Parent)
	if p.region.Parent != nil {
		return fmt.Sprintf("http://download.geofabrik.de/%s/%s", continent, *p.region.Parent)
	}
	
	return fmt.Sprintf("http://download.geofabrik.de/%s", continent)
}