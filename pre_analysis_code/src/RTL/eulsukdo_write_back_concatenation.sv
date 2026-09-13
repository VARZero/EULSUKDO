`timescale 1ns/1ps

module eulsukdo_write_back_concatenation #(
    parameter int unsigned PC_WIDTH       = 32,
    parameter int unsigned PHY_REGS       = 64,
    parameter int unsigned FLOW_WINDOWS   = 8,
    parameter int unsigned RESULT_PORTS   = 5,
    parameter int unsigned BRANCH_PORTS   = 1,
    parameter int unsigned PHY_REG_WIDTH  = (PHY_REGS <= 1) ? 1 : $clog2(PHY_REGS),
    parameter int unsigned FLOW_WIDTH     = (FLOW_WINDOWS <= 1) ? 1 : $clog2(FLOW_WINDOWS),
    parameter int unsigned RESULT_WIDTH   = PC_WIDTH + FLOW_WIDTH + PHY_REG_WIDTH,
    parameter int unsigned DONE_PC_WIDTH  = PC_WIDTH + FLOW_WIDTH,
    parameter int unsigned BRANCH_WIDTH   = PC_WIDTH + FLOW_WIDTH + 1 + PC_WIDTH
) (
    input  logic [RESULT_PORTS-1:0]       i_ex_result_valid,
    input  logic [RESULT_PORTS*RESULT_WIDTH-1:0] i_ex_result_data,
    input  logic [BRANCH_PORTS-1:0]       i_ex_branch_valid,
    input  logic [BRANCH_PORTS*BRANCH_WIDTH-1:0] i_ex_branch_data,

    output logic [RESULT_PORTS-1:0]       o_done_pc_valid,
    output logic [RESULT_PORTS*DONE_PC_WIDTH-1:0] o_done_pc_data,
    output logic [RESULT_PORTS-1:0]       o_done_phy_valid,
    output logic [RESULT_PORTS*PHY_REG_WIDTH-1:0] o_done_phy_data,
    output logic [BRANCH_PORTS-1:0]       o_branch_valid,
    output logic [BRANCH_PORTS*BRANCH_WIDTH-1:0] o_branch_data
);
    integer port;
    logic [PHY_REG_WIDTH-1:0] result_phy;

    always_comb begin
        o_done_pc_valid = i_ex_result_valid;
        o_done_pc_data = '0;
        o_done_phy_valid = '0;
        o_done_phy_data = '0;
        for (port = 0; port < RESULT_PORTS; port = port + 1) begin
            o_done_pc_data[port*DONE_PC_WIDTH +: DONE_PC_WIDTH] =
                i_ex_result_data[port*RESULT_WIDTH +: DONE_PC_WIDTH];
            result_phy = i_ex_result_data[port*RESULT_WIDTH + DONE_PC_WIDTH +: PHY_REG_WIDTH];
            o_done_phy_data[port*PHY_REG_WIDTH +: PHY_REG_WIDTH] = result_phy;
            o_done_phy_valid[port] = i_ex_result_valid[port] && (result_phy != '0);
        end
        o_branch_valid = i_ex_branch_valid;
        o_branch_data = i_ex_branch_data;
    end
endmodule
