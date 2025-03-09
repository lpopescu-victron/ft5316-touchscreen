#!/bin/bash

echo "Starting touchscreen setup for Raspberry Pi..."

# Stop and disable any existing services
echo "Stopping and disabling existing services..."
sudo systemctl stop ft5316-touchscreen.service 2>/dev/null || echo "No ft5316-touchscreen.service to stop"
sudo systemctl disable ft5316-touchscreen.service 2>/dev/null || echo "No ft5316-touchscreen.service to disable"
sudo systemctl stop adjust-resolution.service 2>/dev/null || echo "No adjust-resolution.service to stop"
sudo systemctl disable adjust-resolution.service 2>/dev/null || echo "No adjust-resolution.service to disable"

# Remove old service files
echo "Removing old service files..."
sudo rm -f /etc/systemd/system/ft5316-touchscreen.service
sudo rm -f /etc/systemd/system/adjust-resolution.service
sudo systemctl daemon-reload

# Kill any running instances
echo "Terminating any running instances..."
sudo pkill -f ft5316_touch.py 2>/dev/null || echo "No ft5316_touch.py processes found"
sudo pkill -f adjust_resolution.sh 2>/dev/null || echo "No adjust_resolution.sh processes found"

# Clean up old script files
echo "Removing old script files..."
sudo rm -f /home/pi/ft5316_touch.py
sudo rm -f /home/pi/adjust_resolution.sh

# Update system and install prerequisites
echo "Updating system and installing base packages..."
sudo apt update
sudo apt install -y python3-pip x11-xserver-utils x11-apps python3-smbus i2c-tools xserver-xorg-core

# Install pyautogui
echo "Installing pyautogui..."
pip3 install pyautogui --break-system-packages

# Check and switch to X11 if Wayland is in use
echo "Checking display server mode..."
CURRENT_DESKTOP=$(echo $XDG_SESSION_TYPE)
if [ "$CURRENT_DESKTOP" = "wayland" ]; then
    echo "Wayland detected, switching to X11..."
    sudo bash -c "echo '[General]' > /etc/lightdm/lightdm.conf.d/10-force-x11.conf"
    sudo bash -c "echo 'display-setup-script=/bin/true' >> /etc/lightdm/lightdm.conf.d/10-force-x11.conf"
    echo "Switched to X11. A reboot is required."
else
    echo "X11 already in use, no changes needed."
fi

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
        SCREEN_WIDTH=1280
        SCREEN_HEIGHT=800
        ;;
    2)
        echo "Setting HDMI screen resolution to 1024x600..."
        SCREEN_WIDTH=1024
        SCREEN_HEIGHT=600
        ;;
    3)
        echo "Setting HDMI screen resolution to 800x480..."
        SCREEN_WIDTH=800
        SCREEN_HEIGHT=480
        ;;
    *)
        echo "Invalid option, defaulting to 800x480..."
        SCREEN_WIDTH=800
        SCREEN_HEIGHT=480
        ;;
esac

# Generate modeline for the selected resolution
echo "Generating modeline for ${SCREEN_WIDTH}x${SCREEN_HEIGHT}..."
MODELINE=$(cvt $SCREEN_WIDTH $SCREEN_HEIGHT 60 | grep "Modeline" | sed 's/Modeline //')

# Add the new mode and apply it
echo "Adding new mode and applying resolution..."
xrandr --newmode $MODELINE
xrandr --addmode HDMI-2 "${SCREEN_WIDTH}x${SCREEN_HEIGHT}_60.00"
xrandr --output HDMI-2 --mode "${SCREEN_WIDTH}x${SCREEN_HEIGHT}_60.00"

# Make the resolution persistent
echo "Making resolution persistent..."
sudo bash -c "echo 'xrandr --newmode $MODELINE' >> /etc/X11/Xsession.d/45custom_xrandr"
sudo bash -c "echo 'xrandr --addmode HDMI-2 \"${SCREEN_WIDTH}x${SCREEN_HEIGHT}_60.00\"' >> /etc/X11/Xsession.d/45custom_xrandr"
sudo bash -c "echo 'xrandr --output HDMI-2 --mode \"${SCREEN_WIDTH}x${SCREEN_HEIGHT}_60.00\"' >> /etc/X11/Xsession.d/45custom_xrandr"

# Create the touchscreen script with fixed resolution
echo "Setting up touchscreen script..."
cat << EOF > /home/pi/ft5316_touch.py
import smbus
import time
import pyautogui
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
            except IOError as e:
                print(f"Error on bus {bus_num}: {e}")
                continue
    raise RuntimeError("No I2C bus found with FT5316 (0x38), 0x50, and 0x51")

try:
    bus_number = detect_i2c_bus()
    bus = smbus.SMBus(bus_number)
except RuntimeError as e:
    print(f"Error: {e}")
    sys.exit(1)

pyautogui.FAILSAFE = False
print("Starting touchscreen control. Ctrl+C or SIGTERM to stop.")
last_event = None
last_x, last_y = None, None
touch_start_time = None
touch_start_x, touch_start_y = None, None
no_touch_time = None

while True:
    try:
        regs = bus.read_i2c_block_data(FT5316_ADDR, 0x00, 16)
        touch_points = regs[2]
        if touch_points > 0:
            event = (regs[3] >> 6) & 0x03
            x = ((regs[3] & 0x0F) << 8) | regs[4]
            y = ((regs[5] & 0x0F) << 8) | regs[6]
            screen_x = min(max(x, 0), SCREEN_WIDTH - 1)
            screen_y = min(max(y, 0), SCREEN_HEIGHT - 1)
            print(f"Event: {event}, Raw X: {x}, Raw Y: {y} -> Screen X: {screen_x}, Screen Y: {screen_y}")

            if event != last_event:
                print(f"Event changed: {last_event} -> {event}")
                last_event = event

            if event == 0:  # Touch down
                print("Touch down detected")
                pyautogui.mouseDown(screen_x, screen_y)
                last_x, last_y = screen_x, screen_y
                touch_start_time = time.time()
                touch_start_x, touch_start_y = screen_x, screen_y
            elif event == 1:  # Touch up
                print("Touch up detected")
                if last_x is not None and last_y is not None:
                    pyautogui.mouseUp(screen_x, screen_y)
                    touch_duration = time.time() - touch_start_time if touch_start_time else 0
                    movement = abs(screen_x - touch_start_x) + abs(screen_y - touch_start_y)
                    if touch_duration < 0.3 and movement < 15:
                        print("Click detected!")
                        pyautogui.click(screen_x, screen_y)
                last_x, last_y = None, None
                touch_start_time = None
            elif event == 2:  # Touch move
                print("Touch move detected")
                if last_x is None:
                    pyautogui.mouseDown(screen_x, screen_y)
                    touch_start_time = time.time()
                    touch_start_x, touch_start_y = screen_x, screen_y
                pyautogui.moveTo(screen_x, screen_y)
                last_x, last_y = screen_x, screen_y
                no_touch_time = None

        else:
            if last_x is not None and last_y is not None:
                if no_touch_time is None:
                    no_touch_time = time.time()
                elif time.time() - no_touch_time >= 0.1:
                    touch_duration = time.time() - touch_start_time if touch_start_time else 0
                    movement = abs(last_x - touch_start_x) + abs(last_y - touch_start_y)
                    if touch_duration < 0.3 and movement < 15:
                        print("Click detected (no-touch fallback)!")
                        pyautogui.click(last_x, last_y)
                    pyautogui.mouseUp(last_x, last_y)
                    last_x, last_y = None, None
                    touch_start_time = None
                    no_touch_time = None

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
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/pi/.Xauthority
ExecStart=/usr/bin/python3 /home/pi/ft5316_touch.py
Restart=always
WorkingDirectory=/home/pi
KillSignal=SIGTERM
TimeoutStopSec=10

[Install]
WantedBy=graphical.target
EOF'

# Enable and start service
echo "Enabling and starting touchscreen service..."
sudo systemctl daemon-reload
sudo systemctl enable ft5316-touchscreen.service
sudo systemctl start ft5316-touchscreen.service

# Clean up the downloaded script file
echo "Cleaning up downloaded script file..."
rm -f "$0"
echo "Setup complete! If you change the screen, rerun this script with:"
echo "wget -O setup_touchscreen.sh https://raw.githubusercontent.com/lpopescu-victron/ft5316-touchscreen/main/setup_touchscreen.sh && chmod +x setup_touchscreen.sh && ./setup_touchscreen.sh"
echo "Rebooting in 5 seconds to apply changes..."
sleep 5
sudo reboot
