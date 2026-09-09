module axi_master_wrapper (
    input  logic        clk,
    input  logic        rstn,

    input  logic [31:0] mem_addr,
    input  logic [31:0] mem_wdata,
    input  logic        mem_read,
    input  logic        mem_write,
    input  logic [2:0]  funct3,

    output logic [31:0] mem_rdata,
    output logic        stall_o,

    axi_full_if.master axi
);

    // =========================================================================
    // CPU -> AXI master adapter
    //
    // Design policy:
    //   - one outstanding transaction
    //   - one AXI beat per CPU load/store
    //   - registered request metadata
    //   - VALID/RREADY/BREADY derived only from registered FSM state
    //   - next-state logic never reads back this module's own AXI outputs
    //
    // This structure intentionally avoids combinational handshake feedback
    // through the interconnect/slaves.
    // =========================================================================

    typedef enum logic [2:0] {
        IDLE,
        WRITE_ADDR,
        WRITE_DATA,
        WRITE_RESP,
        READ_ADDR,
        READ_DATA,
        DONE
    } state_t;

    state_t current_state;
    state_t next_state;

    logic [31:0] mem_addr_q;
    logic [31:0] mem_wdata_q;
    logic [2:0]  funct3_q;
    logic [31:0] mem_rdata_q;

    // -------------------------------------------------------------------------
    // Load formatter
    // -------------------------------------------------------------------------
    function automatic logic [31:0] format_load_data (
        input logic [31:0] rdata,
        input logic [2:0]  load_funct3,
        input logic [1:0]  byte_offset
    );
        logic [7:0]  selected_byte;
        logic [15:0] selected_half;

        begin
            case (byte_offset)
                2'b00: selected_byte = rdata[7:0];
                2'b01: selected_byte = rdata[15:8];
                2'b10: selected_byte = rdata[23:16];
                2'b11: selected_byte = rdata[31:24];
                default: selected_byte = 8'b0;
            endcase

            if (byte_offset[1] == 1'b0)
                selected_half = rdata[15:0];
            else
                selected_half = rdata[31:16];

            case (load_funct3)
                3'b000: format_load_data = {{24{selected_byte[7]}}, selected_byte}; // LB
                3'b001: format_load_data = {{16{selected_half[15]}}, selected_half}; // LH
                3'b010: format_load_data = rdata;                                   // LW
                3'b100: format_load_data = {24'b0, selected_byte};                  // LBU
                3'b101: format_load_data = {16'b0, selected_half};                  // LHU
                default: format_load_data = rdata;
            endcase
        end
    endfunction

    // =========================================================================
    // Sequential state / request / read-response registers
    // =========================================================================
    always_ff @(posedge clk) begin
        if (!rstn) begin
            current_state <= IDLE;

            mem_addr_q     <= 32'b0;
            mem_wdata_q    <= 32'b0;
            funct3_q       <= 3'b0;
            mem_rdata_q    <= 32'b0;
        end
        else begin
            current_state <= next_state;

            // Capture the CPU request while the CPU is being stalled in IDLE.
            if ((current_state == IDLE) && (mem_read || mem_write)) begin
                mem_addr_q  <= mem_addr;
                mem_wdata_q <= mem_wdata;
                funct3_q    <= funct3;
            end

            // READ_DATA always drives RREADY=1, therefore RVALID/RLAST alone
            // identify the actual read-data handshake.
            if ((current_state == READ_DATA) && axi.rvalid && axi.rlast) begin
                mem_rdata_q <= format_load_data(
                    axi.rdata,
                    funct3_q,
                    mem_addr_q[1:0]
                );
            end
        end
    end

    // =========================================================================
    // Next-state logic
    //
    // IMPORTANT:
    // Do not test axi.awvalid / axi.wvalid / axi.rready / axi.bready here.
    // Those outputs are guaranteed by the current FSM state.
    // Only consume signals driven by the opposite endpoint.
    // =========================================================================
    always_comb begin
        next_state = current_state;

        case (current_state)
            IDLE: begin
                if (mem_write && !mem_read)
                    next_state = WRITE_ADDR;
                else if (mem_read && !mem_write)
                    next_state = READ_ADDR;
            end

            WRITE_ADDR: begin
                if (axi.awready)
                    next_state = WRITE_DATA;
            end

            WRITE_DATA: begin
                if (axi.wready)
                    next_state = WRITE_RESP;
            end

            WRITE_RESP: begin
                if (axi.bvalid)
                    next_state = DONE;
            end

            READ_ADDR: begin
                if (axi.arready)
                    next_state = READ_DATA;
            end

            READ_DATA: begin
                if (axi.rvalid && axi.rlast)
                    next_state = DONE;
            end

            DONE: begin
                next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    // =========================================================================
    // CPU-side outputs
    // =========================================================================

    // In IDLE, assert stall immediately when the current instruction requests
    // memory. This prevents the single-cycle CPU from advancing its PC before
    // the request can be captured on the next rising edge.
    always_comb begin
        mem_rdata = mem_rdata_q;

        case (current_state)
            IDLE:    stall_o = mem_read || mem_write;
            DONE:    stall_o = 1'b0;
            default: stall_o = 1'b1;
        endcase
    end

    // =========================================================================
    // AXI output generation
    //
    // This block reads only registered local request/state. It does not read
    // READY/VALID/RDATA from the downstream AXI fabric.
    // =========================================================================
    always_comb begin
        // -------------------------
        // AW defaults
        // -------------------------
        axi.awid      = '0;
        axi.awwakeup  = 1'b0;
        axi.awaddr    = {mem_addr_q[31:2], 2'b00};
        axi.awlen     = 8'd0;
        axi.awsize    = 3'b010;
        axi.awburst   = 2'b01;
        axi.awvalid   = 1'b0;
        axi.awprot    = 3'b000;
        axi.awchk     = 4'b0000;

        // -------------------------
        // W defaults
        // -------------------------
        axi.wdata     = 32'b0;
        axi.wstrb     = 4'b0000;
        axi.wlast     = 1'b1;
        axi.wvalid    = 1'b0;
        axi.wchk      = 4'b0000;

        // -------------------------
        // B
        // -------------------------
        axi.bready    = 1'b0;

        // -------------------------
        // AR defaults
        // -------------------------
        axi.arid      = '0;
        axi.arwakeup  = 1'b0;
        axi.araddr    = {mem_addr_q[31:2], 2'b00};
        axi.arlen     = 8'd0;
        axi.arsize    = 3'b010;
        axi.arburst   = 2'b01;
        axi.arvalid   = 1'b0;
        axi.arprot    = 3'b000;
        axi.archk     = 4'b0000;

        // -------------------------
        // R
        // -------------------------
        axi.rready    = 1'b0;

        case (current_state)
            WRITE_ADDR: begin
                axi.awwakeup = 1'b1;
                axi.awvalid  = 1'b1;
            end

            WRITE_DATA: begin
                axi.wvalid = 1'b1;

                case (funct3_q)
                    3'b000: begin // SB
                        case (mem_addr_q[1:0])
                            2'b00: begin
                                axi.wstrb = 4'b0001;
                                axi.wdata = {24'b0, mem_wdata_q[7:0]};
                            end
                            2'b01: begin
                                axi.wstrb = 4'b0010;
                                axi.wdata = {16'b0, mem_wdata_q[7:0], 8'b0};
                            end
                            2'b10: begin
                                axi.wstrb = 4'b0100;
                                axi.wdata = {8'b0, mem_wdata_q[7:0], 16'b0};
                            end
                            2'b11: begin
                                axi.wstrb = 4'b1000;
                                axi.wdata = {mem_wdata_q[7:0], 24'b0};
                            end
                            default: begin
                                axi.wstrb = 4'b0000;
                                axi.wdata = 32'b0;
                            end
                        endcase
                    end

                    3'b001: begin // SH
                        if (mem_addr_q[1] == 1'b0) begin
                            axi.wstrb = 4'b0011;
                            axi.wdata = {16'b0, mem_wdata_q[15:0]};
                        end
                        else begin
                            axi.wstrb = 4'b1100;
                            axi.wdata = {mem_wdata_q[15:0], 16'b0};
                        end
                    end

                    3'b010: begin // SW
                        axi.wstrb = 4'b1111;
                        axi.wdata = mem_wdata_q;
                    end

                    default: begin
                        axi.wstrb = 4'b0000;
                        axi.wdata = mem_wdata_q;
                    end
                endcase
            end

            WRITE_RESP: begin
                axi.bready = 1'b1;
            end

            READ_ADDR: begin
                axi.arwakeup = 1'b1;
                axi.arvalid  = 1'b1;
            end

            READ_DATA: begin
                axi.rready = 1'b1;
            end

            default: begin
                // Keep defaults.
            end
        endcase
    end

endmodule

