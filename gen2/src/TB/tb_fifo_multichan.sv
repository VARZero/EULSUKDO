`timescale 1ns/1ps

module tb_fifo_multichan #(
    parameter int DATA_WIDTH = 32,
    parameter int READ_CHANNEL = 2,
    parameter int WRITE_CHANNEL = 3,
    parameter int MIN_FIFO_ENTRY = 17,
    parameter int USE_BRAM = 0
);
    logic clk = 0, reset_n = 0, flush = 0;
    always #5 clk = ~clk;
    logic [WRITE_CHANNEL-1:0] push, ready;
    logic [WRITE_CHANNEL*DATA_WIDTH-1:0] push_data;
    logic [READ_CHANNEL-1:0] pop, valid;
    logic [READ_CHANNEL*DATA_WIDTH-1:0] data;
    logic [DATA_WIDTH-1:0] expected[$];
    int serial = 1, accepted, removed;
    logic [31:0] rng = 32'hc0ffee13;

    fifo_multichan #(
        .DATA_WIDTH(DATA_WIDTH), .READ_CHANNEL(READ_CHANNEL), .WRITE_CHANNEL(WRITE_CHANNEL),
        .MIN_FIFO_ENTRY(MIN_FIFO_ENTRY), .USE_BRAM(USE_BRAM != 0)
    ) dut (
        .clk(clk), .reset_n(reset_n), .i_flush(flush),
        .i_push(push), .o_push_ready(ready), .i_push_data(push_data),
        .i_pop(pop), .o_pop_valid(valid), .o_pop_data(data)
    );

    always @(posedge clk) begin
        if (!reset_n || flush) begin
            if ((|valid) || (|ready)) $fatal(1, "FIFO offers during reset/flush");
            expected.delete(); accepted = 0; removed = 0;
        end
        else begin
            for (int r = 0; r < READ_CHANNEL; r++) begin
                if (valid[r]) begin
                    if ((r >= expected.size()) || (data[r*DATA_WIDTH +: DATA_WIDTH] != expected[r]))
                        $fatal(1, "FIFO order/data error lane=%0d data=%h count=%0d", r, data[r*DATA_WIDTH +: DATA_WIDTH], expected.size());
                    if ((r > 0) && !valid[r-1]) $fatal(1, "Non-prefix FIFO output");
                end
            end
            for (int r = READ_CHANNEL-1; r >= 0; r--) begin
                if (valid[r] && pop[r]) begin expected.delete(r); removed++; end
            end
            for (int w = 0; w < WRITE_CHANNEL; w++) begin
                if (push[w] && ready[w]) begin expected.push_back(push_data[w*DATA_WIDTH +: DATA_WIDTH]); accepted++; end
            end
        end
    end

    task automatic step;
        @(posedge clk); #1; @(negedge clk);
    endtask
    function automatic int random_word;
        rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5;
        return int'(rng & 32'h7fffffff);
    endfunction
    task automatic new_data;
        for (int w = 0; w < WRITE_CHANNEL; w++) begin
            for (int b = 0; b < DATA_WIDTH; b++)
                push_data[w*DATA_WIDTH+b] = 1'((serial >> (b%31)) ^ (b/31));
            serial++;
        end
    endtask
    task automatic drain;
        push = '0; pop = '1;
        for (int t = 0; t < MIN_FIFO_ENTRY*10+200; t++) begin
            if (expected.size() == 0) begin
                repeat (10) step();
                if ((|valid) || (accepted != removed)) $fatal(1, "Extra FIFO data");
                return;
            end
            step();
        end
        $fatal(1, "FIFO lost %0d entries", expected.size());
    endtask

    initial begin
        push = '0; pop = '0; push_data = '0;
        repeat (3) step(); reset_n = 1;
        for (int round_idx = 0; round_idx < 4; round_idx++) begin
            // Continue presenting input while full; only Ready permits capture.
            push = '1; pop = '0;
            for (int t = 0; t < MIN_FIFO_ENTRY*3+60; t++) begin new_data(); step(); end
            if (|ready) $fatal(1, "FIFO never backpressured");
            if (expected.size() < MIN_FIFO_ENTRY) $fatal(1, "FIFO capacity below promised minimum");
            drain();
        end
        for (int t = 0; t < 2000; t++) begin
            new_data();
            for (int w = 0; w < WRITE_CHANNEL; w++) push[w] = 1'((random_word()%3) != 0);
            for (int r = 0; r < READ_CHANNEL; r++) pop[r] = 1'((random_word()%3) != 0);
            step();
        end
        drain();
        push = '1; pop = '0;
        repeat (20) begin new_data(); step(); end
        flush = 1; step(); flush = 0; push = '0; drain();
        push = '1;
        repeat (10) begin new_data(); step(); end
        drain();
        $display("PASS FIFO WIDTH=%0d R=%0d W=%0d N=%0d BRAM=%0d", DATA_WIDTH, READ_CHANNEL, WRITE_CHANNEL, MIN_FIFO_ENTRY, USE_BRAM);
        $finish;
    end
    initial begin
        #2000000; $fatal(1, "FIFO watchdog");
    end
endmodule
