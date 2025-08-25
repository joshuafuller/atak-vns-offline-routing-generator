#!/bin/bash

# ==============================================================================
# VNS Offline Data Generator - Region Lister
#
# Description:
# Lists available Geofabrik download regions in clean, organized hierarchy.
# Groups regions properly by continent with clear separation.
# ==============================================================================

INDEX_URL="https://download.geofabrik.de/index-v1-nogeom.json"

# Check if jq is installed
check_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "❌ Error: jq is required but not installed."
        echo ""
        echo "📦 Please install jq:"
        echo ""
        echo "🐧 Ubuntu/Debian:  sudo apt-get install jq"
        echo "🍎 macOS:          brew install jq"
        echo "🪟 Windows:        choco install jq"
        echo "🐳 Docker:         apk add jq  (Alpine)"
        echo "📦 Other:          https://stedolan.github.io/jq/download/"
        echo ""
        echo "Then run this script again."
        exit 1
    fi
}

# Format output with simple, reliable formatting
format_output() {
    while IFS=$'\t' read -r name command; do
        printf "  %-30s %s\n" "$name" "$command"
    done
}

# Main function
main() {
    check_jq
    
    echo "🌍 VNS Offline Routing - Available Regions"
    echo "============================================="
    echo "📡 Fetching current region data from Geofabrik..."
    echo ""
    
    local json_data
    if ! json_data=$(curl -s "$INDEX_URL" 2>/dev/null); then
        echo "❌ Error: Failed to fetch region data from Geofabrik API"
        echo "Please check your internet connection and try again."
        exit 1
    fi
    
    local total_count
    total_count=$(echo "$json_data" | jq '.features | length')
    
    echo "📍 Available Regions by Continent:"
    echo ""
    
    # Get list of continents
    local continents
    continents=$(echo "$json_data" | jq -r '.features[] | select(.properties.parent == null) | .properties.id' | sort)
    
    # Process each continent
    for continent in $continents; do
        local continent_name
        continent_name=$(echo "$json_data" | jq -r --arg cont "$continent" '.features[] | select(.properties.id == $cont) | .properties.name')
        
        echo "📍 $continent_name:"
        
        # Show children of this continent with proper alignment
        echo "$json_data" | jq -r --arg cont "$continent" '
            .features[] | 
            select(.properties.parent == $cont) | 
            .properties.name + "\t→ ./run.sh " + .properties.id
        ' | sort | format_output
        
        echo ""
    done
    
    echo "💡 Usage:"
    echo "   • Copy any command above: ./run.sh [region-id]"  
    echo "   • Smaller regions = faster processing"
    echo "   • Larger regions = more time and memory needed"
    echo ""
    echo "📊 Total: $total_count regions available"
    echo "🔗 Browse online: https://download.geofabrik.de/"
}

main "$@"