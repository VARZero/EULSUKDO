`timescale 1ns/1ps

module eulsukdo_flow_control_logic #(
    parameter int unsigned PC_WIDTH       = 32,
    parameter int unsigned PC_STEP        = 4,
    parameter int unsigned DECODE_WIDTH   = 2,
    parameter int unsigned PHY_REGS       = 64,
    parameter int unsigned FLOW_WINDOWS   = 8,
    parameter int unsigned RESULT_PORTS   = 5,
    parameter int unsigned BRANCH_PORTS   = 1,
    parameter int unsigned FREE_PORTS     = 4,
    parameter int unsigned ROB_ENTRIES    = 128,
    parameter int unsigned PHY_REG_WIDTH  = (PHY_REGS <= 1) ? 1 : $clog2(PHY_REGS),
    parameter int unsigned FLOW_WIDTH     = (FLOW_WINDOWS <= 1) ? 1 : $clog2(FLOW_WINDOWS),
    parameter int unsigned RETIRE_WIDTH   = PC_WIDTH + FLOW_WIDTH + PHY_REG_WIDTH + 1,
    parameter int unsigned CONTROL_WIDTH  = PC_WIDTH + FLOW_WIDTH + PC_WIDTH + 3,
    parameter int unsigned DONE_PC_WIDTH  = PC_WIDTH + FLOW_WIDTH,
    parameter int unsigned BRANCH_WIDTH   = PC_WIDTH + FLOW_WIDTH + 1 + PC_WIDTH,
    parameter int unsigned ROB_PTR_WIDTH  = (ROB_ENTRIES <= 1) ? 1 : $clog2(ROB_ENTRIES),
    parameter int unsigned ROB_COUNT_WIDTH = $clog2(ROB_ENTRIES + 1)
) (
    input  logic                              clk,
    input  logic                              reset_n,

    output logic [DECODE_WIDTH-1:0]           o_im_req_valid,
    input  logic [DECODE_WIDTH-1:0]           i_im_req_get,
    output logic [DECODE_WIDTH*(PC_WIDTH+FLOW_WIDTH)-1:0] o_im_req_data,

    input  logic [DECODE_WIDTH-1:0]           i_retire_valid,
    input  logic [DECODE_WIDTH*RETIRE_WIDTH-1:0] i_retire_data,
    output logic                              o_retire_ready,

    input  logic                              i_control_valid,
    input  logic [CONTROL_WIDTH-1:0]          i_control_data,

    input  logic [RESULT_PORTS-1:0]           i_done_valid,
    input  logic [RESULT_PORTS*DONE_PC_WIDTH-1:0] i_done_data,
    input  logic [BRANCH_PORTS-1:0]           i_branch_valid,
    input  logic [BRANCH_PORTS*BRANCH_WIDTH-1:0] i_branch_data,

    output logic [FREE_PORTS-1:0]             o_free_valid,
    output logic [FREE_PORTS*PHY_REG_WIDTH-1:0] o_free_phy
);
    logic [PC_WIDTH-1:0] next_pc;
    logic [FLOW_WIDTH-1:0] current_flow;
    logic waiting_for_control;
    logic [PC_WIDTH-1:0] pending_control_pc;
    logic [FLOW_WIDTH-1:0] pending_control_flow;

    logic [ROB_ENTRIES-1:0] rob_valid;
    logic [ROB_ENTRIES-1:0] rob_done;
    logic [PC_WIDTH-1:0] rob_pc [0:ROB_ENTRIES-1];
    logic [FLOW_WIDTH-1:0] rob_flow [0:ROB_ENTRIES-1];
    logic [PHY_REG_WIDTH-1:0] rob_old_phy [0:ROB_ENTRIES-1];
    logic rob_has_old [0:ROB_ENTRIES-1];
    logic [ROB_PTR_WIDTH-1:0] rob_head;
    logic [ROB_PTR_WIDTH-1:0] rob_tail;
    logic [ROB_COUNT_WIDTH-1:0] rob_count;
    integer lane;
    integer port;
    integer entry;
    integer accepted_requests;
    integer enqueue_count;
    integer retire_count;
    integer free_count;
    integer index;
    logic prefix;
    logic [PC_WIDTH-1:0] done_pc;
    logic [FLOW_WIDTH-1:0] done_flow;
    logic branch_taken;
    logic [PC_WIDTH-1:0] branch_pc;
    logic [FLOW_WIDTH-1:0] branch_flow;
    logic [PC_WIDTH-1:0] branch_target;

    always_comb begin
        o_im_req_valid = '0;
        o_im_req_data = '0;
        if (!waiting_for_control) begin
            for (lane = 0; lane < DECODE_WIDTH; lane = lane + 1) begin
                o_im_req_valid[lane] = 1'b1;
                o_im_req_data[lane*(PC_WIDTH+FLOW_WIDTH) +: PC_WIDTH] = next_pc + PC_WIDTH'(lane*PC_STEP);
                o_im_req_data[lane*(PC_WIDTH+FLOW_WIDTH) + PC_WIDTH +: FLOW_WIDTH] = current_flow;
            end
        end

        o_retire_ready = (rob_count <= (ROB_ENTRIES - DECODE_WIDTH));

        o_free_valid = '0;
        o_free_phy = '0;
        retire_count = 0;
        free_count = 0;
        prefix = 1'b1;
        for (entry = 0; entry < ROB_ENTRIES; entry = entry + 1) begin
            index = (rob_head + entry) % ROB_ENTRIES;
            if (prefix && (entry < FREE_PORTS) && rob_valid[index] && rob_done[index]) begin
                retire_count = retire_count + 1;
                if (rob_has_old[index] && (rob_old_phy[index] != '0) && (free_count < FREE_PORTS)) begin
                    o_free_valid[free_count] = 1'b1;
                    o_free_phy[free_count*PHY_REG_WIDTH +: PHY_REG_WIDTH] = rob_old_phy[index];
                    free_count = free_count + 1;
                end
            end else begin
                prefix = 1'b0;
            end
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            next_pc <= '0;
            current_flow <= '0;
            waiting_for_control <= 1'b0;
            pending_control_pc <= '0;
            pending_control_flow <= '0;
            rob_valid <= '0;
            rob_done <= '0;
            rob_head <= '0;
            rob_tail <= '0;
            rob_count <= '0;
            for (entry = 0; entry < ROB_ENTRIES; entry = entry + 1) begin
                rob_pc[entry] <= '0;
                rob_flow[entry] <= '0;
                rob_old_phy[entry] <= '0;
                rob_has_old[entry] <= 1'b0;
            end
        end else begin
            accepted_requests = 0;
            prefix = 1'b1;
            for (lane = 0; lane < DECODE_WIDTH; lane = lane + 1) begin
                if (prefix && o_im_req_valid[lane] && i_im_req_get[lane])
                    accepted_requests = accepted_requests + 1;
                else
                    prefix = 1'b0;
            end
            if (accepted_requests != 0)
                next_pc <= next_pc + PC_WIDTH'(accepted_requests*PC_STEP);

            if (i_control_valid) begin
                pending_control_pc <= i_control_data[3+PC_WIDTH+FLOW_WIDTH +: PC_WIDTH];
                pending_control_flow <= i_control_data[3+PC_WIDTH +: FLOW_WIDTH];
                current_flow <= i_control_data[3+PC_WIDTH +: FLOW_WIDTH] + FLOW_WIDTH'(1);
                if (i_control_data[0] && !i_control_data[1]) begin
                    next_pc <= i_control_data[3 +: PC_WIDTH];
                    waiting_for_control <= 1'b0;
                end else begin
                    waiting_for_control <= 1'b1;
                end
            end

            for (port = 0; port < BRANCH_PORTS; port = port + 1) begin
                branch_pc = i_branch_data[port*BRANCH_WIDTH +: PC_WIDTH];
                branch_flow = i_branch_data[port*BRANCH_WIDTH + PC_WIDTH +: FLOW_WIDTH];
                branch_taken = i_branch_data[port*BRANCH_WIDTH + PC_WIDTH + FLOW_WIDTH];
                branch_target = i_branch_data[port*BRANCH_WIDTH + PC_WIDTH + FLOW_WIDTH + 1 +: PC_WIDTH];
                if (i_branch_valid[port] && waiting_for_control &&
                    (branch_pc == pending_control_pc) && (branch_flow == pending_control_flow)) begin
                    next_pc <= branch_taken ? branch_target : (pending_control_pc + PC_WIDTH'(PC_STEP));
                    current_flow <= pending_control_flow + FLOW_WIDTH'(1);
                    waiting_for_control <= 1'b0;
                end
            end

            for (port = 0; port < RESULT_PORTS; port = port + 1) begin
                done_pc = i_done_data[port*DONE_PC_WIDTH +: PC_WIDTH];
                done_flow = i_done_data[port*DONE_PC_WIDTH + PC_WIDTH +: FLOW_WIDTH];
                if (i_done_valid[port]) begin
                    for (entry = 0; entry < ROB_ENTRIES; entry = entry + 1) begin
                        if (rob_valid[entry] && (rob_pc[entry] == done_pc) && (rob_flow[entry] == done_flow))
                            rob_done[entry] <= 1'b1;
                    end
                end
            end

            for (entry = 0; entry < retire_count; entry = entry + 1) begin
                index = (rob_head + entry) % ROB_ENTRIES;
                rob_valid[index] <= 1'b0;
                rob_done[index] <= 1'b0;
            end
            if (retire_count != 0) rob_head <= ROB_PTR_WIDTH'((rob_head + retire_count) % ROB_ENTRIES);

            enqueue_count = 0;
            if (o_retire_ready) begin
                for (lane = 0; lane < DECODE_WIDTH; lane = lane + 1) begin
                    if (i_retire_valid[lane]) begin
                        index = (rob_tail + enqueue_count) % ROB_ENTRIES;
                        rob_valid[index] <= 1'b1;
                        rob_done[index] <= 1'b0;
                        rob_old_phy[index] <= i_retire_data[lane*RETIRE_WIDTH +: PHY_REG_WIDTH];
                        rob_has_old[index] <= i_retire_data[lane*RETIRE_WIDTH + PHY_REG_WIDTH];
                        rob_flow[index] <= i_retire_data[lane*RETIRE_WIDTH + PHY_REG_WIDTH + 1 +: FLOW_WIDTH];
                        rob_pc[index] <= i_retire_data[lane*RETIRE_WIDTH + PHY_REG_WIDTH + 1 + FLOW_WIDTH +: PC_WIDTH];
                        enqueue_count = enqueue_count + 1;
                    end
                end
            end
            if (enqueue_count != 0) rob_tail <= ROB_PTR_WIDTH'((rob_tail + enqueue_count) % ROB_ENTRIES);
            if ((enqueue_count != 0) || (retire_count != 0))
                rob_count <= ROB_COUNT_WIDTH'(rob_count + enqueue_count - retire_count);
        end
    end

    initial begin
        if (ROB_ENTRIES < DECODE_WIDTH || FLOW_WINDOWS < 2)
            $error("Invalid EULSUKDO FCL parameters");
    end
endmodule
