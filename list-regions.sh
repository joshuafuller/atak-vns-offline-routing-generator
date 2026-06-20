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
    while IFS='	' read -r name command; do
        printf "  %-30s %s\n" "$name" "$command"
    done
}

# Portable DNS resolution check. getent is Linux-only (absent on macOS and some
# minimal images), so fall back through host/nslookup/python3 before giving up.
dns_check_host() {
    local host="$1"
    if command -v getent >/dev/null 2>&1; then
        getent hosts "$host" >/dev/null 2>&1 && { echo "resolves OK"; return; }
        echo "RESOLUTION FAILED"; return
    elif command -v host >/dev/null 2>&1; then
        host "$host" >/dev/null 2>&1 && { echo "resolves OK"; return; }
        echo "RESOLUTION FAILED"; return
    elif command -v nslookup >/dev/null 2>&1; then
        nslookup "$host" >/dev/null 2>&1 && { echo "resolves OK"; return; }
        echo "RESOLUTION FAILED"; return
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "import socket,sys; socket.gethostbyname(sys.argv[1])" "$host" >/dev/null 2>&1 \
            && { echo "resolves OK"; return; }
        echo "RESOLUTION FAILED"; return
    fi
    echo "could not check (no getent/host/nslookup/python3 available)"
}

# Main function
main() {
    check_jq
    
    echo "🌍 VNS Offline Routing - Available Regions"
    echo "============================================="
    echo "📡 Fetching current region data from Geofabrik..."
    echo ""
    
    local json_data
    local retry_count=0
    local max_retries=10
    # NOTE: err_file is intentionally NOT 'local' — the EXIT trap below fires
    # after main() returns, by which point a local would be out of scope and
    # the temp file would leak on every successful run.
    if ! err_file=$(mktemp 2>/dev/null) || [ -z "$err_file" ]; then
        err_file="/tmp/vns-fetch-err.$$"
        : > "$err_file" 2>/dev/null || err_file="/dev/null"
    fi
    # Clean the temp file up even if the user hits Ctrl-C mid-fetch.
    [ "$err_file" != "/dev/null" ] && trap 'rm -f "$err_file"' EXIT

    while [ $retry_count -lt $max_retries ]; do
        # Try a normal (dual-stack) request first; on failure, retry forcing
        # IPv4 (-4) to work around hosts where IPv6 is configured but broken.
        # Real errors are captured to $err_file so we can show them if we give up.
        if json_data=$(curl -sS --fail --max-time 30 "$INDEX_URL" 2>>"$err_file") && [ -n "$json_data" ]; then
            break
        fi
        if json_data=$(curl -4 -sS --fail --max-time 30 "$INDEX_URL" 2>>"$err_file") && [ -n "$json_data" ]; then
            break
        fi
        retry_count=$((retry_count + 1))
        echo "⚠️  Retry $retry_count/$max_retries - Failed to fetch region data from Geofabrik API"
        sleep 2
    done

    if [ $retry_count -eq $max_retries ]; then
        echo "❌ Error: Failed to fetch region data from Geofabrik API after $max_retries attempts"
        echo ""
        echo "----- Actual error reported by curl -----"
        if [ -s "$err_file" ]; then
            tail -n 5 "$err_file"
        else
            echo "(no error output captured)"
        fi
        echo "-----------------------------------------"
        echo ""
        echo "🔍 Quick diagnostics:"
        printf "   • DNS for download.geofabrik.de: "
        dns_check_host download.geofabrik.de
        echo "   • For the full handshake, run:"
        echo "       curl -v https://download.geofabrik.de/index-v1-nogeom.json"
        echo ""
        echo "   Common causes when a browser works but this does not:"
        echo "     - a TLS-intercepting proxy/AV whose CA curl does not trust"
        echo "     - a DNS resolver that cannot reach Geofabrik"
        echo "     - broken IPv6, or an IP/geo block on Geofabrik's side"
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