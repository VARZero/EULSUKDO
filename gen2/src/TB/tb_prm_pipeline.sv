`timescale 1ns/1ps

// WBC pulses at every pipeline boundary, including a blocked commit stage.
// Scoreboard checks exactly-once notification from the public interface.
module tb_prm_pipeline #(
    parameter int DECODE = 3,
    parameter int UPDATES = 5,
    parameter int DEPTH = 2
);
    localparam int INPUTS = 2*DECODE;
    localparam int PHY_W = 4, IST_W = 5, PAIR_W = PHY_W+IST_W;
    logic clk = 0, reset_n = 0;
    always #5 clk = ~clk;
    logic [INPUTS-1:0] wait_valid = 0;
    logic [INPUTS*PAIR_W-1:0] wait_data = 0;
    logic [4:0] done_valid = 0;
    logic [5*PHY_W-1:0] done_data = 0;
    wire [DECODE-1:0] alloc_valid;
    wire [UPDATES-1:0] ready_valid;
    wire [UPDATES*PAIR_W-1:0] ready_data;
    physical_register_mapper #(
        .STRUCT_DECODE_NEW_INST(DECODE), .STRUCT_PHYREGS(16),
        .STRUCT_INST_STATE_ENTRIES(32), .STRUCT_PRM_ENTRY_UPDATE(UPDATES),
        .STRUCT_PRM_INPUT_BUFFER_DEPTH(DEPTH), .STRUCT_PRM_OUTPUT_FIFO_DEPTH(8)
    ) dut (
        .clk(clk), .reset_n(reset_n),
        .i_ist_wait_phyreg_valid(wait_valid), .i_ist_wait_phyreg_data(wait_data),
        .i_wbc_done_phyreg_valid(done_valid), .i_wbc_done_phyreg_data(done_data),
        .i_fcl_unallocate_phyreg_valid('0), .i_fcl_unallocate_phyreg_data('0),
        .o_nel_phyreg_valid(alloc_valid), .i_nel_phyreg_get('0), .o_nel_phyreg_data(),
        .o_ist_ready_phyreg_valid(ready_valid), .o_ist_ready_phyreg_data(ready_data)
    );
    bit pending[32][16], completed[16];
    int sent = 0, received = 0;
    always @(posedge clk) begin
        if (!reset_n) begin
            sent = 0; received = 0;
            for (int p = 0; p < 16; p++) begin
                completed[p] = (p == 0);
                for (int s = 0; s < 32; s++) pending[s][p] = 0;
            end
        end else begin
            for (int lane = 0; lane < INPUTS; lane++) begin
                if (wait_valid[lane]) begin
                    automatic int p = int'(wait_data[lane*PAIR_W +: PHY_W]);
                    automatic int s = int'(wait_data[lane*PAIR_W+PHY_W +: IST_W]);
                    automatic bit duplicate = 0;
                    for (int prev = 0; prev < lane; prev++)
                        if (wait_valid[prev] && wait_data[prev*PAIR_W +: PAIR_W] == wait_data[lane*PAIR_W +: PAIR_W]) duplicate = 1;
                    if (!duplicate) begin
                        if (pending[s][p]) $fatal(1, "Test reused pending pair");
                        pending[s][p] = 1; sent++;
                    end
                end
            end
            for (int lane = 0; lane < 5; lane++)
                if (done_valid[lane]) completed[int'(done_data[lane*PHY_W +: PHY_W])] = 1;
            for (int lane = 0; lane < UPDATES; lane++) begin
                if (ready_valid[lane]) begin
                    automatic int p = int'(ready_data[lane*PAIR_W +: PHY_W]);
                    automatic int s = int'(ready_data[lane*PAIR_W+PHY_W +: IST_W]);
                    if (!pending[s][p] || !completed[p]) $fatal(1, "Duplicate/early notification IST=%0d PHY=%0d", s, p);
                    pending[s][p] = 0; received++;
                end
            end
        end
    end
    task automatic step;
        @(posedge clk); #1; @(negedge clk);
    endtask
    task automatic pair(input int lane, input int s, input int p);
        wait_valid[lane] = 1;
        wait_data[lane*PAIR_W +: PAIR_W] = {IST_W'(s), PHY_W'(p)};
    endtask
    task automatic pulse(input int p);
        done_valid = 1; done_data = (5*PHY_W)'(p);
        step(); done_valid = 0;
    endtask
    task automatic drain;
        for (int t = 0; t < 500; t++) begin
            if (received == sent) begin
                repeat (12) step(); // Detect late duplicates too.
                return;
            end
            step();
        end
        $fatal(1, "Lost completion sent=%0d received=%0d", sent, received);
    endtask
    initial begin
        repeat (3) step(); reset_n = 1;
        repeat (30) step();
        // -1: before arrival; 0: input capture; 1: preprocess capture;
        // 2: map commit edge; 3: after map commit. Each pulse lasts one cycle.
        for (int offset = -1; offset <= 3; offset++) begin
            automatic int p = offset+2;
            if (offset == -1) pulse(p);
            for (int lane = 0; lane < INPUTS; lane++) pair(lane, lane%2, p);
            if (offset == 0) begin done_valid = 1; done_data = (5*PHY_W)'(p); end
            step(); wait_valid = 0; done_valid = 0;
            if (offset > 0) begin
                repeat (offset-1) step();
                pulse(p);
            end
            drain();
        end
        // Consecutive bundles to the same PHYREG must use the updated counter.
        for (int s = 0; s < 4; s++) begin
            pair(0, s, 6); step(); wait_valid = 0;
            step();
        end
        repeat (3) step();
        // Head cannot fit. The next bundle remains queued behind it. Complete
        // that later bundle's PHYREG while the head is still blocked.
        pair(0, 4, 6); pair(1, 5, 7); step(); wait_valid = 0;
        pair(0, 6, 8); step(); wait_valid = 0;
        repeat (3) step();
        if (!dut.map_stage_valid || dut.input_fire) $fatal(1, "Missing blocked commit coverage");
        pulse(7); pulse(8);
        repeat (5) step();
        if (!pending[5][7] || !pending[6][8]) $fatal(1, "Bundle bypassed blocked head");
        pulse(6); drain();
        // Reset discards in-flight work as well as the registered grouping.
        pair(0, 9, 9); step(); wait_valid = 0; step();
        if (!dut.map_stage_valid) $fatal(1, "Missing in-flight reset coverage");
        reset_n = 0; step(); reset_n = 1;
        pulse(9); repeat (20) step();
        pair(0, 10, 9); step(); wait_valid = 0; drain();
        if (DEPTH >= 3) begin
            // Full throughput after fill: one new bundle each cycle, including
            // adjacent commits to the same PHYREG (no stale counter snapshot).
            repeat (30) step();
            for (int s = 0; s < 8; s++) begin
                if (!(&alloc_valid)) $fatal(1, "Unnecessary pipeline admission bubble");
                pair(0, s, 10+s/4); step(); wait_valid = 0;
            end
            pulse(10); pulse(11); drain();
        end
        $display("PASS PRM pipeline D=%0d U=%0d depth=%0d WBC offsets=-1..3 blocked-head reset", DECODE, UPDATES, DEPTH);
        $finish;
    end
    initial begin #100000; $fatal(1, "Pipeline watchdog"); end
endmodule
