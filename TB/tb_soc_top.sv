`timescale 1ns/1ps

module tb_soc_top;
    bit test_passed = 1'b0;

    localparam time CLK_PERIOD = 10ns;
    localparam int unsigned RESET_CYCLES   = 8;
    localparam int unsigned TIMEOUT_CYCLES = 20_000;

    localparam logic [31:0] SRAM_EXPECTED = 32'h1234_5678;

    localparam logic [31:0] AES_CT0 = 32'h8EA2_B7CA;
    localparam logic [31:0] AES_CT1 = 32'h5167_45BF;
    localparam logic [31:0] AES_CT2 = 32'hEAFC_4990;
    localparam logic [31:0] AES_CT3 = 32'h4B49_6089;

    logic clk;
    logic rstn;

    logic uart_rx_i;
    logic uart_tx_o;

    logic cpu_stall_debug;
    logic aes_done_debug;

    int unsigned stall_cycles;
    int unsigned axi_aw_count;
    int unsigned axi_ar_count;
    int unsigned axi_b_count;
    int unsigned axi_r_count;

    logic        aes_done_seen;
    logic        uart_start_seen;
    logic [7:0]  uart_accepted_byte;

    event uart_byte_accepted;

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    soc_top dut (
        .clk             (clk),
        .rstn            (rstn),

        .uart_rx_i       (uart_rx_i),
        .uart_tx_o       (uart_tx_o),

        .cpu_stall_debug (cpu_stall_debug),
        .aes_done_debug  (aes_done_debug)
    );

    // -------------------------------------------------------------------------
    // Clock
    // -------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // UART RX is unused in this smoke test. Keep line idle-high.
    initial begin
        uart_rx_i = 1'b1;
    end

    // -------------------------------------------------------------------------
    // Wave dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_soc_top.vcd");
        $dumpvars(0, tb_soc_top);
    end

    // -------------------------------------------------------------------------
    // AXI / debug statistics
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rstn) begin
            stall_cycles <= 0;
            axi_aw_count  <= 0;
            axi_ar_count  <= 0;
            axi_b_count   <= 0;
            axi_r_count   <= 0;
            aes_done_seen <= 1'b0;
        end
        else begin
            if (cpu_stall_debug)
                stall_cycles <= stall_cycles + 1;

            if (aes_done_debug)
                aes_done_seen <= 1'b1;

            if (dut.cpu_axi.awvalid && dut.cpu_axi.awready)
                axi_aw_count <= axi_aw_count + 1;

            if (dut.cpu_axi.arvalid && dut.cpu_axi.arready)
                axi_ar_count <= axi_ar_count + 1;

            if (dut.cpu_axi.bvalid && dut.cpu_axi.bready)
                axi_b_count <= axi_b_count + 1;

            if (dut.cpu_axi.rvalid && dut.cpu_axi.rready)
                axi_r_count <= axi_r_count + 1;
        end
    end

    // -------------------------------------------------------------------------
    // Observe the UART wrapper -> UART core acceptance handshake.
    //
    // This is intentionally white-box for the initial SoC bring-up. It proves
    // that the CPU MMIO store reached uart_axi_slave and was accepted by the
    // UART transmitter.
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rstn &&
            dut.u_uart_slave.tx_pending_q &&
            dut.u_uart_slave.uart_tx_ready) begin

            uart_accepted_byte = dut.u_uart_slave.tx_data_q;

            $display("[%0t] UART accepted byte 0x%02h ('%c')",
                     $time,
                     dut.u_uart_slave.tx_data_q,
                     dut.u_uart_slave.tx_data_q);

            -> uart_byte_accepted;
        end
    end

    // A real UART frame must leave idle-high and produce a start-bit falling edge.
    always @(negedge uart_tx_o) begin
        if (rstn)
            uart_start_seen = 1'b1;
    end

    // -------------------------------------------------------------------------
    // End-state checker
    // -------------------------------------------------------------------------
    task automatic check_architectural_results;
        begin
            // SRAM SW/LW round-trip result is retained in x2.
            if (dut.u_cpu.dut_register_file.registers[2] !== SRAM_EXPECTED) begin
                $fatal(1,
                    "SRAM check failed: x2=0x%08h expected=0x%08h",
                    dut.u_cpu.dut_register_file.registers[2],
                    SRAM_EXPECTED
                );
            end

            if (!aes_done_seen) begin
                $fatal(1, "AES done was never observed.");
            end

            if (dut.u_aes_slave.ct_q[0] !== AES_CT0 ||
                dut.u_aes_slave.ct_q[1] !== AES_CT1 ||
                dut.u_aes_slave.ct_q[2] !== AES_CT2 ||
                dut.u_aes_slave.ct_q[3] !== AES_CT3) begin

                $display("AES ciphertext observed:");
                $display("  CT0 = %08h", dut.u_aes_slave.ct_q[0]);
                $display("  CT1 = %08h", dut.u_aes_slave.ct_q[1]);
                $display("  CT2 = %08h", dut.u_aes_slave.ct_q[2]);
                $display("  CT3 = %08h", dut.u_aes_slave.ct_q[3]);

                $fatal(1,
                    "AES KAT failed. Expected 8EA2B7CA_516745BF_EAFC4990_4B496089"
                );
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Reset + test controller
    // -------------------------------------------------------------------------
    initial begin : test_control
        rstn              = 1'b0;
        uart_start_seen   = 1'b0;
        uart_accepted_byte = 8'h00;

        repeat (RESET_CYCLES)
            @(posedge clk);

        @(negedge clk);
        rstn = 1'b1;

        $display("============================================================");
        $display(" SoC smoke test started");
        $display(" SRAM -> AES-256 -> UART");
        $display("============================================================");

        fork
            begin : completion_thread
                forever begin
                    @uart_byte_accepted;

                    if (uart_accepted_byte == 8'h46) begin
                        $display("CPU firmware reported FAIL ('F').");
                        $display("PC    = 0x%08h", dut.u_cpu.pc_debug);
                        $display("INSTR = 0x%08h", dut.u_cpu.instr_debug);
                        $fatal(1, "SOC SMOKE TEST FAILED");
                    end

                    if (uart_accepted_byte == 8'h50) begin
                        check_architectural_results();

                        // The UART core must actually leave IDLE after accepting P.
                        wait (dut.u_uart_slave.uart_tx_ready === 1'b0);

                        // The serial line must produce a start bit.
                        wait (uart_start_seen === 1'b1);

                        // Wait until the complete UART frame has been transmitted.
                        wait (dut.u_uart_slave.uart_tx_ready === 1'b1);

                        $display("");
                        $display("============================================================");
                        $display(" SOC SMOKE TEST PASSED");
                        $display("============================================================");
                        $display(" SRAM       : PASS (0x12345678 round-trip)");
                        $display(" AES-256 KAT : PASS");
                        $display(" UART TX     : PASS ('P' accepted and frame completed)");
                        $display(" AXI AW      : %0d", axi_aw_count);
                        $display(" AXI B       : %0d", axi_b_count);
                        $display(" AXI AR      : %0d", axi_ar_count);
                        $display(" AXI R       : %0d", axi_r_count);
                        $display(" Stall cycles: %0d", stall_cycles);
                        $display("============================================================");

                        test_passed = 1'b1;
                        $finish;
                    end
                end
            end

            begin : timeout_thread
                repeat (TIMEOUT_CYCLES)
                    @(posedge clk);

                $display("");
                $display("TIMEOUT");
                $display("PC           = 0x%08h", dut.u_cpu.pc_debug);
                $display("INSTR        = 0x%08h", dut.u_cpu.instr_debug);
                $display("CPU stall    = %0b", cpu_stall_debug);
                $display("AES done     = %0b", aes_done_debug);
                $display("UART TX      = %0b", uart_tx_o);
                $display("AXI AW count = %0d", axi_aw_count);
                $display("AXI AR count = %0d", axi_ar_count);
                $fatal(1, "SOC SMOKE TEST TIMEOUT");
            end
        join_any

        disable fork;
    end

    always @(posedge clk) begin
    if (($time >= 140ns) && ($time <= 200ns)) begin
        $display(
            "\n[T=%0t] PC=%08h INSTR=%08h stall=%b read=%b write=%b addr=%08h",
            $time,
            dut.u_cpu.pc_debug,
            dut.u_cpu.instr_debug,
            dut.cpu_mem_stall,
            dut.cpu_mem_read,
            dut.cpu_mem_write,
            dut.cpu_mem_addr
        );

        $display(
            " MASTER state=%0d next=%0d",
            dut.u_axi_master.current_state,
            dut.u_axi_master.next_state
        );

        $display(
            " AW  v/r=%b/%b addr=%08h",
            dut.cpu_axi.awvalid,
            dut.cpu_axi.awready,
            dut.cpu_axi.awaddr
        );

        $display(
            " W   v/r=%b/%b data=%08h strb=%b",
            dut.cpu_axi.wvalid,
            dut.cpu_axi.wready,
            dut.cpu_axi.wdata,
            dut.cpu_axi.wstrb
        );

        $display(
            " B   v/r=%b/%b resp=%b",
            dut.cpu_axi.bvalid,
            dut.cpu_axi.bready,
            dut.cpu_axi.bresp
        );

        $display(
            " AR  v/r=%b/%b addr=%08h",
            dut.cpu_axi.arvalid,
            dut.cpu_axi.arready,
            dut.cpu_axi.araddr
        );

        $display(
            " R   v/r=%b/%b data=%08h resp=%b",
            dut.cpu_axi.rvalid,
            dut.cpu_axi.rready,
            dut.cpu_axi.rdata,
            dut.cpu_axi.rresp
        );

        $display(
            " IC wr_active=%b wr_sel=%0d rd_active=%b rd_sel=%0d",
            dut.u_interconnect.wr_active_q,
            dut.u_interconnect.wr_sel_q,
            dut.u_interconnect.rd_active_q,
            dut.u_interconnect.rd_sel_q
        );

        $display(
            " SRAM Wstate=%0d AWcap=%b Wcap=%b Rstate=%0d ME=%b WE=%b A=%0d RDATA=%08h",
            dut.u_shared_sram_slave.u_ctrl.wstate_q,
            dut.u_shared_sram_slave.u_ctrl.aw_captured_q,
            dut.u_shared_sram_slave.u_ctrl.w_captured_q,
            dut.u_shared_sram_slave.u_ctrl.rstate_q,
            dut.u_shared_sram_slave.sram_me,
            dut.u_shared_sram_slave.sram_we,
            dut.u_shared_sram_slave.sram_addr,
            dut.u_shared_sram_slave.sram_rdata
        );
    end
end

endmodule
