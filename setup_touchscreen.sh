#!/bin/bash

echo "Starting touchscreen setup for Raspberry Pi 5..."

# Update system and install prerequisites
echo "Updating system and installing base packages..."
sudo apt update
sudo apt install -y python3-pip x11-xserver-utils x11-apps

# Install pyautogui with --break-system-packages
echo "Installing pyautogui..."
pip3 install pyautogui --break-system-packages

# Create the touchscreen script
echo "Setting up touchscreen script..."
cat << 'EOF' > /home/pi/ft5316_touch.py
import smbus
import time
import pyautogui

bus = smbus.SMBus(11)  # HDMI0, adjust to 12 if needed
FT5316_ADDR = 0x38
SCREEN_WIDTH = 1024
SCREEN_HEIGHT = 600

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

# Make the script executable
chmod +x /home/pi/ft5316_touch.py

# Create a launcher script
echo "Creating launcher script..."
cat << 'EOF' > /home/pi/run_touchscreen.sh
#!/bin/bash
export DISPLAY=:0
python3 /home/pi/ft5316_touch.py
EOF

chmod +x /home/pi/run_touchscreen.sh

echo "Setup complete!"
echo "To run the touchscreen, use: /home/pi/run_touchscreen.sh"
echo "Assuming X11 is enabled via raspi-config (Advanced Options > Wayland > X11)."
