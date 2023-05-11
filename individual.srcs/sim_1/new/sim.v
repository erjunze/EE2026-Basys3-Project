`timescale 1ns / 1ps
module sim();
    reg sysclk = 0;
    reg left = 0;
    reg [4:0] btn_curr = 0;
    reg [4:0] btn_prev = 0;
    reg [7:0] mouse_x = 0;
    reg [7:0] mouse_y = 0;
    reg [3:0] mouse_z = 0;
    reg [12:0] pixel_idx = 0;
    wire [7:0] pixel_x;
    wire [7:0] pixel_y;
    wire [15:0] colour;
    
    Test test_module(
        .enabled(1'b1),
        .clk(sysclk),
        .left(left),
        .sampling(sysclk),
        .btn_curr(btn_curr),
        .btn_prev(btn_prev),
        .mouse_x(mouse_x),
        .mouse_y(mouse_y),
        .mouse_z(mouse_z),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .pixel_index(pixel_idx),
        .colour(colour)
    );
    
    always begin
        #5 sysclk = ~sysclk;
    end
    
    always @ (posedge sysclk) begin
        pixel_idx = pixel_idx == 6143 ? 0 : pixel_idx + 1;
    end
    
    assign pixel_x = pixel_idx % 96;
    assign pixel_y = pixel_idx / 96;
    
    initial begin
    end
endmodule
