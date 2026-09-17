-- CCI AEROSTAT INSTALLER
-- https://github.com/Frez7373/aerostat
-- CC:Tweaked

local BASE_URL = "https://raw.githubusercontent.com/Frez7373/aerostat/main/"
local ROOT = "/aerostat"
local VERSION = "1.0.0"

local function line()
    print("----------------------------------------------")
end

local function pause()
    print("")
    print("Press ENTER to continue...")
    read()
end

local function ensureDir()
    if not fs.exists(ROOT) then fs.makeDir(ROOT) end
end

local function download(file, path)
    ensureDir()
    if fs.exists(path) then fs.delete(path) end
    print("Downloading " .. file .. "...")
    local ok = shell.run("wget", BASE_URL .. "programs/" .. file, path)
    if not ok or not fs.exists(path) then
        print("ERROR: download failed")
        return false
    end
    print("OK: " .. path)
    return true
end

local function saveText(path, text)
    local h = fs.open(path, "w")
    if not h then return false end
    h.write(text)
    h.close()
    return true
end

local function installBase()
    ensureDir()
    local target = ROOT .. "/base_terminal.lua"
    if not download("base_terminal.lua", target) then pause(); return end
    saveText(ROOT .. "/role", "base")
    saveText(ROOT .. "/version", VERSION)
    print("")
    print("Base terminal installed.")
    print("Start with: /aerostat/base_terminal.lua")
    pause()
end

local function askNumber(prompt, default)
    while true do
        write(prompt .. " [" .. default .. "]: ")
        local value = read()
        if value == "" then value = tostring(default) end
        local n = tonumber(value)
        if n and n >= 1 then return math.floor(n) end
        print("Enter a positive number.")
    end
end

local function askSide()
    local sides = {"left", "right", "front", "back", "top", "bottom"}
    while true do
        print("")
        print("Redstone output side:")
        for i, side in ipairs(sides) do
            print(i .. ". " .. side)
        end
        write("Choose side [1]: ")
        local n = tonumber(read()) or 1
        if sides[n] then return sides[n] end
        print("Invalid side.")
    end
end

local function installAirship()
    ensureDir()

    local terminalId = askNumber("Airship terminal number", 1)
    local side = askSide()

    local target = ROOT .. "/airship_terminal.lua"
    if not download("airship_terminal.lua", target) then pause(); return end

    local config = textutils.serialize({
        terminalId = terminalId,
        redstoneSide = side
    })

    saveText(ROOT .. "/config", config)
    saveText(ROOT .. "/role", "airship")
    saveText(ROOT .. "/version", VERSION)

    print("")
    print("Airship terminal installed.")
    print("Terminal ID : " .. terminalId)
    print("Redstone    : " .. side)
    print("Start with: /aerostat/airship_terminal.lua")
    pause()
end

local function updateInstalled()
    if not fs.exists(ROOT .. "/role") then
        print("No Aerostat installation found.")
        pause()
        return
    end

    local h = fs.open(ROOT .. "/role", "r")
    local role = h and h.readAll() or ""
    if h then h.close() end

    if role == "base" then
        download("base_terminal.lua", ROOT .. "/base_terminal.lua")
    elseif role == "airship" then
        download("airship_terminal.lua", ROOT .. "/airship_terminal.lua")
    else
        print("Unknown installation role.")
        pause()
        return
    end

    saveText(ROOT .. "/version", VERSION)
    print("Updated to version " .. VERSION)
    pause()
end

local function runInstalled()
    if not fs.exists(ROOT .. "/role") then
        print("Aerostat is not installed.")
        pause()
        return
    end

    local h = fs.open(ROOT .. "/role", "r")
    local role = h and h.readAll() or ""
    if h then h.close() end

    local program
    if role == "base" then
        program = ROOT .. "/base_terminal.lua"
    elseif role == "airship" then
        program = ROOT .. "/airship_terminal.lua"
    else
        print("Unknown installation role.")
        pause()
        return
    end

    if not fs.exists(program) then
        print("Program is missing. Use Update first.")
        pause()
        return
    end

    shell.run("clear")
    shell.run(program)
end

local function uninstall()
    if fs.exists(ROOT) then
        print("This will remove the Aerostat program and its config.")
        write("Type DELETE to confirm: ")
        if read() == "DELETE" then
            fs.delete(ROOT)
            print("Aerostat removed.")
        else
            print("Cancelled.")
        end
    else
        print("Nothing to remove.")
    end
    pause()
end

while true do
    term.clear()
    term.setCursorPos(1, 1)

    print("==============================================")
    print("          CCI AEROSTAT INSTALLER")
    print("==============================================")
    print("Version: " .. VERSION)
    print("")
    print("1. Install base terminal")
    print("2. Install airship terminal")
    print("3. Update installed terminal")
    print("4. Run installed terminal")
    print("5. Remove Aerostat")
    print("6. Exit")
    line()
    write("Choose [1-6]: ")

    local choice = read()

    if choice == "1" then
        installBase()
    elseif choice == "2" then
        installAirship()
    elseif choice == "3" then
        updateInstalled()
    elseif choice == "4" then
        runInstalled()
    elseif choice == "5" then
        uninstall()
    elseif choice == "6" then
        term.clear()
        term.setCursorPos(1, 1)
        print("CCI Aerostat installer closed.")
        break
    else
        print("Invalid choice.")
        sleep(1)
    end
end
