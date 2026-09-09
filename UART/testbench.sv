`timescale 1ns/1ps

module tb_uart_core;

    localparam time CLK_PERIOD = 10ns;
    localparam logic [15:0] BAUD_CONFIG = 16'd1;
    localparam int CLKS_PER_BIT = 8 * (BAUD_CONFIG + 1);
    localparam int RX_TIMEOUT_CLKS = 4_000;

    logic        clk;
    logic        rstn;
    logic [15:0] i_baudrate;
    logic [1:0]  i_parity_mode;
    logic        i_frame_mode;
    logic        i_tx_en;
    logic        i_rx_en;
    logic [7:0]  i_data;
    logic        i_data_valid;
    logic        o_ready;
    logic        o_tx;
    logic        i_rx;
    logic [7:0]  o_data;
    logic        o_data_valid;
    logic        i_ready;
    logic        o_parity_err;
    logic        o_frame_err;

    logic loopback_enable;
    logic rx_drive;

    int checks_run;

    assign i_rx = loopback_enable ? o_tx : rx_drive;

    uart_core dut (
        .clk           (clk),
        .rstn          (rstn),
        .i_baudrate    (i_baudrate),
        .i_parity_mode (i_parity_mode),
        .i_frame_mode  (i_frame_mode),
        .i_tx_en       (i_tx_en),
        .i_rx_en       (i_rx_en),
        .i_data        (i_data),
        .i_data_valid  (i_data_valid),
        .o_ready       (o_ready),
        .o_tx          (o_tx),
        .i_rx           (i_rx),
        .o_data        (o_data),
        .o_data_valid  (o_data_valid),
        .i_ready       (i_ready),
        .o_parity_err  (o_parity_err),
        .o_frame_err   (o_frame_err)
    );

    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    task automatic apply_reset;
        begin
            rstn = 1'b0;
            repeat (10) @(posedge clk);
            @(negedge clk);
            rstn = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic configure_core(
        input logic [1:0] parity_mode,
        input logic       frame_mode,
        input logic       tx_enable,
        input logic       rx_enable
    );
        begin
            // The specification requires disabling the core before reconfiguration.
            @(negedge clk);
            i_tx_en = 1'b0;
            i_rx_en = 1'b0;
            repeat (2) @(posedge clk);
            @(negedge clk);
            i_parity_mode = parity_mode;
            i_frame_mode = frame_mode;
            i_tx_en = tx_enable;
            i_rx_en = rx_enable;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic send_tx_byte(input logic [7:0] value);
        int timeout;
        begin
            timeout = 0;
            while ((o_ready !== 1'b1) && (timeout < RX_TIMEOUT_CLKS)) begin
                @(negedge clk);
                timeout++;
            end
            if (o_ready !== 1'b1) begin
                $fatal(1, "TX ready timeout for byte 0x%02h", value);
            end

            i_data = value;
            i_data_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            i_data_valid = 1'b0;
        end
    endtask

    task automatic expect_and_consume_good_byte(input logic [7:0] expected);
        int timeout;
        logic [7:0] held_data;
        begin
            timeout = 0;
            while ((o_data_valid !== 1'b1) && (timeout < RX_TIMEOUT_CLKS)) begin
                @(posedge clk);
                timeout++;
            end
            if (o_data_valid !== 1'b1) begin
                $fatal(1, "RX valid timeout; expected 0x%02h", expected);
            end
            if (o_data !== expected) begin
                $fatal(1, "RX mismatch: expected 0x%02h, received 0x%02h", expected, o_data);
            end
            if (o_parity_err || o_frame_err) begin
                $fatal(1, "Unexpected RX error for 0x%02h: parity=%0b frame=%0b",
                       expected, o_parity_err, o_frame_err);
            end

            // Exercise back-pressure: data and valid must remain stable until ready.
            held_data = o_data;
            repeat (3) begin
                @(posedge clk);
                if (!o_data_valid || (o_data !== held_data)) begin
                    $fatal(1, "RX valid/data changed while i_ready was low");
                end
            end

            @(negedge clk);
            i_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            i_ready = 1'b0;
            if (o_data_valid) begin
                $fatal(1, "RX valid did not clear after valid-ready handshake");
            end
            checks_run++;
        end
    endtask

    task automatic drive_one_uart_bit(input logic bit_value);
        begin
            @(negedge clk);
            rx_drive = bit_value;
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    task automatic drive_rx_frame(
        input logic [7:0] value,
        input logic [1:0] parity_mode,
        input logic       frame_mode,
        input logic       corrupt_parity,
        input logic       corrupt_stop_1,
        input logic       corrupt_stop_2
    );
        logic parity_value;
        int bit_index;
        begin
            drive_one_uart_bit(1'b0);
            for (bit_index = 0; bit_index < 8; bit_index++) begin
                drive_one_uart_bit(value[bit_index]);
            end

            if (parity_mode[0]) begin
                case (parity_mode)
                    2'b01: parity_value = ~^value;
                    2'b11: parity_value =  ^value;
                    default: parity_value = 1'b0;
                endcase
                drive_one_uart_bit(parity_value ^ corrupt_parity);
            end

            drive_one_uart_bit(!corrupt_stop_1);
            if (frame_mode) begin
                drive_one_uart_bit(!corrupt_stop_2);
            end
            @(negedge clk);
            rx_drive = 1'b1;
        end
    endtask

    task automatic expect_parity_error(input logic [7:0] expected);
        int timeout;
        begin
            timeout = 0;
            while ((o_data_valid !== 1'b1) && (timeout < RX_TIMEOUT_CLKS)) begin
                @(posedge clk);
                timeout++;
            end
            if (o_data_valid !== 1'b1) begin
                $fatal(1, "Parity-error frame did not make its byte available");
            end
            if ((o_data !== expected) || !o_parity_err || o_frame_err) begin
                $fatal(1, "Bad parity-error result: data=%02h parity=%0b frame=%0b",
                       o_data, o_parity_err, o_frame_err);
            end
            @(negedge clk);
            i_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            i_ready = 1'b0;
            checks_run++;
        end
    endtask

    task automatic expect_frame_error;
        int timeout;
        begin
            timeout = 0;
            while ((o_frame_err !== 1'b1) && (timeout < RX_TIMEOUT_CLKS)) begin
                @(posedge clk);
                timeout++;
            end
            if (o_frame_err !== 1'b1) begin
                $fatal(1, "Frame error was not reported");
            end
            if (o_data_valid) begin
                $fatal(1, "Frame-error byte was incorrectly buffered");
            end
            checks_run++;
        end
    endtask

    initial begin : test_sequence
        int parity_index;
        int frame_index;
        int data_index;

        rstn = 1'b0;
        i_baudrate = BAUD_CONFIG;
        i_parity_mode = 2'b00;
        i_frame_mode = 1'b0;
        i_tx_en = 1'b0;
        i_rx_en = 1'b0;
        i_data = '0;
        i_data_valid = 1'b0;
        i_ready = 1'b0;
        loopback_enable = 1'b1;
        rx_drive = 1'b1;
        checks_run = 0;

        apply_reset();

        if ((o_tx !== 1'b1) || (o_ready !== 1'b0)) begin
            $fatal(1, "TX reset/disabled outputs are incorrect");
        end

        // Exhaustive loopback over every byte, parity encoding and stop-bit mode.
        for (frame_index = 0; frame_index < 2; frame_index++) begin
            for (parity_index = 0; parity_index < 4; parity_index++) begin
                configure_core(parity_index[1:0], frame_index[0], 1'b1, 1'b1);
                for (data_index = 0; data_index < 256; data_index++) begin
                    send_tx_byte(data_index[7:0]);
                    expect_and_consume_good_byte(data_index[7:0]);
                end
                $display("PASS loopback: parity=%02b frame=%0b", parity_index[1:0], frame_index[0]);
            end
        end

        // Inject a bad odd-parity bit. The byte must remain readable.
        loopback_enable = 1'b0;
        rx_drive = 1'b1;
        configure_core(2'b01, 1'b0, 1'b0, 1'b1);
        drive_rx_frame(8'hA6, 2'b01, 1'b0, 1'b1, 1'b0, 1'b0);
        expect_parity_error(8'hA6);

        // Corrupt the only stop bit. The byte must be discarded.
        configure_core(2'b00, 1'b0, 1'b0, 1'b1);
        drive_rx_frame(8'h3C, 2'b00, 1'b0, 1'b0, 1'b1, 1'b0);
        expect_frame_error();

        // In two-stop-bit mode, corruption of either stop bit is an error.
        configure_core(2'b11, 1'b1, 1'b0, 1'b1);
        drive_rx_frame(8'h5A, 2'b11, 1'b1, 1'b0, 1'b1, 1'b0);
        expect_frame_error();

        configure_core(2'b11, 1'b1, 1'b0, 1'b1);
        drive_rx_frame(8'hC3, 2'b11, 1'b1, 1'b0, 1'b0, 1'b1);
        expect_frame_error();

        $display("ALL UART TESTS PASSED (%0d checked frames)", checks_run);
        $finish;
    end

  	
`ifndef NO_DUMP_WAVE
    initial begin
      $dumpfile("tb_uart_core.vcd");
      $dumpvars(0, tb_uart_core);
    end
`endif
  
    initial begin
        #20ms;
        $fatal(1, "Global testbench timeout");
    end

endmodule

