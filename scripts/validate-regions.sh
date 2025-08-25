#!/bin/bash

# ==============================================================================
# VNS Offline Data Generator - Region Validator
#
# Description:
# Validates that regions listed in list-regions.sh actually exist by checking
# for 404 errors on the download URLs. This prevents users from getting
# incorrect region paths.
# ==============================================================================

INDEX_URL="https://download.geofabrik.de/index-v1-nogeom.json"

# Check dependencies
check_deps() {
    local missing=0
    
    if ! command -v jq >/dev/null 2>&1; then
        echo "❌ Error: jq is required. Install: sudo apt-get install jq"
        missing=1
    fi
    
    if ! command -v curl >/dev/null 2>&1; then
        echo "❌ Error: curl is required. Install: sudo apt-get install curl"
        missing=1
    fi
    
    if [ $missing -eq 1 ]; then
        exit 1
    fi
}

# Test if a URL returns 404
test_url() {
    local url="$1"
    local http_code
    # Follow redirects (-L) and get final HTTP code
    http_code=$(curl -s -L -o /dev/null -w "%{http_code}" --max-time 10 "$url" 2>/dev/null)
    echo "$http_code"
}

# Validate a single region
validate_region() {
    local region_id="$1"
    local pbf_url="$3"
    local poly_url="$4" 
    local kml_url="$5"
    
    echo -n "Testing $region_id ... "
    
    # Test PBF file (most important)
    local pbf_code
    pbf_code=$(test_url "$pbf_url")
    
    if [ "$pbf_code" = "404" ]; then
        echo "❌ PBF 404"
        return 1
    elif [ "$pbf_code" = "200" ]; then
        echo "✅ OK"
        return 0  
    elif [ "$pbf_code" = "302" ] || [ "$pbf_code" = "301" ]; then
        echo "✅ OK (redirect)"
        return 0
    else
        echo "⚠️  PBF: $pbf_code"
        return 2
    fi
}

# Main validation function
main() {
    check_deps
    
    echo "🔍 VNS Region Validator"
    echo "======================================"
    echo "📡 Fetching region data from Geofabrik..."
    
    local json_data
    if ! json_data=$(curl -s "$INDEX_URL" 2>/dev/null); then
        echo "❌ Error: Failed to fetch region data"
        exit 1
    fi
    
    echo "🧪 Testing popular regions for accuracy..."
    echo ""
    
    # Test the regions we show in examples
    local test_regions=(
        "germany"
        "malta" 
        "us/rhode-island"
        "us/california"
        "us/delaware"
        "ontario"
        "australia"
        "nepal"
        "morocco"
    )
    
    local failed=0
    local warnings=0
    local passed=0
    
    for region_id in "${test_regions[@]}"; do
        # Extract URLs for this region
        local region_data
        region_data=$(echo "$json_data" | jq -r --arg id "$region_id" '
            .features[] | select(.properties.id == $id) | 
            .properties.urls.pbf + "|" + 
            (.properties.urls.pbf | gsub("-latest.osm.pbf"; ".poly")) + "|" +
            (.properties.urls.pbf | gsub("-latest.osm.pbf"; ".kml"))
        ')
        
        if [ -z "$region_data" ]; then
            echo "❌ $region_id: Not found in API"
            ((failed++))
            continue
        fi
        
        IFS='|' read -r pbf_url poly_url kml_url <<< "$region_data"
        
        validate_region "$region_id" "" "$pbf_url" "$poly_url" "$kml_url"
        local result=$?
        
        if [ $result -eq 0 ]; then
            ((passed++))
        elif [ $result -eq 1 ]; then
            ((failed++))
        else
            ((warnings++))
        fi
        
        # Small delay to be nice to servers
        sleep 0.5
    done
    
    echo ""
    echo "📊 Validation Results:"
    echo "  ✅ Passed: $passed"
    echo "  ⚠️  Warnings: $warnings" 
    echo "  ❌ Failed: $failed"
    echo ""
    
    if [ "$failed" -eq 0 ]; then
        echo "🎉 All popular regions validated successfully!"
        echo "   Users should not encounter 404 errors with our examples."
    else
        echo "⚠️  Some regions failed validation."
        echo "   Consider updating examples in list-regions.sh"
        exit 1
    fi
}

# Allow testing specific regions
if [ $# -gt 0 ]; then
    check_deps
    echo "🔍 Testing specific region: $1"
    
    json_data=$(curl -s "$INDEX_URL" 2>/dev/null)
    region_data=$(echo "$json_data" | jq -r --arg id "$1" '
        .features[] | select(.properties.id == $id) | 
        .properties.urls.pbf + "|" + 
        (.properties.urls.pbf | gsub("-latest.osm.pbf"; ".poly")) + "|" +
        (.properties.urls.pbf | gsub("-latest.osm.pbf"; ".kml"))
    ')
    
    if [ -z "$region_data" ]; then
        echo "❌ Region '$1' not found in API"
        exit 1
    fi
    
    IFS='|' read -r pbf_url poly_url kml_url <<< "$region_data"
    echo "📍 PBF URL: $pbf_url"
    echo "📍 POLY URL: $poly_url"
    echo "📍 KML URL: $kml_url"
    echo ""
    
    validate_region "$1" "" "$pbf_url" "$poly_url" "$kml_url"
    exit $?
else
    main "$@"
fi