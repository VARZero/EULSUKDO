`timescale 1ns/1ps

module tb_allocator #(
    parameter int ENTRIES = 17,
    parameter int START_VALUE = 0,
    parameter int ALLOCATE_CHANNEL = 2,
    parameter int UNALLOCATE_CHANNEL = 5,
    parameter int USE_BRAM = 0
);
    localparam int ID_W = (START_VALUE+ENTRIES > 1)? $clog2(START_VALUE+ENTRIES) : 1;
    logic clk = 0, reset_n = 0, flush = 0;
    always #5 clk = ~clk;
    logic [ALLOCATE_CHANNEL-1:0] take, valid;
    logic [ALLOCATE_CHANNEL*ID_W-1:0] data;
    logic [UNALLOCATE_CHANNEL-1:0] give, ready;
    logic [UNALLOCATE_CHANNEL*ID_W-1:0] give_data;
    int expected[$];
    bit owned[ENTRIES];
    bit selected[ENTRIES];
    int allocated, returned, target;
    logic [31:0] rng = 32'h12345678;

    allocator #(
        .ENTRIES(ENTRIES), .START_VALUE(START_VALUE),
        .ALLOCATE_CHANNEL(ALLOCATE_CHANNEL), .UNALLOCATE_CHANNEL(UNALLOCATE_CHANNEL), .USE_BRAM(USE_BRAM != 0)
    ) dut (
        .clk(clk), .reset_n(reset_n), .i_flush(flush),
        .i_allocate(take), .o_allocate_valid(valid), .o_allocate_data(data),
        .i_unallocate(give), .o_unallocate_ready(ready), .i_unallocate_data(give_data)
    );

    always @(posedge clk) begin
        if (!reset_n || flush) begin
            if ((|valid) || (|ready)) $fatal(1, "Allocator offers during reset/flush");
            expected.delete(); allocated = 0; returned = 0;
            for (int n = 0; n < ENTRIES; n++) begin
                expected.push_back(START_VALUE+n); owned[n] = 0;
            end
        end
        else begin
            // Compare every offered lane with the ordered reference free list.
            for (int a = 0; a < ALLOCATE_CHANNEL; a++) begin
                if (valid[a]) begin
                    if ((a >= expected.size()) || (int'(data[a*ID_W +: ID_W]) != expected[a]))
                        $fatal(1, "Wrong allocation lane=%0d data=%0d free=%0d", a, data[a*ID_W +: ID_W], expected.size());
                    if ((a > 0) && !valid[a-1]) $fatal(1, "Non-prefix offer");
                end
            end
            // Sparse Get consumes only the selected numbers; retain other lanes.
            for (int a = ALLOCATE_CHANNEL-1; a >= 0; a--) begin
                if (take[a] && valid[a]) begin
                    target = int'(data[a*ID_W +: ID_W])-START_VALUE;
                    if ((target < 0) || (target >= ENTRIES) || owned[target]) $fatal(1, "Duplicate/out-of-range allocation");
                    owned[target] = 1; allocated++; expected.delete(a);
                end
            end
            for (int u = 0; u < UNALLOCATE_CHANNEL; u++) begin
                if (give[u] && ready[u]) begin
                    target = int'(give_data[u*ID_W +: ID_W])-START_VALUE;
                    if ((target < 0) || (target >= ENTRIES) || !owned[target]) $fatal(1, "Invalid test return");
                    owned[target] = 0; returned++; expected.push_back(START_VALUE+target);
                end
            end
        end
    end

    task automatic step;
        @(posedge clk); #1; @(negedge clk);
    endtask

    function automatic int random_word;
        rng = rng ^ (rng << 13); rng = rng ^ (rng >> 17); rng = rng ^ (rng << 5);
        return int'(rng & 32'h7fffffff);
    endfunction

    task automatic return_owned(input bit random_mask);
        int chosen;
        give = '0; give_data = '0;
        for (int n = 0; n < ENTRIES; n++) selected[n] = 0;
        for (int u = 0; u < UNALLOCATE_CHANNEL; u++) begin
            chosen = -1;
            for (int n = 0; n < ENTRIES; n++) begin
                if (owned[n] && !selected[n] && (chosen < 0)) chosen = n;
            end
            if ((chosen >= 0) && (!random_mask || ((random_word()%3) != 0))) begin
                give[u] = 1; give_data[u*ID_W +: ID_W] = ID_W'(START_VALUE+chosen); selected[chosen] = 1;
            end
        end
    endtask

    task automatic drain_all;
        take = '1; give = '0;
        for (int t = 0; t < ENTRIES*10+100; t++) begin
            if (expected.size() == 0) begin
                repeat (12) step();
                if (|valid) $fatal(1, "Allocator not empty after all numbers allocated");
                take = '0; return;
            end
            step();
        end
        $fatal(1, "Allocator lost numbers: %0d unavailable free IDs", expected.size());
    endtask

    task automatic refill_all;
        take = '0;
        for (int t = 0; t < ENTRIES*10+100; t++) begin
            if (expected.size() == ENTRIES) begin
                give = '0; repeat (20) step(); return;
            end
            return_owned(0); step();
        end
        $fatal(1, "Returns did not complete");
    endtask

    initial begin
        take = '0; give = '0; give_data = '0;
        repeat (3) step(); reset_n = 1;
        // Stall longer than initialization: this reproduced the original loss.
        repeat (ENTRIES*2+30) step();
        for (int round_idx = 0; round_idx < 4; round_idx++) begin
            drain_all(); refill_all();
        end
        for (int cycle = 0; cycle < 1000; cycle++) begin
            for (int a = 0; a < ALLOCATE_CHANNEL; a++) take[a] = 1'((random_word()%3) != 0);
            return_owned(1); step();
        end
        take = '0; give = '0;
        refill_all(); drain_all();
        // Flush an occupied allocator and then interrupt initialization itself.
        flush = 1; take = '1; give = '1; step();
        flush = 0; take = '0; give = '0; step();
        flush = 1; step(); flush = 0;
        repeat (ENTRIES*2+30) step(); drain_all(); refill_all();
        if (expected.size() != ENTRIES) $fatal(1, "Capacity not recovered");
        $display("PASS allocator N=%0d START=%0d A=%0d U=%0d BRAM=%0d", ENTRIES, START_VALUE, ALLOCATE_CHANNEL, UNALLOCATE_CHANNEL, USE_BRAM);
        $finish;
    end
    initial begin
        #2000000; $fatal(1, "Allocator watchdog");
    end
endmodule
