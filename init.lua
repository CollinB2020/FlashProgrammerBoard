
-- Function to start the programmer.lua file after a delay
local function startProgrammer()
    print("\nStarting programmer.lua file...")
    dofile("programmer.lua")
end

-- Create a timer and set it to trigger the startProgrammer function after 15 seconds
local timer = tmr.create()
timer:alarm(20000, tmr.ALARM_SINGLE, startProgrammer)
