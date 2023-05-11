`timescale 1ns / 1ps

module Main(
    input sysclk,          // 100MHz clock
    input [4:0] btn,
    input [1:0] sw,
    output [3:0] an,
    output [7:0] seg,
    output [7:0] JC,       // OLED Display port
    inout ps2_clk,         // Used for mouse
    inout ps2_data         // Used for mouse
    );
    
    // OLED Display
    wire signal6p25M, signal50M;
    wire [12:0] pixel_index;
    wire [15:0] colour_data;
    wire [7:0] pixel_x = pixel_index % 96, pixel_y = pixel_index / 96;
    
    Clock clk50M(.sysclk(sysclk), .compare(1), .out(signal50M));
    Clock clk6p25M(.sysclk(sysclk), .compare(7), .out(signal6p25M));
    Oled_Display display_module(
        .clk(signal6p25M),
        .reset(0),
        .cs(JC[0]),
        .sdin(JC[1]),
        .sclk(JC[3]),
        .d_cn(JC[4]),
        .resn(JC[5]),
        .vccen(JC[6]),
        .pmoden(JC[7]),
        .pixel_index(pixel_index),
        .pixel_data(colour_data)
    );
    
    // Mouse
    wire left, middle, right;
    wire [11:0] mouse_x_original, mouse_y_original;
    wire [7:0] mouse_x = mouse_x_original >> 1, mouse_y = mouse_y_original >> 1;
    wire [3:0] mouse_z;
    
    MouseCtl mouse_module(
        .clk(signal50M),
        .ps2_clk(ps2_clk),
        .ps2_data(ps2_data),
        .rst(0),
        .setx(0),
        .sety(0),
        .value(0),
        .invert(sw[1]),
        .setmax_x(0),
        .setmax_y(0),
        .left(left),
        .middle(middle),
        .right(right),
        .xpos(mouse_x_original),
        .ypos(mouse_y_original),
        .zpos(mouse_z)
    );
    
    wire [4:0] btn_curr, btn_prev;
    Debouncer debounce(.clk(signal50M), .in(btn), .out_curr(btn_curr), .out_prev(btn_prev));
    
    wire [11:0] word_select;
    Test test_module(
        .enabled(sw[0]),
        .clk(signal50M),
        .clk_slower(signal6p25M),
        .left(left),
        .btn_curr(btn_curr),
        .btn_prev(btn_prev),
        .mouse_invert(sw[1]),
        .mouse_x(mouse_x),
        .mouse_y(mouse_y),
        .mouse_z(mouse_z),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .pixel_index(pixel_index),
        .word_select(word_select),
        .colour(colour_data)
    );
    
    // Seven Segment Display
    reg [15:0] sed_digits_in = 0;
    reg [31:0] sed_data = 0;
    wire [31:0] sed_digits_out;
    
    SedDigitConverter sed_digits(.val(sed_digits_in), .digits_out(sed_digits_out));
    SedDisplay sed_module(.clk(signal50M), .val(sed_data), .seg(seg), .an(an));
    
    always @ (posedge signal50M) begin
        sed_digits_in <= word_select >= 2315 ? word_select - 2314 : word_select + 1;
        sed_data <= sed_digits_out;
    end
endmodule

module Test(
    input enabled,
    input clk,
    input clk_slower,
    input left,
    input [4:0] btn_curr,
    input [4:0] btn_prev,
    input mouse_invert,
    input [7:0] mouse_x,
    input [7:0] mouse_y,
    input [3:0] mouse_z,
    input [7:0] pixel_x,
    input [7:0] pixel_y,
    input [12:0] pixel_index,
    output reg [11:0] word_select,
    output [15:0] colour
    );
    
    parameter COLOUR_BLACK     = 16'h0000;
    parameter COLOUR_BLUE      = 16'h4259;
    parameter COLOUR_BROWN     = 16'hB3CA;
    parameter COLOUR_CYAN      = 16'h8FFF;
    parameter COLOUR_DARK_GRAY = 16'h8410;
    parameter COLOUR_GRAY      = 16'hD69A;
    parameter COLOUR_GREEN     = 16'h07E0;
    parameter COLOUR_LIME      = 16'hC7E2;
    parameter COLOUR_ORANGE    = 16'hFD20;
    parameter COLOUR_PINK      = 16'hFDF9;
    parameter COLOUR_RED       = 16'hE8E4;
    parameter COLOUR_WHITE     = 16'hFFFF;
    parameter COLOUR_YELLOW    = 16'hFFE0;
    
    reg left_prev = 0;
    reg [31:0] random = 1234567890, reset_timer = 0;
    reg mouse_z_prev = 0;
    wire cursor_enabled;
    wire [7:0] actual_mouse_x = mouse_invert ? mouse_y : mouse_x;
    wire [7:0] actual_mouse_y = mouse_invert ? (8'd63 - mouse_x) : mouse_y;
    wire [12:0] mouse_index = 13'd96 * actual_mouse_y + actual_mouse_x;
    Cursor cursor(.pixel_x(pixel_x), .pixel_y(pixel_y), .mouse_x(actual_mouse_x), .mouse_y(actual_mouse_y), .radius(2'h1), .enabled(cursor_enabled));
    
    reg [15:0] grid_lut [0:6143];
    initial $readmemh("grid_pos.mem", grid_lut);
    reg [7:0] grid_lut2 [0:6143];
    initial $readmemh("grid_pos2.mem", grid_lut2);
    
    // [15:14] is type of pixel (2'b00: background, 2'b01: grid square, 2'b10: grid outline, 2'b11: buttons)
    wire [15:0] pixel_info = grid_lut[pixel_index];
    wire [15:0] pixel_info2 = grid_lut2[mouse_index];
    // 5 rows, 7 columns
    // [6:5] is the background colour, [4:0] is the letter, from 1 to 26, with 0 for no letter
    // Background: 0 (white), 1 (green), 2 (yellow), 3 (gray)
    reg [6:0] letters [0:4][0:7];
    initial begin
        letters[4][7] <= 0; letters[3][7] <= 28; letters[2][7] <= 0; letters[1][7] <= 30; letters[0][7] <= 0;
    end
    
    wire isForeground;
    // 0 - Before RNG, 1 - Playing, 2 - Checking, 3 - Ended
    reg [1:0] state = 0;
    reg [24:0] selected_word = 0;
    reg [6:0] drawn_letter = 0;
    reg [2:0] curr_letter_x;
    reg [2:0] curr_letter_y;
    reg [15:0] colour_data = 0;
    SpriteRetriever sprite(.clk(clk_slower), .letter(drawn_letter[4:0]), .x(pixel_info[3:0]), .y(pixel_info[7:4]), .foreground(isForeground));
    
    reg check_start = 0;
    wire done, valid;
    wire [9:0] correct;
    wire [24:0] current_word;
    WordSelector word_getter(
        .clk(clk_slower), .check_start(check_start),
        .check_word({letters[0][curr_letter_x][4:0], letters[1][curr_letter_x][4:0], letters[2][curr_letter_x][4:0], letters[3][curr_letter_x][4:0], letters[4][curr_letter_x][4:0]}),
        .select(word_select), .selected_word(current_word),
        .done(done), .valid(valid), .correct(correct)
    );
    
    assign colour = enabled ? (cursor_enabled ? COLOUR_RED : colour_data) : 16'hz;
    
    always @ (posedge clk) begin
        random <= random + 1;
        if (enabled) begin
            if (state == 0) begin
                state <= 1;
                // Use a counter as a PRNG since reset trigger time is likely to be random
                word_select <= random;
                curr_letter_x <= 0;
                curr_letter_y <= 4;
                letters[3][7] <= 28;
                letters[4][0] <= 0; letters[3][0] <= 0; letters[2][0] <= 0; letters[1][0] <= 0; letters[0][0] <= 0;
                letters[4][1] <= 0; letters[3][1] <= 0; letters[2][1] <= 0; letters[1][1] <= 0; letters[0][1] <= 0;
                letters[4][2] <= 0; letters[3][2] <= 0; letters[2][2] <= 0; letters[1][2] <= 0; letters[0][2] <= 0;
                letters[4][3] <= 0; letters[3][3] <= 0; letters[2][3] <= 0; letters[1][3] <= 0; letters[0][3] <= 0;
                letters[4][4] <= 0; letters[3][4] <= 0; letters[2][4] <= 0; letters[1][4] <= 0; letters[0][4] <= 0;
                letters[4][5] <= 0; letters[3][5] <= 0; letters[2][5] <= 0; letters[1][5] <= 0; letters[0][5] <= 0;
                letters[4][6] <= 0; letters[3][6] <= 0; letters[2][6] <= 0; letters[1][6] <= 0; letters[0][6] <= 0;
            end else begin
                selected_word <= current_word;
                letters[4][6] <= selected_word[4:0];
                letters[3][6] <= selected_word[9:5];
                letters[2][6] <= selected_word[14:10];
                letters[1][6] <= selected_word[19:15];
                letters[0][6] <= selected_word[24:20];
                drawn_letter <= letters[pixel_info[13:11]][pixel_info[10:8]];
                
                case (pixel_info[15:14])
                    2'b00: begin
                        colour_data <= COLOUR_WHITE;
                    end
                    2'b01: begin
                        if (isForeground) begin
                            // Foregound of letter is black except for answer row, which is hidden until game end
                            colour_data <= pixel_info[10:8] == 6 & state != 3 ? COLOUR_WHITE : COLOUR_BLACK;
                        end else begin
                            // Background of letter depends on the situation
                            case (drawn_letter[6:5])
                                2'b00: colour_data <= pixel_info[13:11] == curr_letter_y & pixel_info[10:8] == curr_letter_x ? COLOUR_ORANGE : COLOUR_WHITE; // current word
                                2'b01: colour_data <= COLOUR_GREEN;  // submitted word, correct
                                2'b10: colour_data <= COLOUR_YELLOW; // submitted word, correct position
                                2'b11: colour_data <= COLOUR_GRAY;   // submitted word, wrong
                                default: colour_data <= pixel_index; // should not happen
                            endcase
                        end
                    end
                    2'b10: begin
                        colour_data <= COLOUR_DARK_GRAY;
                    end
                    2'b11: begin
                        case (drawn_letter[4:0])
                            28: colour_data <= state == 3 ? COLOUR_WHITE : (isForeground ? COLOUR_LIME : COLOUR_GREEN); // Confirm button
                            29: colour_data <= isForeground ? COLOUR_PINK : COLOUR_RED;  // Incorrect indicator
                            30: colour_data <= isForeground ? COLOUR_CYAN : COLOUR_BLUE; // Reset button
                            default: colour_data <= COLOUR_WHITE; // Unused squares: white
                        endcase
                    end
                endcase
                
                left_prev <= left;
                if (left & ~left_prev) begin
                    case (pixel_info2[7:6])
                        2'b01: begin
                            if (pixel_info2[2:0] == curr_letter_x) begin
                                curr_letter_y <= pixel_info2[5:3];
                            end
                        end
                        2'b10: state <= state == 1 ? 2 : state;
                        2'b11: state <= 0;
                    endcase
                end
                
                if (state == 1) begin
                    if (mouse_z[0] & ~mouse_z_prev) begin
                        letters[3][7] <= 28;
                        if (mouse_z[3])
                            letters[curr_letter_y][curr_letter_x] <= letters[curr_letter_y][curr_letter_x] == 0 ? 26 : letters[curr_letter_y][curr_letter_x] - 1;
                        else
                            letters[curr_letter_y][curr_letter_x] <= letters[curr_letter_y][curr_letter_x] == 26 ? 0 : letters[curr_letter_y][curr_letter_x] + 1;
                    end
                    
                    
                    if (btn_curr[0] > btn_prev[0]) begin // Right button
                        curr_letter_y <= curr_letter_y == 0 ? 4 : curr_letter_y - 1;
                    end
                    if (btn_curr[2] > btn_prev[2]) begin // Left button
                        curr_letter_y <= curr_letter_y == 4 ? 0 : curr_letter_y + 1;
                    end
                    if (btn_curr[1] > btn_prev[1]) begin // Bottom button
                        letters[3][7] <= 28;
                        letters[curr_letter_y][curr_letter_x] <= letters[curr_letter_y][curr_letter_x] == 26 ? 0 : letters[curr_letter_y][curr_letter_x] + 1;
                    end
                    if (btn_curr[3] > btn_prev[3]) begin // Top button
                        letters[3][7] <= 28;
                        letters[curr_letter_y][curr_letter_x] <= letters[curr_letter_y][curr_letter_x] == 0 ? 26 : letters[curr_letter_y][curr_letter_x] - 1;
                    end
                    if (btn_curr[4] > btn_prev[4]) begin // Center button
                        state <= 2;
                    end
                end
                
                if (state == 2) begin
                    check_start <= 1;
                    if (done) begin
                        check_start <= 0;
                        if (correct == 10'b0101010101) begin
                            state <= 3;
                            letters[4][curr_letter_x][6:5] <= correct[9:8];
                            letters[3][curr_letter_x][6:5] <= correct[7:6];
                            letters[2][curr_letter_x][6:5] <= correct[5:4];
                            letters[1][curr_letter_x][6:5] <= correct[3:2];
                            letters[0][curr_letter_x][6:5] <= correct[1:0];
                        end else begin
                            if (valid) begin
                                if (curr_letter_x < 5) begin
                                    state <= 1;
                                    curr_letter_y <= 4;
                                    curr_letter_x <= curr_letter_x + 1;
                                end else begin
                                    state <= 3;
                                end
                                letters[4][curr_letter_x][6:5] <= correct[9:8];
                                letters[3][curr_letter_x][6:5] <= correct[7:6];
                                letters[2][curr_letter_x][6:5] <= correct[5:4];
                                letters[1][curr_letter_x][6:5] <= correct[3:2];
                                letters[0][curr_letter_x][6:5] <= correct[1:0];
                            end else begin
                                state <= 1;
                                letters[3][7] <= 29;
                            end
                        end
                    end
                end
                
                mouse_z_prev <= mouse_z[0];
                if (btn_curr[4] == btn_prev[4] & btn_curr[4] == 1) begin
                    if (reset_timer == 50_000_000) begin // Hold center button for 1 second to reset
                        reset_timer <= 0;
                        state <= 0;
                    end else begin
                        reset_timer <= reset_timer + 1;
                    end
                end else begin
                    reset_timer <= 0;
                end
            end
        end
    end
endmodule

module SpriteRetriever(
    input clk,
    input [4:0] letter,
    input [3:0] x,
    input [3:0] y,
    output reg foreground = 0
    );
    
    reg [9:0] sprites [0:309];
    initial $readmemb("sprites.mem", sprites);
    
    always @ (posedge clk) begin
        foreground <= sprites[letter * 10 + y][x];
    end
endmodule

module WordSelector(
    input clk,
    input check_start,
    input [24:0] check_word,
    input [11:0] select,
    output reg done = 0,
    output reg valid = 0,
    output reg [9:0] correct = 0,
    output reg [24:0] selected_word = 0
    );
    
    parameter NUM_VALID = 12972;
    parameter NUM_CORRECT = 2315;
    
    reg [13:0] check_count;
    reg [24:0] words [0:NUM_VALID-1];
    initial $readmemb("words.mem", words);
    reg [1:0] letter_count [0:25];
    
    always @ (posedge clk) begin
        selected_word <= select >= NUM_CORRECT ? words[select - NUM_CORRECT] :  words[select];
        
        if (check_start) begin
            if (~done) begin
                if (check_count == NUM_VALID) begin
                    done = 1;
                    valid = 0;
                    correct = 0;
                end else if (check_word == words[check_count]) begin
                    if (check_word == selected_word) begin
                        correct = 10'b0101010101;
                    end else if (check_word == words[check_count]) begin
                        if (check_word[4:0] == selected_word[4:0])
                            correct[9:8] = 2'b01;
                        else
                            letter_count[selected_word[4:0]] = letter_count[selected_word[4:0]] + 1;
                        
                        if (check_word[9:5] == selected_word[9:5])
                            correct[7:6] = 2'b01;
                        else
                            letter_count[selected_word[9:5]] = letter_count[selected_word[9:5]] + 1;
                        
                        if (check_word[14:10] == selected_word[14:10])
                            correct[5:4] = 2'b01;
                        else
                            letter_count[selected_word[14:10]] = letter_count[selected_word[14:10]] + 1;
                        
                        if (check_word[19:15] == selected_word[19:15])
                            correct[3:2] = 2'b01;
                        else
                            letter_count[selected_word[19:15]] = letter_count[selected_word[19:15]] + 1;
                        
                        if (check_word[24:20] == selected_word[24:20])
                            correct[1:0] = 2'b01;
                        else
                            letter_count[selected_word[24:20]] = letter_count[selected_word[24:20]] + 1;
                        
                        if (correct[9:8] == 2'b00) begin
                            if (letter_count[check_word[4:0]]) begin
                                correct[9:8] = 2'b10;
                                letter_count[check_word[4:0]] = letter_count[check_word[4:0]] - 1;
                            end else begin
                                correct[9:8] = 2'b11;
                            end
                        end
                        
                        if (correct[7:6] == 2'b00) begin
                            if (letter_count[check_word[9:5]]) begin
                                correct[7:6] = 2'b10;
                                letter_count[check_word[9:5]] = letter_count[check_word[9:5]] - 1;
                            end else begin
                                correct[7:6] = 2'b11;
                            end
                        end
                        
                        if (correct[5:4] == 2'b00) begin
                            if (letter_count[check_word[14:10]]) begin
                                correct[5:4] = 2'b10;
                                letter_count[check_word[14:10]] = letter_count[check_word[14:10]] - 1;
                            end else begin
                                correct[5:4] = 2'b11;
                            end
                        end
                        
                        if (correct[3:2] == 2'b00) begin
                            if (letter_count[check_word[19:15]]) begin
                                correct[3:2] = 2'b10;
                                letter_count[check_word[19:15]] = letter_count[check_word[19:15]] - 1;
                            end else begin
                                correct[3:2] = 2'b11;
                            end
                        end
                        
                        if (correct[1:0] == 2'b00) begin
                            if (letter_count[check_word[24:20]]) begin
                                correct[1:0] = 2'b10;
                                letter_count[check_word[24:20]] = letter_count[check_word[24:20]] - 1;
                            end else begin
                                correct[1:0] = 2'b11;
                            end
                        end
                    end
                    done = 1;
                    valid = 1;
                end else begin
                    check_count = check_count + 1;
                end
            end
        end else begin
            letter_count[0] = 0; letter_count[1] = 0; letter_count[2] = 0; letter_count[3] = 0; letter_count[4] = 0; letter_count[5] = 0; letter_count[6] = 0; letter_count[7] = 0; letter_count[8] = 0; letter_count[9] = 0; letter_count[10] = 0; letter_count[11] = 0; letter_count[12] = 0; letter_count[13] = 0; letter_count[14] = 0; letter_count[15] = 0; letter_count[16] = 0; letter_count[17] = 0; letter_count[18] = 0; letter_count[19] = 0; letter_count[20] = 0; letter_count[21] = 0; letter_count[22] = 0; letter_count[23] = 0; letter_count[24] = 0; letter_count[25] = 0;
            check_count = 0;
            done = 0;
            valid = 0;
            correct = 0;
        end
    end
endmodule

module Cursor(
    input [7:0] pixel_x, // The x position of the current pixel being coloured
    input [7:0] pixel_y, // The y position of the current pixel being coloured
    input [7:0] mouse_x, // The x position of the mouse
    input [7:0] mouse_y, // The y position of the mouse
    input [1:0] radius,   // Radius of the cursor, which is a square. The result is a square with length (2 * radius + 1)
    output enabled       // Whether this pixel should be coloured, depending on whether it is within the cursor radius
    );
    
    // Conversion to signed is needed because when pixel_x is unsigned 0 and radius > 0, (pixel_x - radius) underflows
    assign enabled = $signed(pixel_x - radius) <= $signed(mouse_x)
                     & mouse_x <= pixel_x + radius
                     & $signed(pixel_y - radius) <= $signed(mouse_y)
                     & mouse_y <= pixel_y + radius;
endmodule
