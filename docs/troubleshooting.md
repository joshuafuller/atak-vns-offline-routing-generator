# Troubleshooting Guide

**Current Version**: 1.1

## Common Issues and Solutions

### Docker Issues

#### "Docker command not found"
**Symptoms**: `bash: docker: command not found`

**Solutions**:
1. **Install Docker**:
   - Windows: Download Docker Desktop from docker.com
   - macOS: Download Docker Desktop from docker.com  
   - Linux: Use package manager (`apt install docker.io` or `yum install docker`)

2. **Verify Installation**:
   ```bash
   docker --version
   docker run hello-world
   ```

3. **Start Docker Service** (Linux):
   ```bash
   sudo systemctl start docker
   sudo systemctl enable docker
   ```

#### "Permission denied" accessing Docker
**Symptoms**: `permission denied while trying to connect to the Docker daemon socket`

**Solutions**:
1. **Add user to docker group** (Linux):
   ```bash
   sudo usermod -aG docker $USER
   # Log out and back in
   ```

2. **Run with sudo** (temporary):
   ```bash
   sudo ./run.sh us/delaware
   ```

3. **Start Docker Desktop** (Windows/macOS):
   - Ensure Docker Desktop is running before executing scripts

#### Docker build fails with network errors
**Symptoms**: `Error response from daemon: Get https://...`

**Solutions**:
1. **Check internet connection**
2. **Configure Docker proxy** (if behind corporate firewall):
   ```json
   {
     "proxies": {
       "default": {
         "httpProxy": "http://proxy:port",
         "httpsProxy": "http://proxy:port"
       }
     }
   }
   ```

### Data Download Issues

#### "Failed to download OSM file" (Exit code 8)
**Symptoms**: `Error: Failed to download OSM file` with wget exit code 8

**Causes**:
- Network connectivity issues
- Geofabrik server temporarily unavailable
- Incorrect region path format

**Solutions**:
1. **Verify internet connection**:
   ```bash
   ping download.geofabrik.de
   ```

2. **Check region path format**:
   - Use Geofabrik API paths: `us/california`, `europe/germany`
   - Valid examples: `us/delaware`, `us/north-carolina`, `europe/malta`
   - Run `./list-regions.sh` to see all available regions

3. **Manual verification**:
   ```bash
   # Test API access
   wget -qO- "https://download.geofabrik.de/index-v1-nogeom.json" | jq '.features[] | select(.properties.id == "us/california")'
   ```

4. **Retry after delay**:
   ```bash
   # Wait and retry
   sleep 60
   ./run.sh us/california
   ```

#### "Region not found" error from API
**Symptoms**: `ERROR=Region not found: [region-name]`

**Note**: Version 1.1 includes improved region discovery and worldwide support.

**Solutions**:
1. **Use correct region paths**:
   ```bash
   # List all available regions with proper hierarchy
   ./list-regions.sh
   
   # US states use 'us/' prefix
   ./run.sh us/california
   
   # European countries use 'europe/' prefix  
   ./run.sh europe/germany
   
   # Other continents have their own prefixes
   ./run.sh africa/djibouti
   
   # Worldwide regions are also supported
   ./run.sh north-america
   ```

2. **Check for typos** in region names (case-sensitive)

#### "Failed to download POLY file" (Exit code 8)
**Symptoms**: Download fails specifically for `.poly` file

**Solutions**:
1. **Verify POLY file exists**:
   ```bash
   curl -I http://download.geofabrik.de/north-america/us/california.poly
   ```

2. **Check for redirect**:
   ```bash
   curl -L http://download.geofabrik.de/north-america/us/california.poly
   ```

#### "Failed to download KML file"
**Symptoms**: KML download fails while OSM and POLY succeed

**Solutions**:
1. **Some regions may not have KML files** - this is rare but possible
2. **Check Geofabrik directly**: Visit the website and verify KML availability
3. **Continue without KML** (modify script temporarily if needed)

### Memory Issues

#### "OutOfMemoryError" during GraphHopper import
**Symptoms**: 
```
Exception in thread "main" java.lang.OutOfMemoryError: Java heap space
```

**The tool now predicts memory needs and warns you beforehand, but if you still get this error:**

**Solutions**:
1. **Use manual memory override**:
   ```bash
   # Set specific memory allocation (example: 16GB)
   VNS_MEMORY_GB=16 ./run.sh us/california
   
   # For very large regions like US-South
   VNS_MEMORY_GB=20 ./run.sh us-south
   ```

2. **Check system memory availability**:
   ```bash
   # Check total system RAM
   free -h
   
   # The tool needs significant RAM for large regions:
   # - Small (Delaware): 1-2GB
   # - Medium (Great Britain): 4-6GB  
   # - Large (Germany): 8-12GB
   # - Very Large (US-South): 16-20GB+
   ```

3. **Process smaller regions instead**:
   ```bash
   # Instead of processing us-south (requires 16GB+)
   ./run.sh us/florida
   ./run.sh us/georgia  
   ./run.sh us/alabama
   # Process individual states that need 2-6GB each
   ```

4. **Enable verbose logging for debugging**:
   ```bash
   VERBOSE_LOG=true ./run.sh us/delaware
   # Check logs/ folder for detailed memory analysis
   ```

#### Docker container killed due to memory
**Symptoms**: Container exits unexpectedly, `docker logs` shows killed process

**Solutions**:
1. **Increase Docker memory limit** (Docker Desktop):
   - Settings → Resources → Memory → Increase to match region needs
   - Small regions: 4GB Docker limit
   - Large regions: 16GB+ Docker limit

2. **The tool now warns you about insufficient memory before starting**:
   ```bash
   # Tool output example:
   ❌ INSUFFICIENT MEMORY WARNING!
   • Need: 16GB
   • Have: 8GB total
   • This WILL fail with out-of-memory errors
   ```

3. **Use manual memory override for testing**:
   ```bash
   # Force lower memory usage (may fail, but worth trying)
   VNS_MEMORY_GB=6 ./run.sh us/california
   ```

4. **Use swap space** (Linux - helps but slower):
   ```bash
   sudo swapon --show  # Check current swap
   sudo fallocate -l 8G /swapfile  # Create large swap
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```

### GraphHopper Issues

#### "GraphHopper import failed"
**Symptoms**: Import process exits with non-zero code

**Solutions**:
1. **Check input file integrity**:
   ```bash
   file cache/california.osm.pbf
   # Should show: "Protocol Buffer Binary Format"
   ```

2. **Verify GraphHopper build**:
   ```bash
   docker run --rm -it ghcr.io/joshuafuller/atak-vns-offline-routing-generator:latest bash
   # Inside container:
   ls -la graphhopper/web/target/
   # Should show: graphhopper-web-1.0-SNAPSHOT.jar
   ```

3. **Run with debug output**:
   ```bash
   docker run --rm \
     -v "$(pwd)/output:/app/output" \
     -v "$(pwd)/cache:/app/cache" \
     ghcr.io/joshuafuller/atak-vns-offline-routing-generator:latest \
     bash -x ./generate-data.sh us/delaware
   ```

4. **Clean rebuild**:
   ```bash
   docker build --no-cache -t local-vns:latest .
   ```

#### "Properties file not found"
**Symptoms**: `Error: Properties file not found in [region]. GraphHopper import may have failed.`

**Solutions**:
1. **This indicates GraphHopper import failed silently**
2. **Check available disk space**:
   ```bash
   df -h
   ```
3. **Verify OSM file is not corrupted**:
   ```bash
   file cache/california.osm.pbf
   # Should show proper PBF format
   ```

### File System Issues

#### "Permission denied" accessing output directory
**Symptoms**: Cannot write to `./output/` directory

**Solutions**:
1. **Check directory permissions**:
   ```bash
   ls -la output/
   chmod 755 output/
   ```

2. **Docker volume permissions** (Linux):
   ```bash
   # Ensure output directory is writable
   sudo chown -R $USER:$USER output/ cache/
   ```

3. **SELinux issues** (RHEL/CentOS):
   ```bash
   sudo setsebool -P container_manage_cgroup 1
   ```

#### "No space left on device"
**Symptoms**: Disk full during processing

**Solutions**:
1. **Check available space**:
   ```bash
   df -h
   du -sh output/ cache/
   ```

2. **Clean up temporary files**:
   ```bash
   docker system prune -f
   rm -f output/*.osm.pbf  # Remove any stray temporary files
   ```

3. **Use different storage location**:
   ```bash
   # Use external drive with more space
   mkdir /mnt/external/vns-output
   ln -sf /mnt/external/vns-output output
   ```

### VNS Integration Issues

#### VNS plugin doesn't detect routing data
**Symptoms**: Generated folders don't appear in VNS interface

**Solutions**:
1. **Verify exact file path**:
   ```
   /storage/emulated/0/atak/tools/VNS/GH/delaware/
   ```
   - Must be exact path, case-sensitive
   - Use Android file explorer to verify

2. **Check all required files are present**:
   ```bash
   # All these files must exist:
   delaware.kml
   delaware.poly  
   delaware.timestamp
   timestamp
   edges
   geometry
   location_index
   nodes
   nodes_ch_car
   properties
   shortcuts_car
   string_index_keys
   string_index_vals
   ```

3. **Restart ATAK completely**:
   - Force close ATAK app
   - Restart device if necessary
   - VNS scans for data on startup

4. **Verify file sizes**:
   ```bash
   # Files should have reasonable sizes (not 0 bytes)
   ls -la output/delaware/
   ```

#### Routing requests fail in VNS
**Symptoms**: VNS detects data but routing fails

**Solutions**:
1. **GraphHopper version mismatch**:
   - Ensure using exactly GraphHopper v1.0
   - Newer versions are incompatible

2. **Corrupted graph data**:
   - Regenerate the region data
   - Verify output files are not truncated

3. **Android storage permissions**:
   - Ensure ATAK has storage permissions
   - Check Android security settings

### Network Issues

#### Slow downloads from Geofabrik
**Symptoms**: Very slow download speeds

**Solutions**:
1. **Use mirrors if available**:
   - Check Geofabrik website for mirror servers
   - Consider using torrent downloads for large regions

2. **Download outside Docker first**:
   ```bash
   # Pre-download large files
   wget http://download.geofabrik.de/north-america/us/california-latest.osm.pbf
   # Then modify script to use local file
   ```

3. **Resume interrupted downloads**:
   ```bash
   wget -c http://download.geofabrik.de/north-america/us/california-latest.osm.pbf
   ```

### Logging and Debugging

#### New Comprehensive Logging System
**The tool now automatically logs detailed information for debugging:**

**Automatic Logging:**
```bash
# Every run creates a detailed log
./run.sh us/delaware

# Check the logs
ls -la logs/
# Shows: vns-generation-20250827_071113.log
```

**Verbose Logging** (for detailed system info):
```bash
VERBOSE_LOG=true ./run.sh us/delaware
# Includes detailed system metrics, memory analysis, benchmark results
```

**What's in the logs:**
- Memory predictions vs actual usage
- Processing time predictions vs actual time
- System benchmark results
- Hardware compatibility analysis
- Error details for issue reporting

**Share logs when reporting issues** - they contain all the technical details needed for troubleshooting.

## Advanced Debugging

### Enable Verbose Logging
```bash
# Use the built-in verbose logging system
VERBOSE_LOG=true ./run.sh us/delaware

# For Docker direct usage
docker run --rm \
  -v "$(pwd)/output:/app/output" \
  -v "$(pwd)/cache:/app/cache" \
  -v "$(pwd)/logs:/app/logs" \
  -e VERBOSE_LOG=true \
  ghcr.io/joshuafuller/atak-vns-offline-routing-generator:latest \
  ./generate-data.sh us/delaware

# Check logs after completion
cat logs/vns-generation-*.log
```

### Inspect Docker Container
```bash
# Run container interactively
docker run --rm -it \
  -v "$(pwd)/output:/app/output" \
  -v "$(pwd)/cache:/app/cache" \
  ghcr.io/joshuafuller/atak-vns-offline-routing-generator:latest bash

# Manual step-by-step execution
cd /app
./generate-data.sh us/delaware
```

### Validate Generated Files
```bash
# Check GraphHopper files
file output/delaware/edges
file output/delaware/nodes

# Verify ZIP integrity
unzip -t output/delaware.zip

# Check file sizes
du -sh output/delaware/*
```

### Monitor Resource Usage
```bash
# While processing is running
docker stats

# System resource monitoring
top
htop
iotop
```

## Getting Help

### Region Discovery
The tool now includes a built-in region lister to help you find the correct region paths:

```bash
# List all available regions organized by continent
./list-regions.sh

# This will show you the exact commands to run for each region
# Example output:
#   📍 North America:
#     Delaware                    → ./run.sh us/delaware
#     California                  → ./run.sh us/california
#     Germany                     → ./run.sh europe/germany
```

### Log Collection
When reporting issues, the new logging system makes this much easier:

1. **Automatic Log Files** (most important):
   ```bash
   # Logs are automatically created in logs/ folder
   ls -la logs/
   
   # Share the relevant log file when reporting issues
   cat logs/vns-generation-20250827_071113.log
   ```

2. **For Verbose Details**:
   ```bash
   # Run with verbose logging to get detailed system info
   VERBOSE_LOG=true ./run.sh us/delaware
   
   # Then share the verbose log file
   ```

3. **System Information** (if needed):
   ```bash
   uname -a
   docker --version
   free -h
   df -h
   ```

4. **File Listing**:
   ```bash
   ls -la output/
   ls -la output/delaware/ 2>/dev/null || echo "No delaware folder"
   ls -la cache/
   ```

### Support Channels
- **GitHub Issues**: Primary support channel
- **ATAK Documentation**: For VNS-specific questions
- **GraphHopper Documentation**: For routing engine issues
- **Docker Documentation**: For container issues
- **Region Discovery**: Use `./list-regions.sh` to see all available regions

### Creating Minimal Reproductions
1. **Test with Malta** (smallest region: `europe/malta`)
2. **Include complete error output**  
3. **Specify exact system configuration**
4. **List any modifications made to scripts**