module eulsukdo_scheduler #(
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
    localparam int _BITWIDTH_STRUCT_PHYREGS             = $clog2(STRUCT_PHYREGS),
    localparam int _BITWIDTH_STRUCT_EX_PATH             = $clog2(STRUCT_EX_PATH),
    localparam int _BITWIDTH_STRUCT_FLOW_WINDOWS        = $clog2(STRUCT_FLOW_WINDOWS),
    localparam int _BITWIDTH_INTERNAL_INST_WIDTH        = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
                                                         + EX_INST_MICROOP_BITWIDTH
                                                         + IS_INST_IMM
                                                         + _BITWIDTH_STRUCT_PHYREGS // rd
                                                         + (_BITWIDTH_STRUCT_PHYREGS * IS_INST_OPERANDS) // rs1..n
                                                         + IS_INST_OPERANDS, // Ready1..n
    localparam int _BITWIDTH_EX_INST_WIDTH              = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
                                                         + EX_INST_MICROOP_BITWIDTH
                                                         + IS_INST_IMM
                                                         + _BITWIDTH_STRUCT_PHYREGS // rd
                                                         + (_BITWIDTH_STRUCT_PHYREGS * IS_INST_OPERANDS), // rs1..n
    localparam int _BITWIDTH_EX_RESULT_WIDTH            = BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
                                                         + _BITWIDTH_STRUCT_PHYREGS, // rd
    localparam int _BITWIDTH_STRUCT_RETIRED_PHYREG_MSG  = BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
                                                         + _BITWIDTH_STRUCT_PHYREGS, // Retired Register
    localparam int _BITWIDTH_STRUCT_JUMP_BRANCH_INFO    = 1 // Jump Register Flag
                                                         + 1 // Branch Flag
                                                         + IS_INST_PC_BITWIDTH // New Program Counter
) (
    input  wire                                                                clk,
    input  wire                                                                reset_n,

    // PC Request
    output wire [STRUCT_DECODE_NEW_INST-1:0]                                   o_im_req_pc_valid,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                   i_im_req_pc_get,
    output wire [(STRUCT_DECODE_NEW_INST * IS_INST_PC_BITWIDTH)-1:0]           o_im_req_pc,
    // Instruction Receive
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                   i_im_recv_pc_valid,
    output wire [STRUCT_DECODE_NEW_INST-1:0]                                   o_im_recv_pc_get,
    input  wire [(STRUCT_DECODE_NEW_INST * IS_INST_BITWIDTH)-1:0]              i_im_recv_pc,
    
    // Decoder Info Receive
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                   i_nel_decode_exception,
    input  wire [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_STRUCT_EX_PATH) )-1:0]    i_nel_decode_expath,
    input  wire [(STRUCT_DECODE_NEW_INST *(EX_INST_MICROOP_BITWIDTH) )-1:0]    i_nel_decode_microop,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                   i_nel_decode_rd,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                   i_nel_decode_newreg,
    input  wire [(STRUCT_DECODE_NEW_INST *(IS_INST_OPERANDS) )-1:0]            i_nel_decode_rs,
    input  wire [(STRUCT_DECODE_NEW_INST *(IS_INST_IMM) )-1:0]                 i_nel_decode_imm,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                   i_nel_decode_jump,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                   i_nel_decode_jump_reg,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                   i_nel_decode_branch,
    
    // EX Inst Push (RS Out)
    output wire [STRUCT_EX_CORES-1:0]                                          o_rs_entry_valid,
    input  wire [STRUCT_EX_CORES-1:0]                                          i_rs_entry_get,
    output wire [(STRUCT_EX_CORES *(_BITWIDTH_EX_INST_WIDTH) )-1:0]            o_rs_entry_data,

    // EX Result Receive (EX Out)
    input  wire [STRUCT_EX_OUT_RESULT_SUM-1:0]                                 i_wbc_result_valid,
    input  wire [(STRUCT_EX_OUT_RESULT_SUM *(_BITWIDTH_EX_RESULT_WIDTH) )-1:0] i_wbc_result_data
);

// START ===[ INTERNAL WIRE AREA ]=== START //
    // IM -> NEL : Instruction Receive
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         im_nel_recv_pc_valid;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         im_nel_recv_pc_get;
    wire [(STRUCT_DECODE_NEW_INST * IS_INST_BITWIDTH)-1:0]                                    im_nel_recv_pc;

    // PRM -> NEL : Allocatable Physical Registers
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         prm_nel_phyreg_valid;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         prm_nel_phyreg_get;
    wire [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_STRUCT_PHYREGS) )-1:0]                          prm_nel_phyreg_data;

    // WBC -> NEL, PRM (Broadcast) : Done Physical Registers
    wire [STRUCT_EX_OUT_RESULT_SUM-1:0]                                                       wbc_broadcast_done_phyreg_valid;
    wire [(STRUCT_EX_OUT_RESULT_SUM *(_BITWIDTH_STRUCT_PHYREGS) )-1:0]                        wbc_broadcast_done_phyreg_data;

    // NEL -> IST : New Internal Instructions
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         nel_ist_new_inst_valid;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         nel_ist_new_inst_get;
    wire [(STRUCT_EX_CORES *(_BITWIDTH_INTERNAL_INST_WIDTH) )-1:0]                            nel_ist_new_inst_data;

    // NEL -> FCL : Retired Physical Registers
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         nel_fcl_retired_phyreg_valid;
    wire [(STRUCT_EX_CORES *(_BITWIDTH_STRUCT_RETIRED_PHYREG_MSG) )-1:0]                      nel_fcl_retired_phyreg_data;
    
    // NEL -> FCL : Jump/Branch Information
    wire                                                                                      nel_fcl_jumpbranch_valid;
    wire [_BITWIDTH_STRUCT_JUMP_BRANCH_INFO-1:0]                                              nel_fcl_jumpbranch_data;

    // PRM -> IST : Ready Phyreg/ISTmap pair
    wire [STRUCT_PRM_ENTRY_UPDATE-1:0]                                                        prm_ist_ready_phyreg_valid;
    wire [(STRUCT_PRM_ENTRY_UPDATE *(_BITWIDTH_STRUCT_PHYREGS) )-1:0]                         prm_ist_ready_phyreg_data;

    // IST -> RS : Executable (All phyreg in instruction are ready) Internal Instructions
    wire [(STRUCT_DECODE_NEW_INST+STRUCT_PRM_ENTRY_UPDATE)-1:0]                               ist_rs_ready_inst_valid;
    wire [(STRUCT_DECODE_NEW_INST+STRUCT_PRM_ENTRY_UPDATE)-1:0]                               ist_rs_ready_inst_get;
    wire [((STRUCT_DECODE_NEW_INST+STRUCT_PRM_ENTRY_UPDATE) *(_BITWIDTH_EX_INST_WIDTH) )-1:0] ist_rs_ready_inst_data;

    // IST -> PRM : Wait Phyreg/ISTmap pair
    wire [STRUCT_PRM_ENTRY_UPDATE-1:0]                                                        ist_prm_wait_phyreg_valid;
    wire [(STRUCT_PRM_ENTRY_UPDATE *(_BITWIDTH_STRUCT_PHYREGS) )-1:0]                         ist_prm_wait_phyreg_data;

    // RS -> EX : Wait EX Instructions
    wire [STRUCT_EX_CORES-1:0]                                                                rs_ex_wait_inst_valid;
    wire [STRUCT_EX_CORES-1:0]                                                                rs_ex_wait_inst_get;
    wire [(STRUCT_EX_CORES *(_BITWIDTH_EX_INST_WIDTH) )-1:0]                                  rs_ex_wait_inst_data;

    // EX -> WBC : Done EX Branch Result
    wire [STRUCT_EX_BRANCH-1:0] ex_wbc_result_branch_valid;
    wire [] ex_wbc_result_branch_data;
    
    // EX -> WBC : Done EX Phyreg Result
    wire [STRUCT_EX_OUT_RESULT_SUM-1:0] ex_wbc_result_phyreg_valid;
    wire [] ex_wbc_result_phyreg_data;
    
    // WBC -> FCL : Branch Result
    wire [STRUCT_EX_BRANCH-1:0] wbc_fcl_branch_valid;
    wire [] wbc_fcl_branch_data;
    
    // WBC -> FCL : Done PC
    wire [STRUCT_EX_OUT_RESULT_SUM-1:0] wbc_fcl_done_pc_valid;
    wire [] wbc_fcl_done_pc_data;
// END   ===[ INTERNAL WIRE AREA ]===   END //

// START ===[ INSTANCE AREA ]=== START //
    new_entry_logic #(
    ) U_NEW_ENTRY_LOGIC (
        .clk                            (clk),
        .reset_n                        (reset_n),

        // Instruction Input (IM)
        .i_im_recv_pc_valid             (im_nel_recv_pc_valid),
        .o_im_recv_pc_get               (im_nel_recv_pc_get),
        .i_im_recv_pc                   (im_nel_recv_pc),

        // Allocate Physical Registers Input (PRM)
        .i_prm_phyreg_valid             (prm_nel_phyreg_valid),
        .o_prm_phyreg_get               (prm_nel_phyreg_get),
        .i_prm_phyreg_data              (prm_nel_phyreg_data),

        // Done Physical Registers Input (WBC)
        .i_wbc_done_phyreg_valid        (wbc_broadcast_done_phyreg_valid),
        .i_wbc_done_phyreg_data         (wbc_broadcast_done_phyreg_data),

        // Create Internal Instruction Output (IST)
        .o_ist_new_inst_valid           (nel_ist_new_inst_valid),
        .i_ist_new_inst_get             (nel_ist_new_inst_get),
        .o_ist_new_inst_data            (nel_ist_new_inst_data),

        // Retired Physical Registers Output (FCL)
        .o_fcl_retired_phyreg_valid     (nel_fcl_retired_phyreg_valid),
        .o_fcl_retired_phyreg_data      (nel_fcl_retired_phyreg_data),

        // Jump/Branch Information Output (FCL)
        .o_fcl_jumpbranch_valid         (nel_fcl_jumpbranch_valid),
        .o_fcl_jumpbranch_data          (nel_fcl_jumpbranch_data)
    );

    instruction_state_table #(        
    ) U_INSTRUCTION_STATE_TABLE (
        .clk                            (clk),
        .reset_n                        (reset_n),

        // New Internal Instruction Input (NEL)
        .i_nel_new_inst_valid           (nel_ist_new_inst_valid),
        .o_nel_new_inst_get             (nel_ist_new_inst_get),
        .i_nel_new_inst_data            (nel_ist_new_inst_data),

        // Ready Physical Registers Input (PRM)
        .i_prm_ready_phyreg_valid       (prm_ist_ready_phyreg_valid), 
        .i_prm_ready_phyreg_data        (prm_ist_ready_phyreg_data), 
        
        // Executable (All phyreg in instruction are ready) Internal Instruction Output (RS)
        .o_rs_ready_inst_valid          (ist_rs_ready_inst_valid),
        .i_rs_ready_inst_get            (ist_rs_ready_inst_get),
        .o_rs_ready_inst_data           (ist_rs_ready_inst_data),

        // Wait Physical Registers Output (PRM)
        .o_prm_ready_phyreg_valid       (ist_prm_wait_phyreg_valid), 
        .o_prm_ready_phyreg_data        (ist_prm_wait_phyreg_data)
    );

    ready_station #(
    ) U_READY_STATION (
        .clk                            (clk),
        .reset_n                        (reset_n),

        // Executable (All phyreg in instruction are ready) Internal Instruction Input (IST)
        .i_ist_ready_inst_valid         (ist_rs_ready_inst_valid),
        .o_ist_ready_inst_get           (ist_rs_ready_inst_get),
        .i_ist_ready_inst_data          (ist_rs_ready_inst_data),

        // Wait EX Instruction Output (EX)
        .o_ex_wait_inst_valid           (rs_ex_wait_inst_valid),
        .i_ex_wait_inst_get             (rs_ex_wait_inst_get),
        .o_ex_wait_inst_data            (rs_ex_wait_inst_data),
    );

    write_back_concatenation #(
    ) U_WRITE_BACK_CONCATENATION (
        // Result branch EX Input (EX)
        .i_ex_result_branch_valid       (ex_wbc_result_branch_valid),
        .i_ex_result_branch_data        (ex_wbc_result_branch_data),

        // Result phyreg EX Input (EX)
        .i_ex_result_phyreg_valid       (ex_wbc_result_phyreg_valid),
        .i_ex_result_phyreg_data        (ex_wbc_result_phyreg_data),

        // Branch Result Output (FCL)
        .o_fcl_branch_valid             (wbc_fcl_branch_valid),
        .o_fcl_branch_data              (wbc_fcl_branch_data),

        // Done PC Output (FCL)
        .o_fcl_done_pc_valid            (wbc_fcl_done_pc_valid),
        .o_fcl_done_pc_data             (wbc_fcl_done_pc_data),

        // Broadcast Done phyreg Output (NEL, PRM)
        .o_broadcast_done_phyreg_valid  (wbc_broadcast_done_phyreg_valid),
        .o_broadcast_done_phyreg_data   (wbc_broadcast_done_phyreg_data),
    );
// END   ===[ INSTANCE AREA ]===   END //

// START ===[ INPUT, OUTPUT AREA ]=== START //
// END   ===[ INPUT, OUTPUT AREA ]===   END //

endmodule
