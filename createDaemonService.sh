#!/bin/bash

# Script to create a systemd service for a cryptocurrency daemon

# Function to validate command existence
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Ask for the daemon name
read -p "Enter the daemon name (e.g., evrmored, bitcoind): " daemon_name

# Validate daemon name (basic check for non-empty and no spaces)
if [[ -z "$daemon_name" || "$daemon_name" =~ \  ]]; then
  echo "Error: Daemon name cannot be empty or contain spaces."
  exit 1
fi

# Confirm the input
echo "You entered '${daemon_name}'. Do you want to proceed? (y/n)"
read -r confirmation
if [[ "$confirmation" != "y" ]]; then
  echo "Operation canceled."
  exit 1
fi

# Remove the trailing 'd' from the daemon name for use in directories and PID file
base_name="${daemon_name%d}"

# Ask for the daemon binary path
read -p "Enter the full path to the daemon binary (default: /usr/bin/${daemon_name}): " daemon_path
daemon_path=${daemon_path:-/usr/bin/${daemon_name}}

# Validate daemon binary existence
if ! [ -x "$daemon_path" ]; then
  echo "Error: Daemon binary '${daemon_path}' not found or not executable."
  exit 1
fi

# Ask for data directory
read -p "Enter the data directory (default: /var/lib/${base_name}): " data_dir
data_dir=${data_dir:-/var/lib/${base_name}}

# Ask for configuration directory
read -p "Enter the configuration directory (default: /etc/${base_name}): " conf_dir
conf_dir=${conf_dir:-/etc/${base_name}}

# Create a dedicated user and group if they don’t exist
user_name="${base_name}"
if ! id "$user_name" >/dev/null 2>&1; then
  echo "Creating user and group '${user_name}'..."
  useradd -r -s /sbin/nologin -m -d "$data_dir" "$user_name"
fi

# Create and set permissions for data and configuration directories
echo "Setting up directories: $data_dir, $conf_dir"
mkdir -p "$data_dir" "$conf_dir"
chown -R "$user_name:$user_name" "$data_dir" "$conf_dir"
chmod -R 0710 "$data_dir" "$conf_dir"

# Create the configuration file if it doesn’t exist
conf_file="${conf_dir}/${base_name}.conf"
if [ ! -f "$conf_file" ]; then
  echo "Creating default configuration file at $conf_file..."
  cat <<EOL > "$conf_file"
# ${base_name}.conf
server=1
rpcuser=${base_name}user
rpcpassword=$(openssl rand -base64 32)
rpcbind=127.0.0.1
datadir=${data_dir}
EOL
  chown "$user_name:$user_name" "$conf_file"
  chmod 0640 "$conf_file"
fi

# Create the systemd service file
service_file="/etc/systemd/system/${daemon_name}.service"
echo "Creating service file at $service_file..."

cat <<EOL > "$service_file"
# Systemd service file for ${daemon_name}
# Installed at /etc/systemd/system/${daemon_name}.service
# Enable with: systemctl enable ${daemon_name}
# Start with: systemctl start ${daemon_name}

[Unit]
Description=${daemon_name^} cryptocurrency daemon
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=${daemon_path} -conf=${conf_file} -datadir=${data_dir}

# Process management
Type=simple
Restart=on-failure
RestartSec=10
TimeoutStartSec=300
TimeoutStopSec=600

# Directory creation and permissions
User=${user_name}
Group=${user_name}
RuntimeDirectory=${base_name}
RuntimeDirectoryMode=0710
StateDirectory=${base_name}
StateDirectoryMode=0710
ConfigurationDirectory=${base_name}
ConfigurationDirectoryMode=0710

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true
MemoryDenyWriteExecute=true
RestrictAddressFamilies=AF_INET AF_INET6
RestrictNamespaces=true
SystemCallFilter=@system-service

[Install]
WantedBy=multi-user.target
EOL

# Set service file permissions
chmod 0644 "$service_file"

# Inform the user
echo "Service file for ${daemon_name} created at $service_file"

# Reload systemd daemon to recognize the new service
systemctl daemon-reload

# Enable the service to start on boot
systemctl enable "${daemon_name}"

# Inform the user the service has been enabled
echo "${daemon_name} service has been enabled."

# Ask if the user wants to start the service immediately
read -p "Do you want to start the ${daemon_name} service now? (y/n): " start_now
if [[ "$start_now" == "y" ]]; then
  systemctl start "${daemon_name}"
  echo "${daemon_name} service started. Check status with: systemctl status ${daemon_name}"
fi

# Provide debugging instructions
echo "To debug issues, check logs with: journalctl -u ${daemon_name} -f"
echo "Or run manually: sudo -u ${user_name} ${daemon_path} -conf=${conf_file} -datadir=${data_dir} -printtoconsole"

exit 0
