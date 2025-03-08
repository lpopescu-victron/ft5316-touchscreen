FT5316 Touchscreen Driver for Raspberry Pi 5
This repository provides a setup script for configuring the FT5316 touchscreen on a Raspberry Pi 5. The script installs the required packages, configures the touchscreen driver, and creates a systemd service to ensure the driver runs at boot.

Prerequisites
Before running the installation script, please perform the following steps using raspi-config:

Enable I2C:

Open a terminal and run sudo raspi-config.
Navigate to Interface Options and enable I2C.
Switch from Wayland to X:

In raspi-config, select the option to switch from Wayland to X (this is necessary for the touchscreen to work properly).
Reboot:

After applying the changes, reboot your Raspberry Pi:
bash
sudo reboot
Installation
After your Raspberry Pi has rebooted, install the touchscreen driver by running the following command:

bash
wget https://raw.githubusercontent.com/lpopescu-victron/ft5316-touchscreen/main/setup_touchscreen.sh && chmod +x setup_touchscreen.sh && ./setup_touchscreen.sh
This command will:

Download the setup_touchscreen.sh script from GitHub.
Make the script executable.
Run the script, which will update your system, install prerequisites, configure the touchscreen driver, create a systemd service, and reboot your system again.
Post Installation
Once the installation script has completed and your Raspberry Pi has rebooted, the FT5316 touchscreen driver will automatically start at boot. If you need to troubleshoot or restart the service manually, use the following commands:

Check Service Status:

bash
sudo systemctl status ft5316-touchscreen.service
Restart Service:

bash

sudo systemctl restart ft5316-touchscreen.service
Troubleshooting
I2C Issues: Ensure that I2C is enabled and that your touchscreen is properly connected.
Display Issues: Verify that you have switched from Wayland to X, as the driver requires an X-based display server.
Logs: Check the system logs for errors related to the service:
bash
journalctl -u ft5316-touchscreen.service
