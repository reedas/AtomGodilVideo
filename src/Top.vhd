----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    14:42:09 02/09/2013 
-- Design Name: 
-- Module Name:    Top - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.all;
use IEEE.STD_LOGIC_UNSIGNED.all;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity Top is
    port (

        -- Standard 6847 signals
        --
        -- expept DA which is now input only
        -- except nRP which re-purposed as a nWR
        
        CLK    : in    std_logic;
        DD     : inout std_logic_vector (7 downto 0);
        DA     : in    std_logic_vector (12 downto 0);
        CHB    : out   std_logic;
        OA     : out   std_logic;
        OB     : out   std_logic;
        nMS    : in    std_logic;
        CSS    : in    std_logic;
        nHS    : out   std_logic;
        nFS    : out   std_logic;
        nWR    : in    std_logic;       -- Was nRP
        AG     : in    std_logic;
        AS     : in    std_logic;
        INV    : in    std_logic;
        INTEXT : in    std_logic;
        GM     : in    std_logic_vector (2 downto 0);
        Y      : out   std_logic;

        -- 5 bit VGA Output

        R     : out std_logic_vector (0 downto 0);
        G     : out std_logic_vector (1 downto 0);
        B     : out std_logic_vector (0 downto 0);
        HSYNC : out std_logic;
        VSYNC : out std_logic;
        
        -- 1 bit AUDIO Output
        AUDIO : out std_logic;
        
        -- Other GODIL specific pins

        clock49 : in std_logic;
        nRST : in std_logic;

        nBXXX : in std_logic;

        -- Jumpers
        
        -- Enables VGA Signals on PL4
        nPL4 : in std_logic;
        
        -- Moves SID from 9FE0 to BDC0 
        nSIDD : in std_logic;
        
        -- Active low version of the SID Select Signal for disabling the external bus buffers
        nSIDSEL : out std_logic

        );
end Top;

architecture BEHAVIORAL of Top is

    -- Set this to 0 if you want dark green/dark orange background on text
    -- Set this to 1 if you want black background on text (authentic Atom)
    constant BLACK_BACKGND : std_logic := '1';

    -- Clock12 is a half speed VGA clock
    signal clock12 : std_logic;
    
    -- Other clocks are for SID
    -- 1MHZ, 32MHz and 
    signal div32  : std_logic_vector (4 downto 0);
    signal clock1 : std_logic;
    signal clock15 : std_logic;
    signal clock32 : std_logic;
    
    -- Reset signal to 6847, not currently used
    signal reset   : std_logic;

    -- pipelined versions of the address/data/write signals
    signal nWR1 : std_logic;
    signal nWR2 : std_logic;
    signal nMS1 : std_logic;
    signal nMS2 : std_logic;
    signal nWRMS1 : std_logic;
    signal nWRMS2 : std_logic;
    signal nBXXX1 : std_logic;
    signal nBXXX2 : std_logic;
    signal DA1  : std_logic_vector (12 downto 0);
    signal DA2  : std_logic_vector (12 downto 0);
    signal DD1  : std_logic_vector (7 downto 0);
    signal DD2  : std_logic_vector (7 downto 0);

    -- VGA colour signals out of mc6847, only top 2 bits are used
    signal vga_red   : std_logic_vector (7 downto 0);
    signal vga_green : std_logic_vector (7 downto 0);
    signal vga_blue  : std_logic_vector (7 downto 0);
    signal vga_vsync : std_logic;
    signal vga_hsync : std_logic;
    
    -- 8Kx8 Dual port video RAM signals
    -- Port A connects to Atom and is read/write
    -- Port B connects to MC6847 and is read only
    signal wr     : std_logic;
    signal addra : std_logic_vector (12 downto 0);
    signal dina  : std_logic_vector (7 downto 0);
    signal douta : std_logic_vector (7 downto 0);
    signal addrb : std_logic_vector (12 downto 0);
    signal doutb : std_logic_vector (7 downto 0);

    -- Dout back to the Atom, that is either VRAM or SID
    signal dout  : std_logic_vector (7 downto 0);

    -- Masked (by nRST) version of the mode control signals
    signal mask  : std_logic;    
    signal gm_masked  : std_logic_vector (2 downto 0);
    signal ag_masked  : std_logic;
    signal css_masked : std_logic;
    

    -- SID sigmals
    signal sid_cs : std_logic;
    signal sid_we : std_logic;
    signal sid_addr  : std_logic_vector (4 downto 0);
    signal sid_do  : std_logic_vector (7 downto 0);
    signal sid_di  : std_logic_vector (7 downto 0);
    signal sid_audio : std_logic;

    -- Atom Extensions register
    signal extensions : std_logic_vector (7 downto 0);

    signal mc6847_an_s : std_logic;
    signal mc6847_intn_ext : std_logic;
    signal mc6847_inv : std_logic;
    signal mc6847_css : std_logic;
    signal mc6847_d : std_logic_vector (7 downto 0);

    component DCM0
        port(
            CLKIN_IN  : in  std_logic;
            CLK0_OUT  : out std_logic;
            CLK0_OUT1 : out std_logic;
            CLK2X_OUT : out std_logic
            );
    end component;

    component DCMSID0
        port(
            CLKIN_IN  : in  std_logic;
            CLK0_OUT  : out std_logic;
            CLK0_OUT1 : out std_logic;
            CLK2X_OUT : out std_logic
            );
    end component;

    component DCMSID1
        port(
            CLKIN_IN  : in  std_logic;
            CLK0_OUT  : out std_logic;
            CLK0_OUT1 : out std_logic;
            CLK2X_OUT : out std_logic
            );
    end component;

    component mc6847
        port(
            clk            : in  std_logic;
            clk_ena        : in  std_logic;
            reset          : in  std_logic;
            dd             : in  std_logic_vector(7 downto 0);
            an_g           : in  std_logic;
            an_s           : in  std_logic;
            intn_ext       : in  std_logic;
            gm             : in  std_logic_vector(2 downto 0);
            css            : in  std_logic;
            inv            : in  std_logic;
            artifact_en    : in  std_logic;
            artifact_set   : in  std_logic;
            artifact_phase : in  std_logic;
            da0            : out std_logic;
            videoaddr      : out std_logic_vector(12 downto 0);
            hs_n           : out std_logic;
            fs_n           : out std_logic;
            red            : out std_logic_vector(7 downto 0);
            green          : out std_logic_vector(7 downto 0);
            blue           : out std_logic_vector(7 downto 0);
            hsync          : out std_logic;
            vsync          : out std_logic;
            hblank         : out std_logic;
            vblank         : out std_logic;
            cvbs           : out std_logic_vector(7 downto 0);
            black_backgnd  : in  std_logic
            );
    end component;

    component VideoRam
        port (
            clka  : in  std_logic;
            wea   : in  std_logic;
            addra : in  std_logic_vector(12 downto 0);
            dina  : in  std_logic_vector(7 downto 0);
            douta : out std_logic_vector(7 downto 0);
            clkb  : in  std_logic;
            web   : in  std_logic;
            addrb : in  std_logic_vector(12 downto 0);
            dinb  : in  std_logic_vector(7 downto 0);
            doutb : out std_logic_vector(7 downto 0)
            );
    end component;
    
    component sid6581
        port(
            clk_1MHz : in std_logic;
            clk32 : in std_logic;
            clk_DAC : in std_logic;
            reset : in std_logic;
            cs : in std_logic;
            we : in std_logic;
            addr : in std_logic_vector(4 downto 0);
            di : in std_logic_vector(7 downto 0);    
            pot_x : in std_logic;
            pot_y : in std_logic;      
            do : out std_logic_vector(7 downto 0);
            audio_out : out std_logic;
            audio_data : out std_logic_vector(17 downto 0)
            );
    end component;

begin

    reset <= '0';

    -- Currently set at 49.152 * 8 / 31 = 12.684MHz
    -- half VGA should be 25.175 / 2 = 12. 5875
    -- we could get closer with to cascaded multipliers
    Inst_DCM0 : DCM0
        port map (
            CLKIN_IN  => clock49,
            CLK0_OUT  => clock12,
            CLK0_OUT1 => open,
            CLK2X_OUT => open
            );

    Inst_DCMSID0 : DCMSID0
        port map (
            CLKIN_IN  => clock49,
            CLK0_OUT  => clock15,
            CLK0_OUT1 => open,
            CLK2X_OUT => open
            );
            
    Inst_DCMSID1 : DCMSID1
        port map (
            CLKIN_IN  => clock15,
            CLK0_OUT  => clock32,
            CLK0_OUT1 => open,
            CLK2X_OUT => open
            );            
            
    -- Motorola MC6847
    -- Original version: https://svn.pacedev.net/repos/pace/sw/src/component/video/mc6847.vhd
    -- Updated by AlanD for his Atom FPGA: http://stardot.org.uk/forums/viewtopic.php?f=3&t=6313
    -- A further few bugs fixed by myself
    Inst_mc6847 : mc6847
        port map (
            clk            => clock12,
            clk_ena        => '1',
            reset          => reset,
            da0            => open,
            videoaddr      => addrb,
            dd             => mc6847_d,
            hs_n           => open,
            fs_n           => nFS,
            an_g           => ag_masked,
            an_s           => mc6847_an_s,
            intn_ext       => mc6847_intn_ext,
            gm             => gm_masked,
            css            => mc6847_css,
            inv            => mc6847_inv,
            red            => vga_red,
            green          => vga_green,
            blue           => vga_blue,
            hsync          => vga_hsync,
            vsync          => vga_vsync,
            artifact_en    => '0',
            artifact_set   => '0',
            artifact_phase => '0',
            hblank         => open,
            vblank         => open,
            cvbs           => open,
            black_backgnd  => BLACK_BACKGND
            );
    
    -- 8Kx8 Dual port video RAM
    -- Port A connects to Atom and is read/write
    -- Port B connects to MC6847 and is read only    
    Inst_VideoRam : VideoRam
        port map (
            clka  => clock32,
            wea   => wr,
            addra => addra,
            dina  => dina,
            douta => douta,
            clkb  => clock12,
            web   => '0',
            addrb => addrb,
            dinb  => (others => '0'),
            doutb => doutb
            );

    Inst_sid6581: sid6581
        port map (
            clk_1MHz => clock1,
            clk32 => clock32,
            clk_DAC => clock49,
            reset => not nRST,
            cs => sid_cs,
            we => sid_we,
            addr => sid_addr,
            di => sid_di,
            do => sid_do,
            pot_x => '0',
            pot_y => '0',
            audio_out => sid_audio,
            audio_data => open 
        );


    -- Pipelined version of address/data/write signals
    process (clock32)
    begin
        if rising_edge(clock32) then
            nBXXX2 <= nBXXX1;
            nBXXX1 <= nBXXX;
            nMS2 <= nMS1;
            nMS1 <= nMS;
            nWRMS2 <= nWRMS1;
            nWRMS1 <= nWR or nMS;
            nWR2 <= nWR1;
            nWR1 <= nWR;
            DD2  <= DD1;
            DD1  <= DD;
            DA2  <= DA1;
            DA1  <= DA;
            div32 <= div32 + 1;
        end if;
    end process;

    -- A register to control extra 6847 features
    process (clock32)
    begin
        if rising_edge(clock32) then
            if (nRST = '0') then
                extensions <= (others => '0');
            elsif (sid_cs = '1' and sid_we = '1' and sid_addr = "11111") then
                extensions <= sid_di;
            end if;
        end if;
    end process;
    
    -- Adjust the inputs to the 6847 based on the extensions register
    process (extensions, doutb, css_masked)
    begin
        case extensions(2 downto 0) is
    
        -- Text plus 8 Colour Semigraphics 4
        when "001" =>
            mc6847_an_s <= doutb(6);
            mc6847_intn_ext <= '0';
            mc6847_inv <= doutb(7);
            -- Replace the 64-127 and 192-255 blocks with Semigraphics 4
            -- Only tweak the data bus when actually displaying semigraphics
            if (ag_masked = '0' and doutb(6) = '1') then
                mc6847_d <= '0' & doutb(7) & doutb(5 downto 0);
            else
                mc6847_d <= doutb;
            end if;
            mc6847_css <= css_masked;              

        -- 2 Colour Text Only
        when "010" =>
            mc6847_an_s <= '0';
            mc6847_intn_ext <= '0';
            mc6847_inv <= doutb(7);
            if (ag_masked = '0' and doutb(6) = '1') then
                mc6847_d <= "00" & doutb(5 downto 0);
            else
                mc6847_d <= doutb;
            end if;
            mc6847_css <= doutb(6) xor css_masked;

        -- 4 Colour Semigraphics 6 Only
        when "011" =>
            mc6847_an_s <= '1';
            mc6847_intn_ext <= '1';
            mc6847_inv <= doutb(7);
            mc6847_d <= doutb;
            mc6847_css <= css_masked;

        -- Extended character set, lower case replaces Red Semigraphics
        -- 00-3F - Normal Upper Case
        -- 40-7F - Yellow Semigraphics 6
        -- 80-BF - Inverse Upper Case
        -- C0-FF - Normal Lower Case
        when "100" =>
            mc6847_an_s <= doutb(6) and not doutb(7);
            mc6847_intn_ext <= doutb(6);
            mc6847_inv <= not doutb(6) and doutb(7);
            mc6847_d <= doutb;
            mc6847_css <= css_masked;

        -- Extended character set, lower case replaces Red and Yello Semigraphics
        -- 00-3F - Normal Upper Case
        -- 40-7F - Normal Lower Case
        -- 80-BF - Inverse Upper Case
        -- C0-FF - Inverse Lower Case
        when "101" =>
            mc6847_an_s <= '0';
            mc6847_intn_ext <= '0';
            mc6847_inv <= doutb(7);
            mc6847_d <= doutb;
            mc6847_css <= css_masked;

        -- Extended character set, lower case replaces inverse
        -- 00-3F - Normal Upper Case
        -- 40-7F - Yellow Semigraphics 6 -- Blue
        -- 80-BF - Normal Lower Case
        -- C0-FF - Red Semigraphics 6 
        when "110" =>
            mc6847_an_s <= doutb(6);
            mc6847_intn_ext <= doutb(6);
            mc6847_inv <= '0';
            if (ag_masked = '0' and doutb(7 downto 6) = "10") then
                mc6847_d <= "01" & doutb(5 downto 0);
            else
                mc6847_d <= doutb;
            end if;
            mc6847_css <= css_masked;

        -- Just replace inverse upper case (32 chars) with lower case    
        -- 00-3F - Normal Upper Case
        -- 40-7F - Yellow Semigraphics 6
        -- 80-BF - Lower Case/Inverse Upper Case
        -- C0-FF - Red Semigraphics 6

        when "111" =>
            mc6847_an_s <= doutb(6);
            mc6847_intn_ext <= doutb(6);
            mc6847_inv <= doutb(7) and doutb(5);
            if (ag_masked = '0' and doutb(7 downto 5) = "100") then
                mc6847_d <= "01" & doutb(5 downto 0);
            else
                mc6847_d <= doutb;
            end if;
            mc6847_css <= css_masked;

        -- Default Atom Behaviour        
        -- 00-3F - Normal Upper Case
        -- 40-7F - Yellow Semigraphics 6
        -- 80-BF - Inverse Upper Case
        -- C0-FF - Red Semigraphics 6

        when others =>
            mc6847_an_s <= doutb(6);
            mc6847_intn_ext <= doutb(6);
            mc6847_inv <= doutb(7);
            mc6847_d <= doutb;
            mc6847_css <= css_masked;
        
        end case;
        
    end process;
  
    -- Clock1 is derived by dividing clock32 down by 32
    clock1 <= div32(4);

    -- Signals driving the VRAM
    -- Write just before the rising edge of nWR
    wr    <= '1' when (nWRMS1 = '1' and nWRMS2 = '0') else '0';
    dina  <= DD2;
    addra <= DA2;
    
    -- Signals driving the SID
    -- Kees's Atom SID is at BDC0-BDDF
    -- This one will be at 9DC0-9DDF
    sid_cs <= '1' when (nSIDD = '1' and nMS2 = '0' and DA2(12 downto 5) =  "11111111") or
                       (nSIDD = '0' and nBXXX2 = '0' and DA2(11 downto 5) = "1101110") 
                  else '0';

    sid_we <= '1' when (nSIDD = '1' and nWRMS1 = '1' and nWRMS2 = '0') or
                       (nSIDD = '0' and nWR1 = '1' and nWR2 = '0')
                  else '0';

    sid_di <= DD2;
    sid_addr <= DA2(4 downto 0);
    
    -- Tri-state data back to the Atom
    dout <= sid_do when sid_cs = '1' else douta;
    DD    <= dout when (nMS = '0' and nWR = '1') else (others => 'Z');
    
    -- Output the SID Select Signal so it can be used to disable the bus buffers

    nSIDSEL <= not sid_cs;
    
    -- 1 Bit RGB Video to PL4 Connectors
    OA  <= vga_red(7)    when nPL4 = '0' else '0';
    CHB <= vga_green(7)  when nPL4 = '0' else '0';
    OB  <= vga_blue(7)   when nPL4 = '0' else '0';
    nHS <= vga_hsync     when nPL4 = '0' else '0';
    Y   <= vga_vsync     when nPL4 = '0' else '0';

    -- RGB mapping
    R(0) <= vga_red(7);
    G(1) <= vga_green(7);
    G(0) <= vga_green(6);
    B(0) <= vga_blue(7);
    VSYNC <= vga_vsync;
    HSYNC <= vga_hsync;
    AUDIO <= sid_audio;

    -- Hold internal reset low for two frames after nRST released
    -- This avoids any diaplay glitches
    process (Clock12)
    variable state : std_logic_vector(2 downto 0);
    begin
        if rising_edge(Clock12) then
            if (nRST = '0') then
                state := "000";
            elsif (state = "000" and vga_vsync = '0') then
                state := "001";
            elsif (state = "001" and vga_vsync = '1') then
                state := "010";
            elsif (state = "010" and vga_vsync = '0') then
                state := "011";
            elsif (state = "011" and vga_vsync = '1') then
                state := "100";
            end if;
            mask <= state(2);
        end if;
    end process;
    
    -- During reset, force the 6847 mode select inputs low
    -- (this is necessary to stop the mode changing during reset, as the GODIL has 1.5K pullups)
    gm_masked  <= GM(2 downto 0) when mask = '1' else (others => '0');
    ag_masked  <= AG             when mask = '1' else '0';
    css_masked <= CSS            when mask = '1' else '0';
    
end BEHAVIORAL;

