// =============================================================================
// nn_accelerator.sv — Fixed-Point 4-4-1 Feedforward Neural Network Accelerator
//
// Fixed-point format: Q7.8 signed 16-bit for weights / biases
//   Encoding: integer value = round(float_value × 256)
//   Range: [-128.0, +127.996]
//
// Inputs: signed 8-bit Q0.7
//   Encoding: integer value = round(float_value × 128)
//   Range: [-1.0, +0.992]
//
// Hidden activation: ReLU
// Output activation: Step at zero (equivalent to sigmoid > 0.5)
//
// Latency: fully combinational — result valid on same cycle as inputs
// =============================================================================
module nn_accelerator (
    // ── Weight / bias load port ──────────────────────────────────────────────
    input  logic        clk,
    input  logic        rst_n,
    input  logic        weight_wr_en,
    input  logic [4:0]  weight_addr,   // 0..24 (25 parameters total)
    input  logic [15:0] weight_data,   // Q7.8 signed

    // ── Inference port ───────────────────────────────────────────────────────
    input  logic signed [7:0]  in0,   // bird_y_norm   Q0.7
    input  logic signed [7:0]  in1,   // bird_vy_norm  Q0.7
    input  logic signed [7:0]  in2,   // dx_norm       Q0.7
    input  logic signed [7:0]  in3,   // dy_norm       Q0.7

    output logic        decision,     // 1 = FLAP, 0 = NO FLAP
    output logic        weights_loaded // 1 once a full weight stream has been received
);
    // ── Weight registers ─────────────────────────────────────────────────────
    // Layout (matches NeuralNetwork.h flat array order):
    //   [0..15]  w0[0..15]  input→hidden weights [hidden][input] row-major
    //   [16..19] b0[0..3]   hidden biases
    //   [20..23] w1[0..3]   hidden→output weights
    //   [24]     b1[0]      output bias
    logic signed [15:0] weights [0:24];

    // weights_loaded: set when the last weight (addr 24) is written.
    // Prevents the zero-weight default (o_acc==0 → FLAP) from firing before
    // the ESP32 has finished streaming the trained network to the FPGA.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int k = 0; k < 25; k++) weights[k] <= 16'sd0;
            weights_loaded <= 1'b0;
        end else if (weight_wr_en) begin
            weights[weight_addr] <= $signed(weight_data);
            if (weight_addr == 5'd24)
                weights_loaded <= 1'b1;
        end
    end

    // ── Aliases for readability ───────────────────────────────────────────────
    // w0[h][i] = weights[h*4 + i]
    // b0[h]    = weights[16 + h]
    // w1[h]    = weights[20 + h]
    // b1       = weights[24]

    // ── Gather inputs into array ─────────────────────────────────────────────
    logic signed [7:0] nn_in [0:3];
    assign nn_in[0] = in0;
    assign nn_in[1] = in1;
    assign nn_in[2] = in2;
    assign nn_in[3] = in3;

    // ── Hidden layer (ReLU) ───────────────────────────────────────────────────
    // For each hidden neuron h:
    //   acc[h] = b0[h]  +  sum_i( w0[h][i] * in[i] )
    //
    // Precision analysis:
    //   w0  :  Q7.8  → scale 256
    //   in  :  Q0.7  → scale 128
    //   product: 16b × 8b = 24b,  scale = 256*128 = 32768
    //   normalize to Q7.8 (scale 256) by arithmetic right shift >>7
    //   bias b0: Q7.8, scale 256 — sign-extend to 32b directly
    //   accumulator: 32-bit signed — sum of 4 products + bias easily fits
    //
    logic signed [31:0] h_acc  [0:3];
    logic signed [15:0] hidden [0:3];   // ReLU output in Q7.8

    generate
        genvar h, ii;
        for (h = 0; h < 4; h++) begin : gen_hidden
            // Products for each hidden neuron
            logic signed [31:0] prod [0:3];
            for (ii = 0; ii < 4; ii++) begin : gen_prod
                assign prod[ii] =
                    ($signed({{24{nn_in[ii][7]}}, nn_in[ii]}) *
                     $signed({{16{weights[h*4+ii][15]}}, weights[h*4+ii]})) >>> 7;
                    // 32b × 32b → 32b (lower bits taken after arithmetic shift)
                    // Compiler will optimise to 24-bit actual multiplier input widths
            end

            assign h_acc[h] =
                {{16{weights[16+h][15]}}, weights[16+h]}
                + prod[0] + prod[1] + prod[2] + prod[3];

            // ReLU: clamp to [0, 32767]
            assign hidden[h] = h_acc[h][31] ? 16'sd0
                              : (|h_acc[h][31:15] ? 16'sd32767
                                                  : h_acc[h][15:0]);
        end
    endgenerate

    // ── Output layer (step at zero = sigmoid > 0.5) ──────────────────────────
    // out_acc = b1 + sum_h( w1[h] * hidden[h] )
    //
    // Precision:
    //   hidden: Q7.8, scale 256 (after ReLU, range [0, 32767])
    //   w1    : Q7.8, scale 256
    //   product: 16b × 16b = 32b, scale = 256*256 = 65536
    //   normalize to Q7.8 by >>8
    //   accumulator: 32-bit signed
    //
    logic signed [31:0] o_acc;
    logic signed [31:0] o_prod [0:3];

    generate
        genvar oh;
        for (oh = 0; oh < 4; oh++) begin : gen_oprod
            assign o_prod[oh] =
                ($signed(hidden[oh]) * $signed(weights[20+oh])) >>> 8;
        end
    endgenerate

    assign o_acc = {{16{weights[24][15]}}, weights[24]}
                 + o_prod[0] + o_prod[1] + o_prod[2] + o_prod[3];

    // Decision: output 1 (FLAP) when accumulator is non-negative AND weights
    // have been loaded at least once.  When weights are all-zero (power-up /
    // before the ESP32 streams the trained network) o_acc == 0, which would
    // erroneously force FLAP=1 every frame.  Gating on weights_loaded makes
    // the safe default NO-FLAP so the bird falls gently rather than rocketing
    // off the top of the screen and crashing in the first 12 frames.
    assign decision = weights_loaded & ~o_acc[31];

endmodule
