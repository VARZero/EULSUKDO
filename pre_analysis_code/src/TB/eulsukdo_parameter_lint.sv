`timescale 1ns/1ps

module eulsukdo_parameter_lint;
    eulsukdo_gen3 u_default ();

    eulsukdo_gen3 #(
        .PC_WIDTH(24),
        .PC_STEP(2),
        .LOG_REGS(16),
        .OPERANDS(3),
        .IMM_WIDTH(16),
        .MICROOP_WIDTH(7),
        .DECODE_WIDTH(1),
        .IST_ENTRIES(24),
        .PHY_REGS(40),
        .EX_PATHS(2),
        .FLOW_WINDOWS(4),
        .RESULT_PORTS(2),
        .BRANCH_PORTS(1),
        .DEPTH_PER_REG(6),
        .WAKE_PORTS(3),
        .FREE_PORTS(2),
        .RS_DEPTH(8),
        .ISSUE_PORTS(2),
        .ISSUE_PER_PATH({8'd1, 8'd1}),
        .ROB_ENTRIES(24)
    ) u_alternate ();
endmodule
