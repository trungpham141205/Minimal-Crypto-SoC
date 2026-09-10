# ==============================================================================
# SDC CONSTRAINTS FOR MODULE: soc_top
# ==============================================================================
set sdc_version 2.1
set_units -time ns

# SETUP: initial SoC integration target = 50 MHz
set CLK_PERIOD 20.0
set clk_pw [expr {$CLK_PERIOD / 2.0}]

# 1. CLOCK DEFINITION
create_clock -name CLK -period $CLK_PERIOD  -waveform [list 0 $clk_pw] [get_ports clk]

set_clock_uncertainty -setup 0.3 [get_clocks CLK]
set_clock_uncertainty -hold  0.1 [get_clocks CLK]
set_clock_transition 0.15 [get_clocks CLK]
set_clock_latency 0.0 [get_clocks CLK]

# 2. INPUT DELAYS
# set_input_delay -max 6.0 -clock CLK [get_ports {sync_input[*]}]
# set_input_delay -min 1.0 -clock CLK [get_ports {sync_input[*]}]

# 3. OUTPUT DELAYS
# uart_tx_o is launched by a CLK-domain register.
# Reserve 25% of the clock period for the external output environment.
set_output_delay -max 5.0 -clock CLK [get_ports {uart_tx_o}]
set_output_delay -min -1.0 -clock CLK [get_ports {uart_tx_o}]

# 4. ENVIRONMENT & DRIVE/LOAD CONSTRAINTS
# Exclude clk because its transition is constrained separately.
set DATA_INPUTS [remove_from_collection [all_inputs] [get_ports {clk}]]

set_input_transition -max 0.3 $DATA_INPUTS
set_input_transition -min 0.1 $DATA_INPUTS

set_load -pin_load 0.05 [all_outputs]

# 5. TIMING EXCEPTIONS
# Reset is asynchronous to CLK.
set_false_path -from [get_ports {rstn}]

# UART RX is asynchronous to CLK.
# The RX two-flop synchronizer is the intended CDC boundary.
set_false_path -from [get_ports {uart_rx_i}]

