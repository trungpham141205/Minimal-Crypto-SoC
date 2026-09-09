module risc_top (
    input  logic        clk,
    input  logic        rstn,

    // ---------------------------------------------------------------------
    // External instruction-fetch interface.
    // fetch_req_o remains asserted until the current PC has a valid
    // instruction.  A future I-cache can therefore return fetch_valid_i in
    // the same cycle on a hit, preserving the single-cycle execution path.
    // ---------------------------------------------------------------------
    output logic [31:0] fetch_addr_o,
    output logic        fetch_req_o,
    input  logic [31:0] fetch_instr_i,
    input  logic        fetch_valid_i,

    // ---------------------------------------------------------------------
    // Native load/store interface.
    // data_stall_i remains asserted until the selected data transaction is
    // complete.
    // ---------------------------------------------------------------------
    input  logic        data_stall_i,
    output logic        mem_read_wire,
    output logic        mem_write_wire,
    output logic [2:0]  funct3_wire,
    output logic [31:0] mem_addr,
    output logic [31:0] mem_wdata,
    input  logic [31:0] mem_rdata
);

    // Program counter
    logic [31:0] pc;
    logic [31:0] pc_next;
    logic [31:0] pc_inc;
    logic [31:0] pc_target;

    // ---------------------------------------------------------------------
    // Instruction hold register
    //
    // A normal instruction can execute directly from fetch_instr_i whenever
    // fetch_valid_i is high.  This keeps the cache-hit path single-cycle.
    //
    // A LOAD/STORE can outlive the fetch response because its data AXI access
    // takes multiple cycles.  In that case the fetched instruction is copied
    // into instruction_hold_q and held until the data transaction completes.
    // ---------------------------------------------------------------------
    logic [31:0] instruction_hold_q;
    logic        instruction_hold_valid_q;
    logic [31:0] instruction;
    logic        instruction_available;

    // Control unit
    logic        funct7;
    logic [2:0]  funct3;
    logic [6:0]  opcode;
    logic        reg_write;
    logic [1:0]  reg_back;
    logic [2:0]  imm_sel;
    logic        src_a_sel;
    logic        src_b_sel;
    logic [3:0]  alu_control;
    logic        mem_read;
    logic        mem_write;
    logic [1:0]  pc_sel;

    // Register file
    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [4:0]  rd;
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;

    // Datapath
    logic [31:0] imm_ext;
    logic [31:0] src_a;
    logic [31:0] src_b;
    logic [31:0] result;
    logic        zero;
    logic [31:0] write_back;

    logic execute_mem_op;
    logic cpu_hold;

    assign instruction_available =
        instruction_hold_valid_q || fetch_valid_i;

    always_comb begin
        if (instruction_hold_valid_q)
            instruction = instruction_hold_q;
        else if (fetch_valid_i)
            instruction = fetch_instr_i;
        else
            instruction = 32'h0000_0013; // NOP while fetch is outstanding
    end

    assign funct7 = instruction[30];
    assign funct3 = instruction[14:12];
    assign opcode = instruction[6:0];
    assign rs1    = instruction[19:15];
    assign rs2    = instruction[24:20];
    assign rd     = instruction[11:7];

    // ---------------------------------------------------------------------
    // Fetch side
    // No new fetch is requested while a LOAD/STORE instruction is being held.
    // ---------------------------------------------------------------------
    assign fetch_addr_o = pc;
    assign fetch_req_o  = rstn && !instruction_hold_valid_q;

    // ---------------------------------------------------------------------
    // Data side
    // A memory request can only be emitted for a valid current instruction.
    // ---------------------------------------------------------------------
    assign mem_read_wire  = instruction_available && mem_read;
    assign mem_write_wire = instruction_available && mem_write;
    assign funct3_wire    = funct3;
    assign mem_addr       = result;
    assign mem_wdata      = rs2_data;

    assign execute_mem_op =
        instruction_available && (mem_read || mem_write);

    // Hold architectural state when instruction fetch is not yet valid, or
    // while a LOAD/STORE is waiting for the data path to finish.
    assign cpu_hold =
        !instruction_available ||
        (execute_mem_op && data_stall_i);

    // Preserve a fetched memory instruction across its data-side stall.
    always_ff @(posedge clk) begin
        if (!rstn) begin
            instruction_hold_q       <= 32'h0000_0013;
            instruction_hold_valid_q <= 1'b0;
        end
        else begin
            if (instruction_hold_valid_q) begin
                // The held memory instruction retires when the data path
                // releases stall.  PC/register commit occur on this same edge.
                if (!data_stall_i)
                    instruction_hold_valid_q <= 1'b0;
            end
            else if (fetch_valid_i && (mem_read || mem_write) && data_stall_i) begin
                instruction_hold_q       <= fetch_instr_i;
                instruction_hold_valid_q <= 1'b1;
            end
        end
    end

    // ---------------------------------------------------------------------
    // Datapath instances
    // ---------------------------------------------------------------------
    program_counter dut_pc (
        .clk     (clk),
        .rstn    (rstn),
        .stall_i (cpu_hold),
        .pc_next (pc_next),
        .pc      (pc)
    );

    control_unit dut_control_unit (
        .funct7      (funct7),
        .funct3      (funct3),
        .opcode      (opcode),
        .reg_write   (reg_write),
        .reg_back    (reg_back),
        .imm_sel     (imm_sel),
        .src_a_sel   (src_a_sel),
        .src_b_sel   (src_b_sel),
        .alu_control (alu_control),
        .mem_read    (mem_read),
        .mem_write   (mem_write),
        .pc_sel      (pc_sel)
    );

    register_file dut_register_file (
        .reg_write  (reg_write),
        .stall_i    (cpu_hold),
        .clk        (clk),
        .rs1        (rs1),
        .rs2        (rs2),
        .rd         (rd),
        .write_data (write_back),
        .rs1_data   (rs1_data),
        .rs2_data   (rs2_data)
    );

    immediate_generator dut_immediate_generator (
        .imm_sel (imm_sel),
        .instr   (instruction),
        .imm_ext (imm_ext)
    );

    alu_src_a_mux dut_alu_src_a_mux (
        .src_a_sel (src_a_sel),
        .reg_data  (rs1_data),
        .pc_data   (pc),
        .src_a     (src_a)
    );

    alu_src_b_mux dut_alu_src_b_mux (
        .src_b_sel (src_b_sel),
        .reg_data  (rs2_data),
        .imm_data  (imm_ext),
        .src_b     (src_b)
    );

    alu dut_alu (
        .alu_control (alu_control),
        .a           (src_a),
        .b           (src_b),
        .result      (result),
        .zero        (zero)
    );

    write_back_mux dut_write_back_mux (
        .reg_back    (reg_back),
        .alu_result  (result),
        .data_memory (mem_rdata),
        .pc_adder    (pc_inc),
        .imm         (imm_ext),
        .write_back  (write_back)
    );

    pc_adder dut_pc_adder (
        .pc     (pc),
        .pc_inc (pc_inc)
    );

    pc_imm dut_pc_imm (
        .pc_sel    (pc_sel),
        .rs1_data  (rs1_data),
        .pc        (pc),
        .imm       (imm_ext),
        .pc_target (pc_target)
    );

    branch_unit dut_branch_unit (
        .pc_sel    (pc_sel),
        .zero      (zero),
        .funct3    (funct3),
        .pc_inc    (pc_inc),
        .pc_target (pc_target),
        .pc_next   (pc_next)
    );

    // ---------------------------------------------------------------------
    // Debug registers retained for existing testbenches/waveforms.
    // ---------------------------------------------------------------------
    (* keep = "true", preserve *) logic [31:0] pc_debug;
    (* keep = "true", preserve *) logic [31:0] instr_debug;
    (* keep = "true", preserve *) logic [31:0] wb_debug;
    (* keep = "true", preserve *) logic [4:0]  rd_debug;
    (* keep = "true", preserve *) logic        regwrite_debug;

    always_ff @(posedge clk) begin
        if (!rstn) begin
            pc_debug       <= 32'b0;
            instr_debug    <= 32'h0000_0013;
            wb_debug       <= 32'b0;
            rd_debug       <= 5'b0;
            regwrite_debug <= 1'b0;
        end
        else begin
            pc_debug       <= pc;
            instr_debug    <= instruction;
            wb_debug       <= write_back;
            rd_debug       <= rd;
            regwrite_debug <= reg_write && !cpu_hold;
        end
    end

endmodule
