# ==============================================================================
# VNS Offline Data Generator - Dockerfile
#
# Description:
# This Dockerfile creates a self-contained environment with all the necessary
# dependencies to build VNS-compatible offline routing files. It ensures that
# the correct versions of all tools are used, eliminating configuration issues
# on the user's machine.
# ==============================================================================

# Use OpenJDK 8 JRE for minimal footprint
FROM openjdk:11-jre-slim

# Container metadata labels
LABEL org.opencontainers.image.title="ATAK VNS Offline Routing Generator"
LABEL org.opencontainers.image.description="Automated generation of VNS-compatible offline routing files for ATAK. Creates GraphHopper routing data from OpenStreetMap data for use in disconnected environments."
LABEL org.opencontainers.image.vendor="ATAK Community"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.url="https://github.com/joshuafuller/atak-vns-offline-routing-generator"
LABEL org.opencontainers.image.source="https://github.com/joshuafuller/atak-vns-offline-routing-generator"
LABEL org.opencontainers.image.documentation="https://github.com/joshuafuller/atak-vns-offline-routing-generator/blob/main/README.md"

# Set the working directory inside the container
WORKDIR /app

# Install only runtime dependencies (no maven needed in final image)
# - git: To clone repositories if needed
# - wget: To download map data from Geofabrik  
# - zip: To create compressed archives for easy transfer
# - jq: For JSON parsing and region URL extraction
RUN apt-get update && apt-get install -y \
    git \
    wget \
    zip \
    jq \
    --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

# Download pre-built GraphHopper 1.0 JARs from Maven Central
# This eliminates the need to compile from source, significantly reducing build time
RUN mkdir -p graphhopper && \
    wget -O graphhopper/graphhopper-web-1.0.jar \
    "https://repo1.maven.org/maven2/com/graphhopper/graphhopper-web/1.0/graphhopper-web-1.0.jar" && \
    wget -O graphhopper/graphhopper-core-1.0.jar \
    "https://repo1.maven.org/maven2/com/graphhopper/graphhopper-core/1.0/graphhopper-core-1.0.jar"

# Create minimal GraphHopper config file for import operations
RUN echo 'graphhopper:\n\
  datareader.file: ""\n\
  graph.location: graph-cache\n\
  graph.flag_encoders: car\n\
\n\
  profiles:\n\
    - name: car\n\
      vehicle: car\n\
      weighting: fastest\n\
\n\
  profiles_ch:\n\
    - profile: car\n\
\n\
server:\n\
  type: simple\n\
  connector:\n\
    type: http\n\
    port: 8989' > graphhopper/config-example.yml

# Copy the scripts into the container's working directory
COPY generate-data.sh .
COPY list-regions.sh .

# Make the scripts executable
RUN chmod +x generate-data.sh list-regions.sh

# Set the default command to execute when the container starts.
# This allows the run.sh script to pass the state name directly.
CMD ["./generate-data.sh"]

