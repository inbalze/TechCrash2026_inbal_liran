// ============================================================================
// FP8 E4M3 Adder — 2-STAGE PIPELINED IMPLEMENTATION (OPTIMIZED)
// ============================================================================
// Format: FP8 E4M3  (1 sign | 4 exponent | 3 mantissa)
//   Bias = 7.  No Infinity: exponent 0xF is a valid finite value.
//   NaN = S.1111.111  (|x|[6:0] == 7'h7F).
// ============================================================================

module fp8_adder (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire [7:0] a,
    input  wire [7:0] b,
    output wire [7:0] result,
    output wire       done,
    output reg        busy
);

    // =========================================================================
    // STAGE 1 COMBINATIONAL — Unpack, align, add/subtract
    // =========================================================================

    wire        sa = a[7];
    wire [3:0]  ea = a[6:3];
    wire [2:0]  ma = a[2:0];

    wire        sb = b[7];
    wire [3:0]  eb = b[6:3];
    wire [2:0]  mb = b[2:0];

    // NaN: |x|[6:0] == 7'h7F
    wire nan_a = (ea == 4'hF) & (ma == 3'h7);
    wire nan_b = (eb == 4'hF) & (mb == 3'h7);
    wire s1_any_nan = nan_a | nan_b;

    // Zero: |x|[6:0] == 0
    wire zero_a = (a[6:0] == 7'h00);
    wire zero_b = (b[6:0] == 7'h00);

    // Hidden bits (subnormal exp=0 → hidden=0, eff_exp=1)
    wire hidden_a = (ea != 4'h0);
    wire hidden_b = (eb != 4'h0);
    wire [3:0] eff_ea = (ea == 4'h0) ? 4'd1 : ea;
    wire [3:0] eff_eb = (eb == 4'h0) ? 4'd1 : eb;

    // Swap so larger magnitude is A
    // Direct 7-bit magnitude comparison (equivalent to comparing eff_exp and hidden+mantissa)
    wire a_larger = (a[6:0] >= b[6:0]);

    wire [3:0] s1_exp_big  = a_larger ? eff_ea           : eff_eb;
    wire [3:0] s1_exp_sml  = a_larger ? eff_eb           : eff_ea;
    wire [3:0] man_big4    = a_larger ? {hidden_a, ma}   : {hidden_b, mb};
    wire [3:0] man_sml4    = a_larger ? {hidden_b, mb}   : {hidden_a, ma};
    wire       s1_sign_big = a_larger ? sa               : sb;
    wire       s1_sign_sml = a_larger ? sb               : sa;
    wire       s1_same_sgn = (s1_sign_big == s1_sign_sml);

    // Parallel Exponent Math for exp_diff
    wire [3:0] exp_diff    = s1_exp_big - s1_exp_sml;

    wire [7:0] mant_big    = {man_big4, 4'b0};          // [7]=hidden [6:4]=m [3:0]=GRS

    // Optimized alignment shift directly on the 4-bit man_sml4
    wire [7:0] mant_sml_sh =
        (exp_diff == 4'd0) ? {man_sml4, 4'b0}       :
        (exp_diff == 4'd1) ? {1'b0, man_sml4, 3'b0} :
        (exp_diff == 4'd2) ? {2'b0, man_sml4, 2'b0} :
        (exp_diff == 4'd3) ? {3'b0, man_sml4, 1'b0} :
        (exp_diff == 4'd4) ? {4'b0, man_sml4}       :
        (exp_diff == 4'd5) ? {5'b0, man_sml4[3:1]}  :
        (exp_diff == 4'd6) ? {6'b0, man_sml4[3:2]}  :
        (exp_diff == 4'd7) ? {7'b0, man_sml4[3]}    :
                             8'd0;

    wire sticky_s1 =
        (exp_diff == 4'd5) ? man_sml4[0]     :
        (exp_diff == 4'd6) ? |man_sml4[1:0]  :
        (exp_diff == 4'd7) ? |man_sml4[2:0]  :
        (exp_diff >= 4'd8) ? |man_sml4       :
                             1'b0;

    // 9-bit add/subtract
    wire [8:0] s1_mant_sum =
        s1_same_sgn ? ({1'b0, mant_big} + {1'b0, mant_sml_sh})
                    : ({1'b0, mant_big} - {1'b0, mant_sml_sh} - {8'b0, sticky_s1});

    // Exact-zero detection (subtraction cancellation)
    wire s1_exact_zero = ~s1_same_sgn & (s1_mant_sum[7:0] == 8'h00) & ~sticky_s1;

    // =========================================================================
    // STAGE 1 → STAGE 2 PIPELINE REGISTERS
    // =========================================================================
    reg [8:0] p1_mant_sum;    // 9-bit mantissa sum
    reg [3:0] p1_exp_big;     // exponent of larger operand
    reg       p1_sign_big;    // sign of result
    reg       p1_sticky;      // sticky bit from alignment shift
    reg       p1_any_nan;     // NaN bypass
    reg       p1_exact_zero;  // exact zero
    reg       p1_zero_a;      // zero-passthrough flags
    reg       p1_zero_b;
    reg [7:0] p1_a;           // original inputs (for zero passthrough)
    reg [7:0] p1_b;
    reg       p1_valid;       // stage-1 data valid

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p1_mant_sum   <= 9'd0;
            p1_exp_big    <= 4'd0;
            p1_sign_big   <= 1'b0;
            p1_sticky     <= 1'b0;
            p1_any_nan    <= 1'b0;
            p1_exact_zero <= 1'b0;
            p1_zero_a     <= 1'b0;
            p1_zero_b     <= 1'b0;
            p1_a          <= 8'h00;
            p1_b          <= 8'h00;
            p1_valid      <= 1'b0;
        end else begin
            p1_valid      <= start;
            if (start) begin
                p1_mant_sum   <= s1_mant_sum;
                p1_exp_big    <= s1_exp_big;
                p1_sign_big   <= s1_sign_big;
                p1_sticky     <= sticky_s1;
                p1_any_nan    <= s1_any_nan;
                p1_exact_zero <= s1_exact_zero;
                p1_zero_a     <= zero_a;
                p1_zero_b     <= zero_b;
                p1_a          <= a;
                p1_b          <= b;
            end
        end
    end

    // =========================================================================
    // STAGE 2 COMBINATIONAL — Normalise, shift, prepare rounding
    // =========================================================================

    wire carry_out = p1_mant_sum[8];   // addition carry

    // Behavioral LZD (synthesizes to optimal priority encoder)
    wire [2:0] lzd =
        p1_mant_sum[7] ? 3'd0 :
        p1_mant_sum[6] ? 3'd1 :
        p1_mant_sum[5] ? 3'd2 :
        p1_mant_sum[4] ? 3'd3 :
        p1_mant_sum[3] ? 3'd4 :
        p1_mant_sum[2] ? 3'd5 :
        p1_mant_sum[1] ? 3'd6 :
                         3'd7;

    // --- Addition (carry) path: shift right 1, bump exp ---
    wire [3:0] pre_man4_carry = {1'b1, p1_mant_sum[7:5]};
    wire [4:0] norm_exp_carry = {1'b0, p1_exp_big} + 5'd1;
    wire [2:0] grs_carry      = {p1_mant_sum[4], p1_mant_sum[3],
                                 |(p1_mant_sum[2:0] | {2'b0, p1_sticky})};

    // --- Subtraction path: shift left by sub_shift ---
    wire              sub_subnormal = (p1_exp_big <= {1'b0, lzd});
    wire [3:0]        norm_exp_sub  = sub_subnormal ? 4'd0 : (p1_exp_big - {1'b0, lzd});
    wire [2:0]        sub_shift     = sub_subnormal ? (p1_exp_big[2:0] - 3'd1) : lzd;

    // Left shifter using behavioral shift
    wire [10:0] norm_wide = {p1_mant_sum[7:0], 3'b0} << sub_shift;

    wire [3:0] man_field_sub  = norm_wide[10:7];
    wire [2:0] grs_sub        = {norm_wide[6], norm_wide[5],
                                 |(norm_wide[4:0] | {4'b0, p1_sticky})};

    // --- Carry Path Rounding ---
    wire        round_up_carry   = grs_carry[2] & (grs_carry[1] | grs_carry[0] | pre_man4_carry[0]);
    wire [4:0]  rman5_carry      = {1'b0, pre_man4_carry} + 5'd1;
    
    wire [2:0]  final_man_carry  = round_up_carry ? rman5_carry[2:0] : pre_man4_carry[2:0];
    wire [4:0]  final_exp_carry  = round_up_carry ? (norm_exp_carry + {4'b0, rman5_carry[4]}) : norm_exp_carry;

    // --- Subtraction Path Rounding ---
    wire        round_up_sub     = grs_sub[2] & (grs_sub[1] | grs_sub[0] | man_field_sub[0]);
    wire [4:0]  rman5_sub        = {1'b0, man_field_sub} + 5'd1;

    wire [2:0]  final_man_sub    = round_up_sub ? rman5_sub[2:0] : man_field_sub[2:0];
    wire [4:0]  final_exp_sub    = round_up_sub ? ({1'b0, norm_exp_sub} + {4'b0, rman5_sub[4]}) : {1'b0, norm_exp_sub};

    // --- Mux Final Fields ---
    wire [2:0]  final_man        = carry_out ? final_man_carry : final_man_sub;
    wire [4:0]  final_exp_w      = carry_out ? final_exp_carry : final_exp_sub;
    wire [3:0]  final_exp        = final_exp_w[3:0];

    // --- Overflow / saturation (max finite = 0x7E) ---
    wire overflow = final_exp_w[4] | (final_exp == 4'hF & final_man == 3'h7);
    wire [6:0] sat_mag = overflow ? 7'h7E : {final_exp, final_man};

    // --- Build stage-2 combinational result ---
    wire [7:0] s2_result =
        p1_any_nan    ? 8'h7F :
        p1_exact_zero ? 8'h00 :
        p1_zero_a     ? p1_b  :
        p1_zero_b     ? p1_a  :
                        {p1_sign_big, sat_mag};

    // =========================================================================
    // OUTPUT LOGIC + done/busy
    // =========================================================================
    assign result = s2_result;
    assign done   = p1_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy   <= 1'b0;
        end else begin
            if (start)
                busy <= 1'b1;       // busy from start
            else if (p1_valid)
                busy <= 1'b0;
        end
    end

endmodule
