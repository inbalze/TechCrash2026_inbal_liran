// =============================================================
// CrashTech VLSI-2026 — Challenge 5: FPGA Volt-Meter
// uart_tx_volt.sv  —  5-byte framed UART TX at 115200 baud
//
// Frame layout (5 bytes):
//   [0x55][0xAA][VAL_H][VAL_L][CRC8]
//   VAL   = 16-bit millivolt reading (0–3300)
//   CRC8  = XOR of bytes 0..3
//
// Parameters:
//   CLKS_PER_BIT   50 000 000 / 115 200 ≈ 434
// =============================================================

module uart_tx_volt #(
    parameter int CLKS_PER_BIT = 434
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        trigger,        // 1-cycle start pulse
    input  logic [15:0] mv_value,       // millivolt value to transmit
    output logic        tx,
    output logic        busy
);

    localparam int FRAME_LEN = 5;

    // ---- State -------------------------------------------------
    typedef enum logic [1:0] { IDLE, LOAD, SEND_BIT, NEXT_BYTE } state_t;
    state_t state;

    logic [7:0]  frame [0:FRAME_LEN-1];
    logic [2:0]  byte_idx;    // 0..4
    logic [3:0]  bit_idx;     // 0..9  (start + 8 data + stop)
    logic [9:0]  shift;       // 10-bit UART frame
    logic [11:0] baud_cnt;    // 434 max → 9 bits, use 10 for margin

    assign busy = (state != IDLE);
    assign tx   = (state == IDLE) ? 1'b1 : shift[0];

    // CRC = XOR of all data bytes preceding it
    logic [7:0] crc;
    always_comb
        crc = 8'h55 ^ 8'hAA ^ mv_value[15:8] ^ mv_value[7:0];

    // ---- FSM ---------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            byte_idx <= '0;
            bit_idx  <= '0;
            baud_cnt <= '0;
            shift    <= 10'b11_1111_1111;
            for (int i = 0; i < FRAME_LEN; i++) frame[i] <= '0;
        end else begin
            case (state)

                IDLE: begin
                    if (trigger) begin
                        frame[0] <= 8'h55;
                        frame[1] <= 8'hAA;
                        frame[2] <= mv_value[15:8];
                        frame[3] <= mv_value[7:0];
                        frame[4] <= crc;
                        byte_idx <= '0;
                        state    <= LOAD;
                    end
                end

                LOAD: begin
                    // Build 10-bit UART frame: {stop=1, D7..D0, start=0}
                    shift    <= {1'b1, frame[byte_idx], 1'b0};
                    bit_idx  <= '0;
                    baud_cnt <= '0;
                    state    <= SEND_BIT;
                end

                SEND_BIT: begin
                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt <= '0;
                        if (bit_idx == 4'd9) begin
                            state <= NEXT_BYTE;
                        end else begin
                            shift   <= {1'b1, shift[9:1]};  // shift right, fill MSB=1
                            bit_idx <= bit_idx + 1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                NEXT_BYTE: begin
                    if (byte_idx == FRAME_LEN - 1) begin
                        state <= IDLE;
                    end else begin
                        byte_idx <= byte_idx + 1;
                        state    <= LOAD;
                    end
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule
