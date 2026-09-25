`timescale 1ns/1ps
module tb_gen2_allocator_full;
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset_n = 0;
    logic [1:0] allocate = 0;
    wire [1:0] allocate_valid;
    wire [13:0] allocate_data;
    int issued = 0;
    allocator #(
        .ENTRIES(128), .START_VALUE(0),
        .ALLOCATE_CHANNEL(2), .UNALLOCATE_CHANNEL(7)
    ) dut (
        .clk(clk), .reset_n(reset_n), .i_flush(1'b0),
        .i_unallocate(7'b0), .o_unallocate_ready(), .i_unallocate_data(49'b0),
        .i_allocate(allocate), .o_allocate_valid(allocate_valid),
        .o_allocate_data(allocate_data)
    );
    initial begin
        repeat (2) begin @(posedge clk); #1; end
        reset_n = 1;
        for (int cycle = 0; cycle < 400; cycle++) begin
            allocate = 0;
            #1;
            if (allocate_valid[0]) begin
                if (issued >= 128 || allocate_data[6:0] !== 7'(issued))
                    $fatal(1, "IST allocator ID at %0d got %0d", issued, allocate_data[6:0]);
                allocate[0] = 1'b1;
                issued++;
            end
            @(posedge clk); #1;
        end
        if (issued != 128 || allocate_valid != 0)
            $fatal(1, "IST allocator issue count %0d valid %b", issued, allocate_valid);
        $display("Gen2 128-entry IST allocator sequence passed");
        $finish;
    end
endmodule
