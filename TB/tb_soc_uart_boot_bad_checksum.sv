`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// Negative-path stability test: send a fully well-formed UART boot payload
// (same 77-word firmware as tb_soc_uart_boot) but with a deliberately corrupted
// checksum byte. Verifies the Boot ROM rejects it with 'E' instead of 'K', and
// that it does not spill over into executing the downloaded firmware/AES core.
// See firmware/uart_bootloader.S: checksum is validated only after every
// payload word has already been written to Instruction SRAM, so the AXI write
// counters are still expected to reach PAYLOAD_WORDS even on rejection.
// -----------------------------------------------------------------------------
module tb_soc_uart_boot_bad_checksum;

    bit test_passed = 1'b0;

    localparam time         CLK_PERIOD      = 10ns;
    localparam int unsigned UART_BIT_CLKS   = 8;
    localparam int unsigned PAYLOAD_WORDS   = 77;
    localparam int unsigned TIMEOUT_CYCLES  = 200_000;

    localparam logic [31:0] INSTR_BASE      = 32'h0001_0000;
    localparam logic [31:0] INSTR_END       = 32'h0001_03ff;
    localparam logic [31:0] ENTRY_POINT     = 32'h0001_0000;

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
    int unsigned axi_error_count;

    bit pc_entered_instr_region;
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
        $dumpfile("tb_soc_uart_boot_bad_checksum.vcd");
        $dumpvars(0, tb_soc_uart_boot_bad_checksum);
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

    always @(posedge clk) begin
        if (!rstn) begin
            instr_aw_count           <= 0;
            instr_w_count            <= 0;
            instr_b_count            <= 0;
            axi_error_count          <= 0;
            pc_entered_instr_region  <= 1'b0;
            shared_ct_write_seen     <= 4'b0000;
        end
        else begin
            if ((dut.u_cpu.pc_debug >= INSTR_BASE) &&
                (dut.u_cpu.pc_debug <= INSTR_END))
                pc_entered_instr_region <= 1'b1;

            if (dut.instr_sram_axi.awvalid && dut.instr_sram_axi.awready)
                instr_aw_count <= instr_aw_count + 1;

            if (dut.instr_sram_axi.wvalid && dut.instr_sram_axi.wready)
                instr_w_count <= instr_w_count + 1;

            if (dut.instr_sram_axi.bvalid && dut.instr_sram_axi.bready) begin
                instr_b_count <= instr_b_count + 1;
                if (dut.instr_sram_axi.bresp != 2'b00)
                    axi_error_count <= axi_error_count + 1;
            end

            if (dut.shared_sram_axi.awvalid && dut.shared_sram_axi.awready)
                shared_ct_write_seen <= shared_ct_write_seen | 4'b0001;

            if (dut.cpu_axi.bvalid && dut.cpu_axi.bready &&
                dut.cpu_axi.bresp != 2'b00)
                axi_error_count <= axi_error_count + 1;

            if (dut.cpu_axi.rvalid && dut.cpu_axi.rready &&
                dut.cpu_axi.rresp != 2'b00)
                axi_error_count <= axi_error_count + 1;
        end
    end

    initial begin : bad_checksum_test
        logic [7:0] response;
        logic [7:0] checksum;
        logic [7:0] bad_checksum;
        logic [7:0] payload_byte;
        logic [31:0] pc_sample_a, pc_sample_b;

        checksum = 8'b0;

        repeat (8) @(posedge clk);
        @(negedge clk);
        rstn = 1'b1;

        $display("============================================================");
        $display(" UART BOOT NEGATIVE TEST: corrupted checksum must be rejected");
        $display("============================================================");

        uart_recv_byte(response);
        if (response !== 8'h52)
            $fatal(1, "Expected boot-ready 'R', received %02h", response);

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

        // Deliberately corrupt the checksum. Bitwise complement can never
        // equal the original 8-bit value, so this is always a mismatch.
        bad_checksum = ~checksum;
        uart_send_byte(bad_checksum);

        uart_recv_byte(response);
        if (response === 8'h4b)
            $fatal(1, "Boot ROM accepted a corrupted checksum (replied 'K')");
        if (response !== 8'h45)
            $fatal(1, "Expected boot error 'E' for bad checksum, received %02h",
                   response);

        // The Boot ROM parks in boot_error_loop on error: PC must settle and
        // hold, and no downstream firmware/AES activity must ever be seen.
        repeat (200) @(posedge clk);
        pc_sample_a = dut.u_cpu.pc_debug;
        repeat (200) @(posedge clk);
        pc_sample_b = dut.u_cpu.pc_debug;
        if (pc_sample_a !== pc_sample_b)
            $fatal(1,
                "CPU did not park after boot error: PC moved %08h -> %08h",
                pc_sample_a, pc_sample_b);

        if (pc_entered_instr_region)
            $fatal(1, "CPU entered Instruction SRAM region despite rejected boot");

        if (shared_ct_write_seen != 4'b0000)
            $fatal(1, "AES/result stage ran despite rejected boot: seen=%b",
                   shared_ct_write_seen);

        if ((instr_aw_count != PAYLOAD_WORDS) ||
            (instr_w_count  != PAYLOAD_WORDS) ||
            (instr_b_count  != PAYLOAD_WORDS))
            $fatal(1,
                "Payload AXI write count mismatch AW/W/B=%0d/%0d/%0d expected=%0d",
                instr_aw_count, instr_w_count, instr_b_count, PAYLOAD_WORDS);

        if (axi_error_count != 0)
            $fatal(1, "AXI error responses observed: %0d", axi_error_count);

        $display("============================================================");
        $display(" BAD-CHECKSUM REJECTION TEST PASSED");
        $display("============================================================");
        $display(" Boot ROM ready response          : R");
        $display(" Corrupted checksum sent           : %02h (correct was %02h)",
                  bad_checksum, checksum);
        $display(" Boot ROM error response           : E");
        $display(" CPU parked at                     : %08h", pc_sample_b);
        $display(" Instruction SRAM AXI AW/W/B        : %0d/%0d/%0d",
                 instr_aw_count, instr_w_count, instr_b_count);
        $display("============================================================");

        test_passed = 1'b1;
        $finish;
    end

    initial begin : timeout
        repeat (TIMEOUT_CYCLES) @(posedge clk);
        $fatal(1,
            "Bad-checksum test timeout: PC=%08h instruction=%08h",
            dut.u_cpu.pc_debug,
            dut.u_cpu.instr_debug);
    end

endmodule
