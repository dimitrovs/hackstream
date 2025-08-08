# hackstream

HackStream enables ultra-low-RAM devices to run heavyweight desktop applications remotely. This repository contains the server-side component for running a browser in a Docker container and streaming it via xpra.

## Prerequisites

- A remote Linux server with Docker and Docker Compose installed.
- A local machine with `ssh` and `rsync` installed.
- A client machine on the same LAN as the server to test the connection.

## Deployment

This project includes a script to automate deployment to a remote server.

### 1. Configure SSH Access

The deployment script uses `ssh` and `rsync` to connect to your remote server. For a seamless experience, you should set up SSH key-based authentication to avoid typing a password.

If you don't have an SSH key pair yet, create one:
```bash
ssh-keygen -t rsa -b 4096
```

Then, copy your public key to the remote server. Replace `user` and `your_server_ip` with your actual remote username and server IP address.
```bash
ssh-copy-id user@your_server_ip
```
This command will append your public key to `~/.ssh/authorized_keys` on the remote server.

### 2. Configure the Deployment Script

The `deploy.sh` script is pre-configured with default values. Open the `deploy.sh` file and, if needed, edit the following variables at the top of the script to match your setup:

- `REMOTE_USER`: The username on your remote server (e.g., `ubuntu`).
- `REMOTE_HOST_IP`: The IP address of your remote server (e.g., `192.168.1.83`).

### 3. Run the Deployment Script

Once SSH access is configured, you can deploy the application by running the script from your local machine:

```bash
bash deploy.sh
```

The script will synchronize the project files to the remote server, build the Docker image, and start the `hackstream` container.

## Testing the Connection

After a successful deployment, the xpra server will be running and listening on port `14500` on your remote server. You can connect to it from a client machine on the same Local Area Network (LAN).

### 1. Install an Xpra Client

You need an xpra client on the machine you want to connect from. Installation instructions can be found on the [xpra website](https://xpra.org/trac/wiki/Download).

For Debian-based systems like Ubuntu, you can typically install it with:
```bash
sudo apt-get update
sudo apt-get install xpra
```

### 2. Attach to the Xpra Session

To connect to the remote session, use the `xpra attach` command. Replace `your_server_ip` with the IP address of your remote server.

```bash
xpra attach tcp:your_server_ip:14500
```

A new window should appear on your desktop, showing the application running inside the container (Chromium browser by default). You can now interact with the remote browser as if it were running locally.
