// ============================================================================
// FP8 E4M3 Adder — 2-STAGE PIPELINED IMPLEMENTATION
// ============================================================================
// Task 7 — CrashTech VLSI-2026  (2-stage pipeline, 100/125 MHz target)
//
// Format: FP8 E4M3  (1 sign | 4 exponent | 3 mantissa)
//   Bias = 7.  No Infinity: exponent 0xF is a valid finite value.
//   NaN = S.1111.111  (|x|[6:0] == 7'h7F).
//
// Pipeline stages separated by a single always_ff boundary:
//
//   Stage 1 (Align & Add) — comb on {a,b}; registered at end:
//     - Unpack, NaN/zero detection
//     - Exponent comparison + swap
//     - Barrel-shift smaller mantissa (8-bit extended, sticky bit)
//     - 9-bit add/subtract into mant_sum_p1
//     - Propagate: exp_big, sign_big, sticky, zero/nan flags
//
//   Stage 2 (Normalise & Pack) — comb on stage-1 regs; registered at end:
//     - Carry/LZD detection
//     - Left/right normalisation shift
//     - GRS round-to-nearest-even
//     - Overflow saturation (clamp to 0x7E)
//     - Build final 8-bit result → output register
//     - Assert done; de-assert next cycle
//
// Handshake with test_controller:
//   TC_LAUNCH: start=1   (a/b stable from TC_WAIT_MEM)
//   TC_WAIT_ADD cycle 1: stage-1 pipeline regs loaded
//   TC_WAIT_ADD cycle 2: done=1 fires → TC_CHECK advances
//   Total adder latency: 2 cycles after start.
// ============================================================================

module fp8_adder (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire [7:0] a,
    input  wire [7:0] b,
    output reg  [7:0] result,
    output reg        done,
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

    // Pass-through flags (NaN/zero bypass the pipeline)
    wire s1_zero_a  = zero_a;
    wire s1_zero_b  = zero_b;
    wire [7:0] s1_a = a;    // kept for zero-passthrough
    wire [7:0] s1_b = b;

    // Hidden bits (subnormal exp=0 → hidden=0, eff_exp=1)
    wire hidden_a = (ea != 4'h0);
    wire hidden_b = (eb != 4'h0);
    wire [3:0] eff_ea = (ea == 4'h0) ? 4'd1 : ea;
    wire [3:0] eff_eb = (eb == 4'h0) ? 4'd1 : eb;

    // Swap so larger magnitude is A
    wire a_larger = (eff_ea > eff_eb) |
                    ((eff_ea == eff_eb) & ({hidden_a, ma} >= {hidden_b, mb}));

    wire [3:0] s1_exp_big  = a_larger ? eff_ea           : eff_eb;
    wire [3:0] s1_exp_sml  = a_larger ? eff_eb           : eff_ea;
    wire [3:0] man_big4    = a_larger ? {hidden_a, ma}   : {hidden_b, mb};
    wire [3:0] man_sml4    = a_larger ? {hidden_b, mb}   : {hidden_a, ma};
    wire       s1_sign_big = a_larger ? sa               : sb;
    wire       s1_sign_sml = a_larger ? sb               : sa;
    wire       s1_same_sgn = (s1_sign_big == s1_sign_sml);

    // Alignment shift (barrel shift small mantissa right by exp_diff)
    wire [3:0] exp_diff    = s1_exp_big - s1_exp_sml;  // 0..15
    wire [7:0] mant_big    = {man_big4, 4'b0};          // [7]=hidden [6:4]=m [3:0]=GRS
    wire [7:0] mant_sml_u  = {man_sml4, 4'b0};

    wire [7:0] mant_sml_sh;
    wire       sticky_s1;
    assign {mant_sml_sh, sticky_s1} =
        (exp_diff == 4'd0) ? {mant_sml_u,        1'b0}                          :
        (exp_diff == 4'd1) ? {1'b0, mant_sml_u[7:1], mant_sml_u[0]}            :
        (exp_diff == 4'd2) ? {2'b0, mant_sml_u[7:2], |mant_sml_u[1:0]}         :
        (exp_diff == 4'd3) ? {3'b0, mant_sml_u[7:3], |mant_sml_u[2:0]}         :
        (exp_diff == 4'd4) ? {4'b0, mant_sml_u[7:4], |mant_sml_u[3:0]}         :
        (exp_diff == 4'd5) ? {5'b0, mant_sml_u[7:5], |mant_sml_u[4:0]}         :
        (exp_diff == 4'd6) ? {6'b0, mant_sml_u[7:6], |mant_sml_u[5:0]}         :
        (exp_diff == 4'd7) ? {7'b0, mant_sml_u[7],   |mant_sml_u[6:0]}         :
                             {8'b0,                   |mant_sml_u[7:0]}         ;

    // 9-bit add/subtract
    wire [8:0] s1_mant_sum =
        s1_same_sgn ? ({1'b0, mant_big} + {1'b0, mant_sml_sh})
                    : ({1'b0, mant_big} - {1'b0, mant_sml_sh} - {8'd0, sticky_s1});

    // Exact-zero detection (subtraction cancellation)
    wire s1_exact_zero = ~s1_same_sgn & (s1_mant_sum[7:0] == 8'h00) & ~sticky_s1;

    // =========================================================================
    // STAGE 1 → STAGE 2 PIPELINE REGISTERS
    // =========================================================================
    reg [8:0] p1_mant_sum;    // 9-bit mantissa sum
    reg [3:0] p1_exp_big;     // exponent of larger operand
    reg       p1_sign_big;    // sign of result
    reg       p1_sticky;      // sticky bit from alignment shift
    reg       p1_same_sgn;    // add or subtract
    reg       p1_any_nan;     // NaN bypass
    reg       p1_exact_zero;  // exact zero
    reg       p1_zero_a;      // zero-passthrough flags
    reg       p1_zero_b;
    reg [7:0] p1_a;           // original inputs (for zero passthrough)
    reg [7:0] p1_b;
    reg       p1_valid;       // stage-1 data valid (start was seen)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p1_mant_sum  <= 9'd0;
            p1_exp_big   <= 4'd0;
            p1_sign_big  <= 1'b0;
            p1_sticky    <= 1'b0;
            p1_same_sgn  <= 1'b1;
            p1_any_nan   <= 1'b0;
            p1_exact_zero<= 1'b0;
            p1_zero_a    <= 1'b0;
            p1_zero_b    <= 1'b0;
            p1_a         <= 8'h00;
            p1_b         <= 8'h00;
            p1_valid     <= 1'b0;
        end else begin
            p1_valid     <= start;           // data valid one cycle after start
            if (start) begin
                p1_mant_sum   <= s1_mant_sum;
                p1_exp_big    <= s1_exp_big;
                p1_sign_big   <= s1_sign_big;
                p1_sticky     <= sticky_s1;
                p1_same_sgn   <= s1_same_sgn;
                p1_any_nan    <= s1_any_nan;
                p1_exact_zero <= s1_exact_zero;
                p1_zero_a     <= s1_zero_a;
                p1_zero_b     <= s1_zero_b;
                p1_a          <= s1_a;
                p1_b          <= s1_b;
            end
        end
    end

    // =========================================================================
    // STAGE 2 COMBINATIONAL — Normalise, round, pack
    // =========================================================================

    wire carry_out = p1_mant_sum[8];   // addition carry

    // --- LZD on p1_mant_sum[7:0] ---
    wire [2:0] lzd;
    assign lzd = p1_mant_sum[7] ? 3'd0 :
                 p1_mant_sum[6] ? 3'd1 :
                 p1_mant_sum[5] ? 3'd2 :
                 p1_mant_sum[4] ? 3'd3 :
                 p1_mant_sum[3] ? 3'd4 :
                 p1_mant_sum[2] ? 3'd5 :
                 p1_mant_sum[1] ? 3'd6 :
                                  3'd7 ;

    // --- Addition (carry) path: shift right 1, bump exp ---
    // After right-shift by 1: new {hidden,m2,m1,m0} = {1, mant_sum[7:5]}
    // GRS bits: G=mant_sum[4], R=mant_sum[3], S=|{mant_sum[2:0],sticky}
    wire [3:0] pre_man4_carry = {1'b1, p1_mant_sum[7:5]};
    wire [4:0] norm_exp_carry = {1'b0, p1_exp_big} + 5'd1;
    wire [2:0] grs_carry      = {p1_mant_sum[4], p1_mant_sum[3],
                                 |(p1_mant_sum[2:0] | {2'b0, p1_sticky})};

    wire signed [4:0] new_exp_sub_s = {1'b0, p1_exp_big} - {2'b0, lzd};
    wire              sub_subnormal = (new_exp_sub_s <= 5'sd0);
    wire [3:0]        norm_exp_sub  = sub_subnormal ? 4'd0 : new_exp_sub_s[3:0];

    wire [2:0] sub_shift = sub_subnormal ? (p1_exp_big[2:0] - 3'd1) : lzd;

    // --- Subtraction path: shift left by sub_shift ---
    wire [10:0] norm_wide =
        (sub_shift == 3'd0) ? {p1_mant_sum[7:0], 3'b0} :
        (sub_shift == 3'd1) ? {p1_mant_sum[6:0], 4'b0} :
        (sub_shift == 3'd2) ? {p1_mant_sum[5:0], 5'b0} :
        (sub_shift == 3'd3) ? {p1_mant_sum[4:0], 6'b0} :
        (sub_shift == 3'd4) ? {p1_mant_sum[3:0], 7'b0} :
        (sub_shift == 3'd5) ? {p1_mant_sum[2:0], 8'b0} :
        (sub_shift == 3'd6) ? {p1_mant_sum[1:0], 9'b0} :
                              {p1_mant_sum[0],  10'b0} ;

    wire [3:0] man_field_sub  = norm_wide[10:7];
    wire [2:0] grs_sub        = {norm_wide[6], norm_wide[5],
                                 |(norm_wide[4:0] | {4'b0, p1_sticky})};

    // --- Mux normalised fields ---
    wire [3:0] pre_man4 = carry_out ? pre_man4_carry : man_field_sub;
    wire [4:0] pre_exp  = carry_out ? norm_exp_carry  : {1'b0, norm_exp_sub};
    wire [2:0] grs      = carry_out ? grs_carry       : grs_sub;

    // --- Round-to-nearest-even ---
    wire round_up = grs[2] & (grs[1] | grs[0] | pre_man4[0]);

    // 5-bit addition to correctly detect rounding overflow.
    // pre_man4 = {hidden=1, m2, m1, m0}. Overflow only when 4'b1111 + 1 = 5'b10000.
    // rman[3] (4-bit) is ALWAYS 1 for normal (no-overflow) results and 0 on overflow,
    // so we must use the 5th carry bit — NOT rman[3].
    wire [4:0] rman5   = {1'b0, pre_man4} + {4'b0, round_up};
    wire       rcarry  = rman5[4];   // true overflow: 1.111 + 1 → 10.000

    wire [2:0] final_man = rman5[2:0];

    // Exponent after rounding (5-bit to detect exp overflow beyond 15)
    wire [4:0] final_exp_w = pre_exp + {4'b0, rcarry};
    wire [3:0] final_exp   = final_exp_w[3:0];

    // --- Overflow / saturation (max finite = 0x7E = S.1111.110 = 448.0) ---
    // NaN = exp=0xF, man=0x7; clamp there to 0x7E to avoid producing NaN.
    wire overflow = final_exp_w[4] |
                    (final_exp == 4'hF & final_man == 3'h7);
    wire [6:0] sat_mag = overflow ? 7'h7E : {final_exp, final_man};

    // --- Build stage-2 combinational result ---
    wire [7:0] s2_result =
        p1_any_nan    ? 8'h7F :
        p1_exact_zero ? 8'h00 :
        p1_zero_a     ? p1_b  :
        p1_zero_b     ? p1_a  :
                        {p1_sign_big, sat_mag};

    // =========================================================================
    // STAGE 2 OUTPUT REGISTERS + done/busy
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result <= 8'h00;
            done   <= 1'b0;
            busy   <= 1'b0;
        end else begin
            done <= 1'b0;           // default: de-assert

            if (start)
                busy <= 1'b1;       // busy from start

            if (p1_valid) begin
                result <= s2_result;
                done   <= 1'b1;     // done 2 cycles after start
                busy   <= 1'b0;
            end
        end
    end

endmodule
