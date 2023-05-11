`timescale 1ns / 1ps

module Debouncer(
    input clk,                     // 100MHz clock
    input [4:0] in,                // Undebounced button signal
    output reg [4:0] out_curr = 0, // Current debounced button signal
    output reg [4:0] out_prev = 0  // Previous debounced button signal
    );
    
    reg [4:0] in_prev = 0;
    reg [20:0] count = 0;
    
    always @ (posedge clk) begin
        if (in == in_prev) begin
            if (count == {21{1'b1}}) begin
                // If current == prev == 0 -> Buttons are unpressed
                // If current  > prev      -> Buttons are pressed
                // If current  < prev      -> Buttons are released
                // If current == prev  > 0 -> Buttons are held
                out_curr <= in;
                out_prev <= out_curr;
            end else begin
                count <= count + 1;
            end
        end else begin
            count <=  0;
        end
        in_prev <= in;
    end
endmodule
