
min = 10
max = 44
idx = 10
function loop()
    print("Looping...")
    disp:clearBuffer()
    disp:drawFrame(0,0,128,64)
    disp:drawFrame(5,5,118,54)
    disp:drawStr(30, idx, "Hello, World!")
    disp:updateDisplay()

    if (idx < max) then
        idx = idx + 1
    else
        idx = 10
    end
end


print("Initializing display...")
loop()
tmr.create():alarm(10000, tmr.ALARM_AUTO, function()
    loop()
end)
