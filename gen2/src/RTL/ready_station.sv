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

    // Synthesis Create Local Parameters
    localparam int _BITWIDTH_IS_INST_REGS               = $clog2(IS_INST_REGS),
    localparam int _BITWIDTH_STRUCT_PHYREGS             = $clog2(STRUCT_PHYREGS),
    localparam int _BITWIDTH_STRUCT_EX_PATH             = $clog2(STRUCT_EX_PATH),
    localparam int _BITWIDTH_STRUCT_FLOW_WINDOWS        = $clog2(STRUCT_FLOW_WINDOWS),
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
    input  wire [(STRUCT_DECODE_NEW_INST+STRUCT_PRM_ENTRY_UPDATE)-1:0]                               i_ist_ready_inst_valid,
    output reg  [(STRUCT_DECODE_NEW_INST+STRUCT_PRM_ENTRY_UPDATE)-1:0]                               o_ist_ready_inst_get,
    input  wire [((STRUCT_DECODE_NEW_INST+STRUCT_PRM_ENTRY_UPDATE) *(_BITWIDTH_EX_INST_WIDTH) )-1:0] i_ist_ready_inst_data,
    
    // Wait EX Instruction Output (EX)
    output reg  [STRUCT_EX_CORES-1:0]                                                                o_ex_wait_inst_valid,
    input  wire [STRUCT_EX_CORES-1:0]                                                                i_ex_wait_inst_get,
    output wire [(STRUCT_EX_CORES *(_BITWIDTH_EX_INST_WIDTH) )-1:0]                                  o_ex_wait_inst_data
);
    localparam INPUT_CHANNEL           = STRUCT_DECODE_NEW_INST+STRUCT_PRM_ENTRY_UPDATE;
    localparam STARTPOINT_INST_EX_PATH = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                         + IS_INST_PC_BITWIDTH;

    logic [INPUT_CHANNEL-1:0]                           ex_valid        [0:STRUCT_EX_PATH-1];
    logic [_BITWIDTH_STRUCT_EX_PATH-1:0]                compare_ex_path [0:INPUT_CHANNEL-1];
    logic [INPUT_CHANNEL-1:0]                           gather_ex_path  [0:STRUCT_EX_PATH-1];
    logic [INPUT_CHANNEL-1:0]                           ex_fifos_ready  [0:INPUT_CHANNEL-1];
    logic [STRUCT_EX_PATH-1:0]                          ex_fifo_ready;
    logic [(INPUT_CHANNEL*_BITWIDTH_EX_INST_WIDTH)-1:0] gather_inst     [0:STRUCT_EX_PATH-1];
    integer                                             ex_split, ex_fifo_ready_idx, input_position;

    always_comb begin
        for (ex_split = 0; ex_split < STRUCT_EX_PATH; ex_split = ex_split+1)
            ex_valid[ex_split] = 0;

        for (input_position = 0; input_position < INPUT_CHANNEL; input_position = input_position+1) begin
            compare_ex_path[input_position] = 
                i_ist_ready_inst_data[STARTPOINT_INST_EX_PATH+(_BITWIDTH_EX_INST_WIDTH*input_position) +: _BITWIDTH_STRUCT_EX_PATH];
        end

        for (input_position = 0; input_position < INPUT_CHANNEL; input_position = input_position+1) begin
            for (ex_split = 0; ex_split < STRUCT_EX_PATH; ex_split = ex_split+1) begin
                if (compare_ex_path[input_position] == ex_split) ex_valid[ex_split][input_position] = i_ist_ready_inst_valid[input_position];
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
        for (ex_split_gen = 0; ex_split_gen < STRUCT_EX_PATH; ex_split_gen = ex_split_gen+1) begin
            valid_gather #(
                .DATA_WIDTH(_BITWIDTH_EX_INST_WIDTH),
                .ENTRIES   (INPUT_CHANNEL)
            ) U_RS_GATHER (
                .i_valid(ex_valid[ex_split_gen]),
                .i_data (i_ist_ready_inst_data),
                .o_valid(gather_ex_path[ex_split_gen]),
                .o_data (gather_inst[ex_split_gen])
            );
        end

        for (ex_split_gen = 0; ex_split_gen < STRUCT_EX_PATH; ex_split_gen = ex_split_gen+1) begin
            fifo_multichan #(
                .DATA_WIDTH    (_BITWIDTH_EX_INST_WIDTH),
                .READ_CHANNEL  (STRUCT_RS_OUT_ENTRY[ex_split_gen]),
                .WRITE_CHANNEL (INPUT_CHANNEL),
                .MIN_FIFO_ENTRY(STRUCT_INST_STATE_ENTRIES),
                .USE_BRAM      (1'b1)
            ) U_RS_FIFO (
                .clk           (clk),
                .reset_n       (reset_n),
                .i_flush       (1'b0),
                .i_push        (gather_ex_path[ex_split_gen]),
                .o_push_ready  (ex_fifos_ready[ex_split_gen]),
                .i_push_data   (gather_inst[ex_split_gen]),
                .i_pop         (i_ex_wait_inst_get[ex_offset(ex_split_gen) +: STRUCT_RS_OUT_ENTRY[ex_split_gen]]),
                .o_pop_valid   (o_ex_wait_inst_valid[ex_offset(ex_split_gen) +: STRUCT_RS_OUT_ENTRY[ex_split_gen]]),
                .o_pop_data    (o_ex_wait_inst_data[(ex_offset(ex_split_gen)*_BITWIDTH_EX_INST_WIDTH) 
                                                     +: (STRUCT_RS_OUT_ENTRY[ex_split_gen]*_BITWIDTH_EX_INST_WIDTH)])
            );
        end

    endgenerate

    always_comb begin
        ex_fifo_ready = {STRUCT_EX_PATH{1'b1}};

        for (ex_fifo_ready_idx = 0; ex_fifo_ready_idx < STRUCT_EX_PATH; ex_fifo_ready_idx = ex_fifo_ready_idx+1) begin
            if ( (&ex_fifos_ready[ex_fifo_ready_idx]) && (&ex_fifo_ready) ) ex_fifo_ready[ex_fifo_ready_idx] = 1'b1;
            else ex_fifo_ready[ex_fifo_ready_idx] = 1'b0;
        end

        o_ist_ready_inst_get = {INPUT_CHANNEL{&ex_fifo_ready}};
    end

endmodule
