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
    echo "Error: Region path not provided to the script."
    echo "Expected format: continent/country/region (e.g., europe/germany)"
    exit 1
fi

REGION_PATH=$1                       # Full geofabrik path such as north-america/us/california
REGION_NAME=$(basename "$REGION_PATH")
FILENAME="${REGION_NAME}-latest"
OSM_FILE="${FILENAME}.osm.pbf"
POLY_FILE="${REGION_NAME}.poly"     # POLY files don't have -latest suffix
KML_FILE="${REGION_NAME}.kml"       # KML boundary file
GRAPH_FOLDER="${REGION_NAME}"      # VNS expects folder named after region

# --- Geofabrik URL Configuration ---
BASE_URL="http://download.geofabrik.de/${REGION_PATH}"
OSM_URL="${BASE_URL}-latest.osm.pbf"
POLY_URL="${BASE_URL}.poly"
KML_URL="${BASE_URL}.kml"

# --- Data Download ---
echo "Step 1: Downloading map data for '${REGION_PATH}'..."
echo "Downloading PBF from: ${OSM_URL}"
if ! wget -q --show-progress -O ${OSM_FILE} ${OSM_URL}; then
    echo "Error: Failed to download OSM file"
    exit 1
fi
echo "Downloading POLY from: ${POLY_URL}"
if ! wget -q --show-progress -O ${POLY_FILE} ${POLY_URL}; then
    echo "Error: Failed to download POLY file"
    exit 1
fi
echo "Downloading KML from: ${KML_URL}"
if ! wget -q --show-progress -O ${KML_FILE} ${KML_URL}; then
    echo "Error: Failed to download KML file"
    exit 1
fi
echo "Downloads complete."

# --- GraphHopper Configuration ---
echo "Step 2: Configuring GraphHopper memory allocation..."
# Modify the graphhopper.sh script to increase Java heap space.
# This is necessary for processing larger states and prevents memory errors.
# 'sed' is used to find and replace the memory setting line in the script.
sed -i 's/-Xmx1000m -Xms1000m/-Xmx4096m -Xms4096m/' ./graphhopper/graphhopper.sh
echo "Memory allocation set to 4GB."

# --- Graph Generation ---
echo "Step 3: Running GraphHopper import process..."
echo "This is the longest step and can take a significant amount of time."

# Run GraphHopper from its directory
(cd graphhopper && java -Xmx4096m -Xms4096m -Ddw.graphhopper.datareader.file="../${OSM_FILE}" -Ddw.graphhopper.graph.location="../${GRAPH_FOLDER}" -jar web/target/graphhopper-web-1.0-SNAPSHOT.jar import config-example.yml)

if [ $? -ne 0 ]; then
    echo "Error: GraphHopper import failed"
    exit 1
fi

echo "GraphHopper import complete. A new folder named '${GRAPH_FOLDER}' has been created."

# --- File Organization ---
echo "Step 4: Organizing files for VNS compatibility..."

# Move both boundary files into the newly created graph folder
mv ${POLY_FILE} ./${GRAPH_FOLDER}/
mv ${KML_FILE} ./${GRAPH_FOLDER}/

# Extract the creation timestamp from the 'properties' file inside the graph folder
if [ ! -f "./${GRAPH_FOLDER}/properties" ]; then
    echo "Error: Properties file not found in ${GRAPH_FOLDER}. GraphHopper import may have failed."
    exit 1
fi

TIMESTAMP=$(grep 'datareader.data_date' ./${GRAPH_FOLDER}/properties | cut -d'=' -f2)

if [ -z "$TIMESTAMP" ]; then
    echo "Warning: Could not automatically determine timestamp. Using current time."
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
fi

# Create both timestamp files required by VNS (matching the structure you found)
echo ${TIMESTAMP} > ./${GRAPH_FOLDER}/timestamp
echo ${TIMESTAMP} > ./${GRAPH_FOLDER}/${REGION_NAME}.timestamp
echo "Timestamp files created with value: ${TIMESTAMP}"

# --- Finalizing Output ---
echo "Step 5: Moving final data to the output directory..."
# The 'output' directory inside the container is mapped to the user's local machine.
mv ./${GRAPH_FOLDER} ./output/

echo "Step 6: Creating ZIP file for easy transfer..."
cd ./output/
zip -r ${GRAPH_FOLDER}.zip ${GRAPH_FOLDER}/
echo "ZIP file created: ${GRAPH_FOLDER}.zip ($(du -sh ${GRAPH_FOLDER}.zip | cut -f1))"
cd ..

echo "Cleanup: Removing temporary downloaded files..."
rm ${OSM_FILE}

echo "Process finished."
echo ""
echo "🎉 VNS offline routing data successfully generated for ${REGION_NAME}!"
echo ""
echo "Generated files:"
echo "  📁 Folder: ./output/${GRAPH_FOLDER}/"
echo "  📦 ZIP file: ./output/${GRAPH_FOLDER}.zip"
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
