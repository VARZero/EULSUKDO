`timescale 1ns/1ps
module new_entry_logic #(
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
    localparam int _BITWIDTH_STRUCT_JUMP_BRANCH_INFO    = 1 // Jump Flag
                                                         + 1 // Jump Register Flag
                                                         + 1 // Branch Flag
                                                         + IS_INST_PC_BITWIDTH, // New Program Counter
    localparam int _BITWIDTH_STRUCT_EX_DONE_PC          = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
) (
    input  logic                                                                              clk,
    input  logic                                                                              reset_n,

    // Instruction Input (IM)
    input  logic [STRUCT_DECODE_NEW_INST-1:0]                                                 i_im_recv_inst_valid,
    output logic [STRUCT_DECODE_NEW_INST-1:0]                                                 o_im_recv_inst_get,
    input  logic [(STRUCT_DECODE_NEW_INST * _BITWIDTH_FLOW_WINDOWS_PC)-1:0]                   i_im_recv_pc,

    // FCL tracks every consumed IM response, including discarded branch tails.
    input  logic                                                                              i_fcl_discard,
    output logic [STRUCT_DECODE_NEW_INST-1:0]                                                 o_fcl_recv_valid,
    output logic [STRUCT_DECODE_NEW_INST-1:0]                                                 o_fcl_recv_keep,
    output logic                                                                              o_fcl_recv_control,
    output logic [STRUCT_DECODE_NEW_INST-1:0]                                                 o_fcl_new_inst_valid,
    output logic [(STRUCT_DECODE_NEW_INST*_BITWIDTH_FLOW_WINDOWS_PC)-1:0]                    o_fcl_new_inst_pc,

    // Allocate Physical Registers Input (PRM)
    input  logic [STRUCT_DECODE_NEW_INST-1:0]                                                 i_prm_phyreg_valid,
    output logic [STRUCT_DECODE_NEW_INST-1:0]                                                 o_prm_phyreg_get,
    input  logic [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_STRUCT_PHYREGS) )-1:0]                  i_prm_phyreg_data,

    // Done Physical Registers Input (WBC)
    input  logic [STRUCT_EX_OUT_RESULT_SUM-1:0]                                               i_wbc_done_phyreg_valid,
    input  logic [(STRUCT_EX_OUT_RESULT_SUM *(_BITWIDTH_STRUCT_PHYREGS) )-1:0]                i_wbc_done_phyreg_data,

    // Decoder Input (Decoder)
    input  logic [STRUCT_DECODE_NEW_INST-1:0]                                                 i_dec_decode_exception,
    input  logic [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_STRUCT_EX_PATH) )-1:0]                  i_dec_decode_expath,
    input  logic [(STRUCT_DECODE_NEW_INST *(EX_INST_MICROOP_BITWIDTH) )-1:0]                  i_dec_decode_microop,
    input  logic [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_IS_INST_REGS) )-1:0]                    i_dec_decode_rd,
    input  logic [STRUCT_DECODE_NEW_INST-1:0]                                                 i_dec_decode_newreg,
    input  logic [((STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS) *(_BITWIDTH_IS_INST_REGS) )-1:0] i_dec_decode_rs,
    input  logic [(STRUCT_DECODE_NEW_INST *(IS_INST_IMM) )-1:0]                               i_dec_decode_imm,
    input  logic [STRUCT_DECODE_NEW_INST-1:0]                                                 i_dec_decode_jump,
    input  logic [STRUCT_DECODE_NEW_INST-1:0]                                                 i_dec_decode_jump_reg,
    input  logic [STRUCT_DECODE_NEW_INST-1:0]                                                 i_dec_decode_branch,

    // Create Internal Instruction Output (IST)
    output logic [STRUCT_DECODE_NEW_INST-1:0]                                                 o_ist_new_inst_valid,
    input  logic [STRUCT_DECODE_NEW_INST-1:0]                                                 i_ist_new_inst_get,
    output logic [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_INTERNAL_INST_WIDTH) )-1:0]             o_ist_new_inst_data,

    // Retired Physical Registers Output (FCL)
    output logic [STRUCT_DECODE_NEW_INST-1:0]                                                 o_fcl_retired_phyreg_valid,
    output logic [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_STRUCT_RETIRED_PHYREG_MSG) )-1:0]       o_fcl_retired_phyreg_data,

    // Jump/Branch Information Output (FCL)
    output logic                                                                              o_fcl_jumpbranch_valid,
    output logic [_BITWIDTH_STRUCT_JUMP_BRANCH_INFO-1:0]                                      o_fcl_jumpbranch_data,
    output logic [_BITWIDTH_FLOW_WINDOWS_PC-1:0]                                             o_fcl_jumpbranch_pc
);
    // LSB [ valid, expath, pc, microop, rd, newreg, rs, imm, jump, jump_reg, branch ] MSB
    localparam int BITWIDTH_NEL_STAGE1 = 1                                           // Valid
                                        +_BITWIDTH_STRUCT_EX_PATH                    // Expath
                                        +_BITWIDTH_FLOW_WINDOWS_PC                   // PC
                                        +EX_INST_MICROOP_BITWIDTH                    // MicroOP
                                        +_BITWIDTH_IS_INST_REGS                      // Rd
                                        +1                                           // NewReg
                                        +(_BITWIDTH_IS_INST_REGS*IS_INST_OPERANDS) // Rs
                                        +IS_INST_IMM                                 // IMM
                                        +1 +1 +1;                                    // Jump, Jump Reg, Branch
    
    localparam int STARTPOINT_1EXPATH  = 1;
    localparam int STARTPOINT_1PC      = STARTPOINT_1EXPATH+_BITWIDTH_STRUCT_EX_PATH;
    localparam int STARTPOINT_1MICROOP = STARTPOINT_1PC+_BITWIDTH_FLOW_WINDOWS_PC;
    localparam int STARTPOINT_1RD      = STARTPOINT_1MICROOP+EX_INST_MICROOP_BITWIDTH;
    localparam int STARTPOINT_1NEWREG  = STARTPOINT_1RD+_BITWIDTH_IS_INST_REGS;
    localparam int STARTPOINT_1RS      = STARTPOINT_1NEWREG+1;
    localparam int STARTPOINT_1IMM     = STARTPOINT_1RS+(_BITWIDTH_IS_INST_REGS*IS_INST_OPERANDS);
    localparam int STARTPOINT_1JUMP    = STARTPOINT_1IMM+IS_INST_IMM;
    localparam int STARTPOINT_1JUMPREG = STARTPOINT_1JUMP+1;
    localparam int STARTPOINT_1BRANCH  = STARTPOINT_1JUMPREG+1;
    
    // LSB [ valid, expath, pc, microop, P_Rd, newreg, P_Rs, imm, jump, jump_reg, branch ] MSB
    localparam int BITWIDTH_NEL_STAGE2 = 1                                           // Valid
                                        +_BITWIDTH_STRUCT_EX_PATH                    // Expath
                                        +_BITWIDTH_FLOW_WINDOWS_PC                   // PC
                                        +EX_INST_MICROOP_BITWIDTH                    // MicroOP
                                        +_BITWIDTH_STRUCT_PHYREGS                      // P_Rd
                                        +1                                           // NewReg
                                        +(_BITWIDTH_STRUCT_PHYREGS*IS_INST_OPERANDS) // P_Rs
                                        +IS_INST_IMM                                 // IMM
                                        +1 +1 +1;                                    // Jump, Jump Reg, Branch

    localparam int STARTPOINT_2EXPATH  = 1;
    localparam int STARTPOINT_2PC      = STARTPOINT_2EXPATH+_BITWIDTH_STRUCT_EX_PATH;
    localparam int STARTPOINT_2MICROOP = STARTPOINT_2PC+_BITWIDTH_FLOW_WINDOWS_PC;
    localparam int STARTPOINT_2PRD     = STARTPOINT_2MICROOP+EX_INST_MICROOP_BITWIDTH;
    localparam int STARTPOINT_2NEWREG  = STARTPOINT_2PRD+_BITWIDTH_STRUCT_PHYREGS;
    localparam int STARTPOINT_2PRS     = STARTPOINT_2NEWREG+1;
    localparam int STARTPOINT_2IMM     = STARTPOINT_2PRS+(_BITWIDTH_STRUCT_PHYREGS*IS_INST_OPERANDS);
    localparam int STARTPOINT_2JUMP    = STARTPOINT_2IMM+IS_INST_IMM;
    localparam int STARTPOINT_2JUMPREG = STARTPOINT_2JUMP+1;
    localparam int STARTPOINT_2BRANCH  = STARTPOINT_2JUMPREG+1;

    logic [(BITWIDTH_NEL_STAGE1*STRUCT_DECODE_NEW_INST)-1:0] stage1, stage1_next;
    logic [(BITWIDTH_NEL_STAGE2*STRUCT_DECODE_NEW_INST)-1:0] stage2, stage2_next;

    integer idx_input, idx_stage1, idx_stage2_0, idx_stage2_1, idx_stage2_2;

    always_ff @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            stage1 <= 0;
            stage2 <= 0;
        end
        else begin
            stage1 <= stage1_next;
            stage2 <= stage2_next;
        end
    end

    logic [_BITWIDTH_FLOW_WINDOWS_PC-1:0] input_pc_list            [0:STRUCT_DECODE_NEW_INST-1];

    logic                                 input_dec_exception_list [0:STRUCT_DECODE_NEW_INST-1];
    logic [_BITWIDTH_STRUCT_EX_PATH-1:0]  input_dec_expath_list    [0:STRUCT_DECODE_NEW_INST-1];
    logic [EX_INST_MICROOP_BITWIDTH-1:0]  input_dec_microop_list   [0:STRUCT_DECODE_NEW_INST-1];
    logic [_BITWIDTH_IS_INST_REGS-1:0]    input_dec_rd_list        [0:STRUCT_DECODE_NEW_INST-1];
    logic                                 input_dec_newreg_list    [0:STRUCT_DECODE_NEW_INST-1];
    logic [(_BITWIDTH_IS_INST_REGS*IS_INST_OPERANDS)-1:0]    
                                          input_dec_rs_list        [0:STRUCT_DECODE_NEW_INST-1];
    logic [IS_INST_IMM-1:0]               input_dec_imm_list       [0:STRUCT_DECODE_NEW_INST-1];
    logic                                 input_dec_jump_list      [0:STRUCT_DECODE_NEW_INST-1];
    logic                                 input_dec_jump_reg_list  [0:STRUCT_DECODE_NEW_INST-1];
    logic                                 input_dec_branch_list    [0:STRUCT_DECODE_NEW_INST-1];

    logic [_BITWIDTH_STRUCT_PHYREGS-1:0]  input_wbc_done_phyreg    [0:STRUCT_EX_OUT_RESULT_SUM-1];

    logic                                 input_jump_branch;
    
    logic                                 s1out_valid_list         [0:STRUCT_DECODE_NEW_INST-1];
    logic [_BITWIDTH_STRUCT_EX_PATH-1:0]  s1out_dec_expath_list    [0:STRUCT_DECODE_NEW_INST-1];
    logic [_BITWIDTH_FLOW_WINDOWS_PC-1:0] s1out_pc_list            [0:STRUCT_DECODE_NEW_INST-1];
    logic [EX_INST_MICROOP_BITWIDTH-1:0]  s1out_dec_microop_list   [0:STRUCT_DECODE_NEW_INST-1];
    logic [_BITWIDTH_IS_INST_REGS-1:0]    s1out_dec_rd_list        [0:STRUCT_DECODE_NEW_INST-1];
    logic                                 s1out_dec_newreg_list    [0:STRUCT_DECODE_NEW_INST-1];
    logic [(_BITWIDTH_IS_INST_REGS*IS_INST_OPERANDS)-1:0]    
                                          s1out_dec_rs_list        [0:STRUCT_DECODE_NEW_INST-1];
    logic [IS_INST_IMM-1:0]               s1out_dec_imm_list       [0:STRUCT_DECODE_NEW_INST-1];
    logic                                 s1out_dec_jump_list      [0:STRUCT_DECODE_NEW_INST-1];
    logic                                 s1out_dec_jump_reg_list  [0:STRUCT_DECODE_NEW_INST-1];
    logic                                 s1out_dec_branch_list    [0:STRUCT_DECODE_NEW_INST-1];

    logic [(_BITWIDTH_IS_INST_REGS*STRUCT_DECODE_NEW_INST)-1:0]
                                          s1out_rd_all;
    logic [(_BITWIDTH_IS_INST_REGS*IS_INST_OPERANDS*STRUCT_DECODE_NEW_INST)-1:0]
                                          s1out_rs_all;
    logic [(_BITWIDTH_STRUCT_PHYREGS*STRUCT_DECODE_NEW_INST)-1:0]
                                          prd_mapping_all;
    logic [(_BITWIDTH_STRUCT_PHYREGS*IS_INST_OPERANDS*STRUCT_DECODE_NEW_INST)-1:0]
                                          prs_mapping_all, prs_result_all;
    logic [STRUCT_DECODE_NEW_INST-1:0]    s1out_valid_all, s1out_newreg_all, real_newreg;
    logic [STRUCT_DECODE_NEW_INST-1:0]    stage1_alloc_req, stage1_alloc_fire;
    logic                                 stage1_to_stage2, stage1_accept_enable;
    logic                                 stage2_to_ist, stage2_can_accept;
    logic                                 stage1_has_control, control_found;
    logic [_BITWIDTH_STRUCT_PHYREGS-1:0] retired_phyreg            [0:STRUCT_DECODE_NEW_INST-1];
    logic [IS_INST_PC_BITWIDTH-1:0]      control_new_pc;

    logic                                 s2in_valid_list          [0:STRUCT_DECODE_NEW_INST-1];
    logic [_BITWIDTH_STRUCT_EX_PATH-1:0]  s2in_expath_list         [0:STRUCT_DECODE_NEW_INST-1];
    logic [_BITWIDTH_FLOW_WINDOWS_PC-1:0] s2in_pc_list             [0:STRUCT_DECODE_NEW_INST-1];
    logic [EX_INST_MICROOP_BITWIDTH-1:0]  s2in_microop_list        [0:STRUCT_DECODE_NEW_INST-1];
    logic [_BITWIDTH_STRUCT_PHYREGS-1:0]  s2in_prd_list            [0:STRUCT_DECODE_NEW_INST-1];
    logic                                 s2in_newreg_list         [0:STRUCT_DECODE_NEW_INST-1];
    logic [(_BITWIDTH_STRUCT_PHYREGS*IS_INST_OPERANDS)-1:0]    
                                          s2in_prs_list            [0:STRUCT_DECODE_NEW_INST-1];
    logic [IS_INST_IMM-1:0]               s2in_imm_list            [0:STRUCT_DECODE_NEW_INST-1];
    logic                                 s2in_jump_list           [0:STRUCT_DECODE_NEW_INST-1];
    logic                                 s2in_jump_reg_list       [0:STRUCT_DECODE_NEW_INST-1];
    logic                                 s2in_branch_list         [0:STRUCT_DECODE_NEW_INST-1];
    
    logic [(_BITWIDTH_STRUCT_PHYREGS*STRUCT_DECODE_NEW_INST)-1:0]    
                                          s2in_prd_all;
    logic [STRUCT_DECODE_NEW_INST-1:0]    s2in_newreg_all;

    logic                                 s2out_valid_list         [0:STRUCT_DECODE_NEW_INST-1];
    logic [_BITWIDTH_STRUCT_EX_PATH-1:0]  s2out_expath_list        [0:STRUCT_DECODE_NEW_INST-1];
    logic [_BITWIDTH_FLOW_WINDOWS_PC-1:0] s2out_pc_list            [0:STRUCT_DECODE_NEW_INST-1];
    logic [EX_INST_MICROOP_BITWIDTH-1:0]  s2out_microop_list       [0:STRUCT_DECODE_NEW_INST-1];
    logic [_BITWIDTH_STRUCT_PHYREGS-1:0]  s2out_prd_list           [0:STRUCT_DECODE_NEW_INST-1];
    logic                                 s2out_newreg_list        [0:STRUCT_DECODE_NEW_INST-1];
    logic [(_BITWIDTH_STRUCT_PHYREGS*IS_INST_OPERANDS)-1:0]    
                                          s2out_prs_list           [0:STRUCT_DECODE_NEW_INST-1];
    logic [IS_INST_IMM-1:0]               s2out_imm_list           [0:STRUCT_DECODE_NEW_INST-1];
    logic                                 s2out_jump_list          [0:STRUCT_DECODE_NEW_INST-1];
    logic                                 s2out_jump_reg_list      [0:STRUCT_DECODE_NEW_INST-1];
    logic                                 s2out_branch_list        [0:STRUCT_DECODE_NEW_INST-1];
    
    logic [(_BITWIDTH_STRUCT_PHYREGS*STRUCT_DECODE_NEW_INST)-1:0]    
                                          s2out_prd_all;
    logic [(_BITWIDTH_STRUCT_PHYREGS*STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS)-1:0]    
                                          s2out_prs_all;
    logic [STRUCT_DECODE_NEW_INST-1:0]    s2out_valid_all, s2out_newreg_all;
    
    logic [(STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS)-1:0]
                                          ready_table_out;
    logic [IS_INST_OPERANDS-1:0]          last_ready               [0:STRUCT_DECODE_NEW_INST-1];

    logic [_BITWIDTH_IS_INST_REGS-1:0]    ref_reg, comp_reg;
    logic [_BITWIDTH_STRUCT_PHYREGS-1:0]  ref_preg;
    logic [STRUCT_DECODE_NEW_INST-1:0]    reg_dest_map_suffix      [0:STRUCT_DECODE_NEW_INST-1];
    logic [STRUCT_DECODE_NEW_INST-1:0]    reg_src_map_suffix       [0:(STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS)-1];

    always_comb begin
        stage1_next = stage1;
        stage2_next = stage2;
        o_im_recv_inst_get = 0;
        o_prm_phyreg_get = 0;
        o_ist_new_inst_valid = 0;
        o_ist_new_inst_data = 0;
        o_fcl_retired_phyreg_valid = 0;
        o_fcl_retired_phyreg_data = 0;
        o_fcl_jumpbranch_valid = 1'b0;
        o_fcl_jumpbranch_data = 0;
        o_fcl_jumpbranch_pc = 0;
        o_fcl_recv_valid = 0;
        o_fcl_recv_keep = 0;
        o_fcl_recv_control = 1'b0;
        o_fcl_new_inst_valid = 0;
        o_fcl_new_inst_pc = 0;
        ref_reg = 0;
        comp_reg = 0;
        ref_preg = 0;

        // Split Inputs "STRUCT_DECODE_NEW_INST"
        for (idx_input = 0; idx_input < STRUCT_DECODE_NEW_INST; idx_input = idx_input+1) begin
            input_pc_list    [idx_input] = 
                i_im_recv_pc[(_BITWIDTH_FLOW_WINDOWS_PC*idx_input) +: _BITWIDTH_FLOW_WINDOWS_PC];

            input_dec_exception_list[idx_input] = 
                i_dec_decode_exception[idx_input];
            input_dec_expath_list   [idx_input] = 
                i_dec_decode_expath   [(_BITWIDTH_STRUCT_EX_PATH*idx_input) +: _BITWIDTH_STRUCT_EX_PATH];
            input_dec_microop_list  [idx_input] = 
                i_dec_decode_microop  [(EX_INST_MICROOP_BITWIDTH*idx_input) +: EX_INST_MICROOP_BITWIDTH];
            input_dec_rd_list       [idx_input] = 
                i_dec_decode_rd       [(_BITWIDTH_IS_INST_REGS*idx_input) +: _BITWIDTH_IS_INST_REGS];
            input_dec_newreg_list   [idx_input] = 
                i_dec_decode_newreg   [idx_input];
            input_dec_rs_list       [idx_input] = 
                i_dec_decode_rs       [((_BITWIDTH_IS_INST_REGS*IS_INST_OPERANDS)*idx_input) +: (_BITWIDTH_IS_INST_REGS*IS_INST_OPERANDS)];
            input_dec_imm_list      [idx_input] = 
                i_dec_decode_imm      [(IS_INST_IMM*idx_input) +: IS_INST_IMM];
            input_dec_jump_list     [idx_input] = 
                i_dec_decode_jump     [idx_input];
            input_dec_jump_reg_list [idx_input] = 
                i_dec_decode_jump_reg [idx_input];
            input_dec_branch_list   [idx_input] = 
                i_dec_decode_branch   [idx_input];
        end

        // Split Inputs "STRUCT_EX_OUT_RESULT_SUM"
        for (idx_input = 0; idx_input < STRUCT_EX_OUT_RESULT_SUM; idx_input = idx_input+1) begin
            input_wbc_done_phyreg[idx_input] = 
                i_wbc_done_phyreg_data[(_BITWIDTH_STRUCT_PHYREGS*idx_input) +: _BITWIDTH_STRUCT_PHYREGS];
        end

        // Stage 1 Register Output
        for (idx_stage1 = 0; idx_stage1 < STRUCT_DECODE_NEW_INST; idx_stage1 = idx_stage1+1) begin
            s1out_valid_list       [idx_stage1] = stage1[BITWIDTH_NEL_STAGE1*idx_stage1];
            s1out_dec_expath_list  [idx_stage1] = stage1[((BITWIDTH_NEL_STAGE1*idx_stage1)+STARTPOINT_1EXPATH)  +: _BITWIDTH_STRUCT_EX_PATH];
            s1out_pc_list          [idx_stage1] = stage1[((BITWIDTH_NEL_STAGE1*idx_stage1)+STARTPOINT_1PC)      +: _BITWIDTH_FLOW_WINDOWS_PC];
            s1out_dec_microop_list [idx_stage1] = stage1[((BITWIDTH_NEL_STAGE1*idx_stage1)+STARTPOINT_1MICROOP) +: EX_INST_MICROOP_BITWIDTH];
            s1out_dec_rd_list      [idx_stage1] = stage1[((BITWIDTH_NEL_STAGE1*idx_stage1)+STARTPOINT_1RD)      +: _BITWIDTH_IS_INST_REGS];
            s1out_dec_newreg_list  [idx_stage1] = stage1[((BITWIDTH_NEL_STAGE1*idx_stage1)+STARTPOINT_1NEWREG)  +: 1];
            s1out_dec_rs_list      [idx_stage1] = stage1[((BITWIDTH_NEL_STAGE1*idx_stage1)+STARTPOINT_1RS)      +: (_BITWIDTH_IS_INST_REGS*IS_INST_OPERANDS)];
            s1out_dec_imm_list     [idx_stage1] = stage1[((BITWIDTH_NEL_STAGE1*idx_stage1)+STARTPOINT_1IMM)     +: IS_INST_IMM];
            s1out_dec_jump_list    [idx_stage1] = stage1[((BITWIDTH_NEL_STAGE1*idx_stage1)+STARTPOINT_1JUMP)    +: 1];
            s1out_dec_jump_reg_list[idx_stage1] = stage1[((BITWIDTH_NEL_STAGE1*idx_stage1)+STARTPOINT_1JUMPREG) +: 1];
            s1out_dec_branch_list  [idx_stage1] = stage1[((BITWIDTH_NEL_STAGE1*idx_stage1)+STARTPOINT_1BRANCH)  +: 1];
        end

        for (idx_stage1 = 0; idx_stage1 < STRUCT_DECODE_NEW_INST; idx_stage1 = idx_stage1+1) begin
            s1out_valid_all[idx_stage1]         = s1out_valid_list[idx_stage1];
            s2out_valid_all[idx_stage1]         = stage2[BITWIDTH_NEL_STAGE2*idx_stage1];
            s1out_newreg_all[idx_stage1]        = s1out_dec_newreg_list[idx_stage1];
        end

        // Pipeline Transfer Conditions
        // PRM Valid is also the global admission permission. Even a no-RD
        // instruction waits here while PRM holds a buffered input bundle.
        // An already-renamed Stage 2 bundle may still reach IST exactly once.
        stage2_to_ist = reset_n && (|s2out_valid_all) && (&i_ist_new_inst_get);
        stage2_can_accept = !(|s2out_valid_all) || stage2_to_ist;
        stage1_to_stage2 = reset_n && (|s1out_valid_all) && stage2_can_accept && (&i_prm_phyreg_valid);
        stage1_alloc_req = 0;
        stage1_has_control = 1'b0;
        for (idx_stage1 = 0; idx_stage1 < STRUCT_DECODE_NEW_INST; idx_stage1 = idx_stage1+1) begin
            stage1_alloc_req[idx_stage1] = s1out_valid_list[idx_stage1] &&
                s1out_dec_newreg_list[idx_stage1] && (s1out_dec_rd_list[idx_stage1] != 0);
            stage1_has_control = stage1_has_control ||
                (s1out_valid_list[idx_stage1] && (s1out_dec_jump_list[idx_stage1] ||
                 s1out_dec_jump_reg_list[idx_stage1] || s1out_dec_branch_list[idx_stage1]));
        end
        stage1_alloc_fire = stage1_alloc_req & {STRUCT_DECODE_NEW_INST{stage1_to_stage2}};
        o_prm_phyreg_get = stage1_alloc_fire;
        stage1_accept_enable = reset_n && (&i_prm_phyreg_valid) &&
                               (!(|s1out_valid_all) || stage1_to_stage2) && !stage1_has_control && !i_fcl_discard;

        // Stage 1 Update
        // Keep the decoded bundle until it advances. A control-flow bundle leaves
        // a bubble so FCL observes its notification before accepting a new bundle.
        input_jump_branch = 1'b0;
        if (stage1_to_stage2) stage1_next = 0;
        if (stage1_accept_enable) begin
            stage1_next = 0;
            for (idx_stage1 = 0; idx_stage1 < STRUCT_DECODE_NEW_INST; idx_stage1 = idx_stage1+1) begin
                if (i_im_recv_inst_valid[idx_stage1] && !input_jump_branch) begin
                    o_fcl_recv_keep[idx_stage1] = 1'b1;
                    stage1_next[(BITWIDTH_NEL_STAGE1*idx_stage1) +: BITWIDTH_NEL_STAGE1] = {
                        input_dec_branch_list   [idx_stage1],
                        input_dec_jump_reg_list [idx_stage1],
                        input_dec_jump_list     [idx_stage1],
                        input_dec_imm_list      [idx_stage1],
                        input_dec_rs_list       [idx_stage1],
                        input_dec_newreg_list   [idx_stage1],
                        input_dec_rd_list       [idx_stage1],
                        input_dec_microop_list  [idx_stage1],
                        input_pc_list           [idx_stage1],
                        input_dec_expath_list   [idx_stage1],
                        1'b1
                    };
                    o_im_recv_inst_get[idx_stage1] = 1'b1;
                    input_jump_branch = input_dec_jump_list[idx_stage1] ||
                                        input_dec_jump_reg_list[idx_stage1] || input_dec_branch_list[idx_stage1];
                end
                // Responses are in program order. Consume the younger suffix
                // without creating instructions once the first control is seen.
                if (i_im_recv_inst_valid[idx_stage1]) o_im_recv_inst_get[idx_stage1] = 1'b1;
            end
            o_fcl_recv_control = input_jump_branch;
        end
        if (reset_n && i_fcl_discard) o_im_recv_inst_get = i_im_recv_inst_valid;
        o_fcl_recv_valid = i_im_recv_inst_valid & o_im_recv_inst_get;
        for (idx_stage1 = 0; idx_stage1 < STRUCT_DECODE_NEW_INST; idx_stage1 = idx_stage1+1) begin
            o_fcl_new_inst_valid[idx_stage1] = stage1_to_stage2 && s1out_valid_list[idx_stage1];
            o_fcl_new_inst_pc[idx_stage1*_BITWIDTH_FLOW_WINDOWS_PC +: _BITWIDTH_FLOW_WINDOWS_PC] = s1out_pc_list[idx_stage1];
        end

        // Stage 2 - Get Mapping Input Registers
            // Initial
        real_newreg = stage1_alloc_fire;
        for (idx_stage2_0 = 0; idx_stage2_0 < STRUCT_DECODE_NEW_INST; idx_stage2_0 = idx_stage2_0+1) begin
            reg_dest_map_suffix[idx_stage2_0] = 0;
        end
        for (idx_stage2_0 = 0; idx_stage2_0 < (STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS); idx_stage2_0 = idx_stage2_0+1) begin
            reg_src_map_suffix[idx_stage2_0] = 0;
        end
            // Real Action - Suffix AND
        for (idx_stage2_0 = 0; idx_stage2_0 < STRUCT_DECODE_NEW_INST; idx_stage2_0 = idx_stage2_0+1) begin
            ref_reg = s1out_dec_rd_list[idx_stage2_0];

            for (idx_stage2_1 = idx_stage2_0+1; idx_stage2_1 < STRUCT_DECODE_NEW_INST; idx_stage2_1 = idx_stage2_1+1) begin
                comp_reg = s1out_dec_rd_list[idx_stage2_1];
                if ( (s1out_valid_list[idx_stage2_0]) && (s1out_valid_list[idx_stage2_1]) && 
                     (s1out_dec_newreg_list[idx_stage2_0]) && (s1out_dec_newreg_list[idx_stage2_1]) && 
                     (ref_reg != 0) && (comp_reg != 0) && (ref_reg == comp_reg) ) begin

                    reg_dest_map_suffix[idx_stage2_1]               = 0;
                    reg_dest_map_suffix[idx_stage2_1][idx_stage2_0] = 1'b1;
                    // Every writer allocates its own PRD; only the youngest one
                    // for this logical RD commits the final mapping-table value.
                    real_newreg[idx_stage2_0] = 1'b0;
                end
            end

            for (idx_stage2_1 = (idx_stage2_0+1)*IS_INST_OPERANDS; idx_stage2_1 < (STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS); idx_stage2_1 = idx_stage2_1+1) begin
                comp_reg = s1out_dec_rs_list[idx_stage2_1/IS_INST_OPERANDS]
                                            [(_BITWIDTH_IS_INST_REGS*(idx_stage2_1%IS_INST_OPERANDS)) +: _BITWIDTH_IS_INST_REGS];
                if ( (s1out_valid_list[idx_stage2_0]) && (s1out_valid_list[idx_stage2_1/IS_INST_OPERANDS]) && 
                     (s1out_dec_newreg_list[idx_stage2_0]) && 
                     (ref_reg != 0) && (comp_reg != 0) && (ref_reg == comp_reg) ) begin

                    reg_src_map_suffix[idx_stage2_1]               = 0;
                    reg_src_map_suffix[idx_stage2_1][idx_stage2_0] = 1'b1;
                end
            end
        end

        // Stage 2 - Other Information Input
        for (idx_stage2_0 = 0; idx_stage2_0 < STRUCT_DECODE_NEW_INST; idx_stage2_0 = idx_stage2_0+1) begin
            s2in_valid_list   [idx_stage2_0] = s1out_valid_list       [idx_stage2_0];
            s2in_expath_list  [idx_stage2_0] = s1out_dec_expath_list  [idx_stage2_0];
            s2in_pc_list      [idx_stage2_0] = s1out_pc_list          [idx_stage2_0];
            s2in_microop_list [idx_stage2_0] = s1out_dec_microop_list [idx_stage2_0];
            s2in_newreg_list  [idx_stage2_0] = stage1_alloc_req      [idx_stage2_0];
            s2in_imm_list     [idx_stage2_0] = s1out_dec_imm_list     [idx_stage2_0];
            s2in_jump_list    [idx_stage2_0] = s1out_dec_jump_list    [idx_stage2_0];
            s2in_jump_reg_list[idx_stage2_0] = s1out_dec_jump_reg_list[idx_stage2_0];
            s2in_branch_list  [idx_stage2_0] = s1out_dec_branch_list  [idx_stage2_0];
        end

        // Stage 2 - Mapping Register Destination
        for (idx_stage2_0 = 0; idx_stage2_0 < STRUCT_DECODE_NEW_INST; idx_stage2_0 = idx_stage2_0+1) begin
            if (s2in_newreg_list[idx_stage2_0]) begin
                s2in_prd_list[idx_stage2_0] = i_prm_phyreg_data[(_BITWIDTH_STRUCT_PHYREGS*idx_stage2_0) +: _BITWIDTH_STRUCT_PHYREGS];
            end
            else begin
                s2in_prd_list[idx_stage2_0] = 0;
            end
        end
        for (idx_stage2_0 = 0; idx_stage2_0 < STRUCT_DECODE_NEW_INST; idx_stage2_0 = idx_stage2_0+1) begin
            s2in_newreg_all[idx_stage2_0] = s2in_newreg_list[idx_stage2_0];
            s2in_prd_all[(_BITWIDTH_STRUCT_PHYREGS*idx_stage2_0) +: _BITWIDTH_STRUCT_PHYREGS]
                = s2in_prd_list[idx_stage2_0];
        end
        
        // Stage 2 - Mapping Registers Source 
        for (idx_stage2_0 = 0; idx_stage2_0 < (STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS); idx_stage2_0 = idx_stage2_0+1) begin
            ref_reg = s1out_dec_rs_list[idx_stage2_0/IS_INST_OPERANDS]
                [(_BITWIDTH_IS_INST_REGS*(idx_stage2_0%IS_INST_OPERANDS)) +: _BITWIDTH_IS_INST_REGS];
            s2in_prs_list[idx_stage2_0/IS_INST_OPERANDS]
                         [(_BITWIDTH_STRUCT_PHYREGS*(idx_stage2_0%IS_INST_OPERANDS)) +: _BITWIDTH_STRUCT_PHYREGS]
                = (ref_reg == 0)? '0 : prs_mapping_all[(_BITWIDTH_STRUCT_PHYREGS*idx_stage2_0) +: _BITWIDTH_STRUCT_PHYREGS];
            if ( |reg_src_map_suffix[idx_stage2_0] ) begin
                for (idx_stage2_1 = 0; idx_stage2_1 < STRUCT_DECODE_NEW_INST; idx_stage2_1 = idx_stage2_1+1) begin
                    if (reg_src_map_suffix[idx_stage2_0][idx_stage2_1])
                        s2in_prs_list[idx_stage2_0/IS_INST_OPERANDS]
                                     [(_BITWIDTH_STRUCT_PHYREGS*(idx_stage2_0%IS_INST_OPERANDS)) +: _BITWIDTH_STRUCT_PHYREGS]
                            = i_prm_phyreg_data[(_BITWIDTH_STRUCT_PHYREGS*idx_stage2_1) +: _BITWIDTH_STRUCT_PHYREGS];
                end
            end
        end

        // Stage 2 - Input Register
        if (stage2_to_ist) stage2_next = 0;
        if (stage1_to_stage2) begin
            for (idx_stage2_0 = 0; idx_stage2_0 < STRUCT_DECODE_NEW_INST; idx_stage2_0 = idx_stage2_0+1) begin
                stage2_next[(BITWIDTH_NEL_STAGE2*idx_stage2_0) +: BITWIDTH_NEL_STAGE2] = {
                    s2in_branch_list  [idx_stage2_0],
                    s2in_jump_reg_list[idx_stage2_0],
                    s2in_jump_list    [idx_stage2_0],
                    s2in_imm_list     [idx_stage2_0],
                    s2in_prs_list     [idx_stage2_0],
                    s2in_newreg_list  [idx_stage2_0],
                    s2in_prd_list     [idx_stage2_0],
                    s2in_microop_list [idx_stage2_0],
                    s2in_pc_list      [idx_stage2_0],
                    s2in_expath_list  [idx_stage2_0],
                    s2in_valid_list   [idx_stage2_0]
                };
            end
        end

        // Retired Physical Registers - Emit Once at Rename Commit
        // Repeated RD writes form a chain: old mapping -> first PRD -> next PRD.
        for (idx_stage2_0 = 0; idx_stage2_0 < STRUCT_DECODE_NEW_INST; idx_stage2_0 = idx_stage2_0+1) begin
            retired_phyreg[idx_stage2_0] = prd_mapping_all[(_BITWIDTH_STRUCT_PHYREGS*idx_stage2_0) +: _BITWIDTH_STRUCT_PHYREGS];
            for (idx_stage2_1 = 0; idx_stage2_1 < STRUCT_DECODE_NEW_INST; idx_stage2_1 = idx_stage2_1+1) begin
                if (reg_dest_map_suffix[idx_stage2_0][idx_stage2_1])
                    retired_phyreg[idx_stage2_0] = i_prm_phyreg_data[(_BITWIDTH_STRUCT_PHYREGS*idx_stage2_1) +: _BITWIDTH_STRUCT_PHYREGS];
            end
            if (stage1_alloc_fire[idx_stage2_0] && (retired_phyreg[idx_stage2_0] != 0)) begin
                o_fcl_retired_phyreg_valid[idx_stage2_0] = 1'b1;
                o_fcl_retired_phyreg_data[(_BITWIDTH_STRUCT_RETIRED_PHYREG_MSG*idx_stage2_0) +: _BITWIDTH_STRUCT_RETIRED_PHYREG_MSG] =
                    {retired_phyreg[idx_stage2_0], s1out_pc_list[idx_stage2_0]};
            end
        end

        // First Jump/Branch - Same Commit Event, Never Repeated During a Stall
        // LSB [jump, jump_reg, branch, new_pc] MSB. Direct targets use PC + signed IMM;
        // a register-jump target is resolved by EX and its new_pc field is unused.
        control_found = 1'b0;
        control_new_pc = 0;
        for (idx_stage2_0 = 0; idx_stage2_0 < STRUCT_DECODE_NEW_INST; idx_stage2_0 = idx_stage2_0+1) begin
            if (stage1_to_stage2 && s1out_valid_list[idx_stage2_0] && !control_found &&
                (s1out_dec_jump_list[idx_stage2_0] || s1out_dec_jump_reg_list[idx_stage2_0] || s1out_dec_branch_list[idx_stage2_0])) begin
                control_found = 1'b1;
                if (!s1out_dec_jump_reg_list[idx_stage2_0])
                    control_new_pc = s1out_pc_list[idx_stage2_0][0 +: IS_INST_PC_BITWIDTH] +
                                     IS_INST_PC_BITWIDTH'($signed(s1out_dec_imm_list[idx_stage2_0]));
                o_fcl_jumpbranch_valid = 1'b1;
                o_fcl_jumpbranch_pc = s1out_pc_list[idx_stage2_0];
                o_fcl_jumpbranch_data = {control_new_pc, s1out_dec_branch_list[idx_stage2_0],
                                        s1out_dec_jump_reg_list[idx_stage2_0], s1out_dec_jump_list[idx_stage2_0]};
            end
        end

        // Out - Stage 2 Out
        for (idx_stage2_0 = 0; idx_stage2_0 < STRUCT_DECODE_NEW_INST; idx_stage2_0 = idx_stage2_0+1) begin
            s2out_valid_list    [idx_stage2_0] = stage2[BITWIDTH_NEL_STAGE2*idx_stage2_0];
            s2out_expath_list   [idx_stage2_0] = stage2[((BITWIDTH_NEL_STAGE2*idx_stage2_0)+STARTPOINT_2EXPATH ) +: _BITWIDTH_STRUCT_EX_PATH];
            s2out_pc_list       [idx_stage2_0] = stage2[((BITWIDTH_NEL_STAGE2*idx_stage2_0)+STARTPOINT_2PC     ) +: _BITWIDTH_FLOW_WINDOWS_PC];
            s2out_microop_list  [idx_stage2_0] = stage2[((BITWIDTH_NEL_STAGE2*idx_stage2_0)+STARTPOINT_2MICROOP) +: EX_INST_MICROOP_BITWIDTH];
            s2out_prd_list      [idx_stage2_0] = stage2[((BITWIDTH_NEL_STAGE2*idx_stage2_0)+STARTPOINT_2PRD    ) +: _BITWIDTH_STRUCT_PHYREGS];
            s2out_newreg_list   [idx_stage2_0] = stage2[((BITWIDTH_NEL_STAGE2*idx_stage2_0)+STARTPOINT_2NEWREG ) +: 1];
            s2out_prs_list      [idx_stage2_0] = stage2[((BITWIDTH_NEL_STAGE2*idx_stage2_0)+STARTPOINT_2PRS    ) +: (_BITWIDTH_STRUCT_PHYREGS*IS_INST_OPERANDS)];
            s2out_imm_list      [idx_stage2_0] = stage2[((BITWIDTH_NEL_STAGE2*idx_stage2_0)+STARTPOINT_2IMM    ) +: IS_INST_IMM];
            s2out_jump_list     [idx_stage2_0] = stage2[((BITWIDTH_NEL_STAGE2*idx_stage2_0)+STARTPOINT_2JUMP   ) +: 1];
            s2out_jump_reg_list [idx_stage2_0] = stage2[((BITWIDTH_NEL_STAGE2*idx_stage2_0)+STARTPOINT_2JUMPREG) +: 1];
            s2out_branch_list   [idx_stage2_0] = stage2[((BITWIDTH_NEL_STAGE2*idx_stage2_0)+STARTPOINT_2BRANCH ) +: 1];
        end
        for (idx_stage2_0 = 0; idx_stage2_0 < STRUCT_DECODE_NEW_INST; idx_stage2_0 = idx_stage2_0+1) begin
            s2out_newreg_all[idx_stage2_0] = s2out_newreg_list[idx_stage2_0];
            s2out_prd_all[(_BITWIDTH_STRUCT_PHYREGS*idx_stage2_0) +: _BITWIDTH_STRUCT_PHYREGS] = s2out_prd_list[idx_stage2_0];
        end

        // Out - Ready
        for (idx_stage2_0 = 0; idx_stage2_0 < STRUCT_DECODE_NEW_INST; idx_stage2_0 = idx_stage2_0+1) begin
            last_ready[idx_stage2_0] = 0;
            for (idx_stage2_1 = 0; idx_stage2_1 < IS_INST_OPERANDS; idx_stage2_1 = idx_stage2_1+1) begin
                ref_preg = s2out_prs_list[idx_stage2_0][(_BITWIDTH_STRUCT_PHYREGS*idx_stage2_1) +: _BITWIDTH_STRUCT_PHYREGS];
                
                if ( ~s2out_valid_list[idx_stage2_0] )
                    last_ready[idx_stage2_0][idx_stage2_1] = 1'b0;
                else if (ref_preg == 0)
                    last_ready[idx_stage2_0][idx_stage2_1] = 1'b1;
                else
                    last_ready[idx_stage2_0][idx_stage2_1] = ready_table_out[(IS_INST_OPERANDS*idx_stage2_0)+idx_stage2_1];
                
                for (idx_stage2_2 = 0; idx_stage2_2 < STRUCT_EX_OUT_RESULT_SUM; idx_stage2_2 = idx_stage2_2+1) begin
                    if ( s2out_valid_list[idx_stage2_0] && ( i_wbc_done_phyreg_valid[idx_stage2_2] )
                         && ( ref_preg == i_wbc_done_phyreg_data[(_BITWIDTH_STRUCT_PHYREGS*idx_stage2_2) +: _BITWIDTH_STRUCT_PHYREGS] ) ) begin

                        last_ready[idx_stage2_0][idx_stage2_1] = 1'b1;
                    end
                end
            end
        end

        // Out - Output
        for (idx_stage2_0 = 0; idx_stage2_0 < STRUCT_DECODE_NEW_INST; idx_stage2_0 = idx_stage2_0+1) begin
            o_ist_new_inst_valid[idx_stage2_0] = stage2_to_ist && s2out_valid_list[idx_stage2_0];
            o_ist_new_inst_data [(_BITWIDTH_INTERNAL_INST_WIDTH*idx_stage2_0) +: _BITWIDTH_INTERNAL_INST_WIDTH]
                = {
                    last_ready         [idx_stage2_0],
                    s2out_prs_list     [idx_stage2_0],
                    s2out_prd_list     [idx_stage2_0],
                    s2out_imm_list     [idx_stage2_0],
                    s2out_microop_list [idx_stage2_0],
                    s2out_expath_list  [idx_stage2_0],
                    s2out_pc_list      [idx_stage2_0]
                };
        end

    end

    // Read-address wiring depends only on the pipeline registers. Keeping this
    // wiring outside the calculation block avoids a false read-data/address loop
    // through the common regfile; all control and next-state logic remains above.
    genvar read_addr_idx;
    generate
        for (read_addr_idx = 0; read_addr_idx < STRUCT_DECODE_NEW_INST; read_addr_idx = read_addr_idx+1) begin : GEN_NEL_READ_ADDR
            assign s1out_rd_all[(_BITWIDTH_IS_INST_REGS*read_addr_idx) +: _BITWIDTH_IS_INST_REGS] =
                stage1[(BITWIDTH_NEL_STAGE1*read_addr_idx+STARTPOINT_1RD) +: _BITWIDTH_IS_INST_REGS];
            assign s1out_rs_all[(_BITWIDTH_IS_INST_REGS*IS_INST_OPERANDS*read_addr_idx) +: (_BITWIDTH_IS_INST_REGS*IS_INST_OPERANDS)] =
                stage1[(BITWIDTH_NEL_STAGE1*read_addr_idx+STARTPOINT_1RS) +: (_BITWIDTH_IS_INST_REGS*IS_INST_OPERANDS)];
            assign s2out_prs_all[(_BITWIDTH_STRUCT_PHYREGS*IS_INST_OPERANDS*read_addr_idx) +: (_BITWIDTH_STRUCT_PHYREGS*IS_INST_OPERANDS)] =
                stage2[(BITWIDTH_NEL_STAGE2*read_addr_idx+STARTPOINT_2PRS) +: (_BITWIDTH_STRUCT_PHYREGS*IS_INST_OPERANDS)];
        end
    endgenerate

    regfile #(
        .DATA_WIDTH    (_BITWIDTH_STRUCT_PHYREGS),
        .ENTRIES       (IS_INST_REGS),
        .READ_CHANNEL  (STRUCT_DECODE_NEW_INST+(STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS)),
        .WRITE_CHANNEL (STRUCT_DECODE_NEW_INST),
        .INITIAL_VALUE (0)
    ) U_NEL_LOGREG_PHYREG_MAP (
        .clk           (clk),
        .reset_n       (reset_n),
        .i_flush       (1'b0),
        .i_read_addr   ({ s1out_rd_all   , s1out_rs_all    }),
        .o_read_data   ({ prd_mapping_all, prs_mapping_all }),
        .i_write_addr  (s1out_rd_all),
        .i_write_en    (real_newreg),
        .i_write_data  (i_prm_phyreg_data)
    );

    regfile #(
        .DATA_WIDTH    (1),
        .ENTRIES       (STRUCT_PHYREGS),
        .READ_CHANNEL  (STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS),
        .WRITE_CHANNEL (STRUCT_EX_OUT_RESULT_SUM+STRUCT_DECODE_NEW_INST),
        .INITIAL_VALUE (1)
    ) U_NEL_PHYREG_READY (
        .clk           (clk),
        .reset_n       (reset_n),
        .i_flush       (1'b0),
        .i_read_addr   (s2out_prs_all),
        .o_read_data   (ready_table_out),
        // Allocation starts a new lifetime and wins over an old WBC event at the
        // same address. Clear every allocated PRD, including earlier WAW writers.
        .i_write_addr  ({ i_prm_phyreg_data,              i_wbc_done_phyreg_data           }),
        .i_write_en    ({ stage1_alloc_fire,             i_wbc_done_phyreg_valid          }),
        .i_write_data  ({ {STRUCT_DECODE_NEW_INST{1'b0}}, {STRUCT_EX_OUT_RESULT_SUM{1'b1}} })
    );

endmodule
