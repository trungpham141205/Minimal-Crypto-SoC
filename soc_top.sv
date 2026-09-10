module soc_top (
    input  logic clk,
    input  logic rstn,

    // External UART pins
    input  logic uart_rx_i,
    output logic uart_tx_o,

    // Bring-up / debug outputs
    output logic cpu_stall_debug,
    output logic aes_done_debug
);

    // -------------------------------------------------------------------------
    // Address map
    //
    // Instruction fetch space:
    //   0x0000_0000 - 0x0000_0FFF : Boot ROM (fetch-only path)
    //   0x0001_0000 - 0x0001_03FF : Instruction/Firmware SRAM (AXI)
    //
    // Load/store/MMIO space:
    //   0x0000_0000 - 0x0000_01FF : Shared/Data SRAM
    //   0x0001_0000 - 0x0001_03FF : Instruction/Firmware SRAM
    //   0x1000_0000 - 0x1000_0FFF : UART MMIO
    //   0x2000_0000 - 0x2000_0FFF : AES MMIO
    //
    // Boot ROM and shared SRAM intentionally overlap in numerical address at
    // this stage because instruction fetch and load/store are separate clients.
    // -------------------------------------------------------------------------
    localparam logic [31:0] BOOT_ROM_BASE    = 32'h0000_0000;
    localparam logic [31:0] BOOT_ROM_MASK    = 32'hFFFF_F000;

    localparam logic [31:0] SHARED_SRAM_BASE = 32'h0000_0000;
    localparam logic [31:0] SHARED_SRAM_MASK = 32'hFFFF_FE00;

    localparam logic [31:0] INSTR_SRAM_BASE  = 32'h0001_0000;
    localparam logic [31:0] INSTR_SRAM_MASK  = 32'hFFFF_FC00;

    localparam logic [31:0] UART_BASE        = 32'h1000_0000;
    localparam logic [31:0] UART_MASK        = 32'hFFFF_F000;

    localparam logic [31:0] AES_BASE         = 32'h2000_0000;
    localparam logic [31:0] AES_MASK         = 32'hFFFF_F000;

    // =========================================================================
    // CPU instruction-fetch interface
    // =========================================================================
    logic [31:0] cpu_fetch_addr;
    logic        cpu_fetch_req;
    logic [31:0] cpu_fetch_instr;
    logic        cpu_fetch_valid;

    // Router -> L1 I-cache (firmware SRAM region only)
    logic        icache_cpu_req;
    logic [31:0] icache_cpu_addr;
    logic [31:0] icache_cpu_rdata;
    logic        icache_cpu_valid;

    // L1 I-cache -> shared CPU AXI request arbiter.  Only misses/refills
    // appear on this interface; cache hits never consume AXI bandwidth.
    logic        axi_fetch_req;
    logic [31:0] axi_fetch_addr;
    logic [31:0] axi_fetch_rdata;
    logic        axi_fetch_valid;

    logic        icache_invalidate;
    logic        icache_hit;
    logic        icache_miss;
    logic        icache_busy;

    // =========================================================================
    // CPU native load/store interface
    // =========================================================================
    logic [31:0] cpu_mem_addr;
    logic [31:0] cpu_mem_wdata;
    logic        cpu_mem_read;
    logic        cpu_mem_write;
    logic [2:0]  cpu_mem_funct3;
    logic [31:0] cpu_mem_rdata;
    logic        cpu_mem_stall;

    // =========================================================================
    // Unified native request into the existing AXI master wrapper
    // =========================================================================
    logic [31:0] axi_req_addr;
    logic [31:0] axi_req_wdata;
    logic        axi_req_read;
    logic        axi_req_write;
    logic [2:0]  axi_req_funct3;
    logic [31:0] axi_req_rdata;
    logic        axi_master_stall;

    // -------------------------------------------------------------------------
    // AXI links
    // -------------------------------------------------------------------------
    axi_full_if #(
        .ADDR_WIDTH (32),
        .DATA_WIDTH (32),
        .ID_WIDTH   (4)
    ) cpu_axi (
        .clk  (clk),
        .rstn (rstn)
    );

    axi_full_if #(
        .ADDR_WIDTH (32),
        .DATA_WIDTH (32),
        .ID_WIDTH   (4)
    ) shared_sram_axi (
        .clk  (clk),
        .rstn (rstn)
    );

    axi_full_if #(
        .ADDR_WIDTH (32),
        .DATA_WIDTH (32),
        .ID_WIDTH   (4)
    ) instr_sram_axi (
        .clk  (clk),
        .rstn (rstn)
    );

    axi_full_if #(
        .ADDR_WIDTH (32),
        .DATA_WIDTH (32),
        .ID_WIDTH   (4)
    ) uart_axi (
        .clk  (clk),
        .rstn (rstn)
    );

    axi_full_if #(
        .ADDR_WIDTH (32),
        .DATA_WIDTH (32),
        .ID_WIDTH   (4)
    ) aes_axi (
        .clk  (clk),
        .rstn (rstn)
    );

    // Fetch waits are represented by fetch_req without fetch_valid; data waits
    // are represented by cpu_mem_stall.  This output is only for bring-up.
    assign cpu_stall_debug =
        (cpu_fetch_req && !cpu_fetch_valid) || cpu_mem_stall;

    // =========================================================================
    // 1. RV32I SINGLE-CYCLE EXECUTION CORE WITH EXTERNAL FETCH INTERFACE
    // =========================================================================
    risc_top u_cpu (
        .clk            (clk),
        .rstn           (rstn),

        .fetch_addr_o   (cpu_fetch_addr),
        .fetch_req_o    (cpu_fetch_req),
        .fetch_instr_i  (cpu_fetch_instr),
        .fetch_valid_i  (cpu_fetch_valid),

        .data_stall_i   (cpu_mem_stall),
        .mem_read_wire  (cpu_mem_read),
        .mem_write_wire (cpu_mem_write),
        .funct3_wire    (cpu_mem_funct3),
        .mem_addr       (cpu_mem_addr),
        .mem_wdata      (cpu_mem_wdata),
        .mem_rdata      (cpu_mem_rdata)
    );

    // =========================================================================
    // 2. INSTRUCTION SOURCE SELECTOR
    //
    // Boot-ROM addresses are served locally.  Firmware-SRAM addresses become
    // a read request to the unified CPU AXI path.
    // =========================================================================
    instruction_fetch_router #(
        .BOOT_ROM_BASE   (BOOT_ROM_BASE),
        .BOOT_ROM_MASK   (BOOT_ROM_MASK),
        .INSTR_SRAM_BASE (INSTR_SRAM_BASE),
        .INSTR_SRAM_MASK (INSTR_SRAM_MASK)
    ) u_fetch_router (
        .fetch_req_i       (cpu_fetch_req),
        .fetch_addr_i      (cpu_fetch_addr),
        .fetch_instr_o     (cpu_fetch_instr),
        .fetch_valid_o     (cpu_fetch_valid),

        .axi_fetch_req_o   (icache_cpu_req),
        .axi_fetch_addr_o  (icache_cpu_addr),
        .axi_fetch_rdata_i (icache_cpu_rdata),
        .axi_fetch_valid_i (icache_cpu_valid)
    );

    // =========================================================================
    // 3. L1 INSTRUCTION CACHE
    //
    // Direct-mapped, 512 bytes, 16-byte lines, blocking refill.  Boot ROM
    // bypasses this block in instruction_fetch_router; only firmware SRAM
    // addresses reach the cache.  Any CPU store to executable SRAM invalidates
    // all lines so a later fetch cannot observe stale instructions.
    // =========================================================================
    // Register the invalidate request to break the long combinational path
    // from instruction fetch/cache lookup through CPU decode and address
    // generation back into the cache write enables.  Hold the registered
    // request only while the store is stalled.  On the completion edge the
    // cache still observes the previous high value, while the register clears
    // in time for the next cycle's instruction fetch/refill.
    always_ff @(posedge clk) begin
        if (!rstn) begin
            icache_invalidate <= 1'b0;
        end
        else begin
            icache_invalidate <=
                cpu_mem_write && cpu_mem_stall &&
                ((cpu_mem_addr & INSTR_SRAM_MASK) == INSTR_SRAM_BASE);
        end
    end

    l1_icache #(
        .NUM_SETS       (32),
        .WORDS_PER_LINE (4)
    ) u_l1_icache (
        .clk              (clk),
        .rstn             (rstn),

        .cpu_req_i        (icache_cpu_req),
        .cpu_addr_i       (icache_cpu_addr),
        .cpu_instr_o      (icache_cpu_rdata),
        .cpu_valid_o      (icache_cpu_valid),

        .mem_req_o        (axi_fetch_req),
        .mem_addr_o       (axi_fetch_addr),
        .mem_rdata_i      (axi_fetch_rdata),
        .mem_valid_i      (axi_fetch_valid),

        .invalidate_all_i (icache_invalidate),
        .hit_o            (icache_hit),
        .miss_o           (icache_miss),
        .busy_o           (icache_busy)
    );

    // =========================================================================
    // 4. FETCH / LOAD-STORE ARBITRATION BEFORE AXI MASTER
    //
    // Exactly one native request owns axi_master_wrapper at a time.  The owner
    // is retained until the AXI transaction completes so the response can be
    // routed to the correct client.
    // =========================================================================
    cpu_axi_request_arbiter u_cpu_axi_arbiter (
        .clk             (clk),
        .rstn            (rstn),

        .fetch_req_i     (axi_fetch_req),
        .fetch_addr_i    (axi_fetch_addr),
        .fetch_rdata_o   (axi_fetch_rdata),
        .fetch_valid_o   (axi_fetch_valid),

        .data_addr_i     (cpu_mem_addr),
        .data_wdata_i    (cpu_mem_wdata),
        .data_read_i     (cpu_mem_read),
        .data_write_i    (cpu_mem_write),
        .data_funct3_i   (cpu_mem_funct3),
        .data_rdata_o    (cpu_mem_rdata),
        .data_stall_o    (cpu_mem_stall),

        .master_addr_o   (axi_req_addr),
        .master_wdata_o  (axi_req_wdata),
        .master_read_o   (axi_req_read),
        .master_write_o  (axi_req_write),
        .master_funct3_o (axi_req_funct3),
        .master_rdata_i  (axi_req_rdata),
        .master_stall_i  (axi_master_stall)
    );

    // =========================================================================
    // 5. UNIFIED NATIVE REQUEST -> AXI MASTER
    // =========================================================================
    axi_master_wrapper u_axi_master (
        .clk       (clk),
        .rstn      (rstn),

        .mem_addr  (axi_req_addr),
        .mem_wdata (axi_req_wdata),
        .mem_read  (axi_req_read),
        .mem_write (axi_req_write),
        .funct3    (axi_req_funct3),

        .mem_rdata (axi_req_rdata),
        .stall_o   (axi_master_stall),

        .axi       (cpu_axi)
    );

    // =========================================================================
    // 6. AXI INTERCONNECT: 1 MASTER -> 4 SLAVES
    // =========================================================================
    axi_interconnect_1m4s #(
        .SHARED_SRAM_BASE (SHARED_SRAM_BASE),
        .SHARED_SRAM_MASK (SHARED_SRAM_MASK),

        .INSTR_SRAM_BASE  (INSTR_SRAM_BASE),
        .INSTR_SRAM_MASK  (INSTR_SRAM_MASK),

        .UART_BASE        (UART_BASE),
        .UART_MASK        (UART_MASK),

        .AES_BASE         (AES_BASE),
        .AES_MASK         (AES_MASK)
    ) u_interconnect (
        .s_axi         (cpu_axi),
        .m_shared_sram (shared_sram_axi),
        .m_instr_sram  (instr_sram_axi),
        .m_uart        (uart_axi),
        .m_aes         (aes_axi)
    );

    // =========================================================================
    // 7. SHARED / DATA SRAM
    // =========================================================================
    axi_shared_sram_slave #(
        .BASE_ADDR (SHARED_SRAM_BASE)
    ) u_shared_sram_slave (
        .s_axi (shared_sram_axi)
    );

    // =========================================================================
    // 8. INSTRUCTION / FIRMWARE SRAM
    //
    // Boot code may write this region through the normal CPU load/store path.
    // When PC enters 0x0001_xxxx, instruction fetch reads it through the same
    // AXI master using the arbitration block above.
    // =========================================================================
    axi_instruction_sram_slave #(
        .BASE_ADDR (INSTR_SRAM_BASE)
    ) u_instruction_sram_slave (
        .s_axi (instr_sram_axi)
    );

    // =========================================================================
    // 9. UART MMIO SLAVE
    // =========================================================================
    uart_axi_slave #(
        .BASE_ADDR (UART_BASE)
    ) u_uart_slave (
        .uart_rx_i (uart_rx_i),
        .uart_tx_o (uart_tx_o),
        .s_axi     (uart_axi)
    );

    // =========================================================================
    // 10. AES-256 MMIO SLAVE
    // =========================================================================
    aes_axi_slave #(
        .BASE_ADDR (AES_BASE)
    ) u_aes_slave (
        .done_debug (aes_done_debug),
        .s_axi      (aes_axi)
    );

endmodule
