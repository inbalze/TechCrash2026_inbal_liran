import argparse
import sys

import serial


FRAME_HEADER = 0xA000


def decode_payload(value):
    key0 = bool(value & 0x0001)
    key1 = bool((value >> 1) & 0x0001)
    sw_bits = (value >> 2) & 0x03FF
    sw = [(sw_bits >> i) & 0x1 for i in range(10)]
    return key0, key1, sw


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", required=True)
    parser.add_argument("--baud", type=int, default=115200)
    args = parser.parse_args()

    try:
        ser = serial.Serial(args.port, args.baud, timeout=1)
    except Exception as exc:
        print(f"Failed to open serial port: {exc}")
        sys.exit(1)

    print(f"Listening on {args.port} @ {args.baud}")

    prev = None
    while True:
        data = ser.read(1)
        if len(data) < 1:
            continue

        b = data[0]
        if prev is None:
            prev = b
            continue

        payload = (prev << 8) | b
        prev = b
        if (payload & 0xF000) != FRAME_HEADER:
            continue
        key0, key1, sw = decode_payload(payload & 0x0FFF)

        print(
            f"payload=0x{payload:04X} key0={int(key0)} key1={int(key1)} "
            f"sw9..0={''.join(str(sw[i]) for i in range(9, -1, -1))}",
            flush=True,
        )


if __name__ == "__main__":
    main()
