----------------------------------------------------------------------
----                                                              ----
---- ATARI MFP compatible IP Core					              ----
----                                                              ----
---- This file is part of the SUSKA ATARI clone project.          ----
---- http://www.experiment-s.de                                   ----
----                                                              ----
---- Description:                                                 ----
---- This is the SUSKA MFP IP core USART control file.            ----
----                                                              ----
---- Control unit and status logic.                               ----
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
-- Revision 2K6B  2006/11/07 WF
--   Modified Source to compile with the Xilinx ISE.
-- Revision 2K8A  2008/07/14 WF
--   Minor changes.
--   Separate Transmit and receive buffer and  some
--      minor changes. Thanks to Peter Neways (20121218).
-- Revision 2K15B  20151224 WF
--   Replaced the data type bit by std_logic.
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity USART_CTRL is
port (
	-- System Control:
	CLK			: in std_logic;
	CEP			: in std_logic;
	RESETn		: in std_logic;

	-- Bus control:
	DSn			: in std_logic;
	CSn			: in std_logic;   
	RWn     		: in std_logic;
	RS				: in std_logic_vector(5 downto 1);
	DATA_IN		: in std_logic_vector(7 downto 0);   
	DATA_OUT		: out std_logic_vector(7 downto 0);   
	DATA_OUT_EN	: out std_logic;

	-- USART data register
	RX_SAMPLE	: in std_logic;
	RX_DATA		: in std_logic_vector(7 downto 0);
	TX_DATA		: out std_logic_vector(7 downto 0);   
	SCR_OUT		: out std_logic_vector(7 downto 0);   

	-- USART control inputs:
	BF				: in std_logic;
	BE				: in std_logic;
	FE				: in std_logic;
	OE				: in std_logic;
	UE				: in std_logic;
	PE				: in std_logic;
	M_CIP			: in std_logic;
	FS_B			: in std_logic;
	TX_END		: in std_logic;

	-- USART control outputs:
	CL				: out std_logic_vector(1 downto 0);
	ST				: out std_logic_vector(1 downto 0);
	FS_CLR		: out std_logic;
	UDR_WRITE	: out std_logic;
	UDR_READ		: out std_logic;
	RSR_READ		: out std_logic;
	TSR_READ		: out std_logic;
	LOOPBACK		: out std_logic;
	SDOUT_EN		: out std_logic;
	SD_LEVEL		: out std_logic;
	CLK_MODE		: out std_logic;
	RE				: out std_logic;
	TE				: out std_logic;
	P_ENA			: out std_logic;
	P_EOn			: out std_logic;
	SS				: out std_logic;
	BR				: out std_logic
);                                              
end entity USART_CTRL;

architecture BEHAVIOR of USART_CTRL is
signal SCR	    : std_logic_vector(7 downto 0); -- Synchronous data register.
signal UCR	    : std_logic_vector(7 downto 1); -- USART control register.
signal RSR	    : std_logic_vector(7 downto 0); -- Receiver status register.
signal TSR	    : std_logic_vector(7 downto 0); -- Transmitter status register.
signal UDR_TB	: std_logic_vector(7 downto 0); -- USART transmit data register.
signal UDR_RB	: std_logic_vector(7 downto 0); -- USART receive data register.
begin
	USART_REGISTERS: process(RESETn, CLK)
	begin
		if RESETn = '0' then
			SCR <= (others => '0');
			UCR <= (others => '0');
			RSR <= (others => '0');
			TSR(5) <= '0';
			TSR(2 downto 0) <= "000";
			-- UDR is not cleared during an asserted RESETn
		elsif CLK = '1' and CLK' event then
			-- Loading via receiver shift register
			-- has priority over data buss access:
			if CEP = '1' and RX_SAMPLE = '1' then
				UDR_RB <= RX_DATA;
			elsif CSn = '0' and DSn = '0' and RWn = '0' then
				case RS is
					when "10011"	=> SCR <= DATA_IN;
					when "10100"	=> UCR <= DATA_IN(7 downto 1);
					when "10101"	=> RSR(1 downto 0) <= DATA_IN(1 downto 0); -- Only the two LSB are read/write.
					when "10110"	=> TSR(5) <= DATA_IN(5); TSR(3 downto 0) <= DATA_IN(3 downto 0);
					when "10111"	=> UDR_TB <= DATA_IN;
					when others		=> null;
				end case;
			end if;
			RSR(7 downto 2) <= BF & OE & PE & FE & FS_B & M_CIP;
			TSR(7 downto 6) <= BE & UE;
			TSR(4) <= TX_END;
			TX_DATA <= UDR_TB;		
		end if;
	end process USART_REGISTERS;

	DATA_OUT_EN <= '1' when CSn = '0' and DSn = '0' and RWn = '1' and RS >= "10011" and RS <= "10111" else '0';
	DATA_OUT <= SCR when CSn = '0' and DSn = '0' and RWn = '1' and RS = "10011" else
				UCR & '0' when CSn = '0' and DSn = '0' and RWn = '1' and RS = "10100" else
				RSR when CSn = '0' and DSn = '0' and RWn = '1' and RS = "10101" else
				TSR when CSn = '0' and DSn = '0' and RWn = '1' and RS = "10110" else
				UDR_RB when CSn = '0' and DSn = '0' and RWn = '1' and RS = "10111" else x"00";

	UDR_WRITE 	<= '1' when CSn = '0' and DSn = '0' and RWn = '0' and RS = "10111" else '0';
	UDR_READ 	<= '1' when CSn = '0' and DSn = '0' and RWn = '1' and RS = "10111" else '0';
	RSR_READ 	<= '1' when CSn = '0' and DSn = '0' and RWn = '1' and RS = "10101" else '0';
	TSR_READ 	<= '1' when CSn = '0' and DSn = '0' and RWn = '1' and RS = "10110" else '0';
	FS_CLR		<= '1' when CSn = '0' and DSn = '0' and RWn = '0' and RS = "10011" else '0';

	RE <= '1' when RSR(0) = '1' else -- Receiver enable.
		  '1' when TSR(5) = '1' and TX_END = '1' else '0'; -- Auto Turnaround.
	SS <= RSR(1); -- Synchronous strip enable.
	BR <= TSR(3); -- Send break.
    TE <= TSR(0); -- Transmitter enable early async version for USART_TX.

	SCR_OUT <= SCR;

	CLK_MODE <= UCR(7); -- Clock mode.
	CL <= UCR(6 downto 5); -- Character length.
	ST <= UCR(4 downto 3); -- Start/Stop configuration.
	P_ENA <= UCR(2); -- Parity enable.
	P_EOn <= UCR(1); -- Even or odd parity.
	
	SOUT_CONFIG: process
	begin
		wait until CLK = '1' and CLK' event;
		-- Do not change the output configuration until the transmitter is disabled and
		-- current character has been transmitted (TX_END = '1').
		if CEP = '1' and TX_END = '1' then
			case TSR(2 downto 1) is
                when "00" => LOOPBACK <= '0'; SD_LEVEL <= '0'; SDOUT_EN <= '0';
                when "01" => LOOPBACK <= '0'; SD_LEVEL <= '0'; SDOUT_EN <= TSR(0);
                when "10" => LOOPBACK <= '0'; SD_LEVEL <= '1'; SDOUT_EN <= TSR(0);
                when others => LOOPBACK <= '1'; SD_LEVEL <= '1'; SDOUT_EN <= TSR(0);
			end case;			
		end if;
	end process SOUT_CONFIG;
end architecture BEHAVIOR;

