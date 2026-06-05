import argparse
import serial
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", required=True)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--seconds", type=float, default=10.0)
    args = parser.parse_args()

    ser = serial.Serial(args.port, args.baud, timeout=0.2)
    end = time.time() + args.seconds
    count = 0

    print(f"Raw capture on {args.port} @ {args.baud} for {args.seconds:.1f}s")
    while time.time() < end:
        data = ser.read(256)
        count += len(data)

    print(f"raw_bytes={count}")


if __name__ == "__main__":
    main()
