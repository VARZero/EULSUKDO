`timescale 1ns/1ps
module ready_station #(
    // Instruction Set Parameters
    parameter int IS_INST_PC_BITWIDTH                   = 32,
    parameter int IS_INST_PC_STEP                       = 4,
    parameter int IS_INST_BITWIDTH                      = 32,
    parameter int IS_INST_REGS                          = 32,
    parameter int IS_INST_OPERANDS                      = 2,
    parameter int IS_INST_IMM                           = 32,

    // Execution Unit Parameters
    parameter int EX_INST_MICROOP_BITWIDTH              = 5,

    // EULSUKDO Structure Parameters
    parameter int STRUCT_DECODE_NEW_INST                = 2,
    parameter int STRUCT_INST_STATE_ENTRIES             = 128,
    parameter int STRUCT_PHYREGS                        = 64,
    parameter int STRUCT_EX_PATH                        = 3,
    parameter int STRUCT_RS_OUT_ENTRY[STRUCT_EX_PATH]   = {1, 3, 1},
    parameter int STRUCT_EX_CORES                       = 5,
    parameter int STRUCT_EX_OUT_RESULT[STRUCT_EX_CORES] = {1, 1, 1, 1, 1},
    parameter int STRUCT_EX_OUT_RESULT_SUM              = 5,
    parameter int STRUCT_EX_BRANCH                      = 1,
    parameter int STRUCT_PRM_ENTRY_UPDATE               = 5,
    parameter int STRUCT_PRM_ENTRY_BUFFER               = 4,
    parameter int STRUCT_UNALLOCATE_PHYREG              = 4,
    parameter int STRUCT_FLOW_WINDOWS                   = 8,
    parameter int STRUCT_FLOW_PC_MAX_RANGE              = 16,

    // Wakeup bandwidth, stored-instruction issue bandwidth and SRAM banking
    // are independent. Banks use low entry-number bits (power of two).
    parameter int STRUCT_IST_ISSUE_WIDTH               = STRUCT_EX_CORES,
    parameter int STRUCT_IST_BANKS                     = 1 << $clog2(
        (STRUCT_DECODE_NEW_INST > STRUCT_IST_ISSUE_WIDTH) ? STRUCT_DECODE_NEW_INST : STRUCT_IST_ISSUE_WIDTH),

    // Minimum instruction capacity per RS EX-path FIFO (not data bit width).
    parameter int STRUCT_RS_FIFO_WIDTH                = 128,

    // Synthesis Create Local Parameters
    localparam int _BITWIDTH_IS_INST_REGS               = $clog2(IS_INST_REGS),
    localparam int _BITWIDTH_STRUCT_INST_STATE_ENTRIES  = $clog2(STRUCT_INST_STATE_ENTRIES),
    localparam int _BITWIDTH_STRUCT_PHYREGS             = $clog2(STRUCT_PHYREGS),
    localparam int _BITWIDTH_STRUCT_EX_PATH             = $clog2(STRUCT_EX_PATH),
    localparam int _BITWIDTH_STRUCT_FLOW_WINDOWS        = (STRUCT_FLOW_WINDOWS > 1)? $clog2(STRUCT_FLOW_WINDOWS) : 1,
    localparam int _BITWIDTH_READY_PRM                  = _BITWIDTH_STRUCT_INST_STATE_ENTRIES+_BITWIDTH_STRUCT_PHYREGS,
    localparam int _BITWIDTH_FLOW_WINDOWS_PC            = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH,
    localparam int _BITWIDTH_INTERNAL_INST_WIDTH        = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
                                                         + _BITWIDTH_STRUCT_EX_PATH
                                                         + EX_INST_MICROOP_BITWIDTH
                                                         + IS_INST_IMM
                                                         + _BITWIDTH_STRUCT_PHYREGS // rd
                                                         + (_BITWIDTH_STRUCT_PHYREGS * IS_INST_OPERANDS) // rs1..n
                                                         + IS_INST_OPERANDS, // Ready1..n
    localparam int _BITWIDTH_EX_INST_WIDTH              = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
                                                         + _BITWIDTH_STRUCT_EX_PATH
                                                         + EX_INST_MICROOP_BITWIDTH
                                                         + IS_INST_IMM
                                                         + _BITWIDTH_STRUCT_PHYREGS // rd
                                                         + (_BITWIDTH_STRUCT_PHYREGS * IS_INST_OPERANDS), // rs1..n
    localparam int _BITWIDTH_EX_RESULT_WIDTH            = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
                                                         + _BITWIDTH_STRUCT_PHYREGS, // rd
    localparam int _BITWIDTH_STRUCT_RETIRED_PHYREG_MSG  = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
                                                         + _BITWIDTH_STRUCT_PHYREGS, // Retired Register
    localparam int _BITWIDTH_STRUCT_JUMP_BRANCH_INFO    = 1 // Jump Register Flag
                                                         + 1 // Branch Flag
                                                         + IS_INST_PC_BITWIDTH, // New Program Counter
    localparam int _BITWIDTH_STRUCT_EX_DONE_PC          = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
) (
    input  wire                                                                                      clk,
    input  wire                                                                                      reset_n,

    // Executable (All phyreg in instruction are ready) Internal Instruction Input (IST)
    input  wire [(STRUCT_DECODE_NEW_INST+STRUCT_IST_ISSUE_WIDTH)-1:0]                               i_ist_ready_inst_valid,
    output reg  [(STRUCT_DECODE_NEW_INST+STRUCT_IST_ISSUE_WIDTH)-1:0]                               o_ist_ready_inst_get,
    input  wire [((STRUCT_DECODE_NEW_INST+STRUCT_IST_ISSUE_WIDTH) *(_BITWIDTH_EX_INST_WIDTH) )-1:0] i_ist_ready_inst_data,
    
    // Wait EX Instruction Output (EX)
    output reg  [STRUCT_EX_CORES-1:0]                                                                o_ex_wait_inst_valid,
    input  wire [STRUCT_EX_CORES-1:0]                                                                i_ex_wait_inst_get,
    output wire [(STRUCT_EX_CORES *(_BITWIDTH_EX_INST_WIDTH) )-1:0]                                  o_ex_wait_inst_data
);
    localparam INPUT_CHANNEL           = STRUCT_DECODE_NEW_INST+STRUCT_IST_ISSUE_WIDTH;
    localparam STARTPOINT_INST_EX_PATH = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                         + IS_INST_PC_BITWIDTH;

    logic [INPUT_CHANNEL-1:0]                           ex_valid        [0:STRUCT_EX_PATH-1];
    logic [_BITWIDTH_STRUCT_EX_PATH-1:0]                compare_ex_path [0:INPUT_CHANNEL-1];
    logic [INPUT_CHANNEL-1:0]                           ex_fifos_ready  [0:STRUCT_EX_PATH-1];
    logic [STRUCT_EX_PATH-1:0]                          ex_fifo_ready;
    logic                                              accept_bundle;
    integer                                             ex_split, input_position;

    // IST transfers the whole bundle together. No path may capture it
    // while another path holds the shared acknowledgement low.
    assign accept_bundle = &ex_fifo_ready;
    assign o_ist_ready_inst_get = {INPUT_CHANNEL{accept_bundle}};

    always_comb begin
        for (ex_split = 0; ex_split < STRUCT_EX_PATH; ex_split = ex_split+1)
            ex_valid[ex_split] = 0;

        for (input_position = 0; input_position < INPUT_CHANNEL; input_position = input_position+1) begin
            compare_ex_path[input_position] = 
                i_ist_ready_inst_data[STARTPOINT_INST_EX_PATH+(_BITWIDTH_EX_INST_WIDTH*input_position) +: _BITWIDTH_STRUCT_EX_PATH];
        end

        for (input_position = 0; input_position < INPUT_CHANNEL; input_position = input_position+1) begin
            for (ex_split = 0; ex_split < STRUCT_EX_PATH; ex_split = ex_split+1) begin
                if (compare_ex_path[input_position] == ex_split)
                    ex_valid[ex_split][input_position] = i_ist_ready_inst_valid[input_position] && accept_bundle;
            end
        end
    end

    genvar  ex_split_gen;

    function automatic int ex_offset(integer ex_path_idx);
        int posit = 0;
        for (integer path = 0; path < ex_path_idx; path = path + 1) begin
            posit = posit + STRUCT_RS_OUT_ENTRY[path];
        end
        return posit;
    endfunction

    generate
        // Each input owns a simple FIFO; only the output heads are gathered.
        for (ex_split_gen = 0; ex_split_gen < STRUCT_EX_PATH; ex_split_gen = ex_split_gen+1) begin
            assign ex_fifo_ready[ex_split_gen] = &ex_fifos_ready[ex_split_gen];

            rs_banked_queue #(
                .DATA_WIDTH    (_BITWIDTH_EX_INST_WIDTH),
                .READ_CHANNEL  (STRUCT_RS_OUT_ENTRY[ex_split_gen]),
                .WRITE_CHANNEL (INPUT_CHANNEL),
                .MIN_FIFO_ENTRY(STRUCT_RS_FIFO_WIDTH)
            ) U_RS_FIFO (
                .clk           (clk),
                .reset_n       (reset_n),
                .i_push        (ex_valid[ex_split_gen]),
                .o_push_ready  (ex_fifos_ready[ex_split_gen]),
                .i_push_data   (i_ist_ready_inst_data),
                .i_pop         (i_ex_wait_inst_get[ex_offset(ex_split_gen) +: STRUCT_RS_OUT_ENTRY[ex_split_gen]]),
                .o_pop_valid   (o_ex_wait_inst_valid[ex_offset(ex_split_gen) +: STRUCT_RS_OUT_ENTRY[ex_split_gen]]),
                .o_pop_data    (o_ex_wait_inst_data[(ex_offset(ex_split_gen)*_BITWIDTH_EX_INST_WIDTH) 
                                                     +: (STRUCT_RS_OUT_ENTRY[ex_split_gen]*_BITWIDTH_EX_INST_WIDTH)])
            );
        end

    endgenerate

endmodule

// Fixed input-to-bank wiring removes the wide input compaction/append network.
// Across input banks, ready instructions may issue out of arrival order.
// Each output is independently held until its execution unit accepts it.
module rs_banked_queue #(
    parameter int DATA_WIDTH = 92,
    parameter int READ_CHANNEL = 3,
    parameter int WRITE_CHANNEL = 8,
    parameter int MIN_FIFO_ENTRY = 128,
    localparam int DEPTH = (MIN_FIFO_ENTRY+WRITE_CHANNEL-1)/WRITE_CHANNEL,
    localparam int BANK_W = WRITE_CHANNEL > 1 ? $clog2(WRITE_CHANNEL) : 1
) (
    input logic clk, reset_n,
    input logic [WRITE_CHANNEL-1:0] i_push,
    output wire [WRITE_CHANNEL-1:0] o_push_ready,
    input logic [WRITE_CHANNEL*DATA_WIDTH-1:0] i_push_data,
    input logic [READ_CHANNEL-1:0] i_pop,
    output wire [READ_CHANNEL-1:0] o_pop_valid,
    output wire [READ_CHANNEL*DATA_WIDTH-1:0] o_pop_data
);
    wire [WRITE_CHANNEL-1:0] empty, full;
    wire [DATA_WIDTH-1:0] head [WRITE_CHANNEL];
    logic [WRITE_CHANNEL-1:0] take, selected [READ_CHANNEL];
    logic [BANK_W-1:0] first_bank, next_bank;
    logic [READ_CHANNEL-1:0] output_valid;
    logic [DATA_WIDTH-1:0] output_data [READ_CHANNEL], gathered [READ_CHANNEL];
    assign o_push_ready = {WRITE_CHANNEL{reset_n}} & ~full;
    assign o_pop_valid = {READ_CHANNEL{reset_n}} & output_valid;
    for (genvar b = 0; b < WRITE_CHANNEL; b++) begin : G_INPUT
        rs_input_fifo #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(DEPTH)) U_FIFO (
            .clk(clk), .reset_n(reset_n), .push(i_push[b] && o_push_ready[b]),
            .data(i_push_data[b*DATA_WIDTH +: DATA_WIDTH]), .pop(take[b]),
            .head(head[b]), .empty(empty[b]), .full(full[b])
        );
    end
    // Rank eligible bank heads in parallel; match them to available output
    // slots. This avoids READ_CHANNEL cascaded priority scans.
    localparam int COUNT_W = $clog2((WRITE_CHANNEL > READ_CHANNEL ? WRITE_CHANNEL : READ_CHANNEL)+1);
    localparam int TREE_LEAVES = 1 << $clog2(WRITE_CHANNEL);
    logic [COUNT_W-1:0] bank_rank [WRITE_CHANNEL], slot_rank [READ_CHANNEL];
    logic [COUNT_W-1:0] taken_count;
    function automatic logic [COUNT_W-1:0] count_banks(input logic [WRITE_CHANNEL-1:0] bits_in);
        logic [COUNT_W-1:0] tree [2*TREE_LEAVES];
        tree[0] = '0;
        for (int k=0; k<TREE_LEAVES; k++) begin
            tree[TREE_LEAVES+k] = '0;
            if (k<WRITE_CHANNEL) tree[TREE_LEAVES+k] = COUNT_W'(bits_in[k]);
        end
        for (int k=TREE_LEAVES-1; k>0; k--) tree[k] = tree[2*k]+tree[2*k+1];
        return tree[1];
    endfunction
    for (genvar b=0; b<WRITE_CHANNEL; b++) begin : G_RANK
        logic [WRITE_CHANNEL-1:0] ahead;
        for (genvar other=0; other<WRITE_CHANNEL; other++) begin : G_AHEAD
            if (other<b)
                assign ahead[other] = !empty[other] && (int'(first_bank)<=other || int'(first_bank)>b);
            else if (other>b)
                assign ahead[other] = !empty[other] && (int'(first_bank)<=other && int'(first_bank)>b);
            else assign ahead[other] = 1'b0;
        end
        assign bank_rank[b] = count_banks(ahead);
    end
    always_comb begin
        take = '0;
        for (int r=0; r<READ_CHANNEL; r++) begin
            slot_rank[r] = '0;
            for (int prev=0; prev<r; prev++)
                slot_rank[r] += COUNT_W'(!output_valid[prev] || i_pop[prev]);
            selected[r] = '0;
            for (int b=0; b<WRITE_CHANNEL; b++) begin
                selected[r][b] = reset_n && (!output_valid[r] || i_pop[r]) &&
                    !empty[b] && bank_rank[b] == slot_rank[r];
                take[b] |= selected[r][b];
            end
        end
        taken_count = count_banks(take);
        next_bank = first_bank;
        for (int b=0; b<WRITE_CHANNEL; b++)
            if (take[b] && bank_rank[b] == taken_count-1'b1)
                next_bank = BANK_W'(b == WRITE_CHANNEL-1 ? 0 : b+1);
    end
    for (genvar r = 0; r < READ_CHANNEL; r++) begin : G_OUTPUT
        always_comb begin
            gathered[r] = '0;
            for (int b = 0; b < WRITE_CHANNEL; b++)
                gathered[r] |= head[b] & {DATA_WIDTH{selected[r][b]}};
        end
        assign o_pop_data[r*DATA_WIDTH +: DATA_WIDTH] = output_data[r];
        always_ff @(posedge clk or negedge reset_n) begin
            if (!reset_n) begin
                output_valid[r] <= 0; output_data[r] <= '0;
            end else if (!output_valid[r] || i_pop[r]) begin
                output_valid[r] <= |selected[r];
                if (|selected[r]) output_data[r] <= gathered[r];
            end
        end
    end
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) first_bank <= '0;
        else first_bank <= next_bank;
    end
endmodule

// Synchronous look-ahead read with write forwarding when an empty FIFO is
// filled. Only control/head forwarding registers reset; RAM can infer BRAM.
module rs_input_fifo #(
    parameter int DATA_WIDTH = 92, DEPTH = 16,
    localparam int ADDR_W = DEPTH > 1 ? $clog2(DEPTH) : 1
) (
    input logic clk, reset_n, push, pop,
    input logic [DATA_WIDTH-1:0] data,
    output wire [DATA_WIDTH-1:0] head,
    output wire empty, full
);
    wire [ADDR_W-1:0] write_addr, read_addr;
    // Writes are accepted using registered Full only, independently of Pop.
    wire write_enable = reset_n && push && !full;
    logic [DATA_WIDTH-1:0] read_data, forward_data;
    logic forward_valid;
    fifo_control #(.FIFO_DEPTH(DEPTH), .READ_DELAY(1)) U_CONTROL (
        .clk(clk), .reset_n(reset_n), .i_flush(1'b0), .i_push(push), .i_pop(pop),
        .o_empty(empty), .o_full(full), .o_push_addr(write_addr),
        .o_pop_addr(read_addr), .o_we()
    );
    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] memory [DEPTH];
    always_ff @(posedge clk) begin
        if (write_enable) memory[write_addr] <= data;
        read_data <= memory[read_addr];
    end
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin forward_valid <= 0; forward_data <= '0; end
        else begin
            forward_valid <= write_enable && write_addr == read_addr;
            if (write_enable && write_addr == read_addr) forward_data <= data;
        end
    end
    assign head = forward_valid ? forward_data : read_data;
endmodule
