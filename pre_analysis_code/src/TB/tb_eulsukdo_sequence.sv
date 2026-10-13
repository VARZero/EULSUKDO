`timescale 1ns/1ps

module tb_eulsukdo_sequence;
    localparam int PC_WIDTH = 16;
    localparam int LOG_REGS = 8;
    localparam int OPERANDS = 2;
    localparam int IMM_WIDTH = 12;
    localparam int MICROOP_WIDTH = 4;
    localparam int DECODE_WIDTH = 2;
    localparam int IST_ENTRIES = 16;
    localparam int PHY_REGS = 16;
    localparam int EX_PATHS = 2;
    localparam int FLOW_WINDOWS = 4;
    localparam int RESULT_PORTS = 2;
    localparam int BRANCH_PORTS = 1;
    localparam int WAKE_PORTS = 2;
    localparam int FREE_PORTS = 2;
    localparam int ISSUE_PORTS = 2;

    localparam int LOG_REG_WIDTH = $clog2(LOG_REGS);
    localparam int PHY_REG_WIDTH = $clog2(PHY_REGS);
    localparam int EX_PATH_WIDTH = $clog2(EX_PATHS);
    localparam int FLOW_WIDTH = $clog2(FLOW_WINDOWS);
    localparam int FETCH_WIDTH = PC_WIDTH + FLOW_WIDTH;
    localparam int EX_ISSUE_WIDTH = PC_WIDTH + FLOW_WIDTH + MICROOP_WIDTH +
                                    IMM_WIDTH + PHY_REG_WIDTH + OPERANDS*PHY_REG_WIDTH;
    localparam int RESULT_WIDTH = PC_WIDTH + FLOW_WIDTH + PHY_REG_WIDTH;
    localparam int BRANCH_WIDTH = PC_WIDTH + FLOW_WIDTH + 1 + PC_WIDTH;
    localparam int ISSUE_P_PC = 0;
    localparam int ISSUE_P_FLOW = ISSUE_P_PC + PC_WIDTH;
    localparam int ISSUE_P_UOP = ISSUE_P_FLOW + FLOW_WIDTH;
    localparam int ISSUE_P_IMM = ISSUE_P_UOP + MICROOP_WIDTH;
    localparam int ISSUE_P_RD = ISSUE_P_IMM + IMM_WIDTH;
    localparam int ISSUE_P_RS = ISSUE_P_RD + PHY_REG_WIDTH;

    logic clk;
    logic reset_n = 1'b0;
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

`ifdef TRACE
    initial begin
        $dumpfile("eulsukdo_sequence.vcd");
        $dumpvars(0, tb_eulsukdo_sequence);
    end
`endif

    logic [DECODE_WIDTH-1:0] fetch_valid;
    logic [DECODE_WIDTH-1:0] fetch_get;
    logic [DECODE_WIDTH*FETCH_WIDTH-1:0] fetch_data;
    logic [DECODE_WIDTH-1:0] decode_valid;
    logic [DECODE_WIDTH-1:0] decode_get;
    logic [DECODE_WIDTH*PC_WIDTH-1:0] decode_pc;
    logic [DECODE_WIDTH*FLOW_WIDTH-1:0] decode_flow;
    logic [DECODE_WIDTH*EX_PATH_WIDTH-1:0] decode_ex_path;
    logic [DECODE_WIDTH*MICROOP_WIDTH-1:0] decode_microop;
    logic [DECODE_WIDTH*IMM_WIDTH-1:0] decode_imm;
    logic [DECODE_WIDTH*LOG_REG_WIDTH-1:0] decode_rd;
    logic [DECODE_WIDTH-1:0] decode_writes_rd;
    logic [DECODE_WIDTH*OPERANDS*LOG_REG_WIDTH-1:0] decode_rs;
    logic [DECODE_WIDTH-1:0] decode_exception;
    logic [DECODE_WIDTH-1:0] decode_jump;
    logic [DECODE_WIDTH-1:0] decode_jump_reg;
    logic [DECODE_WIDTH-1:0] decode_branch;
    logic [DECODE_WIDTH*PC_WIDTH-1:0] decode_target_pc;
    logic [ISSUE_PORTS-1:0] issue_valid;
    logic [ISSUE_PORTS-1:0] issue_get;
    logic [ISSUE_PORTS*EX_ISSUE_WIDTH-1:0] issue_data;
    logic [RESULT_PORTS-1:0] result_valid;
    logic [RESULT_PORTS*RESULT_WIDTH-1:0] result_data;
    logic [BRANCH_PORTS-1:0] branch_valid;
    logic [BRANCH_PORTS*BRANCH_WIDTH-1:0] branch_data;

    eulsukdo_gen3 #(
        .PC_WIDTH(PC_WIDTH), .PC_STEP(4), .LOG_REGS(LOG_REGS), .OPERANDS(OPERANDS),
        .IMM_WIDTH(IMM_WIDTH), .MICROOP_WIDTH(MICROOP_WIDTH), .DECODE_WIDTH(DECODE_WIDTH),
        .IST_ENTRIES(IST_ENTRIES), .PHY_REGS(PHY_REGS), .EX_PATHS(EX_PATHS),
        .FLOW_WINDOWS(FLOW_WINDOWS), .RESULT_PORTS(RESULT_PORTS),
        .BRANCH_PORTS(BRANCH_PORTS), .DEPTH_PER_REG(4), .WAKE_PORTS(WAKE_PORTS),
        .FREE_PORTS(FREE_PORTS), .RS_DEPTH(8), .ISSUE_PORTS(ISSUE_PORTS),
        .ISSUE_PER_PATH({8'd1, 8'd1}), .ROB_ENTRIES(IST_ENTRIES)
    ) dut (
        .clk, .reset_n,
        .o_fetch_valid(fetch_valid), .i_fetch_get(fetch_get), .o_fetch_data(fetch_data),
        .i_decode_valid(decode_valid), .o_decode_get(decode_get), .i_decode_pc(decode_pc),
        .i_decode_flow(decode_flow), .i_decode_ex_path(decode_ex_path),
        .i_decode_microop(decode_microop), .i_decode_imm(decode_imm), .i_decode_rd(decode_rd),
        .i_decode_writes_rd(decode_writes_rd), .i_decode_rs(decode_rs),
        .i_decode_exception(decode_exception), .i_decode_jump(decode_jump),
        .i_decode_jump_reg(decode_jump_reg), .i_decode_branch(decode_branch),
        .i_decode_target_pc(decode_target_pc),
        .o_issue_valid(issue_valid), .i_issue_get(issue_get), .o_issue_data(issue_data),
        .i_result_valid(result_valid), .i_result_data(result_data),
        .i_branch_valid(branch_valid), .i_branch_data(branch_data)
    );

    task automatic clear_decode;
        begin
            decode_valid = '0;
            decode_pc = '0;
            decode_flow = '0;
            decode_ex_path = '0;
            decode_microop = '0;
            decode_imm = '0;
            decode_rd = '0;
            decode_writes_rd = '0;
            decode_rs = '0;
            decode_exception = '0;
            decode_jump = '0;
            decode_jump_reg = '0;
            decode_branch = '0;
            decode_target_pc = '0;
        end
    endtask

    task automatic set_lane(
        input int lane, input int pc, input int path, input int rd,
        input int rs0, input int rs1, input bit writes_rd, input int uop
    );
        begin
            decode_valid[lane] = 1'b1;
            decode_pc[lane*PC_WIDTH +: PC_WIDTH] = PC_WIDTH'(pc);
            decode_flow[lane*FLOW_WIDTH +: FLOW_WIDTH] = '0;
            decode_ex_path[lane*EX_PATH_WIDTH +: EX_PATH_WIDTH] = EX_PATH_WIDTH'(path);
            decode_microop[lane*MICROOP_WIDTH +: MICROOP_WIDTH] = MICROOP_WIDTH'(uop);
            decode_rd[lane*LOG_REG_WIDTH +: LOG_REG_WIDTH] = LOG_REG_WIDTH'(rd);
            decode_writes_rd[lane] = writes_rd;
            decode_rs[(lane*OPERANDS+0)*LOG_REG_WIDTH +: LOG_REG_WIDTH] = LOG_REG_WIDTH'(rs0);
            decode_rs[(lane*OPERANDS+1)*LOG_REG_WIDTH +: LOG_REG_WIDTH] = LOG_REG_WIDTH'(rs1);
        end
    endtask

    task automatic send_decode_bundle;
        begin
            do @(posedge clk); while ((decode_get & decode_valid) != decode_valid);
            @(negedge clk);
            clear_decode();
        end
    endtask

    task automatic check_issue(
        input int port, input int expected_pc, input int expected_rd, input int expected_rs0
    );
        logic [EX_ISSUE_WIDTH-1:0] record;
        begin
            record = issue_data[port*EX_ISSUE_WIDTH +: EX_ISSUE_WIDTH];
            if (record[ISSUE_P_PC +: PC_WIDTH] != PC_WIDTH'(expected_pc))
                $fatal(1, "port %0d: PC expected %0d, got %0d", port, expected_pc,
                       record[ISSUE_P_PC +: PC_WIDTH]);
            if (record[ISSUE_P_RD +: PHY_REG_WIDTH] != PHY_REG_WIDTH'(expected_rd))
                $fatal(1, "PC %0d: destination P%0d expected, got P%0d", expected_pc,
                       expected_rd, record[ISSUE_P_RD +: PHY_REG_WIDTH]);
            if (record[ISSUE_P_RS +: PHY_REG_WIDTH] != PHY_REG_WIDTH'(expected_rs0))
                $fatal(1, "PC %0d: source P%0d expected, got P%0d", expected_pc,
                       expected_rs0, record[ISSUE_P_RS +: PHY_REG_WIDTH]);
        end
    endtask

    task automatic accept_issue_mask(input logic [ISSUE_PORTS-1:0] mask);
        begin
            @(negedge clk);
            issue_get = mask;
            @(posedge clk);
            @(negedge clk);
            issue_get = '0;
        end
    endtask

    task automatic complete_result(input int port, input int pc, input int phy);
        begin
            @(negedge clk);
            result_valid = '0;
            result_data = '0;
            result_valid[port] = 1'b1;
            result_data[port*RESULT_WIDTH +: PC_WIDTH] = PC_WIDTH'(pc);
            result_data[port*RESULT_WIDTH + PC_WIDTH +: FLOW_WIDTH] = '0;
            result_data[port*RESULT_WIDTH + PC_WIDTH + FLOW_WIDTH +: PHY_REG_WIDTH] = PHY_REG_WIDTH'(phy);
            @(posedge clk);
            @(negedge clk);
            result_valid = '0;
            result_data = '0;
        end
    endtask

    initial begin : test_sequence
        int timeout;
        clear_decode();
        fetch_get = '0;
        issue_get = '0;
        result_valid = '0;
        result_data = '0;
        branch_valid = '0;
        branch_data = '0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        reset_n = 1'b1;

        // A: x1 <- x0 (P1), B: x2 <- x1 (P2 waits for P1).
        set_lane(0, 0, 0, 1, 0, 0, 1'b1, 1);
        set_lane(1, 4, 1, 2, 1, 0, 1'b1, 2);
        send_decode_bundle();

        // C is independent (P3); D consumes C's new P3 in the same bundle.
        set_lane(0, 8, 1, 3, 0, 0, 1'b1, 3);
        set_lane(1, 12, 0, 4, 3, 0, 1'b1, 4);
        send_decode_bundle();

        timeout = 0;
        while (!(issue_valid[0] && issue_valid[1])) begin
            @(posedge clk);
            timeout++;
            if (timeout > 20) $fatal(1, "A and C did not become issuable");
        end
        check_issue(0, 0, 1, 0);
        check_issue(1, 8, 3, 0);
        $display("[PASS] independent A/C issued while dependent B/D waited");
        accept_issue_mask(2'b11);

        // Complete younger C first. D must wake; B must remain blocked on A.
        complete_result(0, 8, 3);
        timeout = 0;
        while (!issue_valid[0]) begin
            @(posedge clk);
            timeout++;
            if (issue_valid[1]) $fatal(1, "B issued before A completed");
            if (timeout > 20) $fatal(1, "D did not wake after C completed");
        end
        check_issue(0, 12, 4, 3);
        if (issue_valid[1]) $fatal(1, "B issued before A completed");
        $display("[PASS] C completion woke only D (out-of-order wakeup)");
        accept_issue_mask(2'b01);

        // Complete older A. B can now issue with its renamed source P1.
        complete_result(0, 0, 1);
        timeout = 0;
        while (!issue_valid[1]) begin
            @(posedge clk);
            timeout++;
            if (timeout > 20) $fatal(1, "B did not wake after A completed");
        end
        check_issue(1, 4, 2, 1);
        $display("[PASS] A completion woke B with the correct physical source");
        accept_issue_mask(2'b10);

        // Finish D and B so the ROB can retire the whole dataflow in order.
        @(negedge clk);
        result_valid = 2'b11;
        result_data = '0;
        result_data[0*RESULT_WIDTH +: PC_WIDTH] = PC_WIDTH'(12);
        result_data[0*RESULT_WIDTH + PC_WIDTH + FLOW_WIDTH +: PHY_REG_WIDTH] = PHY_REG_WIDTH'(4);
        result_data[1*RESULT_WIDTH +: PC_WIDTH] = PC_WIDTH'(4);
        result_data[1*RESULT_WIDTH + PC_WIDTH + FLOW_WIDTH +: PHY_REG_WIDTH] = PHY_REG_WIDTH'(2);
        @(posedge clk);
        @(negedge clk);
        result_valid = '0;
        result_data = '0;

        // A taken branch; lane 1 is after the control and must be discarded.
        set_lane(0, 16, 0, 0, 0, 0, 1'b0, 5);
        decode_branch[0] = 1'b1;
        decode_target_pc[0*PC_WIDTH +: PC_WIDTH] = PC_WIDTH'(100);
        set_lane(1, 20, 1, 5, 0, 0, 1'b1, 6);
        send_decode_bundle();
        if (fetch_valid != '0) $fatal(1, "fetch did not pause for unresolved branch");

        timeout = 0;
        while (!issue_valid[0]) begin
            @(posedge clk);
            timeout++;
            if (issue_valid[1]) $fatal(1, "post-branch lane was not discarded");
            if (timeout > 20) $fatal(1, "branch did not issue");
        end
        check_issue(0, 16, 0, 0);
        accept_issue_mask(2'b01);

        @(negedge clk);
        result_valid[0] = 1'b1;
        result_data[0*RESULT_WIDTH +: PC_WIDTH] = PC_WIDTH'(16);
        branch_valid[0] = 1'b1;
        branch_data[0*BRANCH_WIDTH +: PC_WIDTH] = PC_WIDTH'(16);
        branch_data[0*BRANCH_WIDTH + PC_WIDTH +: FLOW_WIDTH] = '0;
        branch_data[0*BRANCH_WIDTH + PC_WIDTH + FLOW_WIDTH] = 1'b1;
        branch_data[0*BRANCH_WIDTH + PC_WIDTH + FLOW_WIDTH + 1 +: PC_WIDTH] = PC_WIDTH'(100);
        @(posedge clk);
        @(negedge clk);
        result_valid = '0;
        result_data = '0;
        branch_valid = '0;
        branch_data = '0;
        #1;
        if (!fetch_valid[0]) $fatal(1, "fetch did not resume after branch result");
        if (fetch_data[0 +: PC_WIDTH] != PC_WIDTH'(100))
            $fatal(1, "branch target expected 100, got %0d", fetch_data[0 +: PC_WIDTH]);
        if (fetch_data[PC_WIDTH +: FLOW_WIDTH] != FLOW_WIDTH'(1))
            $fatal(1, "new flow index expected 1");
        if (issue_valid[1]) $fatal(1, "discarded post-branch instruction reached issue");
        $display("[PASS] branch paused fetch, discarded the trailing lane, and resumed at flow 1 / PC 100");

        repeat (3) @(posedge clk);
        $display("[PASS] EULSUKDO gen3 ordered-behavior test completed");
        $finish;
    end

    initial begin
        #2000;
        $fatal(1, "global timeout");
    end
endmodule
