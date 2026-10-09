`timescale 1ns/1ps

// Exercise PRM with its real BRAM-backed allocator. NEL/IST/WBC/FCL are
// driven at the interface; the scoreboard tracks physical-register lifetimes.
module tb_physical_register_mapper #(
    parameter int DECODE = 2,
    parameter int UPDATES = 5,
    parameter int PHYREGS = 64
);
    localparam int PHY_W = $clog2(PHYREGS);
    localparam int IST_ENTRIES = 16;
    localparam int IST_W = $clog2(IST_ENTRIES);
    localparam int PAIR_W = PHY_W+IST_W;
    localparam int INPUTS = DECODE*2;
    localparam int RETURNS = 4;
    localparam int DONE = 5;

    logic clk = 0, reset_n = 0;
    always #5 clk = ~clk;
    logic [INPUTS-1:0] wait_valid;
    logic [INPUTS*PAIR_W-1:0] wait_data;
    logic [DONE-1:0] done_valid;
    logic [DONE*PHY_W-1:0] done_data;
    logic [RETURNS-1:0] retire_valid;
    logic [RETURNS*PHY_W-1:0] retire_data;
    logic [DECODE-1:0] alloc_valid, alloc_get;
    logic [DECODE*PHY_W-1:0] alloc_data;
    logic [UPDATES-1:0] ready_valid;
    logic [UPDATES*PAIR_W-1:0] ready_data;

    physical_register_mapper #(
        .STRUCT_DECODE_NEW_INST(DECODE), .STRUCT_PRM_ENTRY_UPDATE(UPDATES),
        .STRUCT_PHYREGS(PHYREGS), .STRUCT_INST_STATE_ENTRIES(IST_ENTRIES),
        .STRUCT_PRM_ENTRY_BUFFER(4), .STRUCT_PRM_OUTPUT_FIFO_DEPTH(8)
    ) dut (
        .clk(clk), .reset_n(reset_n),
        .i_ist_wait_phyreg_valid(wait_valid), .i_ist_wait_phyreg_data(wait_data),
        .i_wbc_done_phyreg_valid(done_valid), .i_wbc_done_phyreg_data(done_data),
        .i_fcl_unallocate_phyreg_valid(retire_valid), .i_fcl_unallocate_phyreg_data(retire_data),
        .o_nel_phyreg_valid(alloc_valid), .i_nel_phyreg_get(alloc_get), .o_nel_phyreg_data(alloc_data),
        .o_ist_ready_phyreg_valid(ready_valid), .o_ist_ready_phyreg_data(ready_data)
    );

    bit owned[PHYREGS], retired[PHYREGS], completed[PHYREGS];
    bit waiting[IST_ENTRIES][PHYREGS];
    int outstanding[PHYREGS], allocations[PHYREGS];
    int notifications[IST_ENTRIES], allocation_total, notification_total;
    int phy, entry_num;
    bit duplicate;

    always @(posedge clk) begin
        if (!reset_n) begin
            allocation_total = 0; notification_total = 0;
            for (int p = 0; p < PHYREGS; p++) begin
                owned[p] = 0; retired[p] = 0; completed[p] = (p == 0);
                outstanding[p] = 0; allocations[p] = 0;
                for (int s = 0; s < IST_ENTRIES; s++) waiting[s][p] = 0;
            end
            for (int s = 0; s < IST_ENTRIES; s++) notifications[s] = 0;
            if ((|alloc_valid) || (|ready_valid)) $fatal(1, "PRM transfer during reset");
        end
        else begin
            // Capture one obligation per unique {IST, PHYREG} pair per bundle.
            for (int w = 0; w < INPUTS; w++) begin
                if (wait_valid[w]) begin
                    duplicate = 0;
                    for (int prev = 0; prev < w; prev++) begin
                        if (wait_valid[prev] && (wait_data[prev*PAIR_W +: PAIR_W] == wait_data[w*PAIR_W +: PAIR_W])) duplicate = 1;
                    end
                    if (!duplicate) begin
                        phy = int'(wait_data[w*PAIR_W +: PHY_W]);
                        entry_num = int'(wait_data[w*PAIR_W+PHY_W +: IST_W]);
                        if (waiting[entry_num][phy]) $fatal(1, "Test repeated a pending pair");
                        waiting[entry_num][phy] = 1; outstanding[phy]++;
                    end
                end
            end
            for (int d = 0; d < DONE; d++) begin
                if (done_valid[d]) completed[int'(done_data[d*PHY_W +: PHY_W])] = 1;
            end
            for (int u = 0; u < UPDATES; u++) begin
                if (ready_valid[u]) begin
                    phy = int'(ready_data[u*PAIR_W +: PHY_W]);
                    entry_num = int'(ready_data[u*PAIR_W+PHY_W +: IST_W]);
                    if (!waiting[entry_num][phy] || !completed[phy]) $fatal(1, "Unexpected/early notification IST=%0d PHY=%0d", entry_num, phy);
                    waiting[entry_num][phy] = 0; outstanding[phy]--;
                    notifications[entry_num]++; notification_total++;
                end
            end
            for (int r = 0; r < RETURNS; r++) begin
                if (retire_valid[r]) begin
                    phy = int'(retire_data[r*PHY_W +: PHY_W]);
                    if (phy != 0) begin
                        if (!owned[phy] || retired[phy]) $fatal(1, "Invalid test retirement");
                        retired[phy] = 1;
                    end
                end
            end
            for (int a = 0; a < DECODE; a++) begin
                if (alloc_valid[a] && alloc_get[a]) begin
                    phy = int'(alloc_data[a*PHY_W +: PHY_W]);
                    if ((phy == 0) || (phy >= PHYREGS)) $fatal(1, "Invalid physical number");
                    if (owned[phy] && !retired[phy]) $fatal(1, "Duplicate allocation PHY=%0d", phy);
                    if (outstanding[phy] != 0) $fatal(1, "Recycled before notification delivery PHY=%0d", phy);
                    owned[phy] = 1; retired[phy] = 0; completed[phy] = 0;
                    allocations[phy]++; allocation_total++;
                end
            end
        end
    end

    task automatic step;
        @(posedge clk); #1; @(negedge clk);
    endtask

    task automatic await_offers;
        for (int t = 0; t < 500; t++) begin
            #1;
            if (&alloc_valid) return;
            step();
        end
        $fatal(1, "No allocator offers");
    endtask

    task automatic await_allocations(input int total);
        for (int t = 0; t < 1000; t++) begin
            if (allocation_total == total) return;
            if (allocation_total > total) $fatal(1, "Extra physical numbers");
            step();
        end
        $fatal(1, "Lost physical numbers: expected=%0d got=%0d", total, allocation_total);
    endtask

    task automatic pair(input int lane, input int ist, input int physical_num);
        wait_valid[lane] = 1;
        wait_data[lane*PAIR_W +: PAIR_W] = {IST_W'(ist), PHY_W'(physical_num)};
    endtask

    task automatic done(input int physical_num);
        done_valid = '0; done_valid[0] = 1;
        done_data = '0; done_data[0 +: PHY_W] = PHY_W'(physical_num);
        step(); done_valid = '0;
    endtask

    task automatic await_notifications(input int total);
        for (int t = 0; t < 500; t++) begin
            if (notification_total == total) return;
            if (notification_total > total) $fatal(1, "Repeated notification");
            step();
        end
        $fatal(1, "Lost notifications: expected=%0d got=%0d", total, notification_total);
    endtask

    int before_stall;
    initial begin
        wait_valid = '0; wait_data = '0; done_valid = '0; done_data = '0;
        retire_valid = '0; retire_data = '0; alloc_get = '0;
        repeat (3) step(); reset_n = 1;
        await_offers();
        // A sparse Get must not consume any other offered number.
        alloc_get[DECODE-1] = 1; step(); alloc_get = '0;
        repeat (4) step(); alloc_get = '1;
        await_allocations(PHYREGS-1); repeat (12) step();
        if (|alloc_valid) $fatal(1, "Allocator exceeded its physical pool");
        alloc_get = '0;

        // Return all unused registers so real allocator offers remain available
        // when PRM later masks them. PHYREG 0 must never enter the free pool.
        retire_valid = '1; retire_data = '0; step(); retire_valid = '0;
        for (int p = 4; p < PHYREGS; p += RETURNS) begin
            retire_valid = '0; retire_data = '0;
            for (int r = 0; r < RETURNS; r++) begin
                if (p+r < PHYREGS) begin retire_valid[r] = 1; retire_data[r*PHY_W +: PHY_W] = PHY_W'(p+r); end
            end
            step();
        end
        retire_valid = '0; await_offers();

        // Fill PHYREG 1's four mapping slots; duplicate operand pairs count once.
        for (int s = 0; s < 4; s++) begin
            pair(0, s, 1); pair(1, s, 1);
            step(); wait_valid = '0; step();
        end
        // The next whole bundle cannot fit. One previously renamed Stage 2
        // bundle may still arrive after allocation is stopped.
        pair(0, 4, 1); pair(1, 5, 2); step(); wait_valid = '0;
        pair(0, 6, 1); pair(1, 7, 3); step(); wait_valid = '0;
        #1;
        if ((|alloc_valid) || !(|dut.allocate_valid)) $fatal(1, "PRM did not mask available allocator offers");
        before_stall = allocation_total; alloc_get = '1;
        // FCL uses a pulse. Retirement must remain pending until all input,
        // mapping and output obligations belonging to this lifetime are delivered.
        retire_valid[0] = 1; retire_data[0 +: PHY_W] = PHY_W'(1);
        step(); retire_valid = '0;
        done(2); done(3);
        repeat (5) step();
        if ((allocation_total != before_stall) || (notification_total != 0)) $fatal(1, "Blocked bundle was partially consumed");

        done(1);
        await_notifications(8);
        await_allocations((PHYREGS-1)+(PHYREGS-4)+1);
        alloc_get = '0;
        for (int s = 0; s < 8; s++) if (notifications[s] != 1) $fatal(1, "Lost/duplicate buffered request");
        if ((allocations[1] != 2) || (allocations[2] != 1) || (allocations[3] != 1)) $fatal(1, "Incorrect lifetime reuse");

        // Allocation starts a new lifetime: the old WBC-ready bit must be clear.
        pair(0, 8, 1); step(); wait_valid = '0;
        repeat (8) step();
        if (notification_total != 8) $fatal(1, "Old readiness leaked into new lifetime");
        done(1); await_notifications(9);
        repeat (10) step();
        for (int p = 0; p < PHYREGS; p++) if (outstanding[p] != 0) $fatal(1, "Outstanding notification remains");

        $display("PASS PRM D=%0d U=%0d PHYREGS=%0d", DECODE, UPDATES, PHYREGS);
        $finish;
    end
    initial begin
        #2000000; $fatal(1, "PRM watchdog");
    end
endmodule
