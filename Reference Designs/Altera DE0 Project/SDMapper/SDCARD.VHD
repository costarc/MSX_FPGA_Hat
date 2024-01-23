-- 
-- megasd.vhd
--   SD/MMC card interface
--   Revision 1.00
-- 
-- Copyright (c) 2006 Kazuhiro Tsujikawa (ESE Artists' factory)
-- All rights reserved.
-- 
-- Redistribution and use of this source code or any derivative works, are 
-- permitted provided that the following conditions are met:
--
-- 1. Redistributions of source code must retain the above copyright notice, 
--    this list of conditions and the following disclaimer.
-- 2. Redistributions in binary form must reproduce the above copyright 
--    notice, this list of conditions and the following disclaimer in the 
--    documentation and/or other materials provided with the distribution.
-- 3. Redistributions may not be sold, nor may they be used in a commercial 
--    product or activity without specific prior written permission.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS 
-- "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED 
-- TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR 
-- PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR 
-- CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, 
-- EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, 
-- PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
-- OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, 
-- WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR 
-- OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF 
-- ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity sdcard is
  port(
    clk21m  : in std_logic;
    reset   : in std_logic;
    clkena  : in std_logic;
    req     : in std_logic;
    ack     : out std_logic;
    wrt     : in std_logic;
    adr     : in std_logic_vector(15 downto 0);
    dbi     : out std_logic_vector(7 downto 0);
    dbo     : in std_logic_vector(7 downto 0);

    mmcdbi  : out std_logic_vector(7 downto 0);
    mmcena  : out std_logic;
    mmcact  : out std_logic;

    mmc_ck  : out std_logic;
    mmc_cs  : out std_logic;
    mmc_di  : out std_logic;
    mmc_do  : in std_logic

  );
end sdcard;

architecture rtl of sdcard is

  signal ErmBank0    : std_logic_vector(7 downto 0);

begin
  ----------------------------------------------------------------
  -- ESE-RAM bank register access
  ----------------------------------------------------------------
  process(clk21m, reset)
  begin
    if (reset = '1') then
      ErmBank0   <= X"00";
    elsif (clk21m'event and clk21m = '1') then
 -- Mapped I/O port access on 6000-7FFFh ... Bank register write
      if (req = '1' and wrt = '1' and adr(15 downto 13) = "011" AND adr(12 downto 11) = "00") then
        ErmBank0 <= dbo;	-- 6000..67ff
      end if;
      ack <= req;
    end if;
  end process;
  
  ----------------------------------------------------------------
  -- SD/MMC card access
  ----------------------------------------------------------------
  process(clk21m, reset)
    variable MmcEnx : std_logic := '1';
    variable MmcMod : std_logic_vector(1 downto 0);
    variable MmcSeq : std_logic_vector(4 downto 0);
    variable MmcTmp : std_logic_vector(7 downto 0);
    variable MmcDbo : std_logic_vector(7 downto 0);
  begin
    if (reset = '1') then
      MmcEnx := '0';
      MmcMod := (others => '0');
      MmcSeq := (others => '0');
      MmcTmp := (others => '1');
      MmcDbo := (others => '1');
      mmcdbi <= (others => '1');

      mmc_ck <= '1';
      mmc_cs <= '1';
      mmc_di <= 'Z';

    elsif (clk21m'event and clk21m = '1') then
      MmcEnx := '1';

-- WR MMC & EPC 
      if (MmcSeq(0) = '0') then
        case MmcSeq(4 downto 1) is
          when "1010" => mmc_di <= MmcDbo(7);
          when "1001" => mmc_di <= MmcDbo(6);
          when "1000" => mmc_di <= MmcDbo(5);
          when "0111" => mmc_di <= MmcDbo(4);
          when "0110" => mmc_di <= MmcDbo(3);
          when "0101" => mmc_di <= MmcDbo(2);
          when "0100" => mmc_di <= MmcDbo(1);
          when "0011" => mmc_di <= MmcDbo(0);
          when "0010" => mmc_di <= '1';
          when "0001" => mmc_di <= 'Z';
          when others => mmc_di <= 'Z';
        end case;
      end if;
-- RD MMC
      if (MmcSeq(0) = '0') then
        case MmcSeq(4 downto 1) is
          when "1001" => MmcTmp(7) := mmc_do;
          when "1000" => MmcTmp(6) := mmc_do;
          when "0111" => MmcTmp(5) := mmc_do;
          when "0110" => MmcTmp(4) := mmc_do;
          when "0101" => MmcTmp(3) := mmc_do;
          when "0100" => MmcTmp(2) := mmc_do;
          when "0011" => MmcTmp(1) := mmc_do;
          when "0010" => MmcTmp(0) := mmc_do;
          when "0001" => mmcdbi <= MmcTmp;		-- RD data MMC
          when others => null;
        end case;
      end if;

-- CLK
      if (MmcSeq(4 downto 1) < "1011" and MmcSeq(4 downto 1) > "0010") then
        mmc_ck <= MmcSeq(0);
      else
        mmc_ck <= '1';
      end if;

-- Memory mapped I/O port access on 4000-57FFh ... SD/MMC data register
      if (req = '1' and adr(15 downto 13) = "010" and adr(12 downto 11) /= "11" and 
          MmcEnx = '1' and MmcSeq = "00000" and MmcMod(0) = '0') then
        if (wrt = '1') then
          MmcDbo := dbo;
        else
          MmcDbo := (others => '1');
        end if;
        
		mmc_cs <= adr(12);		-- /CS MMC (4000h..47ff)
        MmcSeq := "10101";
      elsif (MmcSeq /= "00000") then
        MmcSeq := MmcSeq - 1;
      end if;

-- Memory mapped I/O port access on 5800-5FFFh ... SD/MMC data register
      if (req = '1' and adr(15 downto 13) = "010" and adr(12 downto 11)  = "11" and 
					MmcEnx = '1' and wrt = '1') then
        MmcMod := dbo(1 downto 0);	-- 
      end if;
-- generate /WAIT for Z80
      if (MmcSeq = "00000") then
        mmcact <= '0';
      else
        mmcact <= '1';
      end if;
--
    end if;
end process;
--
  mmcena <= '1' when ErmBank0(7 downto 6) = "01" else '0';

end rtl;
