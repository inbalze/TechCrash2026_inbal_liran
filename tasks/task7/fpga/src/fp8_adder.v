// ============================================================================
// FP8 E4M3 Adder — 1-CYCLE PIPELINED IMPLEMENTATION
// ============================================================================
// Task 7 — CrashTech VLSI-2026 optimised replacement for fp8_adder.v
//
// Format: FP8 E4M3  (1 sign | 4 exponent | 3 mantissa)
//   Bias = 7.  No Infinity: exponent 0xF is a valid finite value.
//   NaN   = any value with exp=0xF and mantissa=0x7  (i.e., |x|[6:0]==7'h7F)
//
// Architecture: FULLY COMBINATIONAL datapath, result registered on the
//   SAME clock edge that sees start=1.  done is asserted the FOLLOWING
//   cycle (TC_WAIT_ADD sees done=1 immediately and advances to TC_CHECK).
//   This gives the minimum 1-cycle latency permitted by the test harness.
//
//   done  is de-asserted one cycle after being asserted (self-clearing FF).
//   busy  mirrors the single in-flight cycle (busy high only during
//         computation, for compatibility — effectively 1 clock wide).
//
// E4M3 edge cases handled:
//   1. NaN input (exp=0xF, man=0x7) → NaN output (0x7F regardless of sign)
//   2. +0 + -0 = +0  (IEEE-like rule: both zero → positive zero)
//   3. Any +0 operand → result is the other operand
//   4. Result magnitude overflow → clamp to max-finite 0x7E (= 448.0)
//   5. Subnormal (exp=0): hidden bit = 0, effective exponent = 1 (E4M3 spec)
//   6. Round-to-nearest-even on the 3-bit mantissa output
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
    // COMBINATIONAL DATAPATH
    // All wires are purely combinational — they read the registered a/b copies
    // that are latched when start fires.  The output of comb_result is
    // registered on the SAME posedge as start, producing a 1-cycle result.
    // =========================================================================

    // Registered copies of inputs (for busy state reuse — not used in comb path)
    reg [7:0] a_r, b_r;
    // Combinational path reads directly from module inputs a, b
    wire [7:0] ai = a;
    wire [7:0] bi = b;

    // ---- Unpack ----
    wire        sa = ai[7];
    wire [3:0]  ea = ai[6:3];
    wire [2:0]  ma = ai[2:0];

    wire        sb = bi[7];
    wire [3:0]  eb = bi[6:3];
    wire [2:0]  mb = bi[2:0];

    // ---- NaN detection (|x| bits[6:0] == 7'h7F) ----
    wire nan_a = (ea == 4'hF) && (ma == 3'h7);
    wire nan_b = (eb == 4'hF) && (mb == 3'h7);
    wire any_nan = nan_a | nan_b;

    // ---- Zero detection ----
    wire zero_a = (ai[6:0] == 7'h00);
    wire zero_b = (bi[6:0] == 7'h00);

    // ---- Hidden bit (0 for subnormals, 1 for normals) ----
    // E4M3: when exp==0 the implied bit is 0 and eff_exp = 1 (not 0)
    wire hidden_a = (ea != 4'h0);
    wire hidden_b = (eb != 4'h0);

    // ---- Effective (unbiased) exponent for alignment ----
    // For normals: eff_exp = ea (biased exponent; we keep it biased throughout)
    // For subnormals: eff_exp = 1 (effective biased exponent in E4M3)
    wire [3:0] eff_ea = (ea == 4'h0) ? 4'd1 : ea;
    wire [3:0] eff_eb = (eb == 4'h0) ? 4'd1 : eb;

    // ---- Determine which operand has the larger exponent ----
    // Swap so that A is always >= B in magnitude for alignment
    wire a_larger = (eff_ea > eff_eb) || ((eff_ea == eff_eb) && ({hidden_a,ma} >= {hidden_b,mb}));

    wire [3:0]  exp_big  = a_larger ? eff_ea    : eff_eb;
    wire [3:0]  exp_sml  = a_larger ? eff_eb    : eff_ea;
    wire [3:0]  man_big3 = a_larger ? {hidden_a, ma} : {hidden_b, mb};
    wire [3:0]  man_sml3 = a_larger ? {hidden_b, mb} : {hidden_a, ma};
    wire        sign_big = a_larger ? sa : sb;
    wire        sign_sml = a_larger ? sb : sa;

    // ---- Alignment shift ----
    // Max useful shift is 7 (3 mantissa bits + 1 hidden bit + guard/round/sticky).
    // We extend mantissas to 8 bits: [hidden . m2 m1 m0 . G R S sticky]
    // Representation: {hidden, man[2:0], 4'b0} = 8-bit left-justified
    // Then right-shift small operand by exp_diff.
    wire [3:0] exp_diff = exp_big - exp_sml;   // 0..15; >7 means small is negligible

    // 8-bit extended mantissas (big has full precision; small will be shifted)
    wire [7:0] mant_big = {man_big3, 4'b0};    // [7]=hidden [6:4]=m2..m0 [3:0]=guard+round+sticky
    wire [7:0] mant_sml_unshifted = {man_sml3, 4'b0};

    // Right-shift small mantissa; collect OR of lost bits into sticky
    // We shift up to 8 positions; anything shifted ≥8 positions is pure sticky.
    wire [7:0] mant_sml_shifted;
    wire       sticky_sml;

    assign {mant_sml_shifted, sticky_sml} =
        (exp_diff == 4'd0) ? {mant_sml_unshifted, 1'b0} :
        (exp_diff == 4'd1) ? {1'b0, mant_sml_unshifted[7:1], mant_sml_unshifted[0]}             :
        (exp_diff == 4'd2) ? {2'b0, mant_sml_unshifted[7:2], |mant_sml_unshifted[1:0]}          :
        (exp_diff == 4'd3) ? {3'b0, mant_sml_unshifted[7:3], |mant_sml_unshifted[2:0]}          :
        (exp_diff == 4'd4) ? {4'b0, mant_sml_unshifted[7:4], |mant_sml_unshifted[3:0]}          :
        (exp_diff == 4'd5) ? {5'b0, mant_sml_unshifted[7:5], |mant_sml_unshifted[4:0]}          :
        (exp_diff == 4'd6) ? {6'b0, mant_sml_unshifted[7:6], |mant_sml_unshifted[5:0]}          :
        (exp_diff == 4'd7) ? {7'b0, mant_sml_unshifted[7],   |mant_sml_unshifted[6:0]}          :
                             {8'b0,                           |mant_sml_unshifted[7:0]}          ;

    // ---- Add or subtract aligned mantissas ----
    wire same_sign = (sign_big == sign_sml);

    // 9-bit to detect carry / borrow; bit 8 is carry/borrow
    wire [8:0] mant_sum =
        same_sign ? ({1'b0, mant_big} + {1'b0, mant_sml_shifted})
                  : ({1'b0, mant_big} - {1'b0, mant_sml_shifted});

    wire result_sign = sign_big;

    // ---- Detect zero result (exact cancellation) ----
    wire exact_zero = !same_sign && (mant_sum[7:0] == 8'h00) && !sticky_sml;

    // ---- Normalise ----
    // After add: possible overflow into bit8 → shift right 1, inc exp
    // After subtract: need to shift left (LZD on 8-bit mant_sum[7:0])

    // Leading-zero detect on bits [7:4] (the meaningful part: hidden + 3 mantissa + guard)
    // We look at bits [7:4] of mant_sum — these are the "integer" part
    // [7] = carry out of addition, or hidden bit after subtraction
    // We need to find the position of the leading 1 in mant_sum[7:0]

    wire carry_out = mant_sum[8];      // only set after addition

    // Post-add: if carry, shift right 1 and increment exponent
    // Post-sub: shift left until hidden bit is in position 7

    // LZD — find number of leading zeros in mant_sum[7:0]
    // Returns 0 if bit7=1, 1 if bit6 is leading 1, etc.
    wire [2:0] lzd;
    assign lzd = mant_sum[7] ? 3'd0 :
                 mant_sum[6] ? 3'd1 :
                 mant_sum[5] ? 3'd2 :
                 mant_sum[4] ? 3'd3 :
                 mant_sum[3] ? 3'd4 :
                 mant_sum[2] ? 3'd5 :
                 mant_sum[1] ? 3'd6 :
                               3'd7 ;

    // After subtraction: new exponent = exp_big - lzd
    // After addition (carry): exp_big + 1
    // Need signed arithmetic to detect subnormal underflow

    // We normalise the 8-bit mantissa + sticky bit to produce
    // a 4-bit hidden+mantissa field and 4-bit guard+round+sticky

    // --- Post-addition (carry case): shift right by 1 ---
    wire [7:0] norm_mant_carry = {1'b1, mant_sum[7:1]};   // hidden=1 implied
    wire [3:0] norm_exp_carry;
    assign norm_exp_carry = (exp_big == 4'hF) ? 4'hF        // clamp at max exponent
                                              : exp_big + 4'd1;
    wire [1:0] round_bits_carry = {mant_sum[0], sticky_sml};

    // --- Post-subtraction (no carry): shift left by lzd ---
    // Left-shift mant_sum by lzd to normalise; the result must keep:
    // bits [7:4] = {1'b1, mantissa[2:0]}
    // Shift: produce a 12-bit wide field so we can extract round bits
    wire [10:0] norm_shift_wide =
        (lzd == 3'd0) ? {mant_sum[7:0], 3'b0}  :
        (lzd == 3'd1) ? {mant_sum[6:0], 4'b0}  :
        (lzd == 3'd2) ? {mant_sum[5:0], 5'b0}  :
        (lzd == 3'd3) ? {mant_sum[4:0], 6'b0}  :
        (lzd == 3'd4) ? {mant_sum[3:0], 7'b0}  :
        (lzd == 3'd5) ? {mant_sum[2:0], 8'b0}  :
        (lzd == 3'd6) ? {mant_sum[1:0], 9'b0}  :
                        {mant_sum[0],  10'b0}  ;
    // norm_shift_wide[10:7] = {hidden, m2, m1, m0}
    // norm_shift_wide[6:4]  = {G, R, S_upper}
    // norm_shift_wide[3:0]  = lower sticky bits
    wire [3:0] man_field_sub  = norm_shift_wide[10:7];     // {hidden, man[2:0]}
    wire [2:0] round_bits_sub = {norm_shift_wide[6], norm_shift_wide[5],
                                 |{norm_shift_wide[4:0], sticky_sml}};

    // Exponent after left normalisation; can go below 1 → subnormal
    wire signed [4:0] new_exp_sub_signed = {1'b0, exp_big} - {2'b0, lzd};
    wire              sub_subnormal = new_exp_sub_signed <= 5'sd0;
    wire [3:0]        norm_exp_sub  = sub_subnormal ? 4'd0 : new_exp_sub_signed[3:0];

    // ---- Round-to-nearest-even (3-bit mantissa output = bits [6:4] of mant) ----
    // GRS = {Guard, Round, Sticky}
    // Round up if: G=1 && (R|S=1) [round up if > halfway]
    //              OR G=1 && R=0 && S=0 && mantissa_lsb=1 [tie → round up if odd]

    // Mux normalised fields
    wire [3:0] pre_round_man4;  // {hidden, man[2:0]}
    wire [3:0] pre_round_exp;
    wire [2:0] grs;             // {Guard, Round, Sticky}

    assign pre_round_man4 = carry_out ? norm_mant_carry[7:4]
                                      : man_field_sub;
    assign pre_round_exp  = carry_out ? norm_exp_carry
                                      : norm_exp_sub;
    assign grs            = carry_out ? {round_bits_carry, sticky_sml}
                                      : round_bits_sub;

    wire round_up = grs[2] && (grs[1] || grs[0] || pre_round_man4[0]);
    wire [3:0] rounded_man4 = pre_round_man4 + {3'b0, round_up};

    // If rounding caused an overflow in the mantissa (4'h10 = carry into hidden bit)
    wire round_carry = rounded_man4[3];   // bit3 = hidden bit position after addition

    // Final mantissa (3 bits) and exponent
    wire [2:0] final_man;
    wire [3:0] final_exp;

    assign final_man = round_carry ? rounded_man4[2:0]   // mantissa wrapped OK; exp bumped
                                   : rounded_man4[2:0];
    assign final_exp = round_carry ? pre_round_exp + 4'd1
                                   : pre_round_exp;

    // ---- Overflow / saturation ----
    // Max finite = exp=0xF, man=0x6 (0x7E = 448.0)
    // NaN = exp=0xF, man=0x7; we must NOT produce NaN as a result.
    wire overflow = (final_exp == 4'hF && final_man == 3'h7) || (final_exp > 4'hF);
    wire [6:0] sat_result = overflow ? 7'h7E : {final_exp, final_man};

    // ---- Build combinational result ----
    wire [7:0] comb_result;
    assign comb_result =
        any_nan       ? 8'h7F                              : // NaN (canonical positive)
        exact_zero    ? ((!sa && !sb) ? 8'h00 : 8'h00)    : // +0 + -0 = +0
        zero_a        ? bi                                  : // 0 + b = b
        zero_b        ? ai                                  : // a + 0 = a
                        {result_sign, sat_result};

    // =========================================================================
    // REGISTERED OUTPUT STAGE
    // The combinational path reads directly from inputs a, b.
    // On the posedge where start=1, comb_result is already valid
    // (a and b are stable per the test harness — adder_a/b are
    // registered in TC_WAIT_MEM and held stable through TC_LAUNCH).
    // We register comb_result on that same edge and assert done one
    // cycle later (TC_WAIT_ADD sees done=1 on the very next clock).
    //
    // Pipeline:
    //   Cycle 0: TC_LAUNCH fires start=1, a/b stable → comb_result valid
    //   Cycle 1: (TC_WAIT_ADD) result registered, done=1 → TC_CHECK
    // Total adder contribution: 1 cycle.
    // =========================================================================
    reg result_valid_next;   // one-cycle delay flag

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_r               <= 8'h00;
            b_r               <= 8'h00;
            result            <= 8'h00;
            done              <= 1'b0;
            busy              <= 1'b0;
            result_valid_next <= 1'b0;
        end else begin
            done              <= 1'b0;              // default: de-assert
            result_valid_next <= 1'b0;

            if (start) begin
                // Latch result of current a/b into output register
                result            <= comb_result;
                result_valid_next <= 1'b1;
                busy              <= 1'b1;
            end

            if (result_valid_next) begin
                done <= 1'b1;
                busy <= 1'b0;
            end
        end
    end

endmodule
