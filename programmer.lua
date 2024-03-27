--Shift Register Pins
local sData = 2 -- GPIO4
local shiftClk = 4 -- GPIO2, goes to all 4 shift registers
local addrLatch = 3 -- GPIO0
local dataLatch = 0 -- GPIO1
local dataOE = 2


-- Control signals of ROM (active low)
local WE = 7 -- GPIO13
local OE = 1 -- GPIO5

-- Set the pin mode to output
--gpio.mode(sData, gpio.OUTPUT)
gpio.mode(shiftClk, gpio.OUTPUT)
gpio.mode(addrLatch, gpio.OUTPUT)
gpio.mode(dataLatch, gpio.OUTPUT)
-- Output mode for serial data
gpio.mode(sData, gpio.OUTPUT)

--gpio.mode(WE, gpio.OUTPUT)
gpio.mode(OE, gpio.OUTPUT)
--gpio.mode(CE, gpio.OUTPUT)

-- Define the pin number for GPIO10 (which corresponds to D10 on NodeMCU)
local gpioPin = 10 -- GPIO10 is represented as pin 1 on NodeMCU

-- Set the pin mode to OUTPUT
--gpio.mode(gpioPin, gpio.OUTPUT)

-- Initialize the ADC
adc.force_init_mode(adc.INIT_ADC)

-- Function to perform bitwise AND operation without using the 'bit' library
local function bitwise_and(a, b)
    local result = 0
    local bit_mask = 1

    -- Iterate through each bit of the binary representation of 'a' and 'b'
    while a > 0 and b > 0 do
        -- Check if the least significant bit of 'a' and 'b' is 1
        if a % 2 == 1 and b % 2 == 1 then
            -- Set the corresponding bit of 'result' to 1
            result = result + bit_mask
        end

        -- Right shift 'a' and 'b' to process the next bit
        a = math.floor(a / 2)
        b = math.floor(b / 2)

        -- Left shift the bit mask to process the next bit position
        bit_mask = bit_mask * 2
    end

    return result
end

local function init()
    --gpio.write(CE, gpio.HIGH) -- Disable Chip Enable
    gpio.write(OE, gpio.HIGH) -- Disable Output Enable
    gpio.write(WE, gpio.HIGH) -- Disable Write Enable
    gpio.write(dataOE, gpio.HIGH) -- Disable Output of data register. Sdata is high

    gpio.write(addrLatch, gpio.LOW) -- Disable Address Latch Enable
    gpio.write(shiftClk, gpio.LOW) -- Disable the Shift Register Clock
    gpio.write(dataLatch, gpio.HIGH) -- Disable Parallel Data Load
end

-- Function to shift a single bit into the shift registers
-- Accepts a boolean bit
local function shift_bit(bit)
    -- Check if the input is a numerical value
    if type(bit) ~= "number" or (bit ~= 0 and bit ~= 1) then
        print("Error: Input must be a numerical value of 0 or 1.")
        return
    end

    -- Set serial data according to the bit value
    if bit == 1 then
        gpio.write(sData, gpio.HIGH)
    else
        gpio.write(sData, gpio.LOW)
    end

    tmr.delay(1000)
    -- Cycle shift registers
    gpio.write(shiftClk, gpio.HIGH)
    tmr.delay(1000) -- wait 1000 us
    gpio.write(shiftClk, gpio.LOW)
    tmr.delay(1000)

    -- Reset to high so OE of data is not enabled
    --gpio.write(sData, gpio.HIGH)

end

-- Function to perform a series of shifts in order to load and latch an address into registers
local function load_addr_reg(byte1, byte2, byte3)
    -- Verify that three bytes are provided
    if type(byte1) == "number" and type(byte2) == "number" and type(byte3) == "number" then
        -- Combine the three bytes into a single numerical value (address)
        local numAddr = (byte1 * 65536) + (byte2 * 256) + byte3
        
        -- Truncate the address to 17 bits (only the 17 address bits are allowed)
        numAddr = bitwise_and(numAddr, 0x1FFFF)

        -- Iterate over each bit of the address (17 bits)
        for i = 15, 0, -1 do
            -- Extract the i-th bit from the address
            local bit = bitwise_and(math.floor(numAddr / (2^i)), 0x01)
            
            -- Shift the bit into the shift registers
            shift_bit(bit)
        end

        -- Latch the address shift registers
        gpio.write(addrLatch, gpio.HIGH)
        tmr.delay(1000) -- wait 10 us
        gpio.write(addrLatch, gpio.LOW)
        tmr.delay(1000)

        -- Set the serial Data wire to the 17th bit value (A16)
        local bit = bitwise_and(math.floor(numAddr / (2^16)), 0x01)
        shift_bit(bit) -- Shift the bit into the LSB
        for i = 14, 0, -1 do
            shift_bit(0) -- Shift bits 15 times to get the LSB to the MSB
        end
        tmr.delay(1000)

    else
        print("Error: Three input bytes are required.")
        return
    end
end

-- Function to perform a series of shifts in order to load and latch a byte into data register
local function load_data_reg(byte)
    if type(byte) == "string" and string.len(byte) == 1 then

        -- Convert the byte string to a numerical byte value
        local numByte = string.byte(byte)

        -- Iterate over each bit of the byte
        for i = 7, 0, -1 do
            -- Extract the i-th bit from the byte
            local bit = math.floor(numAddr / 2^i) % 2
            
            -- Shift the bit into the shift registers
            shift_bit(bit)
        end

        -- Latch the data shift register
        gpio.write(dataLatch, gpio.LOW)
        tmr.delay(1000) -- wait 1000 us
        gpio.write(dataLatch, gpio.HIGH)
    else
        print("Error: Input byte must be a string of exactly one byte.")
    end
end

-- Returns a byte
local function load_read_data()

    local receivedByte = 0

    -- Make sure data input reg is disabled
    gpio.write(dataOE, gpio.HIGH)

    -- Enable Output on ROM
    gpio.write(OE, gpio.LOW)
    tmr.delay(10)

    -- Latch current output from ROM
    gpio.write(dataLatch, gpio.LOW)
    tmr.delay(1000) -- wait 1 us
    gpio.write(dataLatch, gpio.HIGH)
    tmr.delay(1000)

    -- Disable Output on ROM
    gpio.write(OE, gpio.HIGH)

    -- Read in each bit of the byte one at a time
    for i = 7, 0, -1 do

        tmr.delay(100) -- wait 1 us between bits

        -- Read the data pin and shift the received bit into the byte
        local dataBit = 0
        local analogValue = adc.read(0)

        if analogValue >= (1024 / 2) then
            dataBit = 1
        else 
            dataBit = 0
        end

        receivedByte = receivedByte + (dataBit * 2^i)

        -- Cycle the serial data clock
        gpio.write(shiftClk, gpio.HIGH)
        tmr.delay(1000) -- wait 1000 us
        gpio.write(shiftClk, gpio.LOW)
    end

    return receivedByte
end

-- Function to write a single byte
-- Accepts a single byte as a char
-- Accepts a 3-byte address as a string
local function write_byte(byte, addr)

    -- Verify a valid byte is given and load it into the data register
    if type(byte) == "string" and string.len(byte) == 1 then
        load_data_reg(byte)
    else
        print("Error: Input byte must be a string of exactly one byte.")
        return
    end

    -- Verify a valid address is given and load it into the address register
    -- NOTE: the MSB of the address is not latched, it is stored in the shift registers so ensure that
    -- NOTE: the address is also loaded AFTER the data is loaded
    if type(addr) == "string" and string.len(addr) == 9 then
        -- Parse the hexadecimal bytes and convert them to integers
        local byte1 = tonumber(string.sub(addr, 3, 4), 16)
        local byte2 = tonumber(string.sub(addr, 6, 7), 16)
        local byte3 = tonumber(string.sub(addr, 9, 10), 16)
        
        load_addr_reg(byte1, byte2, byte3)
    else
        print("Error: Address must be a string of exactly 3 bytes.")
        return
    end

    gpio.write(dataOE, gpio.LOW) -- Enable data register output

    tmr.delay(1) -- wait 1 us

    -- Chip Enable
    --gpio.write(CE, gpio.HIGH)
    -- Write Enable
    gpio.write(WE, gpio.HIGH)
    tmr.delay(1) -- wait 1 us
    -- Disable Write
    gpio.write(WE, gpio.HIGH)
    -- Disable Chip
    --gpio.write(CE, gpio.HIGH)

    gpio.write(dataOE, gpio.HIGH) -- Disable data register output


    print("Byte written:", byte)
end

-- Returns a byte
local function read_byte(byte1, byte2, byte3)

    tmr.delay(1000) -- wait 1 ms

    -- Verify that three bytes are provided
    if type(byte1) == "number" and type(byte2) == "number" and type(byte3) == "number" then
        -- Load the address register with the provided bytes
        load_addr_reg(byte1, byte2, byte3)
    else
        print("Error: Three numerical values representing bytes are required.")
        return
    end

    -- Logic to read a byte
    return load_read_data()
end

-- Function to read bytes from address 0x000000 to 0x01FFFF and save to a file
local function read_and_save_bytes(filename)
    -- Open the file in binary write mode
    local file = file.open(filename, "w+")
    if not file then
        print("Error: Unable to open file for writing.")
        return
    end

    -- Iterate over addresses from 0x000000 to 0x01FFFF
    for addr = 0x000000, 0x01FFFF do

        local hexString = string.format("%X", addr)
        print("Read addr:", hexString)

        -- Calculate the byte address components
        local byte1 = math.floor(addr / 0x10000) % 0x100
        local byte2 = math.floor(addr / 0x100) % 0x100
        local byte3 = addr % 0x100

        -- Read a byte from the address (assuming read_byte function is defined elsewhere)
        local byte = read_byte(byte1, byte2, byte3)

        -- Write the byte to the file
        file.write(string.char(byte))
    end

    -- Close the file
    file.close()
    print("Bytes read and saved to file:", filename)
end




-- Check for data file and create one if it doesnt exist
print("Checking for existing data.txt...")
if(file.exists("data.txt")) then
    print("Found data.txt")
end


print("Reading 0x014A4A")
local hexString = string.format("%X", read_byte(0x01, 0x4A, 0x4A))
print("Value:", hexString)

print("Reading 0x011FF1")
hexString = string.format("%X", read_byte(0x01, 0x1F, 0xF1))
print("Value:", hexString)

print("Reading 0x015555")
hexString = string.format("%X", read_byte(0x01, 0x55, 0x55))
print("Value:", hexString)

print("Reading 0x00AAAA")
hexString = string.format("%X", read_byte(0x00, 0xAA, 0xAA))
print("Value:", hexString)

-- Read all bytes into a file
read_and_save_bytes("data.bin")
