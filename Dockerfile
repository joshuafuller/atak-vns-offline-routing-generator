# ==============================================================================
# VNS Offline Data Generator - Dockerfile
#
# Description:
# This Dockerfile creates a self-contained environment with all the necessary
# dependencies to build VNS-compatible offline routing files. It ensures that
# the correct versions of all tools are used, eliminating configuration issues
# on the user's machine.
# ==============================================================================

# Multi-stage build for better caching and faster builds
FROM maven:3.8-openjdk-8-slim AS graphhopper-builder

# Install git in the builder stage
RUN apt-get update && apt-get install -y git --no-install-recommends && rm -rf /var/lib/apt/lists/*

# Set working directory for GraphHopper build
WORKDIR /build

# Clone the specific 1.0 branch of the GraphHopper repository.
# This is critical, as VNS is only compatible with this version.
RUN git clone --depth 1 --branch 1.0 https://github.com/graphhopper/graphhopper.git

# Build GraphHopper from source using Maven with optimizations
# Use parallel builds and skip tests for faster compilation
WORKDIR /build/graphhopper
RUN mvn -T 1C -DskipTests=true -Dmaven.javadoc.skip=true -Dmaven.source.skip=true clean install

# Final runtime stage - smaller image
FROM openjdk:8-jre-slim

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

# Copy built GraphHopper from builder stage
COPY --from=graphhopper-builder /build/graphhopper ./graphhopper

# Copy the scripts into the container's working directory
COPY generate-data.sh .
COPY list-regions.sh .

# Make the scripts executable
RUN chmod +x generate-data.sh list-regions.sh

# Set the default command to execute when the container starts.
# This allows the run.sh script to pass the state name directly.
CMD ["./generate-data.sh"]

