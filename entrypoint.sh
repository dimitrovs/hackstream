#!/bin/bash
set -e

# P0-1: Entrypoint to start xpra and launch an application.
# This script starts a virtual framebuffer, then launches an xpra server
# that runs a given command (e.g., a browser).

# Define the display to use and export it for other processes
DISPLAY_NUM=100
export DISPLAY=:${DISPLAY_NUM}

echo "Starting Xvfb on display ${DISPLAY}"
# Start Xvfb (X Virtual Framebuffer) in the background.
# -screen 0 1920x1080x24: Creates a virtual screen with a resolution of 1920x1080 and 24-bit color.
# +extension RANDR: Enables the RANDR extension for display resizing.
# The process is backgrounded with '&'.
Xvfb ${DISPLAY} -screen 0 720x720x24 &
XVFB_PID=$!

# Setup trap to ensure Xvfb is killed on exit or signal
cleanup() {
    echo "Stopping Xvfb (PID $XVFB_PID)"
    kill $XVFB_PID 2>/dev/null || true
}
trap cleanup EXIT INT TERM
# Wait for Xvfb to be ready by polling for the X11 socket file.
for i in {1..20}; do
    if [ -e /tmp/.X11-unix/X${DISPLAY_NUM} ]; then
        break
    fi
    sleep 0.5
done
if [ ! -e /tmp/.X11-unix/X${DISPLAY_NUM} ]; then
    echo "Error: Xvfb did not create the X11 socket file in time." >&2
    exit 1
fi

echo "Starting xpra server on display ${DISPLAY} and launching command: $*"
# Use 'exec' to replace the shell process with the xpra process. This means
# xpra becomes PID 1 in the container (or at least the main process),
# allowing it to receive signals like SIGTERM from 'docker stop' directly.
#
# --no-daemon: Run xpra in the foreground. Essential for containerized services.
# --bind-tcp: Listen on all network interfaces on the specified port.
# --html=on: Enable the HTML5 client for browser-based access.
# --start-child: The command to execute within the xpra session. "$*" passes the CMD from Dockerfile as a single string.
# --exit-with-children: Terminate the xpra server when the child process (the browser) exits.
# Other flags disable features not needed for this simple use case to reduce overhead.
exec xpra start ${DISPLAY} \
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
    --start-child="$*"
