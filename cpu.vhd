-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2023 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): Boris Hatala <xhatal02>
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic;                      -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'

   -- stavove signaly
   READY    : out std_logic;                      -- hodnota 1 znamena, ze byl procesor inicializovan a zacina vykonavat program
   DONE     : out std_logic                       -- hodnota 1 znamena, ze procesor ukoncil vykonavani programu (narazil na instrukci halt)
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

--PROGRAM_COUNTER--------------------------------------------------------------

    signal pc_register : std_logic_vector (12 downto 0);
    signal pc_inc : std_logic;
    signal pc_dec : std_logic;

--POINTER_COUNTER--------------------------------------------------------------

    signal ptr_register : std_logic_vector (12 downto 0);
    signal ptr_inc : std_logic;
    signal ptr_dec : std_logic;

--WHILE_LOOP_COUNTER-----------------------------------------------------------

    signal cnt_register : std_logic_vector (7 downto 0);
    signal cnt_inc : std_logic;
    signal cnt_dec : std_logic;

--MULTIPLEXOR_1----------------------------------------------------------------

    signal mx_1_select : std_logic;

--MULTIPLEXOR_2----------------------------------------------------------------

    signal mx_2_select : std_logic_vector (1 downto 0);

--STATES-----------------------------------------------------------------------

    type fsm_states is (s_init, s_fetch, s_decode,
                    s_ptr_inc, s_ptr_dec,
                    s_cell_inc, s_cell_inc2,
                    s_cell_dec, s_cell_dec2,
                    s_print, s_print2,
                    s_scan, s_scan2,
                    s_while,
                    s_break,
                    s_other, s_stop
                    );

    signal current_state : fsm_states := s_init;
    signal next_state : fsm_states;

begin

--PROGRAM_COUNTER--------------------------------------------------------------

    program_counter : process (CLK, RESET) begin 
        if RESET = '1' then 
            pc_register <= (others => '0');
        elsif rising_edge(CLK) then
            if pc_inc = '1' then
                pc_register <= pc_register + 1;
            elsif pc_dec = '1' then
                pc_register <= pc_register - 1;
            end if;
        end if;
    end process program_counter;        
    
--POINTER_COUNTER--------------------------------------------------------------

    pointer_counter : process (CLK, RESET) begin 
        if RESET = '1' then 
            ptr_register <= (others => '0');
        elsif rising_edge(CLK) then
            if ptr_inc = '1' then
                ptr_register <= ptr_register + 1;
            elsif ptr_dec = '1' then
                ptr_register <= ptr_register - 1;
            end if;
        end if;
    end process pointer_counter;

--MULTIPLEXOR_1--------------------------------------------------------------

    with mx_1_select select
    DATA_ADDR <= pc_register when '0',
            ptr_register when '1',
            (others => '0') when others;

--MULTIPLEXOR_2--------------------------------------------------------------

    with mx_2_select select
        DATA_WDATA <= IN_DATA when "00",
                DATA_RDATA + 1 when "01",
                DATA_RDATA - 1 when "10",
                (others => '0') when others;

--FINITE_STATE_MACHINE--------------------------------------------------------------

    current_state_logic : process (CLK, RESET) begin
        if RESET = '1' then
            current_state <= s_init;
        elsif rising_edge(CLK) then
            if EN = '1' then
                current_state <= next_state;
            end if;
        end if;
    end process current_state_logic;

    next_state_logic : process (current_state, next_state, DATA_RDATA, IN_VLD, OUT_BUSY, EN) begin
        --default state
        --pc
        pc_inc <= '0';
        pc_dec <= '0';
        --ptr
        ptr_inc <= '0';
        ptr_dec <= '0';
        --mux
        mx_1_select <= '0';
        mx_2_select <= "00";
        --RAM
        DATA_EN <= '0';
        DATA_RDWR <= '0';
        --I/O
        IN_REQ <= '0';
        OUT_WE <= '0';
        READY <= '0';
        DONE <= '0';

        case current_state is
            when s_init =>
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                mx_1_select <= '1'; 

                if DATA_RDATA = x"40" then  
                    READY <= '1';
                    next_state <= s_fetch;
                else    
                    ptr_inc <= '1';
                    next_state <= s_init;
                end if;
            
            when s_fetch =>
                mx_1_select <= '0';         
                DATA_EN <= '1';             
                DATA_RDWR <= '0';
                
                next_state <= s_decode;

            when s_decode =>
                case DATA_RDATA is 
                    -- pointer increment >
                    when x"3E" =>
                        next_state <= s_ptr_inc;
                    -- pointer decrement <
                    when x"3C" =>
                        next_state <= s_ptr_dec;
                    -- cell increment +
                    when x"2B" =>
                        next_state <= s_cell_inc;
                    -- cell decrement -
                    when x"2D" =>
                        next_state <= s_cell_dec;
                    -- print .
                    when x"2E" =>
                        next_state <= s_print;
                    -- input ,
                    when x"2C" =>
                        next_state <= s_scan;
                    -- break ~
                    when x"7E" =>
                        next_state <= s_break;
                    -- halt @
                    when x"40" =>
                        next_state <= s_stop;
                    when others =>
                        pc_inc <= '1';
                        next_state <= s_fetch;
                end case;
                
            --pointer inc >
            when s_ptr_inc =>
                pc_inc <= '1';
                ptr_inc <= '1';

                next_state <= s_fetch;

            --pointer dec <
            when s_ptr_dec =>
                pc_inc <= '1';
                ptr_dec <= '1';

                next_state <= s_fetch;

            --cell inc +
            when s_cell_inc =>
                mx_1_select <= '1';
                DATA_EN <= '1';
                DATA_RDWR <= '0';

                next_state <= s_cell_inc2;

            when s_cell_inc2 =>
                mx_1_select <= '1'; 
                DATA_EN <= '1';
                mx_2_select <= "01"; 
                DATA_RDWR <= '1';
                pc_inc <= '1';
                next_state <= s_fetch;

            --cell dec -
            when s_cell_dec =>
                mx_1_select <= '1';
                DATA_EN <= '1';
                DATA_RDWR <= '0';

                next_state <= s_cell_dec2;

            when s_cell_dec2 =>
                mx_1_select <= '1'; 
                DATA_EN <= '1';
                mx_2_select <= "10"; 
                DATA_RDWR <= '1';
                pc_inc <= '1';
                next_state <= s_fetch;

            --print cell .
            when s_print =>
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                mx_1_select <= '1';

                next_state <= s_print2;
            
            when s_print2 =>
                if OUT_BUSY = '1' then
                    mx_1_select <= '1';
                    DATA_EN <= '1';

                    next_state <= s_print2;
                elsif OUT_BUSY = '0' then
                    OUT_DATA <= DATA_RDATA;
                    OUT_WE <= '1';
                    pc_inc <= '1';
                    next_state <= s_fetch;
                end if;
            
            -- input ,
            when s_scan =>
                    IN_REQ <= '1';
                    if IN_VLD = '1' then
                        next_state <= s_scan2;
                    else
                        next_state <= s_scan;
                    end if;
            
            when s_scan2 =>
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                mx_1_select <= '1';
                mx_2_select <= "00";
                pc_inc <= '1';

                next_state <= s_fetch;
            
            -- break ~
            when s_break => 
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                mx_1_select <= '0'; 

                if DATA_RDATA = x"5D" then  --wait for ] else increment PC
                    next_state <= s_fetch;
                else    
                    pc_inc <= '1';
                    next_state <= s_break;
                end if;
                        

            when s_stop =>
            READY <= '1';
            DONE <= '1';
        
            when others => null;
        end case;
    end process next_state_logic;
end behavioral;