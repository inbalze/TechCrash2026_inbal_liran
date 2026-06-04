// =============================================================
// CrashTech VLSI-2026 — Challenge 4: Press Right
// uart_tx_16 — 16-bit UART transmitter, 8N1
//
// Protocol:  LSB byte (data[7:0]) sent first, then MSB byte
//            (data[15:8]).  Idle line = HIGH.
//
// Parameters:
//   CLKS_PER_BIT  Clock cycles per UART bit.
//                 For 50 MHz + 9600 baud → 5208.
//
// Ports:
//   trigger  1-cycle start pulse (ignored while busy)
//   data     16-bit payload to transmit
//   tx       Serial output (idle HIGH, start bit LOW)
//   busy     HIGH while a transmission is in progress
// =============================================================

module uart_tx_16 #(
    parameter int CLKS_PER_BIT = 5208
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        trigger,
    input  logic [15:0] data,
    output logic        tx,
    output logic        busy
);

    // ----- State encoding ----------------------------------------
    localparam logic [1:0] S_IDLE  = 2'd0;
    localparam logic [1:0] S_BYTE0 = 2'd1;   // transmitting data[7:0]
    localparam logic [1:0] S_BYTE1 = 2'd2;   // transmitting data[15:8]

    // ----- Internal registers ------------------------------------
    logic [1:0]  state;
    logic [12:0] baud_cnt;   // counts 0 … CLKS_PER_BIT-1  (5207 max → 13 bits)
    logic [3:0]  bit_idx;    // current bit position 0-9 within frame
    logic [9:0]  shift;      // 10-bit frame: {stop, D7..D0, start}
    logic [15:0] data_latch; // captured payload

    // ----- Combinational outputs ---------------------------------
    // When IDLE: line is HIGH.  Otherwise drive shift[0].
    assign busy = (state != S_IDLE);
    assign tx   = (state == S_IDLE) ? 1'b1 : shift[0];

    // ----- Main state machine ------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            baud_cnt   <= '0;
            bit_idx    <= '0;
            shift      <= 10'b11_1111_1111;  // idle
            data_latch <= '0;
        end else begin
            case (state)

                // --------------------------------------------------
                S_IDLE: begin
                    if (trigger) begin
                        data_latch <= data;
                        // Frame layout: [9]=stop=1, [8..1]=D7..D0, [0]=start=0
                        shift    <= {1'b1, data[7:0], 1'b0};
                        bit_idx  <= '0;
                        baud_cnt <= '0;
                        state    <= S_BYTE0;
                        // tx will be shift[0] = 0 (start bit) next cycle
                    end
                end

                // --------------------------------------------------
                S_BYTE0: begin
                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt <= '0;
                        if (bit_idx == 4'd9) begin
                            // Byte 0 complete — load byte 1 frame
                            shift    <= {1'b1, data_latch[15:8], 1'b0};
                            bit_idx  <= '0;
                            state    <= S_BYTE1;
                        end else begin
                            // Advance to next bit: shift right, fill MSB with 1
                            shift   <= {1'b1, shift[9:1]};
                            bit_idx <= bit_idx + 1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                // --------------------------------------------------
                S_BYTE1: begin
                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt <= '0;
                        if (bit_idx == 4'd9) begin
                            // Byte 1 complete — return to idle
                            state <= S_IDLE;
                        end else begin
                            shift   <= {1'b1, shift[9:1]};
                            bit_idx <= bit_idx + 1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                // --------------------------------------------------
                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
