`timescale 1ns/1ps
module tb_prm_fanout;
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset_n = 0;
    logic [3:0] wait_valid = 0;
    logic [23:0] wait_data = 0;
    logic [4:0] done_valid = 0;
    logic [14:0] done_data = 0;
    wire [1:0] ready_valid;
    wire [11:0] ready_data;

    physical_register_mapper #(
        .STRUCT_INST_STATE_ENTRIES(8), .STRUCT_PHYREGS(8),
        .STRUCT_PRM_ENTRY_BUFFER(2), .STRUCT_PRM_ENTRY_UPDATE(2)
    ) dut (
        .clk(clk), .reset_n(reset_n),
        .i_ist_wait_phyreg_valid(wait_valid),
        .i_ist_wait_phyreg_data(wait_data),
        .i_wbc_done_phyreg_valid(done_valid),
        .i_wbc_done_phyreg_data(done_data),
        .i_fcl_unallocate_phyreg_valid(4'b0),
        .i_fcl_unallocate_phyreg_data(12'b0),
        .o_nel_phyreg_valid(), .i_nel_phyreg_get(2'b0),
        .o_nel_phyreg_data(),
        .o_ist_ready_phyreg_valid(ready_valid),
        .o_ist_ready_phyreg_data(ready_data)
    );

    task automatic tick;
        @(posedge clk); #1;
    endtask

    task automatic check_pair(input int first_entry);
        if (ready_valid !== 2'b11 ||
            ready_data[5:0] !== 6'(first_entry*8+1) ||
            ready_data[11:6] !== 6'((first_entry+1)*8+1))
            $fatal(1, "PRM fanout order/cycle at entry %0d: valid=%b data=%h",
                   first_entry, ready_valid, ready_data);
    endtask

    initial begin
        repeat (2) tick();
        reset_n = 1;
        for (int base = 0; base < 6; base += 2) begin
            wait_valid = 4'b0011;
            wait_data = 24'(base*8+1) | (24'((base+1)*8+1) << 6);
            tick();
        end
        wait_valid = 0;
        done_valid = 5'b00001;
        done_data = 15'd1;
        tick();
        done_valid = 0;
        tick();
        check_pair(0);
        tick();
        check_pair(2);
        tick();
        check_pair(4);
        tick();
        if (ready_valid !== 2'b00) $fatal(1, "duplicate PRM notification");
        $display("six-waiter PRM fanout through two output lanes passed");
        $finish;
    end
endmodule
