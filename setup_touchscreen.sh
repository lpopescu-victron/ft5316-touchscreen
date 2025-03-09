#!/bin/bash

echo "Starting touchscreen setup for Raspberry Pi 5..."

# Update system and install prerequisites
echo "Updating system and installing base packages..."
sudo apt update
sudo apt install -y python3-pip x11-xserver-utils x11-apps python3-smbus

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

# Ask user for display resolution option
echo "Select display resolution option:"
echo "1) PI default (no custom HDMI settings)"
echo "2) 1024x600 - Recommended for GX Touch 70 (higher resolution)"
echo "3) 800x480 - Recommended for GX Touch 50 (lower resolution)"
read -p "Enter your choice (1-3): " choice

case $choice in
    1)
        echo "Using PI default display resolution. Removing any custom HDMI settings..."
        sudo sed -i '/hdmi_force_hotplug/d' ${CONFIG_FILE}
        sudo sed -i '/hdmi_group/d' ${CONFIG_FILE}
        sudo sed -i '/hdmi_mode/d' ${CONFIG_FILE}
        sudo sed -i '/hdmi_cvt/d' ${CONFIG_FILE}
        ;;
    2)
        echo "Setting HDMI screen resolution to 1024x600..."
        sudo sed -i '/hdmi_force_hotplug/d' ${CONFIG_FILE}
        sudo sed -i '/hdmi_group/d' ${CONFIG_FILE}
        sudo sed -i '/hdmi_mode/d' ${CONFIG_FILE}
        sudo sed -i '/hdmi_cvt/d' ${CONFIG_FILE}
        sudo bash -c "echo 'hdmi_force_hotplug=1' >> ${CONFIG_FILE}"
        sudo bash -c "echo 'hdmi_group=2' >> ${CONFIG_FILE}"
        sudo bash -c "echo 'hdmi_mode=87' >> ${CONFIG_FILE}"
        sudo bash -c "echo 'hdmi_cvt=1024 600 60 6 0 0 0' >> ${CONFIG_FILE}"
        ;;
    3)
        echo "Setting HDMI screen resolution to 800x480..."
        sudo sed -i '/hdmi_force_hotplug/d' ${CONFIG_FILE}
        sudo sed -i '/hdmi_group/d' ${CONFIG_FILE}
        sudo sed -i '/hdmi_mode/d' ${CONFIG_FILE}
        sudo sed -i '/hdmi_cvt/d' ${CONFIG_FILE}
        sudo bash -c "echo 'hdmi_force_hotplug=1' >> ${CONFIG_FILE}"
        sudo bash -c "echo 'hdmi_group=2' >> ${CONFIG_FILE}"
        sudo bash -c "echo 'hdmi_mode=87' >> ${CONFIG_FILE}"
        sudo bash -c "echo 'hdmi_cvt=800 480 60 6 0 0 0' >> ${CONFIG_FILE}"
        ;;
    *)
        echo "Invalid option. Exiting..."
        exit 1
        ;;
esac

# Create the touchscreen script (with updated I2C bus detection)
echo "Setting up touchscreen script..."
cat << 'EOF' > /home/pi/ft5316_touch.py
import smbus
import time
import pyautogui
import os

FT5316_ADDR = 0x38
EEPROM_ADDR1 = 0x50
EEPROM_ADDR2 = 0x51
SCREEN_WIDTH = 1024  # Adjust based on choice (default 1024x600)
SCREEN_HEIGHT = 600  # Adjust based on choice (default 1024x600)

def detect_i2c_bus():
    """Detect the I2C bus with FT5316 (0x38), 0x50, and 0x51 present."""
    for bus_num in range(100):  # Check buses 0-99
        dev_path = f"/dev/i2c-{bus_num}"
        if os.path.exists(dev_path):
            try:
                bus = smbus.SMBus(bus_num)
                # Test all three addresses
                bus.read_byte_data(FT5316_ADDR, 0x00)  # FT5316
                bus.read_byte_data(EEPROM_ADDR1, 0x00)  # 0x50
                bus.read_byte_data(EEPROM_ADDR2, 0x00)  # 0x51
                print(f"Found FT5316 (0x38), 0x50, and 0x51 on I2C bus {bus_num}")
                return bus_num
            except IOError:
                continue
    raise RuntimeError("No I2C bus found with FT5316 (0x38), 0x50, and 0x51")

try:
    bus_number = detect_i2c_bus()
    bus = smbus.SMBus(bus_number)
except RuntimeError as e:
    print(e)
    exit(1)

pyautogui.FAILSAFE = False

def read_touch():
    try:
        regs = bus.read_i2c_block_data(FT5316_ADDR, 0x00, 16)
        touch_points = regs[2]  # Number of touch points
        if touch_points > 0:  # Any touch
            event = (regs[3] >> 6) & 0x03  # Bits 7:6 = event (0=down, 1=up, 2=move)
            x = ((regs[3] & 0x0F) << 8) | regs[4]
            y = ((regs[5] & 0x0F) << 8) | regs[6]
            return event, x, y
        return None, None, None
    except Exception as e:
        print(f"Error: {e}")
        return None, None, None

print("Starting touchscreen control. Ctrl+C to stop.")
last_event = None
last_x, last_y = None, None
touch_start_time = None
touch_start_x, touch_start_y = None, None
no_touch_time = None

while True:
    event, x, y = read_touch()
    if event is not None:
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
                if touch_duration < 0.3 and movement < 15:  # Quick tap
                    print("Click detected!")
                    pyautogui.click(screen_x, screen_y)
            last_x, last_y = None, None
            touch_start_time = None
        elif event == 2:  # Touch move
            if last_x is None:  # First touch
                pyautogui.mouseDown(screen_x, screen_y)
                touch_start_time = time.time()
                touch_start_x, touch_start_y = screen_x, screen_y
            pyautogui.moveTo(screen_x, screen_y)
            last_x, last_y = screen_x, screen_y
            no_touch_time = None  # Reset no-touch timer

    else:  # No touch
        if last_x is not None and last_y is not None:
            if no_touch_time is None:
                no_touch_time = time.time()
            elif time.time() - no_touch_time >= 0.1:  # 0.1s debounce
                touch_duration = time.time() - touch_start_time if touch_start_time else 0
                movement = abs(last_x - touch_start_x) + abs(last_y - touch_start_y)
                if touch_duration < 0.3 and movement < 15:  # Quick tap
                    print("Click detected (no-touch fallback)!")
                    pyautogui.click(last_x, last_y)
                pyautogui.mouseUp(last_x, last_y)
                last_x, last_y = None, None
                touch_start_time = None
                no_touch_time = None

    time.sleep(0.05)
EOF

# Make the touchscreen script executable
chmod +x /home/pi/ft5316_touch.py

# Create systemd service to run at boot
echo "Creating systemd service for auto-start..."
sudo bash -c 'cat << "EOF" > /etc/systemd/system/ft5316-touchscreen.service
[Unit]
Description=FT5316 Touchscreen Driver
After=graphical.target

[Service]
User=pi
Environment=DISPLAY=:0
ExecStartPre=/bin/sleep 10
ExecStart=/usr/bin/python3 /home/pi/ft5316_touch.py
Restart=always
WorkingDirectory=/home/pi

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
