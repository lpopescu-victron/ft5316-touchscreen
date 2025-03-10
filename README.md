# Victron Energy Touch GX 7 Touchscreen Setup for Raspberry Pi 5

This repository provides a setup script for configuring the Victron Energy Touch GX 7 with a Raspberry Pi 5 to enable touch functionality over HDMI. The script updates the system, installs required packages, configures the touch driver, and sets up a systemd service to run the driver at boot.

Tested with Pi5 and Pi4 running Raspbian 



## Installation

After your Raspberry Pi has rebooted and your system is updated, install the touchscreen driver by running the following command:

```bash
wget https://raw.githubusercontent.com/lpopescu-victron/ft5316-touchscreen/main/setup_touchscreen.sh && chmod +x setup_touchscreen.sh && ./setup_touchscreen.sh
