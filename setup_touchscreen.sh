while True:
    try:
        regs = bus.read_i2c_block_data(FT5316_ADDR, 0x00, 16)
        touch_points = regs[2]
        print(f"Touch points: {touch_points}, Raw regs: {regs}")
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
                print("Mouse down")
                last_x, last_y = screen_x, screen_y
                touch_start_time = time.time()
                touch_start_x, touch_start_y = screen_x, screen_y
            elif event == 1:  # Touch up
                if last_x is not None and last_y is not None:
                    pyautogui.mouseUp(screen_x, screen_y)
                    print("Mouse up")
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
                    print("Mouse down (move)")
                    touch_start_time = time.time()
                    touch_start_x, touch_start_y = screen_x, screen_y
                pyautogui.moveTo(screen_x, screen_y)
                print("Mouse moved")
                last_x, last_y = screen_x, screen_y
                no_touch_time = None
            else:
                print(f"Unhandled event: {event}")

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
                    print("Mouse up (no touch)")
                    last_x, last_y = None, None
                    touch_start_time = None
                    no_touch_time = None

        time.sleep(0.05)
    except Exception as e:
        print(f"Error in loop: {e}")
        time.sleep(1)
