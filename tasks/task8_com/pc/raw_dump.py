import argparse
import serial
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", required=True)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--bytes", type=int, default=128)
    parser.add_argument("--skip-seconds", type=float, default=0.0)
    args = parser.parse_args()

    ser = serial.Serial(args.port, args.baud, timeout=2)

    if args.skip_seconds > 0:
        end = time.time() + args.skip_seconds
        while time.time() < end:
            ser.read(256)

    data = ser.read(args.bytes)
    print(f"captured={len(data)}")
    print(" ".join(f"{b:02X}" for b in data))


if __name__ == "__main__":
    main()
