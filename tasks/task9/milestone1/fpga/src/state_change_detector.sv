module state_change_detector (
    input  logic clk,
    input  logic rst_n,
    input  logic [3:0] val,
    output logic changed,
    output logic [3:0] registered_val
);
    logic [3:0] val_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            val_r          <= 4'd0;
            changed        <= 1'b0;
            registered_val <= 4'd0;
        end else begin
            val_r          <= val;
            registered_val <= val_r;
            if (val != val_r) begin
                changed <= 1'b1;
            end else begin
                changed <= 1'b0;
            end
        end
    end
endmodule
