#!/bin/bash

# Ask for the daemon name
read -p "Enter the daemon name (e.g., realichaind): " daemon_name

# Confirm the input
echo "You entered '${daemon_name}'. Do you want to proceed? (y/n)"
read -r confirmation

if [[ "$confirmation" != "y" ]]; then
  echo "Operation canceled."
  exit 1
fi

# Remove the trailing 'd' from the daemon name for use in PIDFile
base_name="${daemon_name%d}"

# Create the service file
cat <<EOL > /etc/systemd/system/${daemon_name}.service
# Install this in /etc/systemd/system/
# See below for more details and options
# Then run the following to always start:
# systemctl enable ${daemon_name}
#
# and the following to start immediately:
# systemctl start ${daemon_name}

[Unit]
Description=${daemon_name^} daemon
After=network.target

[Service]
ExecStart=${daemon_name}

# Process management
####################

Type=forking
PIDFile=/root/.${base_name}/${base_name}.pid
Restart=on-failure

# Directory creation and permissions
####################################

# Run as root:root or <youruser>
User=root
Group=root

# Hardening measures
####################

# Provide a private /tmp and /var/tmp.
PrivateTmp=true

# Use a new /dev namespace only populated with API pseudo devices
# such as /dev/null, /dev/zero and /dev/random.
PrivateDevices=true

# Deny the creation of writable and executable memory mappings.
MemoryDenyWriteExecute=true

[Install]
WantedBy=multi-user.target
EOL

# Inform the user
echo "Service file for ${daemon_name} created at /etc/systemd/system/${daemon_name}.service"

# Reload systemd daemon to recognize the new service
systemctl daemon-reload

# Enable the service to start on boot
systemctl enable ${daemon_name}

# Inform the user the service has been enabled
echo "${daemon_name} service has been enabled."

# Optionally, you can uncomment the line below to start the service immediately
# systemctl start ${daemon_name}
