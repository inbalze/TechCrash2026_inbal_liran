import serial
import sys
import time

def main():
    port = 'COM5'
    print(f"Connecting to {port}...", flush=True)
    try:
        ser = serial.Serial(port, 115200, timeout=0.1)
    except Exception as e:
        print(f"Error: {e}", flush=True)
        return

    print("Listening for changes. Please press KEYs or toggle SWs now...", flush=True)
    
    last_val = None
    start_time = time.time()
    
    try:
        while time.time() - start_time < 10:
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
            
            if value != last_val:
                key1 = (value >> 1) & 0x1
                key0 = value & 0x1
                sw0 = (value >> 2) & 0x1
                sw1 = (value >> 3) & 0x1
                sw2 = (value >> 4) & 0x1
                sw9 = (value >> 11) & 0x1
                
                print(f"CHANGE: Val=0x{value:04X} | KEY1={key1} KEY0={key0} | SW0={sw0} SW1={sw1} SW2={sw2} SW9={sw9}", flush=True)
                last_val = value
                
    except KeyboardInterrupt:
        pass
    finally:
        ser.close()
        print("Done.", flush=True)

if __name__ == "__main__":
    main()
