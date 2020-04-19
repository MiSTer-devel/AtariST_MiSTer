derive_pll_clocks
derive_clock_uncertainty;

# SDRAM 96 MHz to system 32 MHz
set_multicycle_path -from [get_clocks { *|pll|pll_inst|altera_pll_i|*[0].*|divclk}] -to [get_clocks { *|pll|pll_inst|altera_pll_i|*[1].*|divclk}] -start -setup 2
set_multicycle_path -from [get_clocks { *|pll|pll_inst|altera_pll_i|*[0].*|divclk}] -to [get_clocks { *|pll|pll_inst|altera_pll_i|*[1].*|divclk}] -start -hold 1

# System 32 MHz to SDRAM 96 MHz
set_multicycle_path -from [get_clocks { *|pll|pll_inst|altera_pll_i|*[1].*|divclk}] -to [get_clocks { *|pll|pll_inst|altera_pll_i|*[0].*|divclk}] -end -setup 2
set_multicycle_path -from [get_clocks { *|pll|pll_inst|altera_pll_i|*[1].*|divclk}] -to [get_clocks { *|pll|pll_inst|altera_pll_i|*[0].*|divclk}] -end -hold 1

# System 32 MHz to 2MHz
set_multicycle_path -from [get_clocks { *|pll|pll_inst|altera_pll_i|*[1].*|divclk}] -to [get_clocks { *|pll|pll_inst|altera_pll_i|*[2].*|divclk}] -start -setup 2
set_multicycle_path -from [get_clocks { *|pll|pll_inst|altera_pll_i|*[1].*|divclk}] -to [get_clocks { *|pll|pll_inst|altera_pll_i|*[2].*|divclk}] -start -hold 1
