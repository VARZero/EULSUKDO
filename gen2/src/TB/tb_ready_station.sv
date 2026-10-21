`timescale 1ns/1ps

module tb_ready_station #(
    parameter int DECODE = 2,
    parameter int UPDATES = 5,
    parameter int ENTRIES = 128,
    parameter int RS_FIFO = ENTRIES,
    parameter int ISSUE = 5
);
    localparam int INPUTS = DECODE+ISSUE;
    localparam int WIDTH = 92;
    localparam int PATH_OFFSET = 35;
    localparam int READS[3] = '{1, 3, 1};
    localparam int OFFSETS[3] = '{0, 1, 4};
    logic clk = 0, reset_n = 0;
    always #5 clk = ~clk;
    logic [INPUTS-1:0] in_valid, in_get;
    logic [INPUTS*WIDTH-1:0] in_data;
    logic [4:0] out_valid, out_get;
    logic [5*WIDTH-1:0] out_data;
    typedef logic [WIDTH-1:0] instruction_t;
    localparam int MODEL_DEPTH = 100000;
    instruction_t expected[MODEL_DEPTH];
    bit live[MODEL_DEPTH];
    logic [4:0] held;
    instruction_t held_data[5];
    int serial = 1, accepted = 0, removed = 0, stalled = 0;
    logic [31:0] rng = 32'h42cafe13;

    ready_station #(
        .STRUCT_DECODE_NEW_INST(DECODE), .STRUCT_PRM_ENTRY_UPDATE(UPDATES),
        .STRUCT_IST_ISSUE_WIDTH(ISSUE),
        .STRUCT_INST_STATE_ENTRIES(ENTRIES),
        .STRUCT_RS_FIFO_WIDTH(RS_FIFO)
    ) dut (
        .clk(clk), .reset_n(reset_n),
        .i_ist_ready_inst_valid(in_valid), .o_ist_ready_inst_get(in_get),
        .i_ist_ready_inst_data(in_data), .o_ex_wait_inst_valid(out_valid),
        .i_ex_wait_inst_get(out_get), .o_ex_wait_inst_data(out_data)
    );

    // Independent identity/data scoreboard: cross-input issue order is free.
    // Every held output must remain on the same lane until accepted.
    always @(posedge clk) begin
        if (!reset_n) begin
            for (int n = 0; n < MODEL_DEPTH; n++) live[n] = 0;
            held = '0;
            accepted = 0; removed = 0;
            if ((|in_get) || (|out_valid)) $fatal(1, "RS offers during reset");
        end else begin
            if (in_get != {INPUTS{in_get[0]}}) $fatal(1, "Partial bundle acknowledgement");
            if ((|in_valid) && !(|in_get)) stalled++;
            for (int p = 0; p < 3; p++) begin
                for (int r = 0; r < READS[p]; r++) begin
                    automatic int lane = OFFSETS[p]+r;
                    automatic int id = int'(out_data[lane*WIDTH +: 32]);
                    if (held[lane] && (!out_valid[lane] ||
                        out_data[lane*WIDTH +: WIDTH] !== held_data[lane]))
                        $fatal(1, "Stalled output changed lane=%0d", lane);
                    if (out_valid[lane]) begin
                        if (id <= 0 || id >= MODEL_DEPTH || !live[id])
                            $fatal(1, "Unexpected/duplicate output id=%0d", id);
                        if (out_data[lane*WIDTH +: WIDTH] !== expected[id] ||
                            out_data[lane*WIDTH+PATH_OFFSET +: 2] != 2'(p))
                            $fatal(1, "RS data/path mismatch id=%0d", id);
                        for (int other = 0; other < lane; other++)
                            if (out_valid[other] && out_data[other*WIDTH +: 32] == 32'(id))
                                $fatal(1, "Duplicate simultaneous offer");
                        if (out_get[lane]) begin live[id] = 0; removed++; end
                    end
                    held[lane] = out_valid[lane] && !out_get[lane];
                    held_data[lane] = out_data[lane*WIDTH +: WIDTH];
                end
            end
            for (int w = 0; w < INPUTS; w++) begin
                if (in_valid[w] && in_get[w]) begin
                    automatic int id = int'(in_data[w*WIDTH +: 32]);
                    if (id <= 0 || id >= MODEL_DEPTH || live[id]) $fatal(1, "Bad input identity");
                    expected[id] = in_data[w*WIDTH +: WIDTH]; live[id] = 1; accepted++;
                end
            end
        end
    end

    function automatic int random_word;
        rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5;
        return int'(rng & 32'h7fffffff);
    endfunction
    task automatic step;
        @(posedge clk); #1; @(negedge clk);
    endtask
    task automatic new_bundle(input int only_path, input bit sparse);
        for (int w = 0; w < INPUTS; w++) begin
            for (int b = 0; b < WIDTH; b++)
                in_data[w*WIDTH+b] = 1'((serial >> (b%31)) ^ (b/31));
            in_data[w*WIDTH +: 32] = 32'(serial);
            in_data[w*WIDTH+PATH_OFFSET +: 2] = 2'(only_path < 0 ? random_word()%3 : only_path);
            in_valid[w] = !sparse || ((random_word()%3) != 0);
            serial++;
        end
    endtask
    task automatic drain;
        in_valid = '0; out_get = '1;
        for (int t = 0; t < RS_FIFO*10+300; t++) begin
            step();
            if (accepted == removed) begin
                repeat (20) step();
                if (|out_valid) $fatal(1, "Extra RS output after drain");
                return;
            end
        end
        $fatal(1, "RS lost entries accepted=%0d removed=%0d", accepted, removed);
    endtask

    initial begin
        in_valid = '0; in_data = '0; out_get = '0;
        repeat (3) step(); reset_n = 1;
        // Fill path 0 alone. Paths 1/2 must not accept a mixed bundle while
        // path 0 blocks the global IST acknowledgement.
        for (int t = 0; t < RS_FIFO*3+100; t++) begin
            new_bundle(0, 0); step();
        end
        if (|in_get) $fatal(1, "Path 0 failed to backpressure");
        new_bundle(-1, 0); out_get = 5'b11110;
        repeat (40) begin
            step();
            if (|in_get) $fatal(1, "Blocked path unexpectedly ready");
        end
        out_get = '1;
        begin : retry_bundle
            bit transferred;
            do begin
                #1; transferred = &in_get; step();
            end while (!transferred);
        end
        drain();
        // Keep the same valid/data bundle until IST receives acknowledgement.
        for (int t = 0; t < 2000; t++) begin
            bit transferred;
            if (!(|in_valid)) new_bundle(-1, 1);
            for (int r = 0; r < 5; r++) out_get[r] = 1'((random_word()%3) != 0);
            #1; transferred = &in_get; step();
            if (transferred) in_valid = '0;
        end
        // Complete the last offered bundle before draining.
        out_get = '1;
        while (|in_valid) begin
            bit transferred;
            #1; transferred = &in_get; step();
            if (transferred) in_valid = '0;
        end
        drain();
        // Reset with queued and held instructions; stale BRAM contents must
        // never become visible after valid/pointers have been reset.
        out_get = '0;
        repeat (5) begin new_bundle(1, 0); step(); end
        in_valid = '0; reset_n = 0; repeat (3) step(); reset_n = 1;
        out_get = '1; repeat (12) step();
        if (|out_valid) $fatal(1, "Stale output after reset");
        new_bundle(-1, 0); step(); drain();
        if (stalled < 40) $fatal(1, "Missing backpressure coverage");
        $display("PASS RS D=%0d U=%0d N=%0d accepted=%0d removed=%0d stalled=%0d",
                 DECODE, UPDATES, ENTRIES, accepted, removed, stalled);
        $finish;
    end
    initial begin
        #2000000; $fatal(1, "RS watchdog");
    end
endmodule
