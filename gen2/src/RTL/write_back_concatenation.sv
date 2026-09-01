`timescale 1ns/1ps
module write_back_concatenation #(
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
    // Result branch EX Input (EX) 
    input  wire [STRUCT_EX_BRANCH-1:0]                                           i_ex_result_branch_valid,
    input  wire [(STRUCT_EX_BRANCH *(_BITWIDTH_STRUCT_JUMP_BRANCH_INFO) )-1:0]   i_ex_result_branch_data,

    // Result EX Input (EX)
    input  wire [STRUCT_EX_OUT_RESULT_SUM-1:0]                                   i_ex_result_valid,
    input  wire [(STRUCT_EX_OUT_RESULT_SUM *(_BITWIDTH_EX_RESULT_WIDTH) )-1:0]   i_ex_result_data,

    // Branch Result Output (FCL)
    output wire [STRUCT_EX_BRANCH-1:0]                                           o_fcl_branch_valid,
    output wire [(STRUCT_EX_BRANCH *(_BITWIDTH_STRUCT_JUMP_BRANCH_INFO) )-1:0]   o_fcl_branch_data,
    
    // Done PC Output (FCL)
    output wire [STRUCT_EX_OUT_RESULT_SUM-1:0]                                   o_fcl_done_pc_valid,
    output wire [(STRUCT_EX_OUT_RESULT_SUM *(_BITWIDTH_STRUCT_EX_DONE_PC) )-1:0] o_fcl_done_pc_data,

    // Broadcast Done phyreg Output (NEL, PRM)
    output wire [STRUCT_EX_OUT_RESULT_SUM-1:0]                                   o_broadcast_done_phyreg_valid,
    output wire [(STRUCT_EX_OUT_RESULT_SUM *(_BITWIDTH_STRUCT_PHYREGS) )-1:0]    o_broadcast_done_phyreg_data
);

    // Branch Section
    assign o_fcl_branch_valid = i_ex_result_branch_valid;
    assign o_fcl_branch_data  = i_ex_result_branch_data;

    genvar ex_core_num;
    generate
        for (ex_core_num = 0; ex_core_num < STRUCT_EX_OUT_RESULT_SUM; ex_core_num = ex_core_num + 1) begin
            // Done PCs
            assign o_fcl_done_pc_valid[ex_core_num] = i_ex_result_valid[ex_core_num];
            assign o_fcl_done_pc_data [( _BITWIDTH_STRUCT_EX_DONE_PC *ex_core_num ) +: _BITWIDTH_STRUCT_EX_DONE_PC] 
                        = i_ex_result_data[( _BITWIDTH_EX_RESULT_WIDTH *ex_core_num ) +: _BITWIDTH_STRUCT_EX_DONE_PC];

            // Done PHYREGs
            assign o_broadcast_done_phyreg_valid[ex_core_num] = i_ex_result_valid[ex_core_num];
            assign o_broadcast_done_phyreg_data [( _BITWIDTH_STRUCT_PHYREGS *ex_core_num ) +: _BITWIDTH_STRUCT_PHYREGS] 
                        = i_ex_result_data[ (( _BITWIDTH_EX_RESULT_WIDTH *ex_core_num ) + _BITWIDTH_STRUCT_EX_DONE_PC ) 
                                            +: _BITWIDTH_STRUCT_PHYREGS];
        end
    endgenerate

endmodule
