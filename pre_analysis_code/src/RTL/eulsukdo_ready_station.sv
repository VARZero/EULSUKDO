`timescale 1ns/1ps

module eulsukdo_ready_station #(
    parameter int unsigned PC_WIDTH       = 32,
    parameter int unsigned OPERANDS       = 2,
    parameter int unsigned IMM_WIDTH      = 32,
    parameter int unsigned MICROOP_WIDTH  = 5,
    parameter int unsigned PHY_REGS       = 64,
    parameter int unsigned EX_PATHS       = 3,
    parameter int unsigned FLOW_WINDOWS   = 8,
    parameter int unsigned INPUT_PORTS    = 7,
    parameter int unsigned RS_DEPTH       = 16,
    parameter int unsigned ISSUE_PORTS    = 5,
    parameter int unsigned ISSUE_COUNT_WIDTH = 8,
    parameter logic [EX_PATHS*ISSUE_COUNT_WIDTH-1:0] ISSUE_PER_PATH = {8'd1, 8'd3, 8'd1},
    parameter int unsigned PHY_REG_WIDTH  = (PHY_REGS <= 1) ? 1 : $clog2(PHY_REGS),
    parameter int unsigned EX_PATH_WIDTH  = (EX_PATHS <= 1) ? 1 : $clog2(EX_PATHS),
    parameter int unsigned FLOW_WIDTH     = (FLOW_WINDOWS <= 1) ? 1 : $clog2(FLOW_WINDOWS),
    parameter int unsigned INPUT_WIDTH    = PC_WIDTH + FLOW_WIDTH + EX_PATH_WIDTH +
                                            MICROOP_WIDTH + IMM_WIDTH + PHY_REG_WIDTH +
                                            (OPERANDS * PHY_REG_WIDTH),
    parameter int unsigned OUTPUT_WIDTH   = INPUT_WIDTH - EX_PATH_WIDTH,
    parameter int unsigned PTR_WIDTH      = (RS_DEPTH <= 1) ? 1 : $clog2(RS_DEPTH),
    parameter int unsigned COUNT_WIDTH    = $clog2(RS_DEPTH + 1)
) (
    input  logic                              clk,
    input  logic                              reset_n,
    input  logic [INPUT_PORTS-1:0]            i_ist_valid,
    output logic [INPUT_PORTS-1:0]            o_ist_get,
    input  logic [INPUT_PORTS*INPUT_WIDTH-1:0] i_ist_data,
    output logic [ISSUE_PORTS-1:0]            o_ex_valid,
    input  logic [ISSUE_PORTS-1:0]            i_ex_get,
    output logic [ISSUE_PORTS*OUTPUT_WIDTH-1:0] o_ex_data
);
    localparam int unsigned P_PATH = PC_WIDTH + FLOW_WIDTH;
    localparam int unsigned HIGH_WIDTH = INPUT_WIDTH - P_PATH - EX_PATH_WIDTH;

    logic [INPUT_WIDTH-1:0] fifo_mem [0:EX_PATHS-1][0:RS_DEPTH-1];
    logic [PTR_WIDTH-1:0] read_ptr [0:EX_PATHS-1];
    logic [PTR_WIDTH-1:0] write_ptr [0:EX_PATHS-1];
    logic [COUNT_WIDTH-1:0] count [0:EX_PATHS-1];
    integer incoming [0:EX_PATHS-1];
    integer outgoing [0:EX_PATHS-1];
    integer path;
    integer lane;
    integer port;
    integer local_port;
    integer offset;
    integer enqueue_position;
    integer fifo_index;
    logic bundle_fits;
    logic [EX_PATH_WIDTH-1:0] lane_path;
    logic [INPUT_WIDTH-1:0] selected_data;

    function automatic integer port_offset(input integer target_path);
        integer p;
        begin
            port_offset = 0;
            for (p = 0; p < target_path; p = p + 1)
                port_offset = port_offset + ISSUE_PER_PATH[p*ISSUE_COUNT_WIDTH +: ISSUE_COUNT_WIDTH];
        end
    endfunction

    function automatic integer issue_count(input integer target_path);
        issue_count = ISSUE_PER_PATH[target_path*ISSUE_COUNT_WIDTH +: ISSUE_COUNT_WIDTH];
    endfunction

    always_comb begin
        selected_data = '0;
        offset = 0;
        port = 0;
        for (path = 0; path < EX_PATHS; path = path + 1) incoming[path] = 0;
        for (lane = 0; lane < INPUT_PORTS; lane = lane + 1) begin
            lane_path = i_ist_data[lane*INPUT_WIDTH + P_PATH +: EX_PATH_WIDTH];
            if (i_ist_valid[lane] && (lane_path < EX_PATHS)) incoming[lane_path] = incoming[lane_path] + 1;
        end

        bundle_fits = 1'b1;
        for (path = 0; path < EX_PATHS; path = path + 1) begin
            if ((count[path] + incoming[path]) > RS_DEPTH) bundle_fits = 1'b0;
        end
        for (lane = 0; lane < INPUT_PORTS; lane = lane + 1)
            o_ist_get[lane] = i_ist_valid[lane] && bundle_fits;

        o_ex_valid = '0;
        o_ex_data = '0;
        for (path = 0; path < EX_PATHS; path = path + 1) begin
            offset = port_offset(path);
            for (local_port = 0; local_port < issue_count(path); local_port = local_port + 1) begin
                port = offset + local_port;
                if ((port < ISSUE_PORTS) && (local_port < count[path])) begin
                    fifo_index = (read_ptr[path] + local_port) % RS_DEPTH;
                    selected_data = fifo_mem[path][fifo_index];
                    o_ex_valid[port] = 1'b1;
                    o_ex_data[port*OUTPUT_WIDTH +: P_PATH] = selected_data[0 +: P_PATH];
                    o_ex_data[port*OUTPUT_WIDTH + P_PATH +: HIGH_WIDTH] =
                        selected_data[P_PATH+EX_PATH_WIDTH +: HIGH_WIDTH];
                end
            end
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (path = 0; path < EX_PATHS; path = path + 1) begin
                read_ptr[path] <= '0;
                write_ptr[path] <= '0;
                count[path] <= '0;
                for (fifo_index = 0; fifo_index < RS_DEPTH; fifo_index = fifo_index + 1)
                    fifo_mem[path][fifo_index] <= '0;
            end
        end else begin
            for (path = 0; path < EX_PATHS; path = path + 1) begin
                enqueue_position = 0;
                for (lane = 0; lane < INPUT_PORTS; lane = lane + 1) begin
                    lane_path = i_ist_data[lane*INPUT_WIDTH + P_PATH +: EX_PATH_WIDTH];
                    if (i_ist_valid[lane] && o_ist_get[lane] && (lane_path == EX_PATH_WIDTH'(path))) begin
                        fifo_index = (write_ptr[path] + enqueue_position) % RS_DEPTH;
                        fifo_mem[path][fifo_index] <= i_ist_data[lane*INPUT_WIDTH +: INPUT_WIDTH];
                        enqueue_position = enqueue_position + 1;
                    end
                end

                outgoing[path] = 0;
                offset = port_offset(path);
                for (local_port = 0; local_port < issue_count(path); local_port = local_port + 1) begin
                    port = offset + local_port;
                    if ((port < ISSUE_PORTS) && o_ex_valid[port] && i_ex_get[port])
                        outgoing[path] = outgoing[path] + 1;
                end

                if (enqueue_position != 0)
                    write_ptr[path] <= PTR_WIDTH'((write_ptr[path] + enqueue_position) % RS_DEPTH);
                if (outgoing[path] != 0)
                    read_ptr[path] <= PTR_WIDTH'((read_ptr[path] + outgoing[path]) % RS_DEPTH);
                if ((enqueue_position != 0) || (outgoing[path] != 0))
                    count[path] <= COUNT_WIDTH'(count[path] + enqueue_position - outgoing[path]);
            end
        end
    end

    initial begin
        if (RS_DEPTH < INPUT_PORTS || ISSUE_PORTS < 1)
            $error("Invalid EULSUKDO RS parameters");
        if (port_offset(EX_PATHS) != ISSUE_PORTS)
            $error("ISSUE_PORTS must equal the sum of ISSUE_PER_PATH");
    end
endmodule
