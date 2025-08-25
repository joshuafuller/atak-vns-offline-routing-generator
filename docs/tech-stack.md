# Technology Stack

**Current Version**: 1.1

## Core Technologies

### Container Runtime
- **Docker** - Containerization platform
  - Version: Latest stable
  - Purpose: Consistent build environment across platforms
  - Benefits: Eliminates "works on my machine" issues

### Programming Languages
- **Bash** - Shell scripting
  - Primary automation language
  - Used for: Data pipeline orchestration, file management
  - Scripts: `run.sh`, `generate-data.sh`, `list-regions.sh`

- **Java 8** - GraphHopper runtime
  - Required by GraphHopper v1.0
  - JVM Arguments: `-Xmx4096m -Xms4096m` (4GB heap)
  - Compatibility: Newer Java versions not supported by GraphHopper v1.0

### Build Tools
- **Maven 3** - Java build automation
  - Purpose: Build GraphHopper v1.0 from source
  - Configuration: `pom.xml` in GraphHopper repository
  - Commands: `mvn clean install -DskipTests`

- **Git** - Version control and source retrieval
  - Purpose: Clone GraphHopper v1.0 source code
  - Repository: `https://github.com/graphhopper/graphhopper.git`
  - Branch: `1.0` (specific version tag)

### Routing Engine
- **GraphHopper v1.0** - Open source routing engine
  - Language: Java
  - Algorithm: Contraction Hierarchies (CH) for fast routing
  - Format: Binary graph files optimized for car routing
  - Compatibility: VNS requires exactly v1.0 (newer versions incompatible)

### Data Sources
- **OpenStreetMap (OSM)** - Open source map data
  - Format: Protocol Buffers Binary (`.osm.pbf`)
  - Source: Geofabrik extracts
  - Update Frequency: Weekly
  - Coverage: Global coverage via Geofabrik API

- **Geofabrik** - OSM data distribution service
  - API: `https://download.geofabrik.de/index-v1-nogeom.json`
  - Files: `.osm.pbf`, `.poly`, `.kml`
  - Reliability: Industry standard for OSM data

### File Formats

#### Input Formats
- **PBF (Protocol Buffer Binary)** - Compressed OSM data
  - Extension: `.osm.pbf`
  - Size: Highly compressed (regions vary from 8MB to 4.3GB)
  - Content: Roads, POIs, geographic features

- **POLY** - Polygon boundary definition
  - Extension: `.poly`
  - Format: Plain text coordinate list
  - Purpose: Define state/region boundaries

- **KML (Keyhole Markup Language)** - Geographic visualization
  - Extension: `.kml`
  - Format: XML-based
  - Purpose: Visual boundary representation

#### Output Formats
- **Binary Graph Files** - GraphHopper proprietary format
  - Files: `edges`, `geometry`, `nodes`, `shortcuts_car`, etc.
  - Purpose: Optimized routing calculations
  - Size: Compressed spatial data structures

### System Tools
- **wget** - HTTP file downloader
  - Purpose: Download OSM data from Geofabrik
  - Flags: `-q --show-progress` for clean output
  - Timeout: Default network timeouts

- **curl** - HTTP client for API requests
  - Purpose: Fetch Geofabrik region index for discovery
  - Used by: `list-regions.sh` for region enumeration
  - Fallback: Used when wget is not available

- **zip/unzip** - Archive compression
  - Purpose: Package routing data for device transfer
  - Algorithm: Standard ZIP compression
  - Benefits: Universal compatibility, good compression ratio

- **jq** - JSON processor
  - Purpose: Parse Geofabrik API responses
  - Usage: Extract download URLs dynamically
  - Benefits: Eliminates hardcoded URLs

### Operating System
- **Debian Linux** (in container)
  - Base Image: `openjdk:8-jdk-slim`
  - Package Manager: `apt-get`
  - Size: Optimized for minimal footprint

## Architecture Patterns

### Pipeline Pattern
```
Download → Process → Structure → Package → Export
```
Each stage has clear inputs/outputs and error handling.

### Discovery Pattern
```
API Query → Parse JSON → Organize by Continent → Display Commands
```
The region discovery system automatically fetches and organizes available regions.

### Container Pattern
- Immutable infrastructure
- Reproducible builds
- Isolated dependencies

### Volume Mounting Pattern
```bash
-v "$(pwd)/output:/app/output"
```
Persistent data storage outside container lifecycle.

## Dependencies and Versions

### Runtime Dependencies
```dockerfile
# Base runtime
FROM openjdk:8-jdk-slim

# System packages
RUN apt-get update && apt-get install -y \
    maven \
    git \
    wget \
    zip \
    jq
```

### Build Dependencies
```xml
<!-- GraphHopper v1.0 (from pom.xml) -->
<dependency>
    <groupId>com.graphhopper</groupId>
    <artifactId>graphhopper-core</artifactId>
    <version>1.0</version>
</dependency>
```

### External Services
- **Geofabrik Downloads**: HTTP-based, no authentication required
- **GitHub**: Git repository access for GraphHopper source
- **OpenStreetMap**: Underlying data source (via Geofabrik)
- **GitHub Container Registry (GHCR)**: Pre-built Docker images

## Performance Stack

### Memory Management
- **JVM Heap**: 4GB allocated (`-Xmx4096m -Xms4096m`)
- **Container Memory**: 6GB recommended (overhead for OS)
- **Host Memory**: 8GB+ recommended for large states

### Storage Requirements
- **Temporary Space**: 2-3x final output size
- **Docker Images**: ~500MB (cached layers)
- **Output Storage**: Varies by region (9MB-760MB zipped)

### Network Usage
- **Download Bandwidth**: Depends on region size (8MB-4.3GB)
- **Upload Bandwidth**: None (offline processing)
- **Latency**: Not critical (batch downloads)

## Security Stack

### Container Security
- **Base Image**: Official OpenJDK (trusted source)
- **User Context**: Non-root operation where possible
- **Network Access**: Download-only, no incoming connections
- **File System**: Isolated via Docker volumes

### Data Security
- **Data Sources**: Public domain (OpenStreetMap)
- **Encryption**: HTTPS for downloads where available
- **Secrets**: None required
- **Privacy**: No user data processed

### Supply Chain Security
- **Dependencies**: Well-known open source projects
- **Verification**: Maven Central repository signatures
- **Updates**: Pinned versions for reproducibility

## Development Stack

### Local Development
```bash
# Development setup
git clone https://github.com/joshuafuller/atak-vns-offline-routing-generator
cd atak-vns-offline-routing-generator
chmod +x run.sh list-regions.sh

# List available regions
./list-regions.sh

# Test with small region
./run.sh europe/malta
```

### Testing Approach
- **Unit Tests**: None (primarily shell scripts)
- **Integration Tests**: End-to-end region processing
- **Validation**: File structure verification
- **Manual Testing**: VNS plugin compatibility
- **Dependencies**: Pure Bash/Java implementation (no Python required)

### Build Pipeline
```bash
# Build process
docker build -t ghcr.io/joshuafuller/atak-vns-offline-routing-generator:latest .

# Execution
docker run --rm \
    -v "$(pwd)/output:/app/output" \
    -v "$(pwd)/cache:/app/cache" \
    ghcr.io/joshuafuller/atak-vns-offline-routing-generator:latest \
    ./generate-data.sh us/delaware
```

## Monitoring and Logging

### Logging Strategy
- **Level**: INFO for normal operations
- **Output**: STDOUT (captured by Docker)
- **Format**: Plain text with timestamps
- **Rotation**: Handled by Docker daemon

### Progress Tracking
- **Stage Indicators**: Step-by-step progress output
- **File Sizes**: Progress indicators for large downloads
- **Time Estimates**: Based on historical performance data
- **Error Reporting**: Exit codes and descriptive messages

### Health Checks
```bash
# Validate output
ls -la output/[region-name]/
du -sh output/[region-name].zip
unzip -t output/[region-name].zip
```

## Integration Points

### ATAK Integration
- **File System**: Android storage access
- **VNS Plugin**: GraphHopper v1.0 compatibility
- **User Interface**: VNS routing selection

### Android Integration
- **Storage Path**: `/storage/emulated/0/atak/tools/VNS/GH/`
- **Permissions**: External storage read/write
- **File Transfer**: USB, WiFi, cloud storage

### CI/CD Potential
- **GitHub Actions**: Automated testing
- **Docker Registry**: Image distribution (GHCR)
- **Release Automation**: Tagged builds

## Extensibility Points

### New Routing Engines
- Modular design allows different engines
- Interface: Input (OSM) → Output (binary graph)
- Requirements: VNS compatibility layer needed

### Additional Data Sources
- Alternative to Geofabrik (same format requirements)
- Custom OSM extracts
- Private/commercial map data (licensing permitting)

### Output Formats
- Current: GraphHopper binary + ZIP
- Future: Different compression, metadata formats
- Requirements: VNS plugin compatibility maintained

## Resource Requirements Summary

### Minimum System Requirements
- **CPU**: 2 cores, 2.0+ GHz
- **RAM**: 6GB available (4GB for container + overhead)
- **Storage**: 10GB free space
- **Network**: Broadband internet (for downloads)
- **OS**: Windows 10+, macOS 10.15+, Linux (Docker support)

### Recommended System Requirements
- **CPU**: 4 cores, 3.0+ GHz
- **RAM**: 8GB available
- **Storage**: 20GB free space (SSD preferred)
- **Network**: Stable broadband
- **OS**: Latest versions with native Docker support