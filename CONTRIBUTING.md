# Contributing to VNS Offline Data Generator

Thank you for your interest in contributing! This project helps ATAK users generate offline routing data for the VNS plugin.

## Development Setup

1. **Prerequisites:**
   - Docker installed and running
   - bash shell
   - jq (for JSON parsing): `sudo apt-get install jq`

2. **Clone and test:**
   ```bash
   git clone <repo-url>
   cd vns_offline_data_generator
   ./list-regions.sh  # Test region listing
   ./run.sh malta     # Test with small region
   ```

## Testing Guidelines

**Always test with small regions first:**
- ✅ **Good for testing**: `malta`, `us/delaware`, `us/rhode-island`
- ❌ **Avoid for testing**: `germany`, `us/california`, `us/texas`

**Quality checks before submitting:**
```bash
# Run shellcheck on all scripts
shellcheck *.sh scripts/*.sh

# Test functionality
./list-regions.sh | head -20
./run.sh malta
```

## Code Style

- Follow existing bash conventions
- Use shellcheck to validate scripts
- Quote variables to prevent word splitting
- Add comments for complex logic
- Keep functions focused and small

## Project Structure

```
vns_offline_data_generator/
├── run.sh              # Main user entry point
├── list-regions.sh     # Region listing utility  
├── generate-data.sh    # Core data processing (runs in Docker)
├── Dockerfile          # Container definition
├── scripts/            # Development/testing utilities
│   ├── validate-regions.sh
│   └── validate-all-regions.sh
└── docs/               # Documentation
```

## Submitting Changes

1. **Test thoroughly** with small regions
2. **Run quality checks** (shellcheck, syntax)
3. **Update documentation** if needed
4. **Keep commits focused** and descriptive

## Areas for Contribution

- **Bug fixes** in data processing
- **Documentation improvements**
- **New small test regions**
- **Performance optimizations**
- **Error handling improvements**

## Questions?

Open an issue for questions or suggestions. Please include:
- What you were trying to do
- What region you tested with
- Any error messages
- Your system info (OS, Docker version)