`timescale 1ns/1ps
module tb_gen2_allocator_init;
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset_n = 0;
    logic [0:0] unallocate = 0;
    logic [2:0] unallocate_data = 0;
    logic [1:0] allocate = 0;
    wire [0:0] unallocate_ready;
    wire [1:0] allocate_valid;
    wire [5:0] allocate_data;
    int issued = 0;
    int cycles = 0;
    bit returned = 0;

    allocator #(
        .ENTRIES(5), .START_VALUE(1),
        .ALLOCATE_CHANNEL(2), .UNALLOCATE_CHANNEL(1)
    ) dut (
        .clk(clk), .reset_n(reset_n), .i_flush(1'b0),
        .i_unallocate(unallocate), .o_unallocate_ready(unallocate_ready),
        .i_unallocate_data(unallocate_data),
        .i_allocate(allocate), .o_allocate_valid(allocate_valid),
        .o_allocate_data(allocate_data)
    );

    initial begin
        repeat (2) begin @(posedge clk); #1; end
        reset_n = 1;
        while (issued < 5 && cycles < 100) begin
            #1;
            allocate = 0;
            if (allocate_valid[0]) begin
                if (allocate_data[2:0] !== 3'(issued+1))
                    $fatal(1, "initial ID order: got %0d expected %0d", allocate_data[2:0], issued+1);
                allocate[0] = 1'b1;
                issued++;
            end
            @(posedge clk); #1;
            cycles++;
        end
        allocate = 0;
        if (issued != 5) $fatal(1, "allocator initialization stalled");
        unallocate = 1;
        unallocate_data = 3'd2;
        @(posedge clk); #1;
        unallocate = 0;
        for (int wait_cycles = 0; wait_cycles < 30; wait_cycles++) begin
            if (allocate_valid[0]) begin
                if (allocate_data[2:0] !== 3'd2) $fatal(1, "returned ID mismatch");
                returned = 1;
                break;
            end
            @(posedge clk); #1;
        end
        if (!returned) $fatal(1, "returned ID did not reappear");
        $display("Gen2 allocator FIFO initialization/return passed (startup %0d cycles)", cycles);
        $finish;
    end
endmodule
