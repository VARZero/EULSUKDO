`timescale 1ns/1ps
// With ample free space, prepared allocation must sustain a full NEL bundle
// each clock. Check both stored instructions and unused grants on ready bypass.
module tb_ist_grant_throughput #(parameter int DECODE = 3);
    localparam int ENTRIES = 128, IDX_W = 7, EX_W = 92, INST_W = 94;
    logic clk = 0, reset_n = 0;
    always #5 clk = ~clk;
    logic [DECODE-1:0] valid = 0;
    wire [DECODE-1:0] get_inst;
    logic [DECODE*INST_W-1:0] data = 0;
    wire [2*DECODE-1:0] wait_valid;
    wire [2*DECODE*(IDX_W+6)-1:0] wait_data;
    bit used[ENTRIES];
    int accepted = 0;
    instruction_state_table #(
        .STRUCT_DECODE_NEW_INST(DECODE), .STRUCT_INST_STATE_ENTRIES(ENTRIES),
        .STRUCT_IST_BANKS(8), .STRUCT_IST_ISSUE_WIDTH(5)
    ) dut (
        .clk(clk), .reset_n(reset_n), .i_nel_new_inst_valid(valid),
        .o_nel_new_inst_get(get_inst), .i_nel_new_inst_data(data),
        .i_prm_ready_phyreg_valid('0), .i_prm_ready_phyreg_data('0),
        .i_rs_ready_inst_get('1), .o_rs_ready_inst_valid(), .o_rs_ready_inst_data(),
        .o_prm_wait_phyreg_valid(wait_valid), .o_prm_wait_phyreg_data(wait_data)
    );
    task automatic step;
        @(posedge clk); #1; @(negedge clk);
    endtask
    initial begin
        for (int mode = 0; mode < 2; mode++) begin
            reset_n = 0; valid = 0; accepted = 0;
            for (int n = 0; n < ENTRIES; n++) used[n] = 0;
            repeat (3) step(); reset_n = 1;
            repeat (20) step();
            for (int cycle = 0; cycle < 8; cycle++) begin
                valid = '1; data = '0;
                for (int lane = 0; lane < DECODE; lane++) begin
                    data[lane*INST_W +: 32] = 32'(cycle*DECODE+lane);
                    data[lane*INST_W+80 +: 12] = {6'd1, 6'd1};
                    data[lane*INST_W+EX_W +: 2] = mode != 0 ? 2'b11 : 2'b00;
                end
                #1;
                if (!(&get_inst)) $fatal(1, "Allocation bubble with ample capacity D=%0d cycle=%0d", DECODE, cycle);
                if (mode == 0) begin
                    if (!(&wait_valid)) $fatal(1, "Missing registration");
                    for (int lane = 0; lane < DECODE; lane++) begin
                        automatic int id = int'(wait_data[(2*lane)*(IDX_W+6)+6 +: IDX_W]);
                        if (id >= ENTRIES || used[id]) $fatal(1, "Duplicate/out-of-range reserved address");
                        used[id] = 1;
                    end
                end else if (|wait_valid) $fatal(1, "Ready bypass registered a dependency");
                step(); accepted += DECODE;
            end
            valid = 0;
            if ($countones(dut.active_entries) != (mode == 0 ? accepted : 0))
                $fatal(1, "Unused grant leaked into active occupancy");
        end
        $display("PASS IST grants D=%0d full bundles/clock=8 stored+ready-bypass", DECODE);
        $finish;
    end
    initial begin #100000; $fatal(1, "Grant throughput watchdog"); end
endmodule
