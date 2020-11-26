//
// ikbd.v
//
// Atari ST ikbd/keyboard implementation
//

module ikbd (
	// 2MHz clock (equals 4Mhz on a real 6301) and system reset
	input        clk,
	input        res,

	input [10:0] ps2_key,
	input [24:0] ps2_mouse,
	input  [7:0] ps2_mouse_ext,

	// ikbd rx/tx to be connected to the 6850
	output       tx,
	input        rx,

	// caps lock output. This is present in the schematics
	// but it is not implemented nor used in the Atari ST
	output       caps_lock,

	// digital joystick with one fire button (FRLDU)
	input  [4:0] joystick1,  // regular joystick
	input  [5:0] joystick0,  // joystick that can replace mouse
	output       joy_port_toggle // signal to toggle between normal and STe joy ports
);

wire [7:0] matrix[14:0];   
wire [5:0] mouse_atari;   

ps2 ps2 (
	.clk(clk),
	.reset(res),

	.ps2_key(ps2_key),
	.matrix(matrix),

	.ps2_mouse(ps2_mouse),
	.ps2_mouse_ext(ps2_mouse_ext),
	.mouse_atari(mouse_atari),
	.joy_port_toggle(joy_port_toggle)
);

// keep track of mouse/joystick0 events to switch between them
reg 	     mouse_active;   
reg [5:0] last_joystick0;
reg [5:0] last_mouse_atari;   

// switch between mouse and joystick
wire [5:0] mouse_joy = mouse_active?mouse_atari:joystick0;

// detect mouse and joystick activity
always @(posedge clk) begin
	if(res) begin
		last_joystick0 <= joystick0;
		last_mouse_atari <= mouse_atari;
		mouse_active <= 1'b1;	 
	end else begin
		if(last_mouse_atari != mouse_atari) begin
			last_mouse_atari <= mouse_atari;
			mouse_active <= 1'b1;	 
		end else if(last_joystick0 != joystick0) begin
			last_joystick0 <= joystick0;
			mouse_active <= 1'b0;	 	    
		end
	end
end      
   
// this implements the 74ls244. This is technically not needed in the FPGA since
// in and out are seperate lines.
wire [7:0] pi4 = po2[0]?8'hff:~{joystick1[3:0], mouse_joy[3:0]};
// right mouse button and joystick1 fire button are connected
wire [1:0] fire_buttons = { mouse_joy[5] | joystick1[4], mouse_joy[4] };

// hd6301 output ports
wire [7:0] po2, po3, po4;

// P24 of the ikbd is its TX line
assign tx = po2[4];
// caps lock led is on P30, but isn't implemented in IKBD ROM
assign caps_lock = po3[0];   

HD63701V0_M6 HD63701V0_M6
(
	.CLKx2(clk),
	.RST(res),
	.NMI(1'b0),
	.IRQ(1'b0),

	// in mode7 the cpu bus becomes
	// io ports 3 and 4
	.RW(),
	.AD({po4, po3}),
	.DO(),
	.DI(),

	.PI1(matrix_out),
	.PI2({po2[4], rx, ~fire_buttons, po2[0]}),
	.PI4(pi4),
	.PO1(),
	.PO2(po2)
);

wire [7:0] matrix_out =
		(!po3[1]?matrix[0]:8'hff)&
		(!po3[2]?matrix[1]:8'hff)&
		(!po3[3]?matrix[2]:8'hff)&
		(!po3[4]?matrix[3]:8'hff)&
		(!po3[5]?matrix[4]:8'hff)&
		(!po3[6]?matrix[5]:8'hff)&
		(!po3[7]?matrix[6]:8'hff)&
		(!po4[0]?matrix[7]:8'hff)&
		(!po4[1]?matrix[8]:8'hff)&
		(!po4[2]?matrix[9]:8'hff)&
		(!po4[3]?matrix[10]:8'hff)&
		(!po4[4]?matrix[11]:8'hff)&
		(!po4[5]?matrix[12]:8'hff)&
		(!po4[6]?matrix[13]:8'hff)&
		(!po4[7]?matrix[14]:8'hff);

endmodule
