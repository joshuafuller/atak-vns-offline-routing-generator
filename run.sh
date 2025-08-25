#!/bin/bash

# ==============================================================================
# VNS Offline Data Generator - Runner Script
#
# Description:
# This is the main script that users will execute. It handles building the
# Docker image and running the data generation process within a container.
#
# Usage:
# ./run.sh <geofabrik-path>
# e.g., ./run.sh us/delaware
# e.g., ./run.sh europe/germany
# ==============================================================================

# --- Configuration ---
IMAGE_NAME="vns-data-generator"
IMAGE_TAG="1.1"

# --- Script Logic ---

# Check if a region path was provided as an argument
if [ -z "$1" ]; then
    echo "Error: No region path provided."
    echo "Usage: ./run.sh <geofabrik-path>"
    echo "Example: ./run.sh us/delaware"
    exit 1
fi

REGION_PATH=$1
REGION_NAME=$(basename "$REGION_PATH")

# Create the output and cache directories on the host machine if they don't exist
# Output: where the final data files will be placed
# Cache: where downloaded OSM data is cached for reuse
mkdir -p ./output
mkdir -p ./cache

echo "--- VNS Offline Data Generator ---"

# Check if the Docker image already exists
if [[ "$(docker images -q ${IMAGE_NAME}:${IMAGE_TAG} 2> /dev/null)" == "" ]]; then
  echo "Docker image '${IMAGE_NAME}:${IMAGE_TAG}' not found. Building it now..."
  echo "This may take several minutes, but it only needs to be done once."
  if ! docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" .; then
    echo "Error: Docker image build failed. Please check your Docker setup and Dockerfile."
    exit 1
  fi
  echo "Docker image built successfully."
else
  echo "Docker image '${IMAGE_NAME}:${IMAGE_TAG}' found."
fi

echo "Starting data generation for: ${REGION_PATH}"
echo "The process can take a very long time depending on the region's size."
echo "Please be patient..."

# Run the data generation script inside a Docker container
# -v "$(pwd)/output:/app/output": This mounts the local './output' directory
#   into the container at '/app/output'. Any files created in '/app/output'
#   inside the container will appear in './output' on your local machine.
# -v "$(pwd)/cache:/app/cache": This mounts the local './cache' directory
#   into the container at '/app/cache' for persistent caching across runs.
# --rm: This flag automatically removes the container when it exits, keeping
#   your system clean.

# Check the exit code of the Docker command
if docker run --rm \
    -v "$(pwd)/output:/app/output" \
    -v "$(pwd)/cache:/app/cache" \
    "${IMAGE_NAME}:${IMAGE_TAG}" \
    bash -c "./generate-data.sh ${REGION_PATH}"; then
    echo "---"
    echo "✅ Data generation completed successfully!"
    echo ""
    echo "📁 Generated files are located in: './output' directory"
    echo "📦 Both folder and ZIP file are ready for transfer to your device"
    echo ""
    echo "📱 VNS SETUP EXAMPLE - Complete folder structure on your Android device:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Internal Storage/"
    echo "└── atak/"
    echo "    └── tools/"
    echo "        └── VNS/"
    echo "            └── GH/"
    echo "                ├── ${REGION_NAME}/          ← Your new routing data"
    echo "                │   ├── ${REGION_NAME}.kml"
    echo "                │   ├── ${REGION_NAME}.poly"
    echo "                │   ├── edges"
    echo "                │   ├── geometry"
    echo "                │   ├── nodes"
    echo "                │   └── ... (other files)"
    echo "                ├── florida/        ← Example: Other data you might have"
    echo "                └── california/     ← Example: Additional routing data"
    echo ""
    echo "🔧 VNS will automatically detect all folders in the GH directory!"
else
    echo "---"
    echo "❌ Error: Data generation failed. Please check the logs above for details."
fi
