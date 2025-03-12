# Victron Energy Touch GX 7 & 5 Inch - Setup for Raspberry Pi

This script sets up the Victron Energy Touch GX 7 Touchscreen on a Raspberry Pi, including necessary dependencies and services.
It was tested on Pi5, Pi4 and Pi3 running Bookworm and Wayland session type. 


---


## Installation

Run the following command to download and install the script:

```bash
wget https://raw.githubusercontent.com/lpopescu-victron/ft5316-touchscreen/main/setup_touchscreen.sh && chmod +x setup_touchscreen.sh && ./setup_touchscreen.sh
```

This script will:
- Install necessary dependencies (`python3-pip`, `i2c-tools`, `ydotool`, etc.).
- Configure the I2C interface.
- Install and configure the touchscreen driver.
- Set up and enable the required services.

## Debugging Commands

If the touchscreen does not work as expected, use the following commands to troubleshoot.

### Check I2C devices (scan all buses)

Since the touchscreen is connected via HDMI and may use a different I2C bus, run the following command to scan all available I2C buses:

```bash
for bus in $(ls /dev/i2c-* | grep -o '[0-9]*'); do
    echo "Scanning I2C bus $bus:"
    sudo i2cdetect -y $bus
done
```

Look for devices at addresses `0x38`, `0x50`, or `0x51`. If they do not appear, ensure that I2C is enabled.

### Check if the touchscreen service is running

```bash
systemctl status ft5316-touchscreen.service
```

If the service is not active, try restarting it:

```bash
sudo systemctl restart ft5316-touchscreen.service
```

### Check if `ydotoold` is running

Since `ydotool` is required for cursor movement, ensure its service is running:

```bash
systemctl status ydotoold.service
```

If it's not running, restart it:

```bash
sudo systemctl restart ydotoold.service
```

### Fix `ydotoold` permission issue

If `ydotoold` fails due to `uinput` permission issues, manually apply the `udev` rule and restart `ydotoold`:

```bash
sudo udevadm control --reload-rules
sudo udevadm trigger
sudo modprobe -r uinput || echo "Module uinput is in use, continuing..."
sudo modprobe uinput
sudo systemctl restart ydotoold.service
```

### Manually start the touchscreen script

To manually run the touchscreen script for debugging:

```bash
python3 /home/pi/ft5316_touch.py
```

Check the output for any errors.

### Check logs for errors

To view logs related to the touchscreen service:

```bash
journalctl -u ft5316-touchscreen.service --no-pager --lines=50
```

To view logs related to `ydotoold`:

```bash
journalctl -u ydotoold.service --no-pager --lines=50
```


---

This should cover installation, debugging, and service management! 🚀

