`timescale 1ns/1ps
module tb_load_store_queue #(
    parameter int DEPTH = 7,
    parameter int ORDERS = 2,
    parameter int LANES = 3,
    parameter int SEED = 17
);
    localparam int TAG = 36, INST = 64, TOTAL = 160;
    logic clk = 0, reset_n = 0;
    always #5 clk = ~clk;
    logic [ORDERS-1:0] order_valid;
    logic [ORDERS*TAG-1:0] order_tag;
    wire order_ready;
    logic [LANES-1:0] ready_valid, ex_get;
    wire [LANES-1:0] ready_get, ex_valid;
    logic [LANES*INST-1:0] ready_data;
    wire [LANES*INST-1:0] ex_data;
    logic [1:0] done_valid;
    logic [2*TAG-1:0] done_tag;
    bit queued[TOTAL];
    int admitted, completed, issued, active, cycles, rotations, full_cycles, stall_cycles;
    logic [31:0] rng;
    logic held;
    logic [LANES-1:0] held_valid;
    logic [LANES*INST-1:0] held_data;

    load_store_queue #(.TAG_WIDTH(TAG), .INST_WIDTH(INST), .ORDER_CHANNELS(ORDERS),
        .READY_CHANNELS(LANES), .DONE_CHANNELS(2), .DEPTH(DEPTH)) dut (
        .clk(clk), .reset_n(reset_n), .i_order_valid(order_valid), .i_order_tag(order_tag),
        .o_order_ready(order_ready), .i_ready_valid(ready_valid), .o_ready_get(ready_get),
        .i_ready_data(ready_data), .o_ex_valid(ex_valid), .i_ex_get(ex_get), .o_ex_data(ex_data),
        .i_done_valid(done_valid), .i_done_tag(done_tag)
    );
    function automatic logic [TAG-1:0] tag(input int id);
        // Four adjacent commands have the SAME full PC but DIFFERENT windows.
        return {4'(id%4), 32'h81230000+32'(4*(id/4))};
    endfunction
    function automatic logic [INST-1:0] payload(input int id);
        return {28'(id ^ 'h5a12), tag(id)};
    endfunction
    function automatic int random_word();
        rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5;
        return int'(rng & 32'h7fffffff);
    endfunction
    task automatic clear_inputs;
        order_valid = '0; order_tag = '0; ready_valid = '0; ready_data = '0;
        ex_get = '0; done_valid = '0; done_tag = '0;
    endtask
    task automatic tick;
        @(posedge clk); @(negedge clk);
    endtask
    task automatic offer_ready(input int id);
        ready_valid = '0; ready_data = '0;
        ready_valid[id%LANES] = 1;
        ready_data[(id%LANES)*INST +: INST] = payload(id);
        do begin
            @(posedge clk);
            if (ready_get[id%LANES]) break;
        end while (1);
        @(negedge clk); ready_valid = '0;
    endtask
    task automatic wait_issue_candidate;
        for (int t = 0; t < 4*DEPTH+10; t++) begin
            if (|ex_valid) return;
            tick();
        end
        $fatal(1, "No candidate completed=%0d admitted=%0d", completed, admitted);
    endtask

    // Independent order/payload scoreboard, including early/unrelated completion
    // rejection and zero-latency acceptance+completion on the same edge.
    always @(posedge clk) begin : scoreboard
        int n, id;
        bit matched;
        if (!reset_n) begin
            admitted = 0; completed = 0; issued = 0; active = -1; cycles = 0;
            rotations = 0; full_cycles = 0; stall_cycles = 0; held = 0;
            held_valid = '0; held_data = '0;
            for (int i = 0; i < TOTAL; i++) queued[i] = 0;
        end else begin
            cycles++;
            if (held && (ex_valid != held_valid || ex_data != held_data))
                $fatal(1, "LSQ output changed under backpressure");
            held = |ex_valid && !(|(ex_valid & ex_get));
            held_valid = ex_valid; held_data = ex_data;
            if (held) stall_cycles++;
            if (dut.rotate) rotations++;
            if (int'(dut.upper_count) == DEPTH) full_cycles++;
            for (int d = 0; d < ORDERS; d++) if (order_valid[d]) begin
                if (!order_ready || order_tag[d*TAG +: TAG] != tag(admitted))
                    $fatal(1, "Bad test order admission");
                admitted++;
            end
            for (int e = 0; e < LANES; e++) if (ready_valid[e] && ready_get[e]) begin
                id = int'(ready_data[e*INST+TAG +: 28]) ^ 'h5a12;
                if (id >= admitted || queued[id]) $fatal(1, "Bad ready transfer");
                queued[id] = 1;
            end
            n = 0;
            for (int e = 0; e < LANES; e++) if (ex_valid[e] && ex_get[e]) begin
                if (active != -1 || !queued[completed] || ex_data[e*INST +: INST] != payload(completed)
                    || e != completed%LANES) $fatal(1, "Early, unordered or corrupted issue expected=%0d", completed);
                active = completed; issued++; n++;
            end
            if (n > 1) $fatal(1, "Multiple memory issues");
            matched = 0;
            if (active != -1) begin
                for (int d = 0; d < 2; d++)
                    matched |= done_valid[d] && done_tag[d*TAG +: TAG] == tag(active);
                if (matched) begin completed++; active = -1; end
            end
            if (cycles > 20000) $fatal(1, "LSQ watchdog admitted=%0d completed=%0d", admitted, completed);
        end
    end

    initial begin : stimulus
        int batch, start_id, old_completed, selected;
        rng = SEED;
        clear_inputs();
        repeat (3) @(negedge clk);
        reset_n = 1;
        // Fill all lower reservations, including sparse and multiple lanes.
        while (admitted < DEPTH) begin
            batch = admitted == 0 && DEPTH%ORDERS != 0 ? DEPTH%ORDERS : ORDERS;
            start_id = admitted;
            for (int d = 0; d < batch; d++) begin
                order_valid[d] = 1; order_tag[d*TAG +: TAG] = tag(start_id+d);
            end
            tick(); order_valid = '0;
        end
        if (order_ready) $fatal(1, "Full lower FIFO admitted a bundle");
        // Younger commands first. Oldest must still have a reserved upper slot.
        for (int id = DEPTH-1; id >= 0; id--) offer_ready(id);
        for (int id = 0; id < DEPTH; id++) begin
            wait_issue_candidate();
            old_completed = completed;
            // A completion before EX acceptance must not pop either head.
            done_valid = 1; done_tag[0 +: TAG] = tag(id); tick(); done_valid = '0;
            if (completed != old_completed) $fatal(1, "Premature completion accepted");
            repeat (3) tick();
            ex_get = '1;
            if (id == DEPTH-1) begin
                done_valid = 2; done_tag[TAG +: TAG] = tag(id);
            end
            tick(); ex_get = '0; done_valid = '0;
            if (id != DEPTH-1) begin
                // Same PC, wrong window: compare the FULL tag on completion.
                done_valid = 1; done_tag[0 +: TAG] = tag(id) ^ (TAG'(1) << 32);
                repeat (4) tick();
                if (completed != old_completed || (|ex_valid)) $fatal(1, "Wrong completion or duplicate issue");
                done_valid = 2; done_tag[TAG +: TAG] = tag(id); tick(); done_valid = '0;
            end
        end
        tick();
        if (completed != DEPTH || issued != DEPTH || dut.order_count != 0 || dut.upper_count != 0)
            $fatal(1, "Directed drain mismatch");
        if (full_cycles == 0 || stall_cycles == 0 || (DEPTH > 1 && rotations == 0))
            $fatal(1, "Missing full/rotation/stall coverage");

        // Random admissions, newest-first readiness, completion delays and EX
        // stalls. Repeated fill/drain wraps non-power-of-two pointers many times.
        while (completed < TOTAL) begin
            clear_inputs();
            if (order_ready && admitted < TOTAL && random_word()%4 != 0) begin
                selected = admitted;
                for (int d = 0; d < ORDERS; d++) begin
                    if (selected < TOTAL && random_word()%3 != 0) begin
                        order_valid[d] = 1; order_tag[d*TAG +: TAG] = tag(selected); selected++;
                    end
                end
            end
            for (int id = admitted-1; id >= completed; id--) begin
                if (!queued[id] && !ready_valid[id%LANES] && random_word()%3 != 0) begin
                    ready_valid[id%LANES] = 1;
                    ready_data[(id%LANES)*INST +: INST] = payload(id);
                end
            end
            for (int e = 0; e < LANES; e++) ex_get[e] = random_word()%3 != 0;
            done_valid = 1; done_tag[0 +: TAG] = '1; // unrelated result
            if (active >= 0 && random_word()%5 == 0) begin
                done_valid[1] = 1; done_tag[TAG +: TAG] = tag(active);
            end
            tick();
        end
        clear_inputs(); repeat (3) tick();
        if (issued != TOTAL || dut.order_count != 0 || dut.upper_count != 0) $fatal(1, "Random drain mismatch");

        // Reset with an accepted, unfinished command. No stale issue afterward.
        reset_n = 0; tick(); reset_n = 1;
        order_valid = 1; order_tag[0 +: TAG] = tag(0); tick(); order_valid = '0;
        offer_ready(0); wait_issue_candidate(); ex_get = '1; tick(); ex_get = '0;
        if (!dut.in_flight) $fatal(1, "Reset test did not start a command");
        reset_n = 0; clear_inputs(); tick(); reset_n = 1; repeat (3) tick();
        if ((|ex_valid) || dut.order_count != 0 || dut.upper_count != 0) $fatal(1, "Reset failed");
        $display("PASS LSQ DEPTH=%0d ORDERS=%0d LANES=%0d", DEPTH, ORDERS, LANES);
        $finish;
    end
endmodule
