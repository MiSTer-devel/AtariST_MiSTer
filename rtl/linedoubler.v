//
// scandoubler.v
// 
// Copyright (c) 2015 Till Harbaum <till@harbaum.org> 
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

// TODO: Delay vsync one line

module linedoubler
(
	// system interface
	input                        clk_sys,

	input                        enable,

	// shifter video interface
	input                        hs_in,
	input                        vs_in,
	input                        hbl_in,
	input                        vbl_in,
	input      [COLOR_DEPTH-1:0] r_in,
	input      [COLOR_DEPTH-1:0] g_in,
	input      [COLOR_DEPTH-1:0] b_in,

	// output interface
	output reg                   hs_out,
	output reg                   vs_out,
	output reg                   hbl_out,
	output reg                   vbl_out,
	output reg [COLOR_DEPTH-1:0] r_out,
	output reg [COLOR_DEPTH-1:0] g_out,
	output reg [COLOR_DEPTH-1:0] b_out
);

parameter HCNT_WIDTH  = 10;
parameter COLOR_DEPTH = 4;

// try to detect changes in input signal and lock input clock gate
// it

reg [1:0] i_div;

reg ce_in;

always @(posedge clk_sys) begin
	reg last_hs_in;
	last_hs_in <= hs_in;
	
	ce_in <= ~ce_in;
	if(last_hs_in & !hs_in) ce_in <= 0;
end	


// ==================================================================
// ======================== the line buffers ========================
// ==================================================================

// 2 lines of 2**HCNT_WIDTH pixels 3*COLOR_DEPTH bit RGB
(* ramstyle = "no_rw_check" *) reg [COLOR_DEPTH*3+2-1:0] sd_buffer[2*2**HCNT_WIDTH];

// use alternating sd_buffers when storing/reading data   
reg        line_toggle;

// total hsync time (in 16MHz cycles), hs_total reaches 1024
reg  [HCNT_WIDTH-1:0] hs_max;
reg  [HCNT_WIDTH-1:0] hs_rise;
reg  [HCNT_WIDTH-1:0] hcnt;

always @(posedge clk_sys) begin
	reg hsD, vsD;

	if(ce_in) begin
		hsD <= hs_in;

		// falling edge of hsync indicates start of line
		if(hsD && !hs_in) begin
			hs_max <= hcnt;
			hcnt <= 0;
		end else begin
			hcnt <= hcnt + 1'd1;
		end

		// save position of rising edge
		if(!hsD && hs_in) hs_rise <= hcnt;

		vsD <= vs_in;
		if(vsD != vs_in) line_toggle <= 0;

		// begin of incoming hsync
		if(hsD && !hs_in) line_toggle <= !line_toggle;
	end
end

// ==================================================================
// ==================== output timing generation ====================
// ==================================================================

reg  [HCNT_WIDTH-1:0] sd_hcnt;

// timing generation runs 32 MHz (twice the input signal analysis speed)
always @(posedge clk_sys) begin
	reg hsD;

	hsD <= hs_in;

	// output counter synchronous to input and at twice the rate
	sd_hcnt <= sd_hcnt + 1'd1;
	if(hsD && !hs_in)     sd_hcnt <= hs_max;
	if(sd_hcnt == hs_max) sd_hcnt <= 0;

	// replicate horizontal sync at twice the speed
	if(sd_hcnt == hs_max)  hs_out <= 0;
	if(sd_hcnt == hs_rise) begin
		hs_out <= 1;
		vs_out <= vs_in;
	end

	{vbl_out, hbl_out, r_out, g_out, b_out} <= sd_out;
	if(!enable) begin
		{vbl_out, hbl_out, r_out, g_out, b_out} <= {vbl_in, hbl_in, r_in, g_in, b_in};
		hs_out <= hs_in;
		vs_out <= vs_in;
	end
end

wire [COLOR_DEPTH*3+2-1:0] sd_out;
line_buf #(HCNT_WIDTH+1, COLOR_DEPTH*3+2) line_buf
(
	.clock(clk_sys),
	.data({vbl_in, hbl_in, r_in, g_in, b_in}),
	.wraddress({line_toggle, hcnt}),
	.wren(ce_in),
	.rdaddress({~line_toggle, sd_hcnt}),
	.q(sd_out)
);

endmodule

module line_buf #(parameter AWIDTH, parameter DWIDTH)
(
	input                   clock,
	input      [DWIDTH-1:0] data,
	input      [AWIDTH-1:0] rdaddress,
	input      [AWIDTH-1:0] wraddress,
	input                   wren,
	output reg [DWIDTH-1:0] q
);

reg [DWIDTH-1:0] ram[0:2**AWIDTH];

always@(posedge clock) begin
	if(wren) ram[wraddress] <= data;
	q <= ram[rdaddress];
end

endmodule
