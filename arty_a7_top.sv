// Arty A7-100T: 100 MHz oscillator -> 47.619 MHz SoC clock.
module arty_a7_top (
    input  logic clk100,
    input  logic btn_reset,
    input  logic uart_rx_i,
    output logic uart_tx_o,
    output logic [2:0] led
);
    logic clk48_unbuffered;
    logic clk48;
    logic clk_feedback_unbuffered;
    logic clk_feedback;
    logic mmcm_locked;
    logic [1:0] reset_sync = 2'b00;
    logic soc_rstn;
    logic cpu_stall;
    logic aes_done;

    // VCO = 100 * 10 = 1000 MHz; CLKOUT0 = 1000 / 21 = 47.619 MHz.
    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKIN1_PERIOD(10.0),
        .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(10.0),
        .CLKOUT0_DIVIDE_F(21.0),
        .CLKOUT0_DUTY_CYCLE(0.5),
        .STARTUP_WAIT("FALSE")
    ) u_mmcm (
        .CLKIN1(clk100),
        .CLKFBIN(clk_feedback),
        .RST(1'b0),
        .PWRDWN(1'b0),
        .CLKFBOUT(clk_feedback_unbuffered),
        .CLKOUT0(clk48_unbuffered),
        .LOCKED(mmcm_locked)
    );

    BUFG u_feedback_buf (.I(clk_feedback_unbuffered), .O(clk_feedback));
    BUFG u_soc_clk_buf (.I(clk48_unbuffered), .O(clk48));

   always_ff @(posedge clk48 or negedge mmcm_locked or posedge btn_reset) begin
        if (!mmcm_locked || btn_reset)
            reset_sync <= 2'b00;
        else
            reset_sync <= {reset_sync[0], 1'b1};
    end
    assign soc_rstn = reset_sync[1];

    soc_top u_soc (
        .clk(clk48),
        .rstn(soc_rstn),
        .uart_rx_i(uart_rx_i),
        .uart_tx_o(uart_tx_o),
        .cpu_stall_debug(cpu_stall),
        .aes_done_debug(aes_done)
    );

    assign led = {aes_done, cpu_stall, mmcm_locked};
endmodule
