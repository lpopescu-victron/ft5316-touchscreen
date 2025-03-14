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

# Set up uinput permissions with persistent udev rule
echo "Configuring uinput permissions with persistent rule..."
sudo usermod -aG input pi
echo 'SUBSYSTEM=="misc", KERNEL=="uinput", MODE="0660", GROUP="input"' | sudo tee /etc/udev/rules.d/10-uinput.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
# Fallback: manually set permissions and verify
for i in {1..5}; do
    if [ -e /dev/uinput ]; then
        sudo chmod 660 /dev/uinput
        sudo chgrp input /dev/uinput
        if [ $(stat -c %a /dev/uinput) -eq 660 ] && [ $(stat -c %G /dev/uinput) = "input" ]; then
            echo "uinput permissions set to 660 with group input."
            break
        else
            echo "uinput permissions not set correctly, retrying... (attempt $i/5)"
        fi
    else
        echo "uinput device not found, retrying... (attempt $i/5)"
    fi
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

# Check I2C devices
echo "Detecting I2C devices..."
for bus in /dev/i2c-*; do
    if [ -e "$bus" ]; then
        i2c_bus=$(basename "$bus")
        i2cdetect -y "$i2c_bus" | grep -E "38|50|51" && echo "FT5316 (0x38), EEPROM (0x50, 0x51) detected on bus $i2c_bus" || echo "No FT5316 or EEPROM detected on bus $i2c_bus"
    fi
done

# Create the touchscreen script with ydotool
echo "Setting up touchscreen script..."
cat << 'EOF' > /home/pi/ft5316_touch.py
import smbus
import time
import subprocess
import os
import sys
import signal

def signal_handler(sig, frame):
    print("Received signal to exit, shutting down...")
    sys.exit(0)

signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)

FT5316_ADDR = 0x38
EEPROM_ADDR1 = 0x50
EEPROM_ADDR2 = 0x51
SCREEN_WIDTH = 800
SCREEN_HEIGHT = 480
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
echo "Checking file rights for ft5316_touch.py..."
if [ -f /home/pi/ft5316_touch.py ]; then
    sudo chown pi:pi /home/pi/ft5316_touch.py
    chmod +x /home/pi/ft5316_touch.py
    echo "ft5316_touch.py rights set: $(ls -l /home/pi/ft5316_touch.py)"
else
    echo "Error: ft5316_touch.py not found!"
fi

# Create wrapper script for ydotoold
echo "Creating ydotoold wrapper script..."
cat << 'EOF' > /home/pi/start_ydotoold.sh
#!/bin/bash
export XAUTHORITY=/home/pi/.Xauthority
ydotoold &
YDOTOOL_PID=$!
while true; do
    if [ -S /tmp/.ydotool_socket ]; then
        chmod 666 /tmp/.ydotool_socket
        if [ $(stat -c %a /tmp/.ydotool_socket) -eq 666 ]; then
            break
        fi
    fi
    sleep 1
done
wait $YDOTOOL_PID
EOF
echo "Checking file rights for start_ydotoold.sh..."
if [ -f /home/pi/start_ydotoold.sh ]; then
    sudo chown pi:pi /home/pi/start_ydotoold.sh
    chmod +x /home/pi/start_ydotoold.sh
    echo "start_ydotoold.sh rights set: $(ls -l /home/pi/start_ydotoold.sh)"
else
    echo "Error: start_ydotoold.sh not found!"
fi

# Create systemd service for touchscreen
echo "Creating touchscreen service..."
cat << 'EOF' | sudo tee /etc/systemd/system/ft5316-touchscreen.service
[Unit]
Description=FT5316 Touchscreen Driver
After=graphical.target multi-user.target ydotoold.service

[Service]
User=pi
ExecStart=/usr/bin/python3 /home/pi/ft5316_touch.py
Restart=always
WorkingDirectory=/home/pi
KillSignal=SIGTERM
TimeoutStopSec=10

[Install]
WantedBy=graphical.target
EOF

# Create and enable ydotoold service with wrapper, running as root
echo "Creating ydotoold service with wrapper..."
cat << 'EOF' | sudo tee /etc/systemd/system/ydotoold.service
[Unit]
Description=Starts ydotoold Daemon
After=graphical.target

[Service]
User=root
ExecStart=/home/pi/start_ydotoold.sh
Restart=always
WorkingDirectory=/home/pi
KillSignal=SIGTERM
TimeoutStopSec=10

[Install]
WantedBy=graphical.target
EOF
sudo systemctl daemon-reload
echo "Checking ydotoold service file..."
if [ -f /etc/systemd/system/ydotoold.service ]; then
    echo "ydotoold.service exists: $(ls -l /etc/systemd/system/ydotoold.service)"
else
    echo "Error: ydotoold.service not found!"
fi
sudo systemctl enable ydotoold.service
sudo systemctl start ydotoold.service

# Enable and start touchscreen service
echo "Creating ft5316-touchscreen service..."
cat << 'EOF' | sudo tee /etc/systemd/system/ft5316-touchscreen.service
[Unit]
Description=FT5316 Touchscreen Driver
After=graphical.target multi-user.target ydotoold.service

[Service]
User=pi
ExecStart=/usr/bin/python3 /home/pi/ft5316_touch.py
Restart=always
WorkingDirectory=/home/pi
KillSignal=SIGTERM
TimeoutStopSec=10

[Install]
WantedBy=graphical.target
EOF
echo "Checking ft5316-touchscreen service file..."
if [ -f /etc/systemd/system/ft5316-touchscreen.service ]; then
    echo "ft5316-touchscreen.service exists: $(ls -l /etc/systemd/system/ft5316-touchscreen.service)"
else
    echo "Error: ft5316-touchscreen.service not found!"
fi
sudo systemctl daemon-reload
sudo systemctl enable ft5316-touchscreen.service
sudo systemctl start ft5316-touchscreen.service

# Check service status before reboot
echo "Checking service status before reboot..."
systemctl status ydotoold.service
systemctl status ft5316-touchscreen.service

# Clean up the downloaded script file
echo "Cleaning up downloaded script file..."
[ -f "$0" ] && rm -f "$0" || echo "No downloadable script to clean up."

echo "Setup complete! Rebooting in 5 seconds to apply changes..."
sleep 5
sudo reboot
