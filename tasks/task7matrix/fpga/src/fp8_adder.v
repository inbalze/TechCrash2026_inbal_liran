module fp8_adder (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [7:0]  a,
    input  wire [7:0]  b,
    output wire [7:0]  result,
    output wire        done,
    output wire        busy
);
    // Infer M9K Block RAM
    reg [7:0] rom [0:65535];
    initial begin
        $readmemh("fp8_lut.hex", rom);
    end

    // 1-Cycle Latency Look-Up
    reg [7:0] r_result;
    reg       r_done;
    
    always @(posedge clk) begin
        r_result <= rom[{a, b}];
        r_done   <= start; 
    end

    // Output assignment
    assign result = r_result;
    assign done   = r_done;
    assign busy   = 1'b0;

endmodule
