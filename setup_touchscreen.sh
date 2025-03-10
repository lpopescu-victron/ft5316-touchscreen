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
    echo "dtparam=i2c_arm=on" | sudo tee -a "$CONFIG_FILE"
else
    echo "I2C is already enabled in $CONFIG_FILE."
fi

# Set resolution using cmdline.txt and config.txt as provided
echo "Setting resolution to 800x480 using cmdline.txt and config.txt..."
CMDLINE_FILE="/boot/firmware/cmdline.txt"

# Update cmdline.txt
echo "console=serial0,115200 console=tty1 root=PARTUUID=57607e47-02 rootfstype=ext4 fsck.repair=yes rootwait quiet splash plymouth.ignore-serial-consoles cfg80211.ieee80211_regdom=GB video=HDMI-A-1:800x480@60 video=HDMI-A-2:800x480@60" | sudo tee "$CMDLINE_FILE"

# Update config.txt with provided settings
sudo bash -c 'cat << "EOF" | tee /boot/firmware/config.txt
# For more options and information see
# http://rptl.io/configtxt
# Some settings may impact device functionality. See link above for details

# Uncomment some or all of these to enable the optional hardware interfaces
#dtparam=i2c_arm=on
#dtparam=i2s=on
#dtparam=spi=on

# Enable audio (loads snd_bcm2835)
dtparam=audio=on

# Additional overlays and parameters are documented
# /boot/firmware/overlays/README

# Automatically load overlays for detected cameras
camera_auto_detect=1

# Automatically load overlays for detected DSI displays
display_auto_detect=1

# Automatically load initramfs files, if found
auto_initramfs=1

# Enable DRM VC4 V3D driver
dtoverlay=vc4-kms-v3d
max_framebuffers=2

# Don\'t have the firmware create an initial video= setting in cmdline.txt.
# Use the kernel\'s default instead.
disable_fw_kms_setup=1

# Run in 64-bit mode
arm_64bit=1

# Disable compensation for displays with overscan
#disable_overscan=1

# Run as fast as firmware / board allows
arm_boost=1

[cm4]
# Enable host mode on the 2711 built-in XHCI USB controller.
# This line should be removed if the legacy DWC2 controller is required
# (e.g. for USB device mode) or if USB support is not required.
otg_mode=1

[cm5]
dtoverlay=dwc2,dr_mode=host

[all]
dtparam=i2c_arm=on
hdmi_force_hotplug=1
hdmi_group=2
hdmi_mode=87
hdmi_cvt=800 480 60 6 0 0 0
disable_overscan=1
hdmi_drive=2
EOF'

# Set screen width and height
SCREEN_WIDTH=800
SCREEN_HEIGHT=480

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
MAX_X = SCREEN_WIDTH - 1  # 799
MAX_Y = SCREEN_HEIGHT - 1  # 479
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
sudo bash -c 'cat << "EOF" | tee /etc/systemd/system/ft5316-touchscreen.service
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
