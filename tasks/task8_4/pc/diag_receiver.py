import serial
import sys

def main():
    if len(sys.argv) < 2:
        print("Usage: python diag_receiver.py <COM_PORT>")
        sys.exit(1)

    port = sys.argv[1]
    ser = serial.Serial(port, 115200, timeout=1)

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

            sw = (value >> 2) & 0x3FF
            key1 = (value >> 1) & 0x1
            key0 = value & 0x1

            print(f"SW: {sw:010b} ({sw:4d}) | KEY[1]: {key1} | KEY[0]: {key0}")
    except KeyboardInterrupt:
        ser.close()
        print("\nConnection closed.")

if __name__ == "__main__":
    main()
