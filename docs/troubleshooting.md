# Troubleshooting Guide

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
   sudo ./run.sh california
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
- Incorrect state name format

**Solutions**:
1. **Verify internet connection**:
   ```bash
   ping download.geofabrik.de
   ```

2. **Check state name format**:
   - Use lowercase with dashes: `new-york` not `New York`
   - Valid examples: `california`, `north-carolina`, `west-virginia`

3. **Manual verification**:
   ```bash
   # Test URL manually
   wget -q --spider http://download.geofabrik.de/north-america/us/california-latest.osm.pbf
   echo $?  # Should return 0 if successful
   ```

4. **Retry after delay**:
   ```bash
   # Wait and retry
   sleep 60
   ./run.sh california
   ```

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
1. **Some states may not have KML files** - this is rare but possible
2. **Check Geofabrik directly**: Visit the website and verify KML availability
3. **Continue without KML** (modify script temporarily if needed)

### Memory Issues

#### "OutOfMemoryError" during GraphHopper import
**Symptoms**: 
```
Exception in thread "main" java.lang.OutOfMemoryError: Java heap space
```

**Solutions**:
1. **Increase available system RAM**:
   - Close other applications
   - Ensure 8GB+ total system RAM for large states

2. **Modify memory allocation**:
   ```bash
   # Edit generate-data.sh and increase heap size
   sed -i 's/-Xmx4096m -Xms4096m/-Xmx6144m -Xms6144m/' generate-data.sh
   ```

3. **Process smaller states first**:
   - Test with Delaware (~10MB output)
   - Gradually work up to larger states

4. **Monitor system resources**:
   ```bash
   # Check available memory
   free -h
   # Monitor Docker container usage
   docker stats
   ```

#### Docker container killed due to memory
**Symptoms**: Container exits unexpectedly, `docker logs` shows killed process

**Solutions**:
1. **Increase Docker memory limit** (Docker Desktop):
   - Settings → Resources → Memory → Increase limit

2. **Use swap space** (Linux):
   ```bash
   sudo swapon --show  # Check current swap
   sudo fallocate -l 4G /swapfile  # Create swap if needed
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
   file output/california-latest.osm.pbf
   # Should show: "Protocol Buffer Binary Format"
   ```

2. **Verify GraphHopper build**:
   ```bash
   docker run --rm -it vns-data-generator:1.0 bash
   # Inside container:
   ls -la graphhopper/web/target/
   # Should show: graphhopper-web-1.0-SNAPSHOT.jar
   ```

3. **Run with debug output**:
   ```bash
   docker run --rm -v "$(pwd)/output:/app/output" \
     vns-data-generator:1.0 bash -x ./generate-data.sh california
   ```

4. **Clean rebuild**:
   ```bash
   docker build --no-cache -t vns-data-generator:1.0 .
   ```

#### "Properties file not found"
**Symptoms**: `Error: Properties file not found in [state]. GraphHopper import may have failed.`

**Solutions**:
1. **This indicates GraphHopper import failed silently**
2. **Check available disk space**:
   ```bash
   df -h
   ```
3. **Verify OSM file is not corrupted**:
   ```bash
   osmium fileinfo output/california-latest.osm.pbf
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
   sudo chown -R $USER:$USER output/
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
   du -sh output/
   ```

2. **Clean up temporary files**:
   ```bash
   docker system prune -f
   rm -f output/*.osm.pbf  # Remove downloaded files
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
   /storage/emulated/0/atak/tools/VNS/GH/california/
   ```
   - Must be exact path, case-sensitive
   - Use Android file explorer to verify

2. **Check all required files are present**:
   ```bash
   # All these files must exist:
   california.kml
   california.poly  
   california.timestamp
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
   ls -la output/california/
   ```

#### Routing requests fail in VNS
**Symptoms**: VNS detects data but routing fails

**Solutions**:
1. **GraphHopper version mismatch**:
   - Ensure using exactly GraphHopper v1.0
   - Newer versions are incompatible

2. **Corrupted graph data**:
   - Regenerate the state data
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
   - Consider using torrent downloads for large states

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

## Advanced Debugging

### Enable Verbose Logging
```bash
# Debug the entire process
docker run --rm -v "$(pwd)/output:/app/output" \
  vns-data-generator:1.0 bash -x ./generate-data.sh california 2>&1 | tee debug.log
```

### Inspect Docker Container
```bash
# Run container interactively
docker run --rm -it -v "$(pwd)/output:/app/output" \
  vns-data-generator:1.0 bash

# Manual step-by-step execution
cd /app
./generate-data.sh california
```

### Validate Generated Files
```bash
# Check GraphHopper files
file output/california/edges
file output/california/nodes

# Verify ZIP integrity
unzip -t output/california.zip

# Check file sizes
du -sh output/california/*
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

### Log Collection
When reporting issues, include:

1. **System Information**:
   ```bash
   uname -a
   docker --version
   free -h
   df -h
   ```

2. **Error Output**:
   ```bash
   ./run.sh california 2>&1 | tee error.log
   ```

3. **File Listing**:
   ```bash
   ls -la output/
   ls -la output/california/ 2>/dev/null || echo "No california folder"
   ```

### Support Channels
- **GitHub Issues**: Primary support channel
- **ATAK Documentation**: For VNS-specific questions
- **GraphHopper Documentation**: For routing engine issues
- **Docker Documentation**: For container issues

### Creating Minimal Reproductions
1. **Test with Delaware** (smallest state)
2. **Include complete error output**  
3. **Specify exact system configuration**
4. **List any modifications made to scripts**