`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// Stability test: run the full UART boot -> Instruction SRAM -> I-cache ->
// AES-256 sequence TWICE in the same simulation, with an explicit reset pulse
// between rounds. Catches state that a real reset should clear but doesn't
// (I-cache tags/FSM, AXI arbiter, sticky flags, ...): if round 2 doesn't
// reproduce round 1 exactly, this test fails where tb_soc_uart_boot (single
// round) would not have noticed.
//
// Note: the register file (RV32I_Single_Cycle/register_file.sv) is NOT
// cleared by rstn, so x31 can hold a stale PASS/FAIL value from round 1 when
// round 2 begins. This is safe here because the downloaded firmware
// (firmware/uart_payload.S) explicitly zeroes x31 at its own entry point,
// before AES even starts, and only reports 'P'/'F' over UART after writing a
// fresh x31 -- so by the time this testbench observes 'P', x31 already
// reflects the current round.
// -----------------------------------------------------------------------------
module tb_soc_uart_boot_reboot;

    bit test_passed = 1'b0;

    localparam time         CLK_PERIOD      = 10ns;
    localparam int unsigned UART_BIT_CLKS   = 8;
    localparam int unsigned PAYLOAD_WORDS   = 77;
    localparam int unsigned NUM_ROUNDS      = 2;
    localparam int unsigned TIMEOUT_CYCLES  = 500_000 * NUM_ROUNDS;

    localparam logic [31:0] INSTR_BASE      = 32'h0001_0000;
    localparam logic [31:0] INSTR_END       = 32'h0001_03ff;
    localparam logic [31:0] ENTRY_POINT     = 32'h0001_0000;
    localparam logic [31:0] RESULT_ADDR     = 32'h0000_0040;
    localparam logic [31:0] EXPECTED_CT0    = 32'h8ea2_b7ca;
    localparam logic [31:0] EXPECTED_CT1    = 32'h5167_45bf;
    localparam logic [31:0] EXPECTED_CT2    = 32'heafc_4990;
    localparam logic [31:0] EXPECTED_CT3    = 32'h4b49_6089;

    logic clk = 1'b0;
    logic rstn = 1'b0;
    logic uart_rx_i = 1'b1;
    logic uart_tx_o;
    logic cpu_stall_debug;
    logic aes_done_debug;

    logic [31:0] payload_words [0:PAYLOAD_WORDS-1];

    int unsigned instr_aw_count;
    int unsigned instr_w_count;
    int unsigned instr_b_count;
    int unsigned instr_ar_count;
    int unsigned instr_r_count;
    int unsigned icache_hit_count;
    int unsigned icache_miss_count;
    int unsigned axi_error_count;

    bit pc_entered_instr_region;
    bit icache_invalidate_seen;
    logic [3:0] shared_ct_write_seen;

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
        $readmemh("uart_payload.hex", payload_words);
        $dumpfile("tb_soc_uart_boot_reboot.vcd");
        $dumpvars(0, tb_soc_uart_boot_reboot);
    end

    task automatic uart_send_byte(input logic [7:0] data);
        begin
            @(negedge clk);
            uart_rx_i <= 1'b0;
            repeat (UART_BIT_CLKS) @(posedge clk);

            for (int bit_index = 0; bit_index < 8; bit_index++) begin
                @(negedge clk);
                uart_rx_i <= data[bit_index];
                repeat (UART_BIT_CLKS) @(posedge clk);
            end

            @(negedge clk);
            uart_rx_i <= 1'b1;
            repeat (UART_BIT_CLKS) @(posedge clk);
        end
    endtask

    task automatic uart_recv_byte(output logic [7:0] data);
        begin
            @(negedge uart_tx_o);

            repeat (UART_BIT_CLKS/2) @(posedge clk);
            if (uart_tx_o !== 1'b0)
                $fatal(1, "UART TX start-bit sampling failed");

            repeat (UART_BIT_CLKS) @(posedge clk);
            for (int bit_index = 0; bit_index < 8; bit_index++) begin
                data[bit_index] = uart_tx_o;
                if (bit_index != 7)
                    repeat (UART_BIT_CLKS) @(posedge clk);
            end

            repeat (UART_BIT_CLKS) @(posedge clk);
            if (uart_tx_o !== 1'b1)
                $fatal(1, "UART TX stop-bit sampling failed");
        end
    endtask

    task automatic uart_send_u16_le(input logic [15:0] value);
        begin
            uart_send_byte(value[7:0]);
            uart_send_byte(value[15:8]);
        end
    endtask

    task automatic uart_send_u32_le(input logic [31:0] value);
        begin
            uart_send_byte(value[7:0]);
            uart_send_byte(value[15:8]);
            uart_send_byte(value[23:16]);
            uart_send_byte(value[31:24]);
        end
    endtask

    task automatic pulse_reset();
        begin
            rstn = 1'b0;
            repeat (8) @(posedge clk);
            @(negedge clk);
            rstn = 1'b1;
        end
    endtask

    always @(posedge clk) begin
        if (!rstn) begin
            instr_aw_count           <= 0;
            instr_w_count            <= 0;
            instr_b_count            <= 0;
            instr_ar_count           <= 0;
            instr_r_count            <= 0;
            icache_hit_count         <= 0;
            icache_miss_count        <= 0;
            axi_error_count          <= 0;
            pc_entered_instr_region  <= 1'b0;
            icache_invalidate_seen   <= 1'b0;
            shared_ct_write_seen     <= 4'b0000;
        end
        else begin
            if ((dut.u_cpu.pc_debug >= INSTR_BASE) &&
                (dut.u_cpu.pc_debug <= INSTR_END))
                pc_entered_instr_region <= 1'b1;

            if (dut.icache_hit)
                icache_hit_count <= icache_hit_count + 1;

            if (dut.icache_miss)
                icache_miss_count <= icache_miss_count + 1;

            if (dut.icache_invalidate)
                icache_invalidate_seen <= 1'b1;

            if (dut.instr_sram_axi.awvalid && dut.instr_sram_axi.awready)
                instr_aw_count <= instr_aw_count + 1;

            if (dut.instr_sram_axi.wvalid && dut.instr_sram_axi.wready)
                instr_w_count <= instr_w_count + 1;

            if (dut.instr_sram_axi.bvalid && dut.instr_sram_axi.bready) begin
                instr_b_count <= instr_b_count + 1;
                if (dut.instr_sram_axi.bresp != 2'b00)
                    axi_error_count <= axi_error_count + 1;
            end

            if (dut.instr_sram_axi.arvalid && dut.instr_sram_axi.arready)
                instr_ar_count <= instr_ar_count + 1;

            if (dut.instr_sram_axi.rvalid && dut.instr_sram_axi.rready) begin
                instr_r_count <= instr_r_count + 1;
                if (dut.instr_sram_axi.rresp != 2'b00)
                    axi_error_count <= axi_error_count + 1;
            end

            if (dut.shared_sram_axi.awvalid && dut.shared_sram_axi.awready) begin
                case (dut.shared_sram_axi.awaddr)
                    RESULT_ADDR + 32'd0:  shared_ct_write_seen[0] <= 1'b1;
                    RESULT_ADDR + 32'd4:  shared_ct_write_seen[1] <= 1'b1;
                    RESULT_ADDR + 32'd8:  shared_ct_write_seen[2] <= 1'b1;
                    RESULT_ADDR + 32'd12: shared_ct_write_seen[3] <= 1'b1;
                    default: ;
                endcase
            end

            if (dut.cpu_axi.bvalid && dut.cpu_axi.bready &&
                dut.cpu_axi.bresp != 2'b00)
                axi_error_count <= axi_error_count + 1;

            if (dut.cpu_axi.rvalid && dut.cpu_axi.rready &&
                dut.cpu_axi.rresp != 2'b00)
                axi_error_count <= axi_error_count + 1;
        end
    end

    task automatic run_boot_round(input int unsigned round_id);
        logic [7:0] response;
        logic [7:0] checksum;
        logic [7:0] payload_byte;
        begin
            checksum = 8'b0;

            $display("------------------------------------------------------------");
            $display(" ROUND %0d: UART BOOT -> I-CACHE -> AES-256", round_id);
            $display("------------------------------------------------------------");

            uart_recv_byte(response);
            if (response !== 8'h52)
                $fatal(1, "[round %0d] Expected boot-ready 'R', received %02h",
                       round_id, response);

            uart_send_byte(8'h42);
            uart_send_byte(8'h4f);
            uart_send_byte(8'h4f);
            uart_send_byte(8'h54);
            uart_send_u16_le(PAYLOAD_WORDS);
            uart_send_u32_le(ENTRY_POINT);

            for (int word_index = 0;
                 word_index < PAYLOAD_WORDS;
                 word_index++) begin
                for (int byte_index = 0; byte_index < 4; byte_index++) begin
                    payload_byte =
                        payload_words[word_index][byte_index*8 +: 8];
                    checksum = checksum + payload_byte;
                    uart_send_byte(payload_byte);
                end
            end

            uart_send_byte(checksum);

            uart_recv_byte(response);
            if (response !== 8'h4b)
                $fatal(1, "[round %0d] Boot failed: expected 'K', received %02h",
                       round_id, response);

            uart_recv_byte(response);
            if (response !== 8'h50)
                $fatal(1, "[round %0d] AES result failed: expected 'P', received %02h",
                       round_id, response);

            wait ((dut.u_cpu.dut_register_file.registers[31] === 32'd1) ||
                  (dut.u_cpu.dut_register_file.registers[31] === 32'd2));
            repeat (32) @(posedge clk);

            if (dut.u_cpu.dut_register_file.registers[31] === 32'd2)
                $fatal(1, "[round %0d] UART-loaded AES firmware reported FAIL",
                       round_id);

            if (!pc_entered_instr_region)
                $fatal(1, "[round %0d] CPU never entered Instruction SRAM region",
                       round_id);

            if ((instr_aw_count != PAYLOAD_WORDS) ||
                (instr_w_count  != PAYLOAD_WORDS) ||
                (instr_b_count  != PAYLOAD_WORDS))
                $fatal(1,
                    "[round %0d] Payload AXI write count mismatch AW/W/B=%0d/%0d/%0d expected=%0d",
                    round_id, instr_aw_count, instr_w_count, instr_b_count, PAYLOAD_WORDS);

            if (!icache_invalidate_seen)
                $fatal(1, "[round %0d] I-cache was not invalidated on this boot",
                       round_id);

            if ((icache_miss_count == 0) || (icache_hit_count == 0))
                $fatal(1, "[round %0d] Expected both I-cache miss and hit activity",
                       round_id);

            if ((instr_ar_count < 8) || (instr_ar_count != instr_r_count))
                $fatal(1, "[round %0d] Instruction refill AR/R mismatch %0d/%0d",
                       round_id, instr_ar_count, instr_r_count);

            if (shared_ct_write_seen != 4'b1111)
                $fatal(1,
                    "[round %0d] Downloaded firmware did not mirror all ciphertext words: seen=%b",
                    round_id, shared_ct_write_seen);

            if ((dut.u_aes_slave.ct_q[0] !== EXPECTED_CT0) ||
                (dut.u_aes_slave.ct_q[1] !== EXPECTED_CT1) ||
                (dut.u_aes_slave.ct_q[2] !== EXPECTED_CT2) ||
                (dut.u_aes_slave.ct_q[3] !== EXPECTED_CT3))
                $fatal(1,
                    "[round %0d] AES ciphertext mismatch: %08h %08h %08h %08h",
                    round_id,
                    dut.u_aes_slave.ct_q[0], dut.u_aes_slave.ct_q[1],
                    dut.u_aes_slave.ct_q[2], dut.u_aes_slave.ct_q[3]);

            if (axi_error_count != 0)
                $fatal(1, "[round %0d] AXI error responses observed: %0d",
                       round_id, axi_error_count);

            $display(" ROUND %0d PASSED  (AW/W/B=%0d/%0d/%0d  AR/R=%0d/%0d  hit/miss=%0d/%0d  ct=%08h%08h%08h%08h)",
                round_id, instr_aw_count, instr_w_count, instr_b_count,
                instr_ar_count, instr_r_count, icache_hit_count, icache_miss_count,
                dut.u_aes_slave.ct_q[0], dut.u_aes_slave.ct_q[1],
                dut.u_aes_slave.ct_q[2], dut.u_aes_slave.ct_q[3]);
        end
    endtask

    initial begin : reboot_test
        $display("============================================================");
        $display(" UART BOOT REBOOT/RESET STABILITY TEST (%0d rounds)", NUM_ROUNDS);
        $display("============================================================");

        for (int round_id = 1; round_id <= NUM_ROUNDS; round_id++) begin
            pulse_reset();
            run_boot_round(round_id);
        end

        $display("============================================================");
        $display(" ALL %0d ROUNDS PASSED -- system is stable across reset/reboot",
                  NUM_ROUNDS);
        $display("============================================================");

        test_passed = 1'b1;
        $finish;
    end

    initial begin : timeout
        repeat (TIMEOUT_CYCLES) @(posedge clk);
        $fatal(1,
            "Reboot stability test timeout: PC=%08h instruction=%08h",
            dut.u_cpu.pc_debug,
            dut.u_cpu.instr_debug);
    end

endmodule
