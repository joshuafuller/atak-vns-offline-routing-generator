# ==============================================================================
# VNS Offline Data Generator - Dockerfile
#
# Description:
# This Dockerfile creates a self-contained environment with all the necessary
# dependencies to build VNS-compatible offline routing files. It ensures that
# the correct versions of all tools are used, eliminating configuration issues
# on the user's machine.
# ==============================================================================

# Start from a base image that includes OpenJDK (Java Development Kit)
FROM openjdk:8-jdk-slim

# Set the working directory inside the container
WORKDIR /app

# Install necessary system packages
# - git: To clone the GraphHopper repository
# - wget: To download map data from Geofabrik
# - maven: To build the GraphHopper project from source
# - zip: To create compressed archives for easy transfer
RUN apt-get update && apt-get install -y \
    git \
    wget \
    maven \
    zip \
    --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

# Clone the specific 1.0 branch of the GraphHopper repository.
# This is critical, as VNS is only compatible with this version.
RUN git clone --depth 1 --branch 1.0 https://github.com/graphhopper/graphhopper.git

# Build GraphHopper from source using Maven.
# The build process downloads dependencies and compiles the Java code.
RUN cd graphhopper && mvn -DskipTests=true clean install

# Copy the data generation script into the container's working directory
COPY generate-data.sh .

# Make the script executable
RUN chmod +x generate-data.sh

# Set the default command to execute when the container starts.
# This allows the run.sh script to pass the state name directly.
CMD ["./generate-data.sh"]

