`timescale 1ns/1ps
module tb_flow_window_pressure;
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset_n = 0;
    logic [4:0] done_valid = 0;
    logic [164:0] done_pc = 0;
    logic branch_valid = 0;
    logic [34:0] branch_data = 0;
    logic jump_valid = 0;
    logic [34:0] jump_data = 0;
    logic [1:0] retired_valid = 0;
    logic [77:0] retired_data = 0;
    logic [1:0] im_valid = 0;
    logic [1:0] im_get = 0;
    logic [65:0] im_pc = 0;
    wire [1:0] im_discard;
    logic [1:0] req_get = 0;
    wire [1:0] req_valid;
    wire [65:0] req_pc;
    wire [0:0] unalloc_valid;
    wire [5:0] unalloc_data;

    flow_control_logic #(
        .STRUCT_FLOW_WINDOWS(2),
        .STRUCT_FLOW_PC_MAX_RANGE(4),
        .STRUCT_UNALLOCATE_PHYREG(1)
    ) dut (
        .clk(clk), .reset_n(reset_n),
        .i_wbc_done_pc_valid(done_valid), .i_wbc_done_pc_data(done_pc),
        .i_wbc_branch_valid(branch_valid), .i_wbc_branch_data(branch_data),
        .i_nel_jumpbranch_valid(jump_valid), .i_nel_jumpbranch_data(jump_data),
        .i_nel_retired_phyreg_valid(retired_valid), .i_nel_retired_phyreg_data(retired_data),
        .i_im_recv_inst_valid(im_valid), .i_im_recv_inst_get(im_get),
        .i_im_recv_pc(im_pc), .o_im_recv_discard(im_discard),
        .o_im_req_pc_valid(req_valid), .i_im_req_pc_get(req_get), .o_im_req_pc(req_pc),
        .o_prm_unallocate_phyreg_valid(unalloc_valid),
        .o_prm_unallocate_phyreg_data(unalloc_data)
    );

    task automatic tick;
        @(posedge clk); #1;
    endtask

    initial begin
        tick();
        reset_n = 1;
        // Both windows keep four outstanding responses. With no free window,
        // PC requests must stop rather than reuse an active flow ID.
        for (int n = 0; n < 8; n++) begin
            #1;
            if (req_valid[0] !== 1'b1 || req_pc[31:0] !== 32'(4*n) ||
                req_pc[32] !== 1'(n/4)) $fatal(1, "window request %0d", n);
            req_get = 2'b01;
            tick();
            req_get = 0;
        end
        #1;
        if (req_valid !== 0) $fatal(1, "requests continued with all windows active");
        repeat (3) begin
            tick();
            if (req_valid !== 0) $fatal(1, "saturated flow did not stall");
        end

        // Return and complete flow 0, retaining flow 1. The next request
        // must reuse flow ID 0, with a new PC rather than the old address.
        for (int n = 0; n < 4; n++) begin
            im_valid = 2'b01;
            im_get = 2'b01;
            im_pc = {33'd0,33'(4*n)};
            done_valid = 5'b00001;
            done_pc = {132'd0,33'(4*n)};
            #1;
            if (n < 3 && req_valid !== 0) $fatal(1, "window reused before last completion");
            tick();
        end
        im_valid = 0;
        im_get = 0;
        done_valid = 0;
        #1;
        if (req_valid[0] !== 1'b1 || req_pc[32] !== 1'b0 || req_pc[31:0] !== 32'd32)
            $fatal(1, "flow ID not reused after full drain");
        $display("flow-window saturation and safe ID reuse passed");
        $finish;
    end
endmodule
