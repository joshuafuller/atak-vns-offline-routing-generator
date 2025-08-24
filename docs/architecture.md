# VNS Technical Architecture

## Overview

This document explains the technical architecture of the ATAK VNS (Visual Navigation System) plugin and how our offline routing generator fits into the ecosystem.

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
│  │  Plugin   │◄─┼────┼─┤ Our Tool    │◄┼────┼─┤ OSM Data    │ │
│  │           │  │    │ │             │ │    │ │             │ │
│  └───────────┘  │    │ └─────────────┘ │    │ └─────────────┘ │
│                 │    │                 │    │                 │
│  ┌───────────┐  │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│  │GraphHopper│  │    │ │ GraphHopper │ │    │ │ Boundary    │ │
│  │   v1.0    │  │    │ │   Builder   │◄┼────┼─┤ Files       │ │
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
3. Memory optimization is required for large state processing

```dockerfile
# Build GraphHopper v1.0 from source (in Dockerfile)
RUN git clone https://github.com/graphhopper/graphhopper.git && \
    cd graphhopper && \
    git checkout 1.0 && \
    mvn clean install -DskipTests
```

### Memory Management

GraphHopper requires significant memory for processing:
- **Minimum**: 4GB heap space (configured automatically)
- **Recommended**: 8GB+ for large states
- **Configuration**: `-Xmx4096m -Xms4096m` in JVM arguments

## VNS File Structure Requirements

### Expected Directory Layout

VNS expects a very specific directory structure on the Android device:

```
/storage/emulated/0/atak/tools/VNS/GH/
├── california/                   ← State routing data folder
│   ├── california.kml            ← Boundary visualization (KML format)
│   ├── california.poly           ← Boundary definition (POLY format)
│   ├── california.timestamp      ← State-specific timestamp
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
├── texas/                        ← Additional states
└── florida/                      ← VNS auto-detects all folders
```

### Critical File Requirements

1. **Boundary Files**: Both `.poly` and `.kml` must be present and match the state name
2. **Timestamps**: Both generic `timestamp` and state-specific `[state].timestamp` required
3. **GraphHopper Files**: All binary files must be present and valid
4. **Naming**: Folder name must match the state name exactly (lowercase, with dashes for spaces)

## Data Processing Pipeline

### Stage 1: Data Acquisition
```bash
# Download from Geofabrik (HTTP)
wget http://download.geofabrik.de/north-america/us/california-latest.osm.pbf
wget http://download.geofabrik.de/north-america/us/california.poly
wget http://download.geofabrik.de/north-america/us/california.kml
```

### Stage 2: GraphHopper Processing
```bash
# Import OSM data into GraphHopper format
java -Xmx4096m -Xms4096m \
    -Ddw.graphhopper.datareader.file="../california-latest.osm.pbf" \
    -Ddw.graphhopper.graph.location="../california" \
    -jar web/target/graphhopper-web-1.0-SNAPSHOT.jar import config-example.yml
```

### Stage 3: VNS Structure Creation
```bash
# Move boundary files into graph folder
mv california.poly california/
mv california.kml california/

# Create timestamp files
echo "2025-01-15T10:30:00Z" > california/timestamp
echo "2025-01-15T10:30:00Z" > california/california.timestamp
```

### Stage 4: Packaging
```bash
# Create ZIP for device transfer
zip -r california.zip california/
```

## Docker Architecture

### Container Design

Our Docker container provides a controlled build environment:

```dockerfile
FROM openjdk:8-jdk-slim

# Install build dependencies
RUN apt-get update && apt-get install -y \
    maven git wget zip unzip

# Build GraphHopper v1.0 from source
RUN git clone https://github.com/graphhopper/graphhopper.git && \
    cd graphhopper && \
    git checkout 1.0 && \
    mvn clean install -DskipTests

# Copy processing scripts
COPY generate-data.sh /app/
```

### Volume Mapping

```bash
# Map local output directory to container
-v "$(pwd)/output:/app/output"
```

This ensures generated data persists outside the container.

## Performance Characteristics

### Processing Times by State Size

| State | OSM File Size | Processing Time | Output Size | Memory Peak |
|-------|---------------|----------------|-------------|-------------|
| Delaware | ~15 MB | 30 seconds | ~10 MB | 2 GB |
| Tennessee | ~85 MB | 3 minutes | ~80 MB | 3 GB |
| California | ~400 MB | 7 minutes | ~260 MB | 4+ GB |
| Texas | ~500 MB | 10+ minutes | ~300 MB | 5+ GB |

### Optimization Strategies

1. **Memory Allocation**: Pre-allocate maximum heap space
2. **I/O Optimization**: Use SSD storage for temp files
3. **Batch Processing**: Process multiple small states together
4. **Resource Monitoring**: Monitor Docker container resource usage

## Integration with ATAK

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
ls -la output/california/
# Should show all required files with reasonable sizes

# Check timestamp format
cat output/california/timestamp
# Should be ISO8601 format: 2025-01-15T10:30:00Z

# Validate ZIP integrity
unzip -t output/california.zip
# Should report "No errors detected"
```

## Security Considerations

### Data Sources
- All data sourced from OpenStreetMap via Geofabrik (trusted source)
- No proprietary or restricted data included
- Public domain mapping data only

### Container Security
- Uses official OpenJDK base image
- No root privileges required for operation
- Isolated file system access via Docker volumes

### Device Security
- Routing data stored in standard ATAK directories
- No network access required for offline routing
- No sensitive information in generated files