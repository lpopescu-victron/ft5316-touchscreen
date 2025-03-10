#!/usr/bin/env python3

import os
import sys
import subprocess
import time
import signal

# Function to install missing packages
def install_dependencies():
    print("Checking for missing dependencies...")
    dependencies = ["ydotool", "python3-smbus"]  # Add other dependencies if needed

    for dep in dependencies:
        if dep == "ydotool":
            # Check if ydotool is installed
            if not os.path.exists("/usr/bin/ydotool"):
                print(f"Installing {dep}...")
                subprocess.run(["sudo", "apt", "update"])
                subprocess.run(["sudo", "apt", "install", "-y", "ydotool"])
        elif dep == "python3-smbus":
            # Check if smbus is installed
            try:
                import smbus
            except ImportError:
                print(f"Installing {dep}...")
                subprocess.run(["sudo", "apt", "update"])
                subprocess.run(["sudo", "apt", "install", "-y", "python3-smbus"])

# Install dependencies before proceeding
install_dependencies()

# Import smbus after ensuring it is installed
import smbus

# Signal handler for graceful exit
def signal_handler(sig, frame):
    print("Received signal to exit, shutting down...")
    sys.exit(0)

# Register signal handlers
signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)

# Constants
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
