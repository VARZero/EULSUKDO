`timescale 1ns/1ps

module eulsukdo_gen3 #(
    parameter int unsigned PC_WIDTH       = 32,
    parameter int unsigned PC_STEP        = 4,
    parameter int unsigned LOG_REGS       = 32,
    parameter int unsigned OPERANDS       = 2,
    parameter int unsigned IMM_WIDTH      = 32,
    parameter int unsigned MICROOP_WIDTH  = 5,
    parameter int unsigned DECODE_WIDTH   = 2,
    parameter int unsigned IST_ENTRIES    = 128,
    parameter int unsigned PHY_REGS       = 64,
    parameter int unsigned EX_PATHS       = 3,
    parameter int unsigned FLOW_WINDOWS   = 8,
    parameter int unsigned RESULT_PORTS   = 5,
    parameter int unsigned BRANCH_PORTS   = 1,
    parameter int unsigned DEPTH_PER_REG  = 4,
    parameter int unsigned WAKE_PORTS     = 5,
    parameter int unsigned FREE_PORTS     = 4,
    parameter int unsigned RS_DEPTH       = 16,
    parameter int unsigned ISSUE_PORTS    = 5,
    parameter int unsigned ISSUE_COUNT_WIDTH = 8,
    parameter logic [EX_PATHS*ISSUE_COUNT_WIDTH-1:0] ISSUE_PER_PATH = {8'd1, 8'd3, 8'd1},
    parameter int unsigned ROB_ENTRIES    = IST_ENTRIES,

    parameter int unsigned LOG_REG_WIDTH  = (LOG_REGS <= 1) ? 1 : $clog2(LOG_REGS),
    parameter int unsigned PHY_REG_WIDTH  = (PHY_REGS <= 1) ? 1 : $clog2(PHY_REGS),
    parameter int unsigned IST_WIDTH      = (IST_ENTRIES <= 1) ? 1 : $clog2(IST_ENTRIES),
    parameter int unsigned EX_PATH_WIDTH  = (EX_PATHS <= 1) ? 1 : $clog2(EX_PATHS),
    parameter int unsigned FLOW_WIDTH     = (FLOW_WINDOWS <= 1) ? 1 : $clog2(FLOW_WINDOWS),
    parameter int unsigned INTERNAL_WIDTH = PC_WIDTH + FLOW_WIDTH + EX_PATH_WIDTH + MICROOP_WIDTH +
                                            IMM_WIDTH + PHY_REG_WIDTH + OPERANDS*PHY_REG_WIDTH + OPERANDS,
    parameter int unsigned IST_ISSUE_WIDTH = INTERNAL_WIDTH - OPERANDS,
    parameter int unsigned EX_ISSUE_WIDTH = IST_ISSUE_WIDTH - EX_PATH_WIDTH,
    parameter int unsigned RESULT_WIDTH   = PC_WIDTH + FLOW_WIDTH + PHY_REG_WIDTH,
    parameter int unsigned BRANCH_WIDTH   = PC_WIDTH + FLOW_WIDTH + 1 + PC_WIDTH,
    parameter int unsigned FETCH_WIDTH    = PC_WIDTH + FLOW_WIDTH
) (
    input  logic                              clk,
    input  logic                              reset_n,

    output logic [DECODE_WIDTH-1:0]           o_fetch_valid,
    input  logic [DECODE_WIDTH-1:0]           i_fetch_get,
    output logic [DECODE_WIDTH*FETCH_WIDTH-1:0] o_fetch_data,

    input  logic [DECODE_WIDTH-1:0]           i_decode_valid,
    output logic [DECODE_WIDTH-1:0]           o_decode_get,
    input  logic [DECODE_WIDTH*PC_WIDTH-1:0]  i_decode_pc,
    input  logic [DECODE_WIDTH*FLOW_WIDTH-1:0] i_decode_flow,
    input  logic [DECODE_WIDTH*EX_PATH_WIDTH-1:0] i_decode_ex_path,
    input  logic [DECODE_WIDTH*MICROOP_WIDTH-1:0] i_decode_microop,
    input  logic [DECODE_WIDTH*IMM_WIDTH-1:0] i_decode_imm,
    input  logic [DECODE_WIDTH*LOG_REG_WIDTH-1:0] i_decode_rd,
    input  logic [DECODE_WIDTH-1:0]           i_decode_writes_rd,
    input  logic [DECODE_WIDTH*OPERANDS*LOG_REG_WIDTH-1:0] i_decode_rs,
    input  logic [DECODE_WIDTH-1:0]           i_decode_exception,
    input  logic [DECODE_WIDTH-1:0]           i_decode_jump,
    input  logic [DECODE_WIDTH-1:0]           i_decode_jump_reg,
    input  logic [DECODE_WIDTH-1:0]           i_decode_branch,
    input  logic [DECODE_WIDTH*PC_WIDTH-1:0]  i_decode_target_pc,

    output logic [ISSUE_PORTS-1:0]            o_issue_valid,
    input  logic [ISSUE_PORTS-1:0]            i_issue_get,
    output logic [ISSUE_PORTS*EX_ISSUE_WIDTH-1:0] o_issue_data,

    input  logic [RESULT_PORTS-1:0]           i_result_valid,
    input  logic [RESULT_PORTS*RESULT_WIDTH-1:0] i_result_data,
    input  logic [BRANCH_PORTS-1:0]           i_branch_valid,
    input  logic [BRANCH_PORTS*BRANCH_WIDTH-1:0] i_branch_data
);
    localparam int unsigned DISPATCH_WIDTH = DECODE_WIDTH + WAKE_PORTS;
    localparam int unsigned DEP_WIDTH = PHY_REG_WIDTH + IST_WIDTH;
    localparam int unsigned RETIRE_WIDTH = PC_WIDTH + FLOW_WIDTH + PHY_REG_WIDTH + 1;
    localparam int unsigned CONTROL_WIDTH = PC_WIDTH + FLOW_WIDTH + PC_WIDTH + 3;
    localparam int unsigned DONE_PC_WIDTH = PC_WIDTH + FLOW_WIDTH;

    logic [DECODE_WIDTH-1:0] alloc_req;
    logic [DECODE_WIDTH-1:0] alloc_valid;
    logic [DECODE_WIDTH-1:0] alloc_get;
    logic [DECODE_WIDTH*PHY_REG_WIDTH-1:0] alloc_phy;
    logic [DECODE_WIDTH-1:0] nel_ist_valid;
    // NEL valid does not depend on this get signal; the warning is caused by
    // conservative process-level analysis across the atomic bundle handshake.
    /* verilator lint_off UNOPTFLAT */
    logic [DECODE_WIDTH-1:0] ist_nel_get;
    /* verilator lint_on UNOPTFLAT */
    logic [DECODE_WIDTH*INTERNAL_WIDTH-1:0] nel_ist_data;
    logic [DECODE_WIDTH-1:0] retire_valid;
    logic [DECODE_WIDTH*RETIRE_WIDTH-1:0] retire_data;
    logic retire_ready;
    logic control_valid;
    logic [CONTROL_WIDTH-1:0] control_data;

    logic [DECODE_WIDTH*OPERANDS-1:0] dep_valid;
    logic [DECODE_WIDTH*OPERANDS*DEP_WIDTH-1:0] dep_data;
    logic dep_commit;
    logic dep_ready;
    logic [WAKE_PORTS-1:0] wake_valid;
    logic [WAKE_PORTS-1:0] wake_get;
    logic [WAKE_PORTS*DEP_WIDTH-1:0] wake_data;
    logic [DISPATCH_WIDTH-1:0] dispatch_valid;
    logic [DISPATCH_WIDTH-1:0] dispatch_get;
    logic [DISPATCH_WIDTH*IST_ISSUE_WIDTH-1:0] dispatch_data;

    logic [RESULT_PORTS-1:0] done_pc_valid;
    logic [RESULT_PORTS*DONE_PC_WIDTH-1:0] done_pc_data;
    logic [RESULT_PORTS-1:0] done_phy_valid;
    logic [RESULT_PORTS*PHY_REG_WIDTH-1:0] done_phy_data;
    logic [BRANCH_PORTS-1:0] branch_valid;
    logic [BRANCH_PORTS*BRANCH_WIDTH-1:0] branch_data;
    logic [FREE_PORTS-1:0] free_valid;
    logic [FREE_PORTS*PHY_REG_WIDTH-1:0] free_phy;

    eulsukdo_new_entry_logic #(
        .PC_WIDTH(PC_WIDTH), .LOG_REGS(LOG_REGS), .OPERANDS(OPERANDS),
        .IMM_WIDTH(IMM_WIDTH), .MICROOP_WIDTH(MICROOP_WIDTH), .DECODE_WIDTH(DECODE_WIDTH),
        .IST_ENTRIES(IST_ENTRIES), .PHY_REGS(PHY_REGS), .EX_PATHS(EX_PATHS),
        .FLOW_WINDOWS(FLOW_WINDOWS), .RESULT_PORTS(RESULT_PORTS)
    ) u_nel (
        .clk, .reset_n,
        .i_dec_valid(i_decode_valid), .o_dec_get(o_decode_get), .i_dec_pc(i_decode_pc),
        .i_dec_flow(i_decode_flow), .i_dec_ex_path(i_decode_ex_path),
        .i_dec_microop(i_decode_microop), .i_dec_imm(i_decode_imm), .i_dec_rd(i_decode_rd),
        .i_dec_writes_rd(i_decode_writes_rd), .i_dec_rs(i_decode_rs),
        .i_dec_exception(i_decode_exception), .i_dec_jump(i_decode_jump),
        .i_dec_jump_reg(i_decode_jump_reg), .i_dec_branch(i_decode_branch),
        .i_dec_target_pc(i_decode_target_pc), .o_prm_alloc_req(alloc_req),
        .i_prm_alloc_valid(alloc_valid), .i_prm_alloc_phy(alloc_phy), .o_prm_alloc_get(alloc_get),
        .i_done_valid(done_phy_valid), .i_done_phy(done_phy_data),
        .o_ist_valid(nel_ist_valid), .i_ist_get(ist_nel_get), .o_ist_data(nel_ist_data),
        .o_fcl_retire_valid(retire_valid), .o_fcl_retire_data(retire_data),
        .i_fcl_retire_ready(retire_ready), .o_fcl_control_valid(control_valid),
        .o_fcl_control_data(control_data)
    );

    eulsukdo_instruction_state_table #(
        .PC_WIDTH(PC_WIDTH), .OPERANDS(OPERANDS), .IMM_WIDTH(IMM_WIDTH),
        .MICROOP_WIDTH(MICROOP_WIDTH), .DECODE_WIDTH(DECODE_WIDTH),
        .IST_ENTRIES(IST_ENTRIES), .PHY_REGS(PHY_REGS), .EX_PATHS(EX_PATHS),
        .FLOW_WINDOWS(FLOW_WINDOWS), .WAKE_PORTS(WAKE_PORTS),
        .DISPATCH_WIDTH(DISPATCH_WIDTH)
    ) u_ist (
        .clk, .reset_n, .i_nel_valid(nel_ist_valid), .o_nel_get(ist_nel_get),
        .i_nel_data(nel_ist_data), .o_prm_dep_valid(dep_valid), .o_prm_dep_data(dep_data),
        .o_prm_dep_commit(dep_commit), .i_prm_dep_ready(dep_ready),
        .i_prm_wake_valid(wake_valid), .o_prm_wake_get(wake_get), .i_prm_wake_data(wake_data),
        .o_rs_valid(dispatch_valid), .i_rs_get(dispatch_get), .o_rs_data(dispatch_data)
    );

    eulsukdo_physical_register_mapper #(
        .DECODE_WIDTH(DECODE_WIDTH), .OPERANDS(OPERANDS), .IST_ENTRIES(IST_ENTRIES),
        .PHY_REGS(PHY_REGS), .DEPTH_PER_REG(DEPTH_PER_REG), .WAKE_PORTS(WAKE_PORTS),
        .FREE_PORTS(FREE_PORTS), .RESULT_PORTS(RESULT_PORTS)
    ) u_prm (
        .clk, .reset_n, .i_alloc_req(alloc_req), .o_alloc_valid(alloc_valid),
        .o_alloc_phy(alloc_phy), .i_alloc_get(alloc_get), .i_dep_valid(dep_valid),
        .i_dep_data(dep_data), .i_dep_commit(dep_commit), .o_dep_ready(dep_ready),
        .i_done_valid(done_phy_valid), .i_done_phy(done_phy_data),
        .o_wake_valid(wake_valid), .o_wake_data(wake_data), .i_wake_get(wake_get),
        .i_free_valid(free_valid), .i_free_phy(free_phy)
    );

    eulsukdo_ready_station #(
        .PC_WIDTH(PC_WIDTH), .OPERANDS(OPERANDS), .IMM_WIDTH(IMM_WIDTH),
        .MICROOP_WIDTH(MICROOP_WIDTH), .PHY_REGS(PHY_REGS), .EX_PATHS(EX_PATHS),
        .FLOW_WINDOWS(FLOW_WINDOWS), .INPUT_PORTS(DISPATCH_WIDTH), .RS_DEPTH(RS_DEPTH),
        .ISSUE_PORTS(ISSUE_PORTS), .ISSUE_COUNT_WIDTH(ISSUE_COUNT_WIDTH),
        .ISSUE_PER_PATH(ISSUE_PER_PATH)
    ) u_rs (
        .clk, .reset_n, .i_ist_valid(dispatch_valid), .o_ist_get(dispatch_get),
        .i_ist_data(dispatch_data), .o_ex_valid(o_issue_valid),
        .i_ex_get(i_issue_get), .o_ex_data(o_issue_data)
    );

    eulsukdo_write_back_concatenation #(
        .PC_WIDTH(PC_WIDTH), .PHY_REGS(PHY_REGS), .FLOW_WINDOWS(FLOW_WINDOWS),
        .RESULT_PORTS(RESULT_PORTS), .BRANCH_PORTS(BRANCH_PORTS)
    ) u_wbc (
        .i_ex_result_valid(i_result_valid), .i_ex_result_data(i_result_data),
        .i_ex_branch_valid(i_branch_valid), .i_ex_branch_data(i_branch_data),
        .o_done_pc_valid(done_pc_valid), .o_done_pc_data(done_pc_data),
        .o_done_phy_valid(done_phy_valid), .o_done_phy_data(done_phy_data),
        .o_branch_valid(branch_valid), .o_branch_data(branch_data)
    );

    eulsukdo_flow_control_logic #(
        .PC_WIDTH(PC_WIDTH), .PC_STEP(PC_STEP), .DECODE_WIDTH(DECODE_WIDTH),
        .PHY_REGS(PHY_REGS), .FLOW_WINDOWS(FLOW_WINDOWS), .RESULT_PORTS(RESULT_PORTS),
        .BRANCH_PORTS(BRANCH_PORTS), .FREE_PORTS(FREE_PORTS), .ROB_ENTRIES(ROB_ENTRIES)
    ) u_fcl (
        .clk, .reset_n, .o_im_req_valid(o_fetch_valid), .i_im_req_get(i_fetch_get),
        .o_im_req_data(o_fetch_data), .i_retire_valid(retire_valid),
        .i_retire_data(retire_data), .o_retire_ready(retire_ready),
        .i_control_valid(control_valid), .i_control_data(control_data),
        .i_done_valid(done_pc_valid), .i_done_data(done_pc_data),
        .i_branch_valid(branch_valid), .i_branch_data(branch_data),
        .o_free_valid(free_valid), .o_free_phy(free_phy)
    );

    initial begin
        if (DECODE_WIDTH < 1 || ISSUE_PORTS < 1 || RESULT_PORTS < 1)
            $error("Invalid EULSUKDO top-level parameters");
    end
endmodule
