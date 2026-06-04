transcript on
vlib work
vlog ../src/fp8_adder.v tb_lut_generator.v
vsim -c work.tb_lut_generator -do "run -all; quit -f"
