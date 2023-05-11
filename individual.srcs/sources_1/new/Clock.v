`timescale 1ns / 1ps

module Clock(
    input sysclk,         // 100MHz clock
    input [31:0] compare, // Value to compare to
    output reg out = 0    // New clock signal
    );
    
    reg [31:0] count = 0;
    
    always @ (posedge sysclk) begin
        count <= count >= compare ? 0 : count + 1;
        out <= count == 0 ? ~out : out;
    end
endmodule
