`timescale 1ns/1ps
module tb_gen2_fifo_order;
    parameter bit USE_BRAM = 1'b0;
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset_n = 0;
    logic [1:0] push = 0, pop = 0;
    logic flush = 0;
    logic [15:0] push_data = 0;
    wire [1:0] push_ready, pop_valid;
    wire [15:0] pop_data;
    int expected [0:1023];
    int used = 0, retained, write_count = 0;
    int next_value = 1;
    logic [31:0] state = 32'h8ad5_701f;

    fifo_multichan #(
        .DATA_WIDTH(8), .READ_CHANNEL(2), .WRITE_CHANNEL(2),
        .MIN_FIFO_ENTRY(5), .USE_BRAM(USE_BRAM)
    ) dut (
        .clk(clk), .reset_n(reset_n), .i_flush(flush),
        .i_push(push), .o_push_ready(push_ready), .i_push_data(push_data),
        .i_pop(pop), .o_pop_valid(pop_valid), .o_pop_data(pop_data)
    );

    initial begin
        repeat (2) begin @(posedge clk); #1; end
        reset_n = 1;
        for (int cycle = 0; cycle < 250; cycle++) begin
            state = {state[30:0], state[31]^state[21]^state[1]^state[0]};
            push = (cycle < 170) ? state[3:2] : 2'b0;
            push_data = {8'(next_value+1), 8'(next_value)};
            pop = (cycle >= 10) ? state[1:0] & pop_valid : 2'b0;
            if (cycle >= 170) pop = pop_valid;
            flush = (cycle == 95 || cycle == 175);
            if (flush) begin
                push = 0;
                pop = 0;
            end
            #1;
            for (int lane = 0; lane < 2; lane++) begin
                if (pop_valid[lane]) begin
                    if (lane >= used || pop_data[lane*8 +: 8] !== 8'(expected[lane]))
                        $fatal(1, "FIFO order at cycle %0d lane %0d", cycle, lane);
                end
            end
            retained = 0;
            for (int idx = 0; idx < used; idx++) begin
                if (idx >= 2 || !(pop[idx] && pop_valid[idx])) begin
                    expected[retained] = expected[idx];
                    retained++;
                end
            end
            used = retained;
            for (int lane = 0; lane < 2; lane++) begin
                if (push[lane] && push_ready[lane]) begin
                    expected[used] = next_value+lane;
                    used++;
                    write_count++;
                end
            end
            next_value += 2;
            @(posedge clk); #1;
            if (flush) used = 0;
        end
        if (used != 0) $fatal(1, "FIFO failed to drain: %0d", used);
        $display("Gen2 staged FIFO order passed (%0d accepted)", write_count);
        $finish;
    end
endmodule
