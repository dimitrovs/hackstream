#!/bin/bash
set -e

# P0-1: Entrypoint to start xpra and launch an application.
# This script starts a virtual framebuffer, then launches an xpra server
# that runs a given command (e.g., a browser).

# Set a writable runtime dir for the user
export XDG_RUNTIME_DIR=/home/appuser/.xdg_runtime_dir

# Define the display to use
DISPLAY_NUM=100
DISPLAY=:${DISPLAY_NUM}

# The xvfb command xpra should run.
# xpra will substitute %d for the display number.
XVFB_CMD="/usr/bin/Xvfb +extension RANDR -screen 0 720x720x24 -displayfd 10"

echo "Starting xpra server on display ${DISPLAY} and launching command: $*"
# Use 'exec' to replace the shell process with the xpra process.
# Let xpra manage Xvfb for a more robust startup.
# --no-input-devices: Fixes issues with uinput device permissions.
exec xpra start ${DISPLAY} \
    --xvfb="${XVFB_CMD}" \
    --bind-tcp=0.0.0.0:14500 \
    --html=on \
    --no-daemon \
    --pulseaudio=no \
    --notifications=no \
    --system-tray=no \
    --bell=no \
    --webcam=no \
    --microphone=no \
    --speaker=no \
    --clipboard=yes \
    --exit-with-children \
    --no-input-devices \
    --start-child="$*"
