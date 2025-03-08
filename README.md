# FT5316 Touchscreen Driver for Raspberry Pi 5

This repository provides a setup script for configuring the FT5316 touchscreen on a Raspberry Pi 5. The script installs the required packages, configures the touchscreen driver, and creates a systemd service to ensure the driver runs at boot.

## Prerequisites

Before running the installation script, please perform the following steps using `raspi-config`:

1. **Enable I2C:**
   - Open a terminal and run:
     ```bash
     sudo raspi-config
     ```
   - Navigate to **Interface Options** and enable **I2C**.

2. **Switch from Wayland to X:**
   - If your Raspberry Pi is currently using the Wayland display server, you need to switch to the X11 (Xorg) display server for the touchscreen to work properly.
   - To do this, follow these steps:
     1. Open a terminal and run:
        ```bash
        sudo raspi-config
        ```
     2. Navigate to **Advanced Options** (or **System Options**, depending on your Raspberry Pi OS version).
     3. Look for the option to switch from Wayland to X. This option might be labeled as **"Disable Wayland"** or **"Force Xorg"**. (The exact wording may vary by OS version.)
     4. Select the option to disable Wayland. This configures your system to use the X11 (Xorg) display server.
     5. Exit the configuration tool and reboot your Raspberry Pi:
        ```bash
        sudo reboot
        ```

3. **Reboot:**
   - After applying the changes from `raspi-config`, reboot your Raspberry Pi if you haven't already.

## Installation

After your Raspberry Pi has rebooted, install the touchscreen driver by running the following command:

```bash
wget https://raw.githubusercontent.com/lpopescu-victron/ft5316-touchscreen/main/setup_touchscreen.sh && chmod +x setup_touchscreen.sh && ./setup_touchscreen.sh
