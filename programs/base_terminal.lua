-- CCI AEROSTAT CONTROL
-- Base terminal
-- CC:Tweaked

local PROTOCOL = "CCI_AEROSTAT_2026"
local AUTH_CODE = "CCI-AEROSTAT-2026"
local running = true
local terminals = {}
local selectedTerminal = nil
local lastMessage = "Searching for airships..."
local refreshTimer = nil

local modemName
for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
        local p = peripheral.wrap(name)
        if p and p.isWireless and p.isWireless() then
            modemName = name
            break
        end
    end
end

assert(modemName, "Wireless modem not found")
rednet.open(modemName)

local function updateTerminal(senderId, msg)
    if type(msg) ~= "table" then return end
    if msg.auth ~= AUTH_CODE then return end

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

    if not selectedTerminal then
        selectedTerminal = id
    end
end

local function sendDiscovery()
    rednet.broadcast({
        type = "DISCOVER",
        auth = AUTH_CODE
    }, PROTOCOL)
end

local function cleanup()
    local now = os.clock()

    for id, data in pairs(terminals) do
        if now - data.lastSeen > 12 then
            terminals[id] = nil

            if selectedTerminal == id then
                selectedTerminal = nil
            end
        end
    end
end

local function getIds()
    local ids = {}

    for id in pairs(terminals) do
        ids[#ids + 1] = id
    end

    table.sort(ids, function(a, b)
        return a < b
    end)

    return ids
end

local function getSelected()
    if selectedTerminal then
        return terminals[selectedTerminal]
    end

    return nil
end

local function sendCommand(message)
    local terminal = getSelected()

    if not terminal then
        lastMessage = "Select an airship first"
        return
    end

    message.auth = AUTH_CODE

    rednet.send(
        terminal.computerId,
        message,
        PROTOCOL
    )

    lastMessage = "Command sent to airship " .. tostring(selectedTerminal)
end

local function askHeight()
    local _, height = term.getSize()

    term.setCursorPos(1, height - 1)
    term.clearLine()
    write("Target height: ")

    local input = read()
    local value = tonumber(input)

    if not value or value < 0 then
        lastMessage = "Invalid height"
        return
    end

    sendCommand({
        type = "SET_HEIGHT",
        height = value
    })
end

local function selectAirship()
    local ids = getIds()

    if #ids == 0 then
        lastMessage = "No airships connected"
        return
    end

    term.clear()
    term.setCursorPos(1, 1)

    print("CCI AEROSTAT - SELECT AIRSHIP")
    print("=============================")
    print("")

    for i, id in ipairs(ids) do
        local t = terminals[id]

        print(string.format(
            "%d. Terminal %d   height %.1f",
            i,
            id,
            t.height or 0
        ))
    end

    print("")
    write("Select row or terminal ID (Q = cancel): ")

    local input = read()

    if string.lower(input) == "q" then
        return
    end

    local value = tonumber(input)

    if value then
        value = math.floor(value)

        -- Prefer an exact terminal ID.
        if terminals[value] then
            selectedTerminal = value
            lastMessage = "Selected airship " .. tostring(selectedTerminal)
            return
        end

        -- Otherwise allow selecting by row number.
        if ids[value] then
            selectedTerminal = ids[value]
            lastMessage = "Selected airship " .. tostring(selectedTerminal)
            return
        end
    end

    lastMessage = "Invalid selection"
end

local function draw()
    local w, h = term.getSize()

    term.clear()
    term.setCursorPos(1, 1)

    print("==============================================")
    print("         CCI AEROSTAT BASE CONTROL")
    print("==============================================")
    print("Connected airships:")
    print("")

    local ids = getIds()

    if #ids == 0 then
        print("No airships found.")
        print("")
        print("Waiting for STATUS packets...")
    else
        for row, id in ipairs(ids) do
            local t = terminals[id]
            local marker = " "

            if selectedTerminal == id then
                marker = ">"
            end

            local text = string.format(
                "%s [%d] H:%6.1f V:%6.2f T:%s %s",
                marker,
                id,
                t.height or 0,
                t.speed or 0,
                tostring(t.target or "-"),
                tostring(t.mode or "-")
            )

            if #text > w then
                text = text:sub(1, w)
            end

            term.setCursorPos(1, 4 + row)
            write(text)
        end
    end

    local bottom = math.max(11, h - 7)

    term.setCursorPos(1, bottom)
    print("----------------------------------------------")

    local selected = getSelected()

    term.setCursorPos(1, bottom + 1)
    if selected then
        print("Selected: airship " .. tostring(selectedTerminal) .. "  PC:" .. tostring(selected.computerId))
    else
        print("Selected: none")
    end

    term.setCursorPos(1, bottom + 2)
    if selected then
        print(
            "Height: " .. string.format("%.1f", selected.height or 0) ..
            "   Target: " .. tostring(selected.target or "-")
        )
    else
        print("Height: -   Target: -")
    end

    term.setCursorPos(1, bottom + 3)
    if selected then
        print(
            "Speed : " .. string.format("%.2f", selected.speed or 0) ..
            "   Burner: " .. tostring(selected.signal or 0) .. "/15"
        )
    else
        print("Speed : -   Burner: -")
    end

    term.setCursorPos(1, bottom + 5)
    print("[S] Height  [L] Lower  [H] Hold  [C] Calibrate")

    term.setCursorPos(1, bottom + 6)
    print("[A] Select  [Q] Exit")

    term.setCursorPos(1, h)
    term.clearLine()
    write(lastMessage)
end

local function handleMouse(x, y)
    local ids = getIds()

    if y >= 5 and y < 5 + #ids then
        selectedTerminal = ids[y - 4]
        lastMessage = "Selected airship " .. tostring(selectedTerminal)
        return
    end

    local _, h = term.getSize()
    local bottom = math.max(11, h - 7)

    if y == bottom + 5 then
        if x <= 13 then
            askHeight()
        elseif x <= 25 then
            sendCommand({type="LOWER"})
        elseif x <= 36 then
            sendCommand({type="HOLD"})
        elseif x <= 50 then
            sendCommand({type="CALIBRATE_HOME"})
        end
    elseif y == bottom + 6 and x <= 22 then
        selectAirship()
    end
end

-- Start discovery immediately.
sendDiscovery()

draw()

while running do
    refreshTimer = os.startTimer(4)

    local event, p1, p2, p3 = os.pullEventRaw()

    if event == "rednet_message" then
        -- CC:Tweaked event format:
        -- rednet_message, senderId, message, protocol
        local senderId = p1
        local message = p2
        local protocol = p3

        if protocol == PROTOCOL then
            updateTerminal(senderId, message)
            lastMessage = "Status received from PC " .. tostring(senderId)
            draw()
        end

    elseif event == "timer" and p1 == refreshTimer then
        sendDiscovery()
        cleanup()
        draw()

    elseif event == "char" then
        local c = string.lower(p1)

        if c == "s" then
            askHeight()
            draw()

        elseif c == "l" then
            sendCommand({type="LOWER"})
            draw()

        elseif c == "h" then
            sendCommand({type="HOLD"})
            draw()

        elseif c == "c" then
            sendCommand({type="CALIBRATE_HOME"})
            draw()

        elseif c == "a" then
            selectAirship()
            draw()
        end

    elseif event == "key" then
        if p1 == keys.q then
            running = false
        end

    elseif event == "mouse_click" then
        handleMouse(p2, p3)
        draw()
    end
end

rednet.close(modemName)
term.clear()
term.setCursorPos(1, 1)
print("CCI Aerostat base terminal stopped.")
