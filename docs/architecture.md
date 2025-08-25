# VNS Technical Architecture

## Overview

This document explains the technical architecture of the ATAK VNS (Visual Navigation System) plugin and how our offline routing generator fits into the ecosystem.

**Current Version**: 1.1

## VNS Plugin Architecture

### Routing Engine Types

The VNS plugin supports two distinct routing approaches:

#### 1. Online Routing (Server-Based)
- **Engine**: OSRM (Open Source Routing Machine)
- **Infrastructure**: Private routing servers with OAuth2 authentication
- **Data**: Real-time traffic, road closures, live conditions
- **Connectivity**: Requires internet/cellular connection
- **Use Case**: Normal operations with connectivity

#### 2. Offline Routing (Local GraphHopper)
- **Engine**: GraphHopper v1.0 (embedded in ATAK device)
- **Infrastructure**: Local files on Android device storage
- **Data**: Pre-processed routing graphs (what this tool generates)
- **Connectivity**: Zero connectivity required
- **Use Case**: Emergency operations, remote deployments

### VNS Data Flow Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   ATAK Device   │    │  Routing Data   │    │  Data Sources   │
│                 │    │   Generator     │    │                 │
│  ┌───────────┐  │    │                 │    │ ┌─────────────┐ │
│  │    VNS    │  │    │ ┌─────────────┐ │    │ │ Geofabrik   │ │
│  │  Plugin   │◄─┼────┼─┤ Our Tool    │◄┼────┼─┤ API + OSM   │ │
│  │           │  │    │ │             │ │    │ │ Data        │ │
│  └───────────┘  │    │ └─────────────┘ │    │ └─────────────┘ │
│                 │    │                 │    │                 │
│  ┌───────────┐  │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│  │GraphHopper│  │    │ │ GraphHopper │◄┼────┼─┤ Dynamic URL │ │
│  │   v1.0    │  │    │ │   Builder   │ │    │ │ Resolution  │ │
│  │           │  │    │ │             │ │    │ │ (.poly/.kml)│ │
│  └───────────┘  │    │ └─────────────┘ │    │ └─────────────┘ │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## GraphHopper Integration

### Version Requirements

**Critical**: VNS requires GraphHopper v1.0 specifically. Newer versions are incompatible due to:
- Binary format changes in routing files
- API modifications in the routing engine
- Different memory layout for graph structures

### GraphHopper v1.0 Build Process

Our tool builds GraphHopper v1.0 from source because:
1. Pre-built binaries are not available for this legacy version
2. Custom configuration is needed for VNS compatibility
3. Memory optimization is required for large region processing

```dockerfile
# Build GraphHopper v1.0 from source (in Dockerfile)
RUN git clone --depth 1 --branch 1.0 https://github.com/graphhopper/graphhopper.git
RUN cd graphhopper && mvn -DskipTests=true clean install
```

### Memory Management

GraphHopper requires significant memory for processing:
- **Minimum**: 4GB heap space (configured automatically)
- **Recommended**: 8GB+ for large regions
- **Configuration**: `-Xmx4096m -Xms4096m` in JVM arguments

## VNS File Structure Requirements

### Expected Directory Layout

VNS expects a very specific directory structure on the Android device:

```
/storage/emulated/0/atak/tools/VNS/GH/
├── california/                   ← Region routing data folder
│   ├── california.kml            ← Boundary visualization (KML format)
│   ├── california.poly           ← Boundary definition (POLY format)
│   ├── california.timestamp      ← Region-specific timestamp
│   ├── timestamp                 ← Generic timestamp file
│   ├── edges                     ← GraphHopper binary files
│   ├── geometry                  ← Routing geometry data
│   ├── location_index            ← Spatial index
│   ├── nodes                     ← Node information
│   ├── nodes_ch_car              ← Car-specific contracted nodes
│   ├── properties                ← Graph properties and metadata
│   ├── shortcuts_car             ← Contraction hierarchy shortcuts
│   ├── string_index_keys         ← String index for names
│   └── string_index_vals         ← String values
├── texas/                        ← Additional regions
└── florida/                      ← VNS auto-detects all folders
```

### Critical File Requirements

1. **Boundary Files**: Both `.poly` and `.kml` must be present and match the region name
2. **Timestamps**: Both generic `timestamp` and region-specific `[region].timestamp` required
3. **GraphHopper Files**: All binary files must be present and valid
4. **Naming**: Folder name must match the region name exactly (lowercase, with dashes for spaces)

## Data Processing Pipeline

### Stage 1: Data Acquisition (API-Based)
```bash
# Query Geofabrik API for region information
wget -qO- "https://download.geofabrik.de/index-v1-nogeom.json"

# Extract URLs using jq for dynamic resolution
# - OSM PBF file URL
# - Boundary POLY file URL  
# - Boundary KML file URL

# Supports worldwide regions including:
# - Continental regions (north-america, europe, asia, etc.)
# - Country-level regions (us/california, europe/germany, etc.)
# - Special administrative regions
```

### Stage 2: Smart Caching and Download
```bash
# Check cache timestamps against remote files
# Download only if files are newer or missing
wget [OSM_URL] -O cache/region.osm.pbf
wget [POLY_URL] -O cache/region.poly
wget [KML_URL] -O cache/region.kml
```

### Stage 3: GraphHopper Processing
```bash
# Import OSM data into GraphHopper format
java -Xmx4096m -Xms4096m \
    -Ddw.graphhopper.datareader.file="../region-latest.osm.pbf" \
    -Ddw.graphhopper.graph.location="../region" \
    -jar graphhopper/web/target/graphhopper-web-1.0-SNAPSHOT.jar import \
    config-example.yml
```

### Stage 4: VNS Structure Creation
```bash
# Copy boundary files into graph folder
cp cache/region.poly region/
cp cache/region.kml region/

# Create timestamp files with current UTC time
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > region/timestamp
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > region/region.timestamp
```

### Stage 5: Packaging
```bash
# Create ZIP for device transfer
cd output && zip -r region.zip region/
```

## Docker Architecture

### Container Design

Our Docker container provides a controlled build environment:

```dockerfile
FROM openjdk:8-jdk-slim

# Install build dependencies
RUN apt-get update && apt-get install -y \
    maven git wget zip jq \
    --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

# Build GraphHopper v1.0 from source
RUN git clone --depth 1 --branch 1.0 https://github.com/graphhopper/graphhopper.git
RUN cd graphhopper && mvn -DskipTests=true clean install

# Copy processing scripts
COPY generate-data.sh /app/
```

### Volume Mapping

```bash
# Map local directories to container
-v "$(pwd)/output:/app/output"   # Generated data persistence
-v "$(pwd)/cache:/app/cache"     # Download cache persistence
```

This ensures generated data and cached downloads persist outside the container.

## Performance Characteristics

### Processing Times by Region Size

| Region | OSM File Size | Processing Time | Output Size | Memory Peak |
|--------|---------------|----------------|-------------|-------------|
| Delaware | ~20 MB | 30 seconds | ~22 MB | 2 GB |
| Rhode Island | ~12 MB | 25 seconds | ~8 MB | 2 GB |
| Malta | ~8 MB | 20 seconds | ~9 MB | 2 GB |
| Great Britain | ~1.9 GB | 15+ minutes | ~656 MB | 5+ GB |
| Germany | ~4.3 GB | 25+ minutes | ~1.3 GB | 6+ GB |

*Note: These are estimated values. Actual performance may vary based on system specifications and network conditions.*

### Optimization Strategies

1. **Memory Allocation**: Pre-allocate maximum heap space
2. **I/O Optimization**: Use SSD storage for temp files
3. **Smart Caching**: Reuse downloaded data when unchanged
4. **Resource Monitoring**: Monitor Docker container resource usage

## Integration with ATAK

### Region Discovery
The tool now includes built-in region discovery via `./list-regions.sh`:
- Automatically fetches current region availability from Geofabrik API
- Organizes regions by continent for easy navigation
- Provides exact commands to run for each region
- Supports worldwide regions including continental and country-level areas

### VNS Plugin Detection

The VNS plugin scans the `/atak/tools/VNS/GH/` directory on startup and:
1. Enumerates all subdirectories
2. Validates required files are present
3. Loads GraphHopper routing engines for each valid dataset
4. Makes routing data available in the VNS interface

### Routing Request Flow

```
User Request → VNS Plugin → GraphHopper Engine → Binary Files → Route Response
```

### Fallback Behavior

VNS routing priority:
1. **Primary**: Online OSRM server (if available)
2. **Fallback**: Local GraphHopper data (our generated files)
3. **Last Resort**: Basic waypoint navigation

## Troubleshooting Architecture Issues

### Common Integration Problems

1. **File Structure Mismatch**: VNS won't detect improperly structured folders
2. **Version Incompatibility**: GraphHopper v2.x+ files won't work with VNS
3. **Memory Issues**: Insufficient heap space causes import failures
4. **Permission Problems**: Android file system permissions can block access

### Validation Steps

```bash
# Verify GraphHopper files are valid
ls -la output/region/
# Should show all required files with reasonable sizes

# Check timestamp format
cat output/region/timestamp
# Should be ISO8601 format: 2025-01-15T10:30:00Z

# Validate ZIP integrity
unzip -t output/region.zip
# Should report "No errors detected"
```

## Security Considerations

### Data Sources
- All data sourced from OpenStreetMap via Geofabrik (trusted source)
- Dynamic URL resolution via official Geofabrik API
- No proprietary or restricted data included
- Public domain mapping data only

### Container Security
- Uses official OpenJDK base image
- Minimal package installation with cleanup
- No root privileges required for operation
- Isolated file system access via Docker volumes

### Device Security
- Routing data stored in standard ATAK directories
- No network access required for offline routing
- No sensitive information in generated files