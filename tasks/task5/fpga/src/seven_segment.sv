// =============================================================
// CrashTech VLSI-2026 — Challenge 5: FPGA Volt-Meter
// seven_segment.sv  —  Active-low 7-segment decoder
//
// Bit 7 = decimal point (1 = off, 0 = on).
// =============================================================

module seven_segment (
    input  logic [3:0] digit,
    output logic [7:0] seg    // active-low; bit[7]=DP (default 1 = off)
);
    always_comb begin
        case (digit)
            4'd0: seg = 8'hC0;
            4'd1: seg = 8'hF9;
            4'd2: seg = 8'hA4;
            4'd3: seg = 8'hB0;
            4'd4: seg = 8'h99;
            4'd5: seg = 8'h92;
            4'd6: seg = 8'h82;
            4'd7: seg = 8'hF8;
            4'd8: seg = 8'h80;
            4'd9: seg = 8'h90;
            default: seg = 8'hFF;  // blank
        endcase
    end
endmodule
