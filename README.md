# ATAK VNS Offline Routing Generator

**Creates backup navigation files for ATAK's VNS plugin - works without cell service**

[![Docker Pulls](https://img.shields.io/github/actions/workflow/status/joshuafuller/atak-vns-offline-routing-generator/build-and-publish.yml?style=flat-square&logo=docker&label=Docker%20Build)](https://github.com/joshuafuller/atak-vns-offline-routing-generator/pkgs/container/atak-vns-offline-routing-generator)
[![GitHub Release](https://img.shields.io/github/v/release/joshuafuller/atak-vns-offline-routing-generator?style=flat-square&logo=github)](https://github.com/joshuafuller/atak-vns-offline-routing-generator/releases/latest)
[![GitHub Downloads](https://img.shields.io/github/downloads/joshuafuller/atak-vns-offline-routing-generator/total?style=flat-square&logo=github)](https://github.com/joshuafuller/atak-vns-offline-routing-generator/releases)
[![GitHub Stars](https://img.shields.io/github/stars/joshuafuller/atak-vns-offline-routing-generator?style=flat-square&logo=github)](https://github.com/joshuafuller/atak-vns-offline-routing-generator/stargazers)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)
[![ATAK](https://img.shields.io/badge/ATAK-VNS%20Plugin-orange?style=flat-square)](https://tak.gov/plugins/vns)

## Why This Tool Matters

**Real-world example**: Your team is responding to a wildfire in remote mountains where cell towers are down. ATAK's normal navigation stops working, but with these offline files installed, navigation continues to work perfectly - no connectivity required.

**Perfect for emergency operations, search & rescue, and remote deployments where internet connectivity is unavailable or unreliable.**

## What You Need

- **Docker** - Free software that runs our map processing ([Download Docker](https://www.docker.com/get-started))
- **Internet connection** for downloading maps
- **No programming knowledge required** - just follow the steps

## Quick Start

### 🚀 Try it instantly (no setup required)
Want to test with Delaware routing data? Run this single command:

```bash
# Create output directories and generate Delaware routing data
mkdir -p output cache && docker run --rm \
  -v "$(pwd)/output:/app/output" \
  -v "$(pwd)/cache:/app/cache" \
  ghcr.io/joshuafuller/atak-vns-offline-routing-generator:latest \
  ./generate-data.sh us/delaware
```

**That's it!** No git clone, no repository download. You'll get:
- ✅ Delaware routing data in `./output/delaware/`
- ✅ Ready-to-transfer ZIP at `./output/delaware.zip`
- ✅ Cached data for future runs

**For other regions:**
```bash
# Generate data for Germany (replace us/delaware with any region)
docker run --rm \
  -v "$(pwd)/output:/app/output" \
  -v "$(pwd)/cache:/app/cache" \
  ghcr.io/joshuafuller/atak-vns-offline-routing-generator:latest \
  ./generate-data.sh germany
```

### 🛠️ Full setup (recommended for regular use)

#### 1. Get the Tool
[Download ZIP](https://github.com/joshuafuller/atak-vns-offline-routing-generator/archive/refs/heads/main.zip) → Extract to a folder

#### 2. Generate Routing Data
```bash
# Make scripts executable (Mac/Linux only)
chmod +x run.sh

# Generate data for any region
./run.sh us/california
./run.sh great-britain  
./run.sh germany

# Need help finding regions?
./list-regions.sh
```

### 3. Install on Your Device
1. Copy the generated ZIP file to your Android device
2. Extract and place folder at: `Internal Storage/atak/tools/VNS/GH/[region-name]/`
3. Restart ATAK

**That's it!** Navigation now works offline in that region.

## Processing Times

| Region Size | Example | Processing Time* | Memory Needed | Output Size |
|-------------|---------|------------------|---------------|-------------|
| Small | Malta | ~10 seconds | 1GB | 2.6 MB |
| Small | Delaware | ~15-30 seconds | 1GB | 9.1 MB |
| Medium | Great Britain | ~3-10 minutes | 6GB | 381 MB |
| Large | Germany | ~8-15 minutes | 8GB | 760 MB |
| Very Large | US-South | ~15-30 minutes | 16GB | 2.1 GB |

***Processing times vary significantly based on your hardware.** The tool automatically benchmarks your system and provides accurate time estimates before starting.

## Memory Requirements

**Large regions require significant RAM.** The tool now predicts memory needs and warns you beforehand:

- **Small regions** (Delaware, Malta): 1-2GB RAM sufficient
- **Medium regions** (Great Britain): 4-6GB RAM needed  
- **Large regions** (Germany, California): 8-12GB RAM needed
- **Very large regions** (US-South, Texas): 16-20GB+ RAM needed

**Manual Memory Override** (if automatic detection doesn't work):
```bash
VNS_MEMORY_GB=16 ./run.sh us/california
```

**Out of Memory?** See [Troubleshooting Guide](docs/troubleshooting.md#memory-issues) for solutions including processing smaller regions instead.

## Important Disclaimers

**VNS Plugin Required**: This tool only generates data files. You need the actual VNS plugin from TAK.gov:
- **Get VNS Plugin**: https://tak.gov/plugins/vns
- **Requires TAK.gov account** (free registration at tak.gov)  
- **Plugin support**: Contact TAK.gov - we are not affiliated with the VNS plugin makers

**Data Limitations**: Offline routing won't know about recent road closures, current traffic, or temporary restrictions. Use both online and offline routing together when possible.

## Documentation

**New to this tool?**
- [Complete Setup Guide](docs/setup.md) - Step-by-step installation from scratch
- [Troubleshooting](docs/troubleshooting.md) - Solutions to common problems

**Need technical details?**
- [Architecture](docs/architecture.md) - How it all works under the hood
- [Folder Structure](docs/folder-structure.md) - Understanding cache and output folders
- [Tech Stack](docs/tech-stack.md) - Complete technology documentation

**Keeping up to date?**
- [Updating Guide](docs/updating.md) - How to get the latest version

**Contributing?**
- [Versioning Guide](VERSIONING.md) - Commit message format for automatic releases

## Support

**For this data generator tool:**
- **Issues**: [Open a GitHub issue](https://github.com/joshuafuller/atak-vns-offline-routing-generator/issues) for problems generating routing files

**For VNS plugin issues (NOT our responsibility):**
- **VNS Plugin Support**: https://tak.gov
- **Plugin Installation/Usage**: Contact TAK.gov support

**We only support the data generation process, not the VNS plugin itself.**

## License

MIT License - see [LICENSE](LICENSE) file for details.

---

**Made with ❤️ for the ATAK community**