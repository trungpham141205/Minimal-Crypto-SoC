module uart_axi_slave #(
    parameter logic [31:0] BASE_ADDR = 32'h1000_0000
)(
    input  logic uart_rx_i,
    output logic uart_tx_o,

    axi_full_if.slave s_axi
);

    localparam logic [11:0] TXDATA_OFF   = 12'h000;
    localparam logic [11:0] RXDATA_OFF   = 12'h004;
    localparam logic [11:0] STATUS_OFF   = 12'h008;
    localparam logic [11:0] CONTROL_OFF  = 12'h00C;
    localparam logic [11:0] BAUDRATE_OFF = 12'h010;

    logic aw_hold_q;
    logic w_hold_q;
    logic [31:0] awaddr_q;
    logic [3:0]  awid_q;
    logic [7:0]  awlen_q;
    logic [2:0]  awsize_q;
    logic [31:0] wdata_q;
    logic [3:0]  wstrb_q;
    logic        wlast_q;

    logic        bvalid_q;
    logic [1:0]  bresp_q;

    logic        rvalid_q;
    logic [3:0]  rid_q;
    logic [31:0] rdata_q;
    logic [1:0]  rresp_q;
    logic        read_rxdata_q;

    logic [31:0] control_reg_q;
    logic [15:0] baudrate_reg_q;

    logic [7:0]  tx_data_q;
    logic        tx_pending_q;

    logic [7:0] uart_rx_data;
    logic       uart_rx_valid;
    logic       uart_tx_ready;
    logic       uart_parity_err;
    logic       uart_frame_err;
    logic       uart_rx_ready;

    logic tx_slot_available;
    logic write_format_ok;
    logic [11:0] wr_off;
    logic [11:0] rd_off;

    function automatic logic [31:0] merge_wstrb32 (
        input logic [31:0] old_value,
        input logic [31:0] new_value,
        input logic [3:0]  strb
    );
        logic [31:0] tmp;
        begin
            tmp = old_value;
            for (int i = 0; i < 4; i++) begin
                if (strb[i])
                    tmp[8*i +: 8] = new_value[8*i +: 8];
            end
            return tmp;
        end
    endfunction

    assign wr_off = awaddr_q[11:0];
    assign rd_off = s_axi.araddr[11:0];
    assign tx_slot_available = !tx_pending_q || uart_tx_ready;
    assign write_format_ok = (awlen_q == 8'd0) && (awsize_q == 3'b010) && wlast_q;

    assign uart_rx_ready = rvalid_q && s_axi.rready && read_rxdata_q && uart_rx_valid;

    uart_core u_uart_core (
        .clk           (s_axi.clk),
        .rstn          (s_axi.rstn),
        .i_baudrate    (baudrate_reg_q),
        .i_parity_mode (control_reg_q[3:2]),
        .i_frame_mode  (control_reg_q[4]),
        .i_tx_en       (control_reg_q[0]),
        .i_rx_en       (control_reg_q[1]),
        .i_data        (tx_data_q),
        .i_data_valid  (tx_pending_q),
        .o_ready       (uart_tx_ready),
        .o_tx          (uart_tx_o),
        .i_rx           (uart_rx_i),
        .o_data         (uart_rx_data),
        .o_data_valid   (uart_rx_valid),
        .i_ready        (uart_rx_ready),
        .o_parity_err   (uart_parity_err),
        .o_frame_err    (uart_frame_err)
    );

    always_ff @(posedge s_axi.clk) begin
        if (!s_axi.rstn) begin
            aw_hold_q       <= 1'b0;
            w_hold_q        <= 1'b0;
            awaddr_q        <= '0;
            awid_q          <= '0;
            awlen_q         <= '0;
            awsize_q        <= '0;
            wdata_q         <= '0;
            wstrb_q         <= '0;
            wlast_q         <= 1'b0;
            bvalid_q        <= 1'b0;
            bresp_q         <= 2'b00;
            rvalid_q        <= 1'b0;
            rid_q           <= '0;
            rdata_q         <= '0;
            rresp_q         <= 2'b00;
            read_rxdata_q   <= 1'b0;
            control_reg_q   <= 32'b0;
            baudrate_reg_q  <= 16'b0;
            tx_data_q       <= 8'b0;
            tx_pending_q    <= 1'b0;
        end
        else begin
            // Consume buffered TX byte when uart_core accepts it.
            if (tx_pending_q && uart_tx_ready)
                tx_pending_q <= 1'b0;

            if (!aw_hold_q && !bvalid_q && s_axi.awvalid && s_axi.awready) begin
                aw_hold_q <= 1'b1;
                awaddr_q  <= s_axi.awaddr;
                awid_q    <= s_axi.awid;
                awlen_q   <= s_axi.awlen;
                awsize_q  <= s_axi.awsize;
            end

            if (!w_hold_q && !bvalid_q && s_axi.wvalid && s_axi.wready) begin
                w_hold_q <= 1'b1;
                wdata_q  <= s_axi.wdata;
                wstrb_q  <= s_axi.wstrb;
                wlast_q  <= s_axi.wlast;
            end

            if (aw_hold_q && w_hold_q && !bvalid_q) begin
                bvalid_q  <= 1'b1;
                bresp_q   <= 2'b00;
                aw_hold_q <= 1'b0;
                w_hold_q  <= 1'b0;

                if (!write_format_ok) begin
                    bresp_q <= 2'b10;
                end
                else begin
                    case (wr_off)
                        TXDATA_OFF: begin
                            if (wstrb_q[0] && tx_slot_available) begin
                                tx_data_q    <= wdata_q[7:0];
                                tx_pending_q <= 1'b1;
                            end
                            else if (!tx_slot_available) begin
                                bresp_q <= 2'b10;
                            end
                        end

                        CONTROL_OFF: begin
                            control_reg_q <= merge_wstrb32(control_reg_q, wdata_q, wstrb_q);
                        end

                        BAUDRATE_OFF: begin
                            if (wstrb_q[0]) baudrate_reg_q[7:0]  <= wdata_q[7:0];
                            if (wstrb_q[1]) baudrate_reg_q[15:8] <= wdata_q[15:8];
                        end

                        default: bresp_q <= 2'b10;
                    endcase
                end
            end

            if (bvalid_q && s_axi.bready)
                bvalid_q <= 1'b0;

            if (!rvalid_q && s_axi.arvalid && s_axi.arready) begin
                rvalid_q      <= 1'b1;
                rid_q         <= s_axi.arid;
                rresp_q       <= 2'b00;
                read_rxdata_q <= 1'b0;

                if ((s_axi.arlen != 8'd0) || (s_axi.arsize != 3'b010)) begin
                    rdata_q <= 32'b0;
                    rresp_q <= 2'b10;
                end
                else begin
                    case (rd_off)
                        TXDATA_OFF:   rdata_q <= {24'b0, tx_data_q};
                        RXDATA_OFF: begin
                            rdata_q       <= uart_rx_valid ? {24'b0, uart_rx_data} : 32'b0;
                            read_rxdata_q <= uart_rx_valid;
                        end
                        STATUS_OFF: begin
                            rdata_q <= {
                                27'b0,
                                tx_pending_q,
                                uart_frame_err,
                                uart_parity_err,
                                uart_rx_valid,
                                uart_tx_ready
                            };
                        end
                        CONTROL_OFF:  rdata_q <= control_reg_q;
                        BAUDRATE_OFF: rdata_q <= {16'b0, baudrate_reg_q};
                        default: begin
                            rdata_q <= 32'b0;
                            rresp_q <= 2'b10;
                        end
                    endcase
                end
            end

            if (rvalid_q && s_axi.rready) begin
                rvalid_q      <= 1'b0;
                read_rxdata_q <= 1'b0;
            end
        end
    end

    always_comb begin
        s_axi.awready = !aw_hold_q && !bvalid_q;
        s_axi.wready  = !w_hold_q  && !bvalid_q;
        s_axi.bid     = awid_q;
        s_axi.bresp   = bresp_q;
        s_axi.bvalid  = bvalid_q;
        s_axi.bchk    = 1'b0;

        s_axi.arready = !rvalid_q;
        s_axi.rid     = rid_q;
        s_axi.rdata   = rdata_q;
        s_axi.rresp   = rresp_q;
        s_axi.rlast   = 1'b1;
        s_axi.rvalid  = rvalid_q;
        s_axi.rchk    = 4'b0;
    end

endmodule
