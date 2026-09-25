`timescale 1ns/1ps

// Per-flow state holder, corresponding to the flow_detect_unit instances in
// structure_src. The parent computes next-state transitions so simultaneous
// IM, NEL, and WBC events retain the existing Gen4 cycle boundary.
module flow_detect_unit #(
    parameter bit INITIAL_ACTIVE = 1'b0
) (
    input  logic clk,
    input  logic reset_n,
    input  logic i_active_next,
    input  logic i_closed_next,
    input  logic i_discard_next,
    input  logic [31:0] i_pending_next,
    input  logic [31:0] i_inflight_next,
    input  logic [31:0] i_order_next,
    output logic o_active,
    output logic o_closed,
    output logic o_discard,
    output logic [31:0] o_pending,
    output logic [31:0] o_inflight,
    output logic [31:0] o_order
);
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            o_active <= INITIAL_ACTIVE;
            o_closed <= 1'b0;
            o_discard <= 1'b0;
            o_pending <= '0;
            o_inflight <= '0;
            o_order <= '0;
        end
        else begin
            o_active <= i_active_next;
            o_closed <= i_closed_next;
            o_discard <= i_discard_next;
            o_pending <= i_pending_next;
            o_inflight <= i_inflight_next;
            o_order <= i_order_next;
        end
    end
endmodule
