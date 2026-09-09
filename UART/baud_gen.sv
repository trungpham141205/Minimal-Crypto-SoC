module baud_gen (
    input  logic        clk,
    input  logic        rstn,
    input  logic [15:0] i_baudrate,
    input  logic        i_tx_en,
    input  logic        i_rx_en,
    output logic        tx_baud_tick,
    output logic        rx_baud_tick
);

    localparam int unsigned OVERSAMPLE_RATE = 8;

    logic [15:0] tx_div_cnt;
    logic [15:0] rx_div_cnt;
    logic [2:0]  tx_oversample_cnt;

    always_ff @(posedge clk) begin
        if (!rstn) begin
            tx_div_cnt         <= '0;
            rx_div_cnt         <= '0;
            tx_oversample_cnt  <= '0;
            tx_baud_tick       <= 1'b0;
            rx_baud_tick       <= 1'b0;
        end
        else begin
            tx_baud_tick <= 1'b0;
            rx_baud_tick <= 1'b0;

            if (!i_rx_en) begin
                rx_div_cnt <= '0;
            end
            else if (rx_div_cnt >= i_baudrate) begin
                rx_div_cnt   <= '0;
                rx_baud_tick <= 1'b1;
            end
            else begin
                rx_div_cnt <= rx_div_cnt + 16'd1;
            end

            if (!i_tx_en) begin
                tx_div_cnt        <= '0;
                tx_oversample_cnt <= '0;
            end
            else if (tx_div_cnt >= i_baudrate) begin
                tx_div_cnt <= '0;
                if (tx_oversample_cnt == OVERSAMPLE_RATE - 1) begin
                    tx_oversample_cnt <= '0;
                    tx_baud_tick      <= 1'b1;
                end
                else begin
                    tx_oversample_cnt <= tx_oversample_cnt + 3'd1;
                end
            end
            else begin
                tx_div_cnt <= tx_div_cnt + 16'd1;
            end
        end
    end

endmodule
