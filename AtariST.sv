//============================================================================
//  Atari ST
//  Copyright (C) Till Harbaum <till@harbaum.org> 
//  Copyright (C) Gyorgy Szombathelyi <gyurco@freemail.hu>
//
//  Port to MiSTer
//  Copyright (C) Alexey Melnikov
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================ 

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [48:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,

`ifdef MISTER_FB
	// Use framebuffer in DDRAM (USE_FB=1 in qsf)
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

assign ADC_BUS  = 'Z;

assign UART_DTR = UART_DSR;
assign UART_RTS = uart ? usart_rts : UART_CTS;
assign UART_TXD = uart ? usart_so  : (midi_tx & ~mt32_use) ;

assign AUDIO_MIX = 0;

assign LED_USER  = ~&floppy_sel;
assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;
assign VGA_SCALER= 0;
assign HDMI_FREEZE = 0;

assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

wire       vcrop_en = status[42];
reg        en216p;
reg  [4:0] voff;
always @(posedge CLK_VIDEO) begin
	en216p <= (HDMI_WIDTH == 1920) && (HDMI_HEIGHT == 1080) && !forced_scandoubler && !scanlines && !mono && !viking_active;
end

wire vga_de;
video_freak video_freak
(
	.*,
	.VGA_DE_IN(vga_de),
	.ARX((!ar) ? (viking_active ? 8'd5 : 8'd4) : (ar - 1'd1)),
	.ARY((!ar) ? (viking_active ? 8'd4 : 8'd3) : 8'd0),
	.CROP_SIZE((en216p & vcrop_en) ? 10'd216 : 10'd0),
	.CROP_OFF(0),
	.SCALE(status[44:43])
);

///////////////////////  CLOCK/RESET  ///////////////////////////////////

wire pll_locked;
wire clk_128, clk_96, clk_32, clk_2;

pll pll
(
	.refclk   (CLK_50M),
	.outclk_0 (clk_96),
	.outclk_1 (clk_32),
	.outclk_2 (clk_2),
	.locked   (pll_locked)
);

wire init = ~pll_locked | RESET;

////////////////////////////  HPS I/O  //////////////////////////////////

`include "build_id.v"
parameter CONF_STR = {
	"AtariST;UART19200:9600:4800:2400:1200,MIDI;",
	"J,A,B,C,Option,Pause,#,*,0,1,2,3,4/L,5,6/R,7/Z,8/Y,9/X;",
	"jn,A,B,X,Select,Start,,,,,,,L,,R;",
	"I,",
	"ST joysticks,",
	"STe joysticks,",
	"MT32-pi: SoundFont #0,",
	"MT32-pi: SoundFont #1,",
	"MT32-pi: SoundFont #2,",
	"MT32-pi: SoundFont #3,",
	"MT32-pi: SoundFont #4,",
	"MT32-pi: SoundFont #5,",
	"MT32-pi: SoundFont #6,",
	"MT32-pi: SoundFont #7,",
	"MT32-pi: MT-32 v1,",
	"MT32-pi: MT-32 v2,",
	"MT32-pi: CM-32L,",
	"MT32-pi: Unknown mode;",
	"V,v",`BUILD_DATE
};

wire  [1:0] buttons;
wire [63:0] status;
wire        forced_scandoubler;
wire [31:0] sd_lba;
wire  [1:0] sd_rd;
wire  [1:0] sd_wr;
wire  [1:0] sd_ack;
wire  [7:0] sd_buff_addr;
wire [15:0] sd_buff_dout;
wire [15:0] sd_buff_din;
wire        sd_buff_wr;
wire  [1:0] img_mounted;
wire        img_readonly;
wire [63:0] img_size;
wire        ioctl_download;
wire [24:0] ioctl_addr;
wire [15:0] ioctl_dout;
wire        ioctl_wr;
wire  [7:0] ioctl_index;

wire [20:0] joy0,joy1,joy2,joy3;
wire [10:0] ps2_key;
wire [24:0] ps2_mouse;
wire  [7:0] ps2_mouse_ext;

wire [21:0] gamma_bus;

wire  [7:0] uart_mode;
wire        uart = (uart_mode < 3);

hps_io #(.CONF_STR(CONF_STR), .WIDE(1), .VDNUM(2)) hps_io
(
	.clk_sys(clk_32),
	.HPS_BUS(HPS_BUS),

	.buttons(buttons),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),
	.new_vmode(mde60),

	.joystick_0(joy0),
	.joystick_1(joy1),
	.joystick_2(joy2),
	.joystick_3(joy3),
	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse),
	.ps2_mouse_ext(ps2_mouse_ext),

	.status(status),
	.status_menumask({mt32_cfg,mt32_available}),
	.info_req(info_req),
	.info(info),

	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wr(ioctl_wr),
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),

	.sd_lba('{sd_lba,sd_lba}),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din('{sd_buff_din,sd_buff_din}),
	.sd_buff_wr(sd_buff_wr),

	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),
	
	.uart_mode(uart_mode),

	.EXT_BUS(EXT_BUS)
);

wire [35:0] EXT_BUS;
wire        dio_data_in_strobe;
wire [15:0] dio_data_in_reg;
wire        dio_data_out_strobe;
wire [15:0] dio_data_out_reg;
wire  [7:0] dio_status_in;
wire  [3:0] dio_status_index;
wire        dio_dma_ack;
wire  [7:0] dio_dma_status;
wire        dio_dma_nak;

hps_ext hps_ext
(
	.clk_sys(clk_32),
	.EXT_BUS(EXT_BUS),
	
	.dio_in_strobe(dio_data_in_strobe),
	.dio_in(dio_data_in_reg),

	.dio_out_strobe(dio_data_out_strobe),
	.dio_out(dio_data_out_reg),

	.dma_ack(dio_dma_ack),
	.dma_status(dio_dma_status),
	.dma_nak(dio_dma_nak),

	.dio_status(dio_status_in),
	.dio_status_idx(dio_status_index)
);

reg        dio_download;
reg [24:1] dio_data_addr;
reg [15:0] dio_data;
reg        dio_data_in_strobe_uio;
always @(posedge clk_32) begin
	
	dio_download <= ioctl_download;
	if(~dio_download & ioctl_download) begin
		case(ioctl_index[4:0])
			0: dio_data_addr <= (24'he00000 - 2'd2) >> 1; // TOS 256k
			1: dio_data_addr <= (24'hfc0000 - 2'd2) >> 1; // TOS 192k
			2: dio_data_addr <= (24'hfa0000 - 2'd2) >> 1; // Cartridge
			3: dio_data_addr <= 0; // Clear memory
		endcase
	end
	
	if (ioctl_wr & ioctl_download) begin
		if(ioctl_index[4:0] == 4 && !ioctl_addr[24:2]) begin // 4 - custom memory pointer
			if(!ioctl_addr) dio_data_addr[16:1] <= ioctl_dout;
			else dio_data_addr[24:17] <= ioctl_dout[7:0];
		end
		else begin
			dio_data_addr <= dio_data_addr + 1'd1;
			dio_data <= {ioctl_dout[7:0], ioctl_dout[15:8]};
			dio_data_in_strobe_uio <= ~dio_data_in_strobe_uio;
		end
	end
end

/////////////////////////////  A/V output  ///////////////////////////////////////

wire [11:0] hstart[8] = '{ 145, 161, 148, 0,  193, 257, 148, 0};
wire [11:0] hend[8]   = '{1841,1841, 788, 0, 1793,1745, 788, 0};
wire [11:0] vstart[8] = '{  19,  28,  37, 0,   28,  46, 122, 0};
wire [11:0] vend[8]   = '{ 261, 311, 437, 0,  252, 293, 522, 0};

reg       hblank_gen, vblank_gen;
reg [2:0] mode;
always @(posedge clk_32) begin
	reg old_vs, old_hs;
	reg  [11:0] hcnt,vcnt;
	
	hcnt <= hcnt + 1'd1;
	old_hs <= hsync_n;
	if(~old_hs & hsync_n) begin
		hcnt <= 0;
		vcnt <= vcnt + 1'd1;
	end

	old_vs <= vsync_n;
	if(old_vs & ~vsync_n) begin
		mode <= {mono ? mde60 : narrow_brd, mono, ~mono & pal};
		vcnt <= 0;
	end

	if(hcnt == hstart[mode]) begin
		hblank_gen <= 0;
		if(vcnt == vstart[mode]) vblank_gen <= 0;
		if(vcnt == vend[mode])   vblank_gen <= 1;
	end

	if(hcnt == hend[mode]) hblank_gen <= 1;
end

wire hs_sd,vs_sd,hbl_sd,vbl_sd;
wire [3:0] r_sd,g_sd,b_sd;
wire sd_ena = (forced_scandoubler || scanlines) && ~mode[1];
linedoubler linedoubler
(
	.clk_sys(clk_32),
	.enable(sd_ena),

	.hs_in(~hsync_n),
	.vs_in(~vsync_n),
	.hbl_in(hblank_gen),
	.vbl_in(vblank_gen),
	.r_in(r),
	.g_in(g),
	.b_in(b),

	.hs_out(hs_sd),
	.vs_out(vs_sd),
	.hbl_out(hbl_sd),
	.vbl_out(vbl_sd),
	.r_out(r_sd),
	.g_out(g_sd),
	.b_out(b_sd)
);

reg ce_pix_gst;
always @(posedge clk_32) begin
	reg [1:0] fs_div, tdiv, cnt;
	reg old_vs;

	if(~hblank_gen && ~vblank_gen && ce_div < tdiv) tdiv <= ce_div;

	old_vs <= vsync_n;
	if(old_vs & ~vsync_n) begin
		fs_div <= tdiv >> sd_ena;
		tdiv <= 3;
	end
	
	cnt <= cnt + 1'd1;
	ce_pix_gst <= 0;
	if(cnt == fs_div) begin
		cnt <= 0;
		ce_pix_gst <= 1;
	end
end

reg [3:0] stvid_r, stvid_g, stvid_b;
reg       stvid_hs, stvid_vs, stvid_hbl, stvid_vbl;
reg       stvid_ce;

always @(posedge clk_96) begin
	reg [1:0] div;

	div <= div + 1'd1;
	if(div == 2) div <= 0;

	stvid_ce <= 0;
	if(viking_active) begin
		stvid_ce  <= 1;
		stvid_r   <= {4{viking_pix}};
		stvid_g   <= {4{viking_pix}};
		stvid_b   <= {4{viking_pix}};
		stvid_hs  <= viking_hs;
		stvid_vs  <= viking_vs;
		stvid_hbl <= viking_hbl;
		stvid_vbl <= viking_vbl;
	end
	else if(!div) begin
		stvid_ce  <= ce_pix_gst;
		stvid_r   <= r_sd;
		stvid_g   <= g_sd;
		stvid_b   <= b_sd;
		stvid_hs  <= hs_sd;
		stvid_vs  <= vs_sd;
		stvid_hbl <= hbl_sd;
		stvid_vbl <= vbl_sd;
	end
end

assign CLK_VIDEO = clk_96;
assign CE_PIXEL  = stvid_ce;
assign VGA_SL    = (~mode[1] & ~viking_active) ? scanlines : 2'b00;
assign VGA_F1    = 0;
wire   [7:0] R   = {stvid_r, stvid_r};
wire   [7:0] G   = {stvid_g, stvid_g};
wire   [7:0] B   = {stvid_b, stvid_b};

gamma_fast gamma
(
	.clk_vid(CLK_VIDEO),
	.ce_pix(CE_PIXEL),

	.gamma_bus(gamma_bus),

	.HSync(stvid_hs),
	.VSync(stvid_vs),
	.DE(~{stvid_hbl | stvid_vbl}),
	
	.RGB_in(mt32_lcd ? {{2{mt32_lcd_pix}},R[7:2], {2{mt32_lcd_pix}},G[7:2], {2{mt32_lcd_pix}},B[7:2]} : {R,G,B}),

	.HSync_out(VGA_HS),
	.VSync_out(VGA_VS),
	.DE_out(vga_de),
	.RGB_out({VGA_R,VGA_G,VGA_B})
);

/* ------------------------------------------------------------------------------ */

reg [15:0] aud_l, aud_r;
always @(posedge CLK_AUDIO) begin
	reg [15:0] old_l0, old_l1, old_r0, old_r1;
	
	old_l0 <= audio_mix_l;
	old_l1 <= old_l0;
	if(old_l0 == old_l1) aud_l <= old_l1;

	old_r0 <= audio_mix_r;
	old_r1 <= old_r0;
	if(old_r0 == old_r1) aud_r <= old_r1;
end

reg [15:0] out_l, out_r;
always @(posedge CLK_AUDIO) begin
	reg [16:0] tmp_l, tmp_r;

	tmp_l <= {2'b00, aud_l[15:1]} + (mt32_mute ? 17'd0 : {mt32_i2s_l[15],mt32_i2s_l});
	tmp_r <= {2'b00, aud_r[15:1]} + (mt32_mute ? 17'd0 : {mt32_i2s_r[15],mt32_i2s_r});

	// clamp the output
	out_l <= (^tmp_l[16:15]) ? {tmp_l[16], {15{tmp_l[15]}}} : tmp_l[15:0];
	out_r <= (^tmp_r[16:15]) ? {tmp_r[16], {15{tmp_r[15]}}} : tmp_r[15:0];
end

assign AUDIO_S = 1;
assign AUDIO_L = out_l;
assign AUDIO_R = out_r;

////////////////////////////  MT32pi  ////////////////////////////////// 

wire        mt32_reset    = status[32] | reset;
wire        mt32_disable  = status[33];
wire        mt32_mode_req = status[34];
wire  [1:0] mt32_rom_req  = status[36:35];
wire  [7:0] mt32_sf_req   = status[39:37];
wire  [1:0] mt32_info     = status[41:40];

wire [15:0] mt32_i2s_r, mt32_i2s_l;
wire  [7:0] mt32_mode, mt32_rom, mt32_sf;
wire        mt32_lcd_en, mt32_lcd_pix, mt32_lcd_update;
wire        midi_rx;

wire mt32_newmode;
wire mt32_available;
wire mt32_use  = mt32_available & ~mt32_disable;
wire mt32_mute = mt32_available &  mt32_disable;

mt32pi mt32pi
(
	.*,
	.reset(mt32_reset),
	.CE_PIXEL(mt32_ce_pix),
	.midi_tx(midi_tx | mt32_mute)
);

wire  [4:0] mt32_cfg = (mt32_mode == 'hA2) ? {mt32_sf[2:0],  2'b10} :
                       (mt32_mode == 'hA1) ? {mt32_rom[1:0], 2'b01} : 5'd0;

reg mt32_lcd_on;
always @(posedge CLK_VIDEO) begin
	int to;
	reg old_update;

	old_update <= mt32_lcd_update;
	if(to) to <= to - 1;

	if(mt32_info == 2) mt32_lcd_on <= 1;
	else if(mt32_info != 3) mt32_lcd_on <= 0;
	else begin
		if(!to) mt32_lcd_on <= 0;
		if(old_update ^ mt32_lcd_update) begin
			mt32_lcd_on <= 1;
			to <= 96000000 * 2;
		end
	end
end

wire mt32_lcd = mt32_lcd_on & mt32_lcd_en;

reg mt32_ce_pix;
always @(posedge CLK_VIDEO) begin
	reg [1:0] div;

	div <= div + 1'd1;
	if(div == 2) div <= 0;

	mt32_ce_pix <= 0;
	if(!div) mt32_ce_pix <= ce_pix;
end


/* ------------------------------------------------------------------------------ */

reg [7:0] info;
reg       info_req = 0;
always @(posedge clk_32) begin
	reg old_mode;
	reg old_mt32mode;

	old_mt32mode <= mt32_newmode;
	old_mode <= joy_port_ste;
	info_req <= (old_mode ^ joy_port_ste) || ((old_mt32mode ^ mt32_newmode) && (mt32_info == 1));

	info <= (old_mode ^ joy_port_ste) ? (joy_port_ste ? 8'd2 : 8'd1) :
           (mt32_mode == 'hA2)                  ? (8'd3 + mt32_sf[2:0]) :
           (mt32_mode == 'hA1 && mt32_rom == 0) ?  8'd11 :
           (mt32_mode == 'hA1 && mt32_rom == 1) ?  8'd12 :
           (mt32_mode == 'hA1 && mt32_rom == 2) ?  8'd13 : 8'd14;
end


//////////////////////////////////////////////////////////////////////////////////
////////////////////////// Atari ST core /////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////

// enable additional ste/megaste features
wire       MEM512K       = (status[3:1] == 3'd0);
wire       MEM1M         = (status[3:1] == 3'd1);
wire       MEM2M         = (status[3:1] == 3'd2);
wire       MEM4M         = (status[3:1] == 3'd3);
wire       MEM8M         = (status[3:1] == 3'd4);
wire       MEM14M        = (status[3:1] == 3'd5);
wire [1:0] fdc_wp        = status[7:6];
wire       mono_monitor  = status[8];
wire [8:0] acsi_enable   = status[17:10];
wire       blitter_en    = (status[19] || ste);
wire [1:0] scanlines     = status[21:20];
wire       psg_stereo    = status[22];
wire       ste           = status[23] || status[24];
wire       mste          = status[24];
wire       steroids      = status[23] && status[24];  // a STE on steroids
wire       cubase_enable = status[25];
wire       viking_en     = status[28];
wire       narrow_brd    = status[29];
wire       mde60         = status[30];
wire [1:0] ar            = {status[31],status[9]};

// synchronized reset signal
reg reset;
always @(posedge clk_32) begin
	reg m8_en;
	reg [7:0] cnt = 0;

	m8_en <= mhz8_en1;
	if(m8_en) reset <= 0;
	
	if(~&cnt) begin
		reset <= 1;
		cnt <= cnt + 1'd1;
	end
	if(RESET | buttons[1] | status[0]) cnt <= 0;
end

reg peripheral_reset;
always @(posedge clk_32) peripheral_reset <= reset | ~cpu_reset_n_o;

reg ikbd_reset;
always @(posedge clk_2) ikbd_reset <= reset | ~cpu_reset_n_o;

// MCU signals
wire        mhz4, mhz4_en, clk16, clk16_en = ~clk16;
wire        mcu_dtack_n;
wire        hsync_n, vsync_n;
wire        rom0_n, rom1_n, rom2_n, rom3_n, rom4_n, rom5_n, rom6_n, romp_n;
wire        ras0_n, ras1_n;
wire        mfpint_n, mfpcs_n, mfpiack_n;
wire        sndir, sndcs;
wire        n6850, fcs_n;
wire        rtccs_n, rtcrd_n, rtcwr_n;
wire        sint;
wire [15:0] mcu_dout;
wire        ras_n = ras0_n & ras1_n;
wire        button_n, joywe_n, joyrl_n, joywl, joyrh_n;

// dma
wire        rdy_o, rdy_i, mcu_bg_n, mcu_br_n, mcu_bgack_n;

// compatibility for viking
wire  [1:0] bus_cycle;

// for other peripherals
wire        iodevice = ~as_n & fc2 & (fc0 ^ fc1) & mbus_a[23:16] == 8'hff;

// CPU signals
wire        mhz8, mhz8_en1, mhz8_en2;
wire        berr_n;
wire        ipl0_n, ipl1_n, ipl2_n;
wire        cpu_fc0, cpu_fc1, cpu_fc2;
wire        cpu_as_n, cpu_rw, cpu_uds_n, cpu_lds_n, vma_n, vpa_n, cpu_E;
wire        cpu_reset_n_o;
wire [15:0] cpu_din, cpu_dout;
wire [23:1] cpu_a;

wire        rom_n = rom0_n & rom1_n & rom2_n & (rom3_n | cubase_enable) & rom4_n & rom5_n & rom6_n & romp_n;
assign      cpu_din = 
              ~fcs_n ? dma_data_out :
              blitter_sel ? blitter_data_out :
              !rdat_n  ? shifter_dout :
              !(mfpcs_n & mfpiack_n)? { 8'hff, mfp_data_out } :
              (!rom3_n & cubase_enable) ? {cubase_dout, 8'hff} :
              !rom_n   ? rom_data_out :
              n6850    ? { mbus_a[2] ? midi_acia_data_out : kbd_acia_data_out, 8'hFF } :
              sndcs    ? { snd_data_out, 8'hFF }:
              mste_ctrl_sel ? {8'hff, mste_ctrl_data_out }:
              !button_n ? { 12'hfff, ste_buttons } :
              !(joyrh_n & joyrl_n) ? { joyrh_n ? 8'hff : ste_joy_in[15:8], joyrl_n ? 8'hff : ste_joy_in[7:0] } :
              mcu_dout;

// Shifter signals
wire        cmpcs_n, latch, de, blank_n, rdat_n, wdat_n, dcyc_n, sreq, sload_n, mono;
wire [15:0] shifter_dout;
wire [ 7:0] dma_snd_l, dma_snd_r;
wire [ 3:0] r, g, b;

// RAM signals
wire [23:1] ram_a;
wire        ram_uds, ram_lds, ram_we_n;
wire [15:0] ram_din;

// combined bus signals
wire        fc0 = blitter_has_bus ? blitter_fc0 : cpu_fc0;
wire        fc1 = blitter_has_bus ? blitter_fc1 : cpu_fc1;
wire        fc2 = blitter_has_bus ? blitter_fc2 : cpu_fc2;
wire        as_n = blitter_has_bus ? blitter_as_n : cpu_as_n;
wire        rw = blitter_has_bus ? blitter_rw_n : cpu_rw;
wire        uds_n = blitter_has_bus ? blitter_ds_n : cpu_uds_n;
wire        lds_n = blitter_has_bus ? blitter_ds_n : cpu_lds_n;
wire [23:1] mbus_a = blitter_has_bus ? blitter_addr : cpu_a;
// dout from the current bus master - TODO: merge with cpu_din after adding output enables to GSTMCU
wire [15:0] mbus_dout = !rdat_n ? shifter_dout :
                        !rom_n   ? rom_data_out :
                        blitter_sel ? blitter_data_out :
                        ~rdy_i ? dma_data_out :
                        cpu_dout;

wire        dtack_n = mcu_dtack_n_adj & ~mfp_dtack & ~mste_ctrl_sel & ~vme_sel & blitter_dtack_n;

/* ------------------------------------------------------------------------------ */
/* ------------------------------ GSTMCU + Shifter ------------------------------ */
/* ------------------------------------------------------------------------------ */

wire pal;
gstmcu gstmcu (
	.clk32      ( clk_32 ),
	.resb       ( ~reset ),
	.porb       ( ~init ),
	.FC0        ( fc0 ),
	.FC1        ( fc1 ),
	.FC2        ( fc2 ),
	.AS_N       ( as_n ),
	.RW         ( rw ),
	.UDS_N      ( uds_n ),
	.LDS_N      ( lds_n ),
	.VMA_N      ( vma_n ),
	.MFPINT_N   ( mfpint_n ),
	.A          ( mbus_a ), // from CPU bus
	.ADDR       ( ram_a ),  // to RAM
	// DIN - only interested in sources which can be bus masters (+shifter) - to avoid long combinatorial paths
	.DIN        ( ~rdy_i ? dma_data_out : blitter_sel ? blitter_data_out : !rdat_n  ? shifter_dout : cpu_dout ),
	.DOUT       ( mcu_dout ),
	.CLK_O      ( clk16 ),
	.MHZ8       ( mhz8 ),
	.MHZ8_EN1   ( mhz8_en1 ),
	.MHZ8_EN2   ( mhz8_en2 ),
	.MHZ4       ( mhz4 ),
	.MHZ4_EN    ( mhz4_en ),
	.RDY_N_I    ( rdy_o ),
	.RDY_N_O    ( rdy_i ),
	.BG_N       ( mcu_bg_n ),
	.BR_N_I     ( blitter_br_n ),
	.BR_N_O     ( mcu_br_n ),
	.BGACK_N_I  ( 1'b1 ),
	.BGACK_N_O  ( mcu_bgack_n ),
	.BERR_N     ( berr_n ),
	.IPL0_N     ( ipl0_n ),
	.IPL1_N     ( ipl1_n ),
	.IPL2_N     ( ipl2_n ),
	.DTACK_N_I  ( dtack_n ),
	.DTACK_N_O  ( mcu_dtack_n ),
	.IACK_N     ( mfpiack_n),
	.ROM0_N     ( rom0_n ),
	.ROM1_N     ( rom1_n ),
	.ROM2_N     ( rom2_n ),
	.ROM3_N     ( rom3_n ),
	.ROM4_N     ( rom4_n ),
	.ROM5_N     ( rom5_n ),
	.ROM6_N     ( rom6_n ),
	.ROMP_N     ( romp_n ),
	.RAM_N      ( ),
	.RAS0_N     ( ras0_n ),
	.RAS1_N     ( ras1_n ),
	.RAM_LDS    ( ram_lds ),
	.RAM_UDS    ( ram_uds ),
	.VPA_N      ( vpa_n ),
	.MFPCS_N    ( mfpcs_n ),
	.SNDIR      ( sndir ),
	.SNDCS      ( sndcs ),
	.N6850      ( n6850 ),
	.FCS_N      ( fcs_n ),
	.RTCCS_N    ( rtccs_n ),
	.RTCRD_N    ( rtcrd_n ),
	.RTCWR_N    ( rtcwr_n ),
	.LATCH      ( latch ),
	.HSYNC_N    ( hsync_n ),
	.VSYNC_N    ( vsync_n ),
	.DE         ( de ),
	.BLANK_N    ( blank_n ),
	.PAL        ( pal ),
	.MDE60      ( mde60 ),
	.RDAT_N     ( rdat_n ),
	.WE_N       ( ram_we_n ),
	.WDAT_N     ( wdat_n ),
	.CMPCS_N    ( cmpcs_n ),
	.DCYC_N     ( dcyc_n ),
	.SREQ       ( sreq),
	.SLOAD_N    ( sload_n),
	.SINT       ( sint ),

	.BUTTON_N   ( button_n ),
	.JOYWE_N    ( joywe_n  ),
	.JOYRL_N    ( joyrl_n  ),
	.JOYWL      ( joywl    ),
	.JOYRH_N    ( joyrh_n  ),

	.st            ( ~ste ),
	.extra_ram     ( MEM8M | MEM14M ),
	.tos192k       ( tos192k ),
	.turbo         ( turbo_bus ),
	.viking_at_c0  ( viking_enable && !steroids ),
	.viking_at_e8  ( viking_enable &&  steroids ),
	.bus_cycle     ( bus_cycle )
);

wire       ce_pix;
wire [1:0] ce_div;
gstshifter gstshifter (
	.clk32      ( clk_32 ),
	.ste        ( ste ),
	.resb       ( ~reset ),

	// CPU/RAM interface
	.CS         ( ~cmpcs_n ),
	.A          ( mbus_a[6:1] ),
	.DIN        ( mbus_dout ),
	.DOUT       ( shifter_dout ),
	.LATCH      ( latch ),
	.RDAT_N     ( rdat_n ),   // latched MDIN -> DOUT
	.WDAT_N     ( wdat_n ),   // DIN  -> MDOUT
	.RW         ( rw ),
	.MDIN       ( ram_data_out ),
	.MDOUT      ( ram_din  ),

	// VIDEO
	.MONO_OUT   ( mono ),
	.LOAD_N     ( dcyc_n ),
	.DE         ( de ),
	.BLANK_N    ( blank_n ),
	.R          ( r ),
	.G          ( g ),
	.B          ( b ),
	.CE_PIX     ( ce_pix ),
	.CE_DIV     ( ce_div ),

	// DMA SOUND
	.SLOAD_N    ( sload_n ),
	.SREQ       ( sreq ),
	.audio_left ( dma_snd_l ),
	.audio_right( dma_snd_r )
);

// --------------- the Viking compatible 1280x1024 graphics card -----------------

// viking/sm194 is enabled and max 8MB memory may be enabled. In steroids mode
// video memory is moved to $e80000 and all stram up to 14MB may be used
wire viking_mem_ok = MEM512K || MEM1M || MEM2M || MEM4M || MEM8M;
wire viking_enable = (viking_en && viking_mem_ok) || steroids;

// check for cpu access to 0xcxxxxx with viking enabled to switch video
// output once the driver loads. 256 accesses to the viking memory range
// are considered a valid sign that the driver is working. Without driver
// others may also probe that area which is why we want to see 256 accesses
reg [7:0] viking_in_use;
reg       viking_active;

always @(posedge clk_32) begin
	if(reset) begin
		viking_in_use <= 8'h00;
		viking_active <= 1'b0;
	end else begin
		// cpu writes to $c0xxxx or $e80000
		if(mhz8_en1 && !as_n && viking_enable &&
		  (mbus_a[23:18] == (steroids?6'b111010:6'b110000)) && (viking_in_use != 8'hff))
			viking_in_use <= viking_in_use + 1'd1;

		viking_active <= (viking_in_use == 8'hff);
	end
end

wire viking_hs, viking_vs, viking_hbl, viking_vbl;
wire viking_pix;

wire [23:1] viking_vaddr;
wire viking_read;

viking viking (
	.pclk      ( clk_96          ),
	.himem     ( steroids        ),
	.bus_sync  ( mhz8_en1 & viking_cycle ), // 2 MHz bus sync

	// memory interface
	.addr      ( viking_vaddr    ), // video word address
	.read      ( viking_read     ), // video read cycle
	.data      ( ram_data_out64  ), // video data read

	// video output
	.hs        ( viking_hs       ),
	.vs        ( viking_vs       ),
	.hblank    ( viking_hbl      ),
	.vblank    ( viking_vbl      ),
	.pix       ( viking_pix      )
);

/* ------------------------------------------------------------------------------ */
/* ------------------------------------ CPU ------------------------------------- */
/* ------------------------------------------------------------------------------ */

reg         use_16mhz;
reg         turbo_bus;

always @(posedge clk_32)
	if (mhz8_en1 & as_n) begin
		use_16mhz <= (enable_16mhz | steroids);
		turbo_bus <= (enable_cache | steroids);
	end

wire        fx68_phi1 = use_16mhz ?  clk16_en : mhz8_en1;
wire        fx68_phi2 = use_16mhz ? ~clk16_en : mhz8_en2;

wire        shifter_cycle = (turbo_bus && (bus_cycle == 0 || bus_cycle == 3)) || (!turbo_bus && bus_cycle == 2);
wire        mcu_dtack_n_adj = (use_16mhz & ~rom_n) ? (mcu_dtack_n | shifter_cycle) : mcu_dtack_n;

fx68k fx68k (
	.clk        ( clk_32     ),
	.extReset   ( reset      ),
	.pwrUp      ( reset      ),
	.enPhi1     ( fx68_phi1 | reset ),
	.enPhi2     ( fx68_phi2 | reset ),

	.eRWn       ( cpu_rw ),
	.ASn        ( cpu_as_n ),
	.LDSn       ( cpu_lds_n ),
	.UDSn       ( cpu_uds_n ),
	.E          ( cpu_E ),
	.VMAn       ( vma_n ),
	.FC0        ( cpu_fc0 ),
	.FC1        ( cpu_fc1 ),
	.FC2        ( cpu_fc2 ),
	.BGn        ( blitter_bg_n ),
	.oRESETn    ( cpu_reset_n_o ),
	.oHALTEDn   (),
	.DTACKn     ( dtack_n    ),
	.VPAn       ( vpa_n      ),
	.BERRn      ( berr_n     ),
	.HALTn      ( 1'b1       ),
	.BRn        ( blitter_br_n & mcu_br_n ),
	.BGACKn     ( blitter_bgack_n ),
	.IPL0n      ( ipl0_n     ),
	.IPL1n      ( ipl1_n     ),
	.IPL2n      ( ipl2_n     ),
	.iEdb       ( cpu_din    ),
	.oEdb       ( cpu_dout ),
	.eab        ( cpu_a )
);

/* ------------------------------------------------------------------------------ */
/* ------------------------------------ MFP ------------------------------------- */
/* ------------------------------------------------------------------------------ */

wire acia_irq = kbd_acia_irq || midi_acia_irq;

// the STE delays the xsirq by 1/250000 second before feeding it into timer_a
// 74ls164
wire      xsint = ~sint;
reg [7:0] xsint_delay;
always @(posedge clk_32 or negedge xsint) begin
	if(!xsint) xsint_delay <= 8'h00;            // async reset
	else if (clk_2_en) xsint_delay <= {xsint_delay[6:0], xsint};
end

wire xsint_delayed = xsint_delay[7];

// mfp io7 is mono_detect which in ste is xor'd with the dma sound irq
wire mfp_io7 = mono_monitor ^ (ste?xsint:1'b0);

// inputs 1,2 and 6 are outputs from an MC1489 serial receiver
wire  [7:0] mfp_gpio_in = {mfp_io7, 1'b1, !(acsi_irq | fdc_irq), !acia_irq, blitter_irq_n, UART_CTS, 1'b1, ~joy2[4]};
wire  [1:0] mfp_timer_in = {de, ste?xsint_delayed:1'b1};
wire  [7:0] mfp_data_out;
wire        mfp_dtack;

wire        usart_so, usart_rts;
wire        mfp_int, mfp_iack = ~mfpiack_n;
assign      mfpint_n = ~mfp_int;

mfp mfp (
	// cpu register interface
	.clk      ( clk_32        ),
	.clk_en   ( mhz4_en       ),
	.reset    ( peripheral_reset ),
	.din      ( mbus_dout[7:0]),
	.sel      ( ~mfpcs_n      ),
	.addr     ( mbus_a[5:1]   ),
	.ds       ( lds_n         ),
	.rw       ( rw            ),
	.dout     ( mfp_data_out  ),
	.irq      ( mfp_int       ),
	.iack     ( mfp_iack      ),
	.dtack    ( mfp_dtack     ),

	// serial/rs232 interface
	.si       ( UART_RXD      ),
	.so       ( usart_so      ),

	// input signals
	.t_i      ( mfp_timer_in  ),  // timer a/b inputs
	.i        ( mfp_gpio_in   )   // gpio-in
);

/* ------------------------------------------------------------------------------ */
/* ---------------------------------- IKBD -------------------------------------- */
/* ------------------------------------------------------------------------------ */

wire ikbd_tx, ikbd_rx;
wire joy_port_ste;

ikbd ikbd (
	.clk(clk_2),
	.res(ikbd_reset),

	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse),
	.ps2_mouse_ext(ps2_mouse_ext),

	.tx(ikbd_tx),
	.rx(ikbd_rx),
	// Port 2 is the first joystick for most games, so swap it by default.
	.joystick0(joy_port_ste ? 6'd0 : {joy1[5:4], joy1[0], joy1[1], joy1[2], joy1[3]}),
	.joystick1(joy_port_ste ? 5'd0 : {joy0[4],   joy0[0], joy0[1], joy0[2], joy0[3]}),
	.joy_port_toggle(joy_port_ste)
);

/* ------------------------------------------------------------------------------ */
/* ------------------------------- keyboard ACIA -------------------------------- */
/* ------------------------------------------------------------------------------ */

wire [7:0] kbd_acia_data_out;
wire       kbd_acia_irq;

acia kbd_acia (
	// cpu interface
	.clk      ( clk_32             ),
	.E        ( cpu_E              ),
	.reset    ( reset              ),
	.din      ( mbus_dout[15:8]    ),
	.sel      ( n6850 & ~mbus_a[2] ),
	.rs       ( mbus_a[1]          ),
	.rw       ( rw                 ),
	.dout     ( kbd_acia_data_out  ),
	.irq      ( kbd_acia_irq       ),

	.rx       ( ikbd_tx            ),
	.tx       ( ikbd_rx            )
);

/* ------------------------------------------------------------------------------ */
/* --------------------------------- MIDI ACIA ---------------------------------- */
/* ------------------------------------------------------------------------------ */

wire [7:0] midi_acia_data_out;
wire       midi_acia_irq;
wire       midi_out_strobe;
wire       midi_tx;

acia midi_acia (
	// cpu interface
	.clk      ( clk_32             ),
	.E        ( cpu_E              ),
	.reset    ( reset              ),
	.din      ( mbus_dout[15:8]    ),
	.sel      ( n6850 & mbus_a[2]  ),
	.rs       ( mbus_a[1]          ),
	.rw       ( rw                 ),
	.dout     ( midi_acia_data_out ),
	.irq      ( midi_acia_irq      ),

	.rx       ( uart ? midi_rx : UART_RXD ),
	.tx       ( midi_tx                   ),

	// redirected midi interface
	.dout_strobe ( midi_out_strobe )
);

/* ------------------------------------------------------------------------------ */
/* ------------------------------------ PSG ------------------------------------- */
/* ------------------------------------------------------------------------------ */

wire [7:0] snd_data_out;
wire [9:0] ym_audio_out_l;
wire [9:0] ym_audio_out_r;

reg clk_2_en;
always @(posedge clk_32) begin
	reg [3:0] cnt;
	clk_2_en <= (cnt == 0);
	cnt <= cnt + 1'd1;
end

// extra joysticks are wired to the printer port
// using the "gauntlet2 interface", fire of
// joystick 0 is connected to the mfp I0 (busy)
wire [7:0] port_b_in = { ~joy2[0], ~joy2[1], ~joy2[2], ~joy2[3],~joy3[0], ~joy3[1], ~joy3[2], ~joy3[3]};
wire [7:0] port_a_in = { port_a_out[7:6], ~joy3[4], port_a_out[4:0] };
wire [7:0] port_a_out;
wire [7:0] port_b_out;
wire       floppy_side = port_a_out[0];
wire [1:0] floppy_sel = port_a_out[2:1];
assign     usart_rts = port_a_out[3];

ym2149 ym2149 (
	.CLK         ( clk_32        ),
	.CE          ( clk_2_en      ),
	.RESET       ( peripheral_reset ),
	.DI          ( mbus_dout[15:8]),
	.DO          ( snd_data_out  ),
	.AUDIO_L     ( ym_audio_out_l),
	.AUDIO_R     ( ym_audio_out_r),
	.BDIR        ( sndir         ),
	.BC          ( sndcs         ),
	.STEREO      ( psg_stereo    ),
	.IOA_in      ( port_a_in     ),
	.IOA_out     ( port_a_out    ),
	.IOB_in      ( port_b_in     ),
	.IOB_out     ( port_b_out    )
);

// audio output processing
wire [15:0] audio_mix_l = {1'b0, ym_audio_out_l, ym_audio_out_l[9:5]} + {1'b0, dma_snd_l, dma_snd_l[7:1]};
wire [15:0] audio_mix_r = {1'b0, ym_audio_out_r, ym_audio_out_r[9:5]} + {1'b0, dma_snd_r, dma_snd_r[7:1]};

/* ------------------------------------------------------------------------------ */
/* ------------------------------ Mega STe control ------------------------------ */
/* ------------------------------------------------------------------------------ */

// mega ste cache controller 8 bit interface at $ff8e20 - $ff8e21
// STEroids mode does not have this config, it always runs full throttle
wire       mste_ctrl_sel = !steroids && mste && iodevice && !lds_n && ({mbus_a[15:1], 1'd0} == 16'h8e20);
wire [7:0] mste_ctrl_data_out;
wire       enable_16mhz, enable_cache;

mste_ctrl mste_ctrl (
	// cpu register interface
	.clk      ( clk_32             ),
	.reset    ( reset              ),
	.din      ( mbus_dout[7:0]     ),
	.sel      ( mste_ctrl_sel      ),
	.rw       ( rw                 ),
	.dout     ( mste_ctrl_data_out ),

	.enable_cache ( enable_cache   ),
	.enable_16mhz ( enable_16mhz   )
);

// vme controller 8 bit interface at $ffff8e00 - $ffff8e0f
// (requierd to enable Mega STE cpu speed/cache control)
wire vme_sel = !steroids && mste && iodevice && ({mbus_a[15:4], 4'd0} == 16'h8e00);

/* ------------------------------------------------------------------------------ */
/* ---------------------------------- Blitter ----------------------------------- */
/* ------------------------------------------------------------------------------ */
wire        blitter_irq_n;
wire        blitter_br_n;
wire        blitter_bgack_n;
wire        blitter_bg_n;
wire        blitter_sel;
wire [15:0] blitter_data_out;

wire        blitter_as_n;
wire        blitter_ds_n;
wire        blitter_rw_n;
wire        blitter_fc0 = 1'b1, blitter_fc1 = 1'b0, blitter_fc2 = 1'b1;
wire        blitter_dtack_n;
wire [23:1] blitter_addr;
wire        blitter_has_bus;

blt_clks Clks;

assign Clks.clk = clk_32;
assign Clks.aRESETn = !peripheral_reset;
assign Clks.sReset = init | peripheral_reset;
assign Clks.pwrUp = init;

assign Clks.enPhi1 = use_16mhz ?  clk16_en : mhz8_en1;
assign Clks.enPhi2 = use_16mhz ? ~clk16_en : mhz8_en2;
assign Clks.anyPhi = Clks.enPhi2 | Clks.enPhi1;

assign { Clks.extReset, Clks.phi1, Clks.phi2} = 3'b000;

wire mblit_selected;
wire mblit_oBGACKn;

stBlitter stBlitter(
	.Clks     ( Clks ),
	.ASn      ( as_n | ~blitter_en ),
	.RWn      ( cpu_rw ),
	.LDSn     ( lds_n ),
	.UDSn     ( uds_n ),
	.FC0      ( fc0 ),
	.FC1      ( fc1 ),
	.FC2      ( fc2 ),
	.BERRn    ( berr_n ),
	.iDTACKn  ( dtack_n ),
	.ctrlOe   ( blitter_has_bus ),
	.dataOe   ( blitter_sel ),
	.oASn     ( blitter_as_n ),
	.oDSn     ( blitter_ds_n ),
	.oRWn     ( blitter_rw_n ),
	.oDTACKn  ( blitter_dtack_n ),
	.selected ( mblit_selected ),
	.iBRn     ( mcu_br_n ),
	.BGIn     ( blitter_bg_n ),
	.iBGACKn  ( mcu_bgack_n ),
	.oBRn     ( blitter_br_n ),
	.oBGACKn  ( mblit_oBGACKn ),
	.INTn     ( blitter_irq_n ),
	.BGOn     ( mcu_bg_n ),
	.dmaInput ( mbus_dout ),
	.iABUS    ( mbus_a ),
	.oABUS    ( blitter_addr ),
	.iDBUS    ( cpu_dout ),
	.oDBUS    ( blitter_data_out )
);

assign blitter_bgack_n = mblit_oBGACKn & mcu_bgack_n;		// This really happens inside Blitter
assign { blitter_fc2, blitter_fc1, blitter_fc0} = 3'b101;

/* ------------------------------------------------------------------------------ */
/* ---------------------------- STe controller ports ---------------------------- */
/* ------------------------------------------------------------------------------ */

wire [15:0] ste_joy_in;
wire  [3:0] ste_buttons;
reg   [7:0] ste_joy_out;

wire  [7:0] ste_joy_out_pins = joywe_n ? 8'hff : ste_joy_out;

always @(posedge clk_32) begin
	if (joywl) ste_joy_out <= mbus_dout[7:0];
end

ste_joypad ste_joypad0 (
	.joy      ( joy_port_ste ? joy1 : 21'd0 ),
	.din      ( ste_joy_out_pins[3:0] ),
	.dout     ( { ste_joy_in[11:8], ste_joy_in[3:0] } ),
	.buttons  ( ste_buttons[1:0] )
);

ste_joypad ste_joypad1 (
	.joy      ( joy_port_ste ? joy0 : 21'd0 ),
	.din      ( ste_joy_out_pins[7:4] ),
	.dout     ( { ste_joy_in[15:12], ste_joy_in[7:4] } ),
	.buttons  ( ste_buttons[3:2] )
);

/* ------------------------------------------------------------------------------ */
/* ------------------------------------- DMA ------------------------------------ */
/* ------------------------------------------------------------------------------ */

wire dma_write, dma_read;
wire [15:0] dma_data_out;

wire acsi_irq;

dma dma (
	// system interface
	.clk          ( clk_32        ),
	.clk_en       ( mhz8_en1      ),
	.reset        ( reset         ),

	// cpu interface
	.cpu_din      ( mbus_dout     ),
	.cpu_sel      ( ~fcs_n        ),
	.cpu_a1       ( mbus_a[1]     ),
	.cpu_rw       ( rw            ),
	.cpu_dout     ( dma_data_out  ),

	// IO controller interface for ACSI
	.dio_data_in_strobe  ( dio_data_in_strobe  ),
	.dio_data_in_reg     ( dio_data_in_reg     ),
	.dio_data_out_strobe ( dio_data_out_strobe ),
	.dio_data_out_reg    ( dio_data_out_reg    ),
	.dio_dma_ack         ( dio_dma_ack         ),
	.dio_dma_status      ( dio_dma_status      ),
	.dio_dma_nak         ( dio_dma_nak         ),
	.dio_status_in       ( dio_status_in       ),
	.dio_status_index    ( dio_status_index    ),

	// additional signals for ACSI interface
	.acsi_irq     ( acsi_irq           ),
	.acsi_enable  ( acsi_enable ),

	// FDC interface
	.fdc_drq      ( fdc_drq  ),
	.fdc_addr     ( fdc_addr ),
	.fdc_sel      ( fdc_sel  ),
	.fdc_rw       ( fdc_rw   ),
	.fdc_din      ( fdc_din  ),
	.fdc_dout     ( fdc_dout ),

	// ram interface
	.rdy_i        ( rdy_i        ),
	.rdy_o        ( rdy_o        ),
	.ram_din      ( shifter_dout )
);

wire       fdc_irq;
wire       fdc_drq;
wire [1:0] fdc_addr;
wire       fdc_sel;
wire       fdc_rw;
wire [7:0] fdc_din;
wire [7:0] fdc_dout;

// Some broken software selects both drives at the same time. On real hardware this
// only works if no second drive is present. In our setup the second drive is present
// but we can simply map all such broken accesses to drive A only
wire [1:0] floppy_sel_exclusive = (floppy_sel == 2'b00)?2'b10:floppy_sel;

fdc1772 #(.IMG_TYPE(1)) fdc1772 (
	.clkcpu         ( clk_32           ), // system cpu clock.
	.clk8m_en       ( mhz8_en1         ),

	// external set signals
	.floppy_drive   ( {2'b11, floppy_sel_exclusive} ),
	.floppy_side    ( floppy_side      ),
	.floppy_reset   ( ~peripheral_reset),

	// interrupts
	.irq            ( fdc_irq          ),
	.drq            ( fdc_drq          ),

	.cpu_addr       ( fdc_addr         ),
	.cpu_sel        ( fdc_sel          ),
	.cpu_rw         ( fdc_rw           ),
	.cpu_din        ( fdc_din          ),
	.cpu_dout       ( fdc_dout         ),

	// place any signals that need to be passed up to the top after here.
	.img_mounted    ( img_mounted      ), // signaling that new image has been mounted
	.img_wp         ( fdc_wp           ), // write protect
	.img_size       ( img_size         ), // size of image in bytes
	.sd_lba         ( sd_lba           ),
	.sd_rd          ( sd_rd            ),
	.sd_wr          ( sd_wr            ),
	.sd_ack         ( |sd_ack          ),
	.sd_buff_addr   ( sd_buff_addr     ),
	.sd_dout        ( sd_buff_dout     ),
	.sd_din         ( sd_buff_din      ),
	.sd_dout_strobe ( sd_buff_wr       )
);

/* ------------------------------------------------------------------------------ */
/* ------------------------------- Cubase dongle  ------------------------------- */
/* ------------------------------------------------------------------------------ */
wire        cubase3_d8;
wire  [7:0] cubase2_dout;
wire  [7:0] cubase_dout = cubase_sel ? cubase2_dout : {7'h7f, cubase3_d8};
reg         cubase_sel; // Cubase3/2 dongle
reg         cubase_lock;

always @(posedge clk_32) begin
	if (peripheral_reset) begin
		cubase_sel <= 0;
		cubase_lock <= 0;
	end
	else if (cubase_enable & !rom3_n & !cubase_lock) begin
		cubase_sel <= |mbus_a[7:1];
		cubase_lock <= 1;
	end
end

cubase2_dongle cubase2_dongle (
	.clk        ( clk_32           ),
	.reset      ( peripheral_reset ),
	.uds_n      ( uds_n            ),
	.A          ( mbus_a[8:1]      ),
	.D          ( cubase2_dout     )
);

cubase3_dongle cubase3_dongle (
	.clk        ( clk_32           ),
	.reset      ( peripheral_reset ),
	.rom3_n     ( rom3_n           ),
	.a8         ( mbus_a[8]        ),
	.d8         ( cubase3_d8       )
);

/* ------------------------------------------------------------------------------ */
/* --------------------------- SDRAM bus multiplexer ---------------------------- */
/* ------------------------------------------------------------------------------ */

wire cpu_precycle = (bus_cycle == 0);
wire cpu_cycle    = (bus_cycle == 1) || (bus_cycle == 2 && turbo_bus);
wire viking_cycle = (bus_cycle == 2 && !turbo_bus) || (bus_cycle == 3 && turbo_bus); // this is the shifter cycle, too

reg ras_n_d;
reg data_wr;
wire ram_req = ras_n_d & ~ras_n & |ram_a; // RAS_N going low and not refresh
wire ram_we = ~ram_we_n;

// TOS/cartridge upload via data_io
reg tos192k = 1'b0;

always @(posedge clk_32) begin
	reg dio_data_in_strobe_uioD;

	ras_n_d <= ras_n;
	data_wr <= 1'b0;
	if (cpu_precycle && mhz8_en1) begin
		dio_data_in_strobe_uioD <= dio_data_in_strobe_uio;
		if (dio_data_in_strobe_uio ^ dio_data_in_strobe_uioD) data_wr <= 1'b1;
	end
	if (dio_download) begin
		if (dio_data_addr[23:18] == 6'b111111) tos192k <= 1'b1;
		else if (dio_data_addr[23:20] == 4'he) tos192k <= 1'b0;
	end
end

// ----------------- RAM address --------------
wire [23:1] sdram_address = (cpu_cycle & dio_download)?dio_data_addr[23:1]:
                            (viking_cycle & viking_active & viking_read)?viking_vaddr:ram_a;

wire        ram_en = (MEM512K & ram_a[23:19] == 5'b00000) ||
                     (MEM1M   & ram_a[23:20] == 4'b0000)  ||
                     (MEM2M   & ram_a[23:21] == 3'b000)   ||
                     (MEM4M   & ram_a[23:22] == 2'b00)    ||
                     (MEM8M   & ram_a[23] == 1'b0)        ||
                     (MEM14M  & (~ram_a[23] | ~ram_a[22] | (ram_a[23] & ram_a[22] & ~ram_a[21]))) ||
                     (viking_enable & ~steroids & ram_a[23:18] == 6'b110000) ||
                     (viking_enable &  steroids & ram_a[23:19] == 5'b11101);

// ----------------- RAM read -----------------
wire sdram_req = (cpu_cycle & dio_download)?data_wr:
                 (viking_cycle & viking_active & viking_read)?1'b1:
                 (ram_req & ram_en);

// ----------------- RAM write -----------------
wire sdram_we = (cpu_cycle & dio_download)?1'b1:ram_we;

wire [15:0] ram_data_in = dio_download? dio_data : ram_din;

// data strobe
wire sdram_uds = (cpu_cycle & dio_download)?1'b1:ram_uds;
wire sdram_lds = (cpu_cycle & dio_download)?1'b1:ram_lds;

wire [23:1] rom_a = (!rom2_n & ~tos192k) ? { 4'hE, 2'b00, mbus_a[17:1] } :
                    (!rom2_n &  tos192k) ? { 4'hF, 2'b11, mbus_a[17:1] } : mbus_a;

wire [15:0] ram_data_out;
wire [63:0] ram_data_out64;
wire [15:0] rom_data_out;

assign SDRAM_CKE = 1'b1;

sdram sdram (
	// interface to the MT48LC16M16 chip
	.sd_data     	( SDRAM_DQ                 ),
	.sd_addr     	( SDRAM_A                  ),
	.sd_dqm      	( {SDRAM_DQMH, SDRAM_DQML} ),
	.sd_cs       	( SDRAM_nCS                ),
	.sd_ba       	( SDRAM_BA                 ),
	.sd_we       	( SDRAM_nWE                ),
	.sd_ras      	( SDRAM_nRAS               ),
	.sd_cas      	( SDRAM_nCAS               ),
	.sd_clk      	( SDRAM_CLK                ),

	// system interface
	.clk_96        ( clk_96                   ),
	.clk_8_en      ( mhz8_en1                 ),
	.init          ( init                     ),

	// cpu/chipset interface
	.din           ( ram_data_in              ),
	.addr          ( { 1'b0, sdram_address }  ),
	.ds            ( { sdram_uds, sdram_lds } ),
	.req           ( sdram_req                ),
	.we            ( sdram_we                 ),
	.dout          ( ram_data_out             ),
	.dout64        ( ram_data_out64           ),

	// ROM access port
	.rom_oe        ( ~rom_n                   ),
	.rom_addr      ( rom_a                    ),
	.rom_dout      ( rom_data_out             )
);

endmodule
