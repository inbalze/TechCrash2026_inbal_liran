import serial
import sys
import time

def main():
    port = 'COM5'
    print(f"Connecting to {port}...", flush=True)
    try:
        ser = serial.Serial(port, 115200, timeout=0.1)
    except Exception as e:
        print(f"Error opening port: {e}", flush=True)
        return

    print("Running key debugger. Press keys on the board now!", flush=True)
    
    start_time = time.time()
    packet_count = 0
    
    try:
        while time.time() - start_time < 5:
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
            sw0 = (value >> 2) & 0x1
            sw1 = (value >> 3) & 0x1
            sw2 = (value >> 4) & 0x1
            
            packet_count += 1
            if packet_count % 10 == 0:  # Print every 10th packet (approx 6 times per second)
                print(f"Val: 0x{value:04X} | KEY1: {key1} | KEY0: {key0} | SW: {sw2}{sw1}{sw0}", flush=True)
                
    except Exception as e:
        print(f"Error in loop: {e}", flush=True)
    finally:
        ser.close()
        print(f"Done. Processed {packet_count} packets.", flush=True)

if __name__ == "__main__":
    main()
