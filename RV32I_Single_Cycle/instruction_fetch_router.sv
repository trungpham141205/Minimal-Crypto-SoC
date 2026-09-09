module instruction_fetch_router #(
    parameter logic [31:0] BOOT_ROM_BASE   = 32'h0000_0000,
    parameter logic [31:0] BOOT_ROM_MASK   = 32'hFFFF_F000,
    parameter logic [31:0] INSTR_SRAM_BASE = 32'h0001_0000,
    parameter logic [31:0] INSTR_SRAM_MASK = 32'hFFFF_FC00
)(
    input  logic        fetch_req_i,
    input  logic [31:0] fetch_addr_i,

    output logic [31:0] fetch_instr_o,
    output logic        fetch_valid_o,

    // Read-only request forwarded to the shared CPU AXI request arbiter when
    // PC targets the downloaded-firmware SRAM region.
    output logic        axi_fetch_req_o,
    output logic [31:0] axi_fetch_addr_o,
    input  logic [31:0] axi_fetch_rdata_i,
    input  logic        axi_fetch_valid_i
);

    logic [31:0] boot_rom_instruction;
    logic        boot_rom_selected;
    logic        instr_sram_selected;

    instruction_memory u_boot_rom (
        .read_addr   (fetch_addr_i - BOOT_ROM_BASE),
        .instruction (boot_rom_instruction)
    );

    assign boot_rom_selected =
        ((fetch_addr_i & BOOT_ROM_MASK) == BOOT_ROM_BASE);

    assign instr_sram_selected =
        ((fetch_addr_i & INSTR_SRAM_MASK) == INSTR_SRAM_BASE);

    always_comb begin
        fetch_instr_o    = 32'h0000_0013;
        fetch_valid_o    = 1'b0;
        axi_fetch_req_o  = 1'b0;
        axi_fetch_addr_o = fetch_addr_i;

        if (fetch_req_i && boot_rom_selected) begin
            // Boot ROM is a combinational instruction source in the current
            // model, therefore a request is valid immediately.
            fetch_instr_o = boot_rom_instruction;
            fetch_valid_o = 1'b1;
        end
        else if (fetch_req_i && instr_sram_selected) begin
            axi_fetch_req_o = 1'b1;
            fetch_instr_o   = axi_fetch_rdata_i;
            fetch_valid_o   = axi_fetch_valid_i;
        end
    end

endmodule
