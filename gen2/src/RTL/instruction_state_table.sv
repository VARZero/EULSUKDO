`timescale 1ns/1ps
module instruction_state_table #(
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
    localparam int _BITWIDTH_STRUCT_FLOW_WINDOWS        = $clog2(STRUCT_FLOW_WINDOWS),
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

    // New Internal Instruction Input (NEL)
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                                         i_nel_new_inst_valid,
    output wire [STRUCT_DECODE_NEW_INST-1:0]                                                         o_nel_new_inst_get,
    input  wire [(STRUCT_EX_CORES *(_BITWIDTH_INTERNAL_INST_WIDTH) )-1:0]                            i_nel_new_inst_data,

    // Ready Physical Registers Input (PRM)
    input  wire [STRUCT_PRM_ENTRY_UPDATE-1:0]                                                        i_prm_ready_phyreg_valid,
    input  wire [(STRUCT_PRM_ENTRY_UPDATE *(_BITWIDTH_READY_PRM) )-1:0]                              i_prm_ready_phyreg_data,
    
    // Executable (All phyreg in instruction are ready) Internal Instruction Output (RS)
    output wire [(STRUCT_DECODE_NEW_INST+STRUCT_PRM_ENTRY_UPDATE)-1:0]                               o_rs_ready_inst_valid,
    input  wire [(STRUCT_DECODE_NEW_INST+STRUCT_PRM_ENTRY_UPDATE)-1:0]                               i_rs_ready_inst_get,
    output wire [((STRUCT_DECODE_NEW_INST+STRUCT_PRM_ENTRY_UPDATE) *(_BITWIDTH_EX_INST_WIDTH) )-1:0] o_rs_ready_inst_data,

    // Wait Physical Registers Output (PRM)
    output wire [STRUCT_PRM_ENTRY_UPDATE-1:0]                                                        o_prm_wait_phyreg_valid,
    output wire [(STRUCT_PRM_ENTRY_UPDATE *(_BITWIDTH_READY_PRM) )-1:0]                              o_prm_wait_phyreg_data
);

    localparam int NEW_UPDATE_WIDTH        = STRUCT_DECODE_NEW_INST + STRUCT_PRM_ENTRY_UPDATE;
    localparam int STARTBIT_RS_PART        = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                           + IS_INST_PC_BITWIDTH
                                           + _BITWIDTH_STRUCT_EX_PATH
                                           + EX_INST_MICROOP_BITWIDTH
                                           + IS_INST_IMM
                                           + _BITWIDTH_STRUCT_PHYREGS;
    localparam int STARTBIT_REG_READY_PART = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                           + IS_INST_PC_BITWIDTH
                                           + _BITWIDTH_STRUCT_EX_PATH
                                           + EX_INST_MICROOP_BITWIDTH
                                           + IS_INST_IMM
                                           + _BITWIDTH_STRUCT_PHYREGS // rd
                                           + (_BITWIDTH_STRUCT_PHYREGS * IS_INST_OPERANDS); // rs1..n

    logic [_BITWIDTH_INTERNAL_INST_WIDTH-1:0]                 target_internal_inst;
    logic [_BITWIDTH_EX_INST_WIDTH-1:0]                       target_ist_entry    [0:STRUCT_DECODE_NEW_INST-1];
    logic [(_BITWIDTH_STRUCT_PHYREGS * IS_INST_OPERANDS)-1:0] target_phyreg_source[0:STRUCT_DECODE_NEW_INST-1];
    logic [IS_INST_OPERANDS-1:0]                              target_source_ready [0:STRUCT_DECODE_NEW_INST-1];

    integer idx_internal_inst;

    always_comb begin
        for (idx_internal_inst = 0; idx_internal_inst < STRUCT_DECODE_NEW_INST; idx_internal_inst = idx_internal_inst+1) begin
            target_internal_inst = 
                i_nel_new_inst_data[(_BITWIDTH_INTERNAL_INST_WIDTH*idx_internal_inst) +: _BITWIDTH_INTERNAL_INST_WIDTH];
            target_ist_entry[idx_internal_inst]     =
                target_internal_inst[0                       +: _BITWIDTH_EX_INST_WIDTH];
            target_phyreg_source[idx_internal_inst] = 
                target_internal_inst[STARTBIT_RS_PART        +: (_BITWIDTH_STRUCT_PHYREGS * IS_INST_OPERANDS)];
            target_source_ready[idx_internal_inst]  = 
                target_internal_inst[STARTBIT_REG_READY_PART +: IS_INST_OPERANDS];
        end
    end

    allocator #(
        .ENTRIES            (STRUCT_INST_STATE_ENTRIES),
        .START_VALUE        (0),
        .ALLOCATE_CHANNEL   (STRUCT_DECODE_NEW_INST),
        .UNALLOCATE_CHANNEL (),
        .USE_BRAM           (1'b0)
    ) U_IST_ENTRY_ALLOCATOR (
        .clk                (clk),
        .reset_n            (reset_n),
        .i_flush            (1'b0), // 지금은 분기가 없어..
        .i_unallocate       (),
        .o_unallocate_ready (),
        .i_unallocate_data  (),
        .i_allocate         (),
        .o_allocate_valid   (),
        .o_allocate_data    ()
    );
    
    regfile #(
        .DATA_WIDTH    (_BITWIDTH_STRUCT_PHYREGS*IS_INST_OPERANDS),
        .ENTRIES       (STRUCT_INST_STATE_ENTRIES),
        .READ_CHANNEL  (STRUCT_PRM_ENTRY_UPDATE),
        .WRITE_CHANNEL (NEW_UPDATE_WIDTH),
        .INITIAL_VALUE (0)
    ) U_IST_SOURCE_TABLE (
        .clk           (clk),
        .reset_n       (reset_n),
        .i_flush       (1'b0), // 지금은 분기가 없어..
        .i_read_addr   (),
        .o_read_data   (),
        .i_write_addr  (),
        .i_write_en    (),
        .i_write_data  ()
    );
    
    regfile #(
        .DATA_WIDTH    (IS_INST_OPERANDS),
        .ENTRIES       (STRUCT_INST_STATE_ENTRIES),
        .READ_CHANNEL  (STRUCT_PRM_ENTRY_UPDATE),
        .WRITE_CHANNEL (NEW_UPDATE_WIDTH),
        .INITIAL_VALUE (0)
    ) U_IST_READY_FLAGS_TABLE (
        .clk           (clk),
        .reset_n       (reset_n),
        .i_flush       (1'b0), // 지금은 분기가 없어..
        .i_read_addr   (),
        .o_read_data   (),
        .i_write_addr  (),
        .i_write_en    (),
        .i_write_data  ()
    );
    
    regfile #(
        .DATA_WIDTH    (_BITWIDTH_EX_INST_WIDTH),
        .ENTRIES       (STRUCT_INST_STATE_ENTRIES),
        .READ_CHANNEL  (STRUCT_PRM_ENTRY_UPDATE),
        .WRITE_CHANNEL (NEW_UPDATE_WIDTH),
        .INITIAL_VALUE (0)
    ) U_IST_ENTRY_TABLE (
        .clk           (clk),
        .reset_n       (reset_n),
        .i_flush       (1'b0), // 지금은 분기가 없어..
        .i_read_addr   (),
        .o_read_data   (),
        .i_write_addr  (),
        .i_write_en    (),
        .i_write_data  ()
    );

endmodule
