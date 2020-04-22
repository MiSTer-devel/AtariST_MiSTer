----------------------------------------------------------------------
----                                                              ----
---- ATARI MFP compatible IP Core					              ----
----                                                              ----
---- This file is part of the SUSKA ATARI clone project.          ----
---- http://www.experiment-s.de                                   ----
----                                                              ----
---- Description:                                                 ----
---- This is the SUSKA MFP IP core USART transmitter file.        ----
----                                                              ----
----                                                              ----
----                                                              ----
---- To Do:                                                       ----
---- -                                                            ----
----                                                              ----
---- Author(s):                                                   ----
---- - Wolfgang Foerster, wf@experiment-s.de; wf@inventronik.de   ----
----                                                              ----
----------------------------------------------------------------------
----                                                              ----
---- Copyright (C) 2006 - 2011 Wolfgang Foerster                  ----
----                                                              ----
---- This source file may be used and distributed without         ----
---- restriction provided that this copyright statement is not    ----
---- removed from the file and that any derivative work contains  ----
---- the original copyright notice and the associated disclaimer. ----
----                                                              ----
---- This source file is free software; you can redistribute it   ----
---- and/or modify it under the terms of the GNU Lesser General   ----
---- Public License as published by the Free Software Foundation; ----
---- either version 2.1 of the License, or (at your option) any   ----
---- later version.                                               ----
----                                                              ----
---- This source is distributed in the hope that it will be       ----
---- useful, but WITHOUT ANY WARRANTY; without even the implied   ----
---- warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR      ----
---- PURPOSE. See the GNU Lesser General Public License for more  ----
---- details.                                                     ----
----                                                              ----
---- You should have received a copy of the GNU Lesser General    ----
---- Public License along with this source; if not, download it   ----
---- from http://www.gnu.org/licenses/lgpl.html                   ----
----                                                              ----
----------------------------------------------------------------------
-- 
-- Revision History
-- 
-- Revision 2K6A  2006/06/03 WF
--   Initial Release.
-- Revision 2K6B	2006/11/07 WF
--   Modified Source to compile with the Xilinx ISE.
-- Revision 2K8A  2008/07/14 WF
--   Minor changes.
-- Revision 2K9A  2009/06/20 WF
--   TDRE has now synchronous reset to meet preset requirement.
-- Revision 2K13B  2013/12/24 WF
--   Minor changes. Thanks to Peter Neways (20121218).
-- Revision 2K15B  20151224 WF
--   Replaced the data type bit by std_logic.
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity USART_TX is
port (
	CLK		: in std_logic;
	CEP		: in std_logic;
	RESETn	: in std_logic;

	SCR		: in std_logic_vector(7 downto 0); -- Synchronous character.
	TX_DATA	: in std_logic_vector(7 downto 0); -- Normal data.

	SDATA_OUT: out std_logic; -- Serial data output.
	TXCLK		: in std_logic;  -- Transmitter clock.

	CL			: in std_logic_vector(1 downto 0); -- Character length.
	ST			: in std_logic_vector(1 downto 0); -- Start and stop bit configuration.
	TE			: in std_logic; -- Transmitter enable.
	BR			: in std_logic; -- BREAK character send enable (all '0' without stop bit).
	P_ENA		: in std_logic; -- Parity enable.
	P_EOn		: in std_logic; -- Even or odd parity.
	UDR_WRITE: in std_logic; -- Flag indicating writing the data register.
	TSR_READ	: in std_logic; -- Flag indicating reading the transmitter status register.
	CLK_MODE	: in std_logic; -- Transmitter clock mode.

	TX_END	: out std_logic; -- End of transmission flag.
	UE			: out std_logic; -- Underrun Flag.
	BE			: out std_logic  -- Buffer empty flag.
);                                              
end entity USART_TX;

architecture BEHAVIOR of USART_TX is
type TR_STATES is (IDLE, CHECK_BREAK, LOAD_SHFT, START, SHIFTOUT, PARITY, STOP1, STOP2);
signal TR_STATE, TR_NEXT_STATE	: TR_STATES;
signal CLK_STRB		: std_logic;
signal CLK_2_STRB	: std_logic;
signal SHIFT_REG	: std_logic_vector(7 downto 0);
signal BITCNT		: std_logic_vector(2 downto 0);
signal PARITY_I		: std_logic;
signal TDRE			: std_logic;
signal BREAK		: std_logic;
begin
	BE <= TDRE; -- Buffer empty flag.
	
	-- The default condition in this statement is to ensure
	-- to cover all possibilities for example if there is a
	-- one hot decoding of the state machine with wrong states
	-- (e.g. not one of the given here).
	SDATA_OUT <= 	'0'				when BREAK = '1'			else
					'1' 			when TR_STATE = IDLE 		else
					'1' 			when TR_STATE = LOAD_SHFT 	else
					'0' 			when TR_STATE = START 		else
					SHIFT_REG(0) 	when TR_STATE = SHIFTOUT 	else
					PARITY_I		when TR_STATE = PARITY 		else
					'1'				when TR_STATE = STOP1 		else
					'1'				when TR_STATE = STOP2 		else '1';

	P_BREAK : process(RESETn, CLK)
	-- This process is responsible to control the BREAK signal. After the break request
	-- is asserted via BR, the break character will be sent after the current transmission has
	-- finished. The BREAK character is sent until the BR is disabled.
	variable LOCK : boolean;
	begin
		if RESETn = '0' then
			BREAK <= '0';
		elsif CLK = '1' and CLK' event then
			if CEP = '1' then
				-- Break is only available in the asynchronous mode (ST /= "00").
				-- The LOCK mechanism is reponsible for sending the BREAK character just once.
				if TE = '1' and BR = '1' and ST /= "00" and TR_STATE = IDLE and LOCK = false then
					BREAK <= '1'; -- Break for the case that there is no current transmission.
					LOCK := true;
				elsif BR = '1' and ST /= "00" and TR_STATE = STOP1 then
					BREAK <= '0'; -- Break character sent.
				elsif BR = '0' then
					BREAK <= '0';
					LOCK := false;
				else
					BREAK <= '0';	
				end if;
			end if;
		end if;
	end process P_BREAK;

	CLKDIV: process
	variable CLK_LOCK	: boolean;
	variable STRB_LOCK	: boolean;
	variable CLK_DIVCNT	: std_logic_vector(4 downto 0);
	begin
		wait until CLK = '1' and CLK' event;
		if CEP = '1' then
			if CLK_MODE = '0' then -- Divider off.
				if TXCLK = '0' and STRB_LOCK = false then  -- Works on negative TXCLK edge.
					CLK_STRB <= '1';
					STRB_LOCK := true;
				elsif TXCLK = '1' then
					CLK_STRB <= '0';
					STRB_LOCK := false;
				else
					CLK_STRB <= '0';
				end if;
				CLK_2_STRB <= '0'; -- No 1 1/2 stop bits in no div by 16 mode.
			elsif TR_STATE = IDLE then
				CLK_DIVCNT := "10000"; -- Div by 16 mode.
				CLK_STRB <= '0';
			else
				CLK_STRB <= '0'; -- Default.
				CLK_2_STRB <= '0'; -- Default.
				-- Works on negative TXCLK edge:
				if CLK_DIVCNT > "00000" and TXCLK = '0' and CLK_LOCK = false then
					CLK_DIVCNT := CLK_DIVCNT - '1';
					CLK_LOCK := true;
					if CLK_DIVCNT = "01000" then
						-- This strobe is asserted at half of the clock cycle.
						-- It is used for the stop bit timing.
						CLK_2_STRB <= '1';
					end if;
				elsif CLK_DIVCNT = "00000" then
					CLK_DIVCNT := "10000"; -- Div by 16 mode.
					if STRB_LOCK = false then
						STRB_LOCK := true;
						CLK_STRB <= '1';
					end if;
				elsif TXCLK = '1' then
					CLK_LOCK := false;
					STRB_LOCK := false;
				end if;
			end if;
		end if;
	end process CLKDIV;

	SHIFTREG: process(RESETn, CLK)
	begin
		if RESETn = '0' then
			SHIFT_REG <= x"00";
		elsif CLK = '1' and CLK' event then
			if CEP = '1' then
				if TR_STATE = LOAD_SHFT and TDRE = '1' then -- Lost data ...
					case ST is
						when "00" => -- Synchronous mode.
							SHIFT_REG <= SCR; -- Send the synchronous character.
						when others => -- Asynchronous mode.
							SHIFT_REG <= x"5A"; -- Load the shift register with a mark (underrun).
					end case;
				elsif TR_STATE = LOAD_SHFT then
					-- Load 'normal' data if there is no break condition:
					case CL is
						when "11" => SHIFT_REG <= "000" & TX_DATA(4 downto 0); -- 5 databits.
						when "10" => SHIFT_REG <= "00" & TX_DATA(5 downto 0); -- 6 databits.
						when "01" => SHIFT_REG <= '0' & TX_DATA(6 downto 0); -- 7 databits.
						when others => SHIFT_REG <= TX_DATA; -- 8 databits.
					end case;
				elsif TR_STATE = SHIFTOUT and CLK_STRB = '1' then
					SHIFT_REG <= '0' & SHIFT_REG(7 downto 1); -- Shift right.
				end if;
			end if;
		end if;
	end process SHIFTREG;	

	P_BITCNT: process
	-- Counter for the data bits transmitted.
	begin
		wait until CLK = '1' and CLK' event;
		if CEP = '1' then
			if TR_STATE = SHIFTOUT and CLK_STRB = '1' then
				BITCNT <= BITCNT + '1';
			elsif TR_STATE /= SHIFTOUT then
				BITCNT <= "000";
			end if;
		end if;
	end process P_BITCNT;

	BUFFER_EMPTY: process
	-- Transmit data register empty flag.
    variable LOCK : boolean;
	begin
		wait until CLK = '1' and CLK' event;
		if RESETn = '0' then
			TDRE <= '1';
		elsif CEP = '1' then
			
			if TE = '0' then
				TDRE <= '1';
			elsif  UDR_WRITE = '1' and LOCK = false then
				TDRE <= '0';
					LOCK := true;
			  -- HP: Note: The Start state takes a long time, LOAD_SHFT just one clock; 
			  --           a write busccyle during the start state may not be ignored
			  elsif TR_STATE = LOAD_SHFT and BREAK = '0' then  -- was: TR_STATE = START
				-- Data has been loaded to the shift register,
				-- thus data register is free again.
				-- If the BREAK flag is enabled, the BE flag
				-- respective TDRE flag cannot be set.
				TDRE <= '1';
			end if;
		end if;
		if CEP = '1' then
			if UDR_WRITE = '0' then
				LOCK := false;
			end if;
		end if;
	end process BUFFER_EMPTY;

	UNDERRUN: process(RESETn, CLK)
	variable LOCK	: boolean;
	begin
		if RESETn = '0' then
			UE <= '0';
			LOCK := false;
		elsif CLK = '1' and CLK' event then
			if CEP = '1' then
				if TE = '0' then
					UE <= '0';
					LOCK := false;
				elsif CLK_STRB = '1' and TR_STATE = START then
					-- Underrun appears if TDRE is '0' at the end of this state.
					UE <= TDRE; -- Never true for enabled BREAK flag. See alos process BUFFER_EMPTY.
					LOCK := true;
				elsif CLK_STRB = '1' then
					LOCK := false; -- Disables clearing UE one transmit clock cycle.
				elsif TSR_READ = '1' and LOCK = false then
					UE <= '0';
				end if;
			end if;
		end if;
	end process UNDERRUN;
	
	P_TX_END: process(RESETn, CLK)
	begin
		if RESETn = '0' then
			TX_END <= '0';
		elsif CLK = '1' and CLK' event then
			if CEP = '1' then
				if TE = '1' then -- Transmitter enabled.
					TX_END <= '0';
				elsif TE = '0' and TR_STATE /= IDLE and TR_NEXT_STATE =IDLE then
					TX_END <= '1'; -- Early indication.
				elsif TE = '0' and TR_STATE = IDLE then
					TX_END <= '1';
				end if;
			end if;
		end if;
	end process P_TX_END;
	
	PARITY_GEN: process
	variable PAR_TMP	: std_logic;
	begin
		wait until CLK = '1' and CLK' event;
		if CEP = '1' then
			if TR_STATE = START then -- Calculate the parity during the start phase.
				 for i in 1 to 7 loop
					  if i = 1 then
							PAR_TMP := SHIFT_REG(i-1) xor SHIFT_REG(i);
					  else
							PAR_TMP := PAR_TMP xor SHIFT_REG(i);
					  end if;
				 end loop;
				if P_ENA = '1' and P_EOn = '1' then -- Even parity.
					PARITY_I <= PAR_TMP;
				elsif P_ENA = '1' and P_EOn = '0' then -- Odd parity.
					PARITY_I <= not PAR_TMP;
				else -- No parity.
					PARITY_I <= '0';		
				end if;
			end if;
		end if;
	end process PARITY_GEN;

	TR_STATEREG: process(RESETn, CLK)
	begin
		if RESETn = '0' then
			TR_STATE <= IDLE;
		elsif CLK = '1' and CLK' event then
			if CEP = '1' then
				TR_STATE <= TR_NEXT_STATE;
			end if;
		end if;
	end process TR_STATEREG;
	
	TR_STATEDEC: process(TR_STATE, CLK_STRB, CLK_2_STRB, BITCNT, TDRE, BREAK, TE, ST, P_ENA, CL, BR)
	begin
		case TR_STATE is
			when IDLE =>
				-- This IDLE state is just one clock cycle and is required to give the
				-- break process time to set the BREAK flag.
				TR_NEXT_STATE <= CHECK_BREAK;
			when CHECK_BREAK =>
				if BREAK = '1' then -- Send break character.
					-- Do not load any data to the shift register, go directly
					-- to the START state.
					TR_NEXT_STATE <= START;
				-- Start enabled transmitter, if the data register is not empty.
				 -- Do not send any further data for the case of an asserted BR flag.
				elsif TE = '1' and TDRE = '0' and BR = '0' then
					TR_NEXT_STATE <= LOAD_SHFT;
				else
					TR_NEXT_STATE <= IDLE; -- Go back, scan for BREAK.
				end if;
			when LOAD_SHFT =>
				TR_NEXT_STATE <= START;
			when START => -- Send the start bit.
				if CLK_STRB = '1' then
					TR_NEXT_STATE <= SHIFTOUT;
				else
					TR_NEXT_STATE <= START;
				end if;
			when SHIFTOUT =>
				if CLK_STRB = '1' then
					if BITCNT < "100" and CL = "11" then
						TR_NEXT_STATE <= SHIFTOUT; -- Transmit 5 data bits.
					elsif BITCNT < "101" and CL = "10" then
						TR_NEXT_STATE <= SHIFTOUT; -- Transmit 6 data bits.
					elsif BITCNT < "110" and CL = "01" then
						TR_NEXT_STATE <= SHIFTOUT; -- Transmit 7 data bits.
					elsif BITCNT < "111" and CL = "00" then
						TR_NEXT_STATE <= SHIFTOUT; -- Transmit 8 data bits.
					elsif P_ENA = '0' and BREAK = '1' then
						TR_NEXT_STATE <= IDLE; -- Break condition, no parity check enabled, no stop bits.
					elsif P_ENA = '0' and ST = "00" then
						TR_NEXT_STATE <= IDLE; -- Synchronous mode, no parity check enabled.
					elsif P_ENA = '0' then
						TR_NEXT_STATE <= STOP1; -- Asynchronous mode, no parity check enabled.
					else
						TR_NEXT_STATE <= PARITY; -- Parity enabled.
					end if;
				else
					TR_NEXT_STATE <= SHIFTOUT;
				end if;
			when PARITY =>
				if CLK_STRB = '1' then
					if ST = "00" then -- Synchronous mode (no stop bits).
						TR_NEXT_STATE <= IDLE;
					elsif BREAK = '1' then -- No stop bits during break condition.
						TR_NEXT_STATE <= IDLE;
					else
						TR_NEXT_STATE <= STOP1;
					end if;
				else
					TR_NEXT_STATE <= PARITY;
				end if;				
			when STOP1 =>
				if CLK_STRB = '1' and (ST = "11" or ST = "10") then
					TR_NEXT_STATE <= STOP2; -- More than one stop bits selected.
				elsif CLK_STRB = '1' then
					TR_NEXT_STATE <= IDLE; -- One stop bits selected.
				else
					TR_NEXT_STATE <= STOP1;
				end if;				
			when STOP2 =>
				if CLK_2_STRB = '1' and ST = "10" then
					TR_NEXT_STATE <= IDLE; -- One and a half stop bits selected.
				elsif CLK_STRB = '1' then
					TR_NEXT_STATE <= IDLE; -- Two stop bits detected.
				else
					TR_NEXT_STATE <= STOP2;
				end if;				
		end case;
	end process TR_STATEDEC;
end architecture BEHAVIOR;

