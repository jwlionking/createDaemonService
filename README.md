
# Systemd Service File Generator

This bash script creates and configures a systemd service file for a specified daemon. The script automates the process of generating a service file, enabling the service on boot, and offers configurable options for the daemon name and other relevant settings.

## Features

- Prompts for the daemon name.
- Automatically generates a systemd service file based on the daemon name.
- Removes the trailing `d` from the daemon name and uses it in the PIDFile path.
- Enables the service to start on boot after creation.
- Confirms user input before proceeding with file creation.

## Usage

1. **Clone the repository**:
   ```bash
   git clone https://github.com/yourusername/your-repo-name.git
   cd your-repo-name
   ```

2. **Make the script executable**:
   ```bash
   chmod +x create_service.sh
   ```

3. **Run the script**:
   ```bash
   sudo ./create_service.sh
   ```

4. **Follow the prompts**:
   - The script will ask for the daemon name.
   - It will then confirm the name with you before proceeding.
   - Once confirmed, it creates a service file in `/etc/systemd/system/`.

5. **Manage the service**:
   - After the script runs, the service is enabled on boot automatically.
   - Optionally, you can start the service immediately:
     ```bash
     sudo systemctl start <daemon_name>
     ```

## Example

For a daemon called `realichaind`, the script generates the following systemd service file:

```ini
[Unit]
Description=Realichaind daemon
After=network.target

[Service]
ExecStart=realichaind
Type=forking
PIDFile=/root/.realichain/realichain.pid
Restart=on-failure
User=root
Group=root
PrivateTmp=true
PrivateDevices=true
MemoryDenyWriteExecute=true

[Install]
WantedBy=multi-user.target
```

## Requirements

- A Linux system running systemd (e.g., Ubuntu, Debian, CentOS).
- `bash` installed (typically default on Linux systems).
- Root privileges to create service files in `/etc/systemd/system/`.

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/your-repo-name.git
   ```

2. Change to the repository directory:
   ```bash
   cd your-repo-name
   ```

3. Make the script executable:
   ```bash
   chmod +x create_service.sh
   ```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributions

Contributions are welcome! Please submit a pull request or create an issue if you have any suggestions or improvements.

## Author

- **Your Name** - [yourusername](https://github.com/yourusername)
