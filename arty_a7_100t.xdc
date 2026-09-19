# Digilent Arty A7-100 Rev. D/E pin map.
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports clk100]
create_clock -name clk100 -period 10.000 [get_ports clk100]
set_property -dict {PACKAGE_PIN D9 IOSTANDARD LVCMOS33} [get_ports btn_reset]
set_property -dict {PACKAGE_PIN A9 IOSTANDARD LVCMOS33} [get_ports uart_rx_i]
set_property -dict {PACKAGE_PIN D10 IOSTANDARD LVCMOS33} [get_ports uart_tx_o]
set_property -dict {PACKAGE_PIN H5 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN J5 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN T9 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
