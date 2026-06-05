module edge_detector (
    input  logic clk,
    input  logic rst_n,
    input  logic in,
    output logic falling_edge
);
    logic in_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_r <= 1'b1;
        end else begin
            in_r <= in;
        end
    end

    assign falling_edge = (in_r == 1'b1) && (in == 1'b0);
endmodule
