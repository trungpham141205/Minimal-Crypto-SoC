`timescale 1ns/1ps

module tb_l1_icache;

    bit test_passed = 1'b0;

    localparam time         CLK_PERIOD = 10ns;
    localparam logic [31:0] MEM_BASE   = 32'h0001_0000;

    logic        clk = 1'b0;
    logic        rstn = 1'b0;

    logic        cpu_req;
    logic [31:0] cpu_addr;
    logic [31:0] cpu_instr;
    logic        cpu_valid;

    logic        mem_req;
    logic [31:0] mem_addr;
    logic [31:0] mem_rdata;
    logic        mem_valid;

    logic        invalidate_all;
    logic        hit;
    logic        miss;
    logic        busy;

    logic [31:0] backing_memory [0:255];
    logic        response_enable;

    int unsigned refill_transfer_count;
    int unsigned hit_cycle_count;
    int unsigned memory_index;

    l1_icache #(
        .NUM_SETS       (32),
        .WORDS_PER_LINE (4)
    ) dut (
        .clk              (clk),
        .rstn             (rstn),
        .cpu_req_i        (cpu_req),
        .cpu_addr_i       (cpu_addr),
        .cpu_instr_o      (cpu_instr),
        .cpu_valid_o      (cpu_valid),
        .mem_req_o        (mem_req),
        .mem_addr_o       (mem_addr),
        .mem_rdata_i      (mem_rdata),
        .mem_valid_i      (mem_valid),
        .invalidate_all_i (invalidate_all),
        .hit_o            (hit),
        .miss_o           (miss),
        .busy_o           (busy)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    // A deliberately throttled combinational memory model.  It accepts one
    // refill word every other cycle so the test also proves that the cache
    // holds mem_req/mem_addr while the lower memory is waiting.
    always_ff @(posedge clk) begin
        if (!rstn)
            response_enable <= 1'b0;
        else
            response_enable <= ~response_enable;
    end

    always_comb begin
        memory_index = 0;
        mem_rdata    = 32'b0;
        mem_valid    = mem_req && response_enable;

        if ((mem_addr >= MEM_BASE) && (mem_addr < MEM_BASE + 32'd1024)) begin
            memory_index = (mem_addr - MEM_BASE) >> 2;
            mem_rdata    = backing_memory[memory_index];
        end
    end

    always_ff @(posedge clk) begin
        if (!rstn) begin
            refill_transfer_count <= 0;
            hit_cycle_count       <= 0;
        end
        else begin
            if (mem_req && mem_valid)
                refill_transfer_count <= refill_transfer_count + 1;
            if (cpu_req && cpu_valid && hit)
                hit_cycle_count <= hit_cycle_count + 1;
        end
    end

    task automatic fetch_and_check(
        input logic [31:0] address,
        input logic [31:0] expected_data,
        input int unsigned expected_new_transfers
    );
        int unsigned transfers_before;
        int unsigned timeout;
        begin
            transfers_before = refill_transfer_count;
            cpu_addr = address;
            cpu_req  = 1'b1;
            timeout  = 0;
            #1;
            while (!cpu_valid && timeout < 100) begin
                @(posedge clk);
                #1;
                timeout++;
            end

            if (!cpu_valid)
                $fatal(1, "Fetch timeout at address %08h", address);

            if (cpu_instr !== expected_data)
                $fatal(1,
                    "Instruction mismatch at %08h: expected=%08h actual=%08h",
                    address, expected_data, cpu_instr);

            if ((refill_transfer_count - transfers_before) !=
                expected_new_transfers)
                $fatal(1,
                    "Wrong refill count at %08h: expected=%0d actual=%0d",
                    address,
                    expected_new_transfers,
                    refill_transfer_count - transfers_before);

            @(negedge clk);
            cpu_req = 1'b0;
            #1;
        end
    endtask

    initial begin : initialize_memory
        for (int i = 0; i < 256; i++)
            backing_memory[i] = 32'hA500_0000 + i;
    end

    initial begin : test_sequence
        cpu_req        = 1'b0;
        cpu_addr       = MEM_BASE;
        invalidate_all = 1'b0;

        repeat (4) @(posedge clk);
        @(negedge clk);
        rstn = 1'b1;

        // Cold miss at word 2 of line 0: exactly four lower-memory reads.
        fetch_and_check(32'h0001_0008, 32'hA500_0002, 4);

        // Same line, different word: must be a hit with no memory read.
        fetch_and_check(32'h0001_000C, 32'hA500_0003, 0);

        // Next 16-byte line: another four-word refill.
        fetch_and_check(32'h0001_0010, 32'hA500_0004, 4);

        // 0x00010208 maps to the same set as 0x00010008 but has another tag.
        fetch_and_check(32'h0001_0208, 32'hA500_0082, 4);

        // The conflict evicted line 0, so fetching it again must miss.
        fetch_and_check(32'h0001_0008, 32'hA500_0002, 4);

        // Global invalidation must turn the just-filled line into a miss.
        @(negedge clk);
        invalidate_all = 1'b1;
        @(posedge clk);
        @(negedge clk);
        invalidate_all = 1'b0;
        fetch_and_check(32'h0001_0008, 32'hA500_0002, 4);

        if (refill_transfer_count != 20)
            $fatal(1, "Unexpected total refill count: %0d",
                   refill_transfer_count);

        $display("============================================================");
        $display(" L1 I-CACHE UNIT TEST PASSED");
        $display("============================================================");
        $display(" Cold miss / four-word refill : PASS");
        $display(" Same-line hit                : PASS");
        $display(" Conflict replacement         : PASS");
        $display(" Global invalidation          : PASS");
        $display(" Refill transfers             : %0d", refill_transfer_count);
        $display("============================================================");

        test_passed = 1'b1;
        $finish;
    end

    initial begin : timeout
        repeat (2000) @(posedge clk);
        $fatal(1, "L1 I-cache unit test timed out");
    end

endmodule
