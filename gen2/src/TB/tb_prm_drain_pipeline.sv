`timescale 1ns/1ps

// Public-interface exactly-once scoreboard plus a sequential round-robin
// reference. Exercise reserved rows, notification stalls and in-flight reset.
module tb_prm_drain_pipeline #(
    parameter int PHYREGS = 64,
    parameter int UPDATES = 5
);
    localparam int PW = $clog2(PHYREGS), SW = 4, W = PW+SW;
    logic clk = 0, reset_n = 0;
    always #5 clk = ~clk;
    logic [3:0] wait_valid = 0;
    logic [4*W-1:0] wait_data = 0;
    logic [4:0] done_valid = 0;
    logic [5*PW-1:0] done_data = 0;
    wire [1:0] alloc_valid;
    wire [UPDATES-1:0] ready_valid;
    wire [UPDATES*W-1:0] ready_data;
    physical_register_mapper #(
        .STRUCT_DECODE_NEW_INST(2), .STRUCT_PHYREGS(PHYREGS),
        .STRUCT_INST_STATE_ENTRIES(16), .STRUCT_PRM_ENTRY_UPDATE(UPDATES),
        .STRUCT_PRM_OUTPUT_FIFO_DEPTH(8)
    ) dut (
        .clk(clk), .reset_n(reset_n),
        .i_ist_wait_phyreg_valid(wait_valid), .i_ist_wait_phyreg_data(wait_data),
        .i_wbc_done_phyreg_valid(done_valid), .i_wbc_done_phyreg_data(done_data),
        .i_fcl_unallocate_phyreg_valid('0), .i_fcl_unallocate_phyreg_data('0),
        .o_nel_phyreg_valid(alloc_valid), .i_nel_phyreg_get('0), .o_nel_phyreg_data(),
        .o_ist_ready_phyreg_valid(ready_valid), .o_ist_ready_phyreg_data(ready_data)
    );
    bit pending[16][PHYREGS], completed[PHYREGS];
    int sent = 0, received = 0, selections = 0, held_rows = 0, held_notifications = 0;
    int consecutive = 0, max_consecutive = 0;
    bit previous_row_held = 0, previous_notify_held = 0;
    logic [PW-1:0] previous_row;
    logic [7:0] previous_valid;
    logic [8*W-1:0] previous_data;

    always @(posedge clk) begin
        if (!reset_n) begin
            sent = 0; received = 0; consecutive = 0;
            previous_row_held = 0; previous_notify_held = 0;
            for (int p = 0; p < PHYREGS; p++) begin
                completed[p] = (p == 0);
                for (int s = 0; s < 16; s++) pending[s][p] = 0;
            end
        end else begin
            automatic int expected = -1;
            for (int offset = 0; offset < PHYREGS; offset++) begin
                automatic int p = (int'(dut.drain_start)+offset)%PHYREGS;
                if (expected < 0 && dut.phyreg_ready[p] && dut.mapping_active[p] &&
                    !(dut.drain_valid && int'(dut.drain_phyreg) == p)) expected = p;
            end
            if (dut.drain_select_valid != (expected >= 0) ||
                (expected >= 0 && int'(dut.drain_select_phyreg) != expected))
                $fatal(1, "Round-robin selector differs from sequential reference");
            if (previous_row_held && (!dut.drain_valid || dut.drain_phyreg != previous_row))
                $fatal(1, "Reserved row changed while stalled");
            if (previous_notify_held && (dut.notify_valid !== previous_valid || dut.notify_data !== previous_data))
                $fatal(1, "Held notification bundle changed");
            if (dut.drain_valid && (!dut.mapping_active[dut.drain_phyreg] ||
                !dut.phyreg_ready[dut.drain_phyreg] || dut.drain_count == 0))
                $fatal(1, "Reserved row lost its mapping/readiness");
            previous_row_held = dut.drain_valid && !dut.drain_fire;
            previous_row = dut.drain_phyreg;
            previous_notify_held = (|dut.notify_valid) && !dut.notify_accept;
            previous_valid = dut.notify_valid; previous_data = dut.notify_data;
            if (previous_row_held) held_rows++;
            if (previous_notify_held) held_notifications++;
            if (dut.drain_fire) begin
                selections++; consecutive++;
                if (consecutive > max_consecutive) max_consecutive = consecutive;
            end else consecutive = 0;
            for (int lane = 0; lane < 4; lane++) if (wait_valid[lane]) begin
                automatic int p = int'(wait_data[lane*W +: PW]);
                automatic int s = int'(wait_data[lane*W+PW +: SW]);
                if (pending[s][p]) $fatal(1, "Test reused pending pair");
                pending[s][p] = 1; sent++;
            end
            for (int lane = 0; lane < 5; lane++)
                if (done_valid[lane]) completed[int'(done_data[lane*PW +: PW])] = 1;
            for (int lane = 0; lane < UPDATES; lane++) if (ready_valid[lane]) begin
                automatic int p = int'(ready_data[lane*W +: PW]);
                automatic int s = int'(ready_data[lane*W+PW +: SW]);
                if (!pending[s][p] || !completed[p]) $fatal(1, "Duplicate/early notification");
                pending[s][p] = 0; received++;
            end
        end
    end
    task automatic step;
        @(posedge clk); #1; @(negedge clk);
    endtask
    task automatic fill_rows;
        repeat (30) step();
        for (int p = 1; p < PHYREGS; p++) begin
            while (!(|alloc_valid)) step();
            wait_valid = '1;
            for (int s = 0; s < 4; s++) wait_data[s*W +: W] = {SW'(s), PW'(p)};
            step(); wait_valid = 0;
        end
        repeat (8) step();
    endtask
    task automatic complete_rows;
        for (int p = PHYREGS-1; p > 0; p -= 5) begin
            done_valid = 0;
            for (int lane = 0; lane < 5; lane++) if (p-lane > 0) begin
                done_valid[lane] = 1;
                done_data[lane*PW +: PW] = PW'(p-lane);
            end
            step();
        end
        done_valid = 0;
    endtask
    task automatic await_all;
        for (int t = 0; t < 20*PHYREGS+100; t++) begin
            if (sent == received) begin repeat (20) step(); return; end
            step();
        end
        $fatal(1, "Lost notifications sent=%0d received=%0d", sent, received);
    endtask
    initial begin
        repeat (3) step(); reset_n = 1;
        fill_rows(); complete_rows(); await_all();
        if (selections != PHYREGS-1) $fatal(1, "Row selected more or less than once");
        if (PHYREGS >= 17 && UPDATES >= 4 && max_consecutive < 8)
            $fatal(1, "Drain pipeline did not sustain one row/cycle");
        if (PHYREGS >= 17 && UPDATES == 1 && (held_rows == 0 || held_notifications == 0))
            $fatal(1, "Missing natural output backpressure coverage");
        reset_n = 0; step(); reset_n = 1;
        fill_rows();
        // Reset with a reserved row (and potentially a buffered notification).
        if (UPDATES == 1 && PHYREGS >= 17) begin
            complete_rows();
            while (!(dut.drain_valid && (|dut.notify_valid) && !dut.notify_accept)) step();
        end else begin
            done_valid = 1; done_data = PW'(PHYREGS-1); step(); done_valid = 0;
            while (!dut.drain_valid) step();
        end
        reset_n = 0; step(); reset_n = 1;
        repeat (30) step();
        if (dut.drain_valid || (|dut.notify_valid) || received != 0)
            $fatal(1, "Reset leaked in-flight work");
        // Fresh notifications after reset exercise a newly initialized pipeline.
        fill_rows(); complete_rows(); await_all();
        $display("PASS drain pipeline PHY=%0d U=%0d selections=%0d row_stalls=%0d notify_stalls=%0d max_rows_per_cycle_run=%0d", PHYREGS, UPDATES, selections, held_rows, held_notifications, max_consecutive);
        $finish;
    end
    initial begin #1000000; $fatal(1, "Drain pipeline watchdog"); end
endmodule
