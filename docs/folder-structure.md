# 📁 Folder Structure & Data Management

Understanding how the VNS Offline Data Generator organizes files and manages data.

## 🏗️ Project Structure

```
atak-vns-offline-routing-generator/
├── 📄 run.sh                    # Main execution script
├── 📄 list-regions.sh           # Show available regions
├── 📄 generate-data.sh          # Core data processing logic
├── 🐳 Dockerfile               # Docker container definition
├── 📁 cache/                   # Downloaded OSM data (preserved)
├── 📁 output/                  # Generated routing files (preserved)
├── 📁 logs/                    # Processing logs
└── 📁 docs/                    # Documentation
```

## 💾 Cache Folder (`cache/`)

**Purpose**: Stores downloaded OpenStreetMap data for reuse

**Contents**:
- `[region].osm.pbf` - Raw OSM data from Geofabrik
- `[region].kml` - KML boundary file
- `[region].poly` - Polygon boundary file
- `[region].timestamp.*` - Tracks when data was downloaded

**Benefits**:
- ⚡ **Faster re-runs** - Skip download if we detect that no new update since last download
- 🌐 **Offline capability** - Work without internet after initial download
- 💰 **Bandwidth savings** - Large regions only downloaded once
- 🔄 **Smart updates** - Automatically checks for newer data

**Example**:
```
cache/
├── delaware.osm.pbf           # 23 MB - OSM data
├── delaware.kml               # 2 KB - Boundary
├── delaware.poly              # 1 KB - Polygon
├── delaware.timestamp.osm     # Tracks OSM download time
└── germany.osm.pbf            # 890 MB - Larger region
```

## 📦 Output Folder (`output/`)

**Purpose**: Contains final VNS-compatible routing files ready for ATAK

**Contents for each region**:
- `📁 [region]/` - Routing data folder
- `📦 [region].zip` - Compressed for device transfer

**Routing Data Files**:
- `edges` - Road network connections
- `geometry` - Route geometries and shapes  
- `location_index` - Spatial indexing for fast lookups
- `nodes` - Road intersections and points
- `nodes_ch_car` - Contraction hierarchies for cars
- `properties` - Routing engine metadata
- `shortcuts_car` - Pre-computed routing shortcuts
- `string_index_*` - String data indexing
- `[region].kml` - Boundary visualization
- `[region].poly` - Boundary polygon
- `[region].timestamp` - Generation timestamp

**Example**:
```
output/
├── 📁 delaware/
│   ├── edges                  # GraphHopper routing data
│   ├── geometry              
│   ├── location_index        
│   ├── nodes                 
│   ├── delaware.kml          # Boundary files
│   └── delaware.timestamp    # When generated
└── 📦 delaware.zip           # Ready for device (9.1 MB)
```

## 🔄 Data Lifecycle

### 1. **Download Phase**
```bash
./run.sh us/california
```
- Downloads OSM data to `cache/california.osm.pbf`
- Downloads boundary files to `cache/`
- Creates timestamp files for tracking

### 2. **Processing Phase**
- GraphHopper processes cached OSM data
- Generates routing files in `output/california/`
- Creates ZIP package `output/california.zip`

### 3. **Reuse Phase**
```bash
./run.sh us/california  # Second run
```
- ✅ **Checks cache first** - Uses existing `california.osm.pbf` if recent
- ⚡ **Skips download** - Starts processing immediately
- 🕒 **Faster completion** - Only processing time, no download time

## 🗂️ File Sizes by Region Type

| Region Size | OSM Cache | Output Folder | ZIP Package |
|-------------|-----------|---------------|-------------|
| **Small** (Malta) | 7.6 MB | 9.1 MB | 2.6 MB |
| **Small** (Delaware) | 20 MB | 22 MB | 9.1 MB |
| **Medium** (Great Britain) | 1.9 GB | 656 MB | 381 MB |
| **Large** (Germany) | 4.3 GB | 1.3 GB | 760 MB |

## 🧹 Cleanup & Maintenance

### Clear Cache (Force Fresh Download)
```bash
rm -rf cache/[region]*
./run.sh [region]  # Will re-download
```

### Clear Output (Regenerate Routing)
```bash
rm -rf output/[region]*
./run.sh [region]  # Will regenerate from cache
```

### Full Cleanup
```bash
rm -rf cache/ output/
```

### Smart Cleanup (Keep Recent)
```bash
find cache/ -name "*.osm.pbf" -mtime +30 -delete  # Remove files older than 30 days
```

## 🔒 Data Safety During Updates

When updating the tool:
- ✅ `cache/` folder is **never** deleted
- ✅ `output/` folder is **never** deleted  
- ✅ Generated ZIP files are **always** preserved
- ✅ Only scripts and Docker images are updated

This means you can safely update without losing hours of processing time or bandwidth.