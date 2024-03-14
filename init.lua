-- I2C pins
sda = 6 -- SDA Pin
scl = 5 -- SCL Pin

-- Initialize the I2C
print("Initializing I2C...")
sla = 0x3C
i2c.setup(0, sda, scl, i2c.SLOW)

-- Initialize the display
disp = u8g2.ssd1306_i2c_128x64_noname(0, sla)
disp:setFont(u8g2.font_6x10_tf)
disp:setDrawColor(1)
disp:setContrast(255)
disp:setPowerSave(0)
disp:setFontMode(0);

-- Function to start the programmer.lua file after a delay
local function startProgrammer()
    print("\nStarting programmer.lua file...")
    dofile("programmer.lua")
end

-- Create a timer and set it to trigger the startProgrammer function after 15 seconds
local timer = tmr.create()
timer:alarm(15000, tmr.ALARM_SINGLE, startProgrammer)
