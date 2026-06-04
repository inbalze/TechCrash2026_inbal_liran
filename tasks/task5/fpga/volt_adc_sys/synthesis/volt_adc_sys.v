// volt_adc_sys.v
// Hand-written top-level wrapper for the MAX 10 Modular ADC Qsys system.
// Exposes all ports required by volt_meter_top.sv.
// Generated submodule: volt_adc_sys_modular_adc_0 (CORE_VAR=3, external command/response)

`timescale 1 ps / 1 ps
module volt_adc_sys (
    // Clock and reset
    input  wire        clk_clk,
    input  wire        reset_reset_n,

    // ADC PLL clock (tie to system clock; adc_pll_locked tie to 1)
    input  wire        adc_pll_clock_clk,
    input  wire        adc_pll_locked_export,

    // Avalon-ST command (master drives to ADC)
    input  wire        command_valid,
    output wire        command_ready,
    input  wire  [4:0] command_channel,
    input  wire        command_startofpacket,
    input  wire        command_endofpacket,

    // Avalon-ST response (ADC drives to master)
    output wire        response_valid,
    output wire  [4:0] response_channel,
    output wire [11:0] response_data,
    output wire        response_startofpacket,
    output wire        response_endofpacket
);

    wire rst_controller_reset_out_reset;

    // ---- ADC core (CORE_VAR=3: external command/response, no internal sequencer) ----
    volt_adc_sys_modular_adc_0 #(
        .is_this_first_or_second_adc (1)
    ) modular_adc_0 (
        .clock_clk              (clk_clk),
        .reset_sink_reset_n     (~rst_controller_reset_out_reset),
        .adc_pll_clock_clk      (adc_pll_clock_clk),
        .adc_pll_locked_export  (adc_pll_locked_export),
        .command_valid          (command_valid),
        .command_channel        (command_channel),
        .command_startofpacket  (command_startofpacket),
        .command_endofpacket    (command_endofpacket),
        .command_ready          (command_ready),
        .response_valid         (response_valid),
        .response_channel       (response_channel),
        .response_data          (response_data),
        .response_startofpacket (response_startofpacket),
        .response_endofpacket   (response_endofpacket)
    );

    // ---- Reset synchroniser ----
    altera_reset_controller #(
        .NUM_RESET_INPUTS          (1),
        .OUTPUT_RESET_SYNC_EDGES   ("deassert"),
        .SYNC_DEPTH                (2),
        .RESET_REQUEST_PRESENT     (0),
        .RESET_REQ_WAIT_TIME       (1),
        .MIN_RST_ASSERTION_TIME    (3),
        .RESET_REQ_EARLY_DSRT_TIME (1),
        .USE_RESET_REQUEST_IN0     (0),
        .USE_RESET_REQUEST_IN1     (0),
        .USE_RESET_REQUEST_IN2     (0),
        .USE_RESET_REQUEST_IN3     (0),
        .USE_RESET_REQUEST_IN4     (0),
        .USE_RESET_REQUEST_IN5     (0),
        .USE_RESET_REQUEST_IN6     (0),
        .USE_RESET_REQUEST_IN7     (0),
        .USE_RESET_REQUEST_IN8     (0),
        .USE_RESET_REQUEST_IN9     (0),
        .USE_RESET_REQUEST_IN10    (0),
        .USE_RESET_REQUEST_IN11    (0),
        .USE_RESET_REQUEST_IN12    (0),
        .USE_RESET_REQUEST_IN13    (0),
        .USE_RESET_REQUEST_IN14    (0),
        .USE_RESET_REQUEST_IN15    (0),
        .ADAPT_RESET_REQUEST       (0)
    ) rst_controller (
        .reset_in0      (~reset_reset_n),
        .clk            (clk_clk),
        .reset_out      (rst_controller_reset_out_reset),
        .reset_req      (),
        .reset_req_in0  (1'b0),
        .reset_in1      (1'b0), .reset_req_in1  (1'b0),
        .reset_in2      (1'b0), .reset_req_in2  (1'b0),
        .reset_in3      (1'b0), .reset_req_in3  (1'b0),
        .reset_in4      (1'b0), .reset_req_in4  (1'b0),
        .reset_in5      (1'b0), .reset_req_in5  (1'b0),
        .reset_in6      (1'b0), .reset_req_in6  (1'b0),
        .reset_in7      (1'b0), .reset_req_in7  (1'b0),
        .reset_in8      (1'b0), .reset_req_in8  (1'b0),
        .reset_in9      (1'b0), .reset_req_in9  (1'b0),
        .reset_in10     (1'b0), .reset_req_in10 (1'b0),
        .reset_in11     (1'b0), .reset_req_in11 (1'b0),
        .reset_in12     (1'b0), .reset_req_in12 (1'b0),
        .reset_in13     (1'b0), .reset_req_in13 (1'b0),
        .reset_in14     (1'b0), .reset_req_in14 (1'b0),
        .reset_in15     (1'b0), .reset_req_in15 (1'b0)
    );

endmodule
