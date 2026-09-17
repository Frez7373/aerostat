-- CCI AEROSTAT CONTROL
-- Airship terminal
-- CC:Tweaked + Create Aeronautics/Create: Avionics

local CONFIG_FILE = "/aerostat/config"
local PROTOCOL = "CCI_AEROSTAT_2026"
local AUTH_CODE = "CCI-AEROSTAT-2026"

local TERMINAL_ID = 1
local BURNER_SIDE = "left"
local VENT_SIDE = "right"
local VENT_ENABLED = true

local HEIGHT_DEADBAND = 1.0
local MAX_ASCEND_SPEED = 1.2
local MAX_DESCEND_SPEED = 1.0
local CONTROL_INTERVAL = 0.25
local LINK_TIMEOUT = 15

local VALID_SIDES = {
    top=true,
    bottom=true,
    left=true,
    right=true,
    front=true,
    back=true
}

local function loadConfig()
    if not fs.exists(CONFIG_FILE) then return end

    local h = fs.open(CONFIG_FILE, "r")
    if not h then return end

    local data = textutils.unserialize(h.readAll())
    h.close()

    if type(data) ~= "table" then return end

    TERMINAL_ID = tonumber(data.terminalId) or TERMINAL_ID

    -- New configuration format.
    if VALID_SIDES[data.burnerSide] then
        BURNER_SIDE = data.burnerSide
    elseif VALID_SIDES[data.redstoneSide] then
        -- Backwards compatibility with version 1.0.0.
        BURNER_SIDE = data.redstoneSide
    end

    if data.ventSide == false or data.ventSide == "none" then
        VENT_ENABLED = false
    elseif VALID_SIDES[data.ventSide] then
        VENT_SIDE = data.ventSide
        VENT_ENABLED = true
    end
end

local function saveConfig()
    fs.makeDir("/aerostat")

    local data = {
        terminalId = TERMINAL_ID,
        burnerSide = BURNER_SIDE,
        ventSide = VENT_ENABLED and VENT_SIDE or "none"
    }

    local h = fs.open(CONFIG_FILE, "w")
    if h then
        h.write(textutils.serialize(data))
        h.close()
    end
end

loadConfig()

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

local altitudeSensor = peripheral.find("altitude_sensor")
assert(altitudeSensor, "altitude_sensor not found")

local currentHeight = 0
local verticalSpeed = 0
local targetHeight = nil
local mode = "HOLD"
local burnerSignal = redstone.getAnalogOutput(BURNER_SIDE)
local ventSignal = VENT_ENABLED and redstone.getAnalogOutput(VENT_SIDE) or 0
local lastCommandTime = os.clock()
local homeHeight = nil
local running = true
local HOME_FILE = "/aerostat/home_height"

if fs.exists(HOME_FILE) then
    local h = fs.open(HOME_FILE, "r")
    if h then
        homeHeight = tonumber(h.readAll())
        h.close()
    end
end

local function saveHome()
    fs.makeDir("/aerostat")

    local h = fs.open(HOME_FILE, "w")
    if h then
        h.write(tostring(homeHeight or 0))
        h.close()
    end
end

local function sensors()
    local ok, value = pcall(function()
        return altitudeSensor.getHeight()
    end)
    if ok and type(value) == "number" then
        currentHeight = value
    end

    ok, value = pcall(function()
        return altitudeSensor.getVerticalSpeed()
    end)
    if ok and type(value) == "number" then
        verticalSpeed = value
    end
end

local function setBurner(value)
    value = math.floor(value + 0.5)
    if value < 0 then value = 0 end
    if value > 15 then value = 15 end

    burnerSignal = value
    redstone.setAnalogOutput(BURNER_SIDE, value)
end

local function setVent(value)
    if not VENT_ENABLED then
        ventSignal = 0
        return
    end

    value = math.floor(value + 0.5)
    if value < 0 then value = 0 end
    if value > 15 then value = 15 end

    ventSignal = value
    redstone.setAnalogOutput(VENT_SIDE, value)
end

local function stopVerticalControl()
    setBurner(0)
    setVent(0)
end

local function status()
    sensors()

    return {
        type = "STATUS",
        auth = AUTH_CODE,
        terminalId = TERMINAL_ID,
        height = currentHeight,
        speed = verticalSpeed,
        target = targetHeight,
        mode = mode,
        signal = burnerSignal,
        ventSignal = ventSignal,
        home = homeHeight,
        ventEnabled = VENT_ENABLED
    }
end

local function controlHeight()
    sensors()

    if not targetHeight then
        stopVerticalControl()
        return
    end

    local error = targetHeight - currentHeight
    local distance = math.abs(error)

    -- At target: remove excess vertical speed, then hold.
    if distance <= HEIGHT_DEADBAND then
        if verticalSpeed > 0.15 then
            setVent(math.min(15, ventSignal + 2))
            setBurner(math.max(0, burnerSignal - 2))
        elseif verticalSpeed < -0.15 then
            setVent(math.max(0, ventSignal - 2))
            setBurner(math.min(15, burnerSignal + 2))
        else
            if burnerSignal > 0 then setBurner(burnerSignal - 1) end
            if ventSignal > 0 then setVent(ventSignal - 1) end
        end
        return
    end

    -- ASCENDING: close the vent and use the burner.
    if error > 0 then
        setVent(0)

        local desiredSpeed = math.min(MAX_ASCEND_SPEED, math.max(0.25, distance * 0.08))

        if verticalSpeed < desiredSpeed - 0.15 then
            local boost = 2
            if distance > 30 then boost = 3 end
            setBurner(burnerSignal + boost)
        elseif verticalSpeed > desiredSpeed + 0.20 then
            setBurner(burnerSignal - 2)
        elseif burnerSignal < 1 then
            setBurner(1)
        end

        return
    end

    -- DESCENDING: shut the burner and open the steam vent.
    -- A burner only adds lifting gas, so reducing its signal cannot actively
    -- remove gas already inside the balloon. The vent is what makes descent
    -- controllable.
    setBurner(0)

    if not VENT_ENABLED then
        setVent(0)
        return
    end

    local desiredSpeed = -math.min(MAX_DESCEND_SPEED, math.max(0.25, distance * 0.08))

    if verticalSpeed > desiredSpeed + 0.15 then
        local boost = 3
        if distance > 30 then boost = 5 end
        setVent(ventSignal + boost)
    elseif verticalSpeed < desiredSpeed - 0.20 then
        setVent(ventSignal - 2)
    end

    -- LAND mode: stronger venting while still far from home,
    -- then close the vent near the landing altitude.
    if mode == "LAND" then
        if distance > 20 and verticalSpeed > -0.9 then
            setVent(math.max(ventSignal, 12))
        elseif distance <= 5 then
            setVent(math.min(ventSignal, 5))
        end
    end
end

local function receiver()
    while running do
        local senderId, msg = rednet.receive(PROTOCOL, 1)

        if senderId and type(msg) == "table" and msg.auth == AUTH_CODE then
            lastCommandTime = os.clock()

            if msg.type == "DISCOVER" or msg.type == "PING" then
                rednet.send(senderId, status(), PROTOCOL)

            elseif msg.type == "SET_HEIGHT" then
                local h = tonumber(msg.height)

                if h and h >= 0 then
                    targetHeight = h
                    mode = "HOLD"
                    rednet.send(senderId, status(), PROTOCOL)
                end

            elseif msg.type == "LOWER" then
                if homeHeight then
                    targetHeight = homeHeight
                    mode = "LAND"
                end

                rednet.send(senderId, status(), PROTOCOL)

            elseif msg.type == "HOLD" then
                sensors()
                targetHeight = currentHeight
                mode = "HOLD"
                rednet.send(senderId, status(), PROTOCOL)

            elseif msg.type == "CALIBRATE_HOME" then
                sensors()
                homeHeight = currentHeight
                saveHome()
                targetHeight = currentHeight
                mode = "HOLD"
                rednet.send(senderId, status(), PROTOCOL)

            elseif msg.type == "SET_CONFIG" then
                local newId = tonumber(msg.terminalId)
                local newBurnerSide = msg.burnerSide or msg.redstoneSide
                local newVentSide = msg.ventSide

                if newId and newId >= 1 then
                    TERMINAL_ID = math.floor(newId)
                end

                if type(newBurnerSide) == "string" and VALID_SIDES[newBurnerSide] then
                    BURNER_SIDE = newBurnerSide
                end

                if newVentSide == "none" or newVentSide == false then
                    VENT_ENABLED = false
                elseif type(newVentSide) == "string" and VALID_SIDES[newVentSide] then
                    VENT_SIDE = newVentSide
                    VENT_ENABLED = true
                end

                burnerSignal = redstone.getAnalogOutput(BURNER_SIDE)
                ventSignal = VENT_ENABLED and redstone.getAnalogOutput(VENT_SIDE) or 0

                saveConfig()
                rednet.send(senderId, status(), PROTOCOL)
            end
        end
    end
end

local function announce()
    while running do
        rednet.broadcast(status(), PROTOCOL)
        sleep(3)
    end
end

local function controller()
    while running do
        controlHeight()
        sleep(CONTROL_INTERVAL)
    end
end

local function ui()
    while running do
        sensors()

        term.clear()
        term.setCursorPos(1, 1)

        print("================================")
        print("       CCI AEROSTAT CONTROL")
        print("================================")
        print("Terminal : " .. TERMINAL_ID)
        print("Height   : " .. string.format("%.1f", currentHeight))
        print("Speed    : " .. string.format("%.2f", verticalSpeed))
        print("Target   : " .. tostring(targetHeight or "-"))
        print("Mode     : " .. mode)
        print("Burner   : " .. burnerSignal .. "/15  [" .. BURNER_SIDE .. "]")
        print("Vent     : " .. (VENT_ENABLED and (ventSignal .. "/15  [" .. VENT_SIDE .. "]") or "DISABLED"))
        print("Home     : " .. tostring(homeHeight or "-"))
        print("Link     : " .. (os.clock() - lastCommandTime <= LINK_TIMEOUT and "OK" or "WAITING"))

        if not VENT_ENABLED and targetHeight and targetHeight < currentHeight - HEIGHT_DEADBAND then
            print("\nWARNING: Steam Vent is disabled.")
            print("Active descent requires a Steam Vent.")
        else
            print("\nAutomatic altitude control active.")
        end

        sleep(0.5)
    end
end

sensors()

if not homeHeight then
    homeHeight = currentHeight
    saveHome()
end

targetHeight = currentHeight

saveConfig()
setVent(0)

parallel.waitForAll(receiver, announce, controller, ui)
