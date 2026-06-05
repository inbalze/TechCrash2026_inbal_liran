import serial
import serial.tools.list_ports
import time

def find_port():
    ports = list(serial.tools.list_ports.comports())
    for p in ports:
        if "USB" in p.description or "UART" in p.description or "COM" in p.device:
            return p.device
    return "COM5"

def main():
    port_name = find_port()
    ser = serial.Serial(port_name, 115200, timeout=1)
    time.sleep(2)
    ser.reset_input_buffer()
    buffer = bytearray()
    while True:
        if ser.in_waiting > 0:
            buffer.extend(ser.read(ser.in_waiting))
            while len(buffer) >= 2:
                if (buffer[0] & 0xF0) == 0:
                    high = buffer[0]
                    low = buffer[1]
                    val = (high << 8) | low
                    k0 = val & 1
                    k1 = (val >> 1) & 1
                    sw = [(val >> (i + 2)) & 1 for i in range(10)]
                    print(f"VAL: 0x{val:04X} | KEY1: {k1}, KEY0: {k0} | SW: {sw}")
                    del buffer[:2]
                else:
                    del buffer[0]
        time.sleep(0.01)

if __name__ == "__main__":
    main()
