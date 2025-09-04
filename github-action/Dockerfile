# Use the OWASP Noir base image from GitHub Container Registry
FROM ghcr.io/owasp-noir/noir:latest

# Install jq for JSON processing
RUN apt-get update && apt-get install -y jq && rm -rf /var/lib/apt/lists/*

# Copy the entrypoint script into the container
COPY entrypoint.sh /entrypoint.sh

# Make the entrypoint script executable
RUN chmod 755 /entrypoint.sh

# Set the entrypoint to the script
ENTRYPOINT ["/entrypoint.sh"]