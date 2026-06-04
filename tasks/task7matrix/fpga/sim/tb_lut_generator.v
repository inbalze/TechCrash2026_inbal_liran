`timescale 1ns/1ps

module tb_lut_generator;

    reg clk;
    reg rst_n;
    reg start;
    reg [7:0] a;
    reg [7:0] b;
    wire [7:0] result;
    wire done;
    wire busy;

    // Instantiate existing fp8_adder
    fp8_adder dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .a(a),
        .b(b),
        .result(result),
        .done(done),
        .busy(busy)
    );

    // Clock generator (100 MHz clock, 10ns period)
    always #5 clk = ~clk;

    integer file_id;
    integer i, j;

    initial begin
        clk = 0;
        rst_n = 0;
        start = 0;
        a = 0;
        b = 0;

        #20;
        rst_n = 1;
        #20;

        file_id = $fopen("../src/fp8_lut.hex", "w");
        if (file_id == 0) begin
            $display("Error: Could not open file fp8_lut.hex for writing");
            $finish;
        end

        for (i = 0; i < 256; i = i + 1) begin
            for (j = 0; j < 256; j = j + 1) begin
                // Apply inputs
                a = i[7:0];
                b = j[7:0];
                start = 1;
                @(posedge clk);
                start = 0;
                
                // Wait for done to assert
                while (!done) begin
                    @(posedge clk);
                end
                
                // Write hex result to file
                $fdisplay(file_id, "%02h", result);
            end
        end

        $fclose(file_id);
        $display("Done generating fp8_lut.hex!");
        $finish;
    end

endmodule
