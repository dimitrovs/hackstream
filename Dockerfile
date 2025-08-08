# P0-1: As an engineer, I can build a Docker image that starts xpra and launches Chrome reliably.
# AC: Image builds on the target host; entrypoint starts xpra server and Chrome; readiness observable.

# Use a stable, slim base image
FROM debian:bullseye-slim

# Set environment variables to prevent interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies from the standard Debian repository.
# For this prototype, the version of xpra in bullseye is sufficient.
# - sudo: to allow user to run commands as root if needed
# - xvfb: X Virtual Framebuffer for running GUI apps in a headless environment
# - xpra: the core streaming server
# - chromium: the browser we want to run
# - pulseaudio: for audio support
# - fonts-*, ttf-*: essential fonts to render web pages correctly
RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo \
    xvfb \
    xpra \
    xauth \
    chromium \
    pulseaudio \
    fonts-noto-color-emoji \
    fonts-liberation \
    ttf-bitstream-vera \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user to run the application for better security
# The architecture doc specifies a "non-root with dedicated home directory"
RUN useradd --create-home --shell /bin/bash appuser \
    && adduser appuser sudo \
    && echo "appuser ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Set the working directory to the user's home
WORKDIR /home/appuser

# Copy the entrypoint script into the container
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# Make the entrypoint script executable
RUN chmod +x /usr/local/bin/entrypoint.sh

# Switch to the non-root user
USER appuser

# Set the entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Default command can be overridden, e.g., to launch a different app
CMD ["/usr/bin/chromium", "--no-sandbox", "--disable-gpu"]
