`timescale 1ns/1ps

module tb_soc_uart_runtime;
    bit test_passed = 1'b0;

    localparam time CLK_PERIOD = 10ns;

    // Current baud_gen with BAUDRATE=0 produces:
    // RX sample tick every clk and TX bit tick every 8 clk.
    localparam int UART_BIT_CLKS = 8;

    localparam logic [255:0] KEY1 =
        256'h000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F;
    localparam logic [127:0] PT1 =
        128'h00112233445566778899AABBCCDDEEFF;
    localparam logic [127:0] CT1 =
        128'h8EA2B7CA516745BFEAFC49904B496089;

    localparam logic [255:0] KEY2 =
        256'h603DEB1015CA71BE2B73AEF0857D77811F352C073B6108D72D9810A30914DFF4;
    localparam logic [127:0] PT2 =
        128'h6BC1BEE22E409F96E93D7E117393172A;
    localparam logic [127:0] CT2 =
        128'hF3EED1BDB5D2A03C064B5A7E3DB181F8;

    logic clk;
    logic rstn;
    logic uart_rx_i;
    logic uart_tx_o;
    logic cpu_stall_debug;
    logic aes_done_debug;

    int unsigned axi_aw_count;
    int unsigned axi_b_count;
    int unsigned axi_ar_count;
    int unsigned axi_r_count;
    int unsigned axi_error_count;

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

    // -------------------------------------------------------------------------
    // Physical UART RX driver.
    // No direct write into DUT registers or SRAM.
    // -------------------------------------------------------------------------
    task automatic uart_send_byte(input logic [7:0] data);
        begin
            @(negedge clk);
            uart_rx_i <= 1'b0; // start
            repeat (UART_BIT_CLKS) @(posedge clk);

            for (int i = 0; i < 8; i++) begin
                @(negedge clk);
                uart_rx_i <= data[i];
                repeat (UART_BIT_CLKS) @(posedge clk);
            end

            @(negedge clk);
            uart_rx_i <= 1'b1; // stop
            repeat (UART_BIT_CLKS) @(posedge clk);
        end
    endtask

    // -------------------------------------------------------------------------
    // Physical UART TX decoder.
    // Samples center of each serial bit.
    // -------------------------------------------------------------------------
    task automatic uart_recv_byte(output logic [7:0] data);
        begin
            @(negedge uart_tx_o); // start-bit edge

            // Center of start bit.
            repeat (UART_BIT_CLKS/2) @(posedge clk);
            if (uart_tx_o !== 1'b0)
                $fatal(1, "UART TX start-bit sampling failed");

            // Center of data bit 0.
            repeat (UART_BIT_CLKS) @(posedge clk);

            for (int i = 0; i < 8; i++) begin
                data[i] = uart_tx_o;
                if (i != 7)
                    repeat (UART_BIT_CLKS) @(posedge clk);
            end

            // Stop bit center.
            repeat (UART_BIT_CLKS) @(posedge clk);
            if (uart_tx_o !== 1'b1)
                $fatal(1, "UART TX stop-bit sampling failed");
        end
    endtask

    task automatic send_request(
        input logic [255:0] key,
        input logic [127:0] plaintext
    );
        begin
            $display("[%0t] Sending 32-byte key through UART RX", $time);
            for (int i = 31; i >= 0; i--)
                uart_send_byte(key[i*8 +: 8]);

            $display("[%0t] Sending 16-byte plaintext through UART RX", $time);
            for (int i = 15; i >= 0; i--)
                uart_send_byte(plaintext[i*8 +: 8]);
        end
    endtask

    task automatic receive_and_check(
        input logic [127:0] expected,
        input int unsigned vector_id
    );
        logic [7:0] b;
        logic [127:0] result;
        begin
            result = '0;

            for (int i = 0; i < 16; i++) begin
                uart_recv_byte(b);
                result = {result[119:0], b};
                $display("[%0t] VECTOR%0d TX byte[%0d] = %02h",
                         $time, vector_id, i, b);
            end

            $display("VECTOR%0d RESULT = %032h", vector_id, result);
            $display("VECTOR%0d EXPECT = %032h", vector_id, expected);

            if (result !== expected)
                $fatal(1,
                    "VECTOR%0d ciphertext mismatch: got=%032h expected=%032h",
                    vector_id, result, expected);

            $display("VECTOR%0d : PASS", vector_id);
        end
    endtask

    // AXI accounting: response pairing + no error response.
    always @(posedge clk) begin
        if (!rstn) begin
            axi_aw_count    <= 0;
            axi_b_count     <= 0;
            axi_ar_count    <= 0;
            axi_r_count     <= 0;
            axi_error_count <= 0;
        end
        else begin
            if (dut.cpu_axi.awvalid && dut.cpu_axi.awready)
                axi_aw_count <= axi_aw_count + 1;

            if (dut.cpu_axi.bvalid && dut.cpu_axi.bready) begin
                axi_b_count <= axi_b_count + 1;
                if (dut.cpu_axi.bresp != 2'b00)
                    axi_error_count <= axi_error_count + 1;
            end

            if (dut.cpu_axi.arvalid && dut.cpu_axi.arready)
                axi_ar_count <= axi_ar_count + 1;

            if (dut.cpu_axi.rvalid && dut.cpu_axi.rready) begin
                axi_r_count <= axi_r_count + 1;
                if (dut.cpu_axi.rresp != 2'b00)
                    axi_error_count <= axi_error_count + 1;
            end
        end
    end

    initial begin : test
        logic [7:0] dummy;

        rstn      = 1'b0;
        uart_rx_i = 1'b1;

        repeat (8) @(posedge clk);
        @(negedge clk);
        rstn = 1'b1;

        $display("============================================================");
        $display(" UART-RUNTIME AES-256 SYSTEM TEST");
        $display(" Same SoC + same firmware, two external input vectors");
        $display(" No key/plaintext preloaded in SRAM/ROM");
        $display("============================================================");

        // Synchronization only: wait until firmware has configured UART RX/TX.
        // Test data still enters exclusively through physical uart_rx_i.
        wait (dut.u_uart_slave.control_reg_q[1:0] == 2'b11);

        fork
            begin
                send_request(KEY1, PT1);
            end
            begin
                receive_and_check(CT1, 1);
            end
        join

        // No reset and no firmware reload here. Same running firmware.
        // Allow CPU to return to its next receive loop.
        repeat (32) @(posedge clk);

        fork
            begin
                send_request(KEY2, PT2);
            end
            begin
                receive_and_check(CT2, 2);
            end
        join

        // Allow last AXI response counters to settle.
        repeat (32) @(posedge clk);

        if (axi_aw_count != axi_b_count)
            $fatal(1, "AXI AW/B mismatch %0d/%0d", axi_aw_count, axi_b_count);

        if (axi_ar_count != axi_r_count)
            $fatal(1, "AXI AR/R mismatch %0d/%0d", axi_ar_count, axi_r_count);

        if (axi_error_count != 0)
            $fatal(1, "AXI error responses observed: %0d", axi_error_count);

        $display("");
        $display("============================================================");
        $display(" UART-RUNTIME AES SYSTEM TEST PASSED");
        $display("============================================================");
        $display(" Vector 1 external UART input -> AES -> UART output : PASS");
        $display(" Vector 2 external UART input -> AES -> UART output : PASS");
        $display(" Same firmware, no reset between vectors            : PASS");
        $display(" AXI AW/B = %0d/%0d", axi_aw_count, axi_b_count);
        $display(" AXI AR/R = %0d/%0d", axi_ar_count, axi_r_count);
        $display("============================================================");

        test_passed = 1'b1;
        $finish;
    end

    initial begin : timeout
        repeat (1_000_000) @(posedge clk);
        $fatal(1, "UART-RUNTIME AES SYSTEM TEST TIMEOUT");
    end

endmodule
