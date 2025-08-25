#!/bin/bash

# ==============================================================================
# VNS Offline Data Generator - Complete Region Validator
#
# Description:
# Systematically validates ALL regions from the JSON against the actual URLs.
# No manual testing - just parse JSON and validate URLs exist.
# ==============================================================================

INDEX_URL="https://download.geofabrik.de/index-v1-nogeom.json"

# Check if URL exists (HEAD request only)
url_exists() {
    local url="$1"
    curl -s --head --fail --max-time 5 "$url" >/dev/null 2>&1
}

main() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "❌ jq required: sudo apt-get install jq"
        exit 1
    fi

    echo "🔍 Systematic Region Validation"
    echo "==============================="
    echo "📡 Fetching region data..."

    local json_data
    if ! json_data=$(curl -s "$INDEX_URL"); then
        echo "❌ Failed to fetch data"
        exit 1
    fi

    echo "🧪 Validating ALL regions systematically..."
    echo ""

    # Extract all regions and their URLs, validate each
    echo "$json_data" | jq -r '
        .features[] | 
        select(.properties.urls.pbf != null) |
        .properties.id + "|" + .properties.urls.pbf
    ' | while IFS='|' read -r region_id pbf_url; do
        
        echo -n "Testing $region_id ... "
        
        if url_exists "$pbf_url"; then
            echo "✅"
        else
            echo "❌ FAIL: $pbf_url"
        fi
        
    done | tee validation_results.log

    echo ""
    echo "📊 Summary:"
    grep -c "✅" validation_results.log && echo " regions passed"
    grep -c "❌" validation_results.log && echo " regions failed"
    
    if grep -q "❌" validation_results.log; then
        echo ""
        echo "❌ Failed regions:"
        grep "❌" validation_results.log
        exit 1
    else
        echo ""
        echo "🎉 All regions validated successfully!"
    fi
}

main "$@"