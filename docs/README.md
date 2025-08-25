# Documentation

This folder contains technical documentation for the ATAK VNS Offline Routing Generator.

## Documents

### 🚀 [Complete Setup Guide](setup.md)
**Step-by-step installation for new users**
- Docker installation for all platforms
- Getting the generator (ZIP vs Git)
- Your first routing data generation
- Testing and verification
- Common issues and solutions

### ⚙️ [Advanced Usage Guide](advanced-usage.md)
**Power user features and customization**
- Docker image options and custom builds
- Batch processing multiple regions
- Debug mode and troubleshooting techniques
- Performance tuning and optimization
- Integration best practices with VNS

### 🔄 [Updating](updating.md)
**How to update to the latest version**
- Quick git pull method
- Fresh download method
- Docker image updates
- What gets updated and what's preserved
- Update troubleshooting

### 📁 [Folder Structure](folder-structure.md)
**Understanding data organization and management**
- Project folder structure
- Cache folder (`cache/`) - OSM data storage
- Output folder (`output/`) - Generated routing files
- Data lifecycle and reuse
- File sizes by region type
- Cleanup and maintenance

### 📋 [Architecture](architecture.md)
**Technical architecture and system design**
- VNS plugin architecture overview
- GraphHopper integration details
- Data processing pipeline
- File structure requirements
- Performance characteristics
- Security considerations

### 🛠️ [Tech Stack](tech-stack.md)
**Complete technology stack documentation**
- Core technologies (Docker, Java, GraphHopper)
- Dependencies and versions
- Performance stack and requirements
- Security stack
- Development and monitoring tools
- Integration points and extensibility

### 🐛 [Troubleshooting](troubleshooting.md)
**Comprehensive troubleshooting guide**
- Docker issues and solutions
- Data download problems
- Memory and performance issues
- GraphHopper-specific problems
- File system and permission issues
- VNS integration troubleshooting
- Advanced debugging techniques

## Quick Navigation

### For New Users
- **Getting started**: Start with [Complete Setup Guide](setup.md)
- **Installation problems**: Check [Troubleshooting](troubleshooting.md)
- **Understanding output**: See [Folder Structure](folder-structure.md)

### For Power Users  
- **Advanced features**: Read [Advanced Usage Guide](advanced-usage.md)
- **Performance tuning**: See [Tech Stack - Performance Stack](tech-stack.md#performance-stack)
- **Custom builds**: Check [Advanced Usage - Docker Builds](advanced-usage.md#custom-docker-build)

### For Developers
- **Understanding the system**: Start with [Architecture](architecture.md)
- **Technology details**: Read [Tech Stack](tech-stack.md)
- **Debugging issues**: Use [Troubleshooting](troubleshooting.md)
- **Development setup**: See [Advanced Usage - Contributing](advanced-usage.md#contributing-to-development)

### For Operators
- **System requirements**: See [Tech Stack](tech-stack.md#resource-requirements-summary)
- **Monitoring**: [Tech Stack - Monitoring](tech-stack.md#monitoring-and-logging)
- **Security**: [Architecture - Security Considerations](architecture.md#security-considerations)
- **Batch processing**: [Advanced Usage - Batch Processing](advanced-usage.md#batch-processing)

## Contributing to Documentation

When contributing to this documentation:

1. **Keep it technical but accessible**
2. **Include code examples where helpful**
3. **Reference actual file locations and line numbers**
4. **Update cross-references when adding new content**
5. **Test all command examples before documenting**

## External References

- [ATAK Official Documentation](https://tak.gov/)
- [GraphHopper Documentation](https://docs.graphhopper.com/)
- [OpenStreetMap Wiki](https://wiki.openstreetmap.org/)
- [Geofabrik Download Server](https://download.geofabrik.de/)
- [Docker Documentation](https://docs.docker.com/)