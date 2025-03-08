# FT5316 Touchscreen Driver for Raspberry Pi 5

This repository provides a setup script for configuring the FT5316 touchscreen on a Raspberry Pi 5. The script installs the required packages, configures the touchscreen driver, and creates a systemd service to ensure the driver runs at boot.

## Prerequisites

Before running the installation script, please perform the following steps using `raspi-config`:

1. **Enable I2C:**
   - Open a terminal and run `sudo raspi-config`.
   - Navigate to **Interface Options** and enable **I2C**.
  
2. **Switch from Wayland to X:**
   - In `raspi-config`, select the option to switch from Wayland to X (this is necessary for the touchscreen to work properly).

3. **Reboot:**
   - After applying the changes, reboot your Raspberry Pi:
     ```bash
     sudo reboot
     ```

## Installation

After your Raspberry Pi has rebooted, install the touchscreen driver by running the following command:

```bash
wget https://raw.githubusercontent.com/lpopescu-victron/ft5316-touchscreen/main/setup_touchscreen.sh && chmod +x setup_touchscreen.sh && ./setup_touchscreen.sh
