#!/bin/bash

echo "Starting touchscreen setup for Raspberry Pi..."

# Stop and disable existing services
echo "Stopping and disabling existing services..."
sudo systemctl stop ft5316-touchscreen.service 2>/dev/null || echo "No ft5316-touchscreen.service to stop"
sudo systemctl disable ft5316-touchscreen.service 2>/dev/null || echo "No ft5316-touchscreen.service to disable"

# Remove old service files
echo "Removing old service files..."
sudo rm -f /etc/systemd/system/ft5316-touchscreen.service
sudo rm -f /etc/systemd/system/ydotoold.service
sudo systemctl daemon-reload

# Kill any running instances
echo "Terminating any running instances..."
sudo pkill -f ydotoold
sudo pkill -f ft5316_touch.py 2>/dev/null || echo "No ft5316_touch.py processes found"

# Clean up old script files
echo "Removing old script files..."
sudo rm -f /home/pi/ft5316_touch.py
sudo rm -f /home/pi/start_ydotoold.sh

# Update system and install prerequisites
echo "Updating system and installing base packages..."
sudo apt update
sudo apt install -y python3-pip python3-smbus i2c-tools git cmake libudev-dev scdoc

# Install ydotool for Wayland cursor control
echo "Installing ydotool..."
cd /home/pi
git clone https://github.com/ReimuNotMoe/ydotool
cd ydotool
mkdir build && cd build
cmake ..
make
sudo make install
cd /home/pi
rm -rf ydotool

# Set up uinput permissions for pi user
echo "Configuring uinput permissions..."
sudo usermod -aG input pi
sudo bash -c 'echo "KERNEL==\"uinput\", SUBSYSTEM==\"misc\", MODE=\"0660\", GROUP=\"input\"" > /etc/udev/rules.d/99-uinput.rules'

# Reload udev rules and ensure the permissions are applied
sudo udevadm control --reload-rules
sudo udevadm trigger
sudo modprobe -r uinput || echo "Module uinput is in use, continuing..."
sudo modprobe uinput

# Wait until /dev/uinput has correct permissions before proceeding
echo "Waiting for /dev/uinput permissions to be applied..."
for i in {1..5}; do
    if [ "$(stat -c %G /dev/uinput)" == "input" ]; then
        echo "/dev/uinput permissions correctly set."
        break
    fi
    echo "Retrying in 1 second..."
    sleep 1
done

# Enable I2C in config.txt
echo "Checking and enabling I2C..."
CONFIG_FILE="/boot/firmware/config.txt"
if ! grep -q "^dtparam=i2c_arm=on" "$CONFIG_FILE"; then
    echo "Enabling I2C in $CONFIG_FILE..."
    echo "dtparam=i2c_arm=on" | sudo tee -a "$CONFIG_FILE"
else
    echo "I2C is already enabled in $CONFIG_FILE."
fi

# Enable and start ydotoold service AFTER ensuring uinput is set up
echo "Enabling and starting ydotoold service..."
sudo systemctl daemon-reload
sudo systemctl enable ydotoold.service
sudo systemctl start ydotoold.service

# Enable and start touchscreen service
echo "Enabling and starting touchscreen service..."
sudo systemctl enable ft5316-touchscreen.service
sudo systemctl start ft5316-touchscreen.service

# Clean up the downloaded script file
echo "Cleaning up downloaded script file..."
[ -f "$0" ] && rm -f "$0" || echo "No downloadable script to clean up."

echo "Setup complete! Rebooting in 5 seconds to apply changes..."
sleep 5
sudo reboot
