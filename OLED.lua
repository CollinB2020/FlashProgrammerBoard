-- I2C pins
sda = 6 -- SDA Pin
scl = 5 -- SCL Pin



local function init()
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

    -- Write to the display
    disp:clearBuffer()
    disp:drawFrame(0,0,128,64)
    disp:drawFrame(4,4,120,56)
    disp:drawStr(6, 14, "Initializing...")
    disp:updateDisplay()
end

-- Function to write value to display
local function show_read_byte(x)
    -- Write value to the display
    disp:clearBuffer()
    disp:drawFrame(0,0,128,64)
    disp:drawFrame(4,4,120,56)
    disp:drawStr(6, 14, "Reading from: \n\t" .. tostring(x))
    disp:updateDisplay()
end

return {
    init = init,
    show_read_byte = show_read_byte
}