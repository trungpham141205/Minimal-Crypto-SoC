`timescale 1ns/1ps

module tb_soc_aes_flow;
    bit test_passed = 1'b0;

    localparam time CLK_PERIOD = 10ns;
    localparam int unsigned RESET_CYCLES   = 8;
    localparam int unsigned TIMEOUT_CYCLES = 100_000;

    localparam logic [255:0] EXPECT_KEY =
        256'h000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F;

    localparam logic [127:0] EXPECT_PT =
        128'h00112233445566778899AABBCCDDEEFF;

    localparam logic [127:0] EXPECT_CT =
        128'h8EA2B7CA516745BFEAFC49904B496089;

    logic clk;
    logic rstn;
    logic uart_rx_i;
    logic uart_tx_o;
    logic cpu_stall_debug;
    logic aes_done_debug;

    int unsigned uart_count;
    int unsigned stall_cycles;
    int unsigned axi_aw_count;
    int unsigned axi_ar_count;
    int unsigned axi_b_count;
    int unsigned axi_r_count;
    int unsigned axi_b_err_count;
    int unsigned axi_r_err_count;

    logic [127:0] uart_ciphertext;
    logic         aes_done_seen;
    logic         uart_serial_seen;

    soc_top dut (
        .clk             (clk),
        .rstn            (rstn),
        .uart_rx_i       (uart_rx_i),
        .uart_tx_o       (uart_tx_o),
        .cpu_stall_debug (cpu_stall_debug),
        .aes_done_debug  (aes_done_debug)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // RX unused in this test.
    initial uart_rx_i = 1'b1;

    initial begin
        $dumpfile("tb_soc_aes_flow.vcd");
        $dumpvars(0, tb_soc_aes_flow);
    end

    // -------------------------------------------------------------------------
    // AXI accounting
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rstn) begin
            stall_cycles   <= 0;
            axi_aw_count   <= 0;
            axi_ar_count   <= 0;
            axi_b_count    <= 0;
            axi_r_count    <= 0;
            axi_b_err_count<= 0;
            axi_r_err_count<= 0;
            aes_done_seen  <= 1'b0;
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

            if (dut.cpu_axi.bvalid && dut.cpu_axi.bready) begin
                axi_b_count <= axi_b_count + 1;
                if (dut.cpu_axi.bresp != 2'b00)
                    axi_b_err_count <= axi_b_err_count + 1;
            end

            if (dut.cpu_axi.rvalid && dut.cpu_axi.rready) begin
                axi_r_count <= axi_r_count + 1;
                if (dut.cpu_axi.rresp != 2'b00)
                    axi_r_err_count <= axi_r_err_count + 1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Capture RAW UART bytes produced by firmware.
    //
    // Firmware emits:
    // 8E A2 B7 CA 51 67 45 BF EA FC 49 90 4B 49 60 89
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        logic [127:0] next_ct;

        if (rstn &&
            dut.u_uart_slave.tx_pending_q &&
            dut.u_uart_slave.uart_tx_ready) begin

            // Firmware fail indicator.
            if ((uart_count == 0) && (dut.u_uart_slave.tx_data_q == 8'h46)) begin
                $display("Firmware reported FAIL ('F').");
                $display("PC    = 0x%08h", dut.u_cpu.pc_debug);
                $display("INSTR = 0x%08h", dut.u_cpu.instr_debug);
                $fatal(1, "AES END-TO-END FLOW FAILED");
            end

            next_ct = {uart_ciphertext[119:0],
                       dut.u_uart_slave.tx_data_q};

            uart_ciphertext <= next_ct;

            $display("[%0t] AES UART byte[%0d] = 0x%02h",
                     $time,
                     uart_count,
                     dut.u_uart_slave.tx_data_q);

            if (uart_count == 15) begin
                $display("");
                $display("AES ciphertext reconstructed from UART:");
                $display("  %032h", next_ct);

                if (next_ct !== EXPECT_CT) begin
                    $fatal(1,
                        "UART ciphertext mismatch: got=%032h expected=%032h",
                        next_ct,
                        EXPECT_CT
                    );
                end
            end

            uart_count <= uart_count + 1;
        end
    end

    always @(negedge uart_tx_o) begin
        if (rstn)
            uart_serial_seen = 1'b1;
    end

    task automatic final_check;
        logic [127:0] internal_ct;
        begin
            internal_ct = {
                dut.u_aes_slave.ct_q[0],
                dut.u_aes_slave.ct_q[1],
                dut.u_aes_slave.ct_q[2],
                dut.u_aes_slave.ct_q[3]
            };

            if (!aes_done_seen)
                $fatal(1, "AES done was never observed.");

            if (internal_ct !== EXPECT_CT)
                $fatal(1,
                    "AES internal ciphertext mismatch got=%032h expected=%032h",
                    internal_ct,
                    EXPECT_CT
                );

            if (uart_ciphertext !== EXPECT_CT)
                $fatal(1,
                    "UART ciphertext mismatch got=%032h expected=%032h",
                    uart_ciphertext,
                    EXPECT_CT
                );

            if (!uart_serial_seen)
                $fatal(1, "UART serial line never generated a start bit.");

            if (axi_aw_count != axi_b_count)
                $fatal(1, "AXI AW/B mismatch: %0d/%0d",
                       axi_aw_count, axi_b_count);

            if (axi_ar_count != axi_r_count)
                $fatal(1, "AXI AR/R mismatch: %0d/%0d",
                       axi_ar_count, axi_r_count);

            if (axi_b_err_count != 0 || axi_r_err_count != 0)
                $fatal(1,
                    "AXI error response observed: BERR=%0d RERR=%0d",
                    axi_b_err_count,
                    axi_r_err_count
                );

            // Successful flow has exactly 47 stores:
            // 12 SRAM staging
            // 13 AES writes (12 data + START)
            // 4 ciphertext-to-SRAM writes
            // 2 UART config writes
            // 16 UART TXDATA writes
            if (axi_aw_count != 47)
                $fatal(1,
                    "Unexpected write transaction count: got=%0d expected=47",
                    axi_aw_count
                );

            $display("");
            $display("============================================================");
            $display(" AES END-TO-END FLOW PASSED");
            $display("============================================================");
            $display(" KEY        = %064h", EXPECT_KEY);
            $display(" PLAINTEXT  = %032h", EXPECT_PT);
            $display(" CIPHERTEXT = %032h", EXPECT_CT);
            $display("------------------------------------------------------------");
            $display(" SRAM staging -> CPU load     : PASS");
            $display(" CPU -> AXI -> AES MMIO        : PASS");
            $display(" AES-256 encryption            : PASS");
            $display(" AES -> CPU -> SRAM result     : PASS");
            $display(" SRAM -> CPU -> UART result    : PASS");
            $display(" UART reconstructed ciphertext : PASS");
            $display(" AXI AW/B = %0d/%0d", axi_aw_count, axi_b_count);
            $display(" AXI AR/R = %0d/%0d", axi_ar_count, axi_r_count);
            $display(" Stall cycles = %0d", stall_cycles);
            $display("============================================================");
        end
    endtask

    initial begin : test_control
        rstn             = 1'b0;
        uart_count       = 0;
        uart_ciphertext  = 128'b0;
        uart_serial_seen = 1'b0;

        repeat (RESET_CYCLES)
            @(posedge clk);

        @(negedge clk);
        rstn = 1'b1;

        $display("============================================================");
        $display(" AES end-to-end SoC flow started");
        $display(" SRAM -> CPU -> AXI -> AES -> SRAM -> UART");
        $display("============================================================");

        fork
            begin : completion_thread
                wait (uart_count == 16);

                // Wait until the final UART frame completely finishes.
                wait (dut.u_uart_slave.uart_tx_ready === 1'b0);
                wait (dut.u_uart_slave.uart_tx_ready === 1'b1);
                wait (uart_tx_o === 1'b1);

                final_check();
                test_passed = 1'b1;
                $finish;
            end

            begin : timeout_thread
                repeat (TIMEOUT_CYCLES)
                    @(posedge clk);

                $display("");
                $display("AES FLOW TIMEOUT");
                $display("PC         = 0x%08h", dut.u_cpu.pc_debug);
                $display("INSTR      = 0x%08h", dut.u_cpu.instr_debug);
                $display("CPU stall  = %0b", cpu_stall_debug);
                $display("AES done   = %0b", aes_done_debug);
                $display("UART count = %0d", uart_count);
                $display("AXI AW/B   = %0d/%0d", axi_aw_count, axi_b_count);
                $display("AXI AR/R   = %0d/%0d", axi_ar_count, axi_r_count);

                $fatal(1, "AES END-TO-END FLOW TIMEOUT");
            end
        join_any

        disable fork;
    end

endmodule
