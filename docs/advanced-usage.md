# Advanced Usage Guide

This document covers advanced usage patterns, customization options, and technical details for power users of the ATAK VNS Offline Routing Generator.

## Docker Image Options

### Pre-built Images (Default)
The tool uses pre-built images from GitHub Container Registry by default:
- **Faster startup** - No build time required  
- **Always up-to-date** - Automatically pulls versioned images (v1.1)
- **No dependencies** - No need for build tools locally

### Local Build
Force local Docker build if needed:
```bash
USE_PREBUILT=false ./run.sh great-britain
```

## Custom Docker Build

### Rebuild with Latest Changes
```bash
# Rebuild Docker image with latest changes
docker build -t vns-data-generator:latest .

# Run with custom memory settings
docker run --rm -v "$(pwd)/output:/app/output" \
    -e JAVA_OPTS="-Xmx8192m -Xms8192m" \
    vns-data-generator:latest ./generate-data.sh california
```

### Memory Optimization
For large regions, you can customize memory allocation:
```bash
# 8GB heap for very large regions
docker run --rm -v "$(pwd)/output:/app/output" \
    -e JAVA_OPTS="-Xmx8192m -Xms8192m" \
    vns-data-generator:latest ./generate-data.sh california
```

## Batch Processing

### Multiple Regions
Process multiple regions in sequence:
```bash
# Process multiple regions
for region in north-america/us/california europe/germany; do
    ./run.sh $region
done
```

### Custom Region Lists
Create a file with your regions and batch process:
```bash
# Create regions.txt
echo "california" > regions.txt
echo "texas" >> regions.txt  
echo "florida" >> regions.txt

# Process all
while read region; do
    ./run.sh $region
done < regions.txt
```

## Debug Mode

### Verbose Output
Run with verbose output for troubleshooting:
```bash
# Run with verbose output
docker run --rm -v "$(pwd)/output:/app/output" \
    vns-data-generator:latest bash -x ./generate-data.sh california
```

### Container Inspection
Inspect the container during processing:
```bash
# Run interactively
docker run -it --rm -v "$(pwd)/output:/app/output" \
    vns-data-generator:latest bash

# Then manually run processing
./generate-data.sh california
```

## Data Management

### Generated File Details
Understanding what gets created:

```
[region-name]/
├── [region-name].kml          ← KML boundary file for visualization
├── [region-name].poly         ← POLY boundary file (Osmosis format)
├── [region-name].timestamp    ← Region-named timestamp
├── timestamp                 ← Generic timestamp file
├── edges                     ← GraphHopper routing edge data
├── geometry                  ← Binary routing geometry files
├── location_index            ← Spatial location index
├── nodes                     ← Node information
├── nodes_ch_car              ← Car-specific contracted nodes
├── properties                ← Graph properties and metadata
├── shortcuts_car             ← Contraction hierarchy shortcuts for cars
├── string_index_keys         ← String index for road/place names
└── string_index_vals         ← String values for names
```

### Cache Management
The tool caches downloaded data to speed up regeneration:

```bash
# View cached data
ls cache/

# Clear cache for specific region
rm cache/california.*

# Clear all cache
rm -rf cache/*
```

### Output Organization
```bash
# View all generated data
ls output/

# Check region folder size
du -sh output/california/

# List all ZIP files
ls -lh output/*.zip
```

## Official VNS Process (What This Tool Automates)

According to VNS documentation, manually creating offline routing data requires:

### 1. Data Collection
- Download `.osm.pbf` files from Geofabrik
- Obtain matching `.poly` boundary files
- Generate `.kml` files from `.poly` files using border utilities
- Create `.timestamp` files with ISO8601 timestamps

### 2. Processing Environment Setup
- Install Docker and Java
- Build custom GraphHopper v1.0 Docker container
- Configure memory settings and build parameters
- Handle version compatibility issues

### 3. GraphHopper Processing
- Run `gh_dataprep` Docker container
- Execute GraphHopper import with correct config
- Generate `.ghz` region files (server format)
- Create proper directory structures

### 4. File Organization
- Structure data for VNS consumption
- Include all required metadata files
- Ensure proper naming conventions

**This tool automates all these steps** into a single command, ensuring consistency and eliminating manual configuration errors.

## Performance Tuning

### System Requirements by Region Size

| Region Type | RAM Required | Disk Space | Processing Time |
|-------------|-------------|------------|----------------|
| Small (Malta) | 2GB | 100MB | 10-30 seconds |
| Medium (Great Britain) | 4GB | 500MB | 5-10 minutes |
| Large (Germany) | 6GB | 1GB | 10-20 minutes |
| Very Large (California) | 8GB+ | 2GB+ | 20-30+ minutes |

### Optimization Tips
1. **Close other applications** during large region processing
2. **Use SSD storage** for faster I/O operations
3. **Process overnight** for very large regions
4. **Monitor system resources** with `top` or Task Manager

## Integration with VNS

### Data Freshness
This tool creates routing data from the latest OpenStreetMap information (updated weekly by Geofabrik). However, offline routing won't know about:
- Recent road closures (accidents, construction, emergencies)  
- Current traffic conditions
- Temporary restrictions or detours

### Best Practice Usage
Use both online and offline routing together:
- **Online routing** (Google Maps API) - Real-time conditions when you have internet
- **Offline routing** (this tool) - Backup navigation when connectivity fails

### Device Storage Considerations
Plan device storage based on your needs:
- Small regions: 5-50MB each
- Medium regions: 100-500MB each  
- Large regions: 500MB-1GB+ each

Multiple regions can be installed simultaneously - VNS will detect all folders in the GH directory.

## Troubleshooting Advanced Issues

### Memory Issues with Large Regions
```bash
# Check available system memory
free -h  # Linux
vm_stat # macOS

# Force garbage collection (if needed)
docker run --rm -v "$(pwd)/output:/app/output" \
    -e JAVA_OPTS="-Xmx6144m -XX:+UseG1GC -XX:+UnlockExperimentalVMOptions" \
    vns-data-generator:latest ./generate-data.sh california
```

### Network Issues
```bash
# Test Geofabrik connectivity
curl -I https://download.geofabrik.de/

# Download with resume support
wget -c https://download.geofabrik.de/north-america/us/california-latest.osm.pbf
```

### Container Issues
```bash
# Clean up Docker system
docker system prune

# Remove all VNS images and rebuild
docker rmi $(docker images | grep vns-data-generator | awk '{print $3}')
docker build -t vns-data-generator:latest .
```

## Contributing to Development

### Local Development Setup
```bash
# Clone repository
git clone https://github.com/joshuafuller/atak-vns-offline-routing-generator
cd atak-vns-offline-routing-generator

# Test with small region
./run.sh delaware

# Make changes and test
# ... edit files ...
docker build -t vns-data-generator:dev .
```

### Testing Changes
1. Always test with Delaware first (small and fast)
2. Test at least one medium region (Great Britain recommended)
3. Verify file structure matches VNS requirements
4. Test ZIP file extraction and folder structure

### Code Organization
```
project/
├── README.md              ← Main documentation
├── Dockerfile             ← Container definition
├── run.sh                 ← Main entry point
├── generate-data.sh       ← Core processing logic
├── list-regions.sh        ← Region listing utility
├── docs/                  ← Documentation
├── output/               ← Generated data (created after first run)
└── cache/                ← Downloaded OSM data cache
```