module aes_axi_slave #(
    parameter logic [31:0] BASE_ADDR = 32'h2000_0000
)(
    output logic done_debug,
    axi_full_if.slave s_axi
);

    localparam logic [11:0] CONTROL_OFF = 12'h000;
    localparam logic [11:0] STATUS_OFF  = 12'h004;
    localparam logic [11:0] PT0_OFF     = 12'h010;
    localparam logic [11:0] PT1_OFF     = 12'h014;
    localparam logic [11:0] PT2_OFF     = 12'h018;
    localparam logic [11:0] PT3_OFF     = 12'h01C;
    localparam logic [11:0] KEY0_OFF    = 12'h020;
    localparam logic [11:0] KEY1_OFF    = 12'h024;
    localparam logic [11:0] KEY2_OFF    = 12'h028;
    localparam logic [11:0] KEY3_OFF    = 12'h02C;
    localparam logic [11:0] KEY4_OFF    = 12'h030;
    localparam logic [11:0] KEY5_OFF    = 12'h034;
    localparam logic [11:0] KEY6_OFF    = 12'h038;
    localparam logic [11:0] KEY7_OFF    = 12'h03C;
    localparam logic [11:0] CT0_OFF     = 12'h040;
    localparam logic [11:0] CT1_OFF     = 12'h044;
    localparam logic [11:0] CT2_OFF     = 12'h048;
    localparam logic [11:0] CT3_OFF     = 12'h04C;

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

    logic [31:0] pt_q  [0:3];
    logic [31:0] key_q [0:7];
    logic [31:0] ct_q  [0:3];

    logic [127:0] aes_plain_text;
    logic [255:0] aes_cipher_key;
    logic [127:0] aes_cipher_text;
    logic         aes_valid_in_q;
    logic         aes_valid_out;
    logic         busy_q;
    logic         done_q;

    logic [11:0] wr_off;
    logic [11:0] rd_off;
    logic write_format_ok;

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
    assign write_format_ok = (awlen_q == 8'd0) && (awsize_q == 3'b010) && wlast_q;

    // Register order is NIST-friendly: PT0 is bits [127:96], KEY0 is [255:224].
    assign aes_plain_text = {pt_q[0], pt_q[1], pt_q[2], pt_q[3]};
    assign aes_cipher_key = {key_q[0], key_q[1], key_q[2], key_q[3],
                             key_q[4], key_q[5], key_q[6], key_q[7]};

    assign done_debug = done_q;

    aes_cipher_top u_aes_core (
        .clk         (s_axi.clk),
        .rst_n       (s_axi.rstn),
        .plain_text  (aes_plain_text),
        .cipher_key  (aes_cipher_key),
        .valid_in    (aes_valid_in_q),
        .cipher_text (aes_cipher_text),
        .valid_out   (aes_valid_out)
    );

    always_ff @(posedge s_axi.clk) begin
        if (!s_axi.rstn) begin
            aw_hold_q      <= 1'b0;
            w_hold_q       <= 1'b0;
            awaddr_q       <= '0;
            awid_q         <= '0;
            awlen_q        <= '0;
            awsize_q       <= '0;
            wdata_q        <= '0;
            wstrb_q        <= '0;
            wlast_q        <= 1'b0;
            bvalid_q       <= 1'b0;
            bresp_q        <= 2'b00;
            rvalid_q       <= 1'b0;
            rid_q          <= '0;
            rdata_q        <= '0;
            rresp_q        <= 2'b00;
            aes_valid_in_q <= 1'b0;
            busy_q         <= 1'b0;
            done_q         <= 1'b0;
            for (int i = 0; i < 4; i++) begin
                pt_q[i] <= 32'b0;
                ct_q[i] <= 32'b0;
            end
            for (int i = 0; i < 8; i++) begin
                key_q[i] <= 32'b0;
            end
        end
        else begin
            aes_valid_in_q <= 1'b0;

            if (aes_valid_out) begin
                ct_q[0] <= aes_cipher_text[127:96];
                ct_q[1] <= aes_cipher_text[95:64];
                ct_q[2] <= aes_cipher_text[63:32];
                ct_q[3] <= aes_cipher_text[31:0];
                busy_q  <= 1'b0;
                done_q  <= 1'b1;
            end

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
                        CONTROL_OFF: begin
                            if (wdata_q[1])
                                done_q <= 1'b0;

                            if (wdata_q[0]) begin
                                if (!busy_q) begin
                                    aes_valid_in_q <= 1'b1;
                                    busy_q         <= 1'b1;
                                    done_q         <= 1'b0;
                                end
                                else begin
                                    bresp_q <= 2'b10;
                                end
                            end
                        end

                        PT0_OFF:  pt_q[0]  <= merge_wstrb32(pt_q[0],  wdata_q, wstrb_q);
                        PT1_OFF:  pt_q[1]  <= merge_wstrb32(pt_q[1],  wdata_q, wstrb_q);
                        PT2_OFF:  pt_q[2]  <= merge_wstrb32(pt_q[2],  wdata_q, wstrb_q);
                        PT3_OFF:  pt_q[3]  <= merge_wstrb32(pt_q[3],  wdata_q, wstrb_q);
                        KEY0_OFF: key_q[0] <= merge_wstrb32(key_q[0], wdata_q, wstrb_q);
                        KEY1_OFF: key_q[1] <= merge_wstrb32(key_q[1], wdata_q, wstrb_q);
                        KEY2_OFF: key_q[2] <= merge_wstrb32(key_q[2], wdata_q, wstrb_q);
                        KEY3_OFF: key_q[3] <= merge_wstrb32(key_q[3], wdata_q, wstrb_q);
                        KEY4_OFF: key_q[4] <= merge_wstrb32(key_q[4], wdata_q, wstrb_q);
                        KEY5_OFF: key_q[5] <= merge_wstrb32(key_q[5], wdata_q, wstrb_q);
                        KEY6_OFF: key_q[6] <= merge_wstrb32(key_q[6], wdata_q, wstrb_q);
                        KEY7_OFF: key_q[7] <= merge_wstrb32(key_q[7], wdata_q, wstrb_q);
                        default: bresp_q <= 2'b10;
                    endcase
                end
            end

            if (bvalid_q && s_axi.bready)
                bvalid_q <= 1'b0;

            if (!rvalid_q && s_axi.arvalid && s_axi.arready) begin
                rvalid_q <= 1'b1;
                rid_q    <= s_axi.arid;
                rresp_q  <= 2'b00;

                if ((s_axi.arlen != 8'd0) || (s_axi.arsize != 3'b010)) begin
                    rdata_q <= 32'b0;
                    rresp_q <= 2'b10;
                end
                else begin
                    case (rd_off)
                        CONTROL_OFF: rdata_q <= 32'b0;
                        STATUS_OFF:  rdata_q <= {30'b0, done_q, busy_q};
                        PT0_OFF:     rdata_q <= pt_q[0];
                        PT1_OFF:     rdata_q <= pt_q[1];
                        PT2_OFF:     rdata_q <= pt_q[2];
                        PT3_OFF:     rdata_q <= pt_q[3];
                        KEY0_OFF:    rdata_q <= key_q[0];
                        KEY1_OFF:    rdata_q <= key_q[1];
                        KEY2_OFF:    rdata_q <= key_q[2];
                        KEY3_OFF:    rdata_q <= key_q[3];
                        KEY4_OFF:    rdata_q <= key_q[4];
                        KEY5_OFF:    rdata_q <= key_q[5];
                        KEY6_OFF:    rdata_q <= key_q[6];
                        KEY7_OFF:    rdata_q <= key_q[7];
                        CT0_OFF:     rdata_q <= ct_q[0];
                        CT1_OFF:     rdata_q <= ct_q[1];
                        CT2_OFF:     rdata_q <= ct_q[2];
                        CT3_OFF:     rdata_q <= ct_q[3];
                        default: begin
                            rdata_q <= 32'b0;
                            rresp_q <= 2'b10;
                        end
                    endcase
                end
            end

            if (rvalid_q && s_axi.rready)
                rvalid_q <= 1'b0;
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
