`timescale 1ns/1ps

// Directed NEL regression; run with DECODE=1, 2 and 3.
// PRM/IST handshakes are driven explicitly to isolate pipeline/rename behavior.
module tb_new_entry_logic #(
    parameter int DECODE = 2
);
    localparam int PC_W = 32;
    localparam int FLOW_W = 3;
    localparam int REG_W = 5;
    localparam int PHY_W = 6;
    localparam int OPERANDS = 2;
    localparam int UOP_W = 5;
    localparam int PATH_W = 2;
    localparam int IMM_W = 32;
    localparam int DONE = 5;
    localparam int PC_FLOW_W = PC_W+FLOW_W;
    localparam int RD_START = PC_FLOW_W+PATH_W+UOP_W+IMM_W;
    localparam int RS_START = RD_START+PHY_W;
    localparam int READY_START = RS_START+OPERANDS*PHY_W;
    localparam int INST_W = READY_START+OPERANDS;
    localparam int RETIRE_W = PC_FLOW_W+PHY_W;

    logic clk = 0;
    logic reset_n = 0;
    always #5 clk = ~clk;

    logic [DECODE-1:0] im_valid, im_get, prm_valid, prm_get, ist_valid, ist_get;
    logic [DECODE*PC_FLOW_W-1:0] im_pc;
    logic [DECODE*PHY_W-1:0] prm_data;
    logic [DONE-1:0] done_valid;
    logic [DONE*PHY_W-1:0] done_data;
    logic [DECODE-1:0] dec_exception, dec_newreg, dec_jump, dec_jump_reg, dec_branch;
    logic [DECODE*PATH_W-1:0] dec_path;
    logic [DECODE*UOP_W-1:0] dec_uop;
    logic [DECODE*REG_W-1:0] dec_rd;
    logic [DECODE*OPERANDS*REG_W-1:0] dec_rs;
    logic [DECODE*IMM_W-1:0] dec_imm;
    logic [DECODE*INST_W-1:0] ist_data;
    logic [DECODE-1:0] retire_valid;
    logic [DECODE*RETIRE_W-1:0] retire_data;
    logic control_valid;
    logic [PC_W+3-1:0] control_data;
    logic [DECODE-1:0] recv_keep;

    new_entry_logic #(
        .STRUCT_DECODE_NEW_INST (DECODE)
    ) dut (
        .clk (clk), .reset_n (reset_n),
        .i_fcl_discard (1'b0), .o_fcl_recv_valid (), .o_fcl_recv_keep (recv_keep),
        .o_fcl_recv_control (), .o_fcl_new_inst_valid (), .o_fcl_new_inst_pc (), .o_fcl_jumpbranch_pc (),
        .i_im_recv_inst_valid (im_valid), .o_im_recv_inst_get (im_get), .i_im_recv_pc (im_pc),
        .i_prm_phyreg_valid (prm_valid), .o_prm_phyreg_get (prm_get), .i_prm_phyreg_data (prm_data),
        .i_wbc_done_phyreg_valid (done_valid), .i_wbc_done_phyreg_data (done_data),
        .i_dec_decode_exception (dec_exception), .i_dec_decode_expath (dec_path),
        .i_dec_decode_microop (dec_uop), .i_dec_decode_rd (dec_rd), .i_dec_decode_newreg (dec_newreg),
        .i_dec_decode_rs (dec_rs), .i_dec_decode_imm (dec_imm),
        .i_dec_decode_jump (dec_jump), .i_dec_decode_jump_reg (dec_jump_reg), .i_dec_decode_branch (dec_branch),
        .o_ist_new_inst_valid (ist_valid), .i_ist_new_inst_get (ist_get), .o_ist_new_inst_data (ist_data),
        .o_fcl_retired_phyreg_valid (retire_valid), .o_fcl_retired_phyreg_data (retire_data),
        .o_fcl_jumpbranch_valid (control_valid), .o_fcl_jumpbranch_data (control_data)
    );

    integer seen [0:63];
    integer allocation_count, control_count;
    // Count externally visible transfers, rather than only inspecting state bits.
    always @(posedge clk) begin
        if (!reset_n) begin
            for (int i = 0; i < 64; i = i+1) seen[i] = 0;
            allocation_count = 0;
            control_count = 0;
        end
        else begin
            for (int i = 0; i < DECODE; i = i+1) begin
                if (ist_valid[i]) seen[ist_data[i*INST_W +: PC_W]/4] = seen[ist_data[i*INST_W +: PC_W]/4]+1;
                if (prm_get[i]) allocation_count = allocation_count+1;
            end
            if (control_valid) control_count = control_count+1;
        end
    end

    task automatic check(input bit condition, input string message);
        if (!condition) $fatal(1, "DECODE=%0d: %s", DECODE, message);
    endtask

    task automatic tick;
        @(posedge clk);
        #1;
    endtask

    task automatic clear_input;
        im_valid = 0;
        im_pc = 0;
        dec_exception = 0;
        dec_path = 0;
        dec_uop = 0;
        dec_rd = 0;
        dec_newreg = 0;
        dec_rs = 0;
        dec_imm = 0;
        dec_jump = 0;
        dec_jump_reg = 0;
        dec_branch = 0;
    endtask

    task automatic offers(input int first);
        for (int i = 0; i < DECODE; i = i+1)
            prm_data[i*PHY_W +: PHY_W] = PHY_W'(first+i);
    endtask

    task automatic instruction(input int lane, input int pc, input int rd, input int rs1, input bit writes_rd);
        im_valid[lane] = 1'b1;
        im_pc[lane*PC_FLOW_W +: PC_FLOW_W] = PC_FLOW_W'(pc);
        dec_rd[lane*REG_W +: REG_W] = REG_W'(rd);
        dec_rs[lane*OPERANDS*REG_W +: REG_W] = REG_W'(rs1);
        dec_newreg[lane] = writes_rd;
    endtask

    function automatic int prd(input int lane);
        return int'(ist_data[lane*INST_W+RD_START +: PHY_W]);
    endfunction

    function automatic int prs(input int lane);
        return int'(ist_data[lane*INST_W+RS_START +: PHY_W]);
    endfunction

    function automatic bit ready1(input int lane);
        return ist_data[lane*INST_W+READY_START];
    endfunction

    task automatic restart;
        reset_n = 0;
        clear_input();
        prm_valid = 0;
        prm_data = 0;
        ist_get = 0;
        done_valid = 0;
        done_data = 0;
        tick();
        tick();
        reset_n = 1;
        prm_valid = '1;
        ist_get = '1;
        offers(10);
    endtask

    initial begin
        // Stage 1 is retained while PRM blocks; Stage 2 drains once, independently.
        restart();
        instruction(0, 0, 1, 0, 1);
        #1; check(im_get == DECODE'(1), "initial input not accepted");
        tick();
        clear_input();
        instruction(0, 4, 2, 1, 1);
        #1; check(prm_get == DECODE'(1), "first rename must allocate with Stage 2 empty");
        tick();
        clear_input();
        instruction(0, 8, 3, 0, 1);
        prm_valid = 0;
        offers(40);
        #1;
        check(ist_valid == DECODE'(1) && prd(0) == 10, "allocated Stage 2 must drain during PRM stall");
        check(prm_get == 0 && im_get == 0 && retire_valid == 0, "stall must have no admission/rename side effects");
        tick();
        done_valid = 1;
        done_data[0 +: PHY_W] = PHY_W'(10);
        #1; check(ist_valid == 0, "consumed Stage 2 repeated during PRM stall");
        tick();
        done_valid = 0;
        tick();
        check(seen[0] == 1 && seen[2] == 0 && allocation_count == 1, "stall duplicated or accepted an instruction");
        clear_input();
        prm_valid = '1;
        offers(20);
        #1;
        check(prm_get == DECODE'(1), "retained Stage 1 did not resume");
        check(retire_valid == 0, "stalled Stage 1 modified the logical map");
        tick();
        #1;
        check(ist_valid == DECODE'(1) && prd(0) == 20 && prs(0) == 10, "retained bundle or source map corrupted");
        check(ready1(0), "WBC completion during stall was lost");
        tick();
        tick();
        check(seen[1] == 1 && seen[2] == 0 && allocation_count == 2, "resume must transfer exactly once");

        // IST backpressure preserves both stages, including partial Get masks.
        restart();
        instruction(0, 0, 1, 0, 1);
        tick();
        clear_input();
        instruction(0, 4, 2, 1, 1);
        tick();
        clear_input();
        offers(20);
        ist_get = '1;
        ist_get[DECODE-1] = 1'b0;
        #1; check(ist_valid == 0 && prm_get == 0, "partial IST Get must not consume a bundle");
        tick();
        tick();
        check(allocation_count == 1 && seen[0] == 0, "IST stall changed allocation or delivery");
        ist_get = '1;
        #1; check(ist_valid == DECODE'(1) && prm_get == DECODE'(1), "simultaneous consume/refill failed");
        tick();
        #1; check(prd(0) == 20 && prs(0) == 10, "IST stall corrupted pending rename");
        tick();
        tick();
        check(seen[0] == 1 && seen[1] == 1 && allocation_count == 2, "IST resume duplicated transfers");

        // No-RD and x0 writes obey global admission permission, without allocating.
        for (int writes = 0; writes < 2; writes = writes+1) begin
            restart();
            instruction(0, 0, 0, 0, 1'(writes));
            tick();
            clear_input();
            prm_valid = 0;
            tick();
            tick();
            check(ist_valid == 0 && allocation_count == 0, "no-RD instruction bypassed PRM stall");
            if (DECODE > 1) begin
                prm_valid = DECODE'(1);
                tick();
                check(ist_valid == 0 && prm_get == 0, "partial PHYREG offers must not admit a bundle");
            end
            prm_valid = '1;
            tick();
            #1; check(ist_valid == DECODE'(1) && prd(0) == 0 && prs(0) == 0 && ready1(0), "x0/no-RD behavior incorrect");
            tick();
            check(allocation_count == 0 && seen[0] == 1, "no-RD/x0 consumed physical registers");
        end

        // Seed x1, then overwrite x1 in every lane. Sources use the nearest older
        // writer and retirement follows the same chain, including three writers.
        restart();
        offers(8);
        instruction(0, 0, 1, 0, 1);
        tick();
        clear_input();
        tick();
        tick();
        offers(10);
        for (int i = 0; i < DECODE; i = i+1) instruction(i, 16+4*i, 1, 1, 1);
        tick();
        clear_input();
        #1;
        check(prm_get == {DECODE{1'b1}} && retire_valid == {DECODE{1'b1}}, "WAW writers must each allocate and retire");
        for (int i = 0; i < DECODE; i = i+1) begin
            check(int'(retire_data[i*RETIRE_W+PC_FLOW_W +: PHY_W]) == ((i == 0)? 8 : 9+i), "incorrect WAW retirement predecessor");
            check(int'(retire_data[i*RETIRE_W +: PC_W]) == 16+4*i, "retirement PC misaligned");
        end
        tick();
        #1;
        for (int i = 0; i < DECODE; i = i+1) begin
            check(prd(i) == 10+i && prs(i) == ((i == 0)? 8 : 9+i), "incorrect nearest older RAW/WAW mapping");
            check(!ready1(i), "allocated WAW source incorrectly marked ready");
        end
        done_valid = 1;
        done_data[0 +: PHY_W] = PHY_W'(8);
        #1; check(ready1(0), "same-cycle WBC bypass missing");
        tick();
        done_valid = 0;
        offers(20);
        instruction(0, 64, 2, 1, 1);
        tick();
        clear_input();
        tick();
        #1; check(prs(0) == 10+DECODE-1, "final logical map must name the last WAW writer");
        tick();
        check(allocation_count == DECODE+2, "WAW allocation count mismatch");

        // Branch truncates the input bundle and emits FCL information only once
        // when it actually advances, including after a PRM stall.
        restart();
        instruction(0, 64, 0, 0, 0);
        dec_branch[0] = 1'b1;
        dec_imm[0 +: IMM_W] = IMM_W'(-4);
        if (DECODE > 1) instruction(1, 68, 3, 0, 1);
        #1; check(im_get == im_valid && recv_keep == DECODE'(1), "branch tail must be consumed without admission");
        tick();
        clear_input();
        instruction(0, 80, 4, 0, 1);
        prm_valid = 0;
        tick();
        check(control_valid == 0 && im_get == 0, "control-flow side effects during stall");
        prm_valid = '1;
        #1;
        check(control_valid && control_data[2:0] == 3'b100 && control_data[3 +: PC_W] == 60, "branch target/flags incorrect");
        check(im_get == 0, "control-flow commit must not capture a stale sequential bundle");
        tick();
        clear_input();
        tick();
        tick();
        check(control_count == 1 && seen[16] == 1 && seen[17] == 0 && seen[20] == 0, "control-flow notification repeated or tail executed");

        $display("PASS: NEL admission, stalls, one-time delivery, no-RD/x0, WBC, RAW/WAW and branch; DECODE=%0d", DECODE);
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "NEL test timeout");
    end
endmodule
