# Victron Energy Touch GX 7 Touchscreen Setup for Raspberry Pi 5

This repository provides a setup script for configuring the Victron Energy Touch GX 7 with a Raspberry Pi 5 to enable touch functionality over HDMI. The script updates the system, installs required packages, configures the touch driver, and sets up a systemd service to run the driver at boot.


## Prerequisites

Before running the installation script, please perform the following steps using `raspi-config` and update your system:

1. **System Update (Recommended):**
   - Open a terminal and run the following command to update your package lists and upgrade all installed packages:
     ```bash
     sudo apt update && sudo apt full-upgrade
     ```
   - This ensures your system is fully updated before you proceed with the touchscreen setup.

2. **Enable I2C:**
   - Open a terminal and run:
     ```bash
     sudo raspi-config
     ```
   - Navigate to **Interface Options** and enable **I2C**.

3. **Switch from Wayland to X:**
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

4. **Reboot:**
   - After applying the changes from `raspi-config`, reboot your Raspberry Pi if you haven't already.

## Installation

After your Raspberry Pi has rebooted and your system is updated, install the touchscreen driver by running the following command:

```bash
wget https://raw.githubusercontent.com/lpopescu-victron/ft5316-touchscreen/main/setup_touchscreen.sh && chmod +x setup_touchscreen.sh && ./setup_touchscreen.sh
