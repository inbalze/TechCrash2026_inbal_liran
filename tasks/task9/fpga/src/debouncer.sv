module debouncer #(
    parameter CLK_FREQ = 50000000,
    parameter DEBOUNCE_TIME_MS = 20
)(
    input  logic clk,
    input  logic rst_n,
    input  logic in,
    output logic out
);
    localparam CNT_MAX = (CLK_FREQ / 1000) * DEBOUNCE_TIME_MS;
    logic [$clog2(CNT_MAX):0] counter;
    logic in_sync_0, in_sync_1;
    logic state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_sync_0 <= 1'b1;
            in_sync_1 <= 1'b1;
            state     <= 1'b1;
            counter   <= '0;
        end else begin
            in_sync_0 <= in;
            in_sync_1 <= in_sync_0;
            
            if (in_sync_1 != state) begin
                if (counter == CNT_MAX - 1) begin
                    state <= in_sync_1;
                    counter <= '0;
                end else begin
                    counter <= counter + 1'b1;
                end
            end else begin
                counter <= '0;
            end
        end
    end

    assign out = state;
endmodule
