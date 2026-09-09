`timescale 1ns/1ps

module tb_soc_exec_from_instr_sram;

    bit test_passed = 1'b0;

    localparam time CLK_PERIOD = 10ns;
    localparam int unsigned TIMEOUT_CYCLES = 20_000;

    localparam logic [31:0] INSTR_BASE = 32'h0001_0000;
    localparam logic [31:0] INSTR_END  = 32'h0001_03ff;
    localparam logic [31:0] RESULT_ADDR = 32'h0000_0040;
    localparam logic [31:0] EXPECTED_RESULT = 32'd12;
    localparam logic [31:0] FIRST_SRAM_INSTR = 32'h0070_0293;

    logic clk = 1'b0;
    logic rstn = 1'b0;
    logic uart_rx_i = 1'b1;
    logic uart_tx_o;
    logic cpu_stall_debug;
    logic aes_done_debug;

    int unsigned instr_aw_count;
    int unsigned instr_b_count;
    int unsigned instr_ar_count;
    int unsigned instr_r_count;
    int unsigned shared_aw_count;
    int unsigned shared_b_count;
    int unsigned shared_ar_count;
    int unsigned shared_r_count;
    int unsigned axi_error_count;

    bit pc_entered_instr_region;
    bit first_instr_fetch_addr_seen;
    bit first_instr_fetch_data_seen;
    bit shared_result_aw_seen;
    bit shared_result_wdata_seen;

    soc_top dut (
        .clk             (clk),
        .rstn            (rstn),
        .uart_rx_i       (uart_rx_i),
        .uart_tx_o       (uart_tx_o),
        .cpu_stall_debug (cpu_stall_debug),
        .aes_done_debug  (aes_done_debug)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        $dumpfile("tb_soc_exec_from_instr_sram.vcd");
        $dumpvars(0, tb_soc_exec_from_instr_sram);
    end

    always @(posedge clk) begin
        if (!rstn) begin
            instr_aw_count           <= 0;
            instr_b_count            <= 0;
            instr_ar_count           <= 0;
            instr_r_count            <= 0;
            shared_aw_count          <= 0;
            shared_b_count           <= 0;
            shared_ar_count          <= 0;
            shared_r_count           <= 0;
            axi_error_count          <= 0;

            pc_entered_instr_region  <= 1'b0;
            first_instr_fetch_addr_seen <= 1'b0;
            first_instr_fetch_data_seen <= 1'b0;
            shared_result_aw_seen    <= 1'b0;
            shared_result_wdata_seen <= 1'b0;
        end
        else begin
            if ((dut.u_cpu.pc_debug >= INSTR_BASE) &&
                (dut.u_cpu.pc_debug <= INSTR_END))
                pc_entered_instr_region <= 1'b1;

            // Instruction SRAM writes: these are the Boot-ROM program loading
            // the application image before JALR.
            if (dut.instr_sram_axi.awvalid && dut.instr_sram_axi.awready)
                instr_aw_count <= instr_aw_count + 1;

            if (dut.instr_sram_axi.bvalid && dut.instr_sram_axi.bready) begin
                instr_b_count <= instr_b_count + 1;
                if (dut.instr_sram_axi.bresp != 2'b00)
                    axi_error_count <= axi_error_count + 1;
            end

            // Instruction SRAM reads: after JALR these must be actual CPU
            // instruction fetch transactions routed through AXI.
            if (dut.instr_sram_axi.arvalid && dut.instr_sram_axi.arready) begin
                instr_ar_count <= instr_ar_count + 1;
                if (dut.instr_sram_axi.araddr == INSTR_BASE)
                    first_instr_fetch_addr_seen <= 1'b1;
            end

            if (dut.instr_sram_axi.rvalid && dut.instr_sram_axi.rready) begin
                instr_r_count <= instr_r_count + 1;
                if ((instr_r_count == 0) &&
                    (dut.instr_sram_axi.rdata == FIRST_SRAM_INSTR))
                    first_instr_fetch_data_seen <= 1'b1;
                if (dut.instr_sram_axi.rresp != 2'b00)
                    axi_error_count <= axi_error_count + 1;
            end

            // Shared SRAM is touched only by the application that is already
            // executing from instruction SRAM.
            if (dut.shared_sram_axi.awvalid && dut.shared_sram_axi.awready) begin
                shared_aw_count <= shared_aw_count + 1;
                if (dut.shared_sram_axi.awaddr == RESULT_ADDR)
                    shared_result_aw_seen <= 1'b1;
            end

            if (dut.shared_sram_axi.wvalid && dut.shared_sram_axi.wready) begin
                if ((dut.shared_sram_axi.wstrb == 4'b1111) &&
                    (dut.shared_sram_axi.wdata == EXPECTED_RESULT))
                    shared_result_wdata_seen <= 1'b1;
            end

            if (dut.shared_sram_axi.bvalid && dut.shared_sram_axi.bready) begin
                shared_b_count <= shared_b_count + 1;
                if (dut.shared_sram_axi.bresp != 2'b00)
                    axi_error_count <= axi_error_count + 1;
            end

            if (dut.shared_sram_axi.arvalid && dut.shared_sram_axi.arready)
                shared_ar_count <= shared_ar_count + 1;

            if (dut.shared_sram_axi.rvalid && dut.shared_sram_axi.rready) begin
                shared_r_count <= shared_r_count + 1;
                if (dut.shared_sram_axi.rresp != 2'b00)
                    axi_error_count <= axi_error_count + 1;
            end
        end
    end

    task automatic check_results;
        begin
            if (!pc_entered_instr_region)
                $fatal(1, "PC never entered instruction SRAM region");

            if (!first_instr_fetch_addr_seen)
                $fatal(1, "No AXI instruction fetch observed at 0x00010000");

            if (!first_instr_fetch_data_seen)
                $fatal(1, "First instruction was not returned by instruction SRAM AXI R channel");

            if (dut.u_cpu.dut_register_file.registers[5] !== 32'd7 ||
                dut.u_cpu.dut_register_file.registers[6] !== 32'd5 ||
                dut.u_cpu.dut_register_file.registers[7] !== EXPECTED_RESULT)
                $fatal(1, "SRAM application arithmetic result mismatch");

            if (dut.u_cpu.dut_register_file.registers[8] !== EXPECTED_RESULT)
                $fatal(1, "Shared SRAM readback mismatch: x8=%08h",
                       dut.u_cpu.dut_register_file.registers[8]);

            if (!shared_result_aw_seen || !shared_result_wdata_seen)
                $fatal(1, "Expected result write to shared SRAM was not observed");

            // The boot image writes exactly seven application instructions.
            if ((instr_aw_count != 7) || (instr_b_count != 7))
                $fatal(1, "Instruction SRAM boot-write count mismatch AW/B=%0d/%0d",
                       instr_aw_count, instr_b_count);

            // Do not require an exact fetch count because the completion check
            // can race with the next loop fetch.  Pairing must nevertheless be
            // exact: no lost or duplicated AXI read transaction is allowed.
            if ((instr_ar_count < 6) || (instr_ar_count != instr_r_count))
                $fatal(1, "Instruction fetch AR/R mismatch = %0d/%0d",
                       instr_ar_count, instr_r_count);

            if ((shared_aw_count < 1) || (shared_aw_count != shared_b_count))
                $fatal(1, "Shared SRAM AW/B mismatch = %0d/%0d",
                       shared_aw_count, shared_b_count);

            if ((shared_ar_count < 1) || (shared_ar_count != shared_r_count))
                $fatal(1, "Shared SRAM AR/R mismatch = %0d/%0d",
                       shared_ar_count, shared_r_count);

            if (axi_error_count != 0)
                $fatal(1, "AXI error responses observed: %0d", axi_error_count);

            $display("============================================================");
            $display(" EXECUTE-FROM-INSTRUCTION-SRAM TEST PASSED");
            $display("============================================================");
            $display(" PC entered 0x0001_xxxx                     : PASS");
            $display(" Instruction came from instruction SRAM AXI : PASS");
            $display(" SRAM program result 7 + 5 = %0d             : PASS",
                     dut.u_cpu.dut_register_file.registers[8]);
            $display(" Shared SRAM result address 0x00000040       : PASS");
            $display(" Instruction SRAM AW/B = %0d/%0d", instr_aw_count, instr_b_count);
            $display(" Instruction fetch AR/R = %0d/%0d", instr_ar_count, instr_r_count);
            $display(" Shared SRAM AW/B = %0d/%0d", shared_aw_count, shared_b_count);
            $display(" Shared SRAM AR/R = %0d/%0d", shared_ar_count, shared_r_count);
            $display(" AXI transaction pairing / responses         : PASS");
            $display("============================================================");
        end
    endtask

    initial begin : test_control
        repeat (8) @(posedge clk);
        @(negedge clk);
        rstn = 1'b1;

        fork
            begin : completion
                wait (dut.u_cpu.dut_register_file.registers[31] === 32'd1);
                #1;
                check_results();
                test_passed = 1'b1;
                $finish;
            end

            begin : timeout
                repeat (TIMEOUT_CYCLES) @(posedge clk);
                $fatal(1,
                    "Execute-from-SRAM timeout: PC=%08h hold_valid=%0b owner=%0d",
                    dut.u_cpu.pc_debug,
                    dut.u_cpu.instruction_hold_valid_q,
                    dut.u_cpu_axi_arbiter.owner_q);
            end
        join_any
        disable fork;
    end

endmodule
