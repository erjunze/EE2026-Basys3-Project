`timescale 1ns / 1ps

module SedDisplay(
    input clk,                        // 50MHz clock
    input [31:0] val,                 // Input value
    output reg [7:0] seg = {8{1'b1}},
    output reg [3:0] an = {4{1'b1}}
    );
    
    // Refresh rate 60Hz -> change through digits at 240Hz
    wire wire400Hz;
    
    Clock clk400Hz(clk, 62_499, wire400Hz);
    
    always @ (posedge wire400Hz) begin
        case (an)
            4'b1110: begin
                seg <= val[15:8];
                an <= 4'b1101;
            end
            4'b1101: begin
                seg <= val[23:16];
                an <= 4'b1011;
            end
            4'b1011: begin
                seg <= val[31:24];
                an <= 4'b0111;
            end
            4'b0111: begin
                seg <= val[7:0];
                an <= 4'b1110;
            end
            default: an <= 4'b1110;
        endcase
    end
endmodule

module SedDigitConverter #(HexMode = 0)( // Whether to output display value in hexadecimal
    input [15:0] val,                    // Input value
    output reg [31:0] digits_out = 0     // Value to control the seven segment display
    );
    
    // {F, E, D, C, B, A, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0}
    parameter [127:0] Digits = {8'h8E, 8'h86, 8'hA1, 8'hC6, 8'h83, 8'h88, 8'h90, 8'h80, 8'hF8, 8'h82, 8'h92, 8'h99, 8'hB0, 8'hA4, 8'hF9, 8'hC0};
    reg [3:0] digit = 0;
    
    always @ (val) begin
        digits_out[7:0] = Digits[8 * (HexMode ? val[3:0] : val % 10) +: 8];
        digits_out[15:8] = Digits[8 * (HexMode ? val[7:4] : (val / 10) % 10) +: 8];
        digits_out[23:16] = Digits[8 * (HexMode ? val[11:8] : (val / 100) % 10) +: 8];
        digits_out[31:24] = Digits[8 * (HexMode ? val[15:12] : (val / 1000) % 10) +: 8];
    end
endmodule
