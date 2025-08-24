# 🗺️ ATAK VNS Offline Routing Generator v2.0

**Automated generation of VNS-compatible offline routing files for any global region**  
🆕 **NEW**: Interactive global region selection with 250+ regions worldwide!

[![Docker](https://img.shields.io/badge/Docker-Required-2496ED?style=flat-square&logo=docker)](https://www.docker.com/)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)
[![ATAK](https://img.shields.io/badge/ATAK-VNS%20Plugin-orange?style=flat-square)](https://tak.gov/)

## 📋 Overview

This tool automates the creation of VNS-compatible offline routing files for **any global region**, transforming a complex multi-step manual process into a simple interactive selection menu. 

The VNS (Visual Navigation System) plugin for ATAK requires specific GraphHopper v1.0 routing data with precise file structures. This generator handles all the complexity:

### 🔥 Critical for Emergency Operations
**Perfect for wildfire operations, search & rescue, and remote deployments where internet connectivity is unavailable or unreliable.** While VNS can use Google Maps API for real-time traffic and road closures, this offline data ensures navigation capabilities when teams are beyond cellular coverage.

**Key Benefits:**
- **Zero connectivity required** - Works completely offline
- **Reliable in emergencies** - No dependence on cell towers or internet
- **Pre-positioned data** - Deploy with confidence knowing routing will work
- **Complements online routing** - Use alongside Google API when connectivity allows

- ✅ **Global coverage**: 250+ regions across all continents
- ✅ **Interactive selection**: Beautiful terminal UI for region discovery
- ✅ **Smart caching**: Avoids re-downloading unchanged files  
- ✅ **Multi-region processing**: Select and process multiple regions at once
- ✅ **Zero dependencies**: Single binary, no Python/pip/venv required
- ✅ Downloads latest OSM data from Geofabrik
- ✅ Processes data with GraphHopper v1.0 (VNS-compatible version)
- ✅ Creates proper VNS folder structure and files
- ✅ Generates ZIP files for easy device transfer

## 🚀 Quick Start

### Prerequisites
- **Docker** installed and running on your system ([Download Docker](https://www.docker.com/get-started))

### NEW: Interactive Global Selection (v2.0)
```bash
# Download the interactive binary for your platform
# Linux:
curl -L https://github.com/joshuafuller/atak-vns-offline-routing-generator/releases/latest/download/vns-interactive -o vns-interactive
chmod +x vns-interactive

# Launch interactive region selection
./vns-interactive
```

**Interactive Features:**
- 🌍 Browse 250+ global regions (Europe, Canada, Australia, Asia, etc.)
- 🔍 Search and filter regions by name
- ☑️ Multi-select regions with spacebar
- ⚡ Smart caching prevents re-downloading large files
- 🚀 Process multiple regions in one batch

### Traditional CLI (Still Available)
```bash
# Clone or download this repository
git clone https://github.com/joshuafuller/atak-vns-offline-routing-generator
cd atak-vns-offline-routing-generator

# Make scripts executable (macOS/Linux)
chmod +x run.sh

# Generate routing data for any region:
./run.sh california          # US States
./run.sh germany            # European Countries  
./run.sh ontario            # Canadian Provinces
./run.sh new-south-wales    # Australian States

# Or use the interactive binary directly:
./vns-interactive --process california,germany,france
```

### Processing Times (Approximate)
| State Size | Example | Time | Output Size |
|------------|---------|------|-------------|
| Small | Delaware | ~30 seconds | ~10 MB |
| Medium | Tennessee | ~3 minutes | ~80 MB |
| Large | California | ~7 minutes | ~260 MB |

## 📱 Installing on Your Android Device

After generation completes, you'll have:
- 📁 **Folder**: `./output/[state-name]/` - Raw routing data
- 📦 **ZIP file**: `./output/[state-name].zip` - Compressed for transfer

### Installation Steps:
1. **Transfer** the ZIP file to your Android device
2. **Extract** the ZIP to get the state folder
3. **Copy** the entire folder to your device at:
   ```
   /storage/emulated/0/atak/tools/VNS/GH/[state-name]/
   ```
   OR
   ```
   Internal Storage/atak/tools/VNS/GH/[state-name]/
   ```

### Required Folder Structure on Device:
```
Internal Storage/
└── atak/
    └── tools/
        └── VNS/
            └── GH/
                ├── california/      ← Your generated routing data
                ├── texas/           ← Additional states
                └── florida/         ← VNS detects all folders here
```

## 🛠️ How It Works

### VNS Routing Architecture Overview
The ATAK VNS (Vehicle Navigation System) supports two types of routing:

1. **🌐 Online Routing** - Uses private routing servers (OSRM) with real-time data
2. **📱 Offline Routing** - Uses local GraphHopper files for zero-connectivity operations

**This tool generates the offline routing data** that gets installed directly on ATAK devices.

### The Complete VNS Ecosystem
According to official VNS documentation, a full routing system includes:

**Server Components** (Not covered by this tool):
- Private routing server using OSRM (Open Source Routing Machine)
- OAuth2 authentication and user management
- API endpoints for real-time routing requests
- Docker Compose orchestration

**Client Components** (Generated by this tool):
- GraphHopper v1.0 routing data files
- Regional boundary files (.poly, .kml)
- Timestamp metadata for data freshness
- VNS-compatible folder structure

### Our Tool's Process
This generator automates the "offline routing data" portion:

1. **Download**: Fetches latest OSM data (.osm.pbf), boundary files (.poly, .kml) from Geofabrik
2. **Process**: Runs GraphHopper v1.0 import with optimized memory settings (4GB heap)
3. **Structure**: Creates VNS-compatible folder structure with all required files
4. **Package**: Generates both folder and ZIP file outputs

### Why Offline Routing Matters
- **Emergency Operations**: Wildfire, search & rescue, disaster response
- **Remote Deployments**: Beyond cellular coverage areas
- **Mission Critical**: No dependency on external infrastructure
- **Redundancy**: Backup when private routing servers are unavailable

### Generated Files:
```
[state-name]/
├── [state-name].kml          ← KML boundary file
├── [state-name].poly         ← POLY boundary file  
├── [state-name].timestamp    ← State-named timestamp
├── timestamp                 ← Generic timestamp
├── edges                     ← GraphHopper routing data
├── geometry                  ← Binary routing files
├── location_index            ← Location index data
├── nodes                     ← Node data
├── nodes_ch_car              ← Car-specific node data
├── properties                ← Graph properties
├── shortcuts_car             ← Car routing shortcuts
├── string_index_keys         ← String index keys
└── string_index_vals         ← String index values
```

## 🏗️ Project Structure

```
atak-vns-offline-routing-generator/
├── README.md              ← This file
├── Dockerfile             ← Docker container definition
├── run.sh                 ← Main entry point script
├── generate-data.sh       ← Core data processing script
└── output/                ← Generated routing data (created after first run)
    ├── [state-name]/      ← VNS-ready folder
    └── [state-name].zip   ← Compressed archive
```

## ⚙️ Technical Details

### Dependencies (Handled by Docker):
- **OpenJDK 8** - Required by GraphHopper v1.0
- **Maven 3** - For building GraphHopper from source
- **GraphHopper v1.0** - Specific version compatible with VNS
- **wget** - For downloading OSM data
- **zip** - For creating compressed archives

### Memory Requirements:
- **Minimum**: 4GB RAM (configured automatically)
- **Recommended**: 8GB+ RAM for large states like California or Texas

### Supported States:
All 50 U.S. states plus DC. Use lowercase names with dashes for spaces:
- `california`, `texas`, `florida`, `new-york`, `north-carolina`, etc.

### Data Freshness:
This tool generates routing data from the latest available OpenStreetMap data via Geofabrik (typically updated weekly). For real-time conditions like:
- **Road closures** (accidents, construction, emergencies)  
- **Live traffic conditions**
- **Temporary restrictions**

VNS can be configured to use Google Maps API when internet is available. The offline data generated by this tool serves as the essential fallback for when connectivity is lost.

### Official VNS Process (What This Tool Automates):
According to VNS documentation, manually creating offline routing data requires:

1. **Data Collection**:
   - Download `.osm.pbf` files from Geofabrik
   - Obtain matching `.poly` boundary files
   - Generate `.kml` files from `.poly` files using border utilities
   - Create `.timestamp` files with ISO8601 timestamps

2. **Processing Environment Setup**:
   - Install Docker and Java
   - Build custom GraphHopper v1.0 Docker container
   - Configure memory settings and build parameters
   - Handle version compatibility issues

3. **GraphHopper Processing**:
   - Run `gh_dataprep` Docker container
   - Execute GraphHopper import with correct config
   - Generate `.ghz` region files (server format)
   - Create proper directory structures

4. **File Organization**:
   - Structure data for VNS consumption
   - Include all required metadata files
   - Ensure proper naming conventions

**This tool automates all these steps** into a single command, ensuring consistency and eliminating manual configuration errors.

## 🔧 Advanced Usage

### Custom Docker Build:
```bash
# Rebuild Docker image with latest changes
docker build -t vns-data-generator:1.0 .

# Run with custom memory settings
docker run --rm -v "$(pwd)/output:/app/output" \
    -e JAVA_OPTS="-Xmx8192m -Xms8192m" \
    vns-data-generator:1.0 ./generate-data.sh california
```

### Batch Processing Multiple States:
```bash
# Process multiple states
for state in california texas florida; do
    ./run.sh $state
done
```

## 🐛 Troubleshooting

### Common Issues:

**"Docker not found"**
- Install Docker and ensure it's running
- On Windows: Restart after Docker installation

**"Permission denied"**
- On macOS/Linux: Run `chmod +x run.sh`
- On Windows: Use PowerShell or Git Bash

**"Out of memory errors"**
- Large states need significant RAM
- Close other applications
- Consider processing smaller states first

**"Network timeouts"**
- Check internet connection
- Geofabrik servers may be busy - retry later

**"VNS not detecting routing data"**
- Ensure folder is copied to exact path: `/storage/emulated/0/atak/tools/VNS/GH/[state-name]/`
- Check that all required files are present (see Generated Files section)
- Restart ATAK after copying new routing data

### Debug Mode:
```bash
# Run with verbose output
docker run --rm -v "$(pwd)/output:/app/output" \
    vns-data-generator:1.0 bash -x ./generate-data.sh california
```

## 🆕 What's New in v2.0

### Global Region Support
- **250+ regions** worldwide vs. 50+ US states in v1.0
- **All continents**: Europe, Asia, North America, South America, Africa, Oceania  
- **Countries**: Germany, France, Canada, Australia, Japan, etc.
- **Sub-regions**: German states, Canadian provinces, Australian states, etc.

### Interactive Terminal UI
- **Beautiful interface** built with Go + BubbleTea
- **Search and filter** regions by typing
- **Multi-selection** with spacebar and arrow keys
- **Real-time feedback** and progress indication

### Smart Caching System
- **Automatic file caching** prevents re-downloading unchanged files
- **HTTP header checking** (ETag, Last-Modified) for change detection
- **Huge bandwidth savings** - Florida (600MB) downloads once, reuses cached version
- **Cache management** tools (`--cache-info`, `--cache-clear`)

### Zero Dependencies
- **Single binary** per platform (Linux, Windows, macOS)
- **No Python/pip/venv** setup required
- **No external dependencies** beyond Docker for processing
- **Easy distribution** via GitHub releases

### Backward Compatibility
- **Existing CLI works unchanged**: `./run.sh california`
- **Same output format** and file structure as v1.0
- **Same VNS compatibility** and installation process

### Usage Examples
```bash
# Interactive mode
./vns-interactive

# Direct processing
./vns-interactive --process germany,france,netherlands

# Traditional CLI (unchanged)
./run.sh california
```

---

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🤝 Contributing

Contributions welcome! Please feel free to submit issues and pull requests.

### Development Setup:
1. Fork the repository
2. Make your changes
3. Test with a small state (Delaware recommended)
4. Submit a pull request

## 📞 Support

- **Issues**: Open a GitHub issue
- **ATAK/VNS Questions**: Consult official ATAK documentation
- **GraphHopper Questions**: See [GraphHopper documentation](https://www.graphhopper.com/)

## ⚠️ Disclaimer

This tool is for legitimate navigation and mapping purposes only. Users are responsible for complying with all applicable laws and terms of service for the data sources used.

---

**Made with ❤️ for the ATAK community**