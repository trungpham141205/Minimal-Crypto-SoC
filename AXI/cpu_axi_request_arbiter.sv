module cpu_axi_request_arbiter (
    input  logic        clk,
    input  logic        rstn,

    // ---------------------------------------------------------------------
    // Instruction-fetch client (read-only, aligned 32-bit access)
    // ---------------------------------------------------------------------
    input  logic        fetch_req_i,
    input  logic [31:0] fetch_addr_i,
    output logic [31:0] fetch_rdata_o,
    output logic        fetch_valid_o,

    // ---------------------------------------------------------------------
    // CPU load/store client
    // ---------------------------------------------------------------------
    input  logic [31:0] data_addr_i,
    input  logic [31:0] data_wdata_i,
    input  logic        data_read_i,
    input  logic        data_write_i,
    input  logic [2:0]  data_funct3_i,
    output logic [31:0] data_rdata_o,
    output logic        data_stall_o,

    // ---------------------------------------------------------------------
    // Unified native request toward the existing axi_master_wrapper
    // ---------------------------------------------------------------------
    output logic [31:0] master_addr_o,
    output logic [31:0] master_wdata_o,
    output logic        master_read_o,
    output logic        master_write_o,
    output logic [2:0]  master_funct3_o,
    input  logic [31:0] master_rdata_i,
    input  logic        master_stall_i
);

    typedef enum logic [1:0] {
        OWN_NONE,
        OWN_FETCH,
        OWN_DATA
    } owner_t;

    owner_t owner_q;

    logic data_req;
    logic select_data;
    logic select_fetch;

    assign data_req = data_read_i || data_write_i;

    // The CPU frontend is designed so fetch and data are normally mutually
    // exclusive.  Data receives priority as a defensive rule in case both are
    // presented simultaneously.
    assign select_data  = (owner_q == OWN_NONE) && data_req;
    assign select_fetch = (owner_q == OWN_NONE) && !data_req && fetch_req_i;

    // Capture the owner at the same edge on which axi_master_wrapper captures
    // the native request.  Keep that owner until the wrapper reaches its DONE
    // cycle (stall_o == 0).
    always_ff @(posedge clk) begin
        if (!rstn) begin
            owner_q <= OWN_NONE;
        end
        else begin
            case (owner_q)
                OWN_NONE: begin
                    if (select_data)
                        owner_q <= OWN_DATA;
                    else if (select_fetch)
                        owner_q <= OWN_FETCH;
                end

                OWN_FETCH: begin
                    if (!master_stall_i)
                        owner_q <= OWN_NONE;
                end

                OWN_DATA: begin
                    if (!master_stall_i)
                        owner_q <= OWN_NONE;
                end

                default: owner_q <= OWN_NONE;
            endcase
        end
    end

    // Launch exactly one native request while there is no outstanding owner.
    // axi_master_wrapper registers request metadata, so the request does not
    // need to remain asserted after owner_q is captured.
    always_comb begin
        master_addr_o   = 32'b0;
        master_wdata_o  = 32'b0;
        master_read_o   = 1'b0;
        master_write_o  = 1'b0;
        master_funct3_o = 3'b010; // LW for instruction fetch

        if (select_data) begin
            master_addr_o   = data_addr_i;
            master_wdata_o  = data_wdata_i;
            master_read_o   = data_read_i;
            master_write_o  = data_write_i;
            master_funct3_o = data_funct3_i;
        end
        else if (select_fetch) begin
            master_addr_o   = fetch_addr_i;
            master_wdata_o  = 32'b0;
            master_read_o   = 1'b1;
            master_write_o  = 1'b0;
            master_funct3_o = 3'b010;
        end
    end

    // Route completion back to the owner.  master_stall_i is low only in the
    // existing wrapper's DONE cycle, at which time master_rdata_i is stable.
    always_comb begin
        fetch_rdata_o = master_rdata_i;
        fetch_valid_o = 1'b0;
        data_rdata_o  = master_rdata_i;

        // A newly presented LOAD/STORE must stall immediately, even before its
        // owner is registered, so the single-cycle execution stage cannot
        // advance past the memory instruction.
        case (owner_q)
            OWN_NONE: begin
                data_stall_o = data_req;
            end

            OWN_FETCH: begin
                fetch_valid_o = !master_stall_i;
                data_stall_o  = data_req;
            end

            OWN_DATA: begin
                data_stall_o = master_stall_i;
            end

            default: begin
                data_stall_o = data_req;
            end
        endcase
    end

endmodule
