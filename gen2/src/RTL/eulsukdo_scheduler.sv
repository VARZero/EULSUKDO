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
                                                         + IS_INST_PC_BITWIDTH, // New Program Counter
    localparam int _BITWIDTH_STRUCT_EX_DONE_PC          = BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
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
    wire [STRUCT_EX_BRANCH-1:0]                                                               ex_wbc_result_branch_valid;
    wire [(STRUCT_EX_BRANCH *(_BITWIDTH_STRUCT_JUMP_BRANCH_INFO) )-1:0]                       ex_wbc_result_branch_data;
    
    // EX -> WBC : Done EX Phyreg Result
    wire [STRUCT_EX_OUT_RESULT_SUM-1:0]                                                       ex_wbc_result_phyreg_valid;
    wire [(STRUCT_EX_OUT_RESULT_SUM *(_BITWIDTH_STRUCT_PHYREGS) )-1:0]                        ex_wbc_result_phyreg_data;
    
    // WBC -> FCL : Branch Result
    wire [STRUCT_EX_BRANCH-1:0]                                                               wbc_fcl_branch_valid;
    wire [(STRUCT_EX_BRANCH *(_BITWIDTH_STRUCT_JUMP_BRANCH_INFO) )-1:0]                       wbc_fcl_branch_data;
    
    // WBC -> FCL : Done PC
    wire [STRUCT_EX_OUT_RESULT_SUM-1:0]                                                       wbc_fcl_done_pc_valid;
    wire [(STRUCT_EX_OUT_RESULT_SUM *(_BITWIDTH_STRUCT_EX_DONE_PC) )-1:0]                     wbc_fcl_done_pc_data;

    // FCL -> IM : New PC Request
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         fcl_im_req_pc_valid;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         fcl_im_req_pc_get;
    wire [(STRUCT_DECODE_NEW_INST *(IS_INST_PC_BITWIDTH) )-1:0]                               fcl_im_req_pc;

    // FCL -> PRM : Unallocate Retired Registers
    wire [STRUCT_UNALLOCATE_PHYREG-1:0]                                                       fcl_prm_unallocate_phyreg_valid;
    wire [(STRUCT_UNALLOCATE_PHYREG *(_BITWIDTH_STRUCT_PHYREGS) )-1:0]                        fcl_prm_unallocate_phyreg_data;

    // DECODER -> NEL : ISA Infomation
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         dec_nel_decode_exception;
    wire [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_STRUCT_EX_PATH) )-1:0]                          dec_nel_decode_expath;
    wire [(STRUCT_DECODE_NEW_INST *(EX_INST_MICROOP_BITWIDTH) )-1:0]                          dec_nel_decode_microop;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         dec_nel_decode_rd;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         dec_nel_decode_newreg;
    wire [(STRUCT_DECODE_NEW_INST *(IS_INST_OPERANDS) )-1:0]                                  dec_nel_decode_rs;
    wire [(STRUCT_DECODE_NEW_INST *(IS_INST_IMM) )-1:0]                                       dec_nel_decode_imm;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         dec_nel_decode_jump;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         dec_nel_decode_jump_reg;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         dec_nel_decode_branch;

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

        // Decoder Input (Decoder)
        .i_dec_decode_exception         (dec_nel_decode_exception),
        .i_dec_decode_expath            (dec_nel_decode_expath),
        .i_dec_decode_microop           (dec_nel_decode_microop),
        .i_dec_decode_rd                (dec_nel_decode_rd),
        .i_dec_decode_newreg            (dec_nel_decode_newreg),
        .i_dec_decode_rs                (dec_nel_decode_rs),
        .i_dec_decode_imm               (dec_nel_decode_imm),
        .i_dec_decode_jump              (dec_nel_decode_jump),
        .i_dec_decode_jump_reg          (dec_nel_decode_jump_reg),
        .i_dec_decode_branch            (dec_nel_decode_branch),

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

    flow_control_logic #(
    ) U_FLOW_CONTROL_LOGIC (
        .clk                            (clk),
        .reset_n                        (reset_n),
        
        // Done PC Input (WBC)
        .i_wbc_done_pc_valid            (wbc_fcl_done_pc_valid),
        .i_wbc_done_pc_data             (wbc_fcl_done_pc_data),
        
        // Jump/Branch Information Input (NEL)
        .i_nel_jumpbranch_valid         (nel_fcl_jumpbranch_valid),
        .i_nel_jumpbranch_data          (nel_fcl_jumpbranch_data),

        // Retired Physical Registers Input (NEL)
        .i_nel_retired_phyreg_valid     (nel_fcl_retired_phyreg_valid),
        .i_nel_retired_phyreg_data      (nel_fcl_retired_phyreg_data),

        // Request New Instruction Output (IM)
        .o_im_req_pc_valid              (fcl_im_req_pc_valid),
        .i_im_req_pc_get                (fcl_im_req_pc_get),
        .o_im_req_pc                    (fcl_im_req_pc),

        // Unallocate Retired Registers Output (PRM)
        .o_prm_unallocate_phyreg_valid  (fcl_prm_unallocate_phyreg_valid),
        .o_prm_unallocate_phyreg_data   (fcl_prm_unallocate_phyreg_data)
    );

// END   ===[ INSTANCE AREA ]===   END //

// START ===[ INPUT, OUTPUT AREA ]=== START //
    // PC Request Output
    assign o_im_req_pc_valid          = fcl_im_req_pc_valid;
    assign fcl_im_req_pc_get          = i_im_req_pc_get;
    assign o_im_req_pc                = fcl_im_req_pc;

    // Instruction Receive Input
    assign im_nel_recv_pc_valid       = i_im_recv_pc_valid;
    assign o_im_recv_pc_get           = im_nel_recv_pc_get;
    assign im_nel_recv_pc             = i_im_recv_pc;

    // Decoder Info Receive
    assign dec_nel_decode_exception   = i_nel_decode_exception;
    assign dec_nel_decode_expath      = i_nel_decode_expath;
    assign dec_nel_decode_microop     = i_nel_decode_microop;
    assign dec_nel_decode_rd          = i_nel_decode_rd;
    assign dec_nel_decode_newreg      = i_nel_decode_newreg;
    assign dec_nel_decode_rs          = i_nel_decode_rs;
    assign dec_nel_decode_imm         = i_nel_decode_imm;
    assign dec_nel_decode_jump        = i_nel_decode_jump;
    assign dec_nel_decode_jump_reg    = i_nel_decode_jump_reg;
    assign dec_nel_decode_branch      = i_nel_decode_branch;

    // EX Inst Push (RS Out)
    assign o_rs_entry_valid           = rs_ex_wait_inst_valid;
    assign rs_ex_wait_inst_get        = i_rs_entry_get;
    assign o_rs_entry_data            = rs_ex_wait_inst_data;

    // EX Result Receive (EX Out)
    assign ex_wbc_result_phyreg_valid = i_wbc_result_valid;
    assign ex_wbc_result_phyreg_data  = i_wbc_result_data;

// END   ===[ INPUT, OUTPUT AREA ]===   END //

endmodule
