//
// viking.v
// 
// Atari ST(E) Viking/SM194
// http://code.google.com/p/mist-board/
// 
// Copyright (c) 2013-2015 Till Harbaum <till@harbaum.org> 
// 
// This source file is free software: you can redistribute it and/or modify 
// it under the terms of the GNU General Public License as published 
// by the Free Software Foundation, either version 3 of the License, or 
// (at your option) any later version. 
// 
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>. 

// The viking card does not have its own CPU interface as it is not 
// configurable in any way. It just etches data from ram and displays
// it on screen.

module viking
(
	input             pclk,      // pixel clock

	// memory interface
	input             himem,     // use memory behind rom
	input             bus_sync,  // 2 MHz bus sync
	output reg [22:0] addr,      // video word address
	output reg        read,      // video read cycle
	input      [63:0] data,      // video data read

	// VGA output (multiplexed with sm124 output in top level)
	output reg        hs,
	output reg        vs,
	output reg        hblank,
	output reg        vblank,
	output reg        pix
);

localparam BASE    = 23'h600000;   // c00000
localparam BASE_HI = 23'h740000;   // e80000

// total width must be multiple of 64, so video runs synchronous
// to main bus

// Horizontal timing
// HBP  |                    H              | HFP | HS 
// -----|XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX|-----|____
// HBP  is used for prefetch

// 1280x
localparam [10:0] HBP  = 124;
localparam [10:0] H    = 1280;
localparam [10:0] HFP  = 44;
localparam [10:0] HS   = 88;
localparam [10:0] HLAST= HBP+H+HFP+HS-1'd1;

// Vertical timing
//                     V              | VFP | VS | VBP
// XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX|-----|____|-----

// x1024
localparam [10:0] V    = 1024;
localparam [10:0] VFP  = 9;
localparam [10:0] VS   = 4;
localparam [10:0] VBP  = 9;
localparam [10:0] VLAST= V+VFP+VS+VBP-1'd1;

reg [63:0] line[32];

always @(posedge pclk) begin
	reg [4:0] cnt;
	reg [2:0] sync;
	reg       bus_syncD;

	sync <= sync << 1;

	bus_syncD <= bus_sync;
	if (~bus_syncD & bus_sync) sync <= 1;

	if(sync[2]) begin
		if(read) begin
			line[cnt] <= { data[15:0], data[31:16], data[47:32], data[63:48] };
			cnt <= cnt + 1'd1;
			addr <= addr + 4'd4;
			if(cnt == 19) read <= 0;
		end
		else if(!cnt) read <= 1;
	end

	if(!h_cnt) begin
		cnt <= 0;
		if(vblank) addr <= himem ? BASE_HI : BASE;
	end
end


// --------------- horizontal timing -------------
reg[10:0] h_cnt;   // 0..2047
always@(posedge pclk) begin
	h_cnt <= h_cnt + 1'd1;
	if(h_cnt==HLAST) h_cnt<=0;
	hs <= (h_cnt >= HBP+H+HFP);
end

// --------------- vertical timing -------------
reg[10:0] v_cnt;   // 0..2047
always@(posedge pclk) begin
	if(h_cnt==HLAST) begin
		if(v_cnt==VLAST) v_cnt <= 0; 
		else v_cnt <= v_cnt+1'd1;
	end
	
	vs <= (v_cnt >= V+VFP) && (v_cnt < V+VFP+VS);
end

reg [63:0] shift_register;

// ---------------- memory timing ----------------
always@(posedge pclk) begin
	reg [4:0] wcnt;
	reg [5:0] bcnt;
	
	shift_register[63:1] <= shift_register[62:0];
	bcnt <= bcnt + 1'd1;

	if(h_cnt == HBP-2'd2) begin
		wcnt <= 0;
		bcnt <= 0;
	end
	else if(!bcnt) begin
		shift_register <= line[wcnt];
		wcnt <= wcnt + 1'd1;
	end
end
 
always@(posedge pclk) begin
	if(h_cnt == HBP)   hblank <= 0;
	if(h_cnt == HBP+H) hblank <= 1;
	if(v_cnt == 0)     vblank <= 0;
	if(v_cnt == V)     vblank <= 1;
	pix <= ~shift_register[63];
end

endmodule
