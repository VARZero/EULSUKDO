`timescale 1ns/1ps
module tb_ready_station_paths;
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset_n = 0;
    logic [6:0] i_ist_ready_inst_valid = 0;
    wire [6:0] o_ist_ready_inst_get;
    logic [643:0] i_ist_ready_inst_data = 0;
    wire [4:0] o_ex_wait_inst_valid;
    logic [4:0] i_ex_wait_inst_get = 0;
    wire [459:0] o_ex_wait_inst_data;

    ready_station dut (.*);

    task automatic tick;
        @(posedge clk); #1;
    endtask

    initial begin
        tick();
        reset_n = 1;
        i_ist_ready_inst_valid = 7'b0011111;
        for (int lane = 0; lane < 5; lane++) begin
            i_ist_ready_inst_data[lane*92 +: 35] = 35'(4*lane);
            i_ist_ready_inst_data[lane*92 + 35 +: 2] =
                2'((lane == 0) ? 0 : (lane == 4) ? 2 : 1);
        end
        #1;
        if (o_ist_ready_inst_get !== 7'b1111111)
            $fatal(1, "multi-path enqueue not ready");
        tick();
        i_ist_ready_inst_valid = 0;
        #1;
        if (o_ex_wait_inst_valid !== 5'b11111)
            $fatal(1, "three execution paths did not preserve channel counts");
        for (int lane = 0; lane < 5; lane++) begin
            if (o_ex_wait_inst_data[lane*92 +: 35] !== 35'(4*lane))
                $fatal(1, "execution path order at output %0d", lane);
        end
        i_ex_wait_inst_get = 5'b11111;
        tick();
        i_ex_wait_inst_get = 0;
        #1;
        if (o_ex_wait_inst_valid !== 0) $fatal(1, "execution paths did not drain");
        $display("three-path RS routing and multi-output ordering passed");
        $finish;
    end
endmodule
