#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root."
    exit 1
fi

# Function to install missing dependencies
install_dependencies() {
    echo "Checking for missing dependencies..."
    dependencies=("ydotool" "python3-smbus" "scdoc")

    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo "Installing $dep..."
            apt update
            apt install -y "$dep"
        fi
    done
}

# Function to fix uinput permissions
fix_uinput_permissions() {
    echo "Fixing uinput permissions..."
    if ! grep -q "uinput" /etc/modules; then
        echo "uinput" | tee -a /etc/modules
    fi

    if ! lsmod | grep -q "uinput"; then
        modprobe uinput
    fi

    if [ ! -f /etc/udev/rules.d/99-uinput.rules ]; then
        echo 'KERNEL=="uinput", MODE="0666", GROUP="input"' | tee /etc/udev/rules.d/99-uinput.rules
        udevadm control --reload-rules
        udevadm trigger
    fi
}

# Function to ensure ydotoold is running
ensure_ydotoold_running() {
    echo "Ensuring ydotoold is running..."
    if ! command -v ydotoold &> /dev/null; then
        echo "ydotoold not found. Building and installing ydotoold..."
        apt update
        apt install -y git cmake build-essential scdoc
        git clone https://github.com/ReimuNotMoe/ydotool.git
        cd ydotool
        mkdir build
        cd build
        cmake ..
        make
        make install
        cd ../..
        rm -rf ydotool
    fi

    # Ensure the socket directory exists
    mkdir -p /run/user/1000
    chmod 700 /run/user/1000

    # Set DISPLAY and allow local connections to the X server
    export DISPLAY=:0
    xhost +local:

    # Start ydotoold in the background
    if ! pgrep -x "ydotoold" > /dev/null; then
        echo "Starting ydotoold..."
        ydotoold &
    fi
}

# Function to fix ydotool command-line options
fix_ydotool_options() {
    echo "Fixing ydotool command-line options..."
    # Replace -a with --absolute for mousemove
    sed -i 's/"ydotool", "mousemove", "-a"/"ydotool", "mousemove", "--absolute"/g' "$0"
}

# Main script logic
install_dependencies
fix_uinput_permissions
ensure_ydotoold_running
fix_ydotool_options

# Run the Python script
python3 <<EOF
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
                subprocess.run(["ydotool", "mousemove", "--absolute", "-x", str(screen_x), "-y", str(screen_y)])
                print(f"Mouse moved to absolute {screen_x}, {screen_y}")
                subprocess.run(["ydotool", "click", "0xC0"])
                print("Mouse clicked (down)")
                is_down = True
            elif event == 1:  # Touch up
                if is_down:
                    subprocess.run(["ydotool", "mousemove", "--absolute", "-x", str(screen_x), "-y", str(screen_y)])
                    print(f"Mouse moved to absolute {screen_x}, {screen_y}")
                is_down = False
            elif event == 2:  # Touch move
                subprocess.run(["ydotool", "mousemove", "--absolute", "-x", str(screen_x), "-y", str(screen_y)])
                print(f"Mouse moved to absolute {screen_x}, {screen_y}")
            else:
                print(f"Unhandled event: {event}")

        time.sleep(0.05)
    except Exception as e:
        print(f"Error in loop: {e}")
        time.sleep(1)
EOF
