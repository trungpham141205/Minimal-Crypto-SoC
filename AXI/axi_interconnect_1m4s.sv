module axi_interconnect_1m4s #(
    parameter logic [31:0] SHARED_SRAM_BASE = 32'h0000_0000,
    parameter logic [31:0] SHARED_SRAM_MASK = 32'hFFFF_FE00,
    parameter logic [31:0] INSTR_SRAM_BASE  = 32'h0001_0000,
    parameter logic [31:0] INSTR_SRAM_MASK  = 32'hFFFF_FC00,
    parameter logic [31:0] UART_BASE        = 32'h1000_0000,
    parameter logic [31:0] UART_MASK        = 32'hFFFF_F000,
    parameter logic [31:0] AES_BASE         = 32'h2000_0000,
    parameter logic [31:0] AES_MASK         = 32'hFFFF_F000
)(
    axi_full_if.slave  s_axi,
    axi_full_if.master m_shared_sram,
    axi_full_if.master m_instr_sram,
    axi_full_if.master m_uart,
    axi_full_if.master m_aes
);

    // Four real destinations plus the decode-error target require 3 bits.
    typedef enum logic [2:0] {
        SEL_SHARED_SRAM,
        SEL_INSTR_SRAM,
        SEL_UART,
        SEL_AES,
        SEL_ERR
    } sel_t;

    logic wr_active_q;
    sel_t wr_sel_q;
    logic [3:0] wr_id_q;
    logic wr_err_bvalid_q;

    logic rd_active_q;
    sel_t rd_sel_q;
    logic [3:0] rd_id_q;
    logic rd_err_rvalid_q;

    sel_t aw_sel;
    sel_t ar_sel;

    function automatic sel_t decode_addr(input logic [31:0] addr);
        begin
            if ((addr & SHARED_SRAM_MASK) == SHARED_SRAM_BASE)
                return SEL_SHARED_SRAM;
            else if ((addr & INSTR_SRAM_MASK) == INSTR_SRAM_BASE)
                return SEL_INSTR_SRAM;
            else if ((addr & UART_MASK) == UART_BASE)
                return SEL_UART;
            else if ((addr & AES_MASK) == AES_BASE)
                return SEL_AES;
            else
                return SEL_ERR;
        end
    endfunction

    assign aw_sel = decode_addr(s_axi.awaddr);
    assign ar_sel = decode_addr(s_axi.araddr);

    // =========================================================================
    // Lock the selected destination for the lifetime of each transaction.
    // =========================================================================
    always_ff @(posedge s_axi.clk) begin
        if (!s_axi.rstn) begin
            wr_active_q      <= 1'b0;
            wr_sel_q         <= SEL_ERR;
            wr_id_q          <= '0;
            wr_err_bvalid_q  <= 1'b0;

            rd_active_q      <= 1'b0;
            rd_sel_q         <= SEL_ERR;
            rd_id_q          <= '0;
            rd_err_rvalid_q  <= 1'b0;
        end
        else begin
            if (!wr_active_q && s_axi.awvalid && s_axi.awready) begin
                wr_active_q <= 1'b1;
                wr_sel_q    <= aw_sel;
                wr_id_q     <= s_axi.awid;
            end

            if (wr_active_q && (wr_sel_q == SEL_ERR) &&
                s_axi.wvalid && s_axi.wready)
                wr_err_bvalid_q <= 1'b1;

            if (s_axi.bvalid && s_axi.bready) begin
                wr_active_q <= 1'b0;
                if (wr_sel_q == SEL_ERR)
                    wr_err_bvalid_q <= 1'b0;
            end

            if (!rd_active_q && s_axi.arvalid && s_axi.arready) begin
                rd_active_q <= 1'b1;
                rd_sel_q    <= ar_sel;
                rd_id_q     <= s_axi.arid;
                if (ar_sel == SEL_ERR)
                    rd_err_rvalid_q <= 1'b1;
            end

            if (s_axi.rvalid && s_axi.rready && s_axi.rlast) begin
                rd_active_q <= 1'b0;
                if (rd_sel_q == SEL_ERR)
                    rd_err_rvalid_q <= 1'b0;
            end
        end
    end

    // =========================================================================
    // AXI routing
    // =========================================================================
    always_comb begin
        // ---------------------------------------------------------------------
        // Downstream defaults: shared SRAM
        // ---------------------------------------------------------------------
        m_shared_sram.awid='0; m_shared_sram.awwakeup=1'b0; m_shared_sram.awaddr='0; m_shared_sram.awlen='0;
        m_shared_sram.awsize='0; m_shared_sram.awburst='0; m_shared_sram.awvalid=1'b0; m_shared_sram.awprot='0; m_shared_sram.awchk='0;
        m_shared_sram.wdata='0; m_shared_sram.wstrb='0; m_shared_sram.wlast=1'b0; m_shared_sram.wvalid=1'b0; m_shared_sram.wchk='0;
        m_shared_sram.bready=1'b0;
        m_shared_sram.arid='0; m_shared_sram.arwakeup=1'b0; m_shared_sram.araddr='0; m_shared_sram.arlen='0;
        m_shared_sram.arsize='0; m_shared_sram.arburst='0; m_shared_sram.arvalid=1'b0; m_shared_sram.arprot='0; m_shared_sram.archk='0;
        m_shared_sram.rready=1'b0;

        // ---------------------------------------------------------------------
        // Downstream defaults: instruction SRAM
        // ---------------------------------------------------------------------
        m_instr_sram.awid='0; m_instr_sram.awwakeup=1'b0; m_instr_sram.awaddr='0; m_instr_sram.awlen='0;
        m_instr_sram.awsize='0; m_instr_sram.awburst='0; m_instr_sram.awvalid=1'b0; m_instr_sram.awprot='0; m_instr_sram.awchk='0;
        m_instr_sram.wdata='0; m_instr_sram.wstrb='0; m_instr_sram.wlast=1'b0; m_instr_sram.wvalid=1'b0; m_instr_sram.wchk='0;
        m_instr_sram.bready=1'b0;
        m_instr_sram.arid='0; m_instr_sram.arwakeup=1'b0; m_instr_sram.araddr='0; m_instr_sram.arlen='0;
        m_instr_sram.arsize='0; m_instr_sram.arburst='0; m_instr_sram.arvalid=1'b0; m_instr_sram.arprot='0; m_instr_sram.archk='0;
        m_instr_sram.rready=1'b0;

        // ---------------------------------------------------------------------
        // Downstream defaults: UART
        // ---------------------------------------------------------------------
        m_uart.awid='0; m_uart.awwakeup=1'b0; m_uart.awaddr='0; m_uart.awlen='0;
        m_uart.awsize='0; m_uart.awburst='0; m_uart.awvalid=1'b0; m_uart.awprot='0; m_uart.awchk='0;
        m_uart.wdata='0; m_uart.wstrb='0; m_uart.wlast=1'b0; m_uart.wvalid=1'b0; m_uart.wchk='0;
        m_uart.bready=1'b0;
        m_uart.arid='0; m_uart.arwakeup=1'b0; m_uart.araddr='0; m_uart.arlen='0;
        m_uart.arsize='0; m_uart.arburst='0; m_uart.arvalid=1'b0; m_uart.arprot='0; m_uart.archk='0;
        m_uart.rready=1'b0;

        // ---------------------------------------------------------------------
        // Downstream defaults: AES
        // ---------------------------------------------------------------------
        m_aes.awid='0; m_aes.awwakeup=1'b0; m_aes.awaddr='0; m_aes.awlen='0;
        m_aes.awsize='0; m_aes.awburst='0; m_aes.awvalid=1'b0; m_aes.awprot='0; m_aes.awchk='0;
        m_aes.wdata='0; m_aes.wstrb='0; m_aes.wlast=1'b0; m_aes.wvalid=1'b0; m_aes.wchk='0;
        m_aes.bready=1'b0;
        m_aes.arid='0; m_aes.arwakeup=1'b0; m_aes.araddr='0; m_aes.arlen='0;
        m_aes.arsize='0; m_aes.arburst='0; m_aes.arvalid=1'b0; m_aes.arprot='0; m_aes.archk='0;
        m_aes.rready=1'b0;

        // ---------------------------------------------------------------------
        // Upstream defaults
        // ---------------------------------------------------------------------
        s_axi.awready = 1'b0;
        s_axi.wready  = 1'b0;
        s_axi.bid     = wr_id_q;
        s_axi.bresp   = 2'b00;
        s_axi.bvalid  = 1'b0;
        s_axi.bchk    = 1'b0;

        s_axi.arready = 1'b0;
        s_axi.rid     = rd_id_q;
        s_axi.rdata   = 32'b0;
        s_axi.rresp   = 2'b00;
        s_axi.rlast   = 1'b1;
        s_axi.rvalid  = 1'b0;
        s_axi.rchk    = 4'b0;

        // ---------------------------------------------------------------------
        // AW routing. Selection is locked after AW handshake.
        // ---------------------------------------------------------------------
        if (!wr_active_q) begin
            case (aw_sel)
                SEL_SHARED_SRAM: begin
                    m_shared_sram.awid=s_axi.awid; m_shared_sram.awwakeup=s_axi.awwakeup; m_shared_sram.awaddr=s_axi.awaddr;
                    m_shared_sram.awlen=s_axi.awlen; m_shared_sram.awsize=s_axi.awsize; m_shared_sram.awburst=s_axi.awburst;
                    m_shared_sram.awvalid=s_axi.awvalid; m_shared_sram.awprot=s_axi.awprot; m_shared_sram.awchk=s_axi.awchk;
                    s_axi.awready=m_shared_sram.awready;
                end

                SEL_INSTR_SRAM: begin
                    m_instr_sram.awid=s_axi.awid; m_instr_sram.awwakeup=s_axi.awwakeup; m_instr_sram.awaddr=s_axi.awaddr;
                    m_instr_sram.awlen=s_axi.awlen; m_instr_sram.awsize=s_axi.awsize; m_instr_sram.awburst=s_axi.awburst;
                    m_instr_sram.awvalid=s_axi.awvalid; m_instr_sram.awprot=s_axi.awprot; m_instr_sram.awchk=s_axi.awchk;
                    s_axi.awready=m_instr_sram.awready;
                end

                SEL_UART: begin
                    m_uart.awid=s_axi.awid; m_uart.awwakeup=s_axi.awwakeup; m_uart.awaddr=s_axi.awaddr;
                    m_uart.awlen=s_axi.awlen; m_uart.awsize=s_axi.awsize; m_uart.awburst=s_axi.awburst;
                    m_uart.awvalid=s_axi.awvalid; m_uart.awprot=s_axi.awprot; m_uart.awchk=s_axi.awchk;
                    s_axi.awready=m_uart.awready;
                end

                SEL_AES: begin
                    m_aes.awid=s_axi.awid; m_aes.awwakeup=s_axi.awwakeup; m_aes.awaddr=s_axi.awaddr;
                    m_aes.awlen=s_axi.awlen; m_aes.awsize=s_axi.awsize; m_aes.awburst=s_axi.awburst;
                    m_aes.awvalid=s_axi.awvalid; m_aes.awprot=s_axi.awprot; m_aes.awchk=s_axi.awchk;
                    s_axi.awready=m_aes.awready;
                end

                default: s_axi.awready = 1'b1;
            endcase
        end

        // ---------------------------------------------------------------------
        // W/B routing uses the AW-selected target until B completes.
        // ---------------------------------------------------------------------
        if (wr_active_q) begin
            case (wr_sel_q)
                SEL_SHARED_SRAM: begin
                    m_shared_sram.wdata=s_axi.wdata; m_shared_sram.wstrb=s_axi.wstrb; m_shared_sram.wlast=s_axi.wlast;
                    m_shared_sram.wvalid=s_axi.wvalid; m_shared_sram.wchk=s_axi.wchk; s_axi.wready=m_shared_sram.wready;
                    s_axi.bid=m_shared_sram.bid; s_axi.bresp=m_shared_sram.bresp; s_axi.bvalid=m_shared_sram.bvalid; s_axi.bchk=m_shared_sram.bchk;
                    m_shared_sram.bready=s_axi.bready;
                end

                SEL_INSTR_SRAM: begin
                    m_instr_sram.wdata=s_axi.wdata; m_instr_sram.wstrb=s_axi.wstrb; m_instr_sram.wlast=s_axi.wlast;
                    m_instr_sram.wvalid=s_axi.wvalid; m_instr_sram.wchk=s_axi.wchk; s_axi.wready=m_instr_sram.wready;
                    s_axi.bid=m_instr_sram.bid; s_axi.bresp=m_instr_sram.bresp; s_axi.bvalid=m_instr_sram.bvalid; s_axi.bchk=m_instr_sram.bchk;
                    m_instr_sram.bready=s_axi.bready;
                end

                SEL_UART: begin
                    m_uart.wdata=s_axi.wdata; m_uart.wstrb=s_axi.wstrb; m_uart.wlast=s_axi.wlast;
                    m_uart.wvalid=s_axi.wvalid; m_uart.wchk=s_axi.wchk; s_axi.wready=m_uart.wready;
                    s_axi.bid=m_uart.bid; s_axi.bresp=m_uart.bresp; s_axi.bvalid=m_uart.bvalid; s_axi.bchk=m_uart.bchk;
                    m_uart.bready=s_axi.bready;
                end

                SEL_AES: begin
                    m_aes.wdata=s_axi.wdata; m_aes.wstrb=s_axi.wstrb; m_aes.wlast=s_axi.wlast;
                    m_aes.wvalid=s_axi.wvalid; m_aes.wchk=s_axi.wchk; s_axi.wready=m_aes.wready;
                    s_axi.bid=m_aes.bid; s_axi.bresp=m_aes.bresp; s_axi.bvalid=m_aes.bvalid; s_axi.bchk=m_aes.bchk;
                    m_aes.bready=s_axi.bready;
                end

                default: begin
                    s_axi.wready = !wr_err_bvalid_q;
                    s_axi.bid    = wr_id_q;
                    s_axi.bresp  = 2'b11; // DECERR
                    s_axi.bvalid = wr_err_bvalid_q;
                    s_axi.bchk   = 1'b0;
                end
            endcase
        end

        // ---------------------------------------------------------------------
        // AR routing. Selection is locked after AR handshake.
        // ---------------------------------------------------------------------
        if (!rd_active_q) begin
            case (ar_sel)
                SEL_SHARED_SRAM: begin
                    m_shared_sram.arid=s_axi.arid; m_shared_sram.arwakeup=s_axi.arwakeup; m_shared_sram.araddr=s_axi.araddr;
                    m_shared_sram.arlen=s_axi.arlen; m_shared_sram.arsize=s_axi.arsize; m_shared_sram.arburst=s_axi.arburst;
                    m_shared_sram.arvalid=s_axi.arvalid; m_shared_sram.arprot=s_axi.arprot; m_shared_sram.archk=s_axi.archk;
                    s_axi.arready=m_shared_sram.arready;
                end

                SEL_INSTR_SRAM: begin
                    m_instr_sram.arid=s_axi.arid; m_instr_sram.arwakeup=s_axi.arwakeup; m_instr_sram.araddr=s_axi.araddr;
                    m_instr_sram.arlen=s_axi.arlen; m_instr_sram.arsize=s_axi.arsize; m_instr_sram.arburst=s_axi.arburst;
                    m_instr_sram.arvalid=s_axi.arvalid; m_instr_sram.arprot=s_axi.arprot; m_instr_sram.archk=s_axi.archk;
                    s_axi.arready=m_instr_sram.arready;
                end

                SEL_UART: begin
                    m_uart.arid=s_axi.arid; m_uart.arwakeup=s_axi.arwakeup; m_uart.araddr=s_axi.araddr;
                    m_uart.arlen=s_axi.arlen; m_uart.arsize=s_axi.arsize; m_uart.arburst=s_axi.arburst;
                    m_uart.arvalid=s_axi.arvalid; m_uart.arprot=s_axi.arprot; m_uart.archk=s_axi.archk;
                    s_axi.arready=m_uart.arready;
                end

                SEL_AES: begin
                    m_aes.arid=s_axi.arid; m_aes.arwakeup=s_axi.arwakeup; m_aes.araddr=s_axi.araddr;
                    m_aes.arlen=s_axi.arlen; m_aes.arsize=s_axi.arsize; m_aes.arburst=s_axi.arburst;
                    m_aes.arvalid=s_axi.arvalid; m_aes.arprot=s_axi.arprot; m_aes.archk=s_axi.archk;
                    s_axi.arready=m_aes.arready;
                end

                default: s_axi.arready = 1'b1;
            endcase
        end

        // ---------------------------------------------------------------------
        // R routing from the locked target.
        // ---------------------------------------------------------------------
        if (rd_active_q) begin
            case (rd_sel_q)
                SEL_SHARED_SRAM: begin
                    s_axi.rid=m_shared_sram.rid; s_axi.rdata=m_shared_sram.rdata; s_axi.rresp=m_shared_sram.rresp;
                    s_axi.rlast=m_shared_sram.rlast; s_axi.rvalid=m_shared_sram.rvalid; s_axi.rchk=m_shared_sram.rchk;
                    m_shared_sram.rready=s_axi.rready;
                end

                SEL_INSTR_SRAM: begin
                    s_axi.rid=m_instr_sram.rid; s_axi.rdata=m_instr_sram.rdata; s_axi.rresp=m_instr_sram.rresp;
                    s_axi.rlast=m_instr_sram.rlast; s_axi.rvalid=m_instr_sram.rvalid; s_axi.rchk=m_instr_sram.rchk;
                    m_instr_sram.rready=s_axi.rready;
                end

                SEL_UART: begin
                    s_axi.rid=m_uart.rid; s_axi.rdata=m_uart.rdata; s_axi.rresp=m_uart.rresp;
                    s_axi.rlast=m_uart.rlast; s_axi.rvalid=m_uart.rvalid; s_axi.rchk=m_uart.rchk;
                    m_uart.rready=s_axi.rready;
                end

                SEL_AES: begin
                    s_axi.rid=m_aes.rid; s_axi.rdata=m_aes.rdata; s_axi.rresp=m_aes.rresp;
                    s_axi.rlast=m_aes.rlast; s_axi.rvalid=m_aes.rvalid; s_axi.rchk=m_aes.rchk;
                    m_aes.rready=s_axi.rready;
                end

                default: begin
                    s_axi.rid    = rd_id_q;
                    s_axi.rdata  = 32'b0;
                    s_axi.rresp  = 2'b11; // DECERR
                    s_axi.rlast  = 1'b1;
                    s_axi.rvalid = rd_err_rvalid_q;
                    s_axi.rchk   = 4'b0;
                end
            endcase
        end
    end

endmodule
