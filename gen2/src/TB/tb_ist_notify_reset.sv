`timescale 1ns/1ps

// Reset between source matching and ready-flag commit, then reuse the reset
// allocation state. Old operand matches must not wake the new instruction.
module tb_ist_notify_reset;
    logic clk = 0, reset_n = 0;
    always #5 clk = ~clk;
    logic new_valid = 0;
    logic [93:0] new_data = 0;
    wire new_get;
    logic [1:0] prm_valid = 0;
    logic [17:0] prm_data = 0;
    wire [1:0] wait_valid, rs_valid;
    wire [17:0] wait_data;
    wire [183:0] rs_data;
    int received = 0;
    logic [2:0] entry_id;
    instruction_state_table #(
        .STRUCT_DECODE_NEW_INST(1), .STRUCT_INST_STATE_ENTRIES(8),
        .STRUCT_IST_BANKS(2), .STRUCT_IST_ISSUE_WIDTH(1), .STRUCT_PRM_ENTRY_UPDATE(2)
    ) dut (
        .clk(clk), .reset_n(reset_n),
        .i_nel_new_inst_valid(new_valid), .i_nel_new_inst_data(new_data), .o_nel_new_inst_get(new_get),
        .i_prm_ready_phyreg_valid(prm_valid), .i_prm_ready_phyreg_data(prm_data),
        .i_rs_ready_inst_get(2'b11), .o_rs_ready_inst_valid(rs_valid), .o_rs_ready_inst_data(rs_data),
        .o_prm_wait_phyreg_valid(wait_valid), .o_prm_wait_phyreg_data(wait_data)
    );
    always @(posedge clk) begin
        if (!reset_n) received = 0;
        else for (int lane = 0; lane < 2; lane++) if (rs_valid[lane]) begin
            if (rs_data[lane*92 +: 32] != 200 || received != 0)
                $fatal(1, "Old or duplicate instruction escaped notification reset");
            received++;
        end
    end
    task automatic step;
        @(posedge clk); #1; @(negedge clk);
    endtask
    task automatic send(input int pc);
        while (!new_get) step();
        new_valid = 1; new_data = '0;
        new_data[31:0] = 32'(pc);
        new_data[80 +: 12] = {6'd2, 6'd1};
        #1;
        if (wait_valid != 2'b11) $fatal(1, "Missing dependency registration");
        entry_id = wait_data[6 +: 3];
        step(); new_valid = 0;
    endtask
    initial begin
        repeat (3) step(); reset_n = 1;
        send(100);
        prm_valid = 3; prm_data = {{entry_id, 6'd2}, {entry_id, 6'd1}};
        step(); prm_valid = 0;
        if (dut.prm_stage_valid != 3) $fatal(1, "No in-flight notification at reset");
        reset_n = 0; repeat (2) step(); reset_n = 1;
        send(200);
        repeat (10) step();
        if (received != 0) $fatal(1, "Old matched operands survived reset");
        prm_valid = 1; prm_data[0 +: 9] = {entry_id, 6'd1};
        step(); prm_valid = 0; repeat (10) step();
        if (received != 0) $fatal(1, "Missing second dependency");
        prm_valid = 2; prm_data[9 +: 9] = {entry_id, 6'd2};
        step(); prm_valid = 0;
        repeat (40) step();
        if (received != 1) $fatal(1, "New lifetime failed to wake");
        $display("PASS IST notification pipeline reset and fresh dependency lifetime");
        $finish;
    end
    initial begin #20000; $fatal(1, "Notification reset watchdog"); end
endmodule
