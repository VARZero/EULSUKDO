`timescale 1ns/1ps
module write_back_concatenation #() (
    // Result branch EX Input (EX) 
    input  wire [STRUCT_EX_BRANCH-1:0]                                           i_ex_result_branch_valid,
    input  wire [(STRUCT_EX_BRANCH *(_BITWIDTH_STRUCT_JUMP_BRANCH_INFO) )-1:0]   i_ex_result_branch_data,

    // Result phyreg EX Input (EX)
    input  wire [STRUCT_EX_OUT_RESULT_SUM-1:0]                                   i_ex_result_phyreg_valid,
    input  wire [(STRUCT_EX_OUT_RESULT_SUM *(_BITWIDTH_STRUCT_PHYREGS) )-1:0]    i_ex_result_phyreg_data,

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

endmodule
