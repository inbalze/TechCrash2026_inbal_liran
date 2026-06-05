import serial
import sys

def main():
    port = 'COM5'
    if len(sys.argv) > 1:
        port = sys.argv[1]
    
    ser = serial.Serial(port, 115200, timeout=None)
    buffer = bytearray()
    
    while True:
        data = ser.read(1)
        if not data:
            continue
        buffer.extend(data)
        if len(buffer) >= 2:
            if (buffer[0] & 0xF0) == 0:
                val = (buffer[0] << 8) | buffer[1]
                key0 = val & 1
                key1 = (val >> 1) & 1
                sw = [(val >> (i + 2)) & 1 for i in range(10)]
                print(f"KEY0: {key0} | KEY1: {key1} | SW: {sw}", flush=True)
                buffer = buffer[2:]
            else:
                buffer = buffer[1:]

if __name__ == '__main__':
    main()
