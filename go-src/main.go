package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/progress"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// Region represents a Geofabrik region
type Region struct {
	ID       string            `json:"id"`
	Name     string            `json:"name"`
	Parent   *string           `json:"parent,omitempty"`
	URLs     map[string]string `json:"urls"`
	Selected bool              `json:"-"` // UI state only
}

// RegionCache stores cached region data
type RegionCache struct {
	Regions     []Region  `json:"regions"`
	LastUpdated time.Time `json:"last_updated"`
	ETag        string    `json:"etag"`
}

// UserLocation represents detected user location from IP geolocation
type UserLocation struct {
	Country     string `json:"country"`
	CountryCode string `json:"country_code"`
	Region      string `json:"region"`
	RegionCode  string `json:"region_code"`
	City        string `json:"city"`
	Detected    bool   `json:"-"` // Whether location was successfully detected
}

// TreeNode represents a hierarchical node in the tree
type TreeNode struct {
	ID       string
	Name     string
	Children []*TreeNode
	Region   *Region // nil for continent/country nodes
	Expanded bool
	Level    int
}

// UI model for BubbleTea
type model struct {
	regions         []Region
	tree            []*TreeNode
	flatTree        []*TreeNode // flattened tree for display
	cursor          int
	selected        map[int]bool // maps to original region indices
	quitting        bool
	processing      bool
	processingRegions []Region
	processingUpdate ProcessingUpdate
	processingContext context.Context
	processingCancel  context.CancelFunc
	processingChannel chan ProcessingUpdate // Store the channel
	status          string
	filterText      string
	filtering       bool
	useTree         bool // true = tree view, false = flat filtered view
	width           int  // terminal width
	height          int  // terminal height
	progressBar     progress.Model // Official Bubbles progress bar
	stepProgressBar progress.Model // Progress bar for individual steps
	userLocation    UserLocation   // Detected user location
	targetStateID   string         // State ID to auto-position cursor on
}

// Styles
var (
	titleStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#FAFAFA")).
			Background(lipgloss.Color("#7D56F4")).
			Padding(0, 1).
			Bold(true)

	selectedStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#02BA84"))

	cursorStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#FF7CCB"))

	helpStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#626262"))
)

func main() {
	if len(os.Args) > 1 {
		switch os.Args[1] {
		case "--process":
			if len(os.Args) < 3 {
				fmt.Println("Usage: vns-interactive --process region1,region2,...")
				os.Exit(1)
			}
			processRegionsDirectly(os.Args[2])
			return
		case "--cache-clear":
			clearCache()
			return
		case "--cache-info":
			showCacheInfo()
			return
		case "--help", "-h":
			showHelp()
			return
		default:
			showHelp()
			return
		}
	}

	// Default: Interactive mode
	runInteractiveMode()
}

func runInteractiveMode() {
	fmt.Println("🌍 Loading global regions from Geofabrik...")

	regions, err := fetchRegions()
	if err != nil {
		fmt.Printf("❌ Error fetching regions: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("✅ Found %d available regions\n", len(regions))
	
	// Detect user location for smart tree expansion
	fmt.Print("📡 Detecting your location... ")
	userLocation := detectUserLocation()
	if userLocation.Detected {
		locationStr := userLocation.Country
		if userLocation.Region != "" {
			locationStr = fmt.Sprintf("%s, %s", userLocation.Region, userLocation.Country)
		}
		fmt.Printf("📍 %s\n", locationStr)
	} else {
		fmt.Println("❓ Could not detect location")
	}

	// Initialize progress bars
	overallProgress := progress.New(progress.WithDefaultGradient())
	overallProgress.Width = 60
	overallProgress.ShowPercentage = true
	
	stepProgress := progress.New(progress.WithGradient("#7571F9", "#A855F7"))
	stepProgress.Width = 50
	stepProgress.ShowPercentage = true

	m := model{
		regions:         regions,
		selected:        make(map[int]bool),
		status:          fmt.Sprintf("Loaded %d regions", len(regions)),
		useTree:         true,
		width:           80,  // Default width
		height:          24,  // Default height
		progressBar:     overallProgress,
		stepProgressBar: stepProgress,
		userLocation:    userLocation,
	}

	m.buildTree()
	m.updateView()

	p := tea.NewProgram(m, tea.WithAltScreen(), tea.WithMouseCellMotion())
	if _, err := p.Run(); err != nil {
		fmt.Printf("Error running program: %v\n", err)
		os.Exit(1)
	}
}

func fetchRegions() ([]Region, error) {
	cacheFile := getCacheDir() + "/regions.json"

	// Try to load from cache first
	if cache, err := loadRegionCache(cacheFile); err == nil {
		if time.Since(cache.LastUpdated) < 24*time.Hour {
			return cache.Regions, nil
		}
	}

	// Fetch from API
	fmt.Println("📡 Fetching latest region data from Geofabrik API...")
	resp, err := http.Get("https://download.geofabrik.de/index-v1-nogeom.json")
	if err != nil {
		return nil, fmt.Errorf("failed to fetch regions: %v", err)
	}
	defer resp.Body.Close()

	var geoJSON struct {
		Features []struct {
			Properties Region `json:"properties"`
		} `json:"features"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&geoJSON); err != nil {
		return nil, fmt.Errorf("failed to parse JSON: %v", err)
	}

	// Filter and process regions
	var regions []Region
	for _, feature := range geoJSON.Features {
		region := feature.Properties
		if isRegionUsable(region) {
			// Enhance display name with parent context
			if region.Parent != nil && !isContinent(*region.Parent) {
				region.Name = fmt.Sprintf("%s (%s)", region.Name, strings.Title(*region.Parent))
			}
			regions = append(regions, region)
		}
	}

	// Sort by name for better UX
	sort.Slice(regions, func(i, j int) bool {
		return regions[i].Name < regions[j].Name
	})

	// Cache the results
	saveRegionCache(cacheFile, regions, resp.Header.Get("ETag"))

	return regions, nil
}

func isRegionUsable(region Region) bool {
	// Must have PBF file
	if _, hasPBF := region.URLs["pbf"]; !hasPBF {
		return false
	}

	// Skip continents (too large)
	if region.Parent == nil && isContinent(region.ID) {
		return false
	}

	return true
}

func isContinent(id string) bool {
	continents := []string{"africa", "asia", "europe", "north-america", "south-america", "oceania", "antarctica"}
	for _, continent := range continents {
		if id == continent {
			return true
		}
	}
	return false
}

func getCacheDir() string {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return ".vns-cache"
	}
	cacheDir := filepath.Join(homeDir, ".vns-cache")
	os.MkdirAll(cacheDir, 0755)
	return cacheDir
}

func loadRegionCache(filename string) (*RegionCache, error) {
	data, err := os.ReadFile(filename)
	if err != nil {
		return nil, err
	}

	var cache RegionCache
	if err := json.Unmarshal(data, &cache); err != nil {
		return nil, err
	}

	return &cache, nil
}

func saveRegionCache(filename string, regions []Region, etag string) error {
	cache := RegionCache{
		Regions:     regions,
		LastUpdated: time.Now(),
		ETag:        etag,
	}

	data, err := json.MarshalIndent(cache, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(filename, data, 0644)
}

// BubbleTea interface implementation
func (m model) Init() tea.Cmd {
	return tea.Batch(
		m.progressBar.Init(),
		m.stepProgressBar.Init(),
	)
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	// Always update progress bars first
	var cmds []tea.Cmd
	if m.processing {
		var cmd tea.Cmd
		var model tea.Model
		
		model, cmd = m.progressBar.Update(msg)
		if progressModel, ok := model.(progress.Model); ok {
			m.progressBar = progressModel
		}
		if cmd != nil {
			cmds = append(cmds, cmd)
		}
		
		model, cmd = m.stepProgressBar.Update(msg)
		if progressModel, ok := model.(progress.Model); ok {
			m.stepProgressBar = progressModel
		}
		if cmd != nil {
			cmds = append(cmds, cmd)
		}
	}

	if m.processing {
		// During processing, handle updates and allow quit
		switch msg := msg.(type) {
		case tea.KeyMsg:
			if msg.String() == "ctrl+c" || msg.String() == "q" {
				if m.processingCancel != nil {
					m.processingCancel()
				}
				m.quitting = true
				return m, tea.Quit
			}
		case nativeProcessingUpdateMsg:
			// Update the processing status and trigger redraw
			m.processingUpdate = ProcessingUpdate(msg)
			
			// Log what we receive for debugging
			if logFile, err := os.OpenFile("progress-debug.log", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644); err == nil {
				fmt.Fprintf(logFile, "UI-RECEIVE: Step=%s, Description='%s', Progress=%.1f%%\n", 
					m.processingUpdate.Step.Name, 
					m.processingUpdate.Step.Description,
					m.processingUpdate.Step.Progress)
				logFile.Close()
			}
			
			// Check if there's an error
			if m.processingUpdate.Error != nil {
				m.processing = false
				m.status = fmt.Sprintf("Error: %v", m.processingUpdate.Error)
				return m, tea.Batch(cmds...)
			}
			
			// Check if processing is complete
			if m.processingUpdate.OverallProgress >= 100 && m.processingUpdate.Status != "" {
				// Processing finished
				if m.processingChannel != nil {
					m.processingChannel = nil // Clear the channel
				}
				m.processing = false
				m.status = m.processingUpdate.Status
				return m, tea.Batch(cmds...)
			}
			
			// Continue listening for updates
			cmds = append(cmds, m.waitForProcessingUpdate(m.processingChannel))
			return m, tea.Batch(cmds...)
			
		case tickMsg:
			// Regular tick during processing - check for updates
			if m.processing && m.processingChannel != nil {
				cmds = append(cmds, 
					m.waitForProcessingUpdate(m.processingChannel),
					tea.Tick(100*time.Millisecond, func(time.Time) tea.Msg { return tickMsg{} }),
				)
			}
			return m, tea.Batch(cmds...)
		}
		return m, tea.Batch(cmds...)
	}

	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil
		
	case processRegionsMsg:
		// Start native processing with real-time UI updates
		m.processing = true
		m.processingRegions = msg.regions
		
		// Create a context for cancellation
		ctx, cancel := context.WithCancel(context.Background())
		m.processingContext = ctx
		m.processingCancel = cancel
		
		// Create a channel for progress updates
		progressCh := make(chan ProcessingUpdate, 100)
		m.processingChannel = progressCh
		
		// Start processing in background
		go func() {
			processSelectedRegionsWithUpdates(msg.regions, progressCh, ctx)
		}()
		
		// Start listening for progress updates with regular ticks
		return m, tea.Batch(
			m.waitForProcessingUpdate(progressCh),
			tea.Tick(100*time.Millisecond, func(time.Time) tea.Msg { return tickMsg{} }),
		)
		
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "q", "esc":
			if m.processing && m.processingCancel != nil {
				// Cancel ongoing processing
				m.processingCancel()
				m.processing = false
				m.status = "Processing cancelled by user"
			}
			m.quitting = true
			return m, tea.Quit

		case "/":
			m.filtering = !m.filtering
			if m.filtering {
				m.useTree = false
				m.status = "Type to filter regions, Enter to finish"
			} else {
				m.useTree = true
				m.filterText = ""
				m.status = "Tree view restored"
			}
			m.updateView()

		case "enter":
			if m.filtering {
				m.filtering = false
				m.useTree = true
				m.filterText = ""
				m.status = "Tree view restored"
				m.updateView()
			} else if m.useTree && len(m.flatTree) > 0 {
				// Toggle node expansion
				node := m.flatTree[m.cursor]
				if node.Region == nil && len(node.Children) > 0 {
					node.Expanded = !node.Expanded
					m.updateView()
				} else if node.Region != nil {
					// Process single region or select it
					selected := m.getSelectedRegions()
					if len(selected) > 0 {
						m.status = fmt.Sprintf("Starting processing of %d regions...", len(selected))
						return m, m.processRegionsCmd(selected)
					} else {
						m.status = "No regions selected"
					}
				}
			} else {
				// Process selected regions in flat mode
				selected := m.getSelectedRegions()
				if len(selected) > 0 {
					m.status = fmt.Sprintf("Starting processing of %d regions...", len(selected))
					return m, m.processRegionsCmd(selected)
				} else {
					m.status = "No regions selected"
				}
			}

		case "up", "k":
			if m.cursor > 0 {
				m.cursor--
			}

		case "down", "j":
			maxItems := len(m.flatTree)
			if m.cursor < maxItems-1 {
				m.cursor++
			}

		case " ":
			if !m.filtering && len(m.flatTree) > 0 {
				node := m.flatTree[m.cursor]
				if node.Region != nil {
					// Find original region index
					for i, region := range m.regions {
						if region.ID == node.Region.ID {
							m.selected[i] = !m.selected[i]
							break
						}
					}
					selectedCount := len(m.getSelectedRegions())
					m.status = fmt.Sprintf("Selected: %d regions", selectedCount)
				}
			}

		case "backspace":
			if m.filtering && len(m.filterText) > 0 {
				m.filterText = m.filterText[:len(m.filterText)-1]
				m.updateView()
			}

		default:
			if m.filtering && len(msg.String()) == 1 {
				m.filterText += msg.String()
				m.updateView()
			}
		}
	}

	return m, nil
}

func (m *model) buildTree() {
	// Create continent nodes
	continentMap := make(map[string]*TreeNode)
	countryMap := make(map[string]*TreeNode)

	for i, region := range m.regions {
		// Determine continent
		continent := getContinent(region.ID, region.Parent)
		
		// Create or get continent node
		if _, exists := continentMap[continent]; !exists {
			continentMap[continent] = &TreeNode{
				ID:       continent,
				Name:     getContinentDisplayName(continent),
				Children: []*TreeNode{},
				Expanded: false,
				Level:    0,
			}
		}
		continentNode := continentMap[continent]

		// Determine country/parent
		countryID := ""
		countryName := ""
		if region.Parent != nil {
			countryID = *region.Parent
			countryName = strings.Title(*region.Parent)
		} else {
			// Region is its own country
			countryID = region.ID
			countryName = region.Name
		}

		countryKey := continent + "/" + countryID
		
		// Create or get country node
		if _, exists := countryMap[countryKey]; !exists {
			countryNode := &TreeNode{
				ID:       countryID,
				Name:     getCountryFlag(countryID) + " " + countryName,
				Children: []*TreeNode{},
				Expanded: false,
				Level:    1,
			}
			countryMap[countryKey] = countryNode
			continentNode.Children = append(continentNode.Children, countryNode)
		}
		countryNode := countryMap[countryKey]

		// Create region node
		regionNode := &TreeNode{
			ID:       region.ID,
			Name:     region.Name,
			Children: []*TreeNode{},
			Region:   &m.regions[i],
			Expanded: false,
			Level:    2,
		}
		countryNode.Children = append(countryNode.Children, regionNode)
	}

	// Sort and build final tree
	m.tree = make([]*TreeNode, 0, len(continentMap))
	for _, continent := range continentMap {
		// Sort countries within continent
		sort.Slice(continent.Children, func(i, j int) bool {
			return continent.Children[i].Name < continent.Children[j].Name
		})
		// Sort regions within each country
		for _, country := range continent.Children {
			sort.Slice(country.Children, func(i, j int) bool {
				return country.Children[i].Name < country.Children[j].Name
			})
		}
		m.tree = append(m.tree, continent)
	}

	// Sort continents
	sort.Slice(m.tree, func(i, j int) bool {
		return getContinentOrder(m.tree[i].ID) < getContinentOrder(m.tree[j].ID)
	})
	
	// Auto-expand tree based on detected user location
	if m.userLocation.Detected {
		m.autoExpandForLocation()
	}
}

func (m *model) autoExpandForLocation() {
	// For US locations, we need special handling since US states are direct children of North America
	if strings.Contains(strings.ToLower(m.userLocation.Country), "united states") || 
	   strings.ToLower(m.userLocation.Country) == "us" {
		
		// Expand North America and US regional groupings
		for _, continent := range m.tree {
			if continent.ID == "north-america" {
				continent.Expanded = true
				
				// Also expand the US container (north-america) and its regional groupings
				for _, country := range continent.Children {
					if country.ID == "north-america" { // This is the US container
						country.Expanded = true
						
						// Expand US regional groupings (US South, US West, etc.)
						for _, usRegion := range country.Children {
							if strings.HasPrefix(usRegion.ID, "us-") {
								usRegion.Expanded = true
							}
						}
					}
				}
				break
			}
		}
		
		// Store the target state for later cursor positioning
		if m.userLocation.Region != "" {
			userState := m.mapUSStateToRegionID(m.userLocation.Region)
			if userState != "" {
				m.targetStateID = userState
			}
		}
		
		// Update status
		if m.userLocation.Region != "" {
			m.status = fmt.Sprintf("📍 Opened %s, United States regions for you", m.userLocation.Region)
		} else {
			m.status = fmt.Sprintf("📍 Opened United States regions for you")
		}
		return
	}
	
	// For other countries, use the original logic
	userContinent := m.mapCountryToContinent(m.userLocation.Country)
	userCountry := m.mapCountryToRegionID(m.userLocation.Country)
	
	if userContinent == "" || userCountry == "" {
		return // Could not map location
	}
	
	// Find and expand the user's continent
	for _, continent := range m.tree {
		if continent.ID == userContinent {
			continent.Expanded = true
			
			// Find and expand the user's country
			for _, country := range continent.Children {
				if country.ID == userCountry {
					country.Expanded = true
					break
				}
			}
			break
		}
	}
	
	// Update status
	if m.userLocation.Region != "" {
		m.status = fmt.Sprintf("📍 Opened %s, %s regions for you", m.userLocation.Region, m.userLocation.Country)
	} else {
		m.status = fmt.Sprintf("📍 Opened %s regions for you", m.userLocation.Country)
	}
}

func (m *model) mapCountryToContinent(country string) string {
	// Map country names to our continent IDs
	countryToContinent := map[string]string{
		"United States": "north-america",
		"USA":           "north-america",
		"Canada":        "north-america",
		"Mexico":        "north-america",
		"Germany":       "europe",
		"France":        "europe",
		"United Kingdom": "europe",
		"UK":            "europe",
		"Italy":         "europe",
		"Spain":         "europe",
		"Netherlands":   "europe",
		"Poland":        "europe",
		"Sweden":        "europe",
		"Norway":        "europe",
		"Denmark":       "europe",
		"Finland":       "europe",
		"Russia":        "europe",
		"China":         "asia",
		"Japan":         "asia",
		"India":         "asia",
		"Australia":     "oceania",
		"New Zealand":   "oceania",
		"Brazil":        "south-america",
		"Argentina":     "south-america",
		"Chile":         "south-america",
		"South Africa":  "africa",
		"Egypt":         "africa",
		"Morocco":       "africa",
	}
	
	if continent, exists := countryToContinent[country]; exists {
		return continent
	}
	
	// Fallback: try lowercase matching
	countryLower := strings.ToLower(country)
	for countryName, continent := range countryToContinent {
		if strings.ToLower(countryName) == countryLower {
			return continent
		}
	}
	
	return ""
}

func (m *model) mapCountryToRegionID(country string) string {
	// Map country names to our region IDs (used in tree structure)
	countryToRegionID := map[string]string{
		"United States": "us",
		"USA":           "us",
		"Canada":        "canada",
		"Mexico":        "mexico",
		"Germany":       "germany",
		"France":        "france",
		"United Kingdom": "united-kingdom",
		"UK":            "united-kingdom",
		"Italy":         "italy",
		"Spain":         "spain",
		"Netherlands":   "netherlands",
		"Poland":        "poland",
		"Sweden":        "sweden",
		"Norway":        "norway",
		"Denmark":       "denmark",
		"Finland":       "finland",
		"Russia":        "russia",
		"China":         "china",
		"Japan":         "japan",
		"India":         "india",
		"Australia":     "australia",
		"New Zealand":   "new-zealand",
		"Brazil":        "brazil",
		"Argentina":     "argentina",
		"Chile":         "chile",
		"South Africa":  "south-africa",
		"Egypt":         "egypt",
		"Morocco":       "morocco",
	}
	
	if regionID, exists := countryToRegionID[country]; exists {
		return regionID
	}
	
	// Fallback: try lowercase matching
	countryLower := strings.ToLower(country)
	for countryName, regionID := range countryToRegionID {
		if strings.ToLower(countryName) == countryLower {
			return regionID
		}
	}
	
	return ""
}

func (m *model) updateView() {
	if m.filtering || !m.useTree {
		m.updateFilter()
	} else {
		m.flattenTree()
	}

	// Position cursor on target state if requested (for auto-expansion)
	if m.targetStateID != "" {
		found := false
		for i, node := range m.flatTree {
			if node.Region != nil && node.Region.ID == m.targetStateID {
				m.cursor = i
				found = true
				break
			}
		}
		if found {
			m.status = fmt.Sprintf("📍 Positioned cursor on %s", m.targetStateID)
		} else {
			m.status = fmt.Sprintf("📍 Could not find %s in tree", m.targetStateID)
		}
		m.targetStateID = "" // Clear the target
	}

	// Reset cursor if out of bounds
	maxItems := len(m.flatTree)
	if !m.useTree {
		maxItems = len(m.regions) // Use filtered count when implemented
	}
	if m.cursor >= maxItems {
		m.cursor = maxItems - 1
	}
	if m.cursor < 0 {
		m.cursor = 0
	}
}

func (m *model) updateFilter() {
	// Simple flat filter for search mode
	m.flatTree = []*TreeNode{}
	
	filterLower := strings.ToLower(m.filterText)
	for i, region := range m.regions {
		if m.filterText == "" || 
			strings.Contains(strings.ToLower(region.Name), filterLower) ||
			strings.Contains(strings.ToLower(region.ID), filterLower) {
			
			node := &TreeNode{
				ID:     region.ID,
				Name:   region.Name,
				Region: &m.regions[i],
				Level:  0,
			}
			m.flatTree = append(m.flatTree, node)
		}
	}
}

func (m *model) flattenTree() {
	m.flatTree = []*TreeNode{}
	for _, continent := range m.tree {
		m.addNodeToFlat(continent)
	}
}

func (m *model) addNodeToFlat(node *TreeNode) {
	m.flatTree = append(m.flatTree, node)
	if node.Expanded {
		for _, child := range node.Children {
			m.addNodeToFlat(child)
		}
	}
}

func (m *model) mapUSStateToRegionID(state string) string {
	// Map US state names and abbreviations to region IDs used in Geofabrik (format: us/state)
	stateToRegionID := map[string]string{
		// Full state names
		"Alabama":        "us/alabama",
		"Alaska":         "us/alaska", 
		"Arizona":        "us/arizona",
		"Arkansas":       "us/arkansas",
		"California":     "us/california",
		"Colorado":       "us/colorado",
		"Connecticut":    "us/connecticut",
		"Delaware":       "us/delaware",
		"Florida":        "us/florida",
		"Georgia":        "us/georgia",
		"Hawaii":         "us/hawaii",
		"Idaho":          "us/idaho",
		"Illinois":       "us/illinois",
		"Indiana":        "us/indiana",
		"Iowa":           "us/iowa",
		"Kansas":         "us/kansas",
		"Kentucky":       "us/kentucky",
		"Louisiana":      "us/louisiana",
		"Maine":          "us/maine",
		"Maryland":       "us/maryland",
		"Massachusetts":  "us/massachusetts",
		"Michigan":       "us/michigan",
		"Minnesota":      "us/minnesota",
		"Mississippi":    "us/mississippi",
		"Missouri":       "us/missouri",
		"Montana":        "us/montana",
		"Nebraska":       "us/nebraska",
		"Nevada":         "us/nevada",
		"New Hampshire":  "us/new-hampshire",
		"New Jersey":     "us/new-jersey",
		"New Mexico":     "us/new-mexico",
		"New York":       "us/new-york",
		"North Carolina": "us/north-carolina",
		"North Dakota":   "us/north-dakota",
		"Ohio":           "us/ohio",
		"Oklahoma":       "us/oklahoma",
		"Oregon":         "us/oregon",
		"Pennsylvania":   "us/pennsylvania",
		"Rhode Island":   "us/rhode-island",
		"South Carolina": "us/south-carolina",
		"South Dakota":   "us/south-dakota",
		"Tennessee":      "us/tennessee",
		"Texas":          "us/texas",
		"Utah":           "us/utah",
		"Vermont":        "us/vermont",
		"Virginia":       "us/virginia",
		"Washington":     "us/washington",
		"West Virginia":  "us/west-virginia",
		"Wisconsin":      "us/wisconsin",
		"Wyoming":        "us/wyoming",
		// State abbreviations
		"AL": "us/alabama",
		"AK": "us/alaska",
		"AZ": "us/arizona", 
		"AR": "us/arkansas",
		"CA": "us/california",
		"CO": "us/colorado",
		"CT": "us/connecticut",
		"DE": "us/delaware",
		"FL": "us/florida",
		"GA": "us/georgia",
		"HI": "us/hawaii",
		"ID": "us/idaho",
		"IL": "us/illinois",
		"IN": "us/indiana",
		"IA": "us/iowa",
		"KS": "us/kansas",
		"KY": "us/kentucky",
		"LA": "us/louisiana",
		"ME": "us/maine",
		"MD": "us/maryland",
		"MA": "us/massachusetts",
		"MI": "us/michigan",
		"MN": "us/minnesota",
		"MS": "us/mississippi",
		"MO": "us/missouri",
		"MT": "us/montana",
		"NE": "us/nebraska",
		"NV": "us/nevada",
		"NH": "us/new-hampshire",
		"NJ": "us/new-jersey",
		"NM": "us/new-mexico",
		"NY": "us/new-york",
		"NC": "us/north-carolina",
		"ND": "us/north-dakota",
		"OH": "us/ohio",
		"OK": "us/oklahoma",
		"OR": "us/oregon",
		"PA": "us/pennsylvania",
		"RI": "us/rhode-island",
		"SC": "us/south-carolina",
		"SD": "us/south-dakota",
		"TN": "us/tennessee",
		"TX": "us/texas",
		"UT": "us/utah",
		"VT": "us/vermont",
		"VA": "us/virginia",
		"WA": "us/washington",
		"WV": "us/west-virginia",
		"WI": "us/wisconsin",
		"WY": "us/wyoming",
	}
	
	if regionID, exists := stateToRegionID[state]; exists {
		return regionID
	}
	
	// Try case-insensitive matching
	stateLower := strings.ToLower(state)
	for stateName, regionID := range stateToRegionID {
		if strings.ToLower(stateName) == stateLower {
			return regionID
		}
	}
	
	return ""
}

func (m model) View() string {
	if m.quitting {
		return "Goodbye! 👋\n"
	}

	// Title bar that spans the full width
	titleText := "🌍 ATAK VNS Global Region Selection"
	titleBar := titleStyle.Width(m.width).Align(lipgloss.Center).Render(titleText)
	s := titleBar + "\n\n"
	
	if m.processing {
		// Show native Go processing with real-time progress
		s += "🚀 Native Go Processing (No Docker Required!)\n\n"
		
		// Update progress bar widths based on terminal width
		overallProgressWidth := m.width - 30
		if overallProgressWidth < 40 {
			overallProgressWidth = 40
		}
		if overallProgressWidth > 80 {
			overallProgressWidth = 80
		}
		m.progressBar.Width = overallProgressWidth
		
		stepProgressWidth := overallProgressWidth - 10
		if stepProgressWidth < 30 {
			stepProgressWidth = 30
		}
		m.stepProgressBar.Width = stepProgressWidth
		
		// Overall progress using official Bubbles progress bar
		overallProgress := m.processingUpdate.OverallProgress / 100.0 // Convert to 0-1 range
		progressBarView := m.progressBar.ViewAs(overallProgress)
		s += fmt.Sprintf("Overall Progress: %s\n\n", progressBarView)
		
		// Current region and step info
		if m.processingUpdate.Region != "" {
			s += fmt.Sprintf("📍 Current Region: %s\n", selectedStyle.Render(m.processingUpdate.Region))
		}
		
		if m.processingUpdate.CurrentStep > 0 && m.processingUpdate.TotalSteps > 0 {
			s += fmt.Sprintf("🔄 Step %d/%d: %s\n", 
				m.processingUpdate.CurrentStep, 
				m.processingUpdate.TotalSteps,
				m.processingUpdate.Step.Description)
		}
		
		// Step-specific progress using official Bubbles progress bar
		if m.processingUpdate.Step.Progress > 0 {
			stepProgress := m.processingUpdate.Step.Progress / 100.0 // Convert to 0-1 range
			stepProgressBarView := m.stepProgressBar.ViewAs(stepProgress)
			s += fmt.Sprintf("   Step Progress: %s\n", stepProgressBarView)
		}
		
		s += "\n"
		
		// Status message
		if m.processingUpdate.Status != "" {
			s += fmt.Sprintf("📊 %s\n\n", m.processingUpdate.Status)
		}
		
		// Controls
		s += helpStyle.Render("Ctrl+C: Cancel processing") + "\n"
		
		return s
	}

	if m.filtering {
		s += fmt.Sprintf("Filter: %s█\n\n", m.filterText)
	}

	// Show tree/filtered items (use full terminal height)
	start := 0
	end := len(m.flatTree)
	
	// Calculate how much vertical space we have
	// Reserve space for: title (3 lines) + status (2 lines) + help (3 lines) + filter (1-2 lines)
	reservedLines := 10
	maxVisible := m.height - reservedLines
	if maxVisible < 10 {
		maxVisible = 10 // Minimum visible items
	}
	if maxVisible > 50 {
		maxVisible = 50 // Maximum for performance
	}

	if len(m.flatTree) > maxVisible {
		start = m.cursor - maxVisible/2
		if start < 0 {
			start = 0
		}
		end = start + maxVisible
		if end > len(m.flatTree) {
			end = len(m.flatTree)
			start = end - maxVisible
			if start < 0 {
				start = 0
			}
		}
	}

	for i := start; i < end; i++ {
		node := m.flatTree[i]

		cursor := "  "
		if i == m.cursor {
			cursor = cursorStyle.Render("→ ")
		}

		// Indent based on level
		indent := strings.Repeat("  ", node.Level)

		// Different icons based on node type
		icon := ""
		if node.Region == nil {
			// Container node (continent/country)
			if node.Expanded {
				icon = "📂 "
			} else {
				icon = "📁 "
			}
		} else {
			// Region node - show selection
			regionIdx := m.findRegionIndex(node.Region.ID)
			if regionIdx >= 0 && m.selected[regionIdx] {
				icon = selectedStyle.Render("☑ ")
			} else {
				icon = "☐ "
			}
		}

		line := fmt.Sprintf("%s%s%s%s", cursor, indent, icon, node.Name)
		if i == m.cursor {
			line = cursorStyle.Render(line)
		}

		s += line + "\n"
	}

	// Status line with item count
	statusLine := m.status
	if len(m.flatTree) > 0 {
		if len(m.flatTree) > maxVisible {
			statusLine += fmt.Sprintf(" | Showing %d-%d of %d items", start+1, end, len(m.flatTree))
		} else {
			statusLine += fmt.Sprintf(" | %d items", len(m.flatTree))
		}
	}
	s += "\n" + statusLine + "\n\n"

	// Help text
	if m.filtering {
		s += helpStyle.Render("Type to filter • Enter: finish filter • Esc: cancel")
	} else if m.useTree {
		selectedCount := len(m.getSelectedRegions())
		s += helpStyle.Render(fmt.Sprintf("Selected: %d | ↑/↓: navigate • Enter: expand/collapse • Space: select • /: search • q: quit", selectedCount))
		s += "\n" + helpStyle.Render(fmt.Sprintf("Terminal: %dx%d | Items per page: %d", m.width, m.height, maxVisible))
	} else {
		selectedCount := len(m.getSelectedRegions())
		s += helpStyle.Render(fmt.Sprintf("Selected: %d | ↑/↓: navigate • Space: select • Enter: process • /: tree view • q: quit", selectedCount))
		s += "\n" + helpStyle.Render(fmt.Sprintf("Terminal: %dx%d | Items per page: %d", m.width, m.height, maxVisible))
	}

	return s
}

func (m model) getSelectedRegions() []Region {
	var selected []Region
	for i, isSelected := range m.selected {
		if isSelected {
			selected = append(selected, m.regions[i])
		}
	}
	return selected
}

func (m model) waitForProcessingUpdate(ch chan ProcessingUpdate) tea.Cmd {
	return func() tea.Msg {
		if ch == nil {
			return nil
		}
		
		// Non-blocking check for updates
		select {
		case update, ok := <-ch:
			if !ok {
				// Channel closed, processing finished
				return nativeProcessingUpdateMsg(ProcessingUpdate{
					OverallProgress: 100,
					Status: "Processing completed",
				})
			}
			return nativeProcessingUpdateMsg(update)
		default:
			// No update available, return a tick to check again later
			return tickMsg{}
		}
	}
}

// Add tick message type for regular updates
type tickMsg struct{}

func (m model) findRegionIndex(regionID string) int {
	for i, region := range m.regions {
		if region.ID == regionID {
			return i
		}
	}
	return -1
}

func getContinent(regionID string, parent *string) string {
	// First, check if the parent itself IS a continent (direct continent children)
	if parent != nil {
		continents := []string{"africa", "asia", "europe", "north-america", "south-america", "oceania", "antarctica"}
		for _, continent := range continents {
			if *parent == continent {
				return *parent
			}
		}
	}
	
	// Map specific regions/countries to continents
	continentMap := map[string]string{
		// North America countries
		"us":        "north-america",
		"canada":    "north-america", 
		"mexico":    "north-america",
		"greenland": "north-america", // Greenland is geographically North America
		
		// Europe countries
		"germany":        "europe",
		"france":         "europe",
		"italy":          "europe",
		"spain":          "europe",
		"united-kingdom": "europe",
		"poland":         "europe",
		"netherlands":    "europe",
		"belgium":        "europe",
		"czech-republic": "europe",
		"austria":        "europe",
		"switzerland":    "europe",
		"sweden":         "europe",
		"norway":         "europe",
		"denmark":        "europe",
		"finland":        "europe",
		"portugal":       "europe",
		"greece":         "europe",
		"hungary":        "europe",
		"ireland":        "europe",
		"romania":        "europe",
		"bulgaria":       "europe",
		"croatia":        "europe",
		"serbia":         "europe",
		"slovenia":       "europe",
		"slovakia":       "europe",
		"estonia":        "europe",
		"latvia":         "europe",
		"lithuania":      "europe",
		"ukraine":        "europe",
		"belarus":        "europe",
		"moldova":        "europe",
		"russia":         "europe", // Primarily European (capital Moscow)
		"albania":        "europe",
		"bosnia-herzegovina": "europe",
		"montenegro":     "europe",
		"north-macedonia": "europe",
		"kosovo":         "europe",
		"luxembourg":     "europe",
		"malta":          "europe",
		"cyprus":         "europe",
		"iceland":        "europe",
		
		// Asia countries
		"china":       "asia",
		"japan":       "asia", 
		"india":       "asia",
		"indonesia":   "asia",
		"thailand":    "asia",
		"malaysia":    "asia",
		"singapore":   "asia",
		"south-korea": "asia",
		"philippines": "asia",
		"vietnam":     "asia",
		"myanmar":     "asia",
		"cambodia":    "asia",
		"laos":        "asia",
		"bangladesh":  "asia",
		"pakistan":    "asia",
		"sri-lanka":   "asia",
		"nepal":       "asia",
		"bhutan":      "asia",
		"afghanistan": "asia",
		"iran":        "asia",
		"iraq":        "asia",
		"syria":       "asia",
		"turkey":      "asia",
		"israel":      "asia",
		"palestine":   "asia",
		"jordan":      "asia",
		"lebanon":     "asia",
		"saudi-arabia": "asia",
		"yemen":       "asia",
		"oman":        "asia",
		"uae":         "asia",
		"qatar":       "asia",
		"bahrain":     "asia",
		"kuwait":      "asia",
		"georgia":     "asia",
		"armenia":     "asia",
		"azerbaijan":  "asia",
		"kazakhstan":  "asia",
		"uzbekistan":  "asia",
		"kyrgyzstan":  "asia",
		"tajikistan":  "asia",
		"turkmenistan": "asia",
		"mongolia":    "asia",
		"north-korea": "asia",
		"taiwan":      "asia",
		"hong-kong":   "asia",
		"macao":       "asia",
		
		// South America countries
		"brazil":    "south-america",
		"argentina": "south-america",
		"chile":     "south-america",
		"colombia":  "south-america",
		"peru":      "south-america",
		"venezuela": "south-america",
		"ecuador":   "south-america",
		"bolivia":   "south-america",
		"paraguay":  "south-america",
		"uruguay":   "south-america",
		"guyana":    "south-america",
		"suriname":  "south-america",
		"french-guiana": "south-america",
		
		// Africa countries  
		"south-africa": "africa",
		"egypt":        "africa",
		"morocco":      "africa",
		"kenya":        "africa",
		"nigeria":      "africa",
		"ethiopia":     "africa",
		"ghana":        "africa",
		"algeria":      "africa",
		"libya":        "africa",
		"tunisia":      "africa",
		"sudan":        "africa",
		"uganda":       "africa",
		"tanzania":     "africa",
		"madagascar":   "africa",
		"mozambique":   "africa",
		"angola":       "africa",
		"zimbabwe":     "africa",
		"botswana":     "africa",
		"namibia":      "africa",
		"zambia":       "africa",
		"malawi":       "africa",
		"congo":        "africa",
		"cameroon":     "africa",
		"ivory-coast":  "africa",
		"burkina-faso": "africa",
		"mali":         "africa",
		"niger":        "africa",
		"chad":         "africa",
		"senegal":      "africa",
		"guinea":       "africa",
		"benin":        "africa",
		"togo":         "africa",
		"liberia":      "africa",
		"sierra-leone": "africa",
		"gambia":       "africa",
		"mauritania":   "africa",
		"somalia":      "africa",
		"eritrea":      "africa",
		"djibouti":     "africa",
		"rwanda":       "africa",
		"burundi":      "africa",
		"central-african-republic": "africa",
		"equatorial-guinea": "africa",
		"gabon":        "africa",
		
		// Oceania countries
		"australia":     "oceania",
		"new-zealand":   "oceania",
		"papua-new-guinea": "oceania",
		"fiji":          "oceania",
		"new-caledonia": "oceania",
		"vanuatu":       "oceania",
		"samoa":         "oceania",
		"tonga":         "oceania",
		"solomon-islands": "oceania",
		"marshall-islands": "oceania",
		"micronesia":    "oceania",
		"palau":         "oceania",
		"nauru":         "oceania",
		"kiribati":      "oceania",
		"tuvalu":        "oceania",
		"cook-islands":  "oceania",
		"french-polynesia": "oceania",
	}
	
	// Check if parent country is mapped
	if parent != nil {
		if continent, exists := continentMap[*parent]; exists {
			return continent
		}
	}
	
	// Check if region itself is mapped
	if continent, exists := continentMap[regionID]; exists {
		return continent
	}
	
	// Special handling for US states
	if strings.HasPrefix(regionID, "us-") {
		return "north-america"
	}
	
	// Special handling for Canadian provinces  
	if parent != nil && *parent == "canada" {
		return "north-america"
	}
	
	return "other"
}

func getContinentDisplayName(continent string) string {
	names := map[string]string{
		"north-america": "🌎 North America",
		"south-america": "🌎 South America", 
		"europe":        "🌍 Europe",
		"asia":          "🌏 Asia",
		"africa":        "🌍 Africa",
		"oceania":       "🌏 Oceania",
		"other":         "🌐 Other",
	}
	if name, exists := names[continent]; exists {
		return name
	}
	return "🌐 " + strings.Title(continent)
}

func getContinentOrder(continent string) int {
	order := map[string]int{
		"north-america": 1,
		"europe":        2,
		"asia":          3,
		"oceania":       4,
		"south-america": 5,
		"africa":        6,
		"other":         7,
	}
	if order, exists := order[continent]; exists {
		return order
	}
	return 99
}

func getCountryFlag(countryID string) string {
	flags := map[string]string{
		// North America
		"us":     "🇺🇸",
		"canada": "🇨🇦",
		"mexico": "🇲🇽",
		
		// Europe
		"germany":        "🇩🇪",
		"france":         "🇫🇷", 
		"italy":          "🇮🇹",
		"spain":          "🇪🇸",
		"united-kingdom": "🇬🇧",
		"poland":         "🇵🇱",
		"netherlands":    "🇳🇱",
		"belgium":        "🇧🇪",
		"czech-republic": "🇨🇿",
		"austria":        "🇦🇹",
		"switzerland":    "🇨🇭",
		"sweden":         "🇸🇪",
		"norway":         "🇳🇴",
		"denmark":        "🇩🇰",
		"russia":         "🇷🇺",
		"finland":        "🇫🇮",
		"iceland":        "🇮🇸",
		
		// Asia
		"china":      "🇨🇳",
		"japan":      "🇯🇵",
		"india":      "🇮🇳",
		"indonesia":  "🇮🇩",
		"thailand":   "🇹🇭",
		"malaysia":   "🇲🇾",
		"singapore":  "🇸🇬",
		"south-korea": "🇰🇷",
		
		// South America
		"brazil":    "🇧🇷",
		"argentina": "🇦🇷",
		"chile":     "🇨🇱",
		"colombia":  "🇨🇴",
		
		// Africa
		"south-africa": "🇿🇦",
		"egypt":        "🇪🇬",
		"morocco":      "🇲🇦",
		"kenya":        "🇰🇪",
		
		// Oceania
		"australia":   "🇦🇺",
		"new-zealand": "🇳🇿",
	}
	
	if flag, exists := flags[countryID]; exists {
		return flag
	}
	return "🏳️"
}

func (m model) processRegionsCmd(regions []Region) tea.Cmd {
	return func() tea.Msg {
		return processRegionsMsg{regions: regions}
	}
}

type processRegionsMsg struct {
	regions []Region
}


type nativeProcessingStartedMsg struct {
	regions    []Region
	progressCh chan ProcessingUpdate
	ctx        context.Context
	cancel     context.CancelFunc
}

type nativeProcessingUpdateMsg ProcessingUpdate

func processRegionsDirectly(regionList string) {
	regionIDs := strings.Split(regionList, ",")
	
	fmt.Printf("🚀 Native Go Processing - %d regions: %s\n\n", len(regionIDs), regionList)
	
	// First fetch all available regions to match IDs to Region objects
	fmt.Println("📡 Loading region data...")
	regions, err := fetchRegions()
	if err != nil {
		fmt.Printf("❌ Error loading regions: %v\n", err)
		os.Exit(1)
	}
	
	// Find matching regions
	var selectedRegions []Region
	var notFound []string
	
	for _, regionID := range regionIDs {
		regionID = strings.TrimSpace(regionID)
		found := false
		
		for _, region := range regions {
			if region.ID == regionID {
				selectedRegions = append(selectedRegions, region)
				found = true
				break
			}
		}
		
		if !found {
			notFound = append(notFound, regionID)
		}
	}
	
	if len(notFound) > 0 {
		fmt.Printf("❌ Regions not found: %v\n", notFound)
		fmt.Printf("💡 Use './vns-interactive' to browse available regions\n")
		os.Exit(1)
	}
	
	fmt.Printf("✅ Found %d regions to process\n\n", len(selectedRegions))
	
	// Create output directory
	outputDir := "./output"
	if err := os.MkdirAll(outputDir, 0755); err != nil {
		fmt.Printf("❌ Failed to create output directory: %v\n", err)
		os.Exit(1)
	}
	
	// Process regions using native Go processing
	progressCh := make(chan ProcessingUpdate, 100)
	ctx := context.Background()
	
	success := 0
	var failed []string
	
	for i, region := range selectedRegions {
		fmt.Printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
		fmt.Printf("🌍 Processing region %d/%d: %s\n", i+1, len(selectedRegions), region.Name)
		fmt.Printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
		
		processor := NewRegionProcessor(region, outputDir, progressCh)
		
		// Listen for progress updates in a goroutine
		go func() {
			for update := range progressCh {
				if update.Error != nil {
					fmt.Printf("❌ Error: %v\n", update.Error)
					continue
				}
				
				if update.Step.Name != "" {
					fmt.Printf("⚡ Step %d/%d: %s", update.CurrentStep, update.TotalSteps, update.Step.Description)
					if update.Step.Progress > 0 {
						fmt.Printf(" (%.1f%%)", update.Step.Progress)
					}
					fmt.Printf("\n")
				}
				
				if update.Status != "" {
					fmt.Printf("📊 %s\n", update.Status)
				}
			}
		}()
		
		if err := processor.Process(ctx); err != nil {
			fmt.Printf("❌ %s failed: %v\n", region.Name, err)
			failed = append(failed, region.Name)
		} else {
			fmt.Printf("✅ %s completed successfully\n", region.Name)
			success++
		}
		
		fmt.Printf("\n")
	}
	
	printSummary(success, failed)
}

func processSelectedRegions(regions []Region) {
	fmt.Printf("\n🚀 Processing %d selected regions...\n\n", len(regions))
	
	success := 0
	var failed []string
	
	for i, region := range regions {
		fmt.Printf("Processing region %d/%d: %s\n", i+1, len(regions), region.Name)
		fmt.Printf("─────────────────────────────\n")
		
		cmd := exec.Command("./run.sh", region.ID)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		
		if err := cmd.Run(); err != nil {
			fmt.Printf("❌ %s failed\n", region.Name)
			failed = append(failed, region.Name)
		} else {
			fmt.Printf("✅ %s completed successfully\n", region.Name)
			success++
		}
		fmt.Println()
	}
	
	printSummary(success, failed)
}

func processSelectedRegionsInteractive(regions []Region) {
	fmt.Printf("🚀 Native Go Processing - %d selected regions\n\n", len(regions))
	
	// Create output directory
	outputDir := "./output"
	if err := os.MkdirAll(outputDir, 0755); err != nil {
		fmt.Printf("❌ Failed to create output directory: %v\n", err)
		os.Exit(1)
	}
	
	// Process regions using native Go processing
	progressCh := make(chan ProcessingUpdate, 100)
	ctx := context.Background()
	
	success := 0
	var failed []string
	
	for i, region := range regions {
		fmt.Printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
		fmt.Printf("🌍 Processing region %d/%d: %s\n", i+1, len(regions), region.Name)
		fmt.Printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
		
		processor := NewRegionProcessor(region, outputDir, progressCh)
		
		// Listen for progress updates in a goroutine
		go func() {
			for update := range progressCh {
				if update.Error != nil {
					fmt.Printf("❌ Error: %v\n", update.Error)
					continue
				}
				
				if update.Step.Name != "" {
					fmt.Printf("⚡ Step %d/%d: %s", update.CurrentStep, update.TotalSteps, update.Step.Description)
					if update.Step.Progress > 0 {
						fmt.Printf(" (%.1f%%)", update.Step.Progress)
					}
					fmt.Printf("\n")
				}
				
				if update.Status != "" {
					fmt.Printf("📊 %s\n", update.Status)
				}
			}
		}()
		
		if err := processor.Process(ctx); err != nil {
			fmt.Printf("❌ %s failed: %v\n", region.Name, err)
			failed = append(failed, region.Name)
		} else {
			fmt.Printf("✅ %s completed successfully\n", region.Name)
			success++
		}
		
		fmt.Printf("\n")
	}
	
	printSummary(success, failed)
}

func processSelectedRegionsWithUpdates(regions []Region, progressCh chan ProcessingUpdate, ctx context.Context) {
	defer close(progressCh)
	
	// Create output directory
	outputDir := "./output"
	if err := os.MkdirAll(outputDir, 0755); err != nil {
		progressCh <- ProcessingUpdate{
			Error: fmt.Errorf("failed to create output directory: %v", err),
		}
		return
	}
	
	success := 0
	var failed []string
	totalRegions := len(regions)
	
	for i, region := range regions {
		select {
		case <-ctx.Done():
			return
		default:
		}
		
		// Send region start update
		progressCh <- ProcessingUpdate{
			Region:          region.Name,
			OverallProgress: float64(i) / float64(totalRegions) * 100,
			Status:          fmt.Sprintf("Starting region %d/%d: %s", i+1, totalRegions, region.Name),
		}
		
		processor := NewRegionProcessor(region, outputDir, progressCh)
		
		if err := processor.Process(ctx); err != nil {
			failed = append(failed, region.Name)
			progressCh <- ProcessingUpdate{
				Region: region.Name,
				Error:  fmt.Errorf("region %s failed: %v", region.Name, err),
			}
		} else {
			success++
		}
		
		// Send region completion update
		progressCh <- ProcessingUpdate{
			Region:          region.Name,
			OverallProgress: float64(i+1) / float64(totalRegions) * 100,
			Status:          fmt.Sprintf("Completed region %d/%d: %s", i+1, totalRegions, region.Name),
		}
	}
	
	// Send final summary
	progressCh <- ProcessingUpdate{
		OverallProgress: 100.0,
		Status: fmt.Sprintf("Batch processing complete! ✅ %d succeeded, ❌ %d failed", success, len(failed)),
	}
}

func printSummary(success int, failed []string) {
	fmt.Printf("═══════════════════════════════\n")
	fmt.Printf("🎉 Batch Processing Complete!\n")
	fmt.Printf("✅ %d regions succeeded\n", success)
	if len(failed) > 0 {
		fmt.Printf("❌ %d regions failed:\n", len(failed))
		for _, name := range failed {
			fmt.Printf("   - %s\n", name)
		}
	}
	fmt.Printf("═══════════════════════════════\n")
}

func clearCache() {
	cacheDir := getCacheDir()
	if err := os.RemoveAll(cacheDir); err != nil {
		fmt.Printf("❌ Error clearing cache: %v\n", err)
		return
	}
	fmt.Println("✅ Cache cleared successfully")
}

func showCacheInfo() {
	cacheDir := getCacheDir()
	
	// Check if cache directory exists
	if _, err := os.Stat(cacheDir); os.IsNotExist(err) {
		fmt.Println("📊 No cache found")
		return
	}
	
	// Check regions cache
	regionsFile := filepath.Join(cacheDir, "regions.json")
	if cache, err := loadRegionCache(regionsFile); err == nil {
		fmt.Printf("📊 Cache Information:\n")
		fmt.Printf("   Cached regions: %d\n", len(cache.Regions))
		fmt.Printf("   Last updated: %s\n", cache.LastUpdated.Format("2006-01-02 15:04:05"))
		fmt.Printf("   Cache age: %s\n", time.Since(cache.LastUpdated).Round(time.Minute))
		fmt.Printf("   Cache location: %s\n", cacheDir)
	} else {
		fmt.Println("📊 Cache directory exists but no valid region data found")
	}
}

func detectUserLocation() UserLocation {
	// Try multiple geolocation services for reliability
	services := []string{
		"https://ipapi.co/json",
		"http://ip-api.com/json",
	}
	
	for _, serviceURL := range services {
		location := tryGeolocationService(serviceURL)
		if location.Detected {
			return location
		}
	}
	
	// Failed to detect location
	return UserLocation{Detected: false}
}

func tryGeolocationService(url string) UserLocation {
	client := &http.Client{Timeout: 3 * time.Second}
	
	resp, err := client.Get(url)
	if err != nil {
		return UserLocation{Detected: false}
	}
	defer resp.Body.Close()
	
	if resp.StatusCode != http.StatusOK {
		return UserLocation{Detected: false}
	}
	
	var location UserLocation
	if err := json.NewDecoder(resp.Body).Decode(&location); err != nil {
		return UserLocation{Detected: false}
	}
	
	// Validate we got useful data
	if location.Country == "" {
		return UserLocation{Detected: false}
	}
	
	location.Detected = true
	return location
}

func showHelp() {
	fmt.Println("🌍 ATAK VNS Offline Routing Generator v2.0")
	fmt.Println()
	fmt.Println("USAGE:")
	fmt.Println("  vns-interactive                    Launch interactive region selection")
	fmt.Println("  vns-interactive --process REGIONS  Process specific regions directly")
	fmt.Println("  vns-interactive --cache-info       Show cache information")
	fmt.Println("  vns-interactive --cache-clear      Clear all cached data")
	fmt.Println("  vns-interactive --help             Show this help")
	fmt.Println()
	fmt.Println("EXAMPLES:")
	fmt.Println("  vns-interactive")
	fmt.Println("  vns-interactive --process california,germany,france")
	fmt.Println("  vns-interactive --process \"new-york,north-carolina\"")
	fmt.Println()
	fmt.Println("INTERACTIVE CONTROLS:")
	fmt.Println("  ↑/↓ or k/j    Navigate regions")
	fmt.Println("  Space         Select/deselect region")
	fmt.Println("  Enter         Process selected regions")
	fmt.Println("  /             Filter regions by name")
	fmt.Println("  q or Esc      Quit")
	fmt.Println()
	fmt.Println("NOTE: Traditional CLI still works: ./run.sh florida")
}