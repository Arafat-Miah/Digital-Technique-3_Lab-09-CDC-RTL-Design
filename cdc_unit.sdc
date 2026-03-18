######################################################################################
# cdc_unit.sdc: Timing Constraints File
#####################################################################################

# 1. Define clock period and clock edge times in ns
create_clock -name clk  -period 10.0 clk
create_clock -name mclk -period 54.2 mclk

set_clock_groups -asynchronous -name cdc_unit_clk_domains -group clk -group mclk

# 2. Define reset input delay relative to clock clk in ns
set_input_delay  -clock clk 5.0 rst_n

# 3. Define data input external delays
# Set clk domain inputs to 1/8 of the clk period (10.0 / 8 = 1.25 ns)
set_input_delay  -clock clk 1.25 test_mode_in
set_input_delay  -clock clk 1.25 audio0_in
set_input_delay  -clock clk 1.25 audio1_in
set_input_delay  -clock clk 1.25 play_in
set_input_delay  -clock clk 1.25 tick_in

# Set mclk domain inputs to 1/8 of the mclk period (54.2 / 8 = 6.775 ns)
set_input_delay  -clock mclk 6.775 req_in

# 4. Define output external delays relative to clock mclk in ns
# Set mclk domain outputs to 1/8 of the mclk period (54.2 / 8 = 6.775 ns)
set_output_delay  -clock mclk 6.775 audio0_out
set_output_delay  -clock mclk 6.775 audio1_out
set_output_delay  -clock mclk 6.775 tick_out
set_output_delay  -clock mclk 6.775 play_out 

# Set clk domain outputs to 1/8 of the clk period (10.0 / 8 = 1.25 ns)
set_output_delay  -clock clk 1.25 req_out
