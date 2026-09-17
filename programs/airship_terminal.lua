-- CCI AEROSTAT CONTROL
-- Airship terminal
-- CC:Tweaked + Create Aeronautics/Create: Avionics

local CONFIG_FILE = "/aerostat/config"
local PROTOCOL = "CCI_AEROSTAT_2026"
local AUTH_CODE = "CCI-AEROSTAT-2026"
local TERMINAL_ID = 1
local REDSTONE_SIDE = "left"
local HEIGHT_DEADBAND = 1.0
local MAX_ASCEND_SPEED = 1.2
local MAX_DESCEND_SPEED = 0.7
local CONTROL_INTERVAL = 0.5
local LINK_TIMEOUT = 15

local VALID_SIDES = {top=true,bottom=true,left=true,right=true,front=true,back=true}

local function loadConfig()
    if not fs.exists(CONFIG_FILE) then return end
    local h = fs.open(CONFIG_FILE, "r")
    if not h then return end
    local data = textutils.unserialize(h.readAll())
    h.close()
    if type(data) == "table" then
        TERMINAL_ID = tonumber(data.terminalId) or TERMINAL_ID
        if VALID_SIDES[data.redstoneSide] then REDSTONE_SIDE = data.redstoneSide end
    end
end

local function saveConfig()
    fs.makeDir("/aerostat")
    local h = fs.open(CONFIG_FILE, "w")
    if h then
        h.write(textutils.serialize({terminalId=TERMINAL_ID,redstoneSide=REDSTONE_SIDE}))
        h.close()
    end
end

loadConfig()

local modemName
for _,name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
        local p=peripheral.wrap(name)
        if p and p.isWireless and p.isWireless() then modemName=name break end
    end
end
assert(modemName,"Wireless modem not found")
rednet.open(modemName)

local altitudeSensor=peripheral.find("altitude_sensor")
assert(altitudeSensor,"altitude_sensor not found")

local currentHeight,verticalSpeed=0,0
local targetHeight=nil
local mode="HOLD"
local burnerSignal=redstone.getAnalogOutput(REDSTONE_SIDE)
local lastCommandTime=os.clock()
local homeHeight=nil
local running=true
local HOME_FILE="/aerostat/home_height"

if fs.exists(HOME_FILE) then
    local h=fs.open(HOME_FILE,"r")
    if h then homeHeight=tonumber(h.readAll());h.close() end
end

local function saveHome()
    fs.makeDir("/aerostat")
    local h=fs.open(HOME_FILE,"w")
    if h then h.write(tostring(homeHeight or 0));h.close() end
end

local function sensors()
    local ok,v=pcall(function() return altitudeSensor.getHeight() end)
    if ok and type(v)=="number" then currentHeight=v end
    ok,v=pcall(function() return altitudeSensor.getVerticalSpeed() end)
    if ok and type(v)=="number" then verticalSpeed=v end
end

local function setBurner(value)
    value=math.floor(value+0.5)
    if value<0 then value=0 end
    if value>15 then value=15 end
    burnerSignal=value
    redstone.setAnalogOutput(REDSTONE_SIDE,value)
end

local function status()
    sensors()
    return {type="STATUS",auth=AUTH_CODE,terminalId=TERMINAL_ID,height=currentHeight,speed=verticalSpeed,target=targetHeight,mode=mode,signal=burnerSignal,home=homeHeight}
end

local function controlHeight()
    sensors()
    if not targetHeight then return end
    local error=targetHeight-currentHeight

    if math.abs(error)<=HEIGHT_DEADBAND then
        if verticalSpeed>0.18 then setBurner(burnerSignal-1)
        elseif verticalSpeed<-0.18 then setBurner(burnerSignal+1) end
        return
    end

    if error>0 then
        if verticalSpeed>MAX_ASCEND_SPEED then setBurner(burnerSignal-1)
        elseif verticalSpeed<MAX_ASCEND_SPEED*0.55 then setBurner(burnerSignal+1) end
    else
        if verticalSpeed<-MAX_DESCEND_SPEED then setBurner(burnerSignal+1)
        elseif verticalSpeed>-MAX_DESCEND_SPEED*0.45 then setBurner(burnerSignal-1) end
        if mode=="LAND" and math.abs(error)<5 and verticalSpeed<-0.35 then setBurner(burnerSignal+1) end
    end
end

local function receiver()
    while running do
        local senderId,msg=rednet.receive(PROTOCOL,1)
        if senderId and type(msg)=="table" and msg.auth==AUTH_CODE then
            lastCommandTime=os.clock()
            if msg.type=="DISCOVER" or msg.type=="PING" then
                rednet.send(senderId,status(),PROTOCOL)
            elseif msg.type=="SET_HEIGHT" then
                local h=tonumber(msg.height)
                if h and h>=0 then targetHeight=h;mode="HOLD";rednet.send(senderId,status(),PROTOCOL) end
            elseif msg.type=="LOWER" then
                if homeHeight then targetHeight=homeHeight;mode="LAND" end
                rednet.send(senderId,status(),PROTOCOL)
            elseif msg.type=="HOLD" then
                sensors();targetHeight=currentHeight;mode="HOLD";rednet.send(senderId,status(),PROTOCOL)
            elseif msg.type=="CALIBRATE_HOME" then
                sensors();homeHeight=currentHeight;saveHome();targetHeight=currentHeight;mode="HOLD";rednet.send(senderId,status(),PROTOCOL)
            elseif msg.type=="SET_CONFIG" then
                local newId=tonumber(msg.terminalId)
                local newSide=msg.redstoneSide
                if newId and newId>=1 then TERMINAL_ID=newId end
                if type(newSide)=="string" and VALID_SIDES[newSide] then REDSTONE_SIDE=newSide end
                saveConfig();rednet.send(senderId,status(),PROTOCOL)
            end
        end
    end
end

local function announce()
    while running do rednet.broadcast(status(),PROTOCOL);sleep(3) end
end

local function controller()
    while running do controlHeight();sleep(CONTROL_INTERVAL) end
end

local function ui()
    while running do
        sensors()
        term.clear();term.setCursorPos(1,1)
        print("================================")
        print("       CCI AEROSTAT CONTROL")
        print("================================")
        print("Terminal : "..TERMINAL_ID)
        print("Height   : "..string.format("%.1f",currentHeight))
        print("Speed    : "..string.format("%.2f",verticalSpeed))
        print("Target   : "..tostring(targetHeight or "-"))
        print("Mode     : "..mode)
        print("Burner   : "..burnerSignal.."/15")
        print("Home     : "..tostring(homeHeight or "-"))
        print("Redstone : "..REDSTONE_SIDE)
        print("Link     : "..(os.clock()-lastCommandTime<=LINK_TIMEOUT and "OK" or "WAITING"))
        print("\nAutomatic altitude control active.")
        sleep(0.5)
    end
end

sensors()
if not homeHeight then homeHeight=currentHeight;saveHome() end
targetHeight=currentHeight
saveConfig()

parallel.waitForAll(receiver,announce,controller,ui)
