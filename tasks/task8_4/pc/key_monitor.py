import serial
import sys

def main():
    if len(sys.argv) < 2:
        print("Usage: python key_monitor.py <COM_PORT>")
        sys.exit(1)

    port = sys.argv[1]
    print(f"Connecting to {port} at 115200 baud...")
    ser = serial.Serial(port, 115200, timeout=0.1)

    print("Listening for key presses. Press Ctrl+C to exit.")
    
    # Initialize previous state to 1 (which prevents startup triggers if a key is already down, 
    # but immediately updates on the first received 'released' packet)
    prev_key0 = 1
    prev_key1 = 1

    try:
        while True:
            b = ser.read(1)
            if not b:
                continue
            high_byte = b[0]
            if (high_byte & 0xF0) != 0x00:
                continue
            low = ser.read(1)
            if not low:
                continue
            value = (high_byte << 8) | low[0]

            key1 = (value >> 1) & 0x1
            key0 = value & 0x1

            if key0 == 1 and prev_key0 == 0:
                print("KEY0 pressed")
            if key1 == 1 and prev_key1 == 0:
                print("KEY1 pressed")

            prev_key0 = key0
            prev_key1 = key1
            
    except KeyboardInterrupt:
        ser.close()
        print("\nConnection closed.")

if __name__ == "__main__":
    main()
