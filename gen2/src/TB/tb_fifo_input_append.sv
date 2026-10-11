`timescale 1ns/1ps
module tb_fifo_input_append #(
    parameter int DATA_WIDTH = 92,
    parameter int INPUT_CHANNEL = 7,
    parameter int BUFFER_ENTRIES = 14,
    localparam int COUNT_WIDTH = $clog2(BUFFER_ENTRIES+1)
);
    logic [BUFFER_ENTRIES-1:0] retained_valid, actual_valid, expected_valid;
    logic [BUFFER_ENTRIES*DATA_WIDTH-1:0] retained_data, actual_data, expected_data;
    logic [COUNT_WIDTH-1:0] retained_count;
    logic [INPUT_CHANNEL-1:0] in_valid;
    logic [INPUT_CHANNEL*DATA_WIDTH-1:0] in_data;
    int cases = 0, position, incoming;
    fifo_input_append #(
        .DATA_WIDTH(DATA_WIDTH), .INPUT_CHANNEL(INPUT_CHANNEL), .BUFFER_ENTRIES(BUFFER_ENTRIES)
    ) dut (
        .i_retained_valid(retained_valid), .i_retained_data(retained_data), .i_retained_count(retained_count),
        .i_valid(in_valid), .i_data(in_data), .o_valid(actual_valid), .o_data(actual_data)
    );
    initial begin
        for (int kept = 0; kept <= BUFFER_ENTRIES; kept++) begin
            for (int mask = 0; mask < (1 << INPUT_CHANNEL); mask++) begin
                in_valid = INPUT_CHANNEL'(mask);
                incoming = $countones(in_valid);
                if (kept + incoming <= BUFFER_ENTRIES) begin
                    retained_count = COUNT_WIDTH'(kept);
                    retained_valid = '0;
                    expected_valid = '0;
                    expected_data = '0;
                    // Randomize invalid data too: stale lanes must never leak.
                    for (int bit_idx = 0; bit_idx < $bits(retained_data); bit_idx++)
                        retained_data[bit_idx] = 1'($urandom_range(0, 1));
                    for (int bit_idx = 0; bit_idx < $bits(in_data); bit_idx++)
                        in_data[bit_idx] = 1'($urandom_range(0, 1));
                    for (int lane = 0; lane < kept; lane++) begin
                        retained_valid[lane] = 1;
                        expected_valid[lane] = 1;
                        expected_data[lane*DATA_WIDTH +: DATA_WIDTH] = retained_data[lane*DATA_WIDTH +: DATA_WIDTH];
                    end
                    position = kept;
                    for (int lane = 0; lane < INPUT_CHANNEL; lane++) begin
                        if (in_valid[lane]) begin
                            expected_valid[position] = 1;
                            expected_data[position*DATA_WIDTH +: DATA_WIDTH] = in_data[lane*DATA_WIDTH +: DATA_WIDTH];
                            position++;
                        end
                    end
                    #1;
                    if (actual_valid !== expected_valid || actual_data !== expected_data)
                        $fatal(1, "Append mismatch retained=%0d mask=%h", kept, mask);
                    cases++;
                end
            end
        end
        $display("PASS input append W=%0d N=%0d cases=%0d", INPUT_CHANNEL, BUFFER_ENTRIES, cases);
        $finish;
    end
endmodule
