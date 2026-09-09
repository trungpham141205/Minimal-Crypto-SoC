`timescale 1ns/1ps

module tb_soc_sram_copy;
    bit test_passed = 1'b0;

    localparam time CLK_PERIOD = 10ns;
    localparam int unsigned TIMEOUT_CYCLES = 5_000;

    localparam logic [31:0] WORD0 = 32'h1122_3344;
    localparam logic [31:0] WORD1 = 32'h89ab_cdef;
    localparam logic [31:0] WORD2 = 32'hdead_beef;

    logic clk = 1'b0;
    logic rstn = 1'b0;
    logic uart_rx_i = 1'b1;
    logic uart_tx_o;
    logic cpu_stall_debug;
    logic aes_done_debug;

    int unsigned instr_aw_count;
    int unsigned instr_ar_count;
    int unsigned shared_aw_count;
    int unsigned shared_ar_count;
    int unsigned axi_error_count;

    bit instr_first_seen;
    bit instr_last_seen;
    bit shared_first_seen;
    bit shared_last_seen;

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
        $dumpfile("tb_soc_sram_copy.vcd");
        $dumpvars(0, tb_soc_sram_copy);
    end

    always @(posedge clk) begin
        if (!rstn) begin
            instr_aw_count  <= 0;
            instr_ar_count  <= 0;
            shared_aw_count <= 0;
            shared_ar_count <= 0;
            axi_error_count <= 0;
            instr_first_seen <= 1'b0;
            instr_last_seen  <= 1'b0;
            shared_first_seen <= 1'b0;
            shared_last_seen  <= 1'b0;
        end
        else begin
            if (dut.instr_sram_axi.awvalid && dut.instr_sram_axi.awready) begin
                instr_aw_count <= instr_aw_count + 1;
                if (dut.instr_sram_axi.awaddr == 32'h0001_0000)
                    instr_first_seen <= 1'b1;
                if (dut.instr_sram_axi.awaddr == 32'h0001_03fc)
                    instr_last_seen <= 1'b1;
            end

            if (dut.instr_sram_axi.arvalid && dut.instr_sram_axi.arready)
                instr_ar_count <= instr_ar_count + 1;

            if (dut.shared_sram_axi.awvalid && dut.shared_sram_axi.awready) begin
                shared_aw_count <= shared_aw_count + 1;
                if (dut.shared_sram_axi.awaddr == 32'h0000_0000)
                    shared_first_seen <= 1'b1;
                if (dut.shared_sram_axi.awaddr == 32'h0000_01fc)
                    shared_last_seen <= 1'b1;
            end

            if (dut.shared_sram_axi.arvalid && dut.shared_sram_axi.arready)
                shared_ar_count <= shared_ar_count + 1;

            if (dut.cpu_axi.bvalid && dut.cpu_axi.bready &&
                dut.cpu_axi.bresp != 2'b00)
                axi_error_count <= axi_error_count + 1;

            if (dut.cpu_axi.rvalid && dut.cpu_axi.rready &&
                dut.cpu_axi.rresp != 2'b00)
                axi_error_count <= axi_error_count + 1;
        end
    end

    task automatic check_results;
        begin
            if (dut.u_cpu.dut_register_file.registers[11] !== WORD0 ||
                dut.u_cpu.dut_register_file.registers[12] !== WORD1 ||
                dut.u_cpu.dut_register_file.registers[13] !== WORD2)
                $fatal(1, "Instruction SRAM readback mismatch");

            if (dut.u_cpu.dut_register_file.registers[14] !== WORD0 ||
                dut.u_cpu.dut_register_file.registers[15] !== WORD1 ||
                dut.u_cpu.dut_register_file.registers[16] !== WORD2)
                $fatal(1, "Shared SRAM copy/readback mismatch");

            if (instr_aw_count != 3 || instr_ar_count != 3)
                $fatal(1, "Instruction SRAM AXI count mismatch AW/AR=%0d/%0d",
                       instr_aw_count, instr_ar_count);

            if (shared_aw_count != 3 || shared_ar_count != 3)
                $fatal(1, "Shared SRAM AXI count mismatch AW/AR=%0d/%0d",
                       shared_aw_count, shared_ar_count);

            if (!instr_first_seen || !instr_last_seen ||
                !shared_first_seen || !shared_last_seen)
                $fatal(1, "SRAM boundary address was not routed correctly");

            if (axi_error_count != 0)
                $fatal(1, "AXI error responses observed: %0d", axi_error_count);

            $display("============================================================");
            $display(" INSTRUCTION SRAM -> SHARED SRAM COPY TEST PASSED");
            $display("============================================================");
            $display(" Instruction SRAM AW/AR = %0d/%0d", instr_aw_count, instr_ar_count);
            $display(" Shared SRAM      AW/AR = %0d/%0d", shared_aw_count, shared_ar_count);
            $display(" Copied words: %08h %08h %08h", WORD0, WORD1, WORD2);
            $display(" Boundary decode and AXI responses: PASS");
            $display("============================================================");
        end
    endtask

    initial begin : test_control
        repeat (8) @(posedge clk);
        @(negedge clk);
        rstn = 1'b1;

        fork
            begin : completion
                wait (dut.u_cpu.dut_register_file.registers[31] === 32'd1 ||
                      dut.u_cpu.dut_register_file.registers[31] === 32'd2);

                if (dut.u_cpu.dut_register_file.registers[31] === 32'd2)
                    $fatal(1, "Firmware comparison reported FAIL");

                check_results();
                test_passed = 1'b1;
                $finish;
            end

            begin : timeout
                repeat (TIMEOUT_CYCLES) @(posedge clk);
                $fatal(1, "SRAM copy test timeout: PC=%08h x31=%08h",
                       dut.u_cpu.pc_debug,
                       dut.u_cpu.dut_register_file.registers[31]);
            end
        join_any
        disable fork;
    end
endmodule
