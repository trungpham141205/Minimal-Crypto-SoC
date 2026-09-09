module instruction_sram_256x32_wrapper (
    input  logic        clk,
    input  logic        me,
    input  logic [7:0]  addr,
    input  logic        we,
    input  logic [31:0] wdata,
    output logic [31:0] rdata
);

    // SRAM1RW256x32 pin polarity from the supplied model:
    //   CE  : clock, active on posedge
    //   CSB : chip select, active LOW
    //   WEB : write enable, active LOW
    //   OEB : output enable, active LOW
    //
    // The macro has no byte-write mask. Partial stores are therefore
    // implemented as read-modify-write in axi_sram_slave.

    SRAM1RW256x32 u_sram (
        .A   (addr),
        .CE  (clk),
        .WEB (~we),
        .OEB (1'b0),
        .CSB (~me),
        .I   (wdata),
        .O   (rdata)
    );

endmodule
