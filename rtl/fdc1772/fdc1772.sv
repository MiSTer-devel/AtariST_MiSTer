//
// fdc1772.v
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
//

// TODO: 
// - 30ms settle time after step before data can be read
// - implement sector size 0

module fdc1772 (
	input            clkcpu, // system cpu clock.
	input            clk8m_en,

	// external set signals
	input      [W:0] floppy_drive,
	input            floppy_side, 
	input            floppy_reset,
	output           floppy_step,
	input            floppy_motor,
	output           floppy_ready,

	// interrupts
	output reg       irq,
	output reg       drq, // data request

	input      [1:0] cpu_addr,
	input            cpu_sel,
	input            cpu_rw,
	input      [7:0] cpu_din,
	output reg [7:0] cpu_dout,

	// place any signals that need to be passed up to the top after here.
	input      [W:0] img_mounted, // signaling that new image has been mounted
	input      [W:0] img_wp,      // write protect
	input            img_ds,      // double-sided image (for BBC Micro only)
	input     [31:0] img_size,    // size of image in bytes
	input            img_mfmt,
	output    [31:0] sd_lba,
	output     [W:0] sd_rd,
	output reg [W:0] sd_wr,
	output     [5:0] sd_blk_cnt,
	input            sd_ack,
	input     [12:0] sd_buff_addr,
	input     [15:0] sd_dout,
	output    [15:0] sd_din,
	input            sd_dout_strobe
);


parameter CLK_EN           = 16'd8000; // in kHz
parameter CLKCPU_KHZ       = 32000;
parameter FD_NUM           = 2;    // number of supported floppies
parameter MODEL            = 2;    // 0 - wd1770, 1 - fd1771, 2 - wd1772, 3 = wd1773/fd1793
parameter EXT_MOTOR        = 1'b0; // != 0 if motor is controlled externally by floppy_motor
parameter INVERT_HEAD_RA   = 1'b0; // != 0 - invert head in READ_ADDRESS reply

localparam IMG_ARCHIE      = 0;
localparam IMG_ST          = 1;
localparam IMG_BBC         = 2; // SSD, DSD formats
localparam IMG_TI99        = 3; // V9T9 format

parameter  IMG_TYPE        = IMG_ARCHIE;

localparam W    = FD_NUM - 1;
localparam WIDX = $clog2(FD_NUM);

// -------------------------------------------------------------------------
// --------------------- IO controller image handling ----------------------
// -------------------------------------------------------------------------

reg  [10:0] fdn_sector_len[FD_NUM];
reg   [4:0] fdn_spt[FD_NUM];     // sectors/track
reg   [9:0] fdn_gap_len[FD_NUM]; // gap len/sector
reg         fdn_doubleside[FD_NUM];
reg         fdn_hd[FD_NUM];
reg         fdn_fm[FD_NUM];
reg         fdn_present[FD_NUM];
reg         fdn_mfmt[FD_NUM];
reg         fdn_was_mfmt[FD_NUM];

reg  [11:0] image_sectors;
reg  [11:0] image_sps; // sectors/side
reg   [4:0] image_spt; // sectors/track
reg   [9:0] image_gap_len;
reg         image_doubleside;
wire        image_hd = img_size[20];
reg         image_fm;

reg   [1:0] sector_size_code; // sec size 0=128, 1=256, 2=512, 3=1024
reg  [31:0] sd_lba_sec;
reg  [10:0] sector_size;
reg         sector_base; // number of first sector on track (archie 0, dos 1)

always @(*) begin
	case (IMG_TYPE)
	IMG_ARCHIE: begin
		// archie, 1024 bytes/sector
		sector_size_code = 2'd3;
		sector_base = 0;
		sd_lba_sec = {(16'd0 + (fd_spt*track[6:0]) << fd_doubleside) + (floppy_side ? 5'd0 : fd_spt) + sector[4:0], s_odd };

		image_fm = 0;
		image_sectors = img_size[21:10];
		image_doubleside = 1'b1;
		image_spt = image_hd ? 5'd10 : 5'd5;
		image_gap_len = 10'd220;

	end
	IMG_ST: begin
		// this block is valid for the .st format (or similar arrangement), 512 bytes/sector
		sector_size_code = 2'd2;
		sector_base = 1;
		sd_lba_sec = ((fd_spt*track[6:0]) << fd_doubleside) + (floppy_side ? 5'd0 : fd_spt) + sector[4:0] - 1'd1;

		image_fm = 0;
		image_sectors = img_size[20:9];
		image_doubleside = 1'b0;
		image_sps = image_sectors;
		if (image_sectors > (85*12)) begin
			image_doubleside = 1'b1;
			image_sps = image_sectors >> 1'b1;
		end
		if (image_hd) image_sps = image_sps >> 1'b1;

		// spt : 9-12, tracks: 79-85
		case (image_sps)
			711,720,729,738,747,756,765   : image_spt = 5'd9;
			790,800,810,820,830,840,850   : image_spt = 5'd10;
			948,960,972,984,996,1008,1020 : image_spt = 5'd12;
			default : image_spt = 5'd11;
		endcase;

		if (image_hd) image_spt = image_spt << 1'b1;

		// SECTOR_GAP_LEN = BPT/SPT - (SECTOR_LEN + SECTOR_HDR_LEN) = 6250/SPT - (512+6)
		case (image_spt)
			5'd9, 5'd18: image_gap_len = 10'd176;
			5'd10,5'd20: image_gap_len = 10'd107;
			5'd11,5'd22: image_gap_len = 10'd50;
			default : image_gap_len = 10'd2;
		endcase;
	end
	IMG_BBC, IMG_TI99: begin
		// 256 bytes/sector single density (BBC SSD/DSD, TI99/4A)
		sector_size_code = 2'd1;
		sector_base = 0;
		if (IMG_TYPE == IMG_BBC) begin
			sd_lba_sec = (((fd_spt*track[6:0]) << fd_doubleside) + (floppy_side ? 5'd0 : fd_spt) + sector[4:0]) >> 1;
			image_spt = 10;
		end else begin
			sd_lba_sec = (fd_spt*(floppy_side ? track[5:0] : 79-track[5:0]) + sector[4:0]) >> 1;
			image_spt = 9;
		end

		image_fm = 1;
		image_sectors = img_size[19:8];
		image_doubleside = img_ds;
		if (img_ds)
			image_sps = image_sectors >> 1'b1;
		else
			image_sps = image_sectors;
		image_gap_len = 10'd50;
	end
	default: begin
		sector_size_code = 2'd0;
		sector_base = 0;
		sd_lba_sec = 0;
		image_fm = 0;
		image_sectors = 0;
		image_doubleside = 0;
		image_spt = 0;
		image_gap_len = 0;
	end

	endcase

	sector_size = 11'd128 << sector_size_code;
end

always @(posedge clkcpu) begin
	reg [W:0] img_mountedD;
	integer i;
	img_mountedD <= img_mounted;
	
	for(i = 0; i < FD_NUM; i = i+1'd1) begin
		if (~img_mountedD[i] && img_mounted[i]) begin
			fdn_present[i] <= |img_size;
			fdn_mfmt[i] <= img_mfmt && |img_size;
			if (|img_size) fdn_was_mfmt[i] <= img_mfmt;
			fdn_sector_len[i] <= sector_size;
			fdn_spt[i] <= image_spt;
			fdn_gap_len[i] <= image_gap_len;
			fdn_doubleside[i] <= image_doubleside;
			fdn_hd[i] <= image_hd;
			fdn_fm[i] <= image_fm;
		end
	end
end

// -------------------------------------------------------------------------
// ---------------------------- IRQ/DRQ handling ---------------------------
// -------------------------------------------------------------------------
reg cpu_selD;
reg cpu_rwD;
reg [1:0] cpu_addrD;
always @(posedge clkcpu) begin
	cpu_rwD <= cpu_sel & ~cpu_rw;
	cpu_selD <= cpu_sel;
	cpu_addrD <= cpu_addr;
end

wire cpu_acc_new = cpu_sel && (!cpu_selD || cpu_addr != cpu_addrD);

wire cpu_we = cpu_sel & ~cpu_rw & ~cpu_rwD;

reg irq_set;

// floppy_reset and read of status register/write of command register clears irq
reg cpu_rw_cmdstatus;
always @(posedge clkcpu)
  cpu_rw_cmdstatus <= cpu_acc_new && cpu_addr == FDC_REG_CMDSTATUS;

wire irq_clr = !floppy_reset || cpu_rw_cmdstatus;

always @(posedge clkcpu) begin
	if(irq_clr) irq <= 1'b0;
	else if(irq_set) irq <= 1'b1;
end

reg drq_set;

reg cpu_rw_data;
always @(posedge clkcpu)
	cpu_rw_data <= cpu_acc_new && cpu_addr == FDC_REG_DATA;

reg drq_drop;
wire drq_clr = !floppy_reset || cpu_rw_data || drq_drop;

always @(posedge clkcpu) begin
	if(drq_clr) drq <= 1'b0;
	else if(drq_set) drq <= 1'b1;
end

// -------------------------------------------------------------------------
// -------------------- virtual floppy drive mechanics ---------------------
// -------------------------------------------------------------------------

wire       fdn_index[FD_NUM];
wire       fdn_ready[FD_NUM];
wire [6:0] fdn_track[FD_NUM];
wire [4:0] fdn_sector[FD_NUM];
wire       fdn_sector_hdr[FD_NUM];
wire       fdn_sector_data[FD_NUM];
wire       fdn_dclk[FD_NUM];

generate
	genvar i;
	
	for(i=0; i < FD_NUM; i = i+1) begin :fdd

		floppy #(.CLK_EN(CLK_EN)) floppy
		(
			.clk         ( clkcpu             ),
			.clk8m_en    ( clk8m_en           ),

			// control signals into floppy
			.select      ( fd_any && fdn == i ),
			.motor_on    ( fd_motor           ),
			.step_in     ( step_in            ),
			.step_out    ( step_out           ),

			// physical parameters
			.sector_len  ( fdn_sector_len[i]  ),
			.spt         ( fdn_spt[i]         ),
			.sector_gap_len ( fdn_gap_len[i]  ),
			.sector_base ( sector_base        ),
			.hd          ( fdn_hd[i]          ),
			.fm          ( fdn_fm[i]          ),

			// status signals generated by floppy
			.dclk_en     ( fdn_dclk[i]        ),
			.track       ( fdn_track[i]       ),
			.sector      ( fdn_sector[i]      ),
			.sector_hdr  ( fdn_sector_hdr[i]  ),
			.sector_data ( fdn_sector_data[i] ),
			.ready       ( fdn_ready[i]       ),
			.index       ( fdn_index[i]       )
		);
	end
endgenerate

// -------------------------------------------------------------------------
// ----------------------------- floppy demux ------------------------------
// -------------------------------------------------------------------------

reg [WIDX:0] fdn;
always begin
	integer i;
	
	fdn = 0;
	for(i = FD_NUM-1; i >= 0; i = i - 1) if(!floppy_drive[i]) fdn = i[WIDX:0];
end

wire       fd_any         = ~&floppy_drive;
wire [1:0] sc_is_scp, sc_probing;

wire       fd_mfmt_img    = fd_any && fdn_present[fdn] && fdn_mfmt[fdn];
wire       fd_scp         = fd_any && fdn_present[fdn] && sc_is_scp[fdn];
wire       fd_mfmt        = fd_mfmt_img | fd_scp;
wire       fd_index       = fd_any ? (fd_mfmt ? !mf_index : fdn_index[fdn]) : 1'b0;
wire       fd_ready       = fd_any ? fdn_ready[fdn]       : 1'b0;
wire [6:0] fd_track       = fd_any ? fdn_track[fdn]       : 7'd0;
wire [4:0] fd_sector      = fd_any ? fdn_sector[fdn]      : 5'd0;
wire       fd_sector_hdr  = fd_any ? fdn_sector_hdr[fdn]  : 1'b0;
//wire     fd_sector_data = fd_any ? fdn_sector_data[fdn] : 1'b0;
wire       fd_dclk_en     = fd_any ? fdn_dclk[fdn]        : 1'b0;
wire       fd_present     = fd_any ? fdn_present[fdn] && !sc_probing[fdn] : 1'b0;

localparam integer GONE_CLKS = 6 * CLKCPU_KHZ;
reg [18:0] absent_cnt;
wire       fd_gone = absent_cnt == GONE_CLKS;
reg        was_scp0;
reg        sc_probingD0;
always @(posedge clkcpu) begin
	sc_probingD0 <= sc_probing[0];
	if (img_mounted[0] && |img_size && img_mfmt) was_scp0 <= 0;
	if (sc_probingD0 && !sc_probing[0]) was_scp0 <= sc_is_scp[0];
end
wire       fd_swap_wait = fdn == 0 && (fdn_was_mfmt[0] || was_scp0);
always @(posedge clkcpu) begin
	if (fd_present) absent_cnt <= 0;
	else if (!fd_gone) absent_cnt <= absent_cnt + 1'd1;
end
localparam integer WPC_CLKS = 200 * CLKCPU_KHZ;
reg        wpc_busy[FD_NUM];
reg [24:0] wpc_cnt[FD_NUM];
always @(posedge clkcpu) begin
	reg [W:0] mountedD;
	integer i;
	mountedD <= img_mounted;
	for(i = 0; i < FD_NUM; i = i+1'd1) begin
		if (~mountedD[i] && img_mounted[i]) begin
			wpc_busy[i] <= 1'b1;
			wpc_cnt[i] <= 0;
		end
		else if (wpc_busy[i]) begin
			if (wpc_cnt[i] == WPC_CLKS - 1) wpc_busy[i] <= 1'b0;
			wpc_cnt[i] <= wpc_cnt[i] + 1'd1;
		end
	end
end

wire       fd_wp_sense    = !fd_any || wpc_busy[fdn] || !fd_present || img_wp[fdn];
wire       fd_writeprot   = fd_any ? (img_wp[fdn] | fd_mfmt) : 1'b1;

wire       fd_doubleside  = fdn_doubleside[fdn];
wire [4:0] fd_spt         = fdn_spt[fdn];

assign floppy_ready = fd_ready && fd_present;

// -------------------------------------------------------------------------
// ----------------------- internal state machines -------------------------
// -------------------------------------------------------------------------

// --------------------------- Motor handling ------------------------------

// if motor is off and type 1 command with "spin up sequnce" bit 3 set
// is received then the command is executed after the motor has
// reached full speed for 5 rotations (800ms spin-up time + 5*200ms =
// 1.8sec) If the floppy is idle for 10 rotations (2 sec) then the
// motor is switched off again
localparam MOTOR_IDLE_COUNTER = 4'd10;
reg [3:0] motor_timeout_index /* verilator public */;
reg indexD;
reg busy /* verilator public */;
reg step_in, step_out;
reg [3:0] motor_spin_up_sequence /* verilator public */;

wire fd_motor = EXT_MOTOR ? floppy_motor : motor_on;

// consider spin up done either if the motor is not supposed to spin at all or
// if it's supposed to run and has left the spin up sequence
wire motor_spin_up_done = (!motor_on) || (motor_on && (motor_spin_up_sequence == 0));

// ---------------------------- step handling ------------------------------

localparam STEP_PULSE_LEN = 16'd1;
localparam STEP_PULSE_CLKS = STEP_PULSE_LEN * CLK_EN;
reg [15:0] step_pulse_cnt;

// the step rate is only valid for command type I
wire [15:0] step_rate_clk = 
           (cmd[1:0]==2'b00)               ? (16'd6 *CLK_EN-1'd1):   //  6ms
           (cmd[1:0]==2'b01)               ? (16'd12*CLK_EN-1'd1):   // 12ms
           (MODEL == 2 && cmd[1:0]==2'b10) ? (16'd2 *CLK_EN-1'd1):   //  2ms
           (cmd[1:0]==2'b10)               ? (16'd20*CLK_EN-1'd1):   // 20ms
           (MODEL == 2)                    ? (16'd3 *CLK_EN-1'd1):   //  3ms
                                             (16'd30*CLK_EN-1'd1);   // 30ms

reg [15:0] step_rate_cnt;
reg [23:0] delay_cnt;

assign floppy_step = step_in | step_out;

// flag indicating that a "step" is in progress
wire step_busy = (step_rate_cnt != 0);
wire delaying = (delay_cnt != 0);

wire fd_track0 = (fd_track == 0);

reg [7:0] step_to;
reg RNF;
reg [1:0] mf_phase;
reg sector_inc_strobe;
reg track_inc_strobe;
reg track_dec_strobe;
reg track_clear_strobe;

always @(posedge clkcpu) begin
	reg [1:0] seek_state;
	reg notready_wait;
	reg sector_not_found;
	reg irq_at_index;
	reg [1:0] data_transfer_state;

	sector_inc_strobe <= 1'b0;
	track_inc_strobe <= 1'b0;
	track_dec_strobe <= 1'b0;
	track_clear_strobe <= 1'b0;
	irq_set <= 1'b0;

	if(!floppy_reset) begin
		motor_on <= 1'b0;
		busy <= 1'b0;
		step_in <= 1'b0;
		step_out <= 1'b0;
		sd_card_read <= 0;
		sd_card_write <= 0;
		data_transfer_start <= 1'b0;
		seek_state <= 0;
		notready_wait <= 1'b0;
		sector_not_found <= 1'b0;
		irq_at_index <= 1'b0;
		data_transfer_state <= 2'b00;
		RNF <= 1'b0;
		mf_phase <= 0;
		mf_start <= 1'b0;
	end else if (clk8m_en) begin
		sd_card_read <= 0;
		sd_card_write <= 0;
		data_transfer_start <= 1'b0;

		// disable step signal after 1 msec
		if(step_pulse_cnt != 0) 
			step_pulse_cnt <= step_pulse_cnt - 16'd1;
		else begin
			step_in <= 1'b0;
			step_out <= 1'b0;
		end

		 // step rate timer
		if(step_rate_cnt != 0) 
			step_rate_cnt <= step_rate_cnt - 16'd1;

		// delay timer
		if(delay_cnt != 0) 
			delay_cnt <= delay_cnt - 1'd1;

		// just received a new command
		if(cmd_rx) begin
			busy <= 1'b1;
			notready_wait <= 1'b0;
			sector_not_found <= 1'b0;
			data_transfer_state <= 2'b00;
			mf_phase <= 0;
			mf_start <= 1'b0;

			if(cmd_type_1 || cmd_type_2 || cmd_type_3) begin
				RNF <= 1'b0;
				motor_on <= 1'b1;
				// 'h' flag '0' -> wait for spin up
				if (!motor_on && !cmd[3]) motor_spin_up_sequence <= 6;   // wait for 6 full rotations
			end

			// handle "forced interrupt"
			if(cmd_type_4) begin
				busy <= 1'b0;
				mf_start <= 1'b0;
				if(cmd[3]) irq_set <= 1'b1;
				if(cmd[3:2] == 2'b01) irq_at_index <= 1'b1;
				// From Hatari: Starting a Force Int command when idle should set the motor bit and clear the spinup bit (verified on STF)
				if (!busy) motor_on <= 1'b1;
			end
		end

		// execute command if motor is not supposed to be running or
		// wait for motor spinup to finish
		if(busy && motor_spin_up_done && !step_busy && !delaying) begin

			// ------------------------ TYPE I -------------------------
			if(cmd_type_1) begin
				if(!fd_present && !fd_swap_wait) begin
					if (fd_gone) begin
						RNF <= 1'b1;
						busy <= 1'b0;
						irq_set <= 1'b1; // emit irq when command done
					end
				end else
				// evaluate command
				case (seek_state)
				0: begin
					// restore
					if(cmd[7:4] == 4'b0000) begin
						if (fd_track0) begin
							track_clear_strobe <= 1'b1;
							seek_state <= 2;
						end else begin
							step_dir <= 1'b1;
							seek_state <= 1;
						end
					end

					// seek
					if(cmd[7:4] == 4'b0001) begin
						if (track == step_to) seek_state <= 2;
						else begin
							step_dir <= (step_to < track);
							seek_state <= 1;
						end
					end

					// step
					if(cmd[7:5] == 3'b001) seek_state <= 1;

					// step-in
					if(cmd[7:5] == 3'b010) begin
						step_dir <= 1'b0;
						seek_state <= 1;
					end

					// step-out
					if(cmd[7:5] == 3'b011) begin
						step_dir <= 1'b1;
						seek_state <= 1;
					end
				   end

				// do the step
				1: begin
					if (step_dir)
						step_in <= 1'b1;
					else
						step_out <= 1'b1;

					// update the track register if seek/restore or the update flag set
					if( (!cmd[6] && !cmd[5]) || ((cmd[6] || cmd[5]) && cmd[4]))
						if (step_dir)
							track_dec_strobe <= 1'b1;
						else
							track_inc_strobe <= 1'b1;

					step_pulse_cnt <= STEP_PULSE_CLKS - 1'd1;
					step_rate_cnt <= step_rate_clk;

					seek_state <= (!cmd[6] && !cmd[5]) ? 0 : 2; // loop for seek/restore
				   end

				// verify
				2: begin
					if (cmd[2]) begin
						delay_cnt <= 16'd3*CLK_EN; // TODO: implement verify, now just delay one more step
					end
					seek_state <= 3;
				   end

				// finish
				3: begin
					busy <= 1'b0;
					irq_set <= 1'b1; // emit irq when command done
					seek_state <= 0;
				   end
				endcase
			end // if (cmd_type_1)

			// ------------------------ TYPE II -------------------------
			if(cmd_type_2) begin
				if(!fd_present) begin
					if (fd_gone && !fd_swap_wait) begin
						RNF <= 1'b1;
						busy <= 1'b0;
						irq_set <= 1'b1; // emit irq when command done
					end
				end else if (sector_not_found) begin
					busy <= 1'b0;
					irq_set <= 1'b1; // emit irq when command done
					RNF <= 1'b1;
				end else if (cmd[2] && !notready_wait) begin
					// e flag: 15 ms settling delay
					delay_cnt <= 16'd15*CLK_EN;
					notready_wait <= 1'b1;
					// read sector
				end else if (fd_mfmt) begin
					if (cmd[7:5] == 3'b101) begin
						busy <= 1'b0;
						irq_set <= 1'b1;
					end
					else case (mf_phase)
						0: begin
							mf_op <= MF_OP_RSEC;
							mf_start <= 1'b1;
							mf_phase <= 1;
						end
						1: if (mf_done) begin
							mf_start <= 1'b0;
							if (cmd[4] && !mf_rnf && !mf_crc_err) begin
								sector_inc_strobe <= 1'b1;
								mf_phase <= 2;
							end else begin
								RNF <= mf_rnf;
								busy <= 1'b0;
								irq_set <= 1'b1;
								mf_phase <= 0;
							end
						end
						2: mf_phase <= 0;
						default: mf_phase <= 0;
					endcase
				end else begin
					if(cmd[7:5] == 3'b100) begin
						if ((sector - sector_base) >= fd_spt) begin
							// wait 5 rotations (1 sec) before setting RNF
							sector_not_found <= 1'b1;
							delay_cnt <= 24'd1000 * CLK_EN;
						end else if (sd_state == SD_IDLE) begin
							case (data_transfer_state)

							2'b00: if (fifo_cpuptr == 0) begin
								// SD Card phase
								sd_card_read <= 1;
								data_transfer_state <= 2'b01;
							end

							2'b01: begin
								// CPU phase
								// we are busy until the right sector header passes under 
								// the head and the sd-card controller indicates the sector
								// is in the fifo
								if(fd_ready && fd_sector_hdr && (fd_sector == sector)) data_transfer_start <= 1'b1;

								if(data_transfer_done) begin
									data_transfer_state <= 2'b00;
									if (cmd[4]) sector_inc_strobe <= 1'b1; // multiple sector transfer
									else begin
										busy <= 1'b0;
										irq_set <= 1'b1; // emit irq when command done
									end
								end
							end

							default :;
							endcase

						end
					end

					// write sector
					if(cmd[7:5] == 3'b101) begin
						if ((sector - sector_base) >= fd_spt) begin
							// wait 5 rotations (1 sec) before setting RNF
							sector_not_found <= 1'b1;
							delay_cnt <= 24'd1000 * CLK_EN;
						end else if (sd_state == SD_IDLE) begin
							case (data_transfer_state)
							2'b00: begin
								// pre-read phase
									if (sector_size_code < 2) sd_card_read <= 1;
									data_transfer_state <= 2'b10;
								end
							2'b10: begin
								// CPU phase
								if (fifo_cpuptr == 0 && fd_ready && fd_sector_hdr && (fd_sector == sector)) data_transfer_start <= 1'b1;
								if (data_transfer_done) begin
									sd_card_write <= 1;
									data_transfer_state <= 2'b11;
								end
							end

							2'b11: begin
								// SD Card phase
								data_transfer_state <= 2'b00;
								if (cmd[4]) sector_inc_strobe <= 1'b1; // multiple sector transfer
								else begin
									busy <= 1'b0;
									irq_set <= 1'b1; // emit irq when command done
								end
							end

							default: ;
							endcase

						end
					end
				end
			end

			// ------------------------ TYPE III -------------------------
			if(cmd_type_3) begin
				if(!fd_present) begin
					if (fd_gone && !fd_swap_wait) begin
						RNF <= 1'b1;
						busy <= 1'b0;
						irq_set <= 1'b1; // emit irq when command done
					end
				end else if (fd_mfmt) begin
					if (cmd[7:4] == 4'b1111) begin
						busy <= 1'b0;
						irq_set <= 1'b1;
					end
					else case (mf_phase)
						0: begin
							mf_op <= (cmd[7:4] == 4'b1100) ? MF_OP_RADDR : MF_OP_RTRK;
							mf_start <= 1'b1;
							mf_phase <= 1;
						end
						1: if (mf_done) begin
							mf_start <= 1'b0;
							RNF <= mf_rnf;
							busy <= 1'b0;
							irq_set <= 1'b1;
							mf_phase <= 0;
						end
						default: mf_phase <= 0;
					endcase
				end else begin
					// read track TODO: fake
					if(cmd[7:4] == 4'b1110) begin
						busy <= 1'b0;
						irq_set <= 1'b1; // emit irq when command done
					end

					// write track TODO: fake
					if(cmd[7:4] == 4'b1111) begin
						busy <= 1'b0;
						irq_set <= 1'b1; // emit irq when command done
					end

					// read address
					if(cmd[7:4] == 4'b1100) begin
						// we are busy until the next setor header passes under the head
						if(fd_ready && fd_sector_hdr)
							data_transfer_start <= 1'b1;

						if(data_transfer_done) begin
							busy <= 1'b0;
							irq_set <= 1'b1; // emit irq when command done
						end
					end
				end
			end
		end

		// stop motor if there was no command for 10 index pulses
		indexD <= fd_index;
		if(indexD && !fd_index) begin
			irq_at_index <= 1'b0;
			if (irq_at_index) irq_set <= 1'b1;

			// let motor timeout run once fdc is not busy anymore
			if(!busy && motor_spin_up_done) begin
				if(motor_timeout_index != 0)
					motor_timeout_index <= motor_timeout_index - 4'd1;
				else if(motor_on)
					motor_timeout_index <= MOTOR_IDLE_COUNTER;

				if(motor_timeout_index == 1)
					motor_on <= 1'b0;
			end

			if(motor_spin_up_sequence != 0)
				motor_spin_up_sequence <= motor_spin_up_sequence - 4'd1;
		end
		if(busy) motor_timeout_index <= 0;
	end
end

// floppy delivers data at a floppy generated rate (usually 250kbit/s), so the start and stop
// signals need to be passed forth and back from cpu clock domain to floppy data clock domain
reg data_transfer_start;
reg data_transfer_done;

wire        mf_sd_busy, mf_sd_rd, mf_cell_stb, mf_cell, mf_index, mf_loaded;
wire [31:0] mf_lba;
wire  [5:0] mf_blk_cnt;
wire        mt_sd_busy, mt_cell_stb, mt_cell, mt_index, mt_loaded;
wire [16:0] mt_position;
wire        sc_sd_busy, sc_sd_rd, sc_sd_drive, sc_cell_stb, sc_cell, sc_index, sc_loaded;
wire [31:0] sc_lba;
wire  [5:0] sc_blk_cnt;
wire [16:0] sc_position;

wire [16:0] mf_position;

reg  [W:0] mf_mountedD;
always @(posedge clkcpu) mf_mountedD <= img_mounted;
wire mf_invalidate = |(img_mounted & ~mf_mountedD);

mfmt_track #(
	.ACC_STEP(16000000 / CLKCPU_KHZ),
	.INDEX_CLKS(4 * CLKCPU_KHZ)
) mfmt_drive (
	.clk            ( clkcpu         ),
	.reset          ( !floppy_reset  ),
	.enable         ( fd_mfmt_img && sd_state == SD_IDLE ),
	.cyl            ( fd_track       ),
	.head           ( !floppy_side   ),
	.drive          ( fdn[0]         ),
	.invalidate     ( mf_invalidate  ),
	.sd_lba         ( mf_lba         ),
	.sd_rd          ( mf_sd_rd       ),
	.sd_blk_cnt     ( mf_blk_cnt     ),
	.sd_ack         ( sd_ack         ),
	.sd_buff_addr   ( sd_buff_addr   ),
	.sd_dout        ( sd_dout        ),
	.sd_dout_strobe ( sd_dout_strobe ),
	.busy           ( mt_sd_busy     ),
	.cell_stb       ( mt_cell_stb    ),
	.cell_bit       ( mt_cell        ),
	.index          ( mt_index       ),
	.loaded         ( mt_loaded      ),
	.position       ( mt_position    )
);

reg  [1:0] sc_mount_ok;
always @(*) for (int i = 0; i < 2; i++) sc_mount_ok[i] = (i < FD_NUM) && |img_size && !img_mfmt;

scp_track #(
	.ACC(16000000 / (CLKCPU_KHZ * 25)),
	.INDEX_CLKS(4 * CLKCPU_KHZ),
	.SETTLE_CLKS(10 * CLKCPU_KHZ)
) scp_drive (
	.clk            ( clkcpu         ),
	.reset          ( !floppy_reset  ),
	.enable         ( fd_scp && sd_state == SD_IDLE ),
	.sd_free        ( sd_state == SD_IDLE && !mt_sd_busy && !(|sd_rd_sec) ),
	.cyl            ( fd_track       ),
	.head           ( !floppy_side   ),
	.drive          ( fdn[0]         ),
	.mount          ( 2'(img_mounted & ~mf_mountedD) ),
	.mount_ok       ( sc_mount_ok    ),
	.pll_reset      ( cmd_rx         ),
	.is_scp         ( sc_is_scp      ),
	.probing        ( sc_probing     ),
	.sd_lba         ( sc_lba         ),
	.sd_rd          ( sc_sd_rd       ),
	.sd_blk_cnt     ( sc_blk_cnt     ),
	.sd_drive       ( sc_sd_drive    ),
	.sd_ack         ( sd_ack         ),
	.sd_buff_addr   ( sd_buff_addr   ),
	.sd_dout        ( sd_dout        ),
	.sd_dout_strobe ( sd_dout_strobe ),
	.busy           ( sc_sd_busy     ),
	.cell_stb       ( sc_cell_stb    ),
	.cell_bit       ( sc_cell        ),
	.index          ( sc_index       ),
	.loaded         ( sc_loaded      ),
	.position       ( sc_position    )
);

assign mf_sd_busy  = mt_sd_busy | sc_sd_busy;
assign mf_cell_stb = fd_scp ? sc_cell_stb : mt_cell_stb;
assign mf_cell     = fd_scp ? sc_cell     : mt_cell;
assign mf_index    = fd_scp ? sc_index    : mt_index;
assign mf_loaded   = fd_scp ? sc_loaded   : mt_loaded;
assign mf_position = fd_scp ? sc_position : mt_position;

localparam MF_OP_RSEC  = 2'd0;
localparam MF_OP_RADDR = 2'd1;
localparam MF_OP_RTRK  = 2'd2;

localparam ME_IDLE = 3'd0, ME_ID = 3'd1, ME_IDF = 3'd2, ME_DAM = 3'd3,
           ME_DATA = 3'd4, ME_TWAIT = 3'd5, ME_TRK = 3'd6, ME_DONE = 3'd7;
reg  [2:0] mf_estate;

reg        mf_dec_restart;
reg  [1:0] mf_dec_mode;
wire       mf_dec_stb, mf_dec_sync, mf_dec_c2;
wire [7:0] mf_dec_val;

wire mf_trk_start = (mf_estate == ME_TWAIT) && mf_cell_stb && mf_position == 0 && mf_loaded;

mfm_dec mfm_decoder (
	.clk       ( clkcpu         ),
	.restart   ( mf_dec_restart | mf_trk_start ),
	.mode      ( mf_trk_start ? 2'd2 : mf_dec_mode ),
	.cell_stb  ( mf_cell_stb    ),
	.cell_bit  ( mf_cell        ),
	.byte_stb  ( mf_dec_stb     ),
	.byte_val  ( mf_dec_val     ),
	.byte_sync ( mf_dec_sync    ),
	.byte_c2   ( mf_dec_c2      )
);

reg        mf_start;
reg  [1:0] mf_op;
reg        mf_done;
reg        mf_rnf, mf_crc_err, mf_deleted;
reg        mf_byte_stb;
reg  [7:0] mf_byte;
reg        mf_ra_stb;
reg  [7:0] mf_ra_track;

always @(posedge clkcpu) begin
	reg        startD, indexD;
	reg  [1:0] syncs;
	reg  [2:0] n;
	reg [10:0] cnt;
	reg  [9:0] budget;
	reg  [2:0] revs;
	reg [15:0] crcv;
	reg  [7:0] id_trk, id_sec;
	reg  [1:0] id_size;
	reg        index_rise;

	mf_dec_restart <= 0;
	mf_byte_stb <= 0;
	mf_ra_stb <= 0;
	startD <= mf_start;
	indexD <= mf_index;
	index_rise = mf_index && !indexD;

	if (!floppy_reset || cmd_rx || !mf_start) begin
		mf_estate <= ME_IDLE;
		mf_done <= 0;
		mf_dec_mode <= 2'd0;
	end
	else case (mf_estate)
	ME_IDLE:
		if (!startD) begin
			mf_rnf <= 0;
			mf_crc_err <= 0;
			mf_deleted <= 0;
			mf_done <= 0;
			revs <= 0;
			syncs <= 0;
			mf_dec_mode <= 2'd0;
			mf_dec_restart <= 1;
			mf_estate <= (mf_op == MF_OP_RTRK) ? ME_TWAIT : ME_ID;
		end

	ME_ID: begin
		if (index_rise && mf_loaded) begin
			revs <= revs + 1'd1;
			if (revs + 1'd1 == ((mf_op == MF_OP_RADDR) ? 3'd6 : 3'd5)) begin
				mf_rnf <= 1;
				mf_estate <= ME_DONE;
			end
		end
		if (mf_dec_stb) begin
			if (mf_dec_sync) begin
				if (syncs != 3) syncs <= syncs + 1'd1;
			end
			else begin
				if (syncs == 3 && mf_dec_val == 8'hFE) begin
					crcv <= crc(16'hCDB4, 8'hFE);
					n <= 0;
					mf_dec_mode <= 2'd1;
					mf_estate <= ME_IDF;
				end
				syncs <= 0;
			end
		end
	end

	ME_IDF:
		if (mf_dec_stb) begin
			crcv <= crc(crcv, mf_dec_val);
			n <= n + 1'd1;
			case (n)
				0: id_trk <= mf_dec_val;
				2: id_sec <= mf_dec_val;
				3: id_size <= mf_dec_val[1:0];
				default: ;
			endcase
			if (mf_op == MF_OP_RADDR) begin
				mf_byte <= mf_dec_val;
				mf_byte_stb <= 1;
			end
			if (n == 5) begin
				mf_dec_mode <= 2'd0;
				syncs <= 0;
				if (mf_op == MF_OP_RADDR) begin
					mf_crc_err <= crc(crcv, mf_dec_val) != 0;
					mf_ra_track <= id_trk;
					mf_ra_stb <= 1;
					mf_estate <= ME_DONE;
				end
				else if (crc(crcv, mf_dec_val) != 0) begin
					if (id_trk == track && id_sec == sector) mf_crc_err <= 1;
					mf_estate <= ME_ID;
				end
				else if (id_trk == track && id_sec == sector) begin
					mf_crc_err <= 0;
					budget <= 10'd688;
					mf_estate <= ME_DAM;
				end
				else mf_estate <= ME_ID;
			end
		end

	ME_DAM: begin
		if (mf_cell_stb) begin
			if (budget == 0) begin
				syncs <= 0;
				mf_estate <= ME_ID;
			end
			else budget <= budget - 1'd1;
		end
		if (mf_dec_stb) begin
			if (mf_dec_sync) begin
				if (syncs != 3) syncs <= syncs + 1'd1;
			end
			else begin
				if (syncs == 3 && mf_dec_val[7:2] == 6'b111110) begin
					mf_deleted <= !mf_dec_val[1];
					crcv <= crc(16'hCDB4, mf_dec_val);
					cnt <= 11'd128 << id_size;
					n <= 0;
					mf_dec_mode <= 2'd1;
					mf_estate <= ME_DATA;
				end
				syncs <= 0;
			end
		end
	end

	ME_DATA:
		if (mf_dec_stb) begin
			crcv <= crc(crcv, mf_dec_val);
			if (cnt != 0) begin
				cnt <= cnt - 1'd1;
				mf_byte <= mf_dec_val;
				mf_byte_stb <= 1;
			end
			else begin
				n <= n + 1'd1;
				if (n == 1) begin
					mf_crc_err <= crc(crcv, mf_dec_val) != 0;
					mf_dec_mode <= 2'd0;
					mf_estate <= ME_DONE;
				end
			end
		end

	ME_TWAIT:
		if (mf_trk_start) begin
			mf_dec_mode <= 2'd2;
			mf_estate <= ME_TRK;
		end
	ME_TRK:
		if (mf_cell_stb && mf_position == 0) begin
			mf_dec_mode <= 2'd0;
			mf_estate <= ME_DONE;
		end
		else if (mf_dec_stb) begin
			mf_byte <= mf_dec_val;
			mf_byte_stb <= 1;
		end

	ME_DONE: mf_done <= 1;
	endcase
end

// ==================================== FIFO ==================================

// 0.5/1 kB buffer used to receive a sector as fast as possible from from the io
// controller. The internal transfer afterwards then runs at 250000 Bit/s
reg  [10:0] fifo_cpuptr;
reg  [9:0] fifo_cpuptr_adj;
wire [7:0] fifo_q;
reg        s_odd; //odd sector
reg  [9:0] fifo_sdptr;

always @(*) begin
	if (sector_size_code == 3)
		fifo_sdptr = { s_odd, sd_buff_addr[7:0] };
	else
		fifo_sdptr = { 1'b0, sd_buff_addr[7:0] };

	if (sector_size_code == 1)
		fifo_cpuptr_adj = { 1'b0, (fd_spt[0] & (track[0] ^ !floppy_side)) ^ sector[0], fifo_cpuptr[7:0] };
	else
		fifo_cpuptr_adj = fifo_cpuptr[9:0];
end

fdc1772_dpram #(10) fifo
(
	.clock(clkcpu),

	.address_a(fifo_sdptr),
	.data_a(sd_dout),
	.wren_a(sd_dout_strobe & sd_ack & ~mf_sd_busy),
	.q_a(sd_din),

	.address_b(fifo_cpuptr_adj),
	.data_b(data_in),
	.wren_b(data_in_strobe),
	.q_b(fifo_q)
);

// ------------------ SD card control ------------------------
localparam SD_IDLE = 0;
localparam SD_READ = 1;
localparam SD_WRITE = 2;

reg [1:0] sd_state;
reg       sd_card_write;
reg       sd_card_read;
reg [W:0] sd_rd_sec;

reg [WIDX:0] mf_rd_fdn;
always @(posedge clkcpu) if (!mt_sd_busy) mf_rd_fdn <= fdn;
assign sd_lba     = sc_sd_busy ? sc_lba : mt_sd_busy ? mf_lba : sd_lba_sec;
assign sd_rd      = sd_rd_sec | (mf_sd_rd ? ((W+1)'(1) << mf_rd_fdn) : '0)
                              | (sc_sd_rd ? ((W+1)'(1) << sc_sd_drive) : '0);
assign sd_blk_cnt = sc_sd_busy ? sc_blk_cnt : mt_sd_busy ? mf_blk_cnt : 6'd0;

always @(posedge clkcpu) begin
	reg sd_ackD;
	reg sd_card_readD;
	reg sd_card_writeD;

	sd_card_readD <= sd_card_read;
	sd_card_writeD <= sd_card_write;
	sd_ackD <= sd_ack;
	if (sd_ack) {sd_rd_sec, sd_wr} <= 0;

	case (sd_state)
	SD_IDLE:
	begin
		s_odd <= 1'b0;
		if (~sd_card_readD & sd_card_read) begin
			sd_rd_sec[fdn] <= 1;
			sd_state <= SD_READ;
		end
		else if (~sd_card_writeD & sd_card_write) begin
			sd_wr[fdn] <= 1;
			sd_state <= SD_WRITE;
		end
	end

	SD_READ:
	if (sd_ackD & ~sd_ack) begin
		if (s_odd || sector_size_code != 3) begin
			sd_state <= SD_IDLE;
		end else begin
			s_odd <= 1;
			sd_rd_sec[fdn] <= 1;
		end
	end

	SD_WRITE:
	if (sd_ackD & ~sd_ack) begin
		if (s_odd || sector_size_code != 3) begin
			sd_state <= SD_IDLE;
		end else begin
			s_odd <= 1;
			sd_wr[fdn] <= 1;
		end
	end

	default: ;
	endcase
end

// -------------------- CPU data read/write -----------------------
reg data_in_strobe;
reg data_in_valid;

function [15:0] crc;
	input [15:0] curcrc;
	input  [7:0] val;
	reg    [3:0] i;
	begin
		crc = {curcrc[15:8] ^ val, 8'h00};
		for (i = 0; i < 8; i=i+1'd1) begin
			if(crc[15]) begin
				crc = crc << 1;
				crc = crc ^ 16'h1021;
			end
			else crc = crc << 1;
		end
		crc = {curcrc[7:0] ^ crc[15:8], crc[7:0]};
	end
endfunction

always @(posedge clkcpu) begin
	reg        data_transfer_startD;
	reg [10:0] data_transfer_cnt;
	reg [15:0] crcval;
	reg        crc_en;

	crc_en <= 0;
	if(crc_en) crcval <= crc(crcval, data_out);

	if (cpu_we && cpu_addr == FDC_REG_DATA) begin
		data_out <= data_in;
		data_in_valid <= 1;
	end

	// reset fifo read pointer on reception of a new command or 
	// when multi-sector transfer increments the sector number
	if(cmd_rx || sector_inc_strobe) begin
		data_in_valid <= 0;
		data_transfer_cnt <= 0;
		fifo_cpuptr <= 0;
	end

	drq_set <= 1'b0;
	if (clk8m_en) data_transfer_done <= 0;
	data_transfer_startD <= data_transfer_start;
	// received request to read data
	if(~data_transfer_startD & data_transfer_start) begin

		// read_address command has 6 data bytes
		if(cmd[7:4] == 4'b1100) begin
			crcval <= 16'hB230;
			data_transfer_cnt <= 11'd6+11'd1;
		end

		// read/write sector has SECTOR_SIZE data bytes
		if(cmd[7:6] == 2'b10)
			data_transfer_cnt <= sector_size + 1'd1;

		// write sector asserts drq earlier to fill up the data register in time
		if(cmd[7:5] == 3'b101) drq_set <= !data_in_valid;
	end

	if (cmd_rx) data_lost <= 1'b0;
	if (mf_byte_stb) begin
		data_out <= mf_byte;
		if (drq) data_lost <= 1'b1;
		drq_set <= 1'b1;
	end

	// advance fifo pointer when the write sector data consumed
	data_in_strobe <= 1'b0;
	if(cmd[7:5] == 3'b101 && data_in_strobe) fifo_cpuptr <= fifo_cpuptr + 1'd1;

	if(fd_dclk_en) begin
		if(data_transfer_cnt != 0) begin
			if(data_transfer_cnt != 1) begin
				data_lost <= 1'b0;
				if (drq) data_lost <= 1'b1;
				// raise drq, except when the last byte is already taken from the CPU for write
				if (cmd[7:5] != 3'b101 || data_transfer_cnt != 2) drq_set <= 1'b1;

				// read_address
				if(cmd[7:4] == 4'b1100) begin
					case(data_transfer_cnt)
						7: begin data_out <= fd_track; crc_en <= 1; end
						6: begin data_out <= { 7'b0000000, (INVERT_HEAD_RA != 0) ^ floppy_side }; crc_en <= 1; end
						5: begin data_out <= fd_sector; crc_en <= 1; end
						4: begin data_out <= sector_size_code[1:0]; crc_en <= 1; end // TODO: sec size 0=128, 1=256, 2=512, 3=1024
						3: data_out <= crcval[15:8];
						2: data_out <= crcval[7:0];
					endcase // case (data_read_cnt)
				end

				// read sector
				if(cmd[7:5] == 3'b100 && fifo_cpuptr != sector_size) begin
					data_out <= fifo_q;
					fifo_cpuptr <= fifo_cpuptr + 1'd1;
				end
				// write sector
				if(cmd[7:5] == 3'b101 && fifo_cpuptr != sector_size) begin
					data_in_strobe <= 1;
					data_in_valid <= 0;
				end

			end

			// count down and stop after last byte
			data_transfer_cnt <= data_transfer_cnt - 11'd1;
			if(data_transfer_cnt == 1)
				data_transfer_done <= 1'b1;
		end
	end
end

// the status byte
wire [7:0] status = { (MODEL == 1 || MODEL == 3) ? !floppy_ready : motor_on,
		      ((cmd[7:5] == 3'b101 || cmd[7:4] == 4'b1111) && fd_writeprot) || (cmd_type_1 && fd_wp_sense), // wrprot
		      cmd_type_1?motor_spin_up_done:(fd_mfmt && cmd_type_2 && mf_deleted), // data mark
		      RNF,                                 // seek error/record not found
		      !cmd_type_1 && fd_mfmt && mf_crc_err,  // crc error
		      cmd_type_1?fd_track0:data_lost,      // track0/data lost
		      cmd_type_1?~fd_index:drq,            // index mark/drq
		      busy } /* synthesis keep */;

reg [7:0] track /* verilator public */;
reg [7:0] sector;
reg [7:0] data_in;
reg [7:0] data_out;

reg step_dir;
reg motor_on /* verilator public */ = 1'b0;
reg data_lost;

// ---------------------------- command register -----------------------   
reg [7:0] cmd /* verilator public */;
wire cmd_type_1 = (cmd[7] == 1'b0);
wire cmd_type_2 = (cmd[7:6] == 2'b10);
wire cmd_type_3 = (cmd[7:5] == 3'b111) || (cmd[7:4] == 4'b1100);
wire cmd_type_4 = (cmd[7:4] == 4'b1101);

localparam FDC_REG_CMDSTATUS    = 0;
localparam FDC_REG_TRACK        = 1;
localparam FDC_REG_SECTOR       = 2;
localparam FDC_REG_DATA         = 3;

// CPU register read
always @(*) begin
	cpu_dout = 8'h00;

	if(cpu_sel && cpu_rw) begin
		case(cpu_addr)
			FDC_REG_CMDSTATUS: cpu_dout = status;
			FDC_REG_TRACK:     cpu_dout = track;
			FDC_REG_SECTOR:    cpu_dout = sector;
			FDC_REG_DATA:      cpu_dout = data_out;
		endcase
	end
end

// cpu register write
reg cmd_rx /* verilator public */;
reg cmd_rx_i;

always @(posedge clkcpu) begin
	if(!floppy_reset) begin
		// clear internal registers
		cmd <= 8'h00;
		track <= 8'h00;
		sector <= 8'h00;

		// reset state machines and counters
		cmd_rx_i <= 1'b0;
		cmd_rx <= 1'b0;
	end else begin

		// cmd_rx is delayed to make sure all signals (the cmd!) are stable when
		// cmd_rx is evaluated
		cmd_rx <= cmd_rx_i;

		// command reception is ack'd by fdc going busy
		if((!cmd_type_4 && busy) || (clk8m_en && cmd_type_4 && !busy)) cmd_rx_i <= 1'b0;

		// only react if stb just raised
		if(cpu_we) begin
			if(cpu_addr == FDC_REG_CMDSTATUS && (!busy || cpu_din[7:4] == 4'b1101)) begin       // command register
				cmd <= cpu_din;
				cmd_rx_i <= 1'b1;
				// ------------- TYPE I commands -------------
				if(cpu_din[7:4] == 4'b0000) begin               // RESTORE
					step_to <= 8'd0;
					track <= 8'hff;
				end

				if(cpu_din[7:4] == 4'b0001) begin               // SEEK
					step_to <= data_in;
				end

				if(cpu_din[7:5] == 3'b001) begin                // STEP
				end

				if(cpu_din[7:5] == 3'b010) begin                // STEP-IN
				end

				if(cpu_din[7:5] == 3'b011) begin                // STEP-OUT
				end

				// ------------- TYPE II commands -------------
				if(cpu_din[7:5] == 3'b100) begin                // read sector
				end

				if(cpu_din[7:5] == 3'b101) begin                // write sector
				end

				// ------------- TYPE III commands ------------
				if(cpu_din[7:4] == 4'b1100) begin               // read address
				end

				if(cpu_din[7:4] == 4'b1110) begin               // read track
				end

				if(cpu_din[7:4] == 4'b1111) begin               // write track
				end

				// ------------- TYPE IV commands -------------
				if(cpu_din[7:4] == 4'b1101) begin               // force intrerupt
				end
			end

			if(cpu_addr == FDC_REG_TRACK)                    // track register
				track <= cpu_din;

			if(cpu_addr == FDC_REG_SECTOR)                   // sector register
				sector <= cpu_din;

			if(cpu_addr == FDC_REG_DATA) begin               // data register
				data_in <= cpu_din;
			end
		end

		if (sector_inc_strobe) sector <= sector + 1'd1;
		if (mf_ra_stb) sector <= mf_ra_track;
		if (track_inc_strobe) track <= track + 1'd1;
		if (track_dec_strobe) track <= track - 1'd1;
		if (track_clear_strobe) track <= 8'd0;
	end
end

reg busy_drqD;
always @(posedge clkcpu) begin
	busy_drqD <= busy;
	drq_drop <= (cmd_rx && !(cmd_type_4 && busy)) || (busy_drqD && !busy && data_lost);
end

endmodule

module fdc1772_dpram #(ADDRWIDTH=9)
(
	input                 clock,

	input [ADDRWIDTH-2:0] address_a,
	input          [15:0] data_a, 
	input                 wren_a,
	output     reg [15:0] q_a,

	input [ADDRWIDTH-1:0] address_b,
	input           [7:0] data_b, 
	input                 wren_b,
	output     reg  [7:0] q_b
);

logic [1:0][7:0] ram[0:(1<<(ADDRWIDTH-1))-1];

always@(posedge clock) begin
	if(wren_a) begin
		ram[address_a] <= data_a;
		q_a <= data_a;
	end
	else begin
		q_a <= ram[address_a];
	end
end

always@(posedge clock) begin
	if(wren_b) begin
		ram[address_b[ADDRWIDTH-1:1]][address_b[0]] <= data_b;
		q_b <= data_b;
	end
	else begin
		q_b <= ram[address_b[ADDRWIDTH-1:1]][address_b[0]];
	end
end

endmodule
