`timescale 1ns/1ps

module tb_flow_control_logic #(
    parameter int DECODE = 3,
    parameter int WINDOWS = 3,
    parameter int RANGE = 5,
    parameter int PC_STEP = 4
);
    localparam int FLOW_W = (WINDOWS > 1)? $clog2(WINDOWS) : 1;
    localparam int TAG_W = 32+FLOW_W;
    localparam int RET_W = TAG_W+6;
    localparam int BR_W = TAG_W+32;
    localparam int DONE = 5;
    localparam int RETURNS = 2;
    logic clk = 0, reset_n = 0;
    always #5 clk = ~clk;
    logic [DECODE-1:0] req_valid, req_get, recv_valid, recv_keep, new_valid, retired_valid;
    logic [DECODE*TAG_W-1:0] req_data, new_pc;
    logic [DECODE*RET_W-1:0] retired_data;
    logic recv_control, discard, control_valid;
    logic [34:0] control_data;
    logic [TAG_W-1:0] control_pc;
    logic [DONE-1:0] done_valid;
    logic [DONE*TAG_W-1:0] done_data;
    logic [1:0] branch_valid;
    logic [2*BR_W-1:0] branch_data;
    logic [RETURNS-1:0] free_valid;
    logic [RETURNS*6-1:0] free_data;
    logic [TAG_W-1:0] fetched[DECODE], history[WINDOWS*RANGE];
    int bundle_size, next_register, return_count;
    int expected_returns[$];
    int expected_reg;

    flow_control_logic #(
        .STRUCT_DECODE_NEW_INST(DECODE), .STRUCT_FLOW_WINDOWS(WINDOWS),
        .STRUCT_FLOW_PC_MAX_RANGE(RANGE), .IS_INST_PC_STEP(PC_STEP),
        .STRUCT_EX_BRANCH(2), .STRUCT_UNALLOCATE_PHYREG(RETURNS)
    ) dut (
        .clk(clk), .reset_n(reset_n),
        .i_nel_recv_valid(recv_valid), .i_nel_recv_keep(recv_keep), .i_nel_recv_control(recv_control),
        .o_nel_discard(discard), .i_nel_new_inst_valid(new_valid), .i_nel_new_inst_pc(new_pc),
        .i_wbc_done_pc_valid(done_valid), .i_wbc_done_pc_data(done_data),
        .i_wbc_branch_valid(branch_valid), .i_wbc_branch_data(branch_data),
        .i_nel_jumpbranch_valid(control_valid), .i_nel_jumpbranch_data(control_data), .i_nel_jumpbranch_pc(control_pc),
        .i_nel_retired_phyreg_valid(retired_valid), .i_nel_retired_phyreg_data(retired_data),
        .o_im_req_pc_valid(req_valid), .i_im_req_pc_get(req_get), .o_im_req_pc(req_data),
        .o_prm_unallocate_phyreg_valid(free_valid), .o_prm_unallocate_phyreg_data(free_data)
    );

    always @(posedge clk) begin
        if (!reset_n) begin
            expected_returns.delete(); return_count = 0;
            if ((|req_valid) || (|free_valid)) $fatal(1, "FCL transfer during reset");
        end
        else begin
            for (int d = 0; d < DECODE; d++) begin
                if (retired_valid[d] && (retired_data[d*RET_W+TAG_W +: 6] != 0))
                    expected_returns.push_back(int'(retired_data[d*RET_W+TAG_W +: 6]));
            end
            for (int r = 0; r < RETURNS; r++) begin
                if (free_valid[r]) begin
                    if (expected_returns.size() == 0) $fatal(1, "Extra register return");
                    expected_reg = expected_returns.pop_front();
                    if (int'(free_data[r*6 +: 6]) != expected_reg) $fatal(1, "Window return order corrupted");
                    return_count++;
                end
            end
        end
    end

    task automatic step;
        @(posedge clk); #1; @(negedge clk);
    endtask
    task automatic restart;
        reset_n = 0; req_get = '0; recv_valid = '0; recv_keep = '0; recv_control = 0;
        new_valid = '0; new_pc = '0; retired_valid = '0; retired_data = '0;
        control_valid = 0; control_data = '0; control_pc = '0;
        done_valid = '0; done_data = '0; branch_valid = '0; branch_data = '0;
        next_register = 1;
        repeat (3) step(); reset_n = 1;
    endtask
    task automatic fetch(input int wanted_pc, input int wanted_flow);
        logic [DECODE-1:0] mask;
        logic [DECODE*TAG_W-1:0] stable_data;
        bit found;
        found = 0;
        for (int t = 0; t < 200; t++) begin
            if (|req_valid) begin found = 1; break; end
            step();
        end
        if (!found) $fatal(1, "Fetch stalled PC=%0d", wanted_pc);
        mask = req_valid; stable_data = req_data; bundle_size = $countones(mask);
        for (int d = 0; d < bundle_size; d++) begin
            fetched[d] = req_data[d*TAG_W +: TAG_W];
            if (fetched[d] != {FLOW_W'(wanted_flow), 32'(wanted_pc+d*PC_STEP)}) $fatal(1, "Wrong flow/PC request");
        end
        repeat (3) begin
            step();
            if ((req_valid != mask) || (req_data != stable_data)) $fatal(1, "Request changed under backpressure");
        end
        // Accept the last lane first; all other offers must remain unchanged.
        req_get = '0; req_get[bundle_size-1] = 1;
        step(); mask[bundle_size-1] = 0;
        if ((req_valid != mask) || (req_data != stable_data)) $fatal(1, "Partial request handshake lost a lane");
        req_get = '1; step(); req_get = '0;
    endtask
    task automatic admit(input bit control, input logic [2:0] flags, input int target);
        recv_valid = '0; recv_keep = '0;
        for (int d = 0; d < bundle_size; d++) begin
            recv_valid[d] = 1; recv_keep[d] = !control || (d == 0);
        end
        recv_control = control; step(); recv_valid = '0; recv_keep = '0; recv_control = 0;
        repeat (2) step();
        if (|req_valid) $fatal(1, "Fetch advanced before rename");
        new_valid = '0; retired_valid = '0; new_pc = '0; retired_data = '0;
        for (int d = 0; d < (control ? 1 : bundle_size); d++) begin
            new_valid[d] = 1; new_pc[d*TAG_W +: TAG_W] = fetched[d];
            retired_valid[d] = 1;
            retired_data[d*RET_W +: RET_W] = {6'(next_register), fetched[d]}; next_register++;
        end
        control_valid = control; control_pc = fetched[0]; control_data = {32'(target), flags};
        step(); new_valid = '0; retired_valid = '0; control_valid = 0;
    endtask
    task automatic complete(input logic [TAG_W-1:0] tag);
        done_valid = '0; done_valid[0] = 1; done_data = '0; done_data[0 +: TAG_W] = tag;
        step(); done_valid = '0;
    endtask
    task automatic await_returns(input int count);
        for (int t = 0; t < 500; t++) begin
            if (return_count == count) return;
            step();
        end
        $fatal(1, "Lost retirement entries wanted=%0d got=%0d", count, return_count);
    endtask

    int filled;
    logic [TAG_W-1:0] saved_control;
    initial begin
        restart();
        for (int w = 0; w < WINDOWS; w++) begin
            filled = 0;
            while (filled < RANGE) begin
                fetch((w*RANGE+filled)*PC_STEP, w);
                for (int d = 0; d < bundle_size; d++) history[w*RANGE+filled+d] = fetched[d];
                filled += bundle_size; admit(0, 0, 0);
            end
        end
        repeat (6) step();
        if (|req_valid) $fatal(1, "Reused an occupied flow ID");
        for (int w = WINDOWS-1; w > 0; w--) begin
            for (int s = 0; s < RANGE; s++) complete(history[w*RANGE+s]);
        end
        // Duplicate completion lanes must not count as additional instructions.
        for (int s = 0; s < RANGE-1; s++) complete(history[s]);
        if (RANGE > 1) begin
            done_valid = '1;
            for (int d = 0; d < DONE; d++) done_data[d*TAG_W +: TAG_W] = history[0];
            step(); done_valid = '0;
        end
        repeat (8) step();
        if (return_count != 0) $fatal(1, "Retired before the oldest window completed");
        complete(history[RANGE-1]); await_returns(WINDOWS*RANGE);
        fetch(WINDOWS*RANGE*PC_STEP, 0);
        saved_control = fetched[0]; admit(1, 3'b001, 256);
        complete(saved_control); await_returns(WINDOWS*RANGE+1);
        fetch(256, (WINDOWS > 1) ? 1 : 0);

        // Conditional branch (not taken) and jump-register resolved by EX.
        // Resolve before all discarded responses arrive to test retained redirect.
        for (int kind = 0; kind < 2; kind++) begin
            restart(); fetch(0, 0); saved_control = fetched[0];
            recv_valid = DECODE'(1); recv_keep = DECODE'(1); recv_control = 1;
            step(); recv_valid = '0; recv_keep = '0; recv_control = 0;
            new_valid = DECODE'(1); new_pc[0 +: TAG_W] = saved_control;
            // No retired register: this instruction still participates in completion.
            control_valid = 1; control_pc = saved_control;
            control_data = {32'd1024, (kind == 0 ? 3'b100 : 3'b010)};
            step(); new_valid = '0; control_valid = 0;
            branch_valid = 2'b10;
            branch_data[BR_W +: BR_W] = {32'd999, (saved_control ^ TAG_W'(PC_STEP))};
            step(); branch_valid = '0;
            repeat (3) step();
            if (|req_valid) $fatal(1, "Wrong branch identity released fetch");
            branch_valid = 2'b10;
            branch_data[BR_W +: BR_W] = {32'(kind == 0 ? PC_STEP : 512), saved_control};
            step(); branch_valid = '0;
            complete(saved_control);
            if (bundle_size > 1) begin
                repeat (3) step();
                if (!discard || (|req_valid)) $fatal(1, "Discarded responses were not awaited");
                recv_valid = '0;
                for (int d = 1; d < bundle_size; d++) recv_valid[d] = 1;
                step(); recv_valid = '0;
            end
            fetch(kind == 0 ? PC_STEP : 512, (WINDOWS > 1) ? 1 : 0);
            if (return_count != 0) $fatal(1, "No-RD control returned a register");
        end
        $display("PASS FCL D=%0d WINDOWS=%0d RANGE=%0d STEP=%0d", DECODE, WINDOWS, RANGE, PC_STEP);
        $finish;
    end
    initial begin
        #2000000; $fatal(1, "FCL watchdog");
    end
endmodule
