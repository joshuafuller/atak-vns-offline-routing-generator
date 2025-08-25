#!/bin/bash

# ==============================================================================
# VNS Offline Data Generator - Core Script
#
# Description:
# This script runs inside the Docker container. It downloads the necessary map
# data, runs the GraphHopper import process, and prepares the final output
# folder for VNS.
# ==============================================================================

set -e # Exit immediately if a command exits with a non-zero status.

# --- Input Validation ---
if [ -z "$1" ]; then
    echo "Error: Region ID not provided to the script."
    echo "Expected format: region-id (e.g., germany, us/delaware, great-britain)"
    echo "Run './list-regions.sh' to see all available regions"
    exit 1
fi

REGION_ID=$1
REGION_NAME=$(basename "$REGION_ID")
FILENAME="${REGION_NAME}-latest"
OSM_FILE="${FILENAME}.osm.pbf"
POLY_FILE="${REGION_NAME}.poly"
KML_FILE="${REGION_NAME}.kml"
GRAPH_FOLDER="${REGION_NAME}"

# --- Fetch URLs from Geofabrik API ---
echo "Fetching region URLs from Geofabrik API..."

if ! API_RESPONSE=$(wget -qO- "https://download.geofabrik.de/index-v1-nogeom.json") || [ -z "$API_RESPONSE" ]; then
    echo "Error: Failed to fetch region data from Geofabrik API"
    exit 1
fi

# Extract URLs for the specified region using jq
REGION_DATA=$(echo "$API_RESPONSE" | jq -r --arg region_id "$REGION_ID" '
(.features[] | select(.properties.id == $region_id) | 
 .properties.urls.pbf as $pbf |
 "PBF=" + $pbf,
 "POLY=" + ($pbf | gsub("-latest.osm.pbf"; ".poly")),
 "KML=" + ($pbf | gsub("-latest.osm.pbf"; ".kml"))) // 
"ERROR=Region not found: " + $region_id
')

if echo "$REGION_DATA" | grep -q "ERROR="; then
    echo "$REGION_DATA" | grep "ERROR=" | cut -d'=' -f2-
    echo "Run './list-regions.sh' to see all available regions"
    exit 1
fi

# Parse the URLs
OSM_URL=$(echo "$REGION_DATA" | grep "PBF=" | cut -d'=' -f2-)
POLY_URL=$(echo "$REGION_DATA" | grep "POLY=" | cut -d'=' -f2-)
KML_URL=$(echo "$REGION_DATA" | grep "KML=" | cut -d'=' -f2-)

# Validate URLs were extracted
if [ -z "$OSM_URL" ] || [ -z "$POLY_URL" ] || [ -z "$KML_URL" ]; then
    echo "Error: Failed to extract valid URLs for region '$REGION_ID'"
    echo "This might indicate an API format change or network issue"
    exit 1
fi

# --- Smart Caching System Setup ---
CACHE_DIR="./cache"
OUTPUT_DIR="./output"
CACHE_FILE_PREFIX="${CACHE_DIR}/${REGION_NAME}"
CACHED_OSM_FILE="${CACHE_FILE_PREFIX}.osm.pbf"
CACHED_POLY_FILE="${CACHE_FILE_PREFIX}.poly"
CACHED_KML_FILE="${CACHE_FILE_PREFIX}.kml"
CACHE_TIMESTAMP_FILE="${CACHE_FILE_PREFIX}.timestamp"

# Ensure directories exist (handles first-time users)
mkdir -p "${CACHE_DIR}" "${OUTPUT_DIR}"

# Function to get remote file modification date
get_remote_date() {
    local url="$1"
    local remote_date
    remote_date=$(wget --spider --server-response "$url" 2>&1 | grep -i "Last-Modified:" | tail -1 | cut -d: -f2- | xargs)
    if [ -z "$remote_date" ]; then
        # Fallback if no Last-Modified header - use current time
        date -u +"%a, %d %b %Y %H:%M:%S GMT"
    else
        echo "$remote_date"
    fi
}

# Function to check if cached file is up to date
is_file_current() {
    local url="$1"
    local cached_file="$2"
    local cache_timestamp_file="$3"
    
    if [ ! -f "$cached_file" ] || [ ! -f "$cache_timestamp_file" ]; then
        echo "false"
        return
    fi
    
    local remote_date
    local cached_date
    remote_date=$(get_remote_date "$url")
    cached_date=$(cat "$cache_timestamp_file" 2>/dev/null)
    
    if [ "$remote_date" = "$cached_date" ]; then
        echo "true"
    else
        echo "false"
    fi
}

# Check if we need to download files (silent check for first-time users)
OSM_CURRENT=$(is_file_current "$OSM_URL" "$CACHED_OSM_FILE" "${CACHE_TIMESTAMP_FILE}.osm")
POLY_CURRENT=$(is_file_current "$POLY_URL" "$CACHED_POLY_FILE" "${CACHE_TIMESTAMP_FILE}.poly")
KML_CURRENT=$(is_file_current "$KML_URL" "$CACHED_KML_FILE" "${CACHE_TIMESTAMP_FILE}.kml")

# Only show cache status if we have existing cache or output
if [ -d "./cache" ] && [ "$(ls -A ./cache 2>/dev/null)" ] || [ -d "./output" ] && [ "$(ls -A ./output 2>/dev/null)" ]; then
    echo "🔍 Checking for cached data and updates..."
fi

# Check if output already exists and all cached files are current
if [ -f "./output/${GRAPH_FOLDER}.zip" ] || [ -d "./output/${GRAPH_FOLDER}" ]; then
    if [ "$OSM_CURRENT" = "true" ] && [ "$POLY_CURRENT" = "true" ] && [ "$KML_CURRENT" = "true" ]; then
        echo "✅ Region '${REGION_ID}' is already up to date!"
        echo "📁 Using existing output: ./output/${GRAPH_FOLDER}/"
        echo "📦 ZIP file: ./output/${GRAPH_FOLDER}.zip"
        echo ""
        echo "🔄 To force regeneration, delete the output and cache directories:"
        echo "   rm -rf ./output/${GRAPH_FOLDER}* ./cache/${REGION_NAME}*"
        exit 0
    else
        echo "⚠️  Region '${REGION_ID}' output exists but source data has been updated."
        
        # Create automatic backup with timestamp
        backup_timestamp=$(date +%Y%m%d_%H%M%S)
        echo "📦 Creating automatic backup: ${GRAPH_FOLDER}.backup.${backup_timestamp}"
        
        # Backup existing files
        if [ -d "./output/${GRAPH_FOLDER}" ]; then
            mv "./output/${GRAPH_FOLDER}" "./output/${GRAPH_FOLDER}.backup.${backup_timestamp}"
        fi
        if [ -f "./output/${GRAPH_FOLDER}.zip" ]; then
            mv "./output/${GRAPH_FOLDER}.zip" "./output/${GRAPH_FOLDER}.backup.${backup_timestamp}.zip"
        fi
        
        echo "🔄 Previous data backed up. Proceeding with fresh processing..."
    fi
fi

# Check disk space before starting (require at least 10GB free)
available_space=$(df . | awk 'NR==2 {print $4}')
if [ "$available_space" -lt 10485760 ]; then  # 10GB in KB
    echo "Warning: Low disk space detected. Large regions may fail."
    echo "Available: $(( available_space / 1024 / 1024 ))GB, Recommended: 10GB+"
    echo "Continue? (y/N)"
    read -r response
    if [ "$response" != "y" ] && [ "$response" != "Y" ]; then
        echo "Aborted by user"
        exit 1
    fi
fi

# --- Smart Data Download ---
echo "Step 1: Downloading/updating map data for '${REGION_ID}'..."

# Function to download with caching
download_with_cache() {
    local url="$1"
    local output_file="$2"
    local cached_file="$3"
    local cache_timestamp_file="$4"
    local file_type="$5"
    
    if [ "$file_type" = "true" ]; then
        echo "✅ ${output_file##*/} is up to date (using cached version)"
        cp "$cached_file" "$output_file"
    else
        echo "📥 Downloading ${output_file##*/} from: ${url}"
        if wget -q --show-progress -O "$output_file" "$url"; then
            # Cache the downloaded file
            cp "$output_file" "$cached_file"
            # Store the remote modification date for future comparison
            local remote_date
            remote_date=$(get_remote_date "$url")
            echo "$remote_date" > "$cache_timestamp_file"
            echo "💾 Cached ${output_file##*/} for future use"
        else
            echo "Error: Failed to download ${output_file##*/}"
            exit 1
        fi
    fi
}

# Download files using smart caching
download_with_cache "$OSM_URL" "$OSM_FILE" "$CACHED_OSM_FILE" "${CACHE_TIMESTAMP_FILE}.osm" "$OSM_CURRENT"
download_with_cache "$POLY_URL" "$POLY_FILE" "$CACHED_POLY_FILE" "${CACHE_TIMESTAMP_FILE}.poly" "$POLY_CURRENT"
download_with_cache "$KML_URL" "$KML_FILE" "$CACHED_KML_FILE" "${CACHE_TIMESTAMP_FILE}.kml" "$KML_CURRENT"

echo "Downloads complete."

# --- Check if GraphHopper processing is needed ---
NEED_PROCESSING="false"
if [ "$OSM_CURRENT" != "true" ]; then
    NEED_PROCESSING="true"
    echo "🔄 OSM data has changed - GraphHopper processing required"
elif [ ! -d "./${GRAPH_FOLDER}" ] && [ ! -d "./output/${GRAPH_FOLDER}" ]; then
    NEED_PROCESSING="true"
    echo "🔄 No existing graph data - GraphHopper processing required"
else
    echo "✅ OSM data unchanged and graph exists - Skipping GraphHopper processing"
fi

if [ "$NEED_PROCESSING" = "true" ]; then
    # --- GraphHopper Configuration ---
    echo "Step 2: Configuring GraphHopper memory allocation..."
    # Using pre-built JAR files, memory allocation is set directly in java command
    # No need to modify shell scripts since we're using JAR files directly
    echo "Memory allocation set to 4GB."

    # --- Graph Generation ---
    echo "Step 3: Running GraphHopper import process..."
    echo "This is the longest step and can take a significant amount of time."

    # Run GraphHopper using pre-built JAR file
    if ! (cd graphhopper && java -Xmx4096m -Xms4096m -Ddw.graphhopper.datareader.file="../${OSM_FILE}" -Ddw.graphhopper.graph.location="../${GRAPH_FOLDER}" -jar graphhopper-web-1.0.jar import config-example.yml); then
        echo "❌ Error: GraphHopper import failed"
        echo ""
        echo "🔧 Troubleshooting tips:"
        echo "  • Large regions need significant RAM (8GB+ recommended)"
        echo "  • Close other applications to free memory"
        echo "  • Try processing a smaller region first"
        echo "  • Check Docker has enough memory allocated"
        echo ""
        echo "💾 Downloaded files preserved for manual inspection:"
        echo "  • ${OSM_FILE} ($(du -sh "${OSM_FILE}" | cut -f1))"
        echo "  • ${POLY_FILE}"
        echo "  • ${KML_FILE}"
        exit 1
    fi

    echo "GraphHopper import complete. A new folder named '${GRAPH_FOLDER}' has been created."
    
    # --- File Organization ---
    echo "Step 4: Organizing files for VNS compatibility..."

    # Move both boundary files into the newly created graph folder
    mv "${POLY_FILE}" "./${GRAPH_FOLDER}/"
    mv "${KML_FILE}" "./${GRAPH_FOLDER}/"
else
    echo "Step 2-3: ⚡ Skipping GraphHopper processing (using existing data)"
    echo "Step 4: Using cached GraphHopper data..."
    
    # If we have existing output, copy it to working directory
    if [ -d "./output/${GRAPH_FOLDER}" ]; then
        cp -r "./output/${GRAPH_FOLDER}" "./"
        echo "✅ Copied existing graph data from output directory"
    else
        echo "❌ Error: No cached graph data found. This shouldn't happen."
        echo "Try deleting cache to force fresh processing: rm -rf ./cache/${REGION_NAME}*"
        exit 1
    fi
    
    # Update boundary files in case they changed
    cp "${POLY_FILE}" "./${GRAPH_FOLDER}/"
    cp "${KML_FILE}" "./${GRAPH_FOLDER}/"
fi

# Handle timestamp files
if [ "$NEED_PROCESSING" = "true" ]; then
    # Extract the creation timestamp from the 'properties' file inside the graph folder
    if [ ! -f "./${GRAPH_FOLDER}/properties" ]; then
        echo "Error: Properties file not found in ${GRAPH_FOLDER}. GraphHopper import may have failed."
        exit 1
    fi

    TIMESTAMP=$(grep 'datareader.data_date' "./${GRAPH_FOLDER}/properties" | cut -d'=' -f2)

    if [ -z "$TIMESTAMP" ]; then
        echo "Warning: Could not automatically determine timestamp. Using current time."
        TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    fi

    # Create both timestamp files required by VNS (matching the structure you found)
    echo "${TIMESTAMP}" > "./${GRAPH_FOLDER}/timestamp"
    echo "${TIMESTAMP}" > "./${GRAPH_FOLDER}/${REGION_NAME}.timestamp"
    echo "Timestamp files created with value: ${TIMESTAMP}"
else
    echo "Timestamp files preserved from existing data"
fi

# --- Finalizing Output ---
echo "Step 5: Moving final data to the output directory..."
# The 'output' directory inside the container is mapped to the user's local machine.

# Use cp instead of mv to avoid cross-device issues, then remove source
# (Output directory cleanup already handled at the beginning)
if cp -r "./${GRAPH_FOLDER}" "./output/"; then
    rm -rf "./${GRAPH_FOLDER}"
    echo "Data successfully moved to output directory"
else
    echo "❌ Error: Failed to copy data to output directory"
    echo "💾 Processed data preserved in: ./${GRAPH_FOLDER}"
    echo "You can manually copy it to ./output/ if needed"
    exit 1
fi

echo "Step 6: Creating ZIP file for easy transfer..."
cd ./output/
zip -r "${GRAPH_FOLDER}.zip" "${GRAPH_FOLDER}/"
echo "ZIP file created: ${GRAPH_FOLDER}.zip ($(du -sh "${GRAPH_FOLDER}.zip" | cut -f1))"
cd ..

echo "Cleanup: Removing temporary working files (keeping cache)..."
rm -f "${OSM_FILE}" "${POLY_FILE}" "${KML_FILE}"

echo "Process finished."
echo ""
echo "🎉 VNS offline routing data successfully generated for ${REGION_NAME}!"
echo ""
echo "Generated files:"
echo "  📁 Folder: ./output/${GRAPH_FOLDER}/"
echo "  📦 ZIP file: ./output/${GRAPH_FOLDER}.zip"
echo "  💾 Cached data: ./cache/${REGION_NAME}* (for faster future updates)"
echo ""
echo "📱 INSTALLATION INSTRUCTIONS FOR VNS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Transfer the ZIP file to your Android device"
echo "2. Extract the ZIP file to get the '${GRAPH_FOLDER}' folder"
echo "3. Copy the ENTIRE '${GRAPH_FOLDER}' folder to your device at:"
echo ""
echo "   📍 /storage/emulated/0/atak/tools/VNS/GH/${GRAPH_FOLDER}/"
echo "   📍 OR: Internal Storage/atak/tools/VNS/GH/${GRAPH_FOLDER}/"
echo ""
echo "✅ The VNS plugin will automatically detect the new routing data!"
echo ""
echo "📋 Required folder structure on device:"
echo "   atak/"
echo "   └── tools/"
echo "       └── VNS/"
echo "           └── GH/"
echo "               └── ${GRAPH_FOLDER}/"
echo "                   ├── ${REGION_NAME}.kml"
echo "                   ├── ${REGION_NAME}.poly"
echo "                   ├── ${REGION_NAME}.timestamp"
echo "                   ├── timestamp"
echo "                   ├── edges"
echo "                   ├── geometry"
echo "                   ├── location_index"
echo "                   ├── nodes"
echo "                   ├── nodes_ch_car"
echo "                   ├── properties"
echo "                   ├── shortcuts_car"
echo "                   ├── string_index_keys"
echo "                   └── string_index_vals"
