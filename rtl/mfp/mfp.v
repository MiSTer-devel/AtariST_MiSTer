// mfp.v
//
// Atari ST multi function peripheral (MFP) for the MiST board
// http://code.google.com/p/mist-board/
//
// Copyright (c) 2014 Till Harbaum <till@harbaum.org>
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

module mfp (
	// cpu register interface
	input            clk,
	input            clk_en,
	input            reset,
	input      [7:0] din,
	input            sel,
	input      [4:0] addr,
	input            ds,
	input            rw,
	output reg [7:0] dout,
	output reg       irq,
	input            iack,
	output           dtack,
	
	input            si,
	output           so,

	// inputs
	input      [1:0] t_i,  // timer input
	input      [7:0] i     // input port
);

// ---------------- mfp uart ------------

reg [3:0] cen;
always @(posedge clk) cen <= {cen[2:0],clk_en};

wire [7:0] uart_dout;

wire int_rx_e,int_rx, int_tx_e, int_tx;
USART_TOP usart
(
	.CLK(clk),
	.CEP(clk_en),
	.CEN(cen[3]),
	.RESETn(~reset),

	.DSn(ds),
	.CSn(~sel),
	.RWn(rw),

	.RS(addr),
	.DATA_IN(din),
	.DATA_OUT(uart_dout),

	.RC(tdo),
	.TC(tdo),
	.SI(si),
	.SO(so),

	.RX_ERR_INT(int_rx_e),
	.RX_BUFF_INT(int_rx),
	.TX_ERR_INT(int_tx_e),
	.TX_BUFF_INT(int_tx)
);

/////////////////////////////////////////////////////////////////////////////////

wire bus_sel = sel & ~ds;
reg  bus_selD;
reg  bus_dtack;
wire write = clk_en & ~bus_selD & bus_sel & ~rw;

always @(posedge clk) begin
	if (clk_en) begin
		bus_selD <= bus_sel;
		if (bus_selD & bus_sel) bus_dtack <= 1'b1;
		if (~bus_sel) bus_dtack <= 1'b0;
	end
end

reg iack_dtack;
reg iack_sel;
reg iack_ack;
always @(posedge clk) begin
	iack_sel <= 1'b0;
	if (clk_en) begin
		if (iack && !iack_ack && highest_irq_pending_mask != 16'h0000) iack_sel <= 1'b1;
		if (iack_ack) iack_dtack <= 1'b1;
		if (~iack) iack_dtack <= 1'b0;
	end
end

assign dtack = bus_dtack || iack_dtack;

// timer a/b is in pulse mode
wire [1:0] pulse_mode;
// timer a/b is in event mode
wire [1:0] event_mode;
   
wire timera_done;
wire [7:0] timera_dat_o;
wire [3:0] timera_ctrl_o;

mfp_timer timer_a (
	.CLK        ( clk                      ),
	.DS         ( ds                       ),
	.RST        ( reset                    ),
	.CTRL_I     ( din[4:0]                 ),
	.CTRL_O     ( timera_ctrl_o            ),
	.CTRL_WE    ( (addr == 5'h0c) && write ),
	.DAT_I      ( din                      ),
	.DAT_O      ( timera_dat_o             ),
	.DAT_WE     ( (addr == 5'h0f) && write ),
	.PULSE_MODE ( pulse_mode[1]            ),
	.EVENT_MODE ( event_mode[1]            ),
	.T_I        ( t_i[0] ^ ~aer[4]         ),
	.T_O_PULSE  ( timera_done              )
);

wire timerb_done;
wire [7:0] timerb_dat_o;
wire [3:0] timerb_ctrl_o;

mfp_timer timer_b (
	.CLK        ( clk                      ),
	.DS         ( ds                       ),
	.RST        ( reset                    ),
	.CTRL_I     ( din[4:0]                 ),
	.CTRL_O     ( timerb_ctrl_o            ),
	.CTRL_WE    ( (addr == 5'h0d) && write ),
	.DAT_I      ( din                      ),
	.DAT_O      ( timerb_dat_o             ),
	.DAT_WE     ( (addr == 5'h10) && write ),
	.PULSE_MODE ( pulse_mode[0]            ),
	.EVENT_MODE ( event_mode[0]            ),
	.T_I        ( t_i[1] ^ ~aer[3]         ),
	.T_O_PULSE  ( timerb_done              )
);

wire timerc_done;
wire [7:0] timerc_dat_o;
wire [3:0] timerc_ctrl_o;

mfp_timer timer_c (
	.CLK        ( clk                      ),
	.DS         ( ds                       ),
	.RST        ( reset                    ),
	.CTRL_I     ( {2'b00, din[6:4]}        ),
	.CTRL_O     ( timerc_ctrl_o            ),
	.CTRL_WE    ( (addr == 5'h0e) && write ),
	.DAT_I      ( din                      ),
	.DAT_O      ( timerc_dat_o             ),
	.DAT_WE     ( (addr == 5'h11) && write ),
	.T_O_PULSE  ( timerc_done              )
);

wire timerd_done;
wire [7:0] timerd_dat_o;
wire [3:0] timerd_ctrl_o;
wire       tdo;

mfp_timer timer_d (
	.CLK        ( clk                      ),
	.DS         ( ds                       ),
	.RST        ( reset                    ),
	.CTRL_I     ( {2'b00, din[2:0]}        ),
	.CTRL_O     ( timerd_ctrl_o            ),
	.CTRL_WE    ( (addr == 5'h0e) && write ),
	.DAT_I      ( din                      ),
	.DAT_O      ( timerd_dat_o             ),
	.DAT_WE     ( (addr == 5'h12) && write ),
	.T_O_PULSE  ( timerd_done              ),
	.T_O        ( tdo                      )
);

reg [7:0] aer, ddr, gpip;

// the mfp can handle 16 irqs, 8 internal and 8 external
reg [15:0] imr, ier;   // interrupt registers
reg [7:0] vr;

// generate irq signal if an irq is pending and no other irq of same or higher prio is in service
wire irq_trigger = ((ipr & imr) != 16'h0000) && (highest_irq_pending > irq_in_service);

// Delay to Falling XINTR from External Input Active Transition: max 380ns
// Let's try with one clock enable cycle (250ns on ST)
always @(posedge clk) if (clk_en) irq <= irq_trigger;

// check number of current interrupt in service
wire [3:0] irq_in_service;
mfp_hbit16 irq_in_service_index (
	.value  ( isr            ),
	.index  ( irq_in_service )
);

// check the number of the highest pending irq 
wire  [3:0] highest_irq_pending;
wire [15:0] highest_irq_pending_mask;
mfp_hbit16 irq_pending_index (
	.value  ( ipr & imr                 ),
	.index  ( highest_irq_pending       ),
	.mask   ( highest_irq_pending_mask  )
);

// gpip as output to the cpu (ddr bit == 1 -> gpip pin is output)
wire [7:0] gpip_cpu_out = (i & ~ddr) | (gpip & ddr);

// cpu read interface
always @(*) begin

	dout = 8'd0;
	if(bus_sel && rw) begin
		if(addr == 5'h00) dout = gpip_cpu_out;
		if(addr == 5'h01) dout = aer;
		if(addr == 5'h02) dout = ddr;

		if(addr == 5'h03) dout = ier[15:8];
		if(addr == 5'h04) dout = ier[7:0];
		if(addr == 5'h06) dout = ipr[7:0];
		if(addr == 5'h05) dout = ipr[15:8];
		if(addr == 5'h07) dout = isr[15:8];
		if(addr == 5'h08) dout = isr[7:0];
		if(addr == 5'h09) dout = imr[15:8];
		if(addr == 5'h0a) dout = imr[7:0];
		if(addr == 5'h0b) dout = vr;

		// timers
		if(addr == 5'h0c) dout = { 4'h0, timera_ctrl_o};
		if(addr == 5'h0d) dout = { 4'h0, timerb_ctrl_o};
		if(addr == 5'h0e) dout = { timerc_ctrl_o, timerd_ctrl_o};
		if(addr == 5'h0f) dout = timera_dat_o;
		if(addr == 5'h10) dout = timerb_dat_o;
		if(addr == 5'h11) dout = timerc_dat_o;
		if(addr == 5'h12) dout = timerd_dat_o;

		// uart
		if(addr >= 5'h13 && addr <= 5'h17) dout = uart_dout; 

	end else if(iack) begin
		dout = irq_vec;
	end
end

// mask of input irqs which are overwritten by timer a/b inputs
// In normal operation, programming the active edge bit to a one will produce an interrupt on the zero-
// to-one transition of the associated input signal. Alternately, programming the edge bit to a zero will
// produce an interrupt on the one-to-zero transition of the input signal.
// However, in the pulse width measurement mode, the interrupt generated by a transition on TAI or TBI will occur
// on the opposite transition as that normally defined by the edge bit.
// Like the pulse width measurement mode, the event count mode requires an auxiliary input signal, TAI or TBI.
// General purpose lines I3 and I4 can be used for I/O or as interrupt producing inputs.

wire [7:0] ti_irq_mask = { 3'b000, pulse_mode, 3'b000};
wire [7:0] ti_irq      = { 3'b000, pulse_mode[1] ^ t_i[0], pulse_mode[0] ^ t_i[1], 3'b000};

// latch to keep irq vector stable during irq ack cycle
reg [7:0] irq_vec;

// IPR bits are always set on the rising edge of their input and are cleared asynchronously
wire [7:0] gpio_irq = ~aer ^ ((i & ~ti_irq_mask) | (ti_irq & ti_irq_mask));

// ------------------------ IPR register --------------------------
wire [15:0] ipr;
reg [15:0] ipr_reset;

// map the 16 interrupt sources onto the 16 interrupt register bits
wire [15:0] ipr_set = {
	gpio_irq[7:6], timera_done, int_rx,
	int_rx_e, int_tx, int_tx_e, timerb_done,
	gpio_irq[5:4], timerc_done, timerd_done, gpio_irq[3:0]
};

mfp_srff16 ipr_latch (
	.clk    ( clk        ),
	.set    ( ipr_set    ),
	.mask   ( ier        ),
	.reset  ( ipr_reset  ),
	.out    ( ipr        )
);

// ------------------------ ISR register --------------------------
wire [15:0] isr;
reg [15:0] isr_reset;
reg [15:0] isr_set;

// move highest pending irq into isr when s bit set and iack raises
mfp_srff16 isr_latch (
	.clk    ( clk        ),
	.set    ( isr_set    ),
	.mask   ( 16'hffff   ),
	.reset  ( isr_reset  ),
	.out    ( isr        )
);

always @(posedge clk) begin
	ipr_reset <= 0;
	isr_reset <= 0;
	isr_set <= 0;

	if(reset) begin
		ipr_reset <= 16'hffff;
		isr_reset <= 16'hffff;
		ier <= 16'h0000; 
		imr <= 16'h0000;
		isr_set <= 16'h0000;
		iack_ack <= 1'b0;
	end else begin 
		// remove active bit from ipr and set it in isr
		if(iack_sel) begin
			ipr_reset[highest_irq_pending] <= 1'b1;
			isr_set <= vr[3]?highest_irq_pending_mask:16'h0000;    // non auto-end
			isr_reset <= !vr[3]?highest_irq_pending_mask:16'h0000; // auto-end
			irq_vec <= { vr[7:4], highest_irq_pending };
			iack_ack <= 1'b1;
		end
		if (~iack) iack_ack <= 1'b0;

		if(write) begin
			// -------- GPIO ---------
			if(addr == 5'h00) gpip <= din;
			if(addr == 5'h01) aer <= din;
			if(addr == 5'h02) ddr <= din;

			// ------ IRQ handling -------
			if(addr == 5'h03) begin
				ier[15:8] <= din;
				ipr_reset[15:8] <= ipr_reset[15:8] | ~din;
			end

			if(addr == 5'h04) begin
				ier[7:0] <= din;
				ipr_reset[7:0] <= ipr_reset[7:0] | ~din;
			end
			
			if(addr == 5'h05) ipr_reset[15:8] <= ipr_reset[15:8] | ~din;
			if(addr == 5'h06) ipr_reset[7:0]  <= ipr_reset[7:0]  | ~din;
			if(addr == 5'h07) isr_reset[15:8] <= isr_reset[15:8] | ~din;  // zero bits are cleared
			if(addr == 5'h08) isr_reset[7:0]  <= isr_reset[7:0]  | ~din;  // -"-
			if(addr == 5'h09) imr[15:8] <= din;
			if(addr == 5'h0a) imr[7:0]  <= din;
			if(addr == 5'h0b) begin
				vr <= din;
				// clear all in-service bits when switching to auto-end mode
				if (!din[3]) isr_reset <= 16'hffff;
			end
		end
	end
end

endmodule
