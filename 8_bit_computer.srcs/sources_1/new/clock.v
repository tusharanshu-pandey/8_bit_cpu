module clock (
    input  wire rst,
    input  wire hlt,
    output reg  clk_out
);
    parameter PERIOD = 5; // ns, override in testbench

    always begin
        if (rst || hlt) begin
            clk_out = 1'b0;
            #(PERIOD);
        end else begin
            #(PERIOD) clk_out = 1'b1;
            #(PERIOD) clk_out = 1'b0;
        end
    end

endmodule