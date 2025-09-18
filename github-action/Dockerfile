# Use the OWASP Noir base image from GitHub Container Registry
FROM ghcr.io/owasp-noir/noir:v0.24.0

# Install jq for JSON processing
USER 0
RUN apt-get update && apt-get install -y jq && rm -rf /var/lib/apt/lists/*

# Copy the entrypoint script into the container
COPY entrypoint.sh /entrypoint.sh

# Set the entrypoint to the script
ENTRYPOINT ["/bin/sh", "-l", "/entrypoint.sh"]
