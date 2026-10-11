`timescale 1ns/1ps

// Compare PRM return selection cycle-by-cycle against a simple ascending scan.
// Synthetic FCL traffic deliberately covers arbitrary pending masks; this test
// checks selection/handshake, while scheduler stress checks legal lifetimes.
module tb_prm_return_selection #(
    parameter int PHYREGS = 64,
    parameter int RETURNS = 4
);
    localparam int PHY_W = $clog2(PHYREGS);
    logic clk = 0, reset_n = 0;
    always #5 clk = ~clk;
    logic [RETURNS-1:0] retire_valid = 0;
    logic [RETURNS*PHY_W-1:0] retire_data = 0;
    logic [1:0] alloc_get = 0;
    wire [1:0] alloc_valid;
    wire [2*PHY_W-1:0] alloc_data;
    physical_register_mapper #(
        .STRUCT_PHYREGS(PHYREGS), .STRUCT_UNALLOCATE_PHYREG(RETURNS),
        .STRUCT_INST_STATE_ENTRIES(16), .STRUCT_PRM_OUTPUT_FIFO_DEPTH(8)
    ) dut (
        .clk(clk), .reset_n(reset_n),
        .i_ist_wait_phyreg_valid('0), .i_ist_wait_phyreg_data('0),
        .i_wbc_done_phyreg_valid('0), .i_wbc_done_phyreg_data('0),
        .i_fcl_unallocate_phyreg_valid(retire_valid), .i_fcl_unallocate_phyreg_data(retire_data),
        .o_nel_phyreg_valid(alloc_valid), .i_nel_phyreg_get(alloc_get), .o_nel_phyreg_data(alloc_data),
        .o_ist_ready_phyreg_valid(), .o_ist_ready_phyreg_data()
    );

    bit [PHYREGS-1:0] pending = 0, next_pending;
    bit [RETURNS-1:0] expected_valid;
    bit [RETURNS*PHY_W-1:0] expected_data;
    int count, phy, accepted = 0, stalled = 0, saturated = 0;
    int unsigned random_state = 32'h1a2b3c4d;
    function automatic int unsigned random_word();
        random_state ^= random_state << 13;
        random_state ^= random_state >> 17;
        random_state ^= random_state << 5;
        return random_state;
    endfunction

    always @(posedge clk) begin
        if (!reset_n) pending = 0;
        else begin
            if (dut.retired_pending !== pending) $fatal(1, "Pending bitmap mismatch");
            next_pending = pending;
            for (int r = 0; r < RETURNS; r++) begin
                phy = int'(retire_data[r*PHY_W +: PHY_W]);
                if (retire_valid[r] && phy != 0) next_pending[phy] = 1;
            end
            count = 0; expected_valid = 0; expected_data = 0;
            for (int p = 1; p < PHYREGS; p++) begin
                if (pending[p] && count < RETURNS) begin
                    expected_valid[count] = 1;
                    expected_data[count*PHY_W +: PHY_W] = PHY_W'(p);
                    if (dut.unallocate_ready[count]) begin
                        next_pending[p] = 0;
                        accepted++;
                    end
                    else stalled++;
                    count++;
                end
            end
            if (count == RETURNS) saturated++;
            if (dut.unallocate_valid !== expected_valid || dut.unallocate_data !== expected_data)
                $fatal(1, "Return order/data mismatch N=%0d R=%0d pending=%h", PHYREGS, RETURNS, pending);
            pending = next_pending;
        end
    end

    task automatic step;
        @(posedge clk); #1; @(negedge clk);
    endtask

    initial begin
        repeat (3) step(); reset_n = 1;
        // Fill the pending bitmap while allocation is blocked, including the
        // partial last group, PHYREG 0, and the final real PHYREG.
        for (int p = 0; p < PHYREGS; p++) begin
            retire_valid = 1; retire_data = PHY_W'(p); step();
        end
        for (int cycle = 0; cycle < 1200; cycle++) begin
            alloc_get = (cycle % 100 < 70) ? 2'b00 : 2'(random_word());
            retire_valid = RETURNS'(random_word());
            for (int r = 0; r < RETURNS; r++)
                retire_data[r*PHY_W +: PHY_W] = PHY_W'(random_word() % PHYREGS);
            step();
        end
        retire_valid = 0; alloc_get = '1;
        repeat (PHYREGS*4+100) step();
        if (pending != 0 || dut.retired_pending != 0) $fatal(1, "Returns did not drain");
        if (accepted == 0 || stalled == 0) $fatal(1, "Missing acceptance/stall coverage");
        if (PHYREGS > RETURNS && saturated == 0) $fatal(1, "Missing full-width selection coverage");
        $display("PASS return selection N=%0d R=%0d accepted=%0d stalled=%0d saturated=%0d", PHYREGS, RETURNS, accepted, stalled, saturated);
        $finish;
    end
    initial begin #200000; $fatal(1, "Watchdog"); end
endmodule
