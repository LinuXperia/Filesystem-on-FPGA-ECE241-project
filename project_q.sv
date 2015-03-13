module project
  (
   CLOCK_50,                    // On Board 50 MHz
   PS2_CLK, PS2_DAT,
   KEY,                         // Push Button[3:0]
   // SW,                          // DPDT Switch[17:0]
   VGA_CLK,                     // VGA Clock
   VGA_HS,                      // VGA H_SYNC
   VGA_VS,                      // VGA V_SYNC
   VGA_BLANK,                   // VGA BLANK
   VGA_SYNC,                    // VGA SYNC
   VGA_R,                       // VGA Red[9:0]
   VGA_G,                       // VGA Green[9:0]
   VGA_B,                       // VGA Blue[9:0]
   LEDR
   );

   input                        CLOCK_50;  // 50 MHz
   input [3:0]                  KEY;       // Button[3:0]
   // input [17:0]                 SW;        // Switches[17:0]
   output                       VGA_CLK;   // VGA Clock
   output                       VGA_HS;    // VGA H_SYNC
   output                       VGA_VS;    // VGA V_SYNC
   output                       VGA_BLANK; // VGA BLANK
   output                       VGA_SYNC;  // VGA SYNC
   output [9:0]                 VGA_R;     // VGA Red[9:0]
   output [9:0]                 VGA_G;     // VGA Green[9:0]
   output [9:0]                 VGA_B;     // VGA Blue[9:0]

   inout                        PS2_CLK, PS2_DAT;

   // DBG
   output [17:0]                LEDR;

   // Clock
   wire                         clock = CLOCK_50;

   parameter IDLE = 4'd0, HEXDUMP = 4'd1, BROWSER = 4'd2, FILEVIEW = 4'd3,
     FILEEDIT = 4'd4;
   reg [3:0]                    state = IDLE;
   reg [3:0]                    next_state;
   
   // VGA
   wire                         resetn;
   assign resetn = KEY[0];
   wire                         colour;
   wire [8:0]                   x;
   wire [7:0]                   y;
   wire                         plot;
   vga_adapter VGA(
                   .resetn(resetn),
                   .clock(CLOCK_50),
                   .colour(colour),
                   .x(x),
                   .y(y),
                   .plot(plot),
                   /* Signals for the DAC to drive the monitor. */
                   .VGA_R(VGA_R),
                   .VGA_G(VGA_G),
                   .VGA_B(VGA_B),
                   .VGA_HS(VGA_HS),
                   .VGA_VS(VGA_VS),
                   .VGA_BLANK(VGA_BLANK),
                   .VGA_SYNC(VGA_SYNC),
                   .VGA_CLK(VGA_CLK)
                   //                   ,.clock_10(clock)
                   );
   defparam VGA.RESOLUTION = "320x240";
   defparam VGA.MONOCHROME = "TRUE";
   defparam VGA.BITS_PER_COLOUR_CHANNEL = 1;
   defparam VGA.BACKGROUND_IMAGE = "background.mif";

   // KEYBOARD STUFF
   wire                         key_pressed;
   wire [7:0]                   keycode;
   keyboard_decoder keyboard(clock, PS2_CLK, PS2_DAT, key_pressed, keycode);

   // RAM
   reg [7:0]                    RAM_data;
   reg [15:0]                   RAM_addr;
   reg                          RAM_we;
   reg [7:0]                    RAM_q;
   ram  RAM(
            .address ( RAM_addr ),
            .clock ( clock ),
            .data ( RAM_data ),
            .wren ( RAM_we ),
            .q ( RAM_q )
            );

   // ROM
   reg [11:0]                   ROM_addr;
   reg                          ROM_q;
   rom ROM(
           .address ( ROM_addr ),
           .clock ( clock ),
           .q ( ROM_q )
           );
   
   // STREAM
   reg [7:0]                    char_stream [0:1589];
   reg [7:0]                    stream_data;
   reg [10:0]                   stream_addr;
   reg                          stream_we, stream_clr;
   integer                      i;
   always@(posedge clock) begin
      if (stream_we)
        char_stream[stream_addr] <= stream_data;
      else if (stream_clr)
        for (i = 0; i <= 1589; i++) char_stream[i] <= 8'd36;
   end

   // DRAW
   reg draw_start;
   wire draw_done;
   draw draw(clock, ROM_addr, ROM_q, draw_start, draw_done, char_stream, x, y, colour, plot);

   // HEXDUMP
   wire [15:0] RAM_addr_hexdump;
   wire        draw_start_hexdump;
   wire [10:0] stream_addr_hexdump;
   wire [7:0]  stream_data_hexdump;
   wire        stream_clr_hexdump, stream_we_hexdump;
   wire        hexdump_start = (state == HEXDUMP);
   wire        hexdump_done;
   hexdump hexdump(clock, hexdump_start, hexdump_done, RAM_q, RAM_addr_hexdump, draw_done,
                   draw_start_hexdump, stream_addr_hexdump, stream_data_hexdump,
                   stream_clr_hexdump, stream_we_hexdump, key_pressed, keycode);
   
   // BROWSER
   wire [15:0] RAM_addr_browser;
   wire [7:0]  RAM_data_browser;
   wire        RAM_we_browser;
   wire        draw_start_browser;
   wire [10:0] stream_addr_browser;
   wire [7:0]  stream_data_browser;
   wire        stream_clr_browser, stream_we_browser;
   wire        browser_start = (state == BROWSER);
   wire        browser_done;
   wire        want_hexdump;
   wire        want_fileview;
   wire        want_fileedit;
   wire [6:0]  file_block_id;
   browser browser(clock, browser_start, browser_done, want_hexdump, want_fileview,
                   want_fileedit, file_block_id, RAM_q, RAM_addr_browser,
                   RAM_we_browser, RAM_data_browser, draw_done,
                   draw_start_browser, stream_addr_browser, stream_data_browser,
                   stream_clr_browser, stream_we_browser, key_pressed, keycode);

   // FILEVIEW
   wire [15:0] RAM_addr_fileview;
   wire        draw_start_fileview;
   wire [10:0] stream_addr_fileview;
   wire [7:0]  stream_data_fileview;
   wire        stream_clr_fileview, stream_we_fileview;
   wire        fileview_start = (state == FILEVIEW);
   wire        fileview_done;
   fileview fileview(clock, fileview_start, fileview_done, file_block_id, RAM_q, RAM_addr_fileview,
                     draw_done, draw_start_fileview, stream_addr_fileview, stream_data_fileview,
                     stream_clr_fileview, stream_we_fileview, key_pressed, keycode);

   // FILEEDIT
   wire [15:0] RAM_addr_fileedit;
   wire        RAM_we_fileedit;
   wire [7:0]  RAM_data_fileedit;
   wire        draw_start_fileedit;
   wire [10:0] stream_addr_fileedit;
   wire [7:0]  stream_data_fileedit;
   wire        stream_clr_fileedit, stream_we_fileedit;
   wire        fileedit_start = (state == FILEEDIT);
   wire        fileedit_done;
   fileedit fileedit(clock, fileedit_start, fileedit_done, file_block_id, RAM_q,
                     RAM_addr_fileedit, RAM_we_fileedit, RAM_data_fileedit, draw_done,
                     draw_start_fileedit, stream_addr_fileedit, stream_data_fileedit,
                     stream_clr_fileedit, stream_we_fileedit, key_pressed, keycode);


   always@* begin
      case (state)
        IDLE: begin
           RAM_addr = 16'd0;
           RAM_data = 8'dx;
           RAM_we = 1'b0;
           draw_start = 1'b0;
           stream_we = 1'b0;
           stream_addr = 11'd0;
           stream_data = 8'bx;
           stream_clr = 1'b0;

           // if (~KEY[1])
           next_state = BROWSER;
           // else
           //   next_state = IDLE;
        end
        HEXDUMP: begin
           RAM_addr = RAM_addr_hexdump;
           RAM_data = 8'bx;
           RAM_we = 1'b0;
           draw_start = draw_start_hexdump;
           stream_we = stream_we_hexdump;
           stream_addr = stream_addr_hexdump;
           stream_data = stream_data_hexdump;
           stream_clr = stream_clr_hexdump;

           if (hexdump_done)
             next_state = BROWSER;
           else
             next_state = HEXDUMP;
        end // case: HEXDUMP
        BROWSER: begin
           RAM_addr = RAM_addr_browser;
           RAM_data = RAM_data_browser;
           RAM_we = RAM_we_browser;
           draw_start = draw_start_browser;
           stream_we = stream_we_browser;
           stream_addr = stream_addr_browser;
           stream_data = stream_data_browser;
           stream_clr = stream_clr_browser;

           if (browser_done)
             next_state = IDLE;
           else if (want_hexdump)
             next_state = HEXDUMP;
           else if (want_fileview)
             next_state = FILEVIEW;
           else if (want_fileedit)
             next_state = FILEEDIT;
           else
             next_state = BROWSER;
        end // case: BROWSER
        FILEVIEW: begin
           RAM_addr = RAM_addr_fileview;
           RAM_data = 8'bx;
           RAM_we = 1'b0;
           draw_start = draw_start_fileview;
           stream_we = stream_we_fileview;
           stream_addr = stream_addr_fileview;
           stream_data = stream_data_fileview;
           stream_clr = stream_clr_fileview;

           if (fileview_done)
             next_state = BROWSER;
           else
             next_state = FILEVIEW;
        end // case: FILEVIEW
        FILEEDIT: begin
           RAM_addr = RAM_addr_fileedit;
           RAM_data = RAM_data_fileedit;
           RAM_we = RAM_we_fileedit;
           draw_start = draw_start_fileedit;
           stream_we = stream_we_fileedit;
           stream_addr = stream_addr_fileedit;
           stream_data = stream_data_fileedit;
           stream_clr = stream_clr_fileedit;

           if (fileedit_done)
             next_state = BROWSER;
           else
             next_state = FILEEDIT;
        end // case: FILEEDIT
        default: next_state = IDLE;
      endcase
   end

   always@(posedge clock) begin
      state <= next_state;
   end
endmodule

// // Encodes a character code
// module char_to_pixels
//   (
//    input [7:0]   code,
//    output [0:47] pixels
//    );
//    always@* begin
//       case (code)
//         8'h0:     pixels = 48'b011100100010100110101010110010100010011100000000;
//         8'h1:     pixels = 48'b001000011000101000001000001000001000111110000000;
//         8'h2:     pixels = 48'b011100100010000010000100001000010000111110000000;
//         8'h3:     pixels = 48'b011100100010000010001100000010100010011100000000;
//         8'h4:     pixels = 48'b001100010100100100100100111110000100000100000000;
//         8'h5:     pixels = 48'b111110100000100000111100000010000010111100000000;
//         8'h6:     pixels = 48'b011100100010100000111100100010100010011100000000;
//         8'h7:     pixels = 48'b111110000010000010000100000100001000001000000000;
//         8'h8:     pixels = 48'b011100100010100010011100100010100010011100000000;
//         8'h9:     pixels = 48'b011100100010100010011110000010100010011100000000;
//         8'hA:     pixels = 48'b011100100010100010111110100010100010100010000000;
//         8'hB:     pixels = 48'b111100100010100010111100100010100010111100000000;
//         8'hC:     pixels = 48'b011110100000100000100000100000100000011110000000;
//         8'hD:     pixels = 48'b111100100010100010100010100010100010111100000000;
//         8'hE:     pixels = 48'b111110100000100000111110100000100000111110000000;
//         8'hF:     pixels = 48'b111110100000100000111110100000100000100000000000;
//         8'd16:    pixels = 48'b011100100010100000100000100110100010011100000000;
//         8'd17:    pixels = 48'b100010100010100010111110100010100010100010000000;
//         8'd18:    pixels = 48'b111110001000001000001000001000001000111110000000;
//         8'd19:    pixels = 48'b111110000100000100000100000100100100011000000000;
//         8'd20:    pixels = 48'b100010100100101000110000101000100100100010000000;
//         8'd21:    pixels = 48'b100000100000100000100000100000100000111110000000;
//         8'd22:    pixels = 48'b100010110110101010101010100010100010100010000000;
//         8'd23:    pixels = 48'b110010110010101010101010101010100110100110000000;
//         8'd24:    pixels = 48'b011100100010100010100010100010100010011100000000;
//         8'd25:    pixels = 48'b111100100010100010111100100000100000100000000000;
//         8'd26:    pixels = 48'b011100100010100010100010101010100100011010000000;
//         8'd27:    pixels = 48'b111100100010100010111100101000100100100010000000;
//         8'd28:    pixels = 48'b011110100000100000011100000010000010111100000000;
//         8'd29:    pixels = 48'b111110001000001000001000001000001000001000000000;
//         8'd30:    pixels = 48'b100010100010100010100010100010100010011100000000;
//         8'd31:    pixels = 48'b100010100010100010100010010100010100001000000000;
//         8'd32:    pixels = 48'b100010100010100010101010101010110110100010000000;
//         8'd33:    pixels = 48'b100010100010010100001000010100100010100010000000;
//         8'd34:    pixels = 48'b100010100010100010010100001000001000001000000000;
//         8'd35:    pixels = 48'b111110000010000100001000010000100000111110000000;
//         8'd36:    pixels = 48'b000000000000000000000000000000000000000000000000;
//         8'd37:    pixels = 48'b000000001000011100111110011100001000000000000000; // big dot
//         8'd38:    pixels = 48'b000000000000000000000000000000011000011000000000; // little dot
//         8'd39:    pixels = 48'b000000000000001000000000001000000000000000000000; // colon
//         // default:  pixels = 48'b000000000000000000000000000000000000000000000000;
//         default: pixels = code;
//       endcase // case (code)
//    end
// endmodule // char_to_pixels

module draw_one_character
  (
   input             clock,
   output reg [11:0] ROM_addr,
   input             ROM_q,
   input             start,
   output reg        done,
   input [5:0]       X,
   input [4:0]       Y,
   input [7:0]       code,
   output reg [8:0]  x,
   output reg [7:0]  y,
   output reg        colour, plot
   );

   reg [5:0]         counter;
   reg [2:0]         Xcount;
   reg [2:0]         Ycount;

   wire [11:0]       ROM_offset = code < 6'd40 ? code * 12'd48 : 12'd1728; // space
   // wire [11:0]   ROM_offset = code * 12'd48;
   
   parameter LOADFIRST = 1'b0, LOADREST = 1'b1;
   reg               state = LOADFIRST;
   reg               next_state;

   always@* begin
      case (state)
        LOADFIRST: begin
           plot = 1'b0;
           x = 1'b0;
           y = 1'b0;
           colour = 1'b0;
           
           ROM_addr = ROM_offset;
           next_state = LOADREST;
        end
        LOADREST: begin
           plot = 1'b1;
           x = X * 9'd6 + Xcount;
           y = Y * 8'd8 + Ycount;
           colour = ROM_q;
           
           ROM_addr = ROM_offset + counter + 11'd1;
           
           next_state = LOADREST;
        end
      endcase // case (state)
   end
   
   always@(posedge clock) begin
      if (start && !done) begin
         if (counter == 6'd47) begin
            state <= LOADFIRST;
            done <= 1'b1;
         end
         else begin
            state <= next_state;

            if (state == LOADREST) begin
               counter <= counter + 1'd1;

               if (Xcount == 3'd5) begin
                  Xcount <= 3'd0;
                  Ycount <= Ycount + 3'd1;
               end else begin
                  Xcount <= Xcount + 3'd1;
               end
            end
         end
      end else begin
         counter <= 6'd0;
         Xcount <= 3'd0;
         Ycount <= 3'd0;
         done <= 1'b0;
      end // else: !if(start && !done)
   end
endmodule // draw_one_character

// Draws a region of the screen
module draw
  (
   input             clock,
   output reg [11:0] ROM_addr,
   input             ROM_q,
   input             start,
   output reg        done,
   input [7:0]       char_stream [0:1589],
   output reg [8:0]  x,
   output reg [7:0]  y,
   output reg        colour, plot
   );

   parameter WAIT_ONE = 1'b0, INC = 1'b1;
   reg               state = WAIT_ONE;
   reg               next_state;

   reg [10:0]        counter;
   reg [5:0]         X;
   reg [4:0]         Y;

   wire              draw_one_start = (start && !done && state == WAIT_ONE);
   wire              draw_one_done;

   draw_one_character u0
     (
      clock,
      ROM_addr,
      ROM_q,
      draw_one_start,
      draw_one_done,
      X,
      Y,
      char_stream[counter],
      x,
      y,
      colour,
      plot
      );

   always@* begin
      case (state)
        WAIT_ONE: begin
           if (draw_one_done)
             next_state = INC;
           else
             next_state = WAIT_ONE;
        end
        INC: begin
           next_state = WAIT_ONE;
        end
      endcase
   end // always@ *
   
   always@(posedge clock) begin
      if (start && !done) begin
         if (counter == 11'd1590) begin // 53*30
            done <= 1'b1;
         end
         else begin
            if (state == INC) begin
               counter <= counter + 1'd1;

               if (X == 6'd52) begin
                  X <= 6'd0;
                  Y <= Y + 5'd1;
               end else begin
                  X <= X + 6'd1;
               end
            end

            state <= next_state;
         end
      end else begin
         counter <= 1'd0;
         X <= 6'd0;
         Y <= 5'd0;
         done <= 1'b0;
      end
   end

endmodule // draw

// 0     6                        31      39
// AAAA  DD DD DD DD DD DD DD DD  dddddddd
module hexdump
  (
   // input [17:0]      SW,
   input             clock,
                     start,
   output reg        done,
   // RAM
   input [7:0]       RAM_q,
   output reg [15:0] RAM_addr,
   // Drawing
   input             draw_done,
   output reg        draw_start,
   // Char stream
   output reg [10:0] stream_addr,
   output reg [7:0]  stream_data,
   output reg        stream_clr,
   output reg        stream_we,
   // Keyboard
   input             key_pressed,
   input [7:0]       keycode
   );

   reg [7:0]         counter;
   reg [15:0]        start_address = 16'd0;

   // Which byte this is in one line
   wire [2:0]        which_byte = counter & 8'b111; // AKA mod 8

   assign RAM_addr = start_address + counter;
   wire [15:0]       display_RAM_addr = start_address + 16'd8 * counter;

   // Address digits
   wire [3:0]        addr_3, addr_2, addr_1, addr_0;
   assign {addr_3, addr_2, addr_1, addr_0} = display_RAM_addr;

   parameter DRAW_CLR = 4'd0, ADDRS_A = 4'd1, ADDRS_B = 4'd2, ADDRS_C = 4'd3, ADDRS_D = 4'd4,
     DATA_A = 4'd5, DATA_B = 4'd6, DATA_C = 4'd7, DATA_D = 4'd8, WAIT_VGA = 4'd9,
     KEYS = 4'd10, INC = 4'd11, DEC = 4'd12, DONE = 4'd13;
   reg [3:0]         state = DRAW_CLR;
   reg [3:0]         next_state;
   
   reg               inc_counter, rst_counter;

   always@* begin
      stream_clr = 1'b0;
      stream_we = 1'b0;
      stream_data = 8'b0;
      stream_addr = 11'b0;
      draw_start = 1'b0;
      inc_counter = 1'b0;
      rst_counter = 1'b0;
      case (state)
        DRAW_CLR: begin
           stream_clr = 1'b1;
           rst_counter = 1'b1;
           next_state = ADDRS_A;
        end
        ADDRS_A: begin
           stream_we = 1'b1;
           stream_addr = 11'd53 * counter + 11'd0;
           stream_data = addr_3;
           next_state = ADDRS_B;
        end
        ADDRS_B: begin
           stream_we = 1'b1;
           stream_addr = 11'd53 * counter + 11'd1;
           stream_data = addr_2;
           next_state = ADDRS_C;
        end
        ADDRS_C: begin
           stream_we = 1'b1;
           stream_addr = 11'd53 * counter + 11'd2;
           stream_data = addr_1;
           next_state = ADDRS_D;
        end
        ADDRS_D: begin
           stream_we = 1'b1;
           stream_addr = 11'd53 * counter + 11'd3;
           stream_data = addr_0;
           if (counter == 8'd30) begin
              next_state = DATA_A;
              rst_counter = 1'b1;
           end else begin
              next_state = ADDRS_A;
              inc_counter = 1'b1;
           end
        end // case: ADDRS_D
        DATA_A: begin
           next_state = DATA_B;
        end
        DATA_B: begin
           stream_we = 1'b1;
           stream_addr = 11'd53 * (counter >> 8'd3) + 11'd6 + 11'd3 * which_byte + 11'd0;
           stream_data = RAM_q[7:4];
           next_state = DATA_C;
        end
        DATA_C: begin
           stream_we = 1'b1;
           stream_addr = 11'd53 * (counter >> 8'd3) + 11'd6 + 11'd3 * which_byte + 11'd1;
           stream_data = RAM_q[3:0];
           next_state = DATA_D;
        end
        DATA_D: begin // full letter display on right
           stream_we = 1'b1;
           stream_addr = 11'd53 * (counter >> 8'd3) + 11'd31 + which_byte;
           stream_data = RAM_q;
           if (counter == 8'd240) // 8 * 30 (number of bytes to display in a page)
             next_state = WAIT_VGA;
           else begin
              inc_counter = 1'b1;
              next_state = DATA_A;
           end
        end // case: DATA_D
        WAIT_VGA: begin
           draw_start = 1'b1;
           if (draw_done) // draw_start will be set to low on next clock (default)
             next_state = KEYS;
           else
             next_state = WAIT_VGA;
        end
        KEYS: begin
           if (key_pressed) begin
              if (keycode == 8'd100 && start_address != 16'd0)
                next_state = DEC;
              else if (keycode == 8'd99)
                next_state = INC;
              else if (keycode == 8'd11)
                next_state = DONE;
              else
                next_state = KEYS;
           end else
             next_state = KEYS;
        end
        INC: next_state = DRAW_CLR;
        DEC: next_state = DRAW_CLR;
        DONE: next_state = DRAW_CLR;
      endcase // case (state)
   end // always@ *

   always@(posedge clock) begin
      if (start && !done) begin
         state <= next_state;
         if (inc_counter)
           counter <= counter + 8'b1;
         if (rst_counter)
           counter <= 8'b0;
         if (state == INC)
           start_address <= start_address + 16'd240;
         if (state == DEC)
           start_address <= start_address - 16'd240;
         if (state == DONE)
           done <= 1'b1;
      end else begin
         done <= 0;
      end
   end // always@ (posedge clock)
endmodule

module browser
  (
   // input [17:0]      SW,
   // output [17:0]     LEDR,
   input             clock,
   input             start,
   output reg        done,
   output reg        want_hexdump,
   output reg        want_fileview,
   output reg        want_fileedit,
   output reg [6:0]  file_block_id,
   // RAM
   input [7:0]       RAM_q,
   output reg [15:0] RAM_addr,
   output reg        RAM_we,
   output reg [7:0]  RAM_data,
   // Drawing
   input             draw_done,
   output reg        draw_start,
   // Char stream
   output reg [10:0] stream_addr,
   output reg [7:0]  stream_data,
   output reg        stream_clr,
   output reg        stream_we,
   // Keyboard
   input             key_pressed,
   input [7:0]       keycode
   );
   
   parameter DRAW_CLR = 6'd0, TITLE = 6'd1, WAIT_VGA = 6'd2, KEYS = 6'd3, COLON = 6'd4,
     BULLET = 6'd5, GET_LIST_NODEID = 6'd6, CHECK_DONE = 6'd7, NAME = 6'd8, FD = 6'd9,
     INC = 6'd10, DEC = 6'd11, CHECK_IF_DIRECTORY1 = 6'd13,
     CHECK_IF_DIRECTORY2 = 6'd14, WAIT_HEXDUMP = 6'd15, DEL1 = 6'd12, DEL2 = 6'd16,
     DEL3 = 6'd17, DEL4 = 6'd18, DEL5 = 6'd19, DEL6 = 6'd20, FIND_EMPTY_NODE = 6'd21,
     WRITE_BLOCK_EOF = 6'd22, FIND_EMPTY_BLOCK_PRE = 6'd23, FIND_EMPTY_BLOCK = 6'd24,
     SET_LAST_NODE_BYTE = 6'd25, WRITE_NEW_BLOCK_EOF = 6'd26, PROMPT = 6'd27,
     WAIT_VGA_NEW = 6'd28, KEYS_NEW = 6'd29, WRITE_NEW_BLOCK_PARENT = 6'd30,
     WAIT_FILEVIEW = 6'd31, WAIT_FILEVIEW_PRE = 6'd32, WAIT_FILEVIEW2 = 6'd33,
     WAIT_FILEEDIT = 6'd34, WAIT_FILEEDIT_PRE = 6'd35, WAIT_FILEEDIT2 = 6'd36,
     DEL7 = 6'd37, DEL8 = 6'd38, DEL55 = 6'd39;
   reg [5:0]         state = DRAW_CLR;
   reg [5:0]         next_state;
   
   reg [4:0]         list_counter;
   reg [6:0]         counter;
   reg               inc_counter, rst_counter, inc_list_counter, rst_list_counter,
                     set_nodeid_of_item, set_nodeid, rst_curr, set_f, set_d,
                     set_nodeid_save, set_block_id_save;
   reg [4:0]         current_item = 5'd0;

   reg [5:0]         nodeid = 6'd0;
   reg [5:0]         nodeid_of_item;
   reg [6:0]         block_id;
   reg [5:0]         nodeid_save, nodeid_save_d;
   reg [6:0]         block_id_save, block_id_save_d;

   wire [15:0]       node_addr = nodeid * 16'd16;
   wire [15:0]       node_of_item_addr = nodeid_of_item * 16'd16;
   wire [15:0]       block_addr = 16'd1024 + 16'd512 * block_id;

   reg               f_or_d;
   
   reg [6:0]         curr_block_id;
   reg [6:0]         curr_block_id_d;
   reg               set_curr_block_id;

   //assign LEDR[0] = f_or_d;
   always@* begin
      want_hexdump = 1'b0;
      want_fileview = 1'b0;
      want_fileedit = 1'b0;
      
      RAM_we = 1'b0;
      RAM_addr = 16'b0;
      RAM_data = 8'bx;
      
      stream_clr = 1'b0;
      stream_we = 1'b0;
      stream_data = 8'b0;
      stream_addr = 11'b0;
      
      draw_start = 1'b0;
      
      inc_counter = 1'b0;
      rst_counter = 1'b0;
      inc_list_counter = 1'b0;
      rst_list_counter = 1'b0;
      set_nodeid_of_item = 1'b0;
      set_nodeid = 1'b0;
      rst_curr = 1'b0;
      set_nodeid_save = 1'b0;
      nodeid_save_d = 6'b0;
      set_block_id_save = 1'b0;
      block_id_save_d = 7'b0;

      set_f = 1'b0;
      set_d = 1'b0;

      set_curr_block_id = 1'b0;
      curr_block_id_d = 7'd0;
      case (state)
        DRAW_CLR: begin
           RAM_addr = node_addr;
           
           stream_clr = 1'b1;
           rst_counter = 1'b1;
           rst_list_counter = 1'b1;
           next_state = TITLE;
        end
        TITLE: begin
           if (counter == 4'd15 || RAM_q == 8'd255) begin
              // Get block ID
              RAM_addr = node_addr + 16'd15;
              
              next_state = COLON;
           end else begin
              RAM_addr = node_addr + counter + 16'd1;
              
              stream_we = 1'b1;
              stream_addr = counter;
              stream_data = RAM_q;
              inc_counter = 1'b1;

              next_state = TITLE;
           end
        end // case: TITLE
        COLON: begin
           stream_we = 1'b1;
           stream_addr = counter;
           stream_data = 8'd39;

           next_state = BULLET;
           // next_state = WAIT_VGA;
        end 
        BULLET: begin
           stream_we = 1'b1;
           stream_addr = (current_item + 11'd1) * 11'd53;
           stream_data = 8'd37;

           next_state = GET_LIST_NODEID;
        end
        GET_LIST_NODEID: begin
           RAM_addr = block_addr + list_counter;

           rst_counter = 1'b1;
           next_state = CHECK_DONE;
        end
        CHECK_DONE: begin
           if (RAM_q == 8'd255) begin // end of directories
              next_state = WAIT_VGA;
           end else begin
              set_nodeid_of_item = 1'b1;
              RAM_addr = RAM_q * 16'd16; // node address, and first letter of name
              // if first dir, 
              next_state = NAME;
           end
        end
        NAME: begin
           if (list_counter == 5'd0) begin // ..
              if (counter == 4'd2) begin
                 RAM_addr = node_of_item_addr + 16'd15;
                 
                 next_state = FD;
                 rst_counter = 1'b1;
              end else begin
                 stream_we = 1'b1;
                 stream_addr = 11'd53 * (list_counter + 11'd1) + 11'd4 + counter;
                 stream_data = 8'd38; // .
                 inc_counter = 1'b1;

                 next_state = NAME;
              end
           end else begin
              if (counter == 4'd15 || RAM_q == 8'd255) begin
                 RAM_addr = node_of_item_addr + 16'd15;
                 
                 next_state = FD;
                 rst_counter = 1'b1;
              end else begin
                 RAM_addr = node_of_item_addr + counter + 16'd1;

                 stream_we = 1'b1;
                 stream_addr = 11'd53 * (list_counter + 11'd1) + 11'd4 + counter;
                 stream_data = RAM_q;
                 inc_counter = 1'b1;

                 next_state = NAME;
              end // else: !if(counter == 4'd15 || RAM_q == 8'd255)
           end
        end // case: NAME
        FD: begin
           stream_we = 1'b1;
           stream_addr = 11'd53 * (list_counter + 11'd1) + 11'd2;
           if (RAM_q[7] == 1'b0) // file
             stream_data = 8'd15; // F
           else
             stream_data = 8'd13; // D

           inc_list_counter = 1'b1;
           next_state = GET_LIST_NODEID;
        end
        WAIT_VGA: begin
           draw_start = 1'b1;
           if (draw_done) // draw_start will be set to low on next clock (default)
             next_state = KEYS;
           else
             next_state = WAIT_VGA;
        end
        KEYS: begin
           if (key_pressed) begin
              if (keycode == 8'd100 && current_item != 6'd0)
                next_state = DEC;
              else if (keycode == 8'd99 && current_item != (list_counter - 5'd1))
                next_state = INC;
              else if (keycode == 8'd98) begin
                 RAM_addr = block_addr + current_item;
                 next_state = CHECK_IF_DIRECTORY1;
              end else if (keycode == 8'd17)
                next_state = WAIT_HEXDUMP;
              else if (keycode == 8'd27 && current_item != 6'd0) begin
                 RAM_addr = block_addr + current_item;
                 set_d = 1'b1;
                 next_state = DEL1;
              end else if (keycode == 8'd13) begin
                 set_d = 1'b1;
                 RAM_addr = 16'd16;

                 inc_counter = 1'b1;
                 next_state = FIND_EMPTY_NODE;
              end else if (keycode == 8'd15) begin
                 set_f = 1'b1;
                 RAM_addr = 16'd16;

                 inc_counter = 1'b1;
                 next_state = FIND_EMPTY_NODE;
              end else if (keycode == 8'd14) begin // e for edit
                 set_f = 1'b1;
                 RAM_addr = block_addr + current_item;
                 next_state = DEL55; // delete file contents
              end else
                next_state = KEYS;
           end
           else
             next_state = KEYS;
        end // case: KEYS
        DEL55: begin
           set_nodeid_save = 1'b1;
           nodeid_save_d = RAM_q;

           next_state = DEL5;
        end
        INC: next_state = DRAW_CLR;
        DEC: next_state = DRAW_CLR;
        CHECK_IF_DIRECTORY1: begin
           RAM_addr = RAM_q * 16'd16 + 16'd15;
           set_nodeid_save = 1'b1;
           nodeid_save_d = RAM_q[5:0];
           
           next_state = CHECK_IF_DIRECTORY2;
        end
        CHECK_IF_DIRECTORY2: begin
           if (RAM_q[7] == 1'b1) begin // folder
              set_nodeid = 1'b1;
              rst_curr = 1'b1;
              next_state = DRAW_CLR;
           end else begin
              RAM_addr = block_addr + current_item;
              next_state = WAIT_FILEVIEW_PRE;
           end
        end
        DEL1: begin
           set_nodeid_save = 1'b1;
           nodeid_save_d = RAM_q[5:0];
           
           // get last nodeid
           RAM_addr = block_addr + list_counter - 16'd1;
           
           next_state = DEL2;
        end
        DEL2: begin
           // set deleted node to the last
           RAM_we = 1'b1;
           RAM_addr = block_addr + current_item;
           RAM_data = RAM_q;

           next_state = DEL3;
        end
        DEL3: begin
           // set the last to be EOF
           RAM_we = 1'b1;
           RAM_addr = block_addr + list_counter - 16'd1;
           RAM_data = 8'd255;
           
           next_state = DEL4;
        end
        DEL4: begin
           // delete node
           RAM_we = 1'b1;
           RAM_addr = nodeid_save * 16'd16;
           RAM_data = 8'b0; // zero first char = delete
           
           next_state = DEL5;
        end // case: DEL4
        DEL5: begin
           // get block address
           RAM_addr = nodeid_save * 16'd16 + 16'd15;

           next_state = DEL6;
        end
        DEL6: begin
           set_curr_block_id = 1'b1;
           curr_block_id_d = RAM_q[6:0];
           
           next_state = DEL7;
        end
        DEL7: begin
           if (curr_block_id == 7'b1111111) begin
              if (f_or_d) begin // 1 for R, 0 for E
                 rst_curr = 1'b1;
                 next_state = DRAW_CLR;
              end else begin
                 RAM_addr = block_addr + current_item;
                 next_state = WAIT_FILEEDIT_PRE;
              end
           end else begin
              // get next block address
              RAM_addr = 16'd1024 + 16'd512 * curr_block_id + 16'd511;
              
              next_state = DEL8;
           end
        end
        DEL8: begin
           // zero "is-a-thing" bit on block
           RAM_we = 1'b1;
           RAM_addr = 16'd1024 + 16'd512 * curr_block_id + 16'd511;
           RAM_data = 8'b0;

           set_curr_block_id = 1'b1;
           curr_block_id_d = RAM_q[6:0];
           
           next_state = DEL7;
        end
        FIND_EMPTY_NODE: begin
           if (RAM_q == 8'b0) begin
              set_nodeid_save = 1'b1;
              nodeid_save_d = counter;

              // write nodeid to current directory block's node list
              RAM_we = 1'b1;
              RAM_addr = block_addr + list_counter;
              RAM_data = counter;

              rst_counter = 1'b1;
              next_state = WRITE_BLOCK_EOF;
           end else begin
              inc_counter = 1'b1;
              RAM_addr = 16'd16 * (counter + 16'd1);

              next_state = FIND_EMPTY_NODE;
           end
        end // case: FIND_EMPTY_NODE
        WRITE_BLOCK_EOF: begin
           RAM_we = 1'b1;
           RAM_addr = block_addr + list_counter + 16'd1;
           RAM_data = 8'd255;

           next_state = FIND_EMPTY_BLOCK_PRE;
        end
        FIND_EMPTY_BLOCK_PRE: begin // needed to set inital RAM read
           RAM_addr = 16'd1024 + 16'd512 + 16'd511;
           inc_counter = 1'b1;
           next_state = FIND_EMPTY_BLOCK;
        end
        FIND_EMPTY_BLOCK: begin
           if (RAM_q[7] == 8'b0) begin
              set_block_id_save = 1'b1;
              block_id_save_d = counter;

              // set "is-a-thing" and EOF for empty block
              RAM_we = 1'b1;
              RAM_addr = 16'd1024 + 16'd512 * counter + 16'd511;
              RAM_data = 8'b11111111;

              rst_counter = 1'b1;
              next_state = SET_LAST_NODE_BYTE;
           end else begin
              inc_counter = 1'b1;
              RAM_addr = 16'd1024 + 16'd512 * (counter + 16'd1) + 16'd511;

              next_state = FIND_EMPTY_BLOCK;
           end
        end // case: FIND_EMPTY_BLOCK
        SET_LAST_NODE_BYTE: begin
           RAM_we = 1'b1;
           RAM_addr = 16'd16 * nodeid_save + 16'd15;
           RAM_data = {f_or_d, block_id_save};

           if (f_or_d == 1'b0) // file
             next_state = PROMPT;
           else // setup directory block
             next_state = WRITE_NEW_BLOCK_PARENT;
        end // case: SET_LAST_NODE_BYTE
        WRITE_NEW_BLOCK_PARENT: begin
           RAM_we = 1'b1;
           RAM_addr = 16'd1024 + 16'd512 * block_id_save;
           RAM_data = nodeid;

           next_state = WRITE_NEW_BLOCK_EOF;
        end           
        WRITE_NEW_BLOCK_EOF: begin
           RAM_we = 1'b1;
           RAM_addr = 16'd1024 + 16'd512 * block_id_save + 16'd1;
           RAM_data = 8'd255;

           next_state = PROMPT;
        end
        PROMPT: begin
           stream_we = 1'b1;
           stream_addr = 11'd762 + counter;
           case (counter)
             4'd0: stream_data = 8'd14; // E
             4'd1: stream_data = 8'd23; // N
             4'd2: stream_data = 8'd29; // T
             4'd3: stream_data = 8'd14; // E
             4'd4: stream_data = 8'd27; // R
             4'd5: stream_data = 8'd36; // 
             4'd6: stream_data = 8'd23; // N
             4'd7: stream_data = 8'd10; // A
             4'd8: stream_data = 8'd22; // M
             4'd9: stream_data = 8'd14; // E
             4'd10: stream_data = 8'd39;// :
             default: stream_data = 8'd0;
           endcase // case (counter)

           if (counter == 4'd10) begin
              rst_counter = 1'b1;
              next_state = WAIT_VGA_NEW;
           end else begin
              inc_counter = 1'b1;
              next_state = PROMPT;
           end
        end // case: PROMPT
        WAIT_VGA_NEW: begin
           draw_start = 1'b1;
           if (draw_done) // draw_start will be set to low on next clock (default)
             next_state = KEYS_NEW;
           else
             next_state = WAIT_VGA_NEW;
        end
        KEYS_NEW: begin
           if (key_pressed) begin
              if (keycode == 8'd98) begin // write the EOF to the node name
                 RAM_we = 1'b1;
                 RAM_addr = 16'd16 * nodeid_save + counter + (counter == 4'd13 ? 16'd1 : 16'd0);
                 RAM_data = 8'd255;

                 next_state = DRAW_CLR;
              end else begin // actually write the change to memory, easiest
                 RAM_we = 1'b1;
                 RAM_addr = 16'd16 * nodeid_save + counter;
                 RAM_data = keycode;

                 stream_we = 1'b1;
                 stream_addr = 11'd815 + counter;
                 stream_data = keycode;

                 // only increment if counter <, to prevent overflow 
                 if (counter != 4'd13)
                   inc_counter = 1'b1;
                 
                 next_state = WAIT_VGA_NEW;
              end
           end
           else
             next_state = KEYS_NEW;
        end
        WAIT_HEXDUMP: begin
           want_hexdump = 1'b1;
           next_state = DRAW_CLR;
        end
        WAIT_FILEVIEW_PRE: begin
           RAM_addr = 16'd16 * RAM_q + 16'd15;
           next_state = WAIT_FILEVIEW;
        end
        WAIT_FILEVIEW: next_state = WAIT_FILEVIEW2;
        WAIT_FILEVIEW2: begin
           want_fileview = 1'b1;
           next_state = DRAW_CLR;
        end
        WAIT_FILEEDIT_PRE: begin
           RAM_addr = 16'd16 * RAM_q + 16'd15;
           next_state = WAIT_FILEEDIT;
        end
        WAIT_FILEEDIT: next_state = WAIT_FILEEDIT2;
        WAIT_FILEEDIT2: begin
           want_fileedit = 1'b1;
           next_state = DRAW_CLR;
        end
      endcase // case (state)
   end // always@ *

   always@(posedge clock) begin
      if (start && !done) begin
         state <= next_state;
         if (inc_counter)
           counter <= counter + 4'd1;
         if (rst_counter)
           counter <= 4'b0;
         if (inc_list_counter)
           list_counter <= list_counter + 5'd1;
         if (rst_list_counter)
           list_counter <= 5'b0;
         if (state == COLON)
           block_id <= RAM_q[6:0];
         if (set_nodeid_of_item)
           nodeid_of_item <= RAM_q[5:0];
         if (state == INC)
           current_item <= current_item + 5'd1;
         if (state == DEC)
           current_item <= current_item - 5'd1;
         if (rst_curr)
           current_item <= 5'd0;
         if (set_nodeid_save)
           nodeid_save <= nodeid_save_d;
         if (set_block_id_save)
           block_id_save <= block_id_save_d;
         if (set_nodeid)
           nodeid <= nodeid_save;
         if (set_f)
           f_or_d <= 1'b0;
         if (set_d)
           f_or_d <= 1'b1;
         if (state == WAIT_FILEVIEW || state == WAIT_FILEEDIT)
           file_block_id <= RAM_q[6:0];
         if (set_curr_block_id)
           curr_block_id <= curr_block_id_d;
      end else begin
         done <= 0;
      end
   end
endmodule

module fileview
  (
   input             clock,
   input             start,
   output reg        done,
   input [6:0]       file_block_id,
   // RAM
   input [7:0]       RAM_q,
   output reg [15:0] RAM_addr,
   // Drawing
   input             draw_done,
   output reg        draw_start,
   // Char stream
   output reg [10:0] stream_addr,
   output reg [7:0]  stream_data,
   output reg        stream_clr,
   output reg        stream_we,
   // Keyboard
   input             key_pressed,
   input [7:0]       keycode
   );

   reg               set_block_id;
   
   reg [6:0]         block_id;
   reg [6:0]         block_id_d;

   wire [15:0]       block_addr = 16'd1024 + 16'd512 * block_id;

   reg               inc_stream_counter, rst_stream_counter, inc_RAM_counter,
                     rst_RAM_counter;

   reg               set_end_reached, end_reached_d, end_reached;
   
   reg [10:0]        stream_counter;
   reg [8:0]         RAM_counter;
   
   parameter START = 4'd0, DRAW_CLR = 4'd1, PUT = 4'd2, FOLLOW_NEXT_BLOCK = 4'd3,
     WAIT_VGA = 4'd4, KEYS = 4'd5, DONE = 4'd6, FOLLOW2 = 4'd7;
   reg [3:0]         state = START;
   reg [3:0]         next_state;

   always@* begin
      set_block_id = 1'b0;
      block_id_d = 7'b0;

      RAM_addr = 16'd0;

      set_end_reached = 1'b0;
      end_reached_d = 1'b0;
      
      stream_clr = 1'b0;
      stream_we = 1'b0;
      stream_data = 8'b0;
      stream_addr = 11'b0;
      draw_start = 1'b0;

      inc_stream_counter = 1'b0;
      rst_stream_counter = 1'b0;
      inc_RAM_counter = 1'b0;
      rst_RAM_counter = 1'b0;

      case (state)
        START: begin
           set_block_id = 1'b1;
           block_id_d = file_block_id;
           rst_RAM_counter = 1'b1;
           set_end_reached = 1'b1;
           end_reached_d = 1'b0;

           next_state = DRAW_CLR;
        end
        DRAW_CLR: begin
           stream_clr = 1'b1;
           rst_stream_counter = 1'b1;

           RAM_addr = block_addr + RAM_counter;
           inc_RAM_counter = 1'b1;
           
           next_state = PUT;
        end
        PUT: begin // do stuff
           if (RAM_q == 8'd255) begin
              set_end_reached = 1'b1;
              end_reached_d = 1'b1;
              
              next_state = WAIT_VGA;
           end else begin
              stream_we = 1'b1;
              stream_addr = stream_counter;
              stream_data = RAM_q;
              inc_stream_counter = 1'b1;
              
              if (stream_counter == 11'd1589) begin
                 next_state = WAIT_VGA;
              end else if (RAM_counter == 9'd511) begin
                 RAM_addr = block_addr + RAM_counter;

                 next_state = FOLLOW_NEXT_BLOCK;
              end else begin
                 RAM_addr = block_addr + RAM_counter;
                 inc_RAM_counter = 1'b1;

                 next_state = PUT;
              end
           end
        end // case: PUT
        FOLLOW_NEXT_BLOCK: begin
           if (RAM_q[6:0] == 7'b1111111) begin
              set_end_reached = 1'b1;
              end_reached_d = 1'b1;

              next_state = WAIT_VGA;
           end else begin 
              rst_RAM_counter = 1'b1;
              set_block_id = 1'b1;
              block_id_d = RAM_q[6:0];

              next_state = FOLLOW2;
           end
        end // case: FOLLOW_NEXT_BLOCK
        FOLLOW2: begin
           RAM_addr = block_addr + RAM_counter;
           inc_RAM_counter = 1'b1;

           next_state = PUT;
        end
        WAIT_VGA: begin
           draw_start = 1'b1;
           if (draw_done)
             next_state = KEYS;
           else
             next_state = WAIT_VGA;
        end
        KEYS: begin
           if (key_pressed) begin
              if (end_reached)
                next_state = DONE;
              else
                next_state = DRAW_CLR;
           end else
             next_state = KEYS;
        end
        DONE: next_state = START;
      endcase // case (state)
   end // always@ *

   always@(posedge clock) begin
      if (start && !done) begin
         state <= next_state;

         if (set_block_id)
           block_id <= block_id_d;
         if (inc_stream_counter)
           stream_counter <= stream_counter + 11'd1;
         if (rst_stream_counter)
           stream_counter <= 11'd0;
         if (inc_RAM_counter)
           RAM_counter <= RAM_counter + 9'd1;
         if (rst_RAM_counter)
           RAM_counter <= 9'd0;
         if (set_end_reached)
           end_reached <= end_reached_d;
         if (state == DONE)
           done <= 1'b1;
         
      end else begin
         done <= 0;
      end
   end // always@ (posedge clock)
endmodule

module fileedit
  (
   input             clock,
   input             start,
   output reg        done,
   input [6:0]       file_block_id,
   // RAM
   input [7:0]       RAM_q,
   output reg [15:0] RAM_addr,
   output reg        RAM_we,
   output reg [7:0]  RAM_data,
   // Drawing
   input             draw_done,
   output reg        draw_start,
   // Char stream
   output reg [10:0] stream_addr,
   output reg [7:0]  stream_data,
   output reg        stream_clr,
   output reg        stream_we,
   // Keyboard
   input             key_pressed,
   input [7:0]       keycode
   );

   reg               set_block_id;
   reg [6:0]         block_id;
   reg [6:0]         block_id_d;
   wire [15:0]       block_addr = 16'd1024 + 16'd512 * block_id;

   reg               inc_stream_counter, rst_stream_counter, inc_RAM_counter,
                     rst_RAM_counter;
   reg [10:0]        stream_counter;
   reg [9:0]         RAM_counter;

   reg               inc_X_count, rst_X_count;
   reg [5:0]         X_count;

   reg               inc_alloc_counter, rst_alloc_counter;
   reg [6:0]         alloc_counter;

   reg               set_key;
   reg [7:0]         key, key_d;

   reg               set_entermode, entermode, entermode_d;
   
   parameter START = 4'd0, DRAW_CLR = 4'd1, GET = 4'd2, FIND_EMPTY_BLOCK_PRE = 4'd3,
     FIND_EMPTY_BLOCK = 4'd4, WAIT_VGA = 4'd5, KEYS = 4'd6, DONE = 4'd7;
   reg [3:0]         state = START;
   reg [3:0]         next_state;

   always@* begin
      set_block_id = 1'b0;
      block_id_d = 7'b0;

      RAM_we = 1'b0;
      RAM_addr = 16'd0;
      RAM_data = 8'd0;
      
      stream_clr = 1'b0;
      stream_we = 1'b0;
      stream_data = 8'b0;
      stream_addr = 11'b0;
      draw_start = 1'b0;

      inc_stream_counter = 1'b0;
      rst_stream_counter = 1'b0;
      inc_RAM_counter = 1'b0;
      rst_RAM_counter = 1'b0;
      inc_alloc_counter = 1'b0;
      rst_alloc_counter = 1'b0;
      inc_X_count = 1'b0;
      rst_X_count = 1'b0;

      set_key = 1'b0;
      key_d = 8'd0;

      set_entermode = 1'b0;
      entermode_d = 1'b0;

      case (state)
        START: begin
           set_block_id = 1'b1;
           block_id_d = file_block_id;
           rst_RAM_counter = 1'b1;
           set_entermode = 1'b1;
           entermode_d = 1'b0;

           next_state = DRAW_CLR;
        end
        DRAW_CLR: begin
           stream_clr = 1'b1;
           rst_stream_counter = 1'b1;
           rst_X_count = 1'b1;

           next_state = WAIT_VGA;
        end
        GET: begin
           if (X_count == 6'd52) begin
              rst_X_count = 1'b1;
              set_entermode = 1'b1;
              entermode_d = 1'b0;
           end
           
           if (RAM_counter == 9'd511) begin
              // set "is-a-thing" for current so when finding next it is skipped
              RAM_we = 1'b1;
              RAM_addr = block_addr + 16'd511;
              RAM_data = 8'b10000000;

              next_state = FIND_EMPTY_BLOCK_PRE;
           end else begin
              stream_we = 1'b1;
              stream_addr = stream_counter;
              stream_data = key;
              inc_stream_counter = 1'b1;
              inc_X_count = 1'b1;

              RAM_we = 1'b1;
              RAM_addr = block_addr + RAM_counter;
              RAM_data = key;
              inc_RAM_counter = 1'b1;
              
              if (stream_counter == 11'd1589)
                next_state = DRAW_CLR;
              else
                next_state = WAIT_VGA;
           end
        end
        FIND_EMPTY_BLOCK_PRE: begin
           RAM_addr = 16'd1024 + 16'd512 + 16'd511;
           inc_alloc_counter = 1'b1;
           next_state = FIND_EMPTY_BLOCK;
        end
        FIND_EMPTY_BLOCK: begin
           if (RAM_q[7] == 8'b0) begin
              set_block_id = 1'b1;
              block_id_d = alloc_counter;

              // set "is-a-thing" and next for current block
              RAM_we = 1'b1;
              RAM_addr = block_addr + 16'd511;
              RAM_data = {1'b1, alloc_counter};

              set_block_id = 1'b1;
              block_id_d = alloc_counter;

              rst_RAM_counter = 1'b1;
              rst_alloc_counter = 1'b1;

              next_state = GET;
           end else begin
              inc_alloc_counter = 1'b1;
              RAM_addr = 16'd1024 + 16'd512 * (alloc_counter + 16'd1) + 16'd511;

              next_state = FIND_EMPTY_BLOCK;
           end
        end // case: FIND_EMPTY_BLOCK
        WAIT_VGA: begin
           draw_start = 1'b1;
           if (draw_done)
             next_state = KEYS;
           else
             next_state = WAIT_VGA;
        end
        KEYS: begin
           if (entermode) begin
              next_state = GET;
           end
           else begin
              if (key_pressed) begin
                 if (keycode == 8'd101) begin
                    RAM_we = 1'b1;
                    RAM_addr = block_addr + RAM_counter;
                    RAM_data = 8'hff; // eof
                    
                    next_state = DONE;
                 end else if (keycode == 8'd98) begin // enter
                    set_entermode = 1'b1;
                    entermode_d = 1'b1;
                    set_key = 1'b1;
                    key_d = 8'd36; // space
                    
                    next_state = GET;
                 end else begin
                    set_key = 1'b1;
                    key_d = keycode;
                    next_state = GET;
                 end // else: !if(keycode == 8'd101)
              end else // if (key_pressed)
                next_state = KEYS;
           end
        end // case: KEYS
        DONE: begin
           RAM_we = 1'b1;
           RAM_addr = block_addr + 16'd511;
           RAM_data = 8'hff;

           next_state = START;
        end
      endcase // case (state)
   end // always@ *

   always@(posedge clock) begin
      if (start && !done) begin
         state <= next_state;

         if (set_block_id)
           block_id <= block_id_d;
         if (inc_stream_counter)
           stream_counter <= stream_counter + 11'd1;
         if (rst_stream_counter)
           stream_counter <= 11'd0;
         if (inc_RAM_counter)
           RAM_counter <= RAM_counter + 10'd1;
         if (rst_RAM_counter)
           RAM_counter <= 9'd0;
         if (inc_alloc_counter)
           alloc_counter <= alloc_counter + 7'd1;
         if (rst_alloc_counter)
           alloc_counter <= 7'd0;
         if (set_key)
           key <= key_d;
         if (set_entermode)
           entermode <= entermode_d;
         if (inc_X_count)
           X_count <= X_count + 6'd1;
         if (rst_X_count)
           X_count <= 6'd0;
         if (state == DONE)
           done <= 1'b1;

      end else begin
         done <= 0;
      end
   end // always@ (posedge clock)
endmodule
