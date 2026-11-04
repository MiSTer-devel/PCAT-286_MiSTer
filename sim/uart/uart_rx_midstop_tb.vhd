-- Back-to-back 8N1 characters from a transmitter whose bit time differs from
-- the receiver's, with MIDSTOP 0 (original) and 1. Prints the errors.
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity uart_rx_midstop_tb is
    generic (
        MIDSTOP  : natural := 0;
        TXBIT    : natural := 158;     -- tx bit time in CLK cycles; rx is 160
        NCHARS   : natural := 200
    );
end uart_rx_midstop_tb;

architecture sim of uart_rx_midstop_tb is
    signal clk, rst, rxclk, sin : std_logic := '0';
    signal pe, fe, bi, fin      : std_logic;
    signal dout                 : std_logic_vector(7 downto 0);
    signal done                 : boolean := false;
    signal got_n                : integer := 0;
    signal bad_n                : integer := 0;
    signal fe_n                 : integer := 0;
    signal bi_n                 : integer := 0;
begin
    clk <= not clk after 10 ns when not done else clk;

    -- RXCLK: 16x the baud rate, one CLK wide, every 10 clocks
    process (clk)
        variable c : integer := 0;
    begin
        if rising_edge(clk) then
            if c = 9 then c := 0; rxclk <= '1'; else c := c + 1; rxclk <= '0'; end if;
        end if;
    end process;

    dut : entity work.uart_receiver
        generic map (MIDSTOP => MIDSTOP)
        port map (CLK => clk, RST => rst, RXCLK => rxclk, RXCLEAR => '0',
                  WLS => "11", STB => '0', PEN => '0', EPS => '0', SP => '0',
                  SIN => sin, PE => pe, FE => fe, BI => bi, DOUT => dout,
                  RXFINISHED => fin);

    -- transmitter
    process
        procedure bit_out (b : std_logic) is
        begin
            sin <= b;
            for i in 1 to TXBIT loop wait until rising_edge(clk); end loop;
        end procedure;
        variable d : std_logic_vector(7 downto 0);
    begin
        sin <= '1';
        rst <= '1';
        for i in 1 to 20 loop wait until rising_edge(clk); end loop;
        rst <= '0';
        for i in 1 to 400 loop wait until rising_edge(clk); end loop;
        for n in 0 to NCHARS - 1 loop
            d := std_logic_vector(to_unsigned((n * 37 + 11) mod 256, 8));
            bit_out('0');
            for k in 0 to 7 loop bit_out(d(k)); end loop;
            bit_out('1');
        end loop;
        sin <= '1';
        for i in 1 to 2000 loop wait until rising_edge(clk); end loop;
        report "RESULT MIDSTOP=" & integer'image(MIDSTOP) &
               " txbit=" & integer'image(TXBIT) &
               " sent=" & integer'image(NCHARS) &
               " got=" & integer'image(got_n) &
               " wrong=" & integer'image(bad_n) &
               " fe=" & integer'image(fe_n);
        done <= true;
        wait;
    end process;

    -- checker: the n-th character received must be the n-th one sent
    process (clk)
        variable n   : integer := 0;
        variable exp : std_logic_vector(7 downto 0);
    begin
        if rising_edge(clk) then
            if fin = '1' then
                exp := std_logic_vector(to_unsigned((n * 37 + 11) mod 256, 8));
                if dout /= exp then bad_n <= bad_n + 1; end if;
                if fe = '1' then fe_n <= fe_n + 1; end if;
                n := n + 1;
                got_n <= n;
            end if;
        end if;
    end process;
end sim;
