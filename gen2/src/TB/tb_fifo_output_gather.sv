`timescale 1ns/1ps

module tb_fifo_output_gather #(
    parameter int DATA_WIDTH = 92,
    parameter int FIFO_CHANNEL = 7,
    parameter int READ_CHANNEL = 3
);
    logic [2*FIFO_CHANNEL-1:0] in_valid, actual_valid, reference_valid;
    logic [2*FIFO_CHANNEL*DATA_WIDTH-1:0] in_data, actual_data, reference_data;
    int cases = 0;
    fifo_output_gather #(
        .DATA_WIDTH(DATA_WIDTH), .FIFO_CHANNEL(FIFO_CHANNEL), .READ_CHANNEL(READ_CHANNEL)
    ) dut (.i_valid(in_valid), .i_data(in_data), .o_valid(actual_valid), .o_data(actual_data));
    valid_gather #(.DATA_WIDTH(DATA_WIDTH), .ENTRIES(2*FIFO_CHANNEL)) reference_gather (
        .i_valid(in_valid), .i_data(in_data), .o_valid(reference_valid), .o_data(reference_data)
    );

    initial begin
        // All legal shapes at the gather boundary: two prefix-valid halves,
        // followed by any subset of pops in the lower half's visible head.
        for (int low = 0; low <= FIFO_CHANNEL; low++) begin
            for (int upper = 0; upper <= FIFO_CHANNEL; upper++) begin
                for (int mask = 0; mask < (1 << READ_CHANNEL); mask++) begin
                    in_valid = '0;
                    for (int lane = 0; lane < 2*FIFO_CHANNEL; lane++) begin
                        in_valid[lane] = (lane < FIFO_CHANNEL) ? (lane < low) : (lane-FIFO_CHANNEL < upper);
                        if (lane < READ_CHANNEL && (((mask >> lane) & 1) != 0)) in_valid[lane] = 0;
                        for (int bit_idx = 0; bit_idx < DATA_WIDTH; bit_idx++)
                            in_data[lane*DATA_WIDTH+bit_idx] = 1'($urandom_range(0, 1));
                    end
                    #1;
                    // Includes invalid lanes: both implementations zero them.
                    if (actual_valid !== reference_valid || actual_data !== reference_data)
                        $fatal(1, "Gather mismatch low=%0d upper=%0d pop=%h", low, upper, mask);
                    cases++;
                end
            end
        end
        $display("PASS FIFO output gather F=%0d R=%0d cases=%0d", FIFO_CHANNEL, READ_CHANNEL, cases);
        $finish;
    end
endmodule
