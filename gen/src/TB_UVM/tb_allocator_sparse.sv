`timescale 1ns/1ps
module tb_allocator_sparse;
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset_n = 0;
    logic [0:0] i_unallocate = 0;
    logic [2:0] i_unallocate_data = 0;
    wire [0:0] o_unallocate_ready;
    logic [1:0] i_allocate = 0;
    wire [1:0] o_allocate_valid;
    wire [5:0] o_allocate_data;

    allocator #(
        .ENTRIES(5), .START_VALUE(1),
        .ALLOCATE_CHANNEL(2), .UNALLOCATE_CHANNEL(1)
    ) dut (
        .clk(clk), .reset_n(reset_n), .i_flush(1'b0),
        .i_unallocate(i_unallocate), .o_unallocate_ready(o_unallocate_ready),
        .i_unallocate_data(i_unallocate_data),
        .i_allocate(i_allocate), .o_allocate_valid(o_allocate_valid),
        .o_allocate_data(o_allocate_data)
    );

    task automatic tick;
        @(posedge clk); #1;
    endtask

    initial begin
        repeat (2) tick();
        reset_n = 1;
        for (int startup = 0; startup < 50 && o_allocate_valid !== 2'b11; startup++) tick();
        if (o_allocate_valid !== 2'b11) $fatal(1, "Gen2 allocator startup timeout");
        if (o_allocate_data !== 6'h11) $fatal(1, "initial IDs");
        i_allocate = 2'b10;
        tick();
        i_allocate = 0;
        #1;
        if (o_allocate_data !== 6'h19)
            $fatal(1, "unselected first lane was lost or second ID repeated");
        i_allocate = 2'b01;
        tick();
        i_allocate = 0;
        #1;
        if (o_allocate_data !== 6'h23)
            $fatal(1, "virgin IDs did not continue in order");
        i_allocate = 2'b11;
        tick();
        i_allocate = 0;
        #1;
        if (o_allocate_valid !== 2'b01 || o_allocate_data[2:0] !== 3'd5)
            $fatal(1, "last virgin ID");
        i_allocate = 2'b01;
        tick();
        i_allocate = 0;
        i_unallocate = 1;
        i_unallocate_data = 2;
        tick();
        i_unallocate = 0;
        for (int wait_return = 0; wait_return < 30 && o_allocate_valid !== 2'b01; wait_return++) tick();
        if (o_allocate_valid !== 2'b01 || o_allocate_data[2:0] !== 3'd2)
            $fatal(1, "returned ID did not reappear");
        $display("sparse allocation and FIFO return passed");
        $finish;
    end
endmodule
