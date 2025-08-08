#!/bin/bash
set -e # exit if any command fails

# --- Configuration ---
# Set the remote user and host IP address.
# IMPORTANT: Ensure you have set up SSH key-based authentication for this user.
# For example, run: ssh-copy-id user@192.168.1.83
REMOTE_USER="user"
REMOTE_HOST_IP="192.168.1.83"

# Set the remote directory where the project will be deployed.
# This directory will be created if it doesn't exist.
REMOTE_DIR="/home/${REMOTE_USER}/hackstream"

# --- Script ---
REMOTE_HOST="${REMOTE_USER}@${REMOTE_HOST_IP}"

echo "Deploying to ${REMOTE_HOST}..."

# Create the remote directory if it doesn't exist
ssh ${REMOTE_HOST} "mkdir -p ${REMOTE_DIR}"

# Use rsync to synchronize the project directory with the remote directory.
# This is more efficient than copying everything each time.
# --delete: deletes files on the remote that are not in the source.
rsync -avz --progress \
    --exclude='.git/' \
    --exclude='.pytest_cache/' \
    --exclude='__pycache__/' \
    --exclude='*.pyc' \
    --exclude='*.pyo' \
    --exclude='*.pyd' \
    --exclude='.env*' \
    --exclude='*.log' \
    --exclude='.vscode/' \
    --exclude='.idea/' \
    --exclude='venv/' \
    --exclude='.venv/' \
    --exclude='env/' \
    --exclude='*.egg-info/' \
    --delete \
    . ${REMOTE_HOST}:${REMOTE_DIR}

# Check if the rsync command was successful
if [ $? -eq 0 ]; then
    echo "✅ Files synchronized successfully."
    echo "🚀 Building and starting the application on the remote host..."

    # Use ssh to execute docker-compose commands on the remote server.
    # - `docker compose down`: Stops and removes the container if it's running.
    # - `docker compose up -d --build`: Builds the image and starts the container in detached mode.
    ssh ${REMOTE_HOST} "cd ${REMOTE_DIR} && sudo docker compose down && sudo docker compose up -d --build"

    echo "✅ Application deployed successfully!"
    echo "➡️  xpra server should be running on ${REMOTE_HOST_IP}:14500"
    echo "➡️  You can now attach to it from a client on the same LAN."
else
    echo "❌ rsync failed. Deployment aborted."
    exit 1
fi
