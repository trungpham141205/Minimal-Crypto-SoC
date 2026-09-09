module axi_shared_sram_slave #(
    parameter logic [31:0] BASE_ADDR = 32'h0000_0000
)(
    axi_full_if.slave s_axi
);

    logic        sram_me;
    logic        sram_we;
    logic [7:0]  sram_addr;
    logic [31:0] sram_wdata;
    logic [31:0] sram_rdata;

    // One independent controller instance owns the transaction state for the
    // shared/data SRAM.
    axi_sram_controller #(
        .BASE_ADDR (BASE_ADDR)
    ) u_ctrl (
        .s_axi      (s_axi),
        .sram_me    (sram_me),
        .sram_we    (sram_we),
        .sram_addr  (sram_addr),
        .sram_wdata (sram_wdata),
        .sram_rdata (sram_rdata)
    );

    shared_sram_256x32_wrapper u_sram (
        .clk   (s_axi.clk),
        .me    (sram_me),
        .addr  (sram_addr),
        .we    (sram_we),
        .wdata (sram_wdata),
        .rdata (sram_rdata)
    );

endmodule
