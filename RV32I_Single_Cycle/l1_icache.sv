module l1_icache #(
    parameter int NUM_SETS       = 32,
    parameter int WORDS_PER_LINE = 4
)(
    input  logic        clk,
    input  logic        rstn,

    // Upper side: instruction_fetch_router.
    // The request/address remain stable while cpu_valid_o is low.
    input  logic        cpu_req_i,
    input  logic [31:0] cpu_addr_i,
    output logic [31:0] cpu_instr_o,
    output logic        cpu_valid_o,

    // Lower side: cpu_axi_request_arbiter.
    // One 32-bit read is issued for each word in a cache line.
    output logic        mem_req_o,
    output logic [31:0] mem_addr_o,
    input  logic [31:0] mem_rdata_i,
    input  logic        mem_valid_i,

    // Used after executable memory is modified through the data path.
    input  logic        invalidate_all_i,

    // Bring-up/debug outputs.
    output logic        hit_o,
    output logic        miss_o,
    output logic        busy_o
);

    // This first implementation intentionally uses the project configuration:
    //   512-byte direct-mapped cache
    //   32 sets
    //   16-byte line = four 32-bit instructions
    // Address split: tag=[31:9], index=[8:4], word=[3:2], byte=[1:0].
    localparam int INDEX_WIDTH  = $clog2(NUM_SETS);
    localparam int WORD_WIDTH   = $clog2(WORDS_PER_LINE);
    localparam int OFFSET_WIDTH = 2 + WORD_WIDTH;
    localparam int TAG_WIDTH    = 32 - OFFSET_WIDTH - INDEX_WIDTH;

    // The current implementation depends on powers of two and four words/line.
    initial begin
        if (NUM_SETS != 32)
            $error("l1_icache currently expects NUM_SETS=32");
        if (WORDS_PER_LINE != 4)
            $error("l1_icache currently expects WORDS_PER_LINE=4");
    end

    logic [31:0]          data_array  [0:NUM_SETS-1][0:WORDS_PER_LINE-1];
    logic [TAG_WIDTH-1:0] tag_array   [0:NUM_SETS-1];
    logic                 valid_array [0:NUM_SETS-1];

    typedef enum logic {
        IC_LOOKUP,
        IC_REFILL
    } state_t;

    state_t state_q;

    logic [31:0]          miss_line_base_q;
    logic [INDEX_WIDTH-1:0] miss_index_q;
    logic [TAG_WIDTH-1:0] miss_tag_q;
    logic [WORD_WIDTH-1:0] refill_word_q;

    logic [INDEX_WIDTH-1:0] lookup_index;
    logic [WORD_WIDTH-1:0]  lookup_word;
    logic [TAG_WIDTH-1:0]   lookup_tag;
    logic                   lookup_hit;

    integer set_idx;

    assign lookup_index = cpu_addr_i[OFFSET_WIDTH + INDEX_WIDTH - 1 : OFFSET_WIDTH];
    assign lookup_word  = cpu_addr_i[OFFSET_WIDTH - 1 : 2];
    assign lookup_tag   = cpu_addr_i[31 : OFFSET_WIDTH + INDEX_WIDTH];

    assign lookup_hit =
        valid_array[lookup_index] &&
        (tag_array[lookup_index] == lookup_tag);

    // Combinational hit path.  This preserves the current single-cycle CPU's
    // same-cycle fetch behavior.  A later SRAM-macro implementation should
    // register this lookup and add an IF pipeline stage/instruction buffer.
    always_comb begin
        cpu_instr_o = 32'h0000_0013;
        cpu_valid_o = 1'b0;

        mem_req_o   = 1'b0;
        mem_addr_o  = miss_line_base_q +
                      {{(32-WORD_WIDTH-2){1'b0}}, refill_word_q, 2'b00};

        hit_o       = 1'b0;
        miss_o      = 1'b0;
        busy_o      = (state_q == IC_REFILL);

        case (state_q)
            IC_LOOKUP: begin
                // A hit may still complete in the cycle invalidate_all_i is
                // asserted.  The sequential block clears all valid bits at
                // the edge, before the following fetch.  Do not gate this hit
                // with invalidate_all_i: that input is derived from the CPU's
                // store request, and gating it would create a combinational
                // fetch -> decode -> store -> invalidate -> fetch loop.
                if (cpu_req_i) begin
                    if (lookup_hit) begin
                        cpu_instr_o = data_array[lookup_index][lookup_word];
                        cpu_valid_o = 1'b1;
                        hit_o       = 1'b1;
                    end
                    else begin
                        miss_o      = 1'b1;
                    end
                end
            end

            IC_REFILL: begin
                // Hold this request until the arbiter returns mem_valid_i.
                mem_req_o = 1'b1;
            end

            default: begin
                // Safe defaults already applied.
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rstn) begin
            state_q          <= IC_LOOKUP;
            miss_line_base_q <= 32'b0;
            miss_index_q     <= '0;
            miss_tag_q       <= '0;
            refill_word_q    <= '0;

            // Data/tag RAM contents need not be reset.  Invalid entries are
            // architecturally ignored until a complete refill sets valid=1.
            for (set_idx = 0; set_idx < NUM_SETS; set_idx = set_idx + 1)
                valid_array[set_idx] <= 1'b0;
        end
        else if (invalidate_all_i) begin
            // Abort any in-progress refill and invalidate every cached line.
            // This simple policy is safe for boot-time firmware loading.
            state_q       <= IC_LOOKUP;
            refill_word_q <= '0;

            for (set_idx = 0; set_idx < NUM_SETS; set_idx = set_idx + 1)
                valid_array[set_idx] <= 1'b0;
        end
        else begin
            case (state_q)
                IC_LOOKUP: begin
                    if (cpu_req_i && !lookup_hit) begin
                        // Capture all miss metadata before the refill starts.
                        miss_line_base_q <= {
                            cpu_addr_i[31:OFFSET_WIDTH],
                            {OFFSET_WIDTH{1'b0}}
                        };
                        miss_index_q  <= lookup_index;
                        miss_tag_q    <= lookup_tag;
                        refill_word_q <= '0;

                        // A victim line must not hit while it is being replaced.
                        valid_array[lookup_index] <= 1'b0;
                        state_q <= IC_REFILL;
                    end
                end

                IC_REFILL: begin
                    if (mem_valid_i) begin
                        data_array[miss_index_q][refill_word_q] <= mem_rdata_i;

                        if (refill_word_q == WORDS_PER_LINE-1) begin
                            // Publish the line only after all four words exist.
                            tag_array[miss_index_q]   <= miss_tag_q;
                            valid_array[miss_index_q] <= 1'b1;
                            refill_word_q             <= '0;
                            state_q                   <= IC_LOOKUP;
                        end
                        else begin
                            refill_word_q <= refill_word_q + 1'b1;
                        end
                    end
                end

                default: begin
                    state_q       <= IC_LOOKUP;
                    refill_word_q <= '0;
                end
            endcase
        end
    end

endmodule
