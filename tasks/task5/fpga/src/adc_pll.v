// adc_pll.v — PLL wrapper for MAX 10 Modular ADC
// Input: 50 MHz; Output c0: 10 MHz (acceptable ADC PLL clock)
// The MAX 10 ADC primitive requires its clock from a PLL c-counter output.

module adc_pll (
    input  wire inclk0,   // 50 MHz system clock
    output wire c0,       // 10 MHz → adc_pll_clock_clk
    output wire locked    // → adc_pll_locked_export
);

altpll #(
    .intended_device_family ("MAX 10"),
    .lpm_type               ("altpll"),
    .pll_type               ("AUTO"),
    .compensate_clock       ("CLK0"),
    .inclk0_input_frequency (20000),   // 20000 ps period = 50 MHz
    .operation_mode         ("NORMAL"),
    .clk0_divide_by         (5),
    .clk0_multiply_by       (1),
    .clk0_phase_shift       ("0"),
    .clk0_duty_cycle        (50),
    .port_clkena0           ("PORT_UNUSED"),
    .port_clkena1           ("PORT_UNUSED"),
    .port_clkena2           ("PORT_UNUSED"),
    .port_clkena3           ("PORT_UNUSED"),
    .port_clkena4           ("PORT_UNUSED"),
    .port_clkena5           ("PORT_UNUSED")
) altpll_component (
    .inclk  ({1'b0, inclk0}),
    .clk    ({4'b0, c0}),
    .locked (locked),
    .activeclock (),
    .areset (1'b0),
    .clkbad (),
    .clkena ({6{1'b1}}),
    .clkloss (),
    .clkswitch (1'b0),
    .configupdate (1'b0),
    .enable0 (),
    .enable1 (),
    .extclk (),
    .extclkena ({4{1'b1}}),
    .fbin (1'b1),
    .fbmimicbidir (),
    .fbout (),
    .fref (),
    .icdrclk (),
    .pfdena (1'b1),
    .phasecounterselect ({4{1'b1}}),
    .phasedone (),
    .phasestep (1'b1),
    .phaseupdown (1'b1),
    .pllena (1'b1),
    .scanaclr (1'b0),
    .scanclk (1'b0),
    .scanclkena (1'b1),
    .scandata (1'b0),
    .scandataout (),
    .scandone (),
    .scanread (1'b0),
    .scanwrite (1'b0),
    .sclkout0 (),
    .sclkout1 (),
    .vcooverrange (),
    .vcounderrange ()
);

endmodule
