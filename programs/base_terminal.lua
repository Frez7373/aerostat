-- CCI AEROSTAT CONTROL
-- Base terminal
-- CC:Tweaked

local PROTOCOL = "CCI_AEROSTAT_2026"
local AUTH_CODE = "CCI-AEROSTAT-2026"
local running = true
local terminals = {}
local selectedTerminal = nil
local lastMessage = "Searching for airships..."

local modemName
for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
        local p = peripheral.wrap(name)
        if p and p.isWireless and p.isWireless() then modemName = name break end
    end
end
assert(modemName, "Wireless modem not found")
rednet.open(modemName)

local function updateTerminal(senderId, msg)
    if type(msg) ~= "table" or msg.auth ~= AUTH_CODE then return end
    local id = tonumber(msg.terminalId)
    if not id then return end
    terminals[id] = {
        terminalId = id,
        computerId = senderId,
        height = tonumber(msg.height) or 0,
        speed = tonumber(msg.speed) or 0,
        target = msg.target,
        mode = msg.mode or "UNKNOWN",
        signal = tonumber(msg.signal) or 0,
        home = msg.home,
        lastSeen = os.clock()
    }
    if not selectedTerminal then selectedTerminal = id end
end

local function receiver()
    while running do
        local senderId, msg = rednet.receive(PROTOCOL, 1)
        if senderId then updateTerminal(senderId, msg) end
    end
end

local function discovery()
    while running do
        rednet.broadcast({type = "DISCOVER", auth = AUTH_CODE}, PROTOCOL)
        sleep(4)
    end
end

local function cleanup()
    while running do
        local now = os.clock()
        for id, data in pairs(terminals) do
            if now - data.lastSeen > 12 then
                terminals[id] = nil
                if selectedTerminal == id then selectedTerminal = nil end
            end
        end
        sleep(2)
    end
end

local function sortedIds()
    local ids = {}
    for id in pairs(terminals) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return a < b end)
    return ids
end

local function selected()
    return selectedTerminal and terminals[selectedTerminal] or nil
end

local function sendCommand(msg)
    local t = selected()
    if not t then lastMessage = "Select an airship first"; return false end
    msg.auth = AUTH_CODE
    rednet.send(t.computerId, msg, PROTOCOL)
    lastMessage = "Command sent to airship " .. selectedTerminal
    return true
end

local function askHeight()
    local w, h = term.getSize()
    term.setCursorPos(1, h - 1)
    term.clearLine()
    write("Target height: ")
    local input = read()
    local value = tonumber(input)
    if not value or value < 0 then lastMessage = "Invalid height"; return end
    sendCommand({type = "SET_HEIGHT", height = value})
end

local function chooseTerminal()
    local ids = sortedIds()
    if #ids == 0 then lastMessage = "No airships connected"; return end

    term.clear()
    term.setCursorPos(1, 1)
    print("CCI AEROSTAT - SELECT AIRSHIP")
    print("============================")
    for i, id in ipairs(ids) do
        local t = terminals[id]
        print(string.format("%d. Terminal %d  height %.1f", i, id, t.height or 0))
    end
    print("\nEnter number (or Q): ")
    local input = read()
    if string.lower(input) == "q" then return end
    local index = tonumber(input)
    if index and ids[index] then
        selectedTerminal = ids[index]
        lastMessage = "Selected airship " .. selectedTerminal
    else
        lastMessage = "Invalid selection"
    end
end

local function draw()
    local w, h = term.getSize()
    term.clear(); term.setCursorPos(1, 1)
    print("==============================================")
    print("         CCI AEROSTAT BASE CONTROL")
    print("==============================================")
    print("Connected airships:")
    print("")

    local ids = sortedIds()
    if #ids == 0 then
        print("No airships found.")
    else
        for row, id in ipairs(ids) do
            local t = terminals[id]
            local mark = selectedTerminal == id and ">" or " "
            local line = string.format("%s [%d]  H:%6.1f  V:%6.2f  T:%s  %s", mark, id, t.height or 0, t.speed or 0, tostring(t.target or "-"), tostring(t.mode or "-"))
            if #line > w then line = line:sub(1, w) end
            term.setCursorPos(1, 4 + row)
            write(line)
        end
    end

    local bottom = math.max(11, h - 7)
    term.setCursorPos(1, bottom); print("----------------------------------------------")
    local t = selected()
    term.setCursorPos(1, bottom + 1)
    print("Selected: " .. (t and ("airship " .. selectedTerminal) or "none"))
    term.setCursorPos(1, bottom + 2)
    print("Height: " .. (t and string.format("%.1f", t.height or 0) or "-") .. "   Target: " .. (t and tostring(t.target or "-") or "-"))
    term.setCursorPos(1, bottom + 3)
    print("Speed : " .. (t and string.format("%.2f", t.speed or 0) or "-") .. "   Burner: " .. (t and tostring(t.signal or 0) or "-") .. "/15")
    term.setCursorPos(1, bottom + 5)
    print("[S] Height   [L] Lower   [H] Hold   [C] Calibrate")
    term.setCursorPos(1, bottom + 6)
    print("[A] Select airship   [Q] Exit")
    term.setCursorPos(1, h)
    write(lastMessage)
end

local function ui()
    while running do
        draw()
        local event, p1, p2, p3 = os.pullEvent()

        if event == "char" then
            local c = string.lower(p1)
            if c == "s" then askHeight()
            elseif c == "l" then sendCommand({type = "LOWER"})
            elseif c == "h" then sendCommand({type = "HOLD"})
            elseif c == "c" then sendCommand({type = "CALIBRATE_HOME"})
            elseif c == "a" then chooseTerminal()
            end
        elseif event == "key" and p1 == keys.q then
            running = false
        elseif event == "mouse_click" then
            local x, y = p2, p3
            local ids = sortedIds()
            if y >= 5 and y < 5 + #ids then
                selectedTerminal = ids[y - 4]
                lastMessage = "Selected airship " .. selectedTerminal
            end
            local _, h = term.getSize()
            local bottom = math.max(11, h - 7)
            if y == bottom + 5 then
                if x <= 13 then askHeight()
                elseif x <= 25 then sendCommand({type = "LOWER"})
                elseif x <= 36 then sendCommand({type = "HOLD"})
                elseif x <= 50 then sendCommand({type = "CALIBRATE_HOME"})
            elseif y == bottom + 6 and x <= 22 then
                chooseTerminal()
            end
        end
    end
end

parallel.waitForAll(receiver, discovery, cleanup, ui)
