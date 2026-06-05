project_open fp8_adder
create_timing_netlist
read_sdc
update_timing_netlist
report_timing -setup -npaths 5 -detail full_path -file timing_setup_report.txt
project_close
