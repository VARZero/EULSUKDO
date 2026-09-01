`timescale 1ns/1ps
module flow_control_logic #(
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
    input  wire                                                                  clk,
    input  wire                                                                  reset_n,
        
    // Done PC Input (WBC)
    input  wire [STRUCT_EX_OUT_RESULT_SUM-1:0]                                   i_wbc_done_pc_valid,
    input  wire [(STRUCT_EX_OUT_RESULT_SUM *(_BITWIDTH_STRUCT_EX_DONE_PC) )-1:0] i_wbc_done_pc_data,
        
    // Jump/Branch Information Input (NEL)
    input  wire                                                                  i_nel_jumpbranch_valid,
    input  wire [_BITWIDTH_STRUCT_JUMP_BRANCH_INFO-1:0]                          i_nel_jumpbranch_data,

    // Retired Physical Registers Input (NEL)
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                     i_nel_retired_phyreg_valid,
    input  wire [(STRUCT_EX_CORES *(_BITWIDTH_STRUCT_RETIRED_PHYREG_MSG) )-1:0]  i_nel_retired_phyreg_data,

    // Request New Instruction Output (IM)
    output wire [STRUCT_DECODE_NEW_INST-1:0]                                     o_im_req_pc_valid,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                     i_im_req_pc_get,
    output wire [(STRUCT_DECODE_NEW_INST *(IS_INST_PC_BITWIDTH) )-1:0]           o_im_req_pc,

    // Unallocate Retired Registers Output (PRM)
    output wire [STRUCT_UNALLOCATE_PHYREG-1:0]                                   o_prm_unallocate_phyreg_valid,
    output wire [(STRUCT_UNALLOCATE_PHYREG *(_BITWIDTH_STRUCT_PHYREGS) )-1:0]    o_prm_unallocate_phyreg_data
);

endmodule