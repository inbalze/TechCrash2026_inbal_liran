# gen_adc_ip.tcl
# Run from task5/fpga/ with:
#   qsys-script.exe --script=gen_adc_ip.tcl --quartus-project=volt_meter
# Creates and generates volt_adc_sys.qsys for Quartus 17.1 / MAX 10

load_package qsys
create_system volt_adc_sys
set_project_property DEVICE_FAMILY {MAX 10}
set_project_property DEVICE {10M50DAF484C7G}

# --- clock source ---
add_instance clk_0 clock_source
set_instance_parameter_value clk_0 clockFrequency        {50000000}
set_instance_parameter_value clk_0 clockFrequencyKnown   {true}
set_instance_parameter_value clk_0 inputClockFrequency   {0}
set_instance_parameter_value clk_0 resetSynchronousEdges {NONE}

# --- Modular ADC (1 channel, standard sequencer, prescalar 10 → 2.5 MHz ADC clk) ---
add_instance modular_adc_0 altera_modular_adc
set_instance_parameter_value modular_adc_0 NUM_CHANNELS             {1}
set_instance_parameter_value modular_adc_0 SEQUENCER_TYPE           {STANDARD}
set_instance_parameter_value modular_adc_0 TSE_ENABLE               {0}
set_instance_parameter_value modular_adc_0 PRESCALAR                {10}
set_instance_parameter_value modular_adc_0 CHANNEL_SETTING_NUMBER_0 {SINGLE_ENDED}
set_instance_parameter_value modular_adc_0 SAMPLE_STORE_ENABLED     {0}

# --- Internal connections ---
add_connection clk_0.clk       modular_adc_0.clock_sink clock
add_connection clk_0.clk_reset modular_adc_0.reset_sink reset

# --- Exported interfaces ---
add_interface clk clock end
set_interface_property clk EXPORT_OF clk_0.clk_in

add_interface reset reset end
set_interface_property reset EXPORT_OF clk_0.clk_in_reset

add_interface adc_pll_clock clock end
set_interface_property adc_pll_clock EXPORT_OF modular_adc_0.adc_pll_clock

add_interface adc_pll_locked conduit end
set_interface_property adc_pll_locked EXPORT_OF modular_adc_0.adc_pll_locked

add_interface command avalon_streaming end
set_interface_property command EXPORT_OF modular_adc_0.command

add_interface response avalon_streaming start
set_interface_property response EXPORT_OF modular_adc_0.response

save_system volt_adc_sys.qsys

generate_system
