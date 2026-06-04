// =============================================================
// CrashTech VLSI-2026 — Challenge 2: 3D Cube Tilt
// uart_tx_framed.sv  —  UART TX with framed 9-byte payload
//
// Transmits a fixed 9-byte frame on every `trigger` pulse:
//   [0x55][0xAA][X_H][X_L][Y_H][Y_L][Z_H][Z_L][CRC8]
//
// CRC8 = XOR of bytes 0..7 (simple, fast, sufficient).
//
// Parameters:
//   CLKS_PER_BIT  50 000 000 / 115200 ≈ 434
// =============================================================

module uart_tx_framed #(
    parameter int CLKS_PER_BIT = 434
)(
    input  logic        clk,
    input  logic        rst_n,
    // Trigger + payload
    input  logic        trigger,
    input  logic signed [15:0] x_data,
    input  logic signed [15:0] y_data,
    input  logic signed [15:0] z_data,
    // Serial output
    output logic        tx,
    output logic        busy
);

    // ---- Frame layout (9 bytes) --------------------------------
    localparam int FRAME_LEN = 9;

    // ---- Internal state ----------------------------------------
    typedef enum logic [1:0] { IDLE, LOAD, SEND_BIT, NEXT_BYTE } state_t;
    state_t state;

    logic [7:0]  frame [0:FRAME_LEN-1];
    logic [3:0]  byte_idx;
    logic [3:0]  bit_idx;    // 0..9  (start + 8 data + stop)
    logic [9:0]  shift;      // 10-bit frame: {stop, D7..D0, start}
    logic [11:0] baud_cnt;

    assign busy = (state != IDLE);

    // ---- CRC8: XOR of all data bytes ---------------------------
    logic [7:0] crc;
    always_comb begin
        crc = 8'h55 ^ 8'hAA
            ^ x_data[15:8] ^ x_data[7:0]
            ^ y_data[15:8] ^ y_data[7:0]
            ^ z_data[15:8] ^ z_data[7:0];
    end

    // ---- TX line -----------------------------------------------
    assign tx = (state == IDLE) ? 1'b1 : shift[0];

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
                        // Build frame
                        frame[0] <= 8'h55;
                        frame[1] <= 8'hAA;
                        frame[2] <= x_data[15:8];
                        frame[3] <= x_data[7:0];
                        frame[4] <= y_data[15:8];
                        frame[5] <= y_data[7:0];
                        frame[6] <= z_data[15:8];
                        frame[7] <= z_data[7:0];
                        frame[8] <= crc;
                        byte_idx <= '0;
                        state    <= LOAD;
                    end
                end

                LOAD: begin
                    // Load next byte into shift register
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
                            shift   <= {1'b1, shift[9:1]};
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
