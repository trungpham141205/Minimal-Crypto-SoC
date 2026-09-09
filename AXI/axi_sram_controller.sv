module axi_sram_controller #(
    parameter logic [31:0] BASE_ADDR = 32'h0000_0000
)(
    axi_full_if.slave s_axi,

    // Native synchronous single-port SRAM interface
    output logic        sram_me,
    output logic        sram_we,
    output logic [7:0]  sram_addr,
    output logic [31:0] sram_wdata,
    input  logic [31:0] sram_rdata
);

    // =========================================================================
    // Reusable AXI single-beat controller for SRAM1RW256x32-class memories.
    //
    // Memory characteristics expected by this controller:
    //   - 256 x 32 = 1024 bytes
    //   - synchronous single-port read/write
    //   - no native byte-write-enable pins
    //
    // AXI subset used by the current SoC:
    //   - one outstanding transaction per controller instance
    //   - LEN=0 only
    //   - SIZE=32-bit only
    //   - full-word stores are written directly
    //   - partial stores use read-modify-write based on WSTRB
    //
    // READY depends only on registered state/capture flags to preserve the
    // registered-handshake structure of the existing SoC.
    // =========================================================================

    typedef enum logic [2:0] {
        W_COLLECT,
        W_DIRECT_WRITE,
        W_RMW_READ,
        W_RMW_WRITE,
        W_RESP
    } write_state_t;

    typedef enum logic [1:0] {
        R_IDLE,
        R_ISSUE,
        R_RESP
    } read_state_t;

    write_state_t wstate_q, wstate_d;
    read_state_t  rstate_q, rstate_d;

    // -------------------------------------------------------------------------
    // Captured AW/W
    // -------------------------------------------------------------------------
    logic        aw_captured_q;
    logic        w_captured_q;

    logic [31:0] awaddr_q;
    logic [3:0]  awid_q;
    logic [7:0]  awlen_q;
    logic [2:0]  awsize_q;

    logic [31:0] wdata_q;
    logic [3:0]  wstrb_q;
    logic        wlast_q;

    // -------------------------------------------------------------------------
    // Captured AR
    // -------------------------------------------------------------------------
    logic [31:0] araddr_q;
    logic [3:0]  arid_q;
    logic [7:0]  arlen_q;
    logic [2:0]  arsize_q;

    logic [31:0] rmw_merged_data;
    logic        write_format_ok;
    logic        read_format_ok;

    assign write_format_ok =
        (awlen_q  == 8'd0)   &&
        (awsize_q == 3'b010) &&
        wlast_q;

    assign read_format_ok =
        (arlen_q  == 8'd0)   &&
        (arsize_q == 3'b010);

    // -------------------------------------------------------------------------
    // Byte-lane merge for SB/SH because the macro only supports whole-word WE.
    // -------------------------------------------------------------------------
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

    assign rmw_merged_data = merge_wstrb32(
        sram_rdata,
        wdata_q,
        wstrb_q
    );

    // =========================================================================
    // Sequential request capture / state
    // =========================================================================
    always_ff @(posedge s_axi.clk) begin
        if (!s_axi.rstn) begin
            wstate_q       <= W_COLLECT;
            rstate_q       <= R_IDLE;

            aw_captured_q  <= 1'b0;
            w_captured_q   <= 1'b0;

            awaddr_q       <= 32'b0;
            awid_q         <= 4'b0;
            awlen_q        <= 8'b0;
            awsize_q       <= 3'b0;

            wdata_q        <= 32'b0;
            wstrb_q        <= 4'b0;
            wlast_q        <= 1'b0;

            araddr_q       <= 32'b0;
            arid_q         <= 4'b0;
            arlen_q        <= 8'b0;
            arsize_q       <= 3'b0;
        end
        else begin
            wstate_q <= wstate_d;
            rstate_q <= rstate_d;

            if (s_axi.awvalid && s_axi.awready) begin
                aw_captured_q <= 1'b1;
                awaddr_q      <= s_axi.awaddr;
                awid_q        <= s_axi.awid;
                awlen_q       <= s_axi.awlen;
                awsize_q      <= s_axi.awsize;
            end

            if (s_axi.wvalid && s_axi.wready) begin
                w_captured_q <= 1'b1;
                wdata_q      <= s_axi.wdata;
                wstrb_q      <= s_axi.wstrb;
                wlast_q      <= s_axi.wlast;
            end

            if ((wstate_q == W_RESP) && s_axi.bready) begin
                aw_captured_q <= 1'b0;
                w_captured_q  <= 1'b0;
            end

            if (s_axi.arvalid && s_axi.arready) begin
                araddr_q <= s_axi.araddr;
                arid_q   <= s_axi.arid;
                arlen_q  <= s_axi.arlen;
                arsize_q <= s_axi.arsize;
            end
        end
    end

    // =========================================================================
    // Write FSM
    // =========================================================================
    always_comb begin
        wstate_d = wstate_q;

        case (wstate_q)
            W_COLLECT: begin
                if (aw_captured_q && w_captured_q) begin
                    if (!write_format_ok)
                        wstate_d = W_RESP;
                    else if (wstrb_q == 4'b0000)
                        wstate_d = W_RESP;
                    else if (wstrb_q == 4'b1111)
                        wstate_d = W_DIRECT_WRITE;
                    else
                        wstate_d = W_RMW_READ;
                end
            end

            W_DIRECT_WRITE: wstate_d = W_RESP;
            W_RMW_READ:     wstate_d = W_RMW_WRITE;
            W_RMW_WRITE:    wstate_d = W_RESP;

            W_RESP: begin
                if (s_axi.bready)
                    wstate_d = W_COLLECT;
            end

            default: wstate_d = W_COLLECT;
        endcase
    end

    // =========================================================================
    // Read FSM
    // =========================================================================
    always_comb begin
        rstate_d = rstate_q;

        case (rstate_q)
            R_IDLE: begin
                if (s_axi.arvalid && s_axi.arready)
                    rstate_d = R_ISSUE;
            end

            R_ISSUE: rstate_d = R_RESP;

            R_RESP: begin
                if (s_axi.rready)
                    rstate_d = R_IDLE;
            end

            default: rstate_d = R_IDLE;
        endcase
    end

    // =========================================================================
    // AXI + native SRAM output decode
    // =========================================================================
    always_comb begin
        // READY: no VALID -> READY combinational dependency.
        s_axi.awready =
            (wstate_q == W_COLLECT) &&
            !aw_captured_q &&
            (rstate_q == R_IDLE);

        s_axi.wready =
            (wstate_q == W_COLLECT) &&
            !w_captured_q &&
            (rstate_q == R_IDLE);

        s_axi.arready =
            (rstate_q == R_IDLE) &&
            (wstate_q == W_COLLECT) &&
            !aw_captured_q &&
            !w_captured_q;

        // B channel
        s_axi.bid    = awid_q;
        s_axi.bresp  = write_format_ok ? 2'b00 : 2'b10;
        s_axi.bvalid = (wstate_q == W_RESP);
        s_axi.bchk   = 1'b0;

        // R channel
        s_axi.rid    = arid_q;
        s_axi.rdata  = read_format_ok ? sram_rdata : 32'b0;
        s_axi.rresp  = read_format_ok ? 2'b00 : 2'b10;
        s_axi.rlast  = 1'b1;
        s_axi.rvalid = (rstate_q == R_RESP);
        s_axi.rchk   = 4'b0;

        // Native SRAM defaults
        sram_me    = 1'b0;
        sram_we    = 1'b0;
        sram_addr  = 8'b0;
        sram_wdata = 32'b0;

        // Full-word write
        if (wstate_q == W_DIRECT_WRITE) begin
            sram_me    = write_format_ok;
            sram_we    = write_format_ok;
            sram_addr  = (awaddr_q - BASE_ADDR) >> 2;
            sram_wdata = wdata_q;
        end
        // Partial write phase 1: read old word
        else if (wstate_q == W_RMW_READ) begin
            sram_me    = write_format_ok;
            sram_we    = 1'b0;
            sram_addr  = (awaddr_q - BASE_ADDR) >> 2;
        end
        // Partial write phase 2: write merged word
        else if (wstate_q == W_RMW_WRITE) begin
            sram_me    = write_format_ok;
            sram_we    = write_format_ok;
            sram_addr  = (awaddr_q - BASE_ADDR) >> 2;
            sram_wdata = rmw_merged_data;
        end
        // Read
        else if (rstate_q == R_ISSUE) begin
            sram_me    = read_format_ok;
            sram_we    = 1'b0;
            sram_addr  = (araddr_q - BASE_ADDR) >> 2;
        end
    end

endmodule

