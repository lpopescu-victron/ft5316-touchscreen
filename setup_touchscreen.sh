#!/bin/bash

echo "Starting touchscreen setup for Raspberry Pi..."

# Stop and disable any existing services
echo "Stopping and disabling existing services..."
sudo systemctl stop ft5316-touchscreen.service 2>/dev/null || echo "No ft5316-touchscreen.service to stop"
sudo systemctl disable ft5316-touchscreen.service 2>/dev/null || echo "No ft5316-touchscreen.service to disable"

# Remove old service files
echo "Removing old service files..."
sudo rm -f /etc/systemd/system/ft5316-touchscreen.service
sudo systemctl daemon-reload

# Kill any running instances
echo "Terminating any running instances..."
sudo pkill -f ft5316_touch.py 2>/dev/null || echo "No ft5316_touch.py processes found"

# Clean up old script files
echo "Removing old script files..."
sudo rm -f /home/pi/ft5316_touch.py

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
sudo udevadm control --reload-rules
sudo udevadm trigger
sudo modprobe -r uinput
sudo modprobe uinput

# Enable I2C in config.txt
echo "Checking and enabling I2C..."
CONFIG_FILE="/boot/firmware/config.txt"
if ! grep -q "^dtparam=i2c_arm=on" "$CONFIG_FILE"; then
    echo "Enabling I2C in $CONFIG_FILE..."
    sudo bash -c "echo 'dtparam=i2c_arm=on' >> $CONFIG_FILE"
else
    echo "I2C is already enabled in $CONFIG_FILE."
fi

# Manual resolution selection
echo "Select display resolution for your screen:"
echo "1) PI default (no custom HDMI settings)"
echo "2) 1024x600 - GX Touch 70"
echo "3) 800x480 - GX Touch 50"
read -p "Enter your choice (1-3): " choice

case $choice in
    1)
        echo "Using PI default display resolution..."
        sudo sed -i '/hdmi_force_hotplug/d' $CONFIG_FILE
        sudo sed -i '/hdmi_group/d' $CONFIG_FILE
        sudo sed -i '/hdmi_mode/d' $CONFIG_FILE
        sudo sed -i '/hdmi_cvt/d' $CONFIG_FILE
        sudo sed -i '/disable_overscan/d' $CONFIG_FILE
        sudo sed -i '/hdmi_drive/d' $CONFIG_FILE
        SCREEN_WIDTH=1280
        SCREEN_HEIGHT=800
        ;;
    2)
        echo "Setting HDMI screen resolution to 1024x600..."
        sudo sed -i '/hdmi_force_hotplug/d' $CONFIG_FILE
        sudo sed -i '/hdmi_group/d' $CONFIG_FILE
        sudo sed -i '/hdmi_mode/d' $CONFIG_FILE
        sudo sed -i '/hdmi_cvt/d' $CONFIG_FILE
        sudo sed -i '/disable_overscan/d' $CONFIG_FILE
        sudo sed -i '/hdmi_drive/d' $CONFIG_FILE
        sudo bash -c "echo 'hdmi_force_hotplug=1' >> $CONFIG_FILE"
        sudo bash -c "echo 'hdmi_group=2' >> $CONFIG_FILE"
        sudo bash -c "echo 'hdmi_mode=87' >> $CONFIG_FILE"
        sudo bash -c "echo 'hdmi_cvt=1024 600 60 6 0 0 0' >> $CONFIG_FILE"
        sudo bash -c "echo 'disable_overscan=1' >> $CONFIG_FILE"
        sudo bash -c "echo 'hdmi_drive=2' >> $CONFIG_FILE"
        SCREEN_WIDTH=1024
        SCREEN_HEIGHT=600
        ;;
    3)
        echo "Setting HDMI screen resolution to 800x480..."
        sudo sed -i '/hdmi_force_hotplug/d' $CONFIG_FILE
        sudo sed -i '/hdmi_group/d' $CONFIG_FILE
        sudo sed -i '/hdmi_mode/d' $CONFIG_FILE
        sudo sed -i '/hdmi_cvt/d' $CONFIG_FILE
        sudo sed -i '/disable_overscan/d' $CONFIG_FILE
        sudo sed -i '/hdmi_drive/d' $CONFIG_FILE
        sudo bash -c "echo 'hdmi_force_hotplug=1' >> $CONFIG_FILE"
        sudo bash -c "echo 'hdmi_group=2' >> $CONFIG_FILE"
        sudo bash -c "echo 'hdmi_mode=87' >> $CONFIG_FILE"
        sudo bash -c "echo 'hdmi_cvt=800 480 60 6 0 0 0' >> $CONFIG_FILE"
        sudo bash -c "echo 'disable_overscan=1' >> $CONFIG_FILE"
        sudo bash -c "echo 'hdmi_drive=2' >> $CONFIG_FILE"
        SCREEN_WIDTH=800
        SCREEN_HEIGHT=480
        ;;
    *)
        echo "Invalid option, defaulting to 800x480..."
        sudo sed -i '/hdmi_force_hotplug/d' $CONFIG_FILE
        sudo sed -i '/hdmi_group/d' $CONFIG_FILE
        sudo sed -i '/hdmi_mode/d' $CONFIG_FILE
        sudo sed -i '/hdmi_cvt/d' $CONFIG_FILE
        sudo sed -i '/disable_overscan/d' $CONFIG_FILE
        sudo sed -i '/hdmi_drive/d' $CONFIG_FILE
        sudo bash -c "echo 'hdmi_force_hotplug=1' >> $CONFIG_FILE"
        sudo bash -c "echo 'hdmi_group=2' >> $CONFIG_FILE"
        sudo bash -c "echo 'hdmi_mode=87' >> $CONFIG_FILE"
        sudo bash -c "echo 'hdmi_cvt=800 480 60 6 0 0 0' >> $CONFIG_FILE"
        sudo bash -c "echo 'disable_overscan=1' >> $CONFIG_FILE"
        sudo bash -c "echo 'hdmi_drive=2' >> $CONFIG_FILE"
        SCREEN_WIDTH=800
        SCREEN_HEIGHT=480
        ;;
esac

# Create the touchscreen script with ydotool
echo "Setting up touchscreen script..."
cat << EOF > /home/pi/ft5316_touch.py
import smbus
import time
import subprocess
import os
import sys
import signal

# Signal handler for clean exit
def signal_handler(sig, frame):
    print("Received signal to exit, shutting down...")
    sys.exit(0)

signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)

FT5316_ADDR = 0x38
EEPROM_ADDR1 = 0x50
EEPROM_ADDR2 = 0x51
SCREEN_WIDTH = $SCREEN_WIDTH
SCREEN_HEIGHT = $SCREEN_HEIGHT
MAX_X = SCREEN_WIDTH - 1  # 799 or 1023 depending on resolution
MAX_Y = SCREEN_HEIGHT - 1  # 479 or 599 depending on resolution
SCALING_FACTOR = 2

print("Script starting...")
def detect_i2c_bus():
    print("Detecting I2C bus...")
    for bus_num in range(0, 100):
        dev_path = f"/dev/i2c-{bus_num}"
        if os.path.exists(dev_path):
            try:
                bus = smbus.SMBus(bus_num)
                bus.read_byte_data(FT5316_ADDR, 0x00)
                bus.read_byte_data(EEPROM_ADDR1, 0x00)
                bus.read_byte_data(EEPROM_ADDR2, 0x00)
                print(f"Found FT5316 (0x38), 0x50, and 0x51 on I2C bus {bus_num}")
                return bus_num
            except IOError:
                continue
    raise RuntimeError("No I2C bus found with FT5316 (0x38), 0x50, and 0x51")

try:
    bus_number = detect_i2c_bus()
    bus = smbus.SMBus(bus_number)
except RuntimeError as e:
    print(f"Error: {e}")
    sys.exit(1)

print("Starting touchscreen control. Ctrl+C or SIGTERM to stop.")
last_event = None
is_down = False

while True:
    try:
        regs = bus.read_i2c_block_data(FT5316_ADDR, 0x00, 16)
        touch_points = regs[2]
        if touch_points > 0:
            print(f"Touch points: {touch_points}, Registers: {regs}")
            event = (regs[3] >> 6) & 0x03
            x = ((regs[3] & 0x0F) << 8) | regs[4]
            y = ((regs[5] & 0x0F) << 8) | regs[6]
            # Apply scaling factor of 2 without offset
            adjusted_x = x / SCALING_FACTOR
            adjusted_y = y / SCALING_FACTOR
            screen_x = min(max(int(adjusted_x), 0), MAX_X)
            screen_y = min(max(int(adjusted_y), 0), MAX_Y)
            print(f"Event: {event}, Raw X: {x}, Raw Y: {y}, Screen X: {screen_x}, Screen Y: {screen_y}")

            if event != last_event:
                print(f"Event changed: {last_event} -> {event}")
                last_event = event

            if event == 0 or (event == 2 and not is_down):  # Touch down or first move
                subprocess.run(["ydotool", "mousemove", "-a", "-x", str(screen_x), "-y", str(screen_y)])
                print(f"Mouse moved to absolute {screen_x}, {screen_y}")
                subprocess.run(["ydotool", "click", "0xC0"])
                print("Mouse clicked (down)")
                is_down = True
            elif event == 1:  # Touch up
                if is_down:
                    subprocess.run(["ydotool", "mousemove", "-a", "-x", str(screen_x), "-y", str(screen_y)])
                    print(f"Mouse moved to absolute {screen_x}, {screen_y}")
                is_down = False
            elif event == 2:  # Touch move
                subprocess.run(["ydotool", "mousemove", "-a", "-x", str(screen_x), "-y", str(screen_y)])
                print(f"Mouse moved to absolute {screen_x}, {screen_y}")
            else:
                print(f"Unhandled event: {event}")

        time.sleep(0.05)
    except Exception as e:
        print(f"Error in loop: {e}")
        time.sleep(1)
EOF

# Set ownership and make executable
sudo chown pi:pi /home/pi/ft5316_touch.py
chmod +x /home/pi/ft5316_touch.py

# Create systemd service for touchscreen
echo "Creating touchscreen service..."
sudo bash -c 'cat << "EOF" > /etc/systemd/system/ft5316-touchscreen.service
[Unit]
Description=FT5316 Touchscreen Driver
After=graphical.target multi-user.target

[Service]
User=pi
ExecStart=/usr/bin/python3 /home/pi/ft5316_touch.py
Restart=always
WorkingDirectory=/home/pi
KillSignal=SIGTERM
TimeoutStopSec=10

[Install]
WantedBy=graphical.target
EOF'

# Enable and start ydotoold service
echo "Starting ydotoold service..."
systemctl --user enable ydotoold.service
systemctl --user start ydotoold.service

# Enable and start touchscreen service
echo "Enabling and starting touchscreen service..."
sudo systemctl daemon-reload
sudo systemctl enable ft5316-touchscreen.service
sudo systemctl start ft5316-touchscreen.service

# Clean up the downloaded script file
echo "Cleaning up downloaded script file..."
rm -f "$0"
echo "Setup complete! Rebooting in 5 seconds to apply changes..."
sleep 5
sudo reboot
