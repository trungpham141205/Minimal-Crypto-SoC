# Timing constraints for soc_top at 49.5 MHz
# Clock period = 1000 / 49.5 = 20.202020 ns

create_clock -name CLK -period 20.4499 [get_ports clk]

set_clock_uncertainty -setup 0.300 [get_clocks CLK]
set_clock_uncertainty -hold  0.100 [get_clocks CLK]
set_clock_transition 0.150 [get_clocks CLK]
set_clock_latency 0.000 [get_clocks CLK]

# UART output timing budget
set_output_delay -max 5.000 -clock CLK [get_ports uart_tx_o]
set_output_delay -min -1.000 -clock CLK [get_ports uart_tx_o]

# External input assumptions
set DATA_INPUTS [remove_from_collection [all_inputs] [get_ports clk]]
set_input_transition -max 0.300 $DATA_INPUTS
set_input_transition -min 0.100 $DATA_INPUTS
set_load -pin_load 0.050 [all_outputs]

# Asynchronous interfaces
set_false_path -from [get_ports rstn]
set_false_path -from [get_ports uart_rx_i]
