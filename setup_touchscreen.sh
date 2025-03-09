#!/bin/bash

echo "Starting touchscreen setup for Raspberry Pi..."

# Update system and install prerequisites
echo "Updating system and installing base packages..."
sudo apt update
sudo apt install -y python3-pip x11-xserver-utils x11-apps python3-smbus i2c-tools

# Install pyautogui with --break-system-packages
echo "Installing pyautogui..."
pip3 install pyautogui --break-system-packages

# Enable I2C in config.txt if not already enabled
echo "Checking and enabling I2C..."
CONFIG_FILE="/boot/firmware/config.txt"
if ! grep -q "^dtparam=i2c_arm=on" "$CONFIG_FILE"; then
    echo "Enabling I2C in $CONFIG_FILE..."
    sudo bash -c "echo 'dtparam=i2c_arm=on' >> $CONFIG_FILE"
else
    echo "I2C is already enabled in $CONFIG_FILE."
fi

# Detect screen type from EEPROM at 0x50, offset 0x53
echo "Detecting screen type from EEPROM..."
I2C_BUS=21  # Based on your output
EEPROM_ADDR=0x50
OFFSET=0x53
MODEL_ID=$(i2cget -y $I2C_BUS $EEPROM_ADDR $OFFSET)

if [ "$MODEL_ID" = "0x35" ]; then
    echo "Detected GX Touch 50 (800x480)"
    SCREEN_WIDTH=800
    SCREEN_HEIGHT=480
    HDMI_GROUP=2
    HDMI_MODE=87
    HDMI_CVT="800 480 60 6 0 0 0"
elif [ "$MODEL_ID" = "0x37" ]; then
    echo "Detected GX Touch 70 (1024x600)"
    SCREEN_WIDTH=1024
    SCREEN_HEIGHT=600
    HDMI_GROUP=3
    HDMI_MODE=88
    HDMI_CVT="1024 600 60 6 0 0 0"
else
    echo "Unknown screen type (ID: $MODEL_ID), defaulting to GX Touch 50 (800x480)"
    SCREEN_WIDTH=800
    SCREEN_HEIGHT=480
    HDMI_GROUP=2
    HDMI_MODE=87
    HDMI_CVT="800 480 60 6 0 0 0"
fi

# Write HDMI settings to config.txt
echo "Setting HDMI screen resolution to ${SCREEN_WIDTH}x${SCREEN_HEIGHT}..."
sudo sed -i '/hdmi_force_hotplug/d' ${CONFIG_FILE}
sudo sed -i '/hdmi_group/d' ${CONFIG_FILE}
sudo sed -i '/hdmi_mode/d' ${CONFIG_FILE}
sudo sed -i '/hdmi_cvt/d' ${CONFIG_FILE}
sudo bash -c "echo 'hdmi_force_hotplug=1' >> ${CONFIG_FILE}"
sudo bash -c "echo 'hdmi_group=${HDMI_GROUP}' >> ${CONFIG_FILE}"
sudo bash -c "echo 'hdmi_mode=${HDMI_MODE}' >> ${CONFIG_FILE}"
sudo bash -c "echo 'hdmi_cvt=${HDMI_CVT}' >> ${CONFIG_FILE}"

# Create the touchscreen script with dynamic resolution
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
    for bus_num in range(100):
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
                pyautogui.mouseDown(screen_x, screen_y)
                last_x, last_y = screen_x, screen_y
                touch_start_time = time.time()
                touch_start_x, touch_start_y = screen_x, screen_y
            elif event == 1:  # Touch up
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

# Make the touchscreen script executable
chmod +x /home/pi/ft5316_touch.py

# Create systemd service for auto-start
echo "Creating systemd service for auto-start..."
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

# Enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable ft5316-touchscreen.service
sudo systemctl start ft5316-touchscreen.service

echo "Setup complete!"
echo "Touchscreen driver is now set to run at boot."
echo "Rebooting in 5 seconds to apply changes..."
sleep 5
sudo reboot
