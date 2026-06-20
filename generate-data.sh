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

# === COMPREHENSIVE LOGGING SYSTEM ===
mkdir -p ./logs
LOG_FILE="./logs/vns-generation-$(date +%Y%m%d_%H%M%S).log"

# Function to log to file only (no screen output)
log_to_file() {
    echo "$@" >> "$LOG_FILE"
}

log_system_info() {
    # Log to file only - no screen output
    log_to_file "=== VNS GENERATION LOG - $(date) ==="
    log_to_file "BASIC: region=$REGION_ID, command=$0 $1"
    
    # Verbose logging only if enabled or on error  
    if [ "$VERBOSE_LOG" = "true" ] || [ "${LOG_VERBOSE_ON_ERROR:-false}" = "true" ]; then
        log_to_file "System Information:"
        log_to_file "  • Container: $(hostname)"
        log_to_file "  • OS: $(uname -a)"
        log_to_file "  • Memory: $(free -h | grep '^Mem:' || echo 'Memory info unavailable')"
        log_to_file "  • Disk Space: $(df -h . | tail -1 || echo 'Disk info unavailable')"
        log_to_file "  • User: $(whoami)"
        log_to_file "  • PWD: $(pwd)"
    fi
    log_to_file ""
}

# Logging functions (file-only, no screen output)
log_minimal() {
    log_to_file "MINIMAL_LOG: $*"
}

log_verbose() {
    if [ "$VERBOSE_LOG" = "true" ] || [ "${LOG_VERBOSE_ON_ERROR:-false}" = "true" ]; then
        log_to_file "VERBOSE_LOG: $*"
    fi
}

log_model_data() {
    local stage="$1"
    local data="$2"
    log_to_file "MODEL_DATA: stage=$stage, $data"
}

# --- Input Validation ---
if [ -z "$1" ]; then
    echo "Error: Region ID not provided to the script."
    echo "Expected format: region-id (e.g., germany, us/delaware, great-britain)"
    echo "Run './list-regions.sh' to see all available regions"
    exit 1
fi

REGION_ID=$1
DOWNLOAD_ONLY=false

# === SYSTEM BENCHMARK FUNCTION ===
run_system_benchmark() {
    local start_time
    start_time=$(date +%s%N)
    
    # CPU + I/O benchmark: compress 50MB of zero data
    # This tests CPU performance, memory bandwidth, and I/O - similar to GraphHopper workload
    dd if=/dev/zero bs=1M count=50 2>/dev/null | gzip > /dev/null
    
    local end_time
    end_time=$(date +%s%N)
    local benchmark_ms=$(((end_time - start_time) / 1000000))
    
    # Return benchmark score (lower = faster system)
    echo "$benchmark_ms"
}

# === BENCHMARK-BASED PREDICTION USING ACTUAL DATA ===
predict_time_with_benchmark() {
    local file_size_mb=$1
    local user_benchmark_score=$2
    local baseline_benchmark_score=250   # Reference system benchmark (modern system baseline)
    
    # Lookup table based on actual 5-state benchmark results (Aug 27, 2025)
    # Format: size_threshold:base_time_seconds
    local base_time=60  # default fallback
    
    if [ "$file_size_mb" -le 50 ]; then
        base_time=10     # Delaware: 20MB → 6s actual (85.7% accuracy)
    elif [ "$file_size_mb" -le 170 ]; then
        base_time=18     # Alaska: 133MB → 13s actual (was 30, now 18)
    elif [ "$file_size_mb" -le 250 ]; then
        base_time=55     # Maryland: 193MB → 43s actual (was 45, now 55)
    elif [ "$file_size_mb" -le 350 ]; then
        base_time=60     # Massachusetts: 287MB → 48s actual (was 55, now 60)
    elif [ "$file_size_mb" -le 450 ]; then
        base_time=130    # North Carolina/Virginia: ~387-392MB → ~115-145s
    elif [ "$file_size_mb" -le 650 ]; then
        base_time=350    # Texas: 632MB → 274s actual (was 280, now 350)
    elif [ "$file_size_mb" -le 1300 ]; then
        base_time=360    # California: 1207MB → 359s
    elif [ "$file_size_mb" -le 1700 ]; then
        base_time=540    # US Northeast: 1629MB → 540s
    else
        # Extrapolate for very large files: ~0.21 seconds per MB
        base_time=$(awk -v size="$file_size_mb" 'BEGIN { printf "%.0f", size * 0.21 }')
    fi
    
    # Scale based on benchmark performance
    local scaled_time
    scaled_time=$(awk -v base="$base_time" -v user="$user_benchmark_score" -v baseline="$baseline_benchmark_score" '
        BEGIN { 
            scale_factor = user / baseline
            # Cap scaling between 0.3x and 3x for safety
            if (scale_factor < 0.3) scale_factor = 0.3
            if (scale_factor > 3.0) scale_factor = 3.0
            printf "%.0f", base * scale_factor 
        }')
    
    echo "$scaled_time"
}

# Initialize logging now that REGION_ID is defined
log_system_info "$@"

# Check for --download-only flag
if [ "$2" = "--download-only" ]; then
    DOWNLOAD_ONLY=true
    echo "🔽 DOWNLOAD-ONLY MODE: Will download files but skip GraphHopper processing"
fi
REGION_NAME=$(basename "$REGION_ID")
FILENAME="${REGION_NAME}-latest"
OSM_FILE="${FILENAME}.osm.pbf"
POLY_FILE="${REGION_NAME}.poly"
KML_FILE="${REGION_NAME}.kml"
GRAPH_FOLDER="${REGION_NAME}"

# --- Fetch URLs from Geofabrik API ---
echo "Fetching region URLs from Geofabrik API..."

GEOFABRIK_INDEX_URL="https://download.geofabrik.de/index-v1-nogeom.json"
retry_count=0
max_retries=10
WGET_ERR=$(mktemp)

while [ $retry_count -lt $max_retries ]; do
    # Try a normal (dual-stack) request first; on failure, retry forcing IPv4
    # (-4) for hosts/containers where IPv6 is present but broken. Real errors
    # are captured to $WGET_ERR so we can surface them if all attempts fail.
    if API_RESPONSE=$(wget -qO- "$GEOFABRIK_INDEX_URL" 2>>"$WGET_ERR") && [ -n "$API_RESPONSE" ]; then
        break
    fi
    if API_RESPONSE=$(wget -4 -qO- "$GEOFABRIK_INDEX_URL" 2>>"$WGET_ERR") && [ -n "$API_RESPONSE" ]; then
        break
    fi
    retry_count=$((retry_count + 1))
    echo "⚠️  Retry $retry_count/$max_retries - Failed to fetch region data from Geofabrik API"
    sleep 2
done

if [ $retry_count -eq $max_retries ]; then
    echo "❌ Error: Failed to fetch region data from Geofabrik API after $max_retries attempts"
    echo ""
    echo "----- Actual error reported by wget -----"
    tail -n 8 "$WGET_ERR" 2>/dev/null | grep -v '^$' | tail -n 5 || echo "(no error output captured)"
    echo "-----------------------------------------"
    echo ""
    echo "🔍 Quick diagnostics (run on the HOST, outside Docker):"
    printf "   • DNS for download.geofabrik.de: "
    if getent hosts download.geofabrik.de >/dev/null 2>&1; then echo "resolves OK inside container"; else echo "RESOLUTION FAILED inside container"; fi
    echo "   • For the full handshake, run on the host:"
    echo "       curl -v https://download.geofabrik.de/index-v1-nogeom.json"
    echo ""
    echo "   Common causes when a browser works but this does not:"
    echo "     - a TLS-intercepting proxy/AV whose CA wget/curl does not trust"
    echo "     - Docker's DNS cannot reach Geofabrik (check the host resolver)"
    echo "     - broken IPv6, or an IP/geo block on Geofabrik's side"
    rm -f "$WGET_ERR"
    exit 1
fi
rm -f "$WGET_ERR"

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

# Exit early if download-only mode
if [ "$DOWNLOAD_ONLY" = "true" ]; then
    echo ""
    echo "🔽 DOWNLOAD-ONLY COMPLETED!"
    echo "="*30
    echo "📁 Files downloaded to cache:"
    echo "  • OSM File: $(du -h "$CACHED_OSM_FILE" | cut -f1) - $OSM_FILE" 
    echo "  • Boundary: $POLY_FILE"
    echo "  • KML: $KML_FILE"
    echo ""
    echo "📊 File size information:"
    if [ -f "$OSM_FILE" ]; then
        OSM_SIZE=$(du -m "$OSM_FILE" | cut -f1)
        OSM_SIZE_GB=$(echo "scale=1; $OSM_SIZE/1000" | bc)
        echo "  • OSM File: ${OSM_SIZE}MB (${OSM_SIZE_GB}G)"
    fi
    echo ""
    echo "✅ Ready for processing with: ./run.sh ${REGION_ID}"
    exit 0
fi

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
    # --- Dynamic Memory Allocation ---
    echo "Step 2: Configuring GraphHopper memory allocation..."
    
    # Function to detect system memory in MB
    detect_system_memory() {
        local total_memory=0
        
        # Try different methods to detect total system memory
        if [ -r /proc/meminfo ]; then
            # Linux (including WSL)
            total_memory=$(awk '/MemTotal/ { printf "%.0f", $2/1024 }' /proc/meminfo)
        elif command -v sysctl >/dev/null 2>&1; then
            # macOS/BSD
            total_memory=$(sysctl -n hw.memsize 2>/dev/null | awk '{ printf "%.0f", $1/1024/1024 }')
        elif command -v wmic >/dev/null 2>&1; then
            # Windows (native, not WSL)
            total_memory=$(wmic computersystem get TotalPhysicalMemory /value 2>/dev/null | grep "=" | cut -d"=" -f2 | awk '{ printf "%.0f", $1/1024/1024 }')
        fi
        
        # Fallback if detection failed
        if [ "$total_memory" -eq 0 ] || [ -z "$total_memory" ]; then
            echo "8192"  # 8GB fallback
        else
            echo "$total_memory"
        fi
    }
    
    # Function to calculate required memory based on OSM file size
    calculate_required_memory() {
        local osm_file="$1"
        
        if [ ! -f "$osm_file" ]; then
            echo "4096"  # 4GB fallback
            return
        fi
        
        # Get file size in MB (consistent with time prediction calculation)
        OSM_FILE_SIZE_MB=$(du -m "$osm_file" | cut -f1)
        
        # CORRECTED Memory calculation based on actual unconstrained measurements:
        # Uses proven linear model: DockerMemory = 4.01 × FileSize + 320MB + 20% safety margin
        # Based on 10-point analysis with unconstrained US-South data (R² = 0.909)
        local base_memory
        # Use awk instead of bc for better compatibility
        base_memory=$(awk -v size="$OSM_FILE_SIZE_MB" 'BEGIN { printf "%.0f", (size * 4.01 + 320) * 1.2 }')
        
        # Log model data for refinement
        log_model_data "memory_prediction" "file_mb=$OSM_FILE_SIZE_MB, model=4.01x+320*1.2, predicted_mb=$base_memory, r_squared=0.909"
        
        # Ensure minimum 1GB for tiny files
        local required_memory
        if [ "$base_memory" -lt 1024 ]; then
            required_memory=1024
            log_verbose "Applied 1GB minimum for small file (was ${base_memory}MB)"
        else
            required_memory="$base_memory"
        fi
        
        echo "$required_memory"
    }
    
    # Detect system memory
    TOTAL_MEMORY_MB=$(detect_system_memory)
    AVAILABLE_MEMORY_MB=$((TOTAL_MEMORY_MB * 80 / 100))  # Use 80% of total as safe available
    
    # Calculate required memory for this OSM file
    REQUIRED_MEMORY_MB=$(calculate_required_memory "$OSM_FILE")
    
    # Apply user override if set
    if [ -n "$VNS_MEMORY_GB" ] && [ "$VNS_MEMORY_GB" -gt 0 ]; then
        ALLOCATED_MEMORY_MB=$((VNS_MEMORY_GB * 1024))
        echo "🎛️  Using user-specified memory: ${VNS_MEMORY_GB}GB"
    else
        # Use required memory, but cap at available memory
        if [ "$REQUIRED_MEMORY_MB" -le "$AVAILABLE_MEMORY_MB" ]; then
            ALLOCATED_MEMORY_MB="$REQUIRED_MEMORY_MB"
        else
            ALLOCATED_MEMORY_MB="$AVAILABLE_MEMORY_MB"
        fi
    fi
    
    # Convert to GB for display
    ALLOCATED_MEMORY_GB=$((ALLOCATED_MEMORY_MB / 1024))
    REQUIRED_MEMORY_GB=$((REQUIRED_MEMORY_MB / 1024))
    TOTAL_MEMORY_GB=$((TOTAL_MEMORY_MB / 1024))
    
    # Get file size for display and predictions
    OSM_FILE_SIZE=$(du -sh "$OSM_FILE" | cut -f1)
    OSM_FILE_SIZE_MB=$(du -m "$OSM_FILE" | cut -f1)
    
    # Run simple system benchmark for hardware-agnostic predictions
    echo "🔧 Running quick system benchmark..."
    BENCHMARK_SCORE=$(run_system_benchmark)
    
    # Use benchmark-based prediction with actual measurement lookup table
    ESTIMATED_TIME_SEC=$(predict_time_with_benchmark "$OSM_FILE_SIZE_MB" "$BENCHMARK_SCORE")
    ESTIMATED_TIME_MIN=$((ESTIMATED_TIME_SEC / 60))
    
    # Log benchmark-based prediction data
    log_model_data "time_prediction" "file_mb=$OSM_FILE_SIZE_MB, model=benchmark_lookup, predicted_sec=$ESTIMATED_TIME_SEC, benchmark_ms=$BENCHMARK_SCORE"
    
    # Log verbose system metrics for model refinement
    log_verbose "cores=$(nproc), arch=$(uname -m), total_ram_mb=$TOTAL_MEMORY_MB, allocated_mb=$REQUIRED_MEMORY_MB"
    
    # Display comprehensive analysis
    echo "📊 Processing Analysis:"
    echo "   • OSM File: ${OSM_FILE_SIZE} (${OSM_FILE_SIZE_MB}MB)"
    echo "   • Predicted Memory: ${REQUIRED_MEMORY_GB}GB Docker container"
    echo "   • Estimated Time: ${ESTIMATED_TIME_MIN} minutes"
    echo "   • System Memory: ${TOTAL_MEMORY_GB}GB total (${AVAILABLE_MEMORY_MB}MB available)"
    echo "   • Allocated Memory: ${ALLOCATED_MEMORY_GB}GB"
    
    # Enhanced warnings and hardware compatibility
    if [ "$REQUIRED_MEMORY_MB" -gt "$AVAILABLE_MEMORY_MB" ]; then
        echo ""
        echo "❌ INSUFFICIENT MEMORY WARNING!"
        echo "   • Need: ${REQUIRED_MEMORY_GB}GB"
        echo "   • Have: ${TOTAL_MEMORY_GB}GB total"
        echo "   • This WILL fail with out-of-memory errors"
        echo ""
        echo "🔧 Solutions:"
        echo "   • Process smaller regions (individual states)"
        echo "   • Add more RAM to your system"
        echo "   • Use a cloud instance with more memory"
        echo "   • Split large regions into smaller chunks"
        echo ""
    elif [ "$ALLOCATED_MEMORY_GB" -ge 16 ]; then
        echo "   • 🚨 MASSIVE region - will take significant time and resources"
    elif [ "$ALLOCATED_MEMORY_GB" -ge 8 ]; then
        echo "   • ⏳ Large region - processing will take significant time"
    elif [ "$ALLOCATED_MEMORY_GB" -ge 4 ]; then
        echo "   • 📊 Medium region - moderate processing time"
    else
        echo "   • ✅ Small region - quick processing"
    fi
    
    # Enhanced override instructions with examples
    echo ""
    echo "🎛️  MANUAL MEMORY OVERRIDE:"
    echo "   To manually set memory allocation, use:"
    echo "   export VNS_MEMORY_GB=16    # Set 16GB"
    echo "   ./run.sh ${REGION_NAME}    # Then run normally"
    echo ""
    echo "   Examples by region size:"
    echo "   • Small regions (<200MB):  VNS_MEMORY_GB=2"
    echo "   • Medium regions (200MB-1GB): VNS_MEMORY_GB=6"
    echo "   • Large regions (1-3GB):   VNS_MEMORY_GB=16"
    echo "   • Massive regions (3GB+):  VNS_MEMORY_GB=24+"
    echo ""

    # --- Graph Generation ---
    echo "Step 3: Running GraphHopper import process..."
    echo "This is the longest step and can take a significant amount of time."

    # Start timing for actual processing
    PROCESS_START_TIME=$(date +%s)
    log_minimal "graphhopper_start: timestamp=$PROCESS_START_TIME, allocated_memory=${ALLOCATED_MEMORY_GB}GB"

    # Run GraphHopper using pre-built JAR file with dynamic memory
    if ! (cd graphhopper && java -Xmx${ALLOCATED_MEMORY_MB}m -Xms${ALLOCATED_MEMORY_MB}m -Ddw.graphhopper.datareader.file="../${OSM_FILE}" -Ddw.graphhopper.graph.location="../${GRAPH_FOLDER}" -jar graphhopper-web-1.0.jar import config-example.yml); then
        # Enable verbose logging for error case
        LOG_VERBOSE_ON_ERROR=true
        
        echo "❌ Error: GraphHopper import failed"
        log_minimal "error: graphhopper_failed, file_mb=$OSM_FILE_SIZE_MB, allocated_mb=$ALLOCATED_MEMORY_MB"
        log_verbose "error_details: exit_code=$?, allocated_memory=${ALLOCATED_MEMORY_MB}MB"
        echo ""
        echo "🔧 Troubleshooting - GraphHopper Import Failed:"
        echo "  • Allocated ${ALLOCATED_MEMORY_GB}GB but processing still failed"
        echo ""
        echo "💾 Memory Solutions:"
        echo "  • Try more memory: export VNS_MEMORY_GB=$((ALLOCATED_MEMORY_GB + 4))"
        echo "  • Close other applications to free memory"  
        echo "  • Check Docker Desktop has sufficient memory allocated"
        echo ""
        echo "🗺️  Region Solutions:"
        echo "  • Process individual states instead of large regions"
        echo "  • Split massive regions into smaller geographic chunks"
        echo "  • Consider using cloud instance with more RAM"
        echo ""
        echo "💾 Downloaded files preserved for manual inspection:"
        echo "  • ${OSM_FILE} ($(du -sh "${OSM_FILE}" | cut -f1))"
        echo "  • ${POLY_FILE}"
        echo "  • ${KML_FILE}"
        echo ""
        echo "📋 TROUBLESHOOTING LOG:"
        echo "  • Full log saved to: ./logs/ folder"
        echo "  • Share this log when reporting issues"
        echo "  • Log contains system info, memory analysis, and error details"
        echo ""
        echo "🐛 REPORT ISSUE FOR MODEL IMPROVEMENT:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📱 Help us improve predictions by reporting this failure:"
        echo ""
        echo "1. 📄 Copy these essential logs (search for these lines in logs/ folder):"
        echo "   BASIC: region=$REGION_ID"
        echo "   MODEL_DATA: stage=memory_prediction"
        echo "   MODEL_DATA: stage=time_prediction" 
        echo "   MINIMAL_LOG: error: graphhopper_failed"
        echo ""
        echo "2. 🌐 Create issue at: https://github.com/yourusername/vns_offline_data_generator/issues"
        echo "   Title: 'Memory prediction failed for $REGION_NAME ($OSM_FILE_SIZE_MB MB)'"
        echo ""
        echo "3. 📋 Include these details:"
        echo "   • Region: $REGION_NAME ($OSM_FILE_SIZE_MB MB OSM file)"
        echo "   • Predicted: ${REQUIRED_MEMORY_GB}GB, Allocated: ${ALLOCATED_MEMORY_GB}GB"  
        echo "   • Error: GraphHopper import failed"
        echo "   • The essential log lines from step 1"
        echo ""
        echo "4. 🔬 For verbose logs (optional - helps improve models):"
        echo "   Re-run with: VERBOSE_LOG=true ./run.sh $REGION_ID"
        echo "   Include VERBOSE_LOG lines in GitHub issue"
        echo ""
        echo "📈 This data helps us refine our 91% accurate prediction models!"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        exit 1
    fi

    echo "GraphHopper import complete. A new folder named '${GRAPH_FOLDER}' has been created."
    
    # Calculate actual processing time
    PROCESS_END_TIME=$(date +%s)
    ACTUAL_TIME_SEC=$((PROCESS_END_TIME - PROCESS_START_TIME))
    
    # Log completion with prediction vs actual comparison
    log_minimal "graphhopper_complete: predicted_sec=$ESTIMATED_TIME_SEC, actual_sec=$ACTUAL_TIME_SEC, accuracy_percent=$(awk -v pred="$ESTIMATED_TIME_SEC" -v actual="$ACTUAL_TIME_SEC" 'BEGIN { if (pred > 0) { diff = (pred > actual) ? pred - actual : actual - pred; printf "%.0f", 100 - (diff/pred)*100 } else { print "0" } }')"
    log_model_data "timing_result" "region=$REGION_NAME, file_mb=$OSM_FILE_SIZE_MB, predicted_sec=$ESTIMATED_TIME_SEC, actual_sec=$ACTUAL_TIME_SEC, benchmark_ms=$BENCHMARK_SCORE"
    
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
# Final success logging
if [ -n "$PROCESS_START_TIME" ]; then
    TOTAL_END_TIME=$(date +%s)
    TOTAL_TIME_SEC=$((TOTAL_END_TIME - PROCESS_START_TIME))
    log_minimal "success: region=$REGION_NAME, total_time_sec=$TOTAL_TIME_SEC, prediction_accuracy=$(awk -v pred="$ESTIMATED_TIME_SEC" -v actual="$ACTUAL_TIME_SEC" 'BEGIN { if (pred > 0) { diff = (pred > actual) ? pred - actual : actual - pred; printf "%.1f%%", 100 - (diff/pred)*100 } else { print "0.0%" } }')"
fi

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
echo "📊 HELP IMPROVE PREDICTIONS:"
echo "  • For better time estimates, share your results:"
echo "    VERBOSE_LOG=true ./run.sh $REGION_ID"
echo "  • Current accuracy: 91% memory, 90% time predictions"
echo "  • Successful runs help refine models for everyone!"
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
