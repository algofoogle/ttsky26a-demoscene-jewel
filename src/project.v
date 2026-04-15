/*
 * Copyright (c) 2026 Anton Maurovic
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_algofoogle_dottee(
  input  wire [7:0] ui_in,    // Dedicated inputs
  output wire [7:0] uo_out,   // Dedicated outputs
  input  wire [7:0] uio_in,   // IOs: Input path
  output wire [7:0] uio_out,  // IOs: Output path
  output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
  input  wire       ena,      // always 1 when the design is powered, so you can ignore it
  input  wire       clk,      // clock
  input  wire       rst_n     // reset_n - low to reset
);

  localparam DOTBITS = 6; //NOTE: Increasing to 6 gives quadrant colours, like gems.

  // VGA signals
  wire hsync;
  wire vsync;
  wire [1:0] R;
  wire [1:0] G;
  wire [1:0] B;
  wire video_active;
  wire [9:0] h;
  // + (v[6]<<5) // Worm
  // + (v>>5) // Minor shift makes it more interesting.
  wire [9:0] v;

  // TinyVGA PMOD
  assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

  // TT Audio PMOD
  assign uio_out[7] = 0;//(&counter[0:0]) ? hit : (delta[7] ^ r[4]); // Weird motor sound: d[4] ^ r[1]; Also try d[9]
  assign uio_oe[7] = 1;

  // Unused outputs assigned to 0.
  assign uio_out[6:0] = 0;
  assign uio_oe[6:0]  = 0;

  // Suppress unused signals warning
  wire _unused_ok = &{ena, ui_in, uio_in};

  reg [9:0] counter;

  hvsync_generator hvsync_gen(
    .clk(clk),
    .reset(~rst_n),
    .hsync(hsync),
    .vsync(vsync),
    .display_on(video_active),
    .hpos(h),
    .vpos(v)
  );

  wire [5:0] rgb;
  wire [5:0] rgb1;
  wire [5:0] rgb2;

  //assign rgb = (0) ? rgb1 : rgb2;//rgb2<<(rgb1>>2);
  // Also pretty (but currently for static BG, no motion):
  //assign rgb = ((((h-16)&9'b100000)^((v-16)&9'b100000))&&(h[6]^v[6])) ? rgb1 : rgb2;//rgb2<<(rgb1>>2); // Can make fish scales with dense half-circles.

  wire ndy;
  not_done_yet message(.hcount(h), .vcount(v), .pixel(ndy));
  assign rgb = 
    (v[8:7]==2'b01) ? {6{ndy}} :
    rgb1 & ({6{(v[8:7]!=2'b01)& (h[2]^v[2])& (h[0]^v[0])}});

  reg [19:0] hlut;

  background_generator #(.DOTBITS(6)) bgen(
    .h(h),//-counter),
    .v(v),
    .counter(counter),
    .rgb(rgb1)
  );

  background_generator #(.DOTBITS(6)) bgen2(
    .h(hlut[11:2]+32-counter),
    .v(v+32),
    .counter(counter),
    .rgb(rgb2)
  );

  assign R = video_active ? rgb[5:4] : 2'b00;
  assign G = video_active ? rgb[3:2] : 2'b00;
  assign B = video_active ? rgb[1:0] : 2'b00;

  // wire [9:0] dist2 = $signed(h[5:0]) * $signed(v[5:0]);

  // wire [9:0] comp = $signed(counter*counter)+v+h*v; //$signed(h[9:3]*h[9:3]+counter);

  // wire hit2 = dist2 < comp;

  // wire [5:0] dithery = (counter+{h[3:2],h[5:4],h[9:6]}) & {6{hit2}} & {6{video_active}};

  always @(posedge clk) begin
    if (h == 0 || ~rst_n) begin
      hlut <= 0;
    end else begin
      hlut <= hlut + 4;
    end
  end

  always @(posedge vsync, negedge rst_n) begin
    if (~rst_n) begin
      counter <= 0;
    end else begin
      counter <= counter + 1;
    end
  end


endmodule


module background_generator #(
  parameter DOTBITS=6
) (
  input [9:0] h,
  input [9:0] v,
  input [9:0] counter,
  output [5:0] rgb
);

  wire signed [9:0] dx = $signed(h[DOTBITS-1:0]);
  wire signed [9:0] dy = $signed(v[DOTBITS-1:0]);

  wire [19:0] d = dx*dx + dy*dy;

  // wire [9:0] r = (counter[DOTBITS-2:0] ^ {(DOTBITS-1){counter[DOTBITS-1]}}) * ({2{hc[7]}} ^ hc[6:5]);

  wire [9:0] r = (counter[DOTBITS-2:0] ^ {(DOTBITS-1){counter[DOTBITS-1]}}) + 1 + ({3{hc[8]}} ^ hc[7:5]);

  wire [9:0] hc = h+(1<<(DOTBITS-1));
  wire [9:0] vc = v+(1<<(DOTBITS-1));
  wire [9:0] hvc = {hc[9:5]+vc[9:5],1'b0} + (counter>>0);

  wire hit = d < r*r; // Also try: h[0]^v[0] ? 0 : d < r*r; and simply: 1;
  wire [9:0] delta = d + r*r; // Subtracting is nice, but so is adding and other logical ops.
  wire [5:0] color = hvc;

  wire [5:0] white = 6'b11_11_11;

  wire sheen = (hc[DOTBITS-1:2]==4'b101 && vc[DOTBITS-1:2]==4'b101);// ||
               //(hc[DOTBITS-1:4]==delta[2:1] && vc[DOTBITS-1:4]==delta[2:1] && (hc[0] ^ vc[0]));

  wire [5:0] altcolor = delta[9:4]; // [9:8] also gives nice blues, and +r is interesting. // &d[9:4] nice anti-tones. // &hvc[9:4] // &counter[9:4] or r or dist2

  assign rgb = 
    sheen ? white :
    hit ? (delta[9:6]+color) : altcolor;  //(dithery & 6'b01_01_01);

endmodule


module not_done_yet(
  input [9:0] hcount,
  input [9:0] vcount,
  output pixel
);

    localparam H_VISIBLE = 640;
    localparam V_VISIBLE = 480;

    // ------------------------------------------------------------------------
    // Text placement
    // 12 chars total: "NOT DONE YET"
    // 8x8 font, no scaling
    // ------------------------------------------------------------------------
    localparam CHAR_W   = 8;
    localparam CHAR_H   = 8;
    localparam MSG_LEN  = 12;
    localparam TEXT_W   = MSG_LEN * CHAR_W;   // 96
    localparam TEXT_H   = CHAR_H;             // 8

    localparam TEXT_X0  = (H_VISIBLE - TEXT_W) / 2;  // 272
    localparam TEXT_Y0  = 192;

    wire in_text_box =
        (hcount >= TEXT_X0) && (hcount < TEXT_X0 + TEXT_W) &&
        (vcount >= TEXT_Y0) && (vcount < TEXT_Y0 + TEXT_H);

    wire [3:0] char_index = (hcount - TEXT_X0) >> 3;  // divide by 8
    wire [9:0] gx = (hcount - TEXT_X0);
    wire [9:0] gy = (vcount - TEXT_Y0);
    wire [2:0] glyph_x    = gx[2:0];
    wire [2:0] glyph_y    = gy[2:0];


    reg [7:0] char_code;
    always @(*) begin
        case (char_index)
            4'd0:  char_code = "N";
            4'd1:  char_code = "O";
            4'd2:  char_code = "T";
            4'd3:  char_code = " ";
            4'd4:  char_code = "D";
            4'd5:  char_code = "O";
            4'd6:  char_code = "N";
            4'd7:  char_code = "E";
            4'd8:  char_code = " ";
            4'd9:  char_code = "Y";
            4'd10: char_code = "E";
            4'd11: char_code = "T";
            default: char_code = " ";
        endcase
    end

    // ------------------------------------------------------------------------
    // 8x8 glyph ROM for just the letters we need
    // Each row is 8 bits, MSB is leftmost pixel
    // ------------------------------------------------------------------------
    reg [7:0] glyph_row;
    always @(*) begin
        case (char_code)

            "N": begin
                case (glyph_y)
                    3'd0: glyph_row = 8'b11000011;
                    3'd1: glyph_row = 8'b11100011;
                    3'd2: glyph_row = 8'b11110011;
                    3'd3: glyph_row = 8'b11011011;
                    3'd4: glyph_row = 8'b11001111;
                    3'd5: glyph_row = 8'b11000111;
                    3'd6: glyph_row = 8'b11000011;
                    3'd7: glyph_row = 8'b00000000;
                endcase
            end

            "O": begin
                case (glyph_y)
                    3'd0: glyph_row = 8'b00111100;
                    3'd1: glyph_row = 8'b01100110;
                    3'd2: glyph_row = 8'b11000011;
                    3'd3: glyph_row = 8'b11000011;
                    3'd4: glyph_row = 8'b11000011;
                    3'd5: glyph_row = 8'b01100110;
                    3'd6: glyph_row = 8'b00111100;
                    3'd7: glyph_row = 8'b00000000;
                endcase
            end

            "T": begin
                case (glyph_y)
                    3'd0: glyph_row = 8'b11111111;
                    3'd1: glyph_row = 8'b00011000;
                    3'd2: glyph_row = 8'b00011000;
                    3'd3: glyph_row = 8'b00011000;
                    3'd4: glyph_row = 8'b00011000;
                    3'd5: glyph_row = 8'b00011000;
                    3'd6: glyph_row = 8'b00011000;
                    3'd7: glyph_row = 8'b00000000;
                endcase
            end

            "D": begin
                case (glyph_y)
                    3'd0: glyph_row = 8'b11111100;
                    3'd1: glyph_row = 8'b11000110;
                    3'd2: glyph_row = 8'b11000011;
                    3'd3: glyph_row = 8'b11000011;
                    3'd4: glyph_row = 8'b11000011;
                    3'd5: glyph_row = 8'b11000110;
                    3'd6: glyph_row = 8'b11111100;
                    3'd7: glyph_row = 8'b00000000;
                endcase
            end

            "E": begin
                case (glyph_y)
                    3'd0: glyph_row = 8'b11111111;
                    3'd1: glyph_row = 8'b11000000;
                    3'd2: glyph_row = 8'b11000000;
                    3'd3: glyph_row = 8'b11111100;
                    3'd4: glyph_row = 8'b11000000;
                    3'd5: glyph_row = 8'b11000000;
                    3'd6: glyph_row = 8'b11111111;
                    3'd7: glyph_row = 8'b00000000;
                endcase
            end

            "Y": begin
                case (glyph_y)
                    3'd0: glyph_row = 8'b11000011;
                    3'd1: glyph_row = 8'b01100110;
                    3'd2: glyph_row = 8'b00111100;
                    3'd3: glyph_row = 8'b00011000;
                    3'd4: glyph_row = 8'b00011000;
                    3'd5: glyph_row = 8'b00011000;
                    3'd6: glyph_row = 8'b00011000;
                    3'd7: glyph_row = 8'b00000000;
                endcase
            end

            " ": begin
                glyph_row = 8'b00000000;
            end

            default: begin
                glyph_row = 8'b00000000;
            end
        endcase
    end

    assign pixel = in_text_box && glyph_row[7 - glyph_x];

endmodule
