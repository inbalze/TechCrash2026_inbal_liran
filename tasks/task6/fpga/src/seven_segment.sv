// Seven-Segment BCD Decoder — active-low
// seg = {DP, G, F, E, D, C, B, A}  (0 = segment ON)
// Valid BCD inputs: 0-9. All other values produce blank (8'hFF).

module seven_segment (
    input  logic [3:0] digit,
    output logic [7:0] seg
);
    always_comb begin
        case (digit)
            4'd0: seg = 8'b11000000;
            4'd1: seg = 8'b11111001;
            4'd2: seg = 8'b10100100;
            4'd3: seg = 8'b10110000;
            4'd4: seg = 8'b10011001;
            4'd5: seg = 8'b10010010;
            4'd6: seg = 8'b10000010;
            4'd7: seg = 8'b11111000;
            4'd8: seg = 8'b10000000;
            4'd9: seg = 8'b10010000;
            default: seg = 8'hFF;   // blank for out-of-range
        endcase
    end
endmodule
