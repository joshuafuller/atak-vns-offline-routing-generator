# ==============================================================================
# VNS Offline Data Generator - Dockerfile
#
# Description:
# This Dockerfile creates a self-contained environment with all the necessary
# dependencies to build VNS-compatible offline routing files. It ensures that
# the correct versions of all tools are used, eliminating configuration issues
# on the user's machine.
# ==============================================================================

# Maintained Java 11 runtime, pinned for reproducible builds.
FROM eclipse-temurin:25-jre-jammy@sha256:25777acfabf927084b7ef46d8bc786b6203c8c344f56541054238b8c4fe73db9

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
# - wget: To download map data from Geofabrik
# - zip: To create compressed archives for easy transfer
# - jq: For JSON parsing and region URL extraction
RUN apt-get update && apt-get install -y \
    wget \
    zip \
    jq \
    --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

# Download and verify the pinned GraphHopper 1.0 JAR from Maven Central.
ARG GRAPHHOPPER_WEB_SHA256=9269d56458fcb343adf8f6f3da6e1a2daa9a09de2dc85eaef7e5e64b7af4d9ca
RUN mkdir -p graphhopper && \
    wget -O graphhopper/graphhopper-web-1.0.jar \
    "https://repo1.maven.org/maven2/com/graphhopper/graphhopper-web/1.0/graphhopper-web-1.0.jar" && \
    echo "${GRAPHHOPPER_WEB_SHA256}  graphhopper/graphhopper-web-1.0.jar" | sha256sum -c -

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

