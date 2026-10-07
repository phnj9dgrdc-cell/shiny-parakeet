 { "AutoOpenCases" },
        WeaponService = { "AutoSell" },
        QuestService = { "AutoClaimQuest" },
        GameService = { "FastRespawn" },
    },
    SkinMainRows = 4,
    SkinGroupRows = 3,
    EconomyInterval = 1,
    StatusInterval = 1,
    OpenDelay = 0.6,
    SellDelay = 0.8,
    ClaimDelay = 0.5,
    FireInterval = 0.12,
    LookSettle = 0.1,
    TriggerRange = 2000,
    RespawnRetry = 0.25,
    AimRenderPriority = Enum.RenderPriority.Camera.Value + 5,
}

xDTaraZ.State = {
    Alive = true,
    Connections = {},
    Halted = {},
    Notices = {},
    Status = "Idle",
}

xDTaraZ.Options = {
    AntiAfk = false,

    InfiniteDash = false,
    FastRespawn = false,
    SkinChanger = false,
    SkinRarities = {},

    AutoOpenCases = false,
    OpenCount = 1,
    AutoSell = false,
    SellRarities = {},
    MaxSellPrice = 500,
    KeepPerRarity = 0,
    AutoClaimQuest = false,

    Aimbot = false,
    SilentAim = false,
    Ragebot = false,
    InstantScope = false,
    HitChance = 100,
    HeadChance = 100,
    TriggerBot = false,
    NoRecoil = false,
    NoSpread = false,
    AimTeamCheck = true,
    AimWallCheck = true,
    AimSmooth = 1,
    AimPrediction = 60,
    ShowFov = false,
    AimFov = 150,
    AimPriority = "Crosshair",
    AimMaxDistance = 1000,
    AimBone = "Head",
}

xDTaraZ.Util = {}
local Util = xDTaraZ.Util

---@return function?  first argument that is callable
local function Resolve(...)
    for index = 1, select("#", ...) do
        local candidate = select(index, ...)
        if type(candidate) == "function" then
            return candidate
        end
    end
    return nil
end

Util.Request = Resolve(request, http_request, syn and syn.request, http and http.request)
Util.SetClipboard = Resolve(setclipboard, toclipboard)
Util.GetHui = Resolve(gethui, get_hidden_gui)
Util.GetUpvalue = Resolve(getupvalue, debug.getupvalue)
Util.GetUpvalues = Resolve(getupvalues, debug.getupvalues)
Util.GetRawMetatable = Resolve(getrawmetatable)

xDTaraZ.Probes = {}

---@return boolean  getrawmetatable and getupvalues both answer for real
function xDTaraZ.Probes.LookSpoof()
    if not (Util.GetRawMetatable and Util.GetUpvalues) then return false end
    local marker, meta = {}, { __metatable = "locked" }
    local proxy = setmetatable({}, meta)
    local function Holder() return marker end

    local ok, found = pcall(function()
        if Util.GetRawMetatable(proxy) ~= meta then return false end
        for _, value in pairs(Util.GetUpvalues(Holder)) do
            if value == marker then return true end
        end
        return false
    end)
    return ok and found == true
end

xDTaraZ.Caps = setmetatable({}, {
    __index = function(caps, name)
        local probe = xDTaraZ.Probes[name]
        if probe then
            local has = probe()
            rawset(caps, name, has)
            return has
        end
        local lib = xDTaraZ.Library
        if not (lib and lib.Compat) then return false end
        return lib.Compat.Caps[name] == true
    end,
})

---@return string  response body, throws if every transport fails
function Util.HttpGet(url)
    if url == "NovaHub://embedded-ui" then return NOVA_HUB_UI_SOURCE end
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if ok and type(body) == "string" then
        return body
    end
    if not Util.Request then
        error("HttpGet failed: " .. url)
    end

    local sent, response = pcall(Util.Request, { Url = url, Method = "GET" })
    if not sent then error(response) end
    local status = type(response) == "table" and tonumber(response.StatusCode) or nil
    if status == 200 and type(response.Body) == "string" then
        return response.Body
    end
    error("HttpGet " .. url .. ": status " .. tostring(status))
end

---@param detail any  goes to the console, the player only sees text
function Util.Alert(text, detail)
    warn("[SniperArena] menu: " .. tostring(detail or text))
    task.spawn(function()
        for _ = 1, xDTaraZ.Config.AlertTries do
            local shown = pcall(StarterGui.SetCore, StarterGui, "SendNotification", {
                Title = "Nova Hub",
                Text = text,
                Duration = 10,
            })
            if shown then return end
            task.wait(xDTaraZ.Config.AlertGap)
        end
    end)
end

---@return table?  UI library, nil after the player was told why
function Util.LoadLibrary(url)
    local fetched, source = pcall(Util.HttpGet, url)
    if not fetched or type(source) ~= "string" or not source:sub(-64):find("return Library%s*$") then
        Util.Alert("Could not download the menu. Check your connection and run it again.", fetched and "response is not the full menu" or source)
        return nil
    end

    local chunk, problem = loadstring(source)
    if type(chunk) ~= "function" then
        Util.Alert("The menu failed to load on this executor: " .. tostring(problem))
        return nil
    end
    local ran, lib = pcall(chunk)
    if not ran or type(lib) ~= "table" then
        Util.Alert("The menu failed to load on this executor: " .. tostring(lib))
        return nil
    end
    if type(lib.Compat) ~= "table" then
        Util.Alert("The menu is out of date. Run the script again in a few minutes.", "ui.lua has no Compat layer")
        return nil
    end
    return lib
end

---@return boolean  false after warning with context
function Util.Try(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        warn("[SniperArena] " .. label .. ": " .. tostring(err))
    end
    return ok
end

function Util.Copy(text)
    if Util.SetClipboard then
        Util.SetClipboard(text)
        return true
    end
    return false
end

---@return ScreenGui  script-owned layer, hidden gui first, PlayerGui last
function Util.Overlay()
    local screen = xDTaraZ.State.Overlay
    if screen and screen.Parent then return screen end

    screen = Instance.new("ScreenGui")
    screen.Name = "NovaHubOverlay"
    screen.IgnoreGuiInset = true
    screen.ResetOnSpawn = false
    screen.DisplayOrder = 50
    local mounts = { function() return game:GetService("CoreGui") end }
    if Util.GetHui then table.insert(mounts, 1, Util.GetHui) end
    for _, mount in ipairs(mounts) do
        if pcall(function() screen.Parent = mount() end) and screen.Parent then break end
    end
    if not screen.Parent then
        screen.Parent = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", xDTaraZ.Config.LoadTimeout)
    end
    xDTaraZ.State.Overlay = screen
    return screen
end

function Util.FormatNumber(value)
    local text = tostring(math.floor(value or 0))
    local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (formatted:gsub("^,", ""))
end

---@return string[]  sorted keys, stable dropdown order
function Util.SortedKeys(map)
    local keys = {}
    for key in pairs(map or {}) do
        keys[#keys + 1] = tostring(key)
    end
    table.sort(keys)
    return keys
end

function Util.SetFromList(list)
    local set = {}
    for key, value in pairs(list or {}) do
        if type(key) == "number" then
            set[value] = true
        elseif value then
            set[key] = true
        end
    end
    return set
end

function xDTaraZ:Connect(signal, handler)
    local connection = signal:Connect(handler)
    table.insert(self.State.Connections, connection)
    return connection
end

function xDTaraZ:SetStatus(text)
    self.State.Status = text
end

local Signal = {}
Signal.__index = Signal

function Signal.new()
    return setmetatable({ Handlers = {} }, Signal)
end

function Signal:Connect(handler)
    table.insert(self.Handlers, handler)
    return {
        Disconnect = function()
            local index = table.find(self.Handlers, handler)
            if index then table.remove(self.Handlers, index) end
        end,
    }
end

function Signal:Fire(...)
    for _, handler in ipairs(table.clone(self.Handlers)) do
        task.spawn(handler, ...)
    end
end

xDTaraZ.Signal = Signal

xDTaraZ.GameLib = { Config = {}, Service = {}, Missing = {}, LoadEnds = nil }
local GameLib = xDTaraZ.GameLib

---@param asGame boolean     retry from an identity-2 thread, skipped when the executor can't switch
---@return boolean, boolean, any  finished before the deadline, require ok, module
function GameLib.RequireWithin(module, asGame)
    local done, ok, loaded = false, false, nil
    task.spawn(function()
        if asGame then
            pcall(setthreadidentity, 2)
            local read, identity = pcall(getthreadidentity)
            if not (read and identity == 2) then
                done = true
                return
            end
        end
        ok, loaded = pcall(require, module)
        done = true
    end)

    local deadline = osClock() + xDTaraZ.Config.RequireTimeout
    if GameLib.LoadEnds then deadline = math.min(deadline, GameLib.LoadEnds) end
    while not done and osClock() < deadline do
        task.wait()
    end
    return done, ok, loaded
end

---@return any  nil when this executor can't require it (never throws)
function GameLib.Require(module)
    if GameLib.LoadEnds and osClock() >= GameLib.LoadEnds then
        GameLib.Missing[module.Name] = true
        warn("[SniperArena] require " .. module.Name .. ": load budget spent")
        return nil
    end

    local finished, ok, loaded = GameLib.RequireWithin(module, false)
    if ok then return loaded end
    if finished then
        local _, again, retried = GameLib.RequireWithin(module, true)
        if again then return retried end
    end
    GameLib.Missing[module.Name] = true
    warn("[SniperArena] require " .. module.Name .. ": " .. (finished and tostring(loaded) or "timed out"))
    return nil
end

---@param parent Instance?  expected folder; a moved module is still found anywhere in ReplicatedStorage
local function RequireChild(parent, name)
    local child = parent and parent:FindFirstChild(name)
    if not (child and child:IsA("ModuleScript")) then
        child = ReplicatedStorage:FindFirstChild(name, true)
    end
    if not (child and child:IsA("ModuleScript")) then
        GameLib.Missing[name] = "Absent"
        warn("[SniperArena] module " .. name .. " not found, features that need it are blocked")
        return nil
    end
    return GameLib.Require(child)
end

do
    local configFolder = ReplicatedStorage:FindFirstChild("Config")
    local remoteFolder = ReplicatedStorage:FindFirstChild("Remote")
    local constantFolder = ReplicatedStorage:FindFirstChild("Constant")
    GameLib.LoadEnds = osClock() + xDTaraZ.Config.RequireBudget

    local configNames = {
        "Config", "WeaponConfig", "GachaConfig", "WeaponCraftConfig", "WeaponSellConfig",
        "RewardsConfig", "BattlepassConfig", "RankingConfig", "QuestConfig", "SpinConfig",
        "RaffleConfig", "ShopConfig", "CustomShopConfig", "AuctionConfig", "ItemConfig",
        "CollectionRewardConfig", "CashPendingConfig", "MinipassConfig", "WrapConfig",
    }
    for _, name in ipairs(configNames) do
        GameLib.Config[name] = RequireChild(configFolder, name)
    end

    local serviceNames = {
        "StatusService", "GachaService", "WeaponService", "QuestService", "EntityService",
        "CombatService", "GameService", "BattlepassService", "RaffleService",
    }
    for _, name in ipairs(serviceNames) do
        GameLib.Service[name] = RequireChild(remoteFolder, name)
    end
    GameLib.CameraController = RequireChild(ReplicatedStorage:FindFirstChild("Client"), "CameraController")
    GameLib.WeaponController = RequireChild(ReplicatedStorage:FindFirstChild("Client"), "WeaponController")
    local gameService = remoteFolder and remoteFolder:FindFirstChild("GameService")
    GameLib.RoomManager = RequireChild(gameService, "RoomManager")
    GameLib.Status = RequireChild(constantFolder, "Status")
    GameLib.Constant = constantFolder
    GameLib.LoadEnds = nil
end

xDTaraZ.Player = { Client = LocalPlayer }

function xDTaraZ.Player:Bind(character)
    self.Character = character
    self.Humanoid = character:WaitForChild("Humanoid", xDTaraZ.Config.LoadTimeout)
    self.Root = character:WaitForChild("HumanoidRootPart", xDTaraZ.Config.LoadTimeout)
end

function xDTaraZ.Player:IsAlive()
    return self.Humanoid ~= nil and self.Humanoid.Health > 0 and self.Root ~= nil and self.Root.Parent ~= nil
end

---@return number  server-side status counter, 0 when unavailable
function xDTaraZ.Player:Status(key)
    local service = GameLib.Service.StatusService
    if not service or not key then return 0 end
    local ok, value = pcall(function() return service.GetStatus(key) end)
    return ok and tonumber(value) or 0
end

function xDTaraZ.Player:Coin()
    local key = GameLib.Status and GameLib.Status.Eco_Coin or "Eco_Coin"
    return self:Status(key)
end

xDTaraZ.Entity = {}

function xDTaraZ.Entity.Service()
    return GameLib.Service.EntityService
end

---@return table  focused combatant entities (empty in lobby / combat paused)
function xDTaraZ.Entity.List()
    local service = xDTaraZ.Entity.Service()
    if not service then return {} end
    local ok, focused = pcall(function() return service.WorldManager:GetFocusedEntities() end)
    if not ok or type(focused) ~= "table" then return {} end
    return focused._items or focused.Items or focused
end

function xDTaraZ.Entity.Local()
    local service = xDTaraZ.Entity.Service()
    if not service then return nil end
    local ok, entity = pcall(function() return service.GetLocalEntity() end)
    if ok and entity then return entity end
    ok, entity = pcall(function() return service:GetLocalEntity() end)
    return ok and entity or nil
end

local function TryCall(object, method)
    if type(object) ~= "table" and typeof(object) ~= "Instance" then return nil, false end
    local fn = object[method]
    if type(fn) ~= "function" then return nil, false end
    local ok, value = pcall(fn, object)
    if ok then return value, true end
    return nil, false
end

function xDTaraZ.Entity.IsLocal(entity)
    local value, called = TryCall(entity, "IsLocalEntity")
    if called then return value == true end
    return entity == xDTaraZ.Entity.Local()
end

---@return string?  per-round team tag, unique per player in FFA/Duel
function xDTaraZ.Entity.Team(entity)
    local inst = entity and entity.Instance
    if typeof(inst) == "Instance" then
        local team = inst:GetAttribute("Team")
        if team ~= nil then return tostring(team) end
    end
    local char = xDTaraZ.Entity.Character(entity)
    local team = char and char:GetAttribute("Team")
    return team ~= nil and tostring(team) or nil
end

function xDTaraZ.Entity.Friendly(entity)
    local char = xDTaraZ.Entity.Character(entity)
    local marks = Workspace:FindFirstChild("Highlight")
    if char and marks then
        local friendly = marks:FindFirstChild("Friendly")
        if friendly and char:IsDescendantOf(friendly) then return true end
        if char:IsDescendantOf(marks) then return false end
    end

    if xDTaraZ.Match.ModeSet() ~= "TDM" then return false end
    local mine = xDTaraZ.Entity.Team(xDTaraZ.Entity.Local())
    local theirs = xDTaraZ.Entity.Team(entity)
    return mine ~= nil and mine == theirs
end

function xDTaraZ.Entity.Health(entity)
    if not entity then return 0, 0 end
    local health = entity.Health or select(1, TryCall(entity, "GetHealth")) or 0
    local maxHealth = entity.MaxHealth or select(1, TryCall(entity, "GetMaxHealth")) or 0
    return health, maxHealth
end

function xDTaraZ.Entity.Character(entity)
    local humanoid = entity and entity.Humanoid
    if humanoid and humanoid.Parent then return humanoid.Parent end
    return entity and entity.Character or nil
end

function xDTaraZ.Entity.Root(entity)
    local character = xDTaraZ.Entity.Character(entity)
    if not character then return nil end
    return character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Head") or character.PrimaryPart
end

xDTaraZ.Match = {}

---@return string?, string?  mode, map — nil outside a room
function xDTaraZ.Match.Info()
    local rooms = GameLib.RoomManager
    local ok, room = pcall(function() return rooms and rooms.GetFocusedRoom() end)
    if not ok or type(room) ~= "table" then return nil, nil end
    return room.Mode, room.Map
end

---@return string?  FFA / TDM / Duel / Boss
function xDTaraZ.Match.ModeSet()
    local rooms = GameLib.RoomManager
    local ok, room = pcall(function() return rooms and rooms.GetFocusedRoom() end)
    return ok and type(room) == "table" and room.ModeSet or nil
end

function xDTaraZ.Match.InRound()
    return LocalPlayer:GetAttribute("combatPaused") == false
end

xDTaraZ.Faults = { Streaks = {}, Said = {} }

---@param err any  the same error again stays quiet for FailWindow
function xDTaraZ.Faults.Say(name, err)
    local text, now = tostring(err), osClock()
    local last = xDTaraZ.Faults.Said[name]
    if last and last[1] == text and now - last[2] < xDTaraZ.Config.FailWindow then return end
    xDTaraZ.Faults.Said[name] = { text, now }
    warn("[SniperArena] " .. name .. ": " .. text)
end

function xDTaraZ.Faults.Clear(name)
    xDTaraZ.Faults.Streaks[name] = nil
end

function xDTaraZ.Faults.Wanted(toggles)
    for _, key in ipairs(toggles) do
        if xDTaraZ.Options[key] then return true end
    end
    return false
end

---@param restore function?  the feature's own off path
function xDTaraZ.Faults.Stop(name, err, toggles, restore)
    warn("[SniperArena] " .. name .. " stopped: " .. tostring(err))
    for _, key in ipairs(toggles) do
        xDTaraZ.Options[key] = false
    end
    if restore then Util.Try(name .. " restore", restore) end
    table.insert(xDTaraZ.State.Halted, { name, tostring(err):match("^[^\n]*"), toggles })
end

---@param toggles string[]   switched off when the feature keeps failing; empty = never stops, warns once per streak
---@param restore function?  run once when the feature is stopped
---@return boolean           true while the feature is stopped
function xDTaraZ.Faults.Report(name, err, toggles, restore)
    local now = osClock()
    local streak = xDTaraZ.Faults.Streaks[name]
    if not streak or (streak.Halted and xDTaraZ.Faults.Wanted(toggles)) then
        streak = { Count = 0, First = now, Warned = false, Halted = false }
        xDTaraZ.Faults.Streaks[name] = streak
    end
    streak.Count += 1
    if streak.Count == 1 then xDTaraZ.Faults.Say(name, err) end
    if streak.Warned then return streak.Halted end
    if streak.Count < xDTaraZ.Config.MaxFails or now - streak.First < xDTaraZ.Config.FailWindow then return false end

    streak.Warned = true
    if #toggles == 0 then
        warn("[SniperArena] " .. name .. " keeps failing: " .. tostring(err))
        return false
    end
    streak.Halted = true
    xDTaraZ.Faults.Stop(name, err, toggles, restore)
    return true
end

xDTaraZ.Scheduler = { Jobs = {}, Booted = false }

---@param toggles string[]?  options the job serves; turned off if it keeps failing
---@param restore function?  the job's off path, run once if it gets stopped
function xDTaraZ.Scheduler.Every(name, interval, fn, toggles, restore)
    xDTaraZ.Scheduler.Jobs[name] = { Interval = interval, Fn = fn, Last = 0, Running = false, Toggles = toggles or {}, Restore = restore }
end

---@return boolean  a stopped job comes back once one of its toggles is on again
function xDTaraZ.Scheduler.Revive(name, job)
    if not xDTaraZ.Faults.Wanted(job.Toggles) then return false end
    job.Halted = false
    xDTaraZ.Faults.Clear(name)
    return true
end

function xDTaraZ.Scheduler.Settle(name, job)
    local err = job.Error
    job.Error = nil
    if err then
        job.Halted = xDTaraZ.Faults.Report(name, err, job.Toggles, job.Restore)
    else
        xDTaraZ.Faults.Clear(name)
    end
end

function xDTaraZ.Scheduler.Step()
    local now = osClock()
    for name, job in pairs(xDTaraZ.Scheduler.Jobs) do
        if job.Running then continue end
        if job.Error ~= nil then xDTaraZ.Scheduler.Settle(name, job) end
        if job.Halted and not xDTaraZ.Scheduler.Revive(name, job) then continue end
        if now - job.Last < job.Interval then continue end

        job.Last = now
        job.Running = true
        task.spawn(function()
            local ok, err = pcall(job.Fn)
            job.Error = (not ok) and tostring(err) or false
            job.Running = false
        end)
    end
end

function xDTaraZ.Scheduler.Boot()
    if xDTaraZ.Scheduler.Booted then return end
    xDTaraZ.Scheduler.Booted = true
    xDTaraZ:Connect(RunService.Heartbeat, xDTaraZ.Scheduler.Step)
end

xDTaraZ.Banner = {
    Print = print,
    Started = osClock(),
    Last = osClock(),
    Done = 0,
    Total = 5,
    Art = [[
                                                                     @%@
                                                                    @*-#@
                                          @@@@@@@@@@@@@          @@#+.:-*%@@      @@
                                   @@@@@%##***********##%@@@@@   @*--:-==+*@@@@#*+==+*%@@
                              @@@@#+=+==---==++++++++++++**+++#@@@@@%==+@@@@#:.......:::=%@@
                          @@%#+---::-=++++++++++************+***++#%@%+@@@#:..-+*****+-:::+%@
                      @@@#=-::.:-==++++++++++*************************#@@+::=*-:.:+-::-+:.:=#@
                    @@%-:...:-===+++++**#################****************%%*+::::+*++::-+..:=#@
                 @@%*-:...:--==++*########**+==--===+**#######************+#%+::-*==-:::=-::=+@@
               @@%+=-::---===+*###%#+-:...................:=+#####***********#@+++==----==:-+*@@
             @@%++=-======+*###%+:............................::+####**********#@*+=----=---**@@
            @%=++=++++++*####=:...................................:+###**********%@==--==--+**@@
          @@*+++++++++*###*:........................................:-*##**********%*==+--=**@@@
         @%+++++++++*##%+:............................................::*##*********%%+--=##%@+%@
       @@#+++++++++###*:.....-+==+*#-......................:**+**#+:....:=###********%%+*##%@*:+@@
      @@*++++++++*###:......-+:.:-=*#*-..................:+*--+**#%*:.....:+##********#@#%%+:.:--+#@
     @@+++++++++*##+:......-*::-=++++*##:...............=#=-++****#%*:.....:-##********#@@@%+=-++#@@
    @@+=-=+++++*##+.......:*-:==++++++*##+............-*+-=+*******#%+:.....:-##********#@  @#=#@@
    @*=:.=++++*##-.......:*=:=++++++++*+*##=........:**==+**********##=:.....::*#********%@  @#@
   @#+-.-++*+*##=........*+-++++++*********##-....:+*==+*************#%-:.....:-**********%@
  @@++-=++***##+........*+-++++++***********#%*::=#+-+****************#%-:.....:=**********@@
 @@*++=++***###........+*-+++++***************###+-=+*****************###-:.....:+*********%@
 @%++=+*****#%:.......=*-++++*******************==+********************#%*-:....:-#********#@@
@@**+++****##+.......=*=+++*********************************************#%+::....:+*********@@
@%**++*****##-......=#=++**********#%#********************%%*************#%+:....:-#********%@
@%**++*****#*:.....-*=++**********#%%%#*****************#%%%**************#%=:....-********##@@
@#**++*****#*:....:*++************%%%%%%#*************#%%%%%#**************##-:...-+*******#*@@
@#**+******#+:...:#++************#%%%@@%%##*********#%%%%%@%#**************#%#-:..:+*+*****#*@@
@#**+******#+:..:#+=************#%%%%%*%%%##*******%%%%%%#%%##**************#%#::.-+*+*****#*@@
@#*********#+:.:+*=*************%%%%%+==*%%###***#%%%%%#++*%##***************#%*::-+*+*****#*@@
@%*#*******#*:.+*=*************%%%%%*=----*%###%%%%%%#+====*###**************##%+--*++****###@@
@%*#********#-:####***********#%%%%#=-::.::=###%%%%#+==--:::####************#%%%#==*+*****###@@
@@##********#+:#%%%%#********#%%%%%=--:....::=%%%%+==--::..:-%###********#%%%%%%#=#++*****##%@
@@###********#-=#%%%%%%##****%%%%%*=-:.......::-==---::.....:+###*****##%%%%%%%#++#++****###@@
 @%###*******##::=+%%%%%%%##%%%%%#=-:...........:::::........:####*#%%%%%%%%%*+=+*+=*****##%@
 @@###********#+:.:-=*%%%%%%%%%%%+--:.........................=###%%%%%%%%*+====*=.=****###@@
  @@###********#+:..::-=*%%%%%%%*=-:..:::-------------::::...::*#%%%%%%*+==---=*+-=+***###%@
   @%###*******#%#*+-..::-=#%@@%#**++==----------------===+++**#%@@@#+===---+*#*++****####@@
    @%###**#%#=::-=+##*##+-:...:::-=+**---*###*=--++++=--=++++=--:::-=+#%**#-:..:=#%##%##@@
    @@%#%#+:...:-=++=:..::=*####+#=:..=@#%:....%@*....*%%#...:--=*##+------=+=:::::-=#%%@@
     @@%*=--::::-*::::::-%=...:%@#:...:@@#.....%@+....=@@=.........:*#=-----=+=:::-==++%@@
  @@%+--+==--:::-#=-::::-%+....+%%-....%@#....:@@+....+@@:...:%%....-@*---==+*+:::-=+++*=+#@@
 @%-:-==*+==-:::-+*--:::-*#:...........*@#....:@@+....+@%..........-%%+---==+*=::-=+++#*=-:-*@@
 @@#+===+*+==-::-=*=--::-=%-......:....+@%:....:-....:#@*....=+:...-%#=--==+**-:--=++#*+=-=*%@
   @@#*=++#+=-:::-+*------#+....+@%....-@@#:.......::*@@+....+#=.:::=%+-===+#+-:-=++***++*%@@
     @@#+++*==-::-=*=-----+%:...-@@-::-=@%%@#+=--==*%@%%=:::::::::::#%+===+**----=++#**#%@@
     @@*-=+*+=-::-=*+=----=%#+*#%@%@@@@@#+-=*%%@@@%#*==*@@%%%##*+*#@@*====+#+-:-=++***++%@
    @@*--=+++===++*#*=------#%%#+=-----===============----==+*#%%%#+=-===+*#*+++=++**+==*@@
    @%=:-==+***%%@@@#=-=====++*##%%%@@@@@@@@@@%%@@@@@@@@@%%%##**++=======+*@@@@%#*+#+=--=#@
    @*:---==+*###%@@@#*#%%@%%%%%%######*****++++++++***######%%%%%%%%%%#*#%@@@####**+=---+@@
   @@+--=**#%@@@@@  @@@%%%%%%%#*******************************####%%%%%%@@@  @@@@@%#**=--+%@
    @@%%@@@@@          @@@@%%%%%%###**********************####%%%%%%%@@@          @@@@@%%%@@
      @@                  @@@@@%%%%%%%%%###############%%%%%%%%%@@@@@                  @@@
                               @@@@@@%%%%%%%%%%%%%%%%%%%%%%@@@@@
                                    @@@@@@@@@@@@@@@@@@@@@@@
]],
    Title = [[
  __  __    _    ____  ___ ___    _   _ _   _ ____
 |  \/  |  / \  |  _ \|_ _/ _ \  | | | | | | | __ )
 | |\/| | / _ \ | |_) || | | | | | |_| | | | |  _ \
 | |  | |/ ___ \|  _ < | | |_| | |  _  | |_| | |_) |
 |_|  |_/_/   \_\_| \_\___\___/  |_| |_|\___/|____/
]],
}

pcall(function()
    local renv = getrenv()
    if type(renv.print) == "function" then xDTaraZ.Banner.Print = renv.print end
end)

function xDTaraZ.Banner.Show()
    local ok, executor = pcall(identifyexecutor)
    if not ok or type(executor) ~= "string" then executor = "Unknown" end
    local rule = string.rep("=", 54)
    xDTaraZ.Banner.Print(table.concat({
        "",
        xDTaraZ.Banner.Art,
        xDTaraZ.Banner.Title,
        rule,
        "   SNIPER ARENA  //  by xDTaraZ  //  discord.gg/FHVfmeSceA",
        "   executor: " .. tostring(executor) .. "   //   player: " .. LocalPlayer.Name,
        rule,
    }, "\n"))
end

---@param label string  what just finished loading
function xDTaraZ.Banner.Step(label)
    local banner = xDTaraZ.Banner
    local now = osClock()
    banner.Done = math.min(banner.Done + 1, banner.Total)
    local filled = math.floor(banner.Done / banner.Total * 20 + 0.5)
    local bar = string.rep("#", filled) .. string.rep(".", 20 - filled)
    xDTaraZ.Banner.Print(string.format("[Nova Hub] [%s] %3d%%  %-24s +%dms",
        bar, math.floor(banner.Done / banner.Total * 100), label, math.floor((now - banner.Last) * 1000)))
    banner.Last = now
end

function xDTaraZ.Banner.Ready()
    local names = xDTaraZ.Config.BannerCaps
    local caps = 0
    for _, name in ipairs(names) do
        if xDTaraZ.Caps[name] then caps += 1 end
    end
    local rule = string.rep("=", 54)
    xDTaraZ.Banner.Print(table.concat({
        rule,
        string.format("   >> READY in %dms  //  caps %d/%d  //  LeftCtrl = menu",
            math.floor((osClock() - xDTaraZ.Banner.Started) * 1000), caps, #names),
        rule,
    }, "\n"))
end

pcall(xDTaraZ.Banner.Show)
pcall(xDTaraZ.Banner.Step, "Core")

xDTaraZ.Player.AntiAfk = { Connection = nil, Status = "Off" }

function xDTaraZ.Player.AntiAfk.OnIdled()
    if not xDTaraZ.Options.AntiAfk then return end
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.zero)
end

function xDTaraZ.Player.AntiAfk.Start()
    xDTaraZ.Options.AntiAfk = true
    if not xDTaraZ.Player.AntiAfk.Connection then
        xDTaraZ.Player.AntiAfk.Connection = xDTaraZ:Connect(LocalPlayer.Idled, xDTaraZ.Player.AntiAfk.OnIdled)
    end
    xDTaraZ.Player.AntiAfk.Status = "Armed"
end

function xDTaraZ.Player.AntiAfk.Stop()
    xDTaraZ.Options.AntiAfk = false
    xDTaraZ.Player.AntiAfk.Status = "Off"
end

function xDTaraZ.Player.AntiAfk.Step()
    if xDTaraZ.Options.AntiAfk and not xDTaraZ.Player.AntiAfk.Connection then
        xDTaraZ.Player.AntiAfk.Connection = xDTaraZ:Connect(LocalPlayer.Idled, xDTaraZ.Player.AntiAfk.OnIdled)
    end
end

function xDTaraZ.Player.AntiAfk.GetStatus()
    return xDTaraZ.Player.AntiAfk.Status
end

xDTaraZ.Player.Respawn = { Status = "Off", Count = 0, LastFire = 0 }

function xDTaraZ.Player.Respawn.IsDead()
    local state = LocalPlayer:GetAttribute("State")
    if state == "Dead" or state == "Died" then return true end
    local humanoid = xDTaraZ.Player.Humanoid
    return humanoid ~= nil and humanoid.Health <= 0
end

function xDTaraZ.Player.Respawn.Fire()
    local gs = xDTaraZ.GameLib.Service.GameService
    if gs and gs.CanFastRespawn and gs.CanFastRespawn() then
        gs.FastRespawn()
        return
    end
    local folder = ReplicatedStorage:FindFirstChild("Remote")
    local service = folder and folder:FindFirstChild("GameService")
    local remote = service and service:FindFirstChild("Respawn")
    if remote then remote:FireServer() end
end

function xDTaraZ.Player.Respawn.Step()
    if not xDTaraZ.Options.FastRespawn then
        xDTaraZ.Player.Respawn.Status = "Off"
        return
    end
    local gs = xDTaraZ.GameLib.Service.GameService
    if not (gs and gs.IsJoined and gs.IsJoined()) then
        xDTaraZ.Player.Respawn.Status = "Not in game"
        return
    end
    if not xDTaraZ.Player.Respawn.IsDead() then
        xDTaraZ.Player.Respawn.Status = "Alive · respawns " .. xDTaraZ.Player.Respawn.Count
        return
    end

    local now = os.clock()
    if now - xDTaraZ.Player.Respawn.LastFire < xDTaraZ.Config.RespawnRetry then
        xDTaraZ.Player.Respawn.Status = "Respawning"
        return
    end
    xDTaraZ.Player.Respawn.LastFire = now
    xDTaraZ.Player.Respawn.Count += 1
    xDTaraZ.Player.Respawn.Fire()
    xDTaraZ.Player.Respawn.Status = "Respawning"
end

function xDTaraZ.Player.Respawn.GetStatus()
    return xDTaraZ.Player.Respawn.Status
end

xDTaraZ.Movement = { Booted = false, Dash = nil }

---@return ModuleScript?  dash helper, searched by name if CombatHelper moved
function xDTaraZ.Movement.FindDash()
    local client = ReplicatedStorage:FindFirstChild("Client")
    local helper = client and client:FindFirstChild("CombatHelper")
    local dash = helper and helper:FindFirstChild("Dash")
    if dash and dash:IsA("ModuleScript") then return dash end
    helper = ReplicatedStorage:FindFirstChild("CombatHelper", true)
    dash = helper and helper:FindFirstChild("Dash")
    return dash and dash:IsA("ModuleScript") and dash or nil
end

function xDTaraZ.Movement.DashHelper()
    if xDTaraZ.Movement.Dash ~= nil then return xDTaraZ.Movement.Dash end
    local dash = xDTaraZ.Movement.FindDash()
    xDTaraZ.Movement.Dash = dash and GameLib.Require(dash) or false
    return xDTaraZ.Movement.Dash
end

function xDTaraZ.Movement.OnStepped()
    if not xDTaraZ.Options.InfiniteDash then return end
    local dash = xDTaraZ.Movement.DashHelper()
    if dash and dash.RefreshNextDashTime then pcall(dash.RefreshNextDashTime) end
end

function xDTaraZ.Movement.Start()
    if xDTaraZ.Movement.Booted then return end
    xDTaraZ.Movement.Booted = true
    xDTaraZ:Connect(RunService.Stepped, xDTaraZ.Movement.OnStepped)
end

function xDTaraZ.Movement.GetStatus()
    return xDTaraZ.Options.InfiniteDash and "Infinite dash" or "Off"
end

xDTaraZ.Esp = { Count = 0 }

---@return table[]  targets in the shape Library.Visuals expects
function xDTaraZ.Esp.Targets()
    local list = {}
    for _, entity in pairs(xDTaraZ.Entity.List()) do
        if type(entity) ~= "table" or xDTaraZ.Entity.IsLocal(entity) then continue end
        local char = xDTaraZ.Entity.Character(entity)
        local health, maxHealth = xDTaraZ.Entity.Health(entity)
        if not char or health <= 0 then continue end
        local player = Players:GetPlayerFromCharacter(char)
        list[#list + 1] = {
            Model = char,
            Name = player and player.DisplayName or char.Name,
            Health = health,
            MaxHealth = maxHealth > 0 and maxHealth or 100,
            Friendly = xDTaraZ.Entity.Friendly(entity),
            Root = xDTaraZ.Entity.Root(entity),
        }
    end
    xDTaraZ.Esp.Count = #list
    return list
end

function xDTaraZ.Esp.GetStatus()
    local visuals = xDTaraZ.Library and xDTaraZ.Library.Visuals
    if not (visuals and visuals:Get("Enabled")) then return "Off" end
    return xDTaraZ.Esp.Count .. " targets"
end

---@return table?  replicated client store for a Remote service
local function StoreData(service)
    if not service then return nil end
    local ok, store = pcall(function() return service.GetData() end)
    if ok and type(store) == "table" then return store end
    if type(service.Data) == "table" then return service.Data end
    ok, store = pcall(function() return service:GetData() end)
    return ok and type(store) == "table" and store or nil
end

xDTaraZ.Shop = { Status = "Off", LastResult = "" }

---@return string[]  case keys the player actually owns (from the gacha store)
function xDTaraZ.Shop.Cases()
    local service = GameLib.Service.GachaService
    local store = service and service.LocalGachaStore
    local data = store and store.Data
    if type(data) ~= "table" then return {} end
    local keys = {}
    for key, entry in pairs(data) do
        local owned = type(entry) == "table" and entry.Owned or entry
        if tonumber(owned) and owned > 0 then keys[#keys + 1] = tostring(key) end
    end
    table.sort(keys)
    return keys
end

function xDTaraZ.Shop.Owned(caseKey)
    local service = GameLib.Service.GachaService
    if not service then return 0 end
    local ok, owned = pcall(function() return service.GetGachaCount(caseKey) end)
    return ok and tonumber(owned) or 0
end

---@return boolean, string  server-authoritative roll result
function xDTaraZ.Shop.Open(caseKey, count)
    local service = GameLib.Service.GachaService
    if not service then return false, "no service" end
    count = math.min(count, xDTaraZ.Shop.Owned(caseKey))
    if count < 1 then return false, "none owned" end
    local ok, roll = pcall(function() return service.Gacha(caseKey, count) end)
    if not ok then return false, tostring(roll) end
    return true, string.format("%s x%d", caseKey, count)
end

function xDTaraZ.Shop.OpenAllNow()
    local opened = 0
    for _, caseKey in ipairs(xDTaraZ.Shop.Cases()) do
        local owned = xDTaraZ.Shop.Owned(caseKey)
        if owned > 0 then
            local ok = xDTaraZ.Shop.Open(caseKey, math.min(owned, math.max(xDTaraZ.Options.OpenCount, 1)))
            if ok then opened += 1 end
            task.wait(xDTaraZ.Config.OpenDelay)
        end
    end
    xDTaraZ.Shop.LastResult = opened > 0 and (opened .. " cases opened") or "no owned cases"
    return xDTaraZ.Shop.LastResult
end

function xDTaraZ.Shop.Start() xDTaraZ.Options.AutoOpenCases = true end
function xDTaraZ.Shop.Stop() xDTaraZ.Options.AutoOpenCases = false end

function xDTaraZ.Shop.Step()
    if not xDTaraZ.Options.AutoOpenCases then xDTaraZ.Shop.Status = "Off" return end
    xDTaraZ.Shop.Status = "Opening owned cases"
    xDTaraZ.Shop.OpenAllNow()
end

function xDTaraZ.Shop.GetStatus()
    return xDTaraZ.Options.AutoOpenCases and xDTaraZ.Shop.Status or "Off"
end

xDTaraZ.Sell = { Status = "Off", LastResult = "" }

---@return string?  skin rarity from WrapConfig, nil for base/unknown skins
function xDTaraZ.Sell.RarityOf(weaponName)
    local skin = tostring(weaponName):match("%.(.+)$")
    local wraps = GameLib.Config.WrapConfig
    local entry = skin and type(wraps) == "table" and wraps[skin]
    return type(entry) == "table" and entry.Rarity or nil
end

---@return string[]  rarity names present in WrapConfig
function xDTaraZ.Sell.Rarities()
    local wraps = GameLib.Config.WrapConfig
    if type(wraps) ~= "table" then return {} end
    local seen = {}
    for _, entry in pairs(wraps) do
        if type(entry) == "table" and entry.Rarity then seen[tostring(entry.Rarity)] = true end
    end
    return Util.SortedKeys(seen)
end

---@return table[]  owned weapons with uid, rarity, price, wear
function xDTaraZ.Sell.Inventory()
    local service = GameLib.Service.WeaponService
    local ok, content = pcall(function() return service and service.GetContent() end)
    if not ok or type(content) ~= "table" then return {} end

    local list = {}
    for uid, weapon in pairs(content) do
        if type(weapon) == "table" then
            list[#list + 1] = {
                Uid = uid,
                Name = weapon.Name or tostring(uid),
                Rarity = xDTaraZ.Sell.RarityOf(weapon.Name),
                Price = tonumber(weapon.Price) or 0,
                Wear = tonumber(weapon.WearFactor) or 0,
            }
        end
    end
    return list
end

---@return string[]  uids matching selected rarities under the price ceiling, keeping N per rarity
function xDTaraZ.Sell.Pick()
    local wanted = Util.SetFromList(xDTaraZ.Options.SellRarities)
    local ceiling = xDTaraZ.Options.MaxSellPrice
    local kept, uids = {}, {}
    for _, weapon in ipairs(xDTaraZ.Sell.Inventory()) do
        if weapon.Rarity and wanted[weapon.Rarity] and (ceiling <= 0 or weapon.Price <= ceiling) then
            kept[weapon.Rarity] = (kept[weapon.Rarity] or 0) + 1
            if kept[weapon.Rarity] > xDTaraZ.Options.KeepPerRarity then
                uids[#uids + 1] = weapon.Uid
            end
        end
    end
    return uids
end

function xDTaraZ.Sell.SellNow()
    local service = GameLib.Service.WeaponService
    if not service then xDTaraZ.Sell.LastResult = "no service" return xDTaraZ.Sell.LastResult end

    local uids = xDTaraZ.Sell.Pick()
    if #uids == 0 then
        xDTaraZ.Sell.LastResult = "nothing to sell"
        return xDTaraZ.Sell.LastResult
    end

    local ok, response = pcall(function() return service.Sell(uids) end)
    xDTaraZ.Sell.LastResult = ok and (#uids .. " sold") or ("sell failed: " .. tostring(response))
    return xDTaraZ.Sell.LastResult
end

function xDTaraZ.Sell.Start() xDTaraZ.Options.AutoSell = true end
function xDTaraZ.Sell.Stop() xDTaraZ.Options.AutoSell = false end

function xDTaraZ.Sell.Step()
    if not xDTaraZ.Options.AutoSell then xDTaraZ.Sell.Status = "Off" return end
    xDTaraZ.Sell.Status = xDTaraZ.Sell.SellNow()
end

function xDTaraZ.Sell.GetStatus()
    return xDTaraZ.Options.AutoSell and xDTaraZ.Sell.Status or "Off"
end

xDTaraZ.Collect = { Status = "Off", LastResult = "" }

---@return table[]  claimable quest descriptors; field mapping is a live seam
function xDTaraZ.Collect.Claimable()
    local store = StoreData(GameLib.Service.QuestService)
    if not store then return {} end
    local source = store.Quests or store.Active or store.Daily or store
    if type(source) ~= "table" then return {} end

    local list = {}
    for key, quest in pairs(source) do
        if type(quest) == "table" then
            local done = quest.Completed or quest.IsComplete or quest.Done
            local claimed = quest.Claimed or quest.IsClaimed
            if done and not claimed then
                list[#list + 1] = quest.Id or quest.QuestId or quest.Key or key
            end
        end
    end
    return list
end

function xDTaraZ.Collect.ClaimNow()
    local service = GameLib.Service.QuestService
    if not service then xDTaraZ.Collect.LastResult = "no service" return xDTaraZ.Collect.LastResult end

    local ids = xDTaraZ.Collect.Claimable()
    if #ids == 0 then
        xDTaraZ.Collect.LastResult = "nothing to claim"
        return xDTaraZ.Collect.LastResult
    end

    local claimed = 0
    for _, id in ipairs(ids) do
        local ok = pcall(function() return service.ClaimReward(id) end)
        if ok then claimed += 1 end
        task.wait(xDTaraZ.Config.ClaimDelay)
    end
    xDTaraZ.Collect.LastResult = claimed .. " quests claimed"
    return xDTaraZ.Collect.LastResult
end

function xDTaraZ.Collect.Start() xDTaraZ.Options.AutoClaimQuest = true end
function xDTaraZ.Collect.Stop() xDTaraZ.Options.AutoClaimQuest = false end

function xDTaraZ.Collect.Step()
    if not xDTaraZ.Options.AutoClaimQuest then xDTaraZ.Collect.Status = "Off" return end
    xDTaraZ.Collect.Status = xDTaraZ.Collect.ClaimNow()
end

function xDTaraZ.Collect.GetStatus()
    return xDTaraZ.Options.AutoClaimQuest and xDTaraZ.Collect.Status or "Off"
end

xDTaraZ.Combat = { State = "Idle", Status = "Off", Target = nil, Part = nil, Look = nil, Bound = false, LastShot = 0, Circle = nil, OriginFn = nil, OriginParams = nil, LookSource = nil, LookHolders = nil, LockedSince = 0 }

local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude

function xDTaraZ.Combat.AimActive()
    return xDTaraZ.Options.Aimbot == true
end

function xDTaraZ.Combat.SilentActive()
    return xDTaraZ.Options.SilentAim == true or xDTaraZ.Options.Ragebot == true
end

function xDTaraZ.Combat.Active()
    local o = xDTaraZ.Options
    return o.Aimbot or o.SilentAim or o.Ragebot or o.TriggerBot or o.ShowFov
end

---@return BasePart?  server hitbox for the chosen bone
function xDTaraZ.Combat.BonePart(entity, bone)
    local char = xDTaraZ.Entity.Character(entity)
    if not char then return nil end
    local collider = char:FindFirstChild("Collider")
    bone = bone or xDTaraZ.Options.AimBone or "Head"
    return collider and (collider:FindFirstChild(bone) or collider:FindFirstChild("Head"))
        or char:FindFirstChild("Head")
        or xDTaraZ.Entity.Root(entity)
end

function xDTaraZ.Combat.Filter()
    local cam = Workspace.CurrentCamera
    aimParams.FilterDescendantsInstances = { cam, xDTaraZ.Entity.Character(xDTaraZ.Entity.Local()) }
    return cam
end

---@return CFrame, any  where the game fires bullets from, detect tag
function xDTaraZ.Combat.Origin()
    local fn = xDTaraZ.Combat.OriginFn
    if not fn then
        local camCtrl = xDTaraZ.GameLib.CameraController
        fn = camCtrl and camCtrl.GetCombatOriginFn and camCtrl.GetCombatOriginFn()
        xDTaraZ.Combat.OriginFn = fn
    end
    if fn then
        local ok, origin, detect = pcall(fn)
        if ok and typeof(origin) == "CFrame" then return origin, detect end
    end
    return Workspace.CurrentCamera.CFrame, nil
end

function xDTaraZ.Combat.Visible(part, char)
    xDTaraZ.Combat.Filter()
    local origin = xDTaraZ.Combat.Origin().Position
    local hit = Workspace:Raycast(origin, part.Position - origin, aimParams)
    return hit ~= nil and hit.Instance:IsDescendantOf(char)
end

function xDTaraZ.Combat.IsEnemy(entity)
    if type(entity) ~= "table" or xDTaraZ.Entity.IsLocal(entity) then return false end
    if xDTaraZ.Options.AimTeamCheck and xDTaraZ.Entity.Friendly(entity) then return false end
    local inst = entity.Instance
    if typeof(inst) == "Instance" and inst:GetAttribute("State") == "Dead" then return false end
    return xDTaraZ.Entity.Health(entity) > 0
end

---@return Vector3  part position led by its velocity
function xDTaraZ.Combat.Predict(part)
    local lead = (xDTaraZ.Options.AimPrediction or 0) / 1000
    if lead <= 0 then return part.Position end
    return part.Position + part.AssemblyLinearVelocity * lead
end

---@return table?, BasePart?  best target inside the FOV circle
---@return Vector2  screen point the FOV circle is centred on
function xDTaraZ.Combat.AimCenter(cam)
    if xDTaraZ.Options.AimPriority == "Mouse" then return UserInputService:GetMouseLocation() end
    return cam.ViewportSize / 2
end

function xDTaraZ.Combat.UsesFov()
    if xDTaraZ.Options.Ragebot then return false end
    local mode = xDTaraZ.Options.AimPriority
    return mode == "Crosshair" or mode == "Mouse"
end

---@return number?  lower is better, nil when the target is filtered out
function xDTaraZ.Combat.Score(entity, part, cam, center, origin)
    local dist = (part.Position - origin).Magnitude
    if dist > xDTaraZ.Options.AimMaxDistance then return nil end

    if xDTaraZ.Combat.UsesFov() then
        local screen, onScreen = cam:WorldToViewportPoint(part.Position)
        if not onScreen then return nil end
        local gap = (Vector2.new(screen.X, screen.Y) - center).Magnitude
        if gap > xDTaraZ.Options.AimFov then return nil end
        return gap
    end
    if xDTaraZ.Options.AimPriority == "Health" then
        return xDTaraZ.Entity.Health(entity) * 10000 + dist
    end
    return dist
end

---@return table?, BasePart?  best target for the chosen priority mode
function xDTaraZ.Combat.SelectTarget()
    local cam = Workspace.CurrentCamera
    if not cam then return nil end
    local center = xDTaraZ.Combat.AimCenter(cam)
    local origin = cam.CFrame.Position
    local best, bestPart, bestScore

    for _, entity in pairs(xDTaraZ.Entity.List()) do
        if not xDTaraZ.Combat.IsEnemy(entity) then continue end
        local part = xDTaraZ.Combat.BonePart(entity)
        if not part then continue end
        local score = xDTaraZ.Combat.Score(entity, part, cam, center, origin)
        if not score or (bestScore and score >= bestScore) then continue end
        if (xDTaraZ.Options.AimWallCheck or xDTaraZ.Options.Ragebot) and not xDTaraZ.Combat.Visible(part, xDTaraZ.Entity.Character(entity)) then continue end
        best, bestPart, bestScore = entity, part, score
    end
    return best, bestPart
end

function xDTaraZ.Combat.BindCamera()
    if xDTaraZ.Combat.Bound then return end
    xDTaraZ.Combat.Bound = true
    RunService:BindToRenderStep("xDTaraZAim", xDTaraZ.Config.AimRenderPriority, function()
        local c = xDTaraZ.Combat
        local cam = Workspace.CurrentCamera
        local part = c.Part
        if not (c.AimActive() and part and part.Parent) then
            xDTaraZ.Combat.Look = nil
            return
        end
        local origin = cam.CFrame.Position
        local want = (xDTaraZ.Combat.Predict(part) - origin).Unit
        local smooth = math.max(xDTaraZ.Options.AimSmooth or 1, 1)
        local look = xDTaraZ.Combat.Look or cam.CFrame.LookVector
        look = smooth <= 1 and want or look:Lerp(want, 1 / smooth).Unit
        xDTaraZ.Combat.Look = look
        cam.CFrame = CFrame.lookAt(origin, origin + look)
    end)
end

function xDTaraZ.Combat.UnbindCamera()
    if not xDTaraZ.Combat.Bound then return end
    xDTaraZ.Combat.Bound = false
    RunService:UnbindFromRenderStep("xDTaraZAim")
end

---@return boolean  crosshair currently on an enemy hitbox
function xDTaraZ.Combat.CrosshairOnEnemy()
    xDTaraZ.Combat.Filter()
    local origin = xDTaraZ.Combat.Origin()
    local hit = Workspace:Raycast(origin.Position, origin.LookVector * xDTaraZ.Config.TriggerRange, aimParams)
    if not hit then return false end
    for _, entity in pairs(xDTaraZ.Entity.List()) do
        local char = xDTaraZ.Entity.Character(entity)
        if char and hit.Instance:IsDescendantOf(char) then return xDTaraZ.Combat.IsEnemy(entity) end
    end
    return false
end

---@return boolean  true when the weapon accepted the shot
function xDTaraZ.Combat.Fire()
    local now = os.clock()
    if now - xDTaraZ.Combat.LastShot < xDTaraZ.Config.FireInterval then return false end
    xDTaraZ.Combat.LastShot = now

    local _, shooter = xDTaraZ.Combat.Shooter()
    if not shooter then return false end

    local ok, fired = pcall(shooter.LocalShoot, shooter)
    if not ok then warn("[SniperArena] shoot:", fired) end
    return ok and fired ~= nil
end

function xDTaraZ.Combat.Shooter()
    local combat = xDTaraZ.GameLib.Service.CombatService
    local weapon = combat and combat.GetCurrentWeapon()
    return weapon, weapon and weapon._Shootable
end

xDTaraZ.Combat.SilentSaved = {}

---@return table?  the game's combat-origin override table
function xDTaraZ.Combat.OriginOverride()
    if xDTaraZ.Combat.OriginParams ~= nil then return xDTaraZ.Combat.OriginParams or nil end
    if not xDTaraZ.Caps.Upvalues then return nil end
    local camCtrl = xDTaraZ.GameLib.CameraController
    local ok, holder = pcall(function() return Util.GetUpvalue(camCtrl.GetCombatOriginFn(), 1) end)
    local params = ok and type(holder) == "table" and type(holder.TempParams) == "table" and holder.TempParams
    xDTaraZ.Combat.OriginParams = params or false
    return params or nil
end

---@return any  what the game's Shoot returns
function xDTaraZ.Combat.ShootAt(shooter, entity, part, opts)
    local params = xDTaraZ.Combat.OriginOverride()
    local start = xDTaraZ.Combat.Origin().Position
    local aim = xDTaraZ.Combat.Predict(part)
    opts = type(opts) == "table" and opts or {}
    opts.Target = entity.Instance
    opts.TargetHeadshot = part.Name == "Head" or nil
    local ok, localPos = pcall(function() return entity:GetPivot(true):PointToObjectSpace(aim) end)
    if ok then opts.TargetPos = localPos end

    local saved = { params.CameraCFrame, params.SubjectDistance, params.MouseLockOffset }
    params.CameraCFrame, params.SubjectDistance, params.MouseLockOffset = CFrame.lookAt(start, aim), 0, Vector3.zero
    local fired, shot = pcall(shooter.Shoot, shooter, start, (aim - start).Unit, opts)
    params.CameraCFrame, params.SubjectDistance, params.MouseLockOffset = saved[1], saved[2], saved[3]
    if not fired then warn("[SniperArena] silent:", shot) end
    return fired and shot or nil
end

---@return any  same as the game's LocalShoot, bullet sent at the locked target
function xDTaraZ.Combat.SilentShoot(shooter, opts)
    local c = xDTaraZ.Combat
    local saved = c.SilentSaved[shooter]
    local entity = c.Target
    if not (c.SilentActive() and entity and c.OriginOverride()) then return saved.Fn(shooter, opts) end
    if math.random(100) > xDTaraZ.Options.HitChance then return saved.Fn(shooter, opts) end

    local bone = math.random(100) <= xDTaraZ.Options.HeadChance and "Head" or "Body"
    local part = c.BonePart(entity, bone)
    if not (part and part.Parent) then return saved.Fn(shooter, opts) end
    return c.ShootAt(shooter, entity, part, opts)
end

---@return CFrame  camera the server is told we look through
function xDTaraZ.Combat.ReportedLook(...)
    local c = xDTaraZ.Combat
    local cf = c.LookSource(...)
    local part = c.Part
    if typeof(cf) ~= "CFrame" or not (c.SilentActive() and c.Target and part and part.Parent) then return cf end
    return CFrame.lookAt(cf.Position, c.Predict(part))
end

---@return table[]  tables that really hold CameraController's functions
function xDTaraZ.Combat.LookTables()
    local camCtrl = xDTaraZ.GameLib.CameraController
    local tables = {}
    if type(camCtrl) ~= "table" then return tables end
    if rawget(camCtrl, "GetCFrame") and not table.isfrozen(camCtrl) then tables[1] = camCtrl end
    local mt = Util.GetRawMetatable and Util.GetRawMetatable(camCtrl)
    local index = type(mt) == "table" and rawget(mt, "__index")
    if type(index) == "table" then index = { index } elseif type(index) == "function" and Util.GetUpvalues then index = Util.GetUpvalues(index) else index = {} end
    for _, holder in pairs(index) do
        if type(holder) == "table" and type(rawget(holder, "GetCFrame")) == "function" and not table.isfrozen(holder) then
            tables[#tables + 1] = holder
        end
    end
    return tables
end

function xDTaraZ.Combat.ApplyLook()
    local c = xDTaraZ.Combat
    if c.LookSource ~= nil then return end
    local tables = c.LookTables()
    if #tables == 0 then
        c.LookSource = false
        return
    end
    c.LookSource = rawget(tables[1], "GetCFrame")
    c.LookHolders = tables
    for _, holder in ipairs(tables) do rawset(holder, "GetCFrame", c.ReportedLook) end
end

function xDTaraZ.Combat.RestoreLook()
    local c = xDTaraZ.Combat
    if not c.LookSource then
        c.LookSource = nil
        return
    end
    for _, holder in ipairs(c.LookHolders or {}) do
        if rawget(holder, "GetCFrame") == c.ReportedLook then rawset(holder, "GetCFrame", c.LookSource) end
    end
    c.LookSource, c.LookHolders = nil, nil
end

function xDTaraZ.Combat.ApplySilent()
    local _, shooter = xDTaraZ.Combat.Shooter()
    if type(shooter) ~= "table" or rawget(shooter, "LocalShoot") == xDTaraZ.Combat.SilentShoot then return end
    if type(shooter.Shoot) ~= "function" then return end
    xDTaraZ.Combat.SilentSaved[shooter] = { Raw = rawget(shooter, "LocalShoot"), Fn = shooter.LocalShoot }
    rawset(shooter, "LocalShoot", xDTaraZ.Combat.SilentShoot)
end

function xDTaraZ.Combat.RestoreSilent()
    for shooter, saved in pairs(xDTaraZ.Combat.SilentSaved) do
        rawset(shooter, "LocalShoot", saved.Raw)
    end
    table.clear(xDTaraZ.Combat.SilentSaved)
end

xDTaraZ.Combat.ScopeSaved = {}

function xDTaraZ.Combat.ApplyInstantScope()
    local weapon = xDTaraZ.Combat.Shooter()
    local cfg = weapon and weapon.Config
    if type(cfg) ~= "table" or rawget(cfg, "AimTime") == 0 then return end
    if not xDTaraZ.Combat.ScopeSaved[cfg] then
        xDTaraZ.Combat.ScopeSaved[cfg] = { rawget(cfg, "AimTime"), rawget(cfg, "DelayTime") }
    end
    rawset(cfg, "AimTime", 0)
    rawset(cfg, "DelayTime", 0)
end

function xDTaraZ.Combat.RestoreScope()
    for cfg, saved in pairs(xDTaraZ.Combat.ScopeSaved) do
        rawset(cfg, "AimTime", saved[1])
        rawset(cfg, "DelayTime", saved[2])
    end
    table.clear(xDTaraZ.Combat.ScopeSaved)
end

---@return table  { Drawing = circle }, or { Frame = ring } as a Gui circle when Drawing is missing
function xDTaraZ.Combat.MakeCircle()
    local color = xDTaraZ.Config.FovColor
    if xDTaraZ.Caps.Drawing then
        local circle = Drawing.new("Circle")
        circle.Thickness, circle.NumSides, circle.Filled = 1.5, 64, false
        circle.Color = color
        return { Drawing = circle }
    end

    local ring = Instance.new("Frame")
    ring.AnchorPoint = Vector2.new(0.5, 0.5)
    ring.BackgroundTransparency = 1
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = ring
    local stroke = Instance.new("UIStroke")
    stroke.Color = color
    stroke.Thickness = 1.5
    stroke.Parent = ring
    ring.Parent = Util.Overlay()
    return { Frame = ring }
end

function xDTaraZ.Combat.SetCircleVisible(visible)
    local circle = xDTaraZ.Combat.Circle
    if not circle then return end
    if circle.Drawing then circle.Drawing.Visible = visible else circle.Frame.Visible = visible end
end

function xDTaraZ.Combat.UpdateCircle()
    if not xDTaraZ.Options.ShowFov then
        xDTaraZ.Combat.SetCircleVisible(false)
        return
    end
    local circle = xDTaraZ.Combat.Circle
    if not circle then
        circle = xDTaraZ.Combat.MakeCircle()
        xDTaraZ.Combat.Circle = circle
    end

    local center = xDTaraZ.Combat.AimCenter(Workspace.CurrentCamera)
    local radius = xDTaraZ.Options.AimFov
    if circle.Drawing then
        circle.Drawing.Position, circle.Drawing.Radius, circle.Drawing.Visible = center, radius, true
        return
    end
    circle.Frame.Position = UDim2.fromOffset(center.X, center.Y)
    circle.Frame.Size = UDim2.fromOffset(radius * 2, radius * 2)
    circle.Frame.Visible = true
end

function xDTaraZ.Combat.DrawCircle()
    local ok, err = pcall(xDTaraZ.Combat.UpdateCircle)
    if ok then
        xDTaraZ.Faults.Clear("FOV circle")
    else
        xDTaraZ.Faults.Report("FOV circle", err, { "ShowFov" })
    end
end

xDTaraZ.Combat.RecoilSaved = {}
xDTaraZ.Combat.ZoomSaved = {}

function xDTaraZ.Combat.ApplyNoRecoil()
    local combat = xDTaraZ.GameLib.Service.CombatService
    local weapon = combat and combat.GetCurrentWeapon()
    local cfg = weapon and weapon.Config
    if type(cfg) ~= "table" then return end
    if type(cfg.RecoilZoom) == "number" and cfg.RecoilZoom ~= 0 then
        xDTaraZ.Combat.ZoomSaved[cfg] = xDTaraZ.Combat.ZoomSaved[cfg] or cfg.RecoilZoom
        cfg.RecoilZoom = 0
    end
    for _, key in ipairs({ "Recoil", "RecoilAiming" }) do
        local recoil = cfg[key]
        if type(recoil) == "table" and recoil.Degree ~= 0 then
            if xDTaraZ.Combat.RecoilSaved[recoil] == nil then xDTaraZ.Combat.RecoilSaved[recoil] = recoil.Degree end
            recoil.Degree = 0
        end
    end
end

xDTaraZ.Combat.SpreadSaved = {}

function xDTaraZ.Combat.ZeroSpread()
    return 0
end

function xDTaraZ.Combat.ApplyNoSpread()
    local combat = xDTaraZ.GameLib.Service.CombatService
    local weapon = combat and combat.GetCurrentWeapon()
    local shooter = weapon and weapon._Shootable
    if type(shooter) ~= "table" or rawget(shooter, "GetCurrentSpread") == xDTaraZ.Combat.ZeroSpread then return end
    xDTaraZ.Combat.SpreadSaved[shooter] = { rawget(shooter, "GetCurrentSpread") }
    rawset(shooter, "GetCurrentSpread", xDTaraZ.Combat.ZeroSpread)
end

function xDTaraZ.Combat.RestoreSpread()
    for shooter, original in pairs(xDTaraZ.Combat.SpreadSaved) do
        rawset(shooter, "GetCurrentSpread", original[1])
    end
    table.clear(xDTaraZ.Combat.SpreadSaved)
end

function xDTaraZ.Combat.RestoreRecoil()
    for recoil, degree in pairs(xDTaraZ.Combat.RecoilSaved) do recoil.Degree = degree end
    for cfg, zoom in pairs(xDTaraZ.Combat.ZoomSaved) do cfg.RecoilZoom = zoom end
    table.clear(xDTaraZ.Combat.RecoilSaved)
    table.clear(xDTaraZ.Combat.ZoomSaved)
end

function xDTaraZ.Combat.Patches()
    local o, c = xDTaraZ.Options, xDTaraZ.Combat
    if o.NoRecoil then
        c.ApplyNoRecoil()
    elseif next(c.RecoilSaved) or next(c.ZoomSaved) then
        c.RestoreRecoil()
    end
    if o.NoSpread then c.ApplyNoSpread() elseif next(c.SpreadSaved) then c.RestoreSpread() end
    if o.InstantScope or o.Ragebot or o.SilentAim then c.ApplyInstantScope() elseif next(c.ScopeSaved) then c.RestoreScope() end
    if c.SilentActive() then
        c.ApplySilent()
        c.ApplyLook()
    else
        if next(c.SilentSaved) then c.RestoreSilent() end
        c.RestoreLook()
    end
end

function xDTaraZ.Combat.Step()
    local c = xDTaraZ.Combat
    c.Patches()
    if not c.Active() then
        if c.State ~= "Idle" then c.Stop() end
        return
    end
    if not xDTaraZ.Match.InRound() then
        c.Target, c.Part = nil, nil
        c.State, c.Status = "Wait", "Waiting for round"
        return
    end

    local mode = xDTaraZ.Match.Info() or "?"
    if c.AimActive() then c.BindCamera() else c.UnbindCamera() end
    if c.AimActive() or c.SilentActive() then
        local target, part = c.SelectTarget()
        if target ~= c.Target then c.LockedSince = os.clock() end
        c.Target, c.Part = target, part
        c.State = target and "Locked" or "Acquire"
        local char = target and xDTaraZ.Entity.Character(target)
        c.Status = mode .. " · " .. (char and char.Name or "no target")
    else
        c.Target, c.Part = nil, nil
        c.State, c.Status = "Ready", mode .. " · aim idle"
    end

    local settled = c.Target ~= nil and os.clock() - c.LockedSince >= xDTaraZ.Config.LookSettle
    local shoot = (xDTaraZ.Options.Ragebot and settled) or (xDTaraZ.Options.TriggerBot and c.CrosshairOnEnemy())
    if shoot and c.Fire() then c.State = "Fired" end
end

function xDTaraZ.Combat.Stop()
    xDTaraZ.Combat.UnbindCamera()
    xDTaraZ.Combat.Target, xDTaraZ.Combat.Part = nil, nil
    xDTaraZ.Combat.State, xDTaraZ.Combat.Status = "Idle", "Off"
end

function xDTaraZ.Combat.Rest()
    local c = xDTaraZ.Combat
    for _, undo in ipairs({ c.Stop, c.RestoreRecoil, c.RestoreSpread, c.RestoreScope, c.RestoreSilent, c.RestoreLook }) do
        Util.Try("combat restore", undo)
    end
end

function xDTaraZ.Combat.Unload()
    xDTaraZ.Combat.Stop()
    xDTaraZ.Combat.RestoreRecoil()
    xDTaraZ.Combat.RestoreSpread()
    xDTaraZ.Combat.RestoreScope()
    xDTaraZ.Combat.RestoreSilent()
    xDTaraZ.Combat.RestoreLook()
    local circle = xDTaraZ.Combat.Circle
    xDTaraZ.Combat.Circle = nil
    if not circle then return end
    if circle.Frame then
        circle.Frame:Destroy()
    else
        pcall(function() circle.Drawing:Remove() end)
    end
end

function xDTaraZ.Combat.GetStatus()
    return xDTaraZ.Combat.Status
end

xDTaraZ.Skin = {
    Catalog = {},
    Types = {},
    Rarities = {},
    Labels = {},
    Chosen = {},
    Saved = setmetatable({}, { __mode = "k" }),
    Status = "Off",
    RarityRank = { Common = 1, UnCommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mystic = 6 },
    Hidden = { Charm = true },
}

---@return string?, string?  weapon type and family, nil for non-weapons
function xDTaraZ.Skin.Classify(cfg)
    if type(cfg) ~= "table" then return nil end
    local ok, kind, family = pcall(function() return cfg.WeaponType, cfg.Family end)
    if not ok or type(kind) ~= "string" or type(family) ~= "string" then return nil end
    if xDTaraZ.Skin.Hidden[kind] or family:find("^Base") then return nil end
    return kind, family
end

do
    local configs = xDTaraZ.GameLib.Config.WeaponConfig or {}
    for key, cfg in pairs(configs) do
        if type(key) ~= "string" then continue end
        local kind, family = xDTaraZ.Skin.Classify(cfg)
        if not kind then continue end
        local byFamily = xDTaraZ.Skin.Catalog[kind]
        if not byFamily then
            byFamily = {}
            xDTaraZ.Skin.Catalog[kind] = byFamily
            table.insert(xDTaraZ.Skin.Types, kind)
        end
        byFamily[family] = byFamily[family] or {}
        local rarity = tostring(cfg.Rarity or "Common")
        table.insert(byFamily[family], { key, rarity, type(cfg.Display) == "string" and cfg.Display or key })
        if not table.find(xDTaraZ.Skin.Rarities, rarity) then table.insert(xDTaraZ.Skin.Rarities, rarity) end
    end
    table.sort(xDTaraZ.Skin.Types)
    table.sort(xDTaraZ.Skin.Rarities, function(a, b)
        local ra, rb = xDTaraZ.Skin.RarityRank[a] or 0, xDTaraZ.Skin.RarityRank[b] or 0
        if ra ~= rb then return ra > rb end
        return a < b
    end)
    for _, byFamily in pairs(xDTaraZ.Skin.Catalog) do
        for _, list in pairs(byFamily) do
            table.sort(list, function(a, b)
                local ra, rb = xDTaraZ.Skin.RarityRank[a[2]] or 0, xDTaraZ.Skin.RarityRank[b[2]] or 0
                if ra ~= rb then return ra > rb end
                return a[3] < b[3]
            end)
        end
    end
end

function xDTaraZ.Skin.Families(kind)
    return Util.SortedKeys(xDTaraZ.Skin.Catalog[kind])
end

---@param rarities table?  set of rarities to show, empty = all
---@return string[]  labels for the dropdown, best rarity first
function xDTaraZ.Skin.List(kind, family, rarities)
    local list = xDTaraZ.Skin.Catalog[kind] and xDTaraZ.Skin.Catalog[kind][family]
    local names = {}
    if not list then return names end
    local filter = rarities and next(rarities) ~= nil and rarities or nil
    for _, skin in ipairs(list) do
        if filter and not filter[skin[2]] then continue end
        local label = string.format("[%s] %s", skin[2], skin[3])
        if xDTaraZ.Skin.Labels[label] and xDTaraZ.Skin.Labels[label] ~= skin[1] then label = label .. " · " .. skin[1] end
        xDTaraZ.Skin.Labels[label] = skin[1]
        names[#names + 1] = label
    end
    return names
end

function xDTaraZ.Skin.Choose(family, label)
    xDTaraZ.Skin.Chosen[family] = label and xDTaraZ.Skin.Labels[label] or nil
end

function xDTaraZ.Skin.ClearAll()
    table.clear(xDTaraZ.Skin.Chosen)
end

---@return table[]  every weapon the local player carries
function xDTaraZ.Skin.Carried()
    local combat = xDTaraZ.GameLib.Service.CombatService
    local ok, weapons = pcall(function() return combat.GetWeapons() end)
    local list = {}
    if ok and type(weapons) == "table" then
        for _, weapon in pairs(weapons) do
            if type(weapon) == "table" and weapon.Name then list[#list + 1] = weapon end
        end
    end
    local held = combat and combat.GetCurrentWeapon()
    if held and not table.find(list, held) then list[#list + 1] = held end
    return list
end

function xDTaraZ.Skin.Rebuild(weapon)
    local controllers = xDTaraZ.GameLib.WeaponController
    local entity = xDTaraZ.GameLib.Service.EntityService.LocalEntity
    if not (controllers and entity and weapon.Controller) then return end
    weapon.Controller:Destroy()
    controllers.Create(entity, weapon)
end

function xDTaraZ.Skin.Apply(weapon, key)
    local cfg = xDTaraZ.GameLib.Config.WeaponConfig[key]
    if not cfg then return end
    if not xDTaraZ.Skin.Saved[weapon] then xDTaraZ.Skin.Saved[weapon] = { weapon.Name, weapon.Config } end
    weapon.Name, weapon.Config = key, cfg
    xDTaraZ.Skin.Rebuild(weapon)
end

function xDTaraZ.Skin.Revert(weapon)
    local saved = xDTaraZ.Skin.Saved[weapon]
    if not saved then return end
    weapon.Name, weapon.Config = saved[1], saved[2]
    xDTaraZ.Skin.Saved[weapon] = nil
    xDTaraZ.Skin.Rebuild(weapon)
end

function xDTaraZ.Skin.Restore()
    for weapon in pairs(xDTaraZ.Skin.Saved) do xDTaraZ.Skin.Revert(weapon) end
end

function xDTaraZ.Skin.Step()
    if not xDTaraZ.Options.SkinChanger then
        if next(xDTaraZ.Skin.Saved) then xDTaraZ.Skin.Restore() end
        xDTaraZ.Skin.Status = "Off"
        return
    end

    local applied = 0
    for _, weapon in ipairs(xDTaraZ.Skin.Carried()) do
        local saved = xDTaraZ.Skin.Saved[weapon]
        local originalCfg = saved and saved[2] or weapon.Config
        local _, family = xDTaraZ.Skin.Classify(originalCfg)
        local key = family and xDTaraZ.Skin.Chosen[family]
        if key then
            if weapon.Name ~= key then xDTaraZ.Skin.Apply(weapon, key) end
            applied += 1
        elseif saved then
            xDTaraZ.Skin.Revert(weapon)
        end
    end
    xDTaraZ.Skin.Status = applied > 0 and (applied .. " weapon(s) skinned") or "Pick a skin"
end

function xDTaraZ.Skin.GetStatus()
    return xDTaraZ.Skin.Status
end

xDTaraZ.UI = { Labels = {}, Shown = {}, Stats = { Cases = 0, Quests = 0 } }
local Library, T

function xDTaraZ.UI.Detach(fn)
    return function(...)
        local packed = table.pack(...)
        task.defer(function()
            local ok, err = pcall(fn, table.unpack(packed, 1, packed.n))
            if not ok then warn("[SniperArena] ui: " .. tostring(err)) end
        end)
    end
end

---@param module table  feature with Start/Stop
function xDTaraZ.UI.StartStop(module)
    return xDTaraZ.UI.Detach(function(on)
        if on then module.Start() else module.Stop() end
    end)
end

---@param widget table  option whose value mirrors an Options key
function xDTaraZ.UI.Bind(widget, key, transform)
    local function Apply(value)
        if transform then value = transform(value) end
        xDTaraZ.Options[key] = value
    end
    Apply(widget.Value)
    widget:OnChanged(Apply)
    return widget
end

function xDTaraZ.UI.SampleStats()
    local cases = 0
    for _, caseKey in ipairs(xDTaraZ.Shop.Cases()) do
        cases += xDTaraZ.Shop.Owned(caseKey)
    end
    xDTaraZ.UI.Stats.Cases = cases
    xDTaraZ.UI.Stats.Quests = #xDTaraZ.Collect.Claimable()
end

function xDTaraZ.UI.Panic()
    for idx, toggle in pairs(Library.Toggles) do
        if toggle.Value ~= true or toggle.Style == "Checkbox" then continue end
        if string.sub(idx, 1, 5) == "Nova" and not xDTaraZ.Config.PanicNova[idx] then continue end
        toggle:SetValue(false)
    end
end

---@param title table  T() pair; the UI pump shows it, game-module threads can't
function xDTaraZ.UI.Notice(title, text, kind)
    table.insert(xDTaraZ.State.Notices, { title, tostring(text), kind })
end

function xDTaraZ.UI.BuildMain(window)
    window:AddTabSection(T("Main", "หลัก"))
    local tab = window:AddTab(T("Main", "หลัก"), "mushroom", T("Status and links", "สถานะและลิงก์"))

    local status = tab:AddLeftGroupbox(T("Status", "สถานะ"), "star")
    xDTaraZ.UI.Labels.Esp = status:AddParagraph({ Title = T("ESP", "ESP"), Content = "-" })
    xDTaraZ.UI.Labels.Combat = status:AddParagraph({ Title = T("Combat", "การต่อสู้"), Content = "-" })
    xDTaraZ.UI.Labels.Skin = status:AddParagraph({ Title = T("Skin", "สกิน"), Content = "-" })
    xDTaraZ.UI.Labels.Economy = status:AddParagraph({ Title = T("Economy", "เศรษฐกิจ"), Content = "-" })

    local panic = tab:AddLeftGroupbox(T("Quick", "ด่วน"), "bomb")
    panic:AddButton({ Text = T("Panic — all off", "ฉุกเฉิน ปิดทั้งหมด"), Style = "Danger", Func = xDTaraZ.UI.Detach(xDTaraZ.UI.Panic) })

    local live = tab:AddRightGroupbox(T("Live", "ตัวเลขสด"), "coin")
    xDTaraZ.UI.Labels.Targets = live:AddParagraph({ Title = T("Enemies seen", "ศัตรูที่เห็น"), Content = "0" })
    xDTaraZ.UI.Labels.Cases = live:AddParagraph({ Title = T("Cases owned", "กล่องที่มี"), Content = "0" })
    xDTaraZ.UI.Labels.Quests = live:AddParagraph({ Title = T("Quests ready", "เควสต์รอรับ"), Content = "0" })

    local discord = tab:AddRightGroupbox(T("Discord", "ดิสคอร์ด"), "link")
    discord:AddLabel(xDTaraZ.Config.Discord)
    discord:AddButton({ Text = T("Copy Discord Link", "คัดลอกลิงก์ดิสคอร์ด"), Func = xDTaraZ.UI.Detach(function()
        if Util.Copy(xDTaraZ.Config.Discord) then
            Library:Notify(T("Discord", "ดิสคอร์ด"), T("Link copied", "คัดลอกลิงก์แล้ว"), 3, "Success")
        else
            Library:Notify(T("Discord", "ดิสคอร์ด"), xDTaraZ.Config.Discord, 6, "Info")
        end
    end) })

    local logBox = tab:AddRightGroupbox(T("Update Log", "อัปเดตล่าสุด"), "bell")
    for i = 1, math.min(2, #xDTaraZ.Config.UpdateLog) do
        local entry = xDTaraZ.Config.UpdateLog[i]
        logBox:AddParagraph({ Title = entry[1], Content = entry[2] })
    end
end

function xDTaraZ.UI.GuardSilent()
    local reason = T("Not supported on this executor", "ใช้กับ executor นี้ไม่ได้")
    for _, idx in ipairs({ "SilentAim", "Ragebot" }) do
        Library.Compat.NeedCap(idx, "Upvalues")
        if not xDTaraZ.Caps.LookSpoof then Library.Compat.Block(idx, reason) end
    end
end

function xDTaraZ.UI.BuildCombat(window)
    window:AddTabSection(T("Combat", "การต่อสู้"))
    local tab = window:AddTab(T("Combat", "การต่อสู้"), "target", T("Aimbot and firing", "เล็งอัตโนมัติและยิง"))

    local aim = tab:AddLeftGroupbox(T("Aimbot", "เล็งอัตโนมัติ"), "crosshair")
    aim:AddToggle("Aimbot", {
        Text = T("Aimbot", "เล็งอัตโนมัติ"),
        Description = T("Locks onto the enemy nearest your crosshair", "ล็อคศัตรูที่ใกล้เป้าเล็งที่สุด"),
    }):AddKeyPicker("AimbotKey", { Default = "E", Mode = "Hold" })
    aim:AddDropdown("AimPriority", { Text = T("Target priority", "เลือกเป้าตาม"), Values = { "Crosshair", "Mouse", "Distance", "Health" }, Default = "Crosshair" })
    aim:AddSlider("AimMaxDistance", { Text = T("Max aim distance", "ระยะเล็งสูงสุด"), Min = 50, Max = 2000, Default = 1000, Suffix = "m" })
    aim:AddDropdown("AimBone", { Text = T("Aim part", "จุดเล็ง"), Values = { "Head", "Body", "Arm", "Leg" }, Default = "Head" })
    aim:AddSlider("AimSmooth", { Text = T("Smoothness", "ความนุ่ม"), Min = 1, Max = 20, Default = 1, Rounding = 0 })
    aim:AddSlider("AimPrediction", { Text = T("Prediction", "เล็งดักหน้า"), Min = 0, Max = 200, Default = 60, Suffix = "ms", Rounding = 0 })
    aim:AddSlider("AimFov", { Text = T("FOV", "ระยะมอง"), Min = 20, Max = 600, Default = 150, Suffix = "px" })
    aim:AddToggle("ShowFov", { Text = T("Show FOV circle", "แสดงวงระยะมอง") })
    aim:AddCheckbox("AimWallCheck", { Text = T("Visible only", "เฉพาะที่มองเห็น"), Default = true })
    aim:AddCheckbox("AimTeamCheck", { Text = T("Team check", "เช็คทีม"), Default = true })

    local rage = tab:AddRightGroupbox(T("Rage", "เรจ"), "bomb")
    rage:AddToggle("Ragebot", { Text = T("Ragebot", "เรจบอท"), Description = T("Shoots every visible enemy on its own, view stays still", "ยิงศัตรูทุกตัวที่มองเห็นเอง กล้องไม่ขยับ"), Risky = true })
        :AddKeyPicker("RagebotKey", { Default = "None", Mode = "Toggle" })
    rage:AddToggle("SilentAim", { Text = T("Silent aim", "ไซเลนต์เอม"), Description = T("Shots land on the target inside the FOV, your view never moves", "กระสุนเข้าเป้าในวง FOV กล้องไม่ขยับเลย") })
        :AddKeyPicker("SilentAimKey", { Default = "None", Mode = "Toggle" })
    rage:AddSlider("HitChance", { Text = T("Hit chance", "โอกาสยิงโดน"), Min = 0, Max = 100, Default = 100, Suffix = "%", Rounding = 0 })
    rage:AddSlider("HeadChance", { Text = T("Headshot chance", "โอกาสเข้าหัว"), Min = 0, Max = 100, Default = 100, Suffix = "%", Rounding = 0 })
    rage:AddToggle("InstantScope", { Text = T("Fast scope", "เปิดสโคปเร็ว"), Description = T("Cuts the wait before the scope is ready", "ลดเวลารอก่อนสโคปพร้อมยิง") })

    local fire = tab:AddRightGroupbox(T("Firing", "การยิง"), "swords")
    fire:AddToggle("TriggerBot", { Text = T("Trigger bot", "ยิงอัตโนมัติ"), Description = T("Fires the moment your crosshair is on an enemy", "ยิงทันทีเมื่อเป้าเล็งทับศัตรู"), Risky = true })
        :AddKeyPicker("TriggerBotKey", { Default = "None", Mode = "Toggle" })
    fire:AddToggle("NoSpread", { Text = T("No spread", "ยิงไม่กระจาย"), Description = T("Shots stay accurate while moving or jumping", "ยิงแม่นแม้ตอนเดินหรือกระโดด") })
    fire:AddToggle("NoRecoil", { Text = T("No recoil", "ไม่มีแรงถีบ"), Description = T("Camera no longer kicks when firing", "กล้องไม่เด้งตอนยิง") })

    xDTaraZ.UI.GuardSilent()
end

function xDTaraZ.UI.BuildPlayer(window)
    window:AddTabSection(T("Player", "ผู้เล่น"))
    local tab = window:AddTab(T("Player", "ผู้เล่น"), "oneup", T("Respawn and utility", "เกิดใหม่และอรรถประโยชน์"))

    local util = tab:AddLeftGroupbox(T("Utility", "อรรถประโยชน์"), "gear")
    util:AddToggle("FastRespawn", { Text = T("Fast respawn", "เกิดใหม่เร็ว"), Description = T("Back in the fight the moment you die", "กลับเข้าสนามทันทีที่ตาย") })
    util:AddToggle("AntiAfk", { Text = T("Anti AFK", "กันหลุด AFK"), Callback = xDTaraZ.UI.StartStop(xDTaraZ.Player.AntiAfk) })

    local move = tab:AddRightGroupbox(T("Movement", "การเคลื่อนที่"), "zap")
    move:AddToggle("InfiniteDash", { Text = T("Infinite dash", "พุ่งไม่จำกัด"), Description = T("Dash again without waiting (FFA/TDM)", "พุ่งซ้ำได้ไม่ต้องรอ (FFA/TDM)") })
end

xDTaraZ.UI.SkinKinds = {
    Sniper = { "Snipers", "สไนเปอร์", "crosshair" },
    Rifle = { "Rifles", "ไรเฟิล", "target" },
    Melee = { "Knives", "มีด", "swords" },
    Glove = { "Gloves", "ถุงมือ", "shield" },
}

---@param kind string  WeaponType from the game config
function xDTaraZ.UI.BuildSkinGroup(tab, kind, left)
    local meta = xDTaraZ.UI.SkinKinds[kind] or { kind, kind, "star" }
    local group = left and tab:AddLeftGroupbox(T(meta[1], meta[2]), meta[3]) or tab:AddRightGroupbox(T(meta[1], meta[2]), meta[3])
    local families = xDTaraZ.Skin.Families(kind)
    local weaponIdx, skinIdx = "Skin" .. kind .. "Weapon", "Skin" .. kind .. "Pick"

    local function Family()
        local picker = Library.Options[weaponIdx]
        return picker and picker.Value
    end

    local function Refill()
        local picker = Library.Options[skinIdx]
        if picker then picker:SetValues(xDTaraZ.Skin.List(kind, Family(), Util.SetFromList(xDTaraZ.Options.SkinRarities))) end
    end
    table.insert(xDTaraZ.UI.SkinRefill, Refill)

    group:AddDropdown(weaponIdx, { Text = T("Weapon", "อาวุธ"), Values = families, Default = families[1], Searchable = true, Callback = function() Refill() end })
    group:AddDropdown(skinIdx, {
        Text = T("Skin", "สกิน"),
        Values = xDTaraZ.Skin.List(kind, families[1], {}),
        Searchable = true,
        AllowNull = true,
        Callback = function(label)
            if Family() then xDTaraZ.Skin.Choose(Family(), label) end
        end,
    })
    group:AddButton({ Text = T("Use default skin", "ใช้สกินเดิม"), Func = function()
        if Family() then xDTaraZ.Skin.Choose(Family(), nil) end
        Library.Options[skinIdx]:SetValue(nil)
    end })
end

function xDTaraZ.UI.BuildSkins(window)
    xDTaraZ.UI.SkinRefill = {}
    local tab = window:AddTab(T("Skins", "สกิน"), "star", T("Every weapon, knife and glove skin", "สกินปืน มีด และถุงมือทุกแบบ"))

    local main = tab:AddLeftGroupbox(T("Skin Changer", "เปลี่ยนสกิน"), "star")
    main:AddToggle("SkinChanger", { Text = T("Skin changer", "เปลี่ยนสกิน"), Description = T("Pick any skin per weapon, only you see it", "เลือกสกินรายอาวุธได้ทุกแบบ เห็นแค่ตัวเอง") })
    local filter = main:AddDropdown("SkinRarities", {
        Text = T("Show rarities", "แสดงเฉพาะ rarity"),
        Description = T("Empty shows everything", "ไม่เลือก = แสดงทั้งหมด"),
        Values = xDTaraZ.Skin.Rarities,
        Multi = true,
        Default = {},
        AllowNull = true,
    })
    xDTaraZ.UI.Bind(filter, "SkinRarities")
    filter:OnChanged(function()
        for _, refill in ipairs(xDTaraZ.UI.SkinRefill) do refill() end
    end)
    main:AddButton({ Text = T("Reset all skins", "คืนสกินเดิมทั้งหมด"), Style = "Warning", Func = function()
        xDTaraZ.Skin.ClearAll()
        for _, kind in ipairs(xDTaraZ.Skin.Types) do
            local picker = Library.Options["Skin" .. kind .. "Pick"]
            if picker then picker:SetValue(nil) end
        end
    end })

    local leftRows, rightRows = xDTaraZ.Config.SkinMainRows, 0
    for _, kind in ipairs(xDTaraZ.Skin.Types) do
        local left = leftRows < rightRows
        Util.Try("skins " .. kind, xDTaraZ.UI.BuildSkinGroup, tab, kind, left)
        if left then
            leftRows += xDTaraZ.Config.SkinGroupRows
        else
            rightRows += xDTaraZ.Config.SkinGroupRows
        end
    end
end

function xDTaraZ.UI.BuildVisuals(window)
    window:AddTabSection(T("Visuals", "การมองเห็น"))
    Util.Try("visuals tab", function()
        window:AddVisualsTab({ Provider = xDTaraZ.Esp.Targets, Preview = true })
    end)
    Util.Try("skins tab", xDTaraZ.UI.BuildSkins, window)
end

---@return table  rarities to sell: every known rarity not kept
function xDTaraZ.UI.SellSet(keep)
    local kept, sell = Util.SetFromList(keep), {}
    for _, rarity in ipairs(xDTaraZ.Sell.Rarities()) do
        if not kept[rarity] then sell[rarity] = true end
    end
    return sell
end

---@param sold table  rarity list an older save picked to sell
---@return string[]   the same choice as rarities to keep
function xDTaraZ.UI.KeepFromSold(sold)
    local selling, keep = Util.SetFromList(sold), {}
    for _, rarity in ipairs(xDTaraZ.Sell.Rarities()) do
        if not selling[rarity] then table.insert(keep, rarity) end
    end
    return keep
end

---@param keep table  KeepRarities dropdown; old saves that only have SellRarities load into it
function xDTaraZ.UI.AdoptOldSellSave(group, keep)
    local old = group:AddDropdown("SellRarities", {
        Text = T("Sell rarities", "rarity ที่จะขาย"),
        Values = xDTaraZ.Sell.Rarities(),
        Multi = true,
        Default = {},
        AllowNull = true,
    })
    old:SetVisible(false)
    old.Serialize = false
    old.Deserialize = function(_, saved)
        keep:SetValue(xDTaraZ.UI.KeepFromSold(saved))
    end
end

function xDTaraZ.UI.BuildEconomy(window)
    window:AddTabSection(T("Economy", "เศรษฐกิจ"))
    local tab = window:AddTab(T("Economy", "เศรษฐกิจ"), "coin", T("Cases, selling, quests", "เปิดกล่อง ขาย เควสต์"))

    local cases = tab:AddLeftGroupbox(T("Cases", "กล่องสุ่ม"), "qblock")
    cases:AddToggle("AutoOpenCases", { Text = T("Auto open owned cases", "เปิดกล่องที่มีอัตโนมัติ"), Callback = xDTaraZ.UI.StartStop(xDTaraZ.Shop) })
    cases:AddSlider("OpenCount", { Text = T("Open per case", "เปิดต่อกล่อง"), Min = 1, Max = 10, Default = 1 })
    cases:AddButton({ Text = T("Open All Now", "เปิดทั้งหมดตอนนี้"), Style = "Primary", Func = xDTaraZ.UI.Detach(function()
        xDTaraZ.UI.Notice(T("Cases", "กล่องสุ่ม"), xDTaraZ.Shop.OpenAllNow(), "Coin")
    end) })

    local sell = tab:AddRightGroupbox(T("Sell", "ขาย"), "shop")
    local keep = sell:AddDropdown("KeepRarities", {
        Text = T("Never sell", "ไม่ขาย"),
        Description = T("Selected rarities are always kept", "rarity ที่เลือกจะเก็บไว้เสมอ"),
        Values = xDTaraZ.Sell.Rarities(),
        Multi = true,
        Default = {},
        AllowNull = true,
    })
    xDTaraZ.UI.Bind(keep, "SellRarities", xDTaraZ.UI.SellSet)
    xDTaraZ.UI.AdoptOldSellSave(sell, keep)
    sell:AddToggle("AutoSell", { Text = T("Auto sell", "ขายอัตโนมัติ"), Risky = true, Callback = xDTaraZ.UI.StartStop(xDTaraZ.Sell) })
    sell:AddSlider("MaxSellPrice", { Text = T("Max price to sell", "ราคาสูงสุดที่ขาย"), Description = T("Keeps anything worth more (0 = no limit)", "ของแพงกว่านี้จะเก็บไว้ (0 = ไม่จำกัด)"), Min = 0, Max = 100000, Default = 500 })
    sell:AddSlider("KeepPerRarity", { Text = T("Keep per rarity", "เก็บต่อ rarity"), Min = 0, Max = 20, Default = 0 })
    sell:AddButton({ Text = T("Sell Now", "ขายตอนนี้"), Style = "Warning", Func = xDTaraZ.UI.Detach(function()
        xDTaraZ.UI.Notice(T("Sell", "ขาย"), xDTaraZ.Sell.SellNow(), "Coin")
    end) })
    sell:AddButton({ Text = T("Refresh rarities", "รีเฟรช rarity"), Func = xDTaraZ.UI.Detach(function()
        keep:SetValues(xDTaraZ.Sell.Rarities())
        xDTaraZ.Options.SellRarities = xDTaraZ.UI.SellSet(keep.Value)
    end) })

    local quest = tab:AddLeftGroupbox(T("Quests", "เควสต์"), "key")
    quest:AddToggle("AutoClaimQuest", { Text = T("Auto claim quests", "รับรางวัลเควสต์อัตโนมัติ"), Callback = xDTaraZ.UI.StartStop(xDTaraZ.Collect) })
    quest:AddButton({ Text = T("Claim Now", "รับตอนนี้"), Style = "Success", Func = xDTaraZ.UI.Detach(function()
        xDTaraZ.UI.Notice(T("Quests", "เควสต์"), xDTaraZ.Collect.ClaimNow(), "Success")
    end) })
end

---@param key string  entry in UI.Labels, only redrawn when the text changes
function xDTaraZ.UI.Show(key, text)
    local label = xDTaraZ.UI.Labels[key]
    text = tostring(text)
    if not label or xDTaraZ.UI.Shown[key] == text then return end
    xDTaraZ.UI.Shown[key] = text
    label:SetContent(text)
end

function xDTaraZ.UI.RefreshStatus()
    local show = xDTaraZ.UI.Show
    show("Skin", xDTaraZ.Skin.GetStatus())
    show("Esp", xDTaraZ.Esp.GetStatus())
    show("Combat", xDTaraZ.Combat.GetStatus())
    show("Economy", string.format("%s | %s | %s", xDTaraZ.Shop.GetStatus(), xDTaraZ.Sell.GetStatus(), xDTaraZ.Collect.GetStatus()))

    show("Targets", xDTaraZ.Esp.Count)
    show("Cases", xDTaraZ.UI.Stats.Cases)
    show("Quests", xDTaraZ.UI.Stats.Quests)
end

function xDTaraZ.UI.ShowHalted()
    local queue = xDTaraZ.State.Halted
    if #queue == 0 then return end
    local stopped = table.clone(queue)
    table.clear(queue)

    for _, halt in ipairs(stopped) do
        local name, reason, toggles = halt[1], halt[2], halt[3]
        for _, key in ipairs(toggles) do
            local toggle = Library.Options[key]
            if toggle and toggle.Value == true then
                Util.Try("halt " .. key, toggle.SetValue, toggle, false)
            end
        end
        Library:Notify("Nova Hub", name .. " stopped: " .. reason, 6, "Error")
    end
end

function xDTaraZ.UI.ShowNotices()
    local queue = xDTaraZ.State.Notices
    if #queue == 0 then return end
    local pending = table.clone(queue)
    table.clear(queue)
    for _, notice in ipairs(pending) do
        Library:Notify(notice[1], notice[2], 4, notice[3])
    end
end

function xDTaraZ.UI.Pump()
    Util.Try("status", xDTaraZ.UI.RefreshStatus)
    Util.Try("halts", xDTaraZ.UI.ShowHalted)
    Util.Try("notices", xDTaraZ.UI.ShowNotices)
end

function xDTaraZ.UI.BlockMissing()
    local unsupported = T("Not available on this executor", "ใช้กับ executor นี้ไม่ได้")
    local outdated = T("Changed by a game update, wait for a script update", "เกมอัปเดตแล้ว รอสคริปต์อัปเดต")
    for module, features in pairs(xDTaraZ.Config.ModuleFeatures) do
        local missing = GameLib.Missing[module]
        if not missing then continue end
        for _, idx in ipairs(features) do
            Library.Compat.Block(idx, missing == "Absent" and outdated or unsupported)
        end
    end

    if not xDTaraZ.Movement.FindDash() then
        warn("[SniperArena] module CombatHelper.Dash not found, Infinite dash is blocked")
        Library.Compat.Block("InfiniteDash", outdated)
    end
end

function xDTaraZ.UI.Build()
    local window = Library.Window
    Util.Try("main tab", xDTaraZ.UI.BuildMain, window)
    Util.Try("combat tab", xDTaraZ.UI.BuildCombat, window)
    Util.Try("player tab", xDTaraZ.UI.BuildPlayer, window)
    Util.Try("visuals tabs", xDTaraZ.UI.BuildVisuals, window)
    Util.Try("economy tab", xDTaraZ.UI.BuildEconomy, window)
    Util.Try("settings tab", function()
        window:AddTabSection(T("Other", "อื่นๆ"))
        window:AddSettingsTab()
    end)

    for _, key in ipairs({ "AimFov", "AimBone", "AimPriority", "AimMaxDistance",
        "Aimbot", "AimSmooth", "AimPrediction", "ShowFov", "AimWallCheck", "AimTeamCheck",
        "SilentAim", "Ragebot", "InstantScope", "HitChance", "HeadChance", "TriggerBot", "NoRecoil", "NoSpread",
        "FastRespawn", "InfiniteDash", "SkinChanger", "OpenCount", "MaxSellPrice", "KeepPerRarity" }) do
        local widget = Library.Options[key]
        if widget then Util.Try("bind " .. key, xDTaraZ.UI.Bind, widget, key) end
    end
    Util.Try("missing modules", xDTaraZ.UI.BlockMissing)
    xDTaraZ:Connect(RunService.RenderStepped, xDTaraZ.Combat.DrawCircle)

    xDTaraZ.Scheduler.Every("Live stats", xDTaraZ.Config.EconomyInterval, xDTaraZ.UI.SampleStats)
    Library:Every(xDTaraZ.Config.StatusInterval, xDTaraZ.UI.Pump)
end

---@return boolean  false when the menu could not be opened
local function BuildInterface()
    Library = Util.LoadLibrary(xDTaraZ.Config.UiSource)
    if not Library then return false end
    xDTaraZ.Library = Library
    pcall(xDTaraZ.Banner.Step, "UI library")
    T = function(en, th) return Library:T(en, th) end
    local opened, err = pcall(Library.CreateWindow, Library, {
        Title = "Nova Hub",
        SubTitle = "Sniper Arena by xDTaraZ",
        MenuKey = Enum.KeyCode.LeftControl,
        ConfigFolder = xDTaraZ.Config.SaveFolder,
        Language = "Auto",
        Theme = "Nova",
        Intro = true,
        OnUnlocked = function()
            xDTaraZ.UI.Build()
            pcall(xDTaraZ.Banner.Step, "Interface")
            task.defer(Util.Try, "boot", xDTaraZ.Boot)
            task.defer(Util.Try, "autoload config", function() Library:LoadAutoloadConfig() end)
        end,
    })
    if not opened then
        Util.Alert("The menu failed to load on this executor: " .. tostring(err):match("^[^\n]*"), err)
        return false
    end
    Library:OnUnload(function()
        xDTaraZ:Unload()
    end)
    return true
end

function xDTaraZ.Boot()
    xDTaraZ:Connect(LocalPlayer.CharacterAdded, function(character)
        xDTaraZ.Player:Bind(character)
    end)

    Util.Try("movement", xDTaraZ.Movement.Start)

    xDTaraZ.Scheduler.Every("Combat", 0.03, xDTaraZ.Combat.Step, xDTaraZ.Config.CombatToggles, xDTaraZ.Combat.Rest)
    xDTaraZ.Scheduler.Every("Anti AFK", 5, xDTaraZ.Player.AntiAfk.Step, { "AntiAfk" })
    xDTaraZ.Scheduler.Every("Fast Respawn", 0.1, xDTaraZ.Player.Respawn.Step, { "FastRespawn" })
    xDTaraZ.Scheduler.Every("Skin Changer", 0.5, xDTaraZ.Skin.Step, { "SkinChanger" }, xDTaraZ.Skin.Step)
    xDTaraZ.Scheduler.Every("Auto Open Cases", xDTaraZ.Config.EconomyInterval, xDTaraZ.Shop.Step, { "AutoOpenCases" })
    xDTaraZ.Scheduler.Every("Auto Sell", xDTaraZ.Config.EconomyInterval, xDTaraZ.Sell.Step, { "AutoSell" })
    xDTaraZ.Scheduler.Every("Auto Claim Quests", xDTaraZ.Config.EconomyInterval, xDTaraZ.Collect.Step, { "AutoClaimQuest" })
    Util.Try("scheduler", xDTaraZ.Scheduler.Boot)
    pcall(xDTaraZ.Banner.Step, "Combat + economy online")
    pcall(xDTaraZ.Banner.Ready)
end

function xDTaraZ:Unload()
    self.State.Alive = false
    xDTaraZ.Combat.Unload()
    xDTaraZ.Skin.Restore()
    for _, connection in ipairs(self.State.Connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(self.State.Connections)

    local overlay = self.State.Overlay
    self.State.Overlay = nil
    if overlay then overlay:Destroy() end
    if environment.SniperArenaUnload == xDTaraZ.UnloadHook then environment.SniperArenaUnload = nil end
end

function xDTaraZ.UnloadHook()
    if xDTaraZ.Library and not xDTaraZ.Library.Unloaded then
        xDTaraZ.Library:Unload()
    else
        xDTaraZ:Unload()
    end
end

environment.SniperArenaUnload = xDTaraZ.UnloadHook

if LocalPlayer.Character then
    xDTaraZ.Player:Bind(LocalPlayer.Character)
end

pcall(xDTaraZ.Banner.Step, "Character bound")
BuildInterface()]==]

NOVA_HUB_MODULES[6739698191] = [==[if not game:IsLoaded() then
    game.Loaded:Wait()
end

if game.GameId ~= 6739698191 then
    game:GetService("Players").LocalPlayer:Kick("Nova Hub: this script is for Violence District only")
    return
end

if not LPH_OBFUSCATED then
    local function Passthrough(fn) return fn end
    LPH_JIT, LPH_JIT_MAX, LPH_NO_VIRTUALIZE = Passthrough, Passthrough, Passthrough
end

local environment = getgenv and getgenv() or _G
if type(environment.ViolenceDistrictUnload) == "function" then
    pcall(environment.ViolenceDistrictUnload)
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Teams = game:GetService("Teams")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer
local vector3New, cframeNew, cframeLookAt = Vector3.new, CFrame.new, CFrame.lookAt
local vectorZero = Vector3.zero
local osClock, mathHuge = os.clock, math.huge

local NovaBanner = {
    Print = print,
    Started = os.clock(),
    Last = os.clock(),
    Done = 0,
    Total = 4,
}

function NovaBanner.Show()
    local ok, executor = pcall(identifyexecutor)
    if not ok or type(executor) ~= "string" then executor = "Unknown" end
    local rule = string.rep("=", 54)
    NovaBanner.Print(table.concat({
        "",
        [[
                                                                     @%@
                                                                    @*-#@
                                          @@@@@@@@@@@@@          @@#+.:-*%@@      @@
                                   @@@@@%##***********##%@@@@@   @*--:-==+*@@@@#*+==+*%@@
                              @@@@#+=+==---==++++++++++++**+++#@@@@@%==+@@@@#:.......:::=%@@
                          @@%#+---::-=++++++++++************+***++#%@%+@@@#:..-+*****+-:::+%@
                      @@@#=-::.:-==++++++++++*************************#@@+::=*-:.:+-::-+:.:=#@
                    @@%-:...:-===+++++**#################****************%%*+::::+*++::-+..:=#@
                 @@%*-:...:--==++*########**+==--===+**#######************+#%+::-*==-:::=-::=+@@
               @@%+=-::---===+*###%#+-:...................:=+#####***********#@+++==----==:-+*@@
             @@%++=-======+*###%+:............................::+####**********#@*+=----=---**@@
            @%=++=++++++*####=:...................................:+###**********%@==--==--+**@@
          @@*+++++++++*###*:........................................:-*##**********%*==+--=**@@@
         @%+++++++++*##%+:............................................::*##*********%%+--=##%@+%@
       @@#+++++++++###*:.....-+==+*#-......................:**+**#+:....:=###********%%+*##%@*:+@@
      @@*++++++++*###:......-+:.:-=*#*-..................:+*--+**#%*:.....:+##********#@#%%+:.:--+#@
     @@+++++++++*##+:......-*::-=++++*##:...............=#=-++****#%*:.....:-##********#@@@%+=-++#@@
    @@+=-=+++++*##+.......:*-:==++++++*##+............-*+-=+*******#%+:.....:-##********#@  @#=#@@
    @*=:.=++++*##-.......:*=:=++++++++*+*##=........:**==+**********##=:.....::*#********%@  @#@
   @#+-.-++*+*##=........*+-++++++*********##-....:+*==+*************#%-:.....:-**********%@
  @@++-=++***##+........*+-++++++***********#%*::=#+-+****************#%-:.....:=**********@@
 @@*++=++***###........+*-+++++***************###+-=+*****************###-:.....:+*********%@
 @%++=+*****#%:.......=*-++++*******************==+********************#%*-:....:-#********#@@
@@**+++****##+.......=*=+++*********************************************#%+::....:+*********@@
@%**++*****##-......=#=++**********#%#********************%%*************#%+:....:-#********%@
@%**++*****#*:.....-*=++**********#%%%#*****************#%%%**************#%=:....-********##@@
@#**++*****#*:....:*++************%%%%%%#*************#%%%%%#**************##-:...-+*******#*@@
@#**+******#+:...:#++************#%%%@@%%##*********#%%%%%@%#**************#%#-:..:+*+*****#*@@
@#**+******#+:..:#+=************#%%%%%*%%%##*******%%%%%%#%%##**************#%#::.-+*+*****#*@@
@#*********#+:.:+*=*************%%%%%+==*%%###***#%%%%%#++*%##***************#%*::-+*+*****#*@@
@%*#*******#*:.+*=*************%%%%%*=----*%###%%%%%%#+====*###**************##%+--*++****###@@
@%*#********#-:####***********#%%%%#=-::.::=###%%%%#+==--:::####************#%%%#==*+*****###@@
@@##********#+:#%%%%#********#%%%%%=--:....::=%%%%+==--::..:-%###********#%%%%%%#=#++*****##%@
@@###********#-=#%%%%%%##****%%%%%*=-:.......::-==---::.....:+###*****##%%%%%%%#++#++****###@@
 @%###*******##::=+%%%%%%%##%%%%%#=-:...........:::::........:####*#%%%%%%%%%*+=+*+=*****##%@
 @@###********#+:.:-=*%%%%%%%%%%%+--:.........................=###%%%%%%%%*+====*=.=****###@@
  @@###********#+:..::-=*%%%%%%%*=-:..:::-------------::::...::*#%%%%%%*+==---=*+-=+***###%@
   @%###*******#%#*+-..::-=#%@@%#**++==----------------===+++**#%@@@#+===---+*#*++****####@@
    @%###**#%#=::-=+##*##+-:...:::-=+**---*###*=--++++=--=++++=--:::-=+#%**#-:..:=#%##%##@@
    @@%#%#+:...:-=++=:..::=*####+#=:..=@#%:....%@*....*%%#...:--=*##+------=+=:::::-=#%%@@
     @@%*=--::::-*::::::-%=...:%@#:...:@@#.....%@+....=@@=.........:*#=-----=+=:::-==++%@@
  @@%+--+==--:::-#=-::::-%+....+%%-....%@#....:@@+....+@@:...:%%....-@*---==+*+:::-=+++*=+#@@
 @%-:-==*+==-:::-+*--:::-*#:...........*@#....:@@+....+@%..........-%%+---==+*=::-=+++#*=-:-*@@
 @@#+===+*+==-::-=*=--::-=%-......:....+@%:....:-....:#@*....=+:...-%#=--==+**-:--=++#*+=-=*%@
   @@#*=++#+=-:::-+*------#+....+@%....-@@#:.......::*@@+....+#=.:::=%+-===+#+-:-=++***++*%@@
     @@#+++*==-::-=*=-----+%:...-@@-::-=@%%@#+=--==*%@%%=:::::::::::#%+===+**----=++#**#%@@
     @@*-=+*+=-::-=*+=----=%#+*#%@%@@@@@#+-=*%%@@@%#*==*@@%%%##*+*#@@*====+#+-:-=++***++%@
    @@*--=+++===++*#*=------#%%#+=-----===============----==+*#%%%#+=-===+*#*+++=++**+==*@@
    @%=:-==+***%%@@@#=-=====++*##%%%@@@@@@@@@@%%@@@@@@@@@%%%##**++=======+*@@@@%#*+#+=--=#@
    @*:---==+*###%@@@#*#%%@%%%%%%######*****++++++++***######%%%%%%%%%%#*#%@@@####**+=---+@@
   @@+--=**#%@@@@@  @@@%%%%%%%#*******************************####%%%%%%@@@  @@@@@%#**=--+%@
    @@%%@@@@@          @@@@%%%%%%###**********************####%%%%%%%@@@          @@@@@%%%@@
      @@                  @@@@@%%%%%%%%%###############%%%%%%%%%@@@@@                  @@@
                               @@@@@@%%%%%%%%%%%%%%%%%%%%%%@@@@@
                                    @@@@@@@@@@@@@@@@@@@@@@@
]],
        [[
  __  __    _    ____  ___ ___    _   _ _   _ ____
 |  \/  |  / \  |  _ \|_ _/ _ \  | | | | | | | __ )
 | |\/| | / _ \ | |_) || | | | | | |_| | | | |  _ \
 | |  | |/ ___ \|  _ < | | |_| | |  _  | |_| | |_) |
 |_|  |_/_/   \_\_| \_\___\___/  |_| |_|\___/|____/
]],
        rule,
        "   VIOLENCE DISTRICT  //  by xDTaraZ  //  discord.gg/FHVfmeSceA",
        "   executor: " .. executor .. "   //   player: " .. game:GetService("Players").LocalPlayer.Name,
        rule,
    }, "\n"))
end

---@param label string  what just finished loading
function NovaBanner.Step(label)
    local now = os.clock()
    NovaBanner.Done = math.min(NovaBanner.Done + 1, NovaBanner.Total)
    local filled = math.floor(NovaBanner.Done / NovaBanner.Total * 20 + 0.5)
    NovaBanner.Print(string.format("[Nova Hub] [%s] %3d%%  %-24s +%dms",
        string.rep("#", filled) .. string.rep(".", 20 - filled),
        math.floor(NovaBanner.Done / NovaBanner.Total * 100), label, math.floor((now - NovaBanner.Last) * 1000)))
    NovaBanner.Last = now
end

function NovaBanner.Ready()
    local rule = string.rep("=", 54)
    NovaBanner.Print(table.concat({
        rule,
        string.format("   >> READY in %dms", math.floor((os.clock() - NovaBanner.Started) * 1000)),
        rule,
    }, "\n"))
end

do
    local ok, renv = pcall(getrenv)
    if ok and type(renv) == "table" and type(renv.print) == "function" then
        NovaBanner.Print = renv.print
    end
end

pcall(NovaBanner.Show)
pcall(NovaBanner.Step, "Core")

local xDTaraZ = setmetatable({}, {
    __newindex = function(self, key, value)
        rawset(self, key, type(value) == "function" and LPH_JIT(value) or value)
    end,
})

xDTaraZ.Config = {
    UiSource = "NovaHub://embedded-ui",
    Discord = "https://discord.gg/FHVfmeSceA",
    UpdateLog = {
        { "2026-10-03", "Classic Nova Hub UI is back\nBetter executor support\nBug fixes & better UI" },
    },
    SaveFolder = "Violence District",
    Intro = true,
    LoadTimeout = 10,
    AlertTries = 20,
    AlertRetry = 0.5,
    JobFailLimit = 5,
    JobFailWindow = 10,
    StatusInterval = 1,
    RepairTick = 0.25,
    GenDone = 100,
    SpareGens = 1,
    AttackReach = 2,
    LungeDelay = 0.21,
    AuraCooldown = 1.1,
    CarryDelay = 0.8,
    Settle = 0.55,
    FinishFirst = 85,
    ArriveRadius = 4,
    DriftLimit = 12,
    DangerKeep = 2,
    DangerPick = 2.5,
    DistanceWeight = 0.05,
    HealMax = 15,
    HealMinUseful = 3,
    HelpBan = 8,
    UnhookReach = 10,
    GuardTick = 0.05,
    FarmDodge = 24,
    SwingTail = 0.4,
    LegitReach = 9,
    ServerReach = 4.2,
    ParryRange = 14,
    ParryPanic = 6,
    ParryClosing = 12,
    ParryRetry = 1,
    ParryFast = 0.25,
    ParryScan = 5,
    LegitAngle = 0.5,
    HookRest = 1,
    UnhookHold = 2.5,
    StallTime = 8,
    StallBan = 30,
    HookTween = 0.2,
    GenBreakTime = 2,
    KickRegress = 25,
    SelfUnhookRetry = 1,
    SelfUnhookMax = 12,
    DodgeCooldown = 1.5,
    RolePending = 8,
    JumpVelocity = 50,
    AlertRadius = 60,
    ShopDelay = 0.6,
    FirstLevelCost = 750,
    EscapeRetry = 6,
    ShopInterval = 10,
    SurvivorSpeed = 21,
    KillerSpeed = 18.7,
    ObjectEspRefresh = 1,
    ModelRescan = 10,
}

xDTaraZ.State = {
    Alive = true,
    Connections = {},
}

xDTaraZ.Options = {
    AntiAfk = false,
    RoleMode = "Any",
    Speed = false,
    SpeedValue = 24,
    Noclip = false,
    NoSlow = false,
    NoFall = false,
    FreeTurn = false,
    AntiShake = false,
    AntiBlind = false,
    SmartHitbox = false,
    SlashMode = "Rage",
    InfiniteJump = false,
    Fullbright = false,
    NoFog = false,

    AutoRepair = false,
    PerfectSkillCheck = false,
    InstantEscape = false,
    EscapeDelay = 0,
    AutoHeal = false,
    AutoUnhook = false,
    AutoDodge = false,
    DodgeRadius = 20,
    AutoSelfUnhook = false,
    AutoParry = false,
    NoParryCooldown = false,
    KillerAlert = false,

    AutoBuyPerks = false,
    AutoLevelPerks = false,
    KeepScrews = 0,

    KillAura = false,
    AuraRange = 500,
    AutoHook = false,
    AutoBreakGens = false,
    AntiStun = false,

    EspGenerators = false,
    EspHooks = false,
    EspGates = false,
    EspPallets = false,
    EspWindows = false,
}

xDTaraZ.Util = {}
local Util = xDTaraZ.Util

---@return function?  first argument that is callable
local function Resolve(...)
    for index = 1, select("#", ...) do
        local candidate = select(index, ...)
        if type(candidate) == "function" then return candidate end
    end
    return nil
end

Util.Request = Resolve(request, http_request, type(syn) == "table" and syn.request, type(http) == "table" and http.request)
Util.SetClipboard = Resolve(setclipboard, toclipboard)
Util.GetHui = Resolve(gethui, get_hidden_gui)
Util.GetConnections = Resolve(getconnections, get_signal_cons)
Util.FireSignal = Resolve(firesignal)
Util.FireTouch = Resolve(firetouchinterest)
Util.GetGc = Resolve(getgc, get_gc_objects)
Util.NameCallMethod = Resolve(getnamecallmethod)
Util.HookMetamethod = Resolve(hookmetamethod)
Util.Closure = Resolve(newcclosure) or function(fn) return fn end

Util.RawCaps = {
    Connections = function() return Util.GetConnections ~= nil end,
    Signals = function() return Util.FireSignal ~= nil end,
    Gc = function() return Util.GetGc ~= nil end,
    Namecall = function() return Util.HookMetamethod ~= nil and Util.NameCallMethod ~= nil end,
}

---@param cap string|string[]  Library.Compat cap name(s), false until the menu has loaded
function Util.Can(cap)
    local library = xDTaraZ.Library
    if library == nil then return false end
    if library.Compat then return (library.Compat.Has(cap)) end
    for _, name in ipairs(type(cap) == "table" and cap or { cap }) do
        local probe = Util.RawCaps[name]
        if not (probe and probe()) then return false end
    end
    return true
end

---@return function?  original, nil when the executor refused the hook
---@return function?  restore
function Util.HookMeta(object, method, handler)
    local compat = xDTaraZ.Library and xDTaraZ.Library.Compat
    if compat then return compat.HookMeta(object, method, handler) end
    if not Util.HookMetamethod then return nil end

    local ok, original = pcall(Util.HookMetamethod, object, method, Util.Closure(handler))
    if not ok or type(original) ~= "function" then return nil end
    return original, function()
        Util.HookMetamethod(object, method, original)
    end
end

---@return string?  response body, nil when every transport failed
function Util.HttpGet(url)
    if url == "NovaHub://embedded-ui" then return NOVA_HUB_UI_SOURCE end
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if ok and type(body) == "string" then return body end
    if not Util.Request then return nil end
    local sent, response = pcall(Util.Request, { Url = url, Method = "GET" })
    if sent and type(response) == "table" and tonumber(response.StatusCode) == 200 and type(response.Body) == "string" then
        return response.Body
    end
    return nil
end

---@param text string  shown as a Roblox notification, works before the menu exists
function Util.Alert(text)
    warn("[ViolenceDistrict] " .. text)
    task.spawn(function()
        local starterGui = game:GetService("StarterGui")
        for _ = 1, xDTaraZ.Config.AlertTries do
            if pcall(starterGui.SetCore, starterGui, "SendNotification", { Title = "Nova Hub", Text = text, Duration = 10 }) then return end
            task.wait(xDTaraZ.Config.AlertRetry)
        end
    end)
end

---@return table?  UI library, nil after telling the player why
function Util.LoadLibrary()
    local source = Util.HttpGet(xDTaraZ.Config.UiSource)
    if not source or not source:sub(-64):find("return Library%s*$") then
        Util.Alert("Could not download the menu. Check your connection and run it again.")
        return nil
    end
    local chunk, err = loadstring(source)
    if not chunk then
        Util.Alert("The menu failed to load on this executor: " .. tostring(err))
        return nil
    end
    local ok, library = pcall(chunk)
    if not ok or type(library) ~= "table" then
        Util.Alert("The menu failed to load on this executor: " .. tostring(library))
        return nil
    end
    return library
end

function Util.Copy(text)
    if not Util.SetClipboard then return false end
    Util.SetClipboard(text)
    return true
end

---@return boolean, any  pcall result, warns with the label when it fails
function Util.Try(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then warn("[ViolenceDistrict] " .. label .. ": " .. tostring(err)) end
    return ok, err
end

---@param instance Instance  parented to gethui, then CoreGui, then PlayerGui
function Util.Mount(instance)
    local ok, hui = pcall(Util.GetHui or error)
    if ok and typeof(hui) == "Instance" and pcall(function() instance.Parent = hui end) then return end
    if pcall(function() instance.Parent = game:GetService("CoreGui") end) then return end
    instance.Parent = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", xDTaraZ.Config.LoadTimeout)
end

function xDTaraZ:Connect(signal, handler)
    local connection = signal:Connect(handler)
    table.insert(self.State.Connections, connection)
    return connection
end

xDTaraZ.GameLib = {}
local GameLib = xDTaraZ.GameLib

GameLib.Folder = ReplicatedStorage:WaitForChild("Remotes", xDTaraZ.Config.LoadTimeout)

---@return Instance?  remote at the path under Remotes, else the only remote with that name anywhere under it
function GameLib.FindRemote(...)
    local root = GameLib.Folder
    if not root then return nil end
    local node = root
    for _, step in ipairs({ ... }) do
        node = node and node:FindFirstChild(step)
    end
    if node then return node end

    local name, found = select(select("#", ...), ...), nil
    for _, desc in ipairs(root:GetDescendants()) do
        if desc.Name ~= name or not (desc:IsA("BaseRemoteEvent") or desc:IsA("RemoteFunction")) then continue end
        if found then return nil end
        found = desc
    end
    return found
end

GameLib.RemotePaths = {
    Repair = { "Generator", "RepairEvent" },
    GenCheck = { "Generator", "SkillCheckEvent" },
    GenResult = { "Generator", "SkillCheckResultEvent" },
    Heal = { "Healing", "HealEvent" },
    HealCheck = { "Healing", "SkillCheckEvent" },
    HealResult = { "Healing", "SkillCheckResultEvent" },
    Unhook = { "Carry", "UnHookEvent" },
    SelfUnhook = { "Carry", "SelfUnHookEvent" },
    Fall = { "Mechanics", "Fall" },
    Carry = { "Carry", "CarrySurvivorEvent" },
    Hook = { "Carry", "HookEvent" },
    HookCommit = { "Carry", "HookCommit" },
    BreakGen = { "Generator", "BreakGenEvent" },
    BreakGenCommit = { "Generator", "BreakGenCommit" },
    Lunge = { "Attacks", "Lunge" },
    Stun = { "Pallet", "Jason", "Stun" },
    StunOver = { "Pallet", "Jason", "Stunover" },
    Attack = { "Attacks", "BasicAttack" },
    BuyPerk = { "Shop", "PurchasePerk" },
    LevelPerk = { "Shop", "LevelUpPerk" },
    PerkInfo = { "Shop", "GetPerkInfo" },
}

GameLib.Remote = {}
for key, path in pairs(GameLib.RemotePaths) do
    GameLib.Remote[key] = GameLib.FindRemote(table.unpack(path))
end

GameLib.Needs = {
    AutoRepair = { "Repair" },
    PerfectSkillCheck = { "GenCheck", "HealCheck", "GenResult", "HealResult" },
    AutoHeal = { "Heal" },
    AutoUnhook = { "Unhook" },
    AutoSelfUnhook = { "SelfUnhook" },
    NoFall = { "Fall" },
    KillAura = { "Lunge", "Attack" },
    AutoHook = { "Carry", "Hook", "HookCommit" },
    AutoBreakGens = { "BreakGen", "BreakGenCommit" },
    AntiStun = { "Stun", "StunOver" },
    AutoBuyPerks = { "BuyPerk", "PerkInfo" },
    AutoLevelPerks = { "LevelPerk", "PerkInfo" },
}

---@return string?  "Folder/Name" of the first remote the toggle needs that is gone
function GameLib.Missing(idx)
    for _, key in ipairs(GameLib.Needs[idx] or {}) do
        if not GameLib.Remote[key] then return table.concat(GameLib.RemotePaths[key], "/") end
    end
    return nil
end

xDTaraZ.Player = { Client = LocalPlayer }

function xDTaraZ.Player:Bind(character)
    self.Character = character
    self.Humanoid = character:WaitForChild("Humanoid", xDTaraZ.Config.LoadTimeout)
    self.Root = character:WaitForChild("HumanoidRootPart", xDTaraZ.Config.LoadTimeout)
end

function xDTaraZ.Player:IsAlive()
    return self.Humanoid ~= nil and self.Humanoid.Health > 0 and self.Root ~= nil and self.Root.Parent ~= nil
end

---@return string?  "Survivors" / "Killer" / "Spectator"
function xDTaraZ.Player.Role(player)
    local team = (player or LocalPlayer).Team
    return team and team.Name or nil
end

---@return boolean  downed, hooked or carried
function xDTaraZ.Player.Disabled(character)
    if not character then return true end
    return character:GetAttribute("Knocked") == true
        or character:GetAttribute("IsHooked") == true
        or character:GetAttribute("IsCarried") == true
end

function xDTaraZ.Player.Killer()
    local team = Teams:FindFirstChild("Killer")
    local killer = team and team:GetPlayers()[1]
    return killer and killer.Character
end

function xDTaraZ.Player.Survivors()
    local team = Teams:FindFirstChild("Survivors")
    local list = {}
    if not team then return list end
    for _, player in ipairs(team:GetPlayers()) do
        local char = player.Character
        if player ~= LocalPlayer and char and char:FindFirstChild("HumanoidRootPart") then
            list[#list + 1] = char
        end
    end
    return list
end

function xDTaraZ.Player.Teleport(cframe)
    local hrp = xDTaraZ.Player.Root
    if not hrp then return end
    hrp.CFrame = cframe
    hrp.AssemblyLinearVelocity = vectorZero
end

xDTaraZ.Map = {}

function xDTaraZ.Map.Root()
    return Workspace:FindFirstChild("Map")
end

function xDTaraZ.Map.Tagged(tag)
    local map = xDTaraZ.Map.Root()
    local list = {}
    if not map then return list end
    for _, part in ipairs(CollectionService:GetTagged(tag)) do
        if part:IsA("BasePart") and part:IsDescendantOf(map) then
            list[#list + 1] = part
        end
    end
    return list
end

xDTaraZ.Map.Cache = { Map = nil, Models = {}, Scanned = {}, Total = 0 }

---@return Model[]  every model with this name in the current map, cached per round
function xDTaraZ.Map.Models(name)
    local map = xDTaraZ.Map.Root()
    local cache = xDTaraZ.Map.Cache
    if not map then return {} end
    if cache.Map ~= map then
        cache.Map, cache.Models, cache.Scanned = map, {}, {}
    end
    local list = cache.Models[name]
    local fresh = osClock() - (cache.Scanned[name] or 0) < xDTaraZ.Config.ModelRescan
    if list and fresh and (not list[1] or list[1]:IsDescendantOf(map)) then return list end
    cache.Scanned[name] = osClock()
    list = {}
    for _, inst in ipairs(map:GetDescendants()) do
        if inst.Name == name and inst:IsA("Model") then list[#list + 1] = inst end
    end
    cache.Models[name] = list
    return list
end

---@return Model[]  every generator on the map, finished ones included
function xDTaraZ.Map.Generators()
    return xDTaraZ.Map.Models("Generator")
end

---@return BasePart[]  GeneratorPoint parts of one generator, cached per round
function xDTaraZ.Map.PointsOf(gen)
    local cache = xDTaraZ.Map.Cache
    cache.Points = cache.Points or setmetatable({}, { __mode = "k" })
    local list = cache.Points[gen]
    if list and list[1] and list[1].Parent then return list end
    list = {}
    for _, point in ipairs(xDTaraZ.Map.Tagged("GeneratorPoint")) do
        if point:IsDescendantOf(gen) then list[#list + 1] = point end
    end
    cache.Points[gen] = list
    return list
end

function xDTaraZ.Map.GenProgress(model)
    return tonumber(model:GetAttribute("RepairProgress")) or 0
end

---@return number  gens still needed before the exits power (one gen is spare)
function xDTaraZ.Map.GensLeft()
    local gens = xDTaraZ.Map.Generators()
    local cache = xDTaraZ.Map.Cache
    local map = xDTaraZ.Map.Root()
    if cache.TotalMap ~= map then cache.TotalMap, cache.Total = map, 0 end
    cache.Total = math.max(cache.Total, #gens)
    local done = 0
    for _, gen in ipairs(gens) do
        if xDTaraZ.Map.GenProgress(gen) >= xDTaraZ.Config.GenDone then done += 1 end
    end
    return math.max(cache.Total - xDTaraZ.Config.SpareGens - done, 0)
end

---@return BasePart?, number  closest part to pos
function xDTaraZ.Map.Nearest(parts, pos, filter)
    local best, bestDist = nil, mathHuge
    for _, part in ipairs(parts) do
        if filter and not filter(part) then continue end
        local dist = (part.Position - pos).Magnitude
        if dist < bestDist then best, bestDist = part, dist end
    end
    return best, bestDist
end

xDTaraZ.Scheduler = { Jobs = {}, Halts = {}, Booted = false }

---@param toggles string[]?  switched off when the job keeps failing
---@param extra table?       { Core = keeps running whatever fails, Restore = run once when it halts }
function xDTaraZ.Scheduler.Every(name, interval, fn, toggles, extra)
    extra = extra or {}
    xDTaraZ.Scheduler.Jobs[name] = {
        Interval = interval, Fn = fn, Last = 0, Running = false, Toggles = toggles or {},
        Core = extra.Core or toggles == nil, Restore = extra.Restore,
    }
end

---Turns the job's options off for the logic right away; the menu toggles follow on the next UI pump.
---@return string[]  idx of every toggle that was on
function xDTaraZ.Scheduler.SwitchOff(job)
    local switched = {}
    for _, idx in ipairs(job.Toggles) do
        if xDTaraZ.Options[idx] then
            xDTaraZ.Options[idx] = false
            switched[#switched + 1] = idx
        end
    end
    return switched
end

---Warns once per failure streak. Config.JobFailLimit errors spanning Config.JobFailWindow seconds switch the job's toggles off and run its restore; a non-core job with nothing to switch off rests until one turns back on.
function xDTaraZ.Scheduler.Fail(name, job, err)
    local streak = job.Streak
    if not streak then
        streak = { count = 0, since = osClock() }
        job.Streak = streak
        warn("[ViolenceDistrict] job " .. name .. ":", err)
    end
    streak.count += 1
    if streak.count < xDTaraZ.Config.JobFailLimit or osClock() - streak.since < xDTaraZ.Config.JobFailWindow then return end

    local switched = xDTaraZ.Scheduler.SwitchOff(job)
    if job.Core and #switched == 0 then return end
    job.Streak = nil
    job.Stopped = not job.Core and #switched == 0
    if job.Restore then Util.Try("restore " .. name, job.Restore) end

    local reason = tostring(err):match("^[^\n]*")
    warn("[ViolenceDistrict] job " .. name .. " stopped: " .. reason)
    if #switched > 0 then
        table.insert(xDTaraZ.Scheduler.Halts, { Toggles = switched, Message = name .. " stopped: " .. reason })
    end
end

---@return boolean  a resting job may run again
function xDTaraZ.Scheduler.Wakes(job)
    for _, idx in ipairs(job.Toggles) do
        if xDTaraZ.Options[idx] then
            job.Stopped = nil
            return true
        end
    end
    return false
end

function xDTaraZ.Scheduler.Step()
    local now = osClock()
    for name, job in pairs(xDTaraZ.Scheduler.Jobs) do
        if job.Running or now - job.Last < job.Interval then continue end
        if job.Stopped and not xDTaraZ.Scheduler.Wakes(job) then continue end
        job.Last = now
        job.Running = true
        task.spawn(function()
            local ok, err = pcall(job.Fn)
            job.Running = false
            if ok then
                job.Streak = nil
            else
                xDTaraZ.Scheduler.Fail(name, job, err)
            end
        end)
    end
end

function xDTaraZ.Scheduler.Boot()
    if xDTaraZ.Scheduler.Booted then return end
    xDTaraZ.Scheduler.Booted = true
    xDTaraZ:Connect(RunService.Heartbeat, xDTaraZ.Scheduler.Step)
end

xDTaraZ.Player.AntiAfk = { Connection = nil }

function xDTaraZ.Player.AntiAfk.OnIdled()
    if not xDTaraZ.Options.AntiAfk then return end
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.zero)
end

function xDTaraZ.Player.AntiAfk.Arm()
    if xDTaraZ.Player.AntiAfk.Connection then return end
    xDTaraZ.Player.AntiAfk.Connection = xDTaraZ:Connect(LocalPlayer.Idled, xDTaraZ.Player.AntiAfk.OnIdled)
end

xDTaraZ.Role = { Pending = 0 }

function xDTaraZ.Role.Step()
    local mode = xDTaraZ.Options.RoleMode
    if mode ~= "Survivor only" and mode ~= "Prefer killer" then return end
    if LocalPlayer:GetAttribute("AllowKiller") == (mode == "Prefer killer") or osClock() < xDTaraZ.Role.Pending then return end
    local settings = LocalPlayer.PlayerGui:FindFirstChild("Settings", true)
    local button = settings and settings:FindFirstChild("chance", true)
    button = button and button:FindFirstChildWhichIsA("GuiButton")
    if not button or not xDTaraZ.Role.Supported() then return end
    xDTaraZ.Role.Pending = osClock() + xDTaraZ.Config.RolePending
    if not Util.Can("Connections") then
        Util.FireSignal(button.MouseButton1Click)
        return
    end
    for _, conn in ipairs(Util.GetConnections(button.MouseButton1Click)) do
        conn:Fire()
    end
end

---@return boolean  the executor can press the game's killer-chance button
function xDTaraZ.Role.Supported()
    return Util.Can("Connections") or Util.Can("Signals")
end

xDTaraZ.Movement = { Collide = {}, JumpConn = nil, Walk = nil, Lifted = nil, LiftedTo = nil }

function xDTaraZ.Movement.Frame()
    local hum, char = xDTaraZ.Player.Humanoid, xDTaraZ.Player.Character
    if not hum or not char then return end

    if xDTaraZ.Options.Speed then
        if not xDTaraZ.Movement.Walk then
            xDTaraZ.Movement.Walk = xDTaraZ.Movement.Lifted or hum.WalkSpeed
            xDTaraZ.Movement.Lifted, xDTaraZ.Movement.LiftedTo = nil, nil
        end
        hum.WalkSpeed = xDTaraZ.Options.SpeedValue
    elseif xDTaraZ.Movement.Walk then
        hum.WalkSpeed = xDTaraZ.Movement.Walk
        xDTaraZ.Movement.Walk = nil
    end
    if xDTaraZ.Options.NoSlow and not xDTaraZ.Options.Speed and hum.WalkSpeed > 0 then
        local base = xDTaraZ.Movement.BaseSpeed(char)
        if hum.WalkSpeed < base then
            xDTaraZ.Movement.Lifted = hum.WalkSpeed
            xDTaraZ.Movement.LiftedTo = base
            hum.WalkSpeed = base
        end
    elseif xDTaraZ.Movement.Lifted then
        xDTaraZ.Movement.DropLift(hum, char)
    end

    if xDTaraZ.Options.FreeTurn and not hum.AutoRotate and not char:GetAttribute("overridelookscript") and not char:GetAttribute("Immobile") then
        local root = xDTaraZ.Player.Root
        local look = Workspace.CurrentCamera.CFrame.LookVector
        local flat = vector3New(look.X, 0, look.Z)
        if root and flat.Magnitude > 0 then root.CFrame = cframeLookAt(root.Position, root.Position + flat) end
    end

    if xDTaraZ.Options.Noclip then
        for _, part in ipairs(char:GetChildren()) do
            if part:IsA("BasePart") and part.CanCollide then
                xDTaraZ.Movement.Collide[part] = true
                part.CanCollide = false
            end
        end
    elseif next(xDTaraZ.Movement.Collide) then
        xDTaraZ.Movement.RestoreCollide()
    end
end

---@return number  normal run speed for the current role
function xDTaraZ.Movement.BaseSpeed(char)
    if xDTaraZ.Player.Role() == "Killer" then
        return tonumber(char:GetAttribute("Speed")) or xDTaraZ.Config.KillerSpeed
    end
    return xDTaraZ.Config.SurvivorSpeed
end

---skipped when the game has since changed the speed itself
---@param hum  Humanoid
---@param char Model
function xDTaraZ.Movement.DropLift(hum, char)
    local before, wrote = xDTaraZ.Movement.Lifted, xDTaraZ.Movement.LiftedTo
    xDTaraZ.Movement.Lifted, xDTaraZ.Movement.LiftedTo = nil, nil
    if char:GetAttribute("Sprinting") or hum.WalkSpeed ~= wrote then return end
    hum.WalkSpeed = before
end

function xDTaraZ.Movement.RestoreCollide()
    for part in pairs(xDTaraZ.Movement.Collide) do
        if part.Parent then part.CanCollide = true end
    end
    table.clear(xDTaraZ.Movement.Collide)
end

function xDTaraZ.Movement.OnJump()
    if not xDTaraZ.Options.InfiniteJump then return end
    local hrp = xDTaraZ.Player.Root
    if not hrp then return end
    local vel = hrp.AssemblyLinearVelocity
    hrp.AssemblyLinearVelocity = vector3New(vel.X, xDTaraZ.Config.JumpVelocity, vel.Z)
end

function xDTaraZ.Movement.Start()
    xDTaraZ:Connect(RunService.Stepped, xDTaraZ.Movement.Frame)
    xDTaraZ:Connect(UserInputService.JumpRequest, xDTaraZ.Movement.OnJump)
end

function xDTaraZ.Movement.Release()
    xDTaraZ.Movement.RestoreCollide()
    local hum = xDTaraZ.Player.Humanoid
    local char = xDTaraZ.Player.Character
    if hum and hum.Parent and char and xDTaraZ.Movement.Lifted then xDTaraZ.Movement.DropLift(hum, char) end
    if hum and hum.Parent and xDTaraZ.Movement.Walk then hum.WalkSpeed = xDTaraZ.Movement.Walk end
    xDTaraZ.Movement.Walk = nil
    xDTaraZ.Movement.Lifted, xDTaraZ.Movement.LiftedTo = nil, nil
end

xDTaraZ.World = { Saved = nil }

function xDTaraZ.World.Save()
    if xDTaraZ.World.Saved then return end
    xDTaraZ.World.Saved = {
        Brightness = Lighting.Brightness,
        Ambient = Lighting.Ambient,
        OutdoorAmbient = Lighting.OutdoorAmbient,
        ClockTime = Lighting.ClockTime,
        GlobalShadows = Lighting.GlobalShadows,
        FogEnd = Lighting.FogEnd,
        FogStart = Lighting.FogStart,
        Atmosphere = {},
    }
    for _, atmo in ipairs(Lighting:GetChildren()) do
        if atmo:IsA("Atmosphere") then xDTaraZ.World.Saved.Atmosphere[atmo] = atmo.Density end
    end
end

function xDTaraZ.World.Step()
    local bright, fog = xDTaraZ.Options.Fullbright, xDTaraZ.Options.NoFog
    if not bright and not fog then
        xDTaraZ.World.Restore()
        return
    end
    xDTaraZ.World.Save()
    local saved = xDTaraZ.World.Saved

    if bright then
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.GlobalShadows = false
        Lighting.Ambient = Color3.new(1, 1, 1)
        Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
    else
        Lighting.Brightness, Lighting.ClockTime = saved.Brightness, saved.ClockTime
        Lighting.GlobalShadows, Lighting.Ambient, Lighting.OutdoorAmbient = saved.GlobalShadows, saved.Ambient, saved.OutdoorAmbient
    end

    Lighting.FogEnd = fog and 1e6 or saved.FogEnd
    Lighting.FogStart = fog and 1e6 or saved.FogStart
    for atmo, density in pairs(saved.Atmosphere) do
        if atmo.Parent then atmo.Density = fog and 0 or density end
    end
end

function xDTaraZ.World.Restore()
    local saved = xDTaraZ.World.Saved
    if not saved then return end
    xDTaraZ.World.Saved = nil
    Lighting.Brightness, Lighting.ClockTime = saved.Brightness, saved.ClockTime
    Lighting.GlobalShadows, Lighting.Ambient, Lighting.OutdoorAmbient = saved.GlobalShadows, saved.Ambient, saved.OutdoorAmbient
    Lighting.FogEnd, Lighting.FogStart = saved.FogEnd, saved.FogStart
    for atmo, density in pairs(saved.Atmosphere) do
        if atmo.Parent then atmo.Density = density end
    end
end

xDTaraZ.Block = { Muted = {}, Own = {}, Restore = nil }

---@return RBXScriptSignal?  game signal a rule silences
local function RemoteSignal(folder, ...)
    local node = ReplicatedStorage:FindFirstChild("Remotes")
    for _, name in ipairs({ folder, ... }) do
        node = node and node:FindFirstChild(name)
    end
    if not node then return nil end
    return node:IsA("BindableEvent") and node.Event or node.OnClientEvent
end

xDTaraZ.Block.Rules = {
    { Option = "PerfectSkillCheck", Signals = { RemoteSignal("Generator", "SkillCheckEvent"), RemoteSignal("Healing", "SkillCheckEvent") } },
    { Option = "AntiStun", Signals = { RemoteSignal("Pallet", "Jason", "Stun") } },
    { Option = "AntiBlind", Signals = { RemoteSignal("Items", "Flashlight", "GotBlinded") } },
    { Option = "AntiShake", Signals = { RemoteSignal("Game", "shake") } },
}

function xDTaraZ.Block.Keep(fn)
    xDTaraZ.Block.Own[fn] = true
end

function xDTaraZ.Block.Mute(rule)
    local muted = xDTaraZ.Block.Muted[rule] or {}
    xDTaraZ.Block.Muted[rule] = muted
    for _, signal in ipairs(rule.Signals) do
        for _, conn in ipairs(Util.GetConnections(signal)) do
            if conn.Enabled and not xDTaraZ.Block.Own[conn.Function] then
                pcall(function() conn:Disable() end)
                muted[#muted + 1] = conn
            end
        end
    end
end

function xDTaraZ.Block.Unmute(rule)
    local muted = xDTaraZ.Block.Muted[rule]
    if not muted then return end
    for _, conn in ipairs(muted) do pcall(function() conn:Enable() end) end
    xDTaraZ.Block.Muted[rule] = nil
end

function xDTaraZ.Block.Step()
    xDTaraZ.Block.SyncFall()
    if not Util.Can("Connections") then return end
    for _, rule in ipairs(xDTaraZ.Block.Rules) do
        if xDTaraZ.Options[rule.Option] then xDTaraZ.Block.Mute(rule) else xDTaraZ.Block.Unmute(rule) end
    end
end

function xDTaraZ.Block.Release()
    xDTaraZ.Block.SyncFall()
    for _, rule in ipairs(xDTaraZ.Block.Rules) do xDTaraZ.Block.Unmute(rule) end
end

---Fall hook lives only while No Fall is on; the original namecall goes back when it turns off or on unload.
function xDTaraZ.Block.SyncFall()
    local wanted = xDTaraZ.Options.NoFall and xDTaraZ.State.Alive
    if wanted and not xDTaraZ.Block.Restore then
        xDTaraZ.Block.HookFall()
    elseif not wanted and xDTaraZ.Block.Restore then
        local restore = xDTaraZ.Block.Restore
        xDTaraZ.Block.Restore = nil
        pcall(restore)
    end
end

function xDTaraZ.Block.HookFall()
    local fall = GameLib.Remote.Fall
    if not (fall and Util.Can("Namecall")) then return end
    local original, restore
    original, restore = Util.HookMeta(game, "__namecall", function(self, ...)
        if self == fall and xDTaraZ.Options.NoFall and xDTaraZ.State.Alive and Util.NameCallMethod() == "FireServer" then return nil end
        return original(self, ...)
    end)
    xDTaraZ.Block.Restore = restore
end

xDTaraZ.Survivor = {
    Job = nil,
    Gen = nil,
    Banned = {},
    Map = nil,
    Status = "Off",
    RoundStart = 0,
    Escapes = 0,
    LastEscape = 0,
}

xDTaraZ.Survivor.Rank = { Unhook = 3, Heal = 2, Repair = 1 }

---@param kind string    Repair / Heal / Unhook
---@param target Instance  point or teammate root the remote takes
function xDTaraZ.Survivor.NewJob(kind, target, remote)
    return { Kind = kind, Target = target, Remote = remote, Since = osClock(), Fired = false, Progress = 0, Checked = osClock() }
end

function xDTaraZ.Survivor.Finish()
    local job = xDTaraZ.Survivor.Job
    xDTaraZ.Survivor.Job = nil
    if not (job and job.Fired) or job.Kind == "Unhook" or not job.Target.Parent then return end
    pcall(function() job.Remote:FireServer(job.Target, false) end)
end

---@param locked boolean  action already started, only re-warp if we drifted far
function xDTaraZ.Survivor.Hold(target, locked)
    local hrp = xDTaraZ.Player.Root
    if not hrp then return end
    local teammate = target.Name == "HumanoidRootPart"
    local spot = teammate and (target.CFrame * cframeNew(0, 0, 2.5)).Position or target.Position
    local flat = vector3New(hrp.Position.X - spot.X, 0, hrp.Position.Z - spot.Z).Magnitude
    if flat <= (locked and xDTaraZ.Config.DriftLimit or xDTaraZ.Config.ArriveRadius) then return end
    local look = teammate and target.Position or spot + target.CFrame.LookVector
    xDTaraZ.Player.Teleport(cframeLookAt(spot, look))
end

---@param scale number?  radius multiplier, larger when picking new work
---@return boolean        too close to the killer while Auto Dodge is on
function xDTaraZ.Survivor.Danger(pos, scale)
    local opts = xDTaraZ.Options
    if not opts.AutoDodge then return false end
    local killer = xDTaraZ.Player.Killer()
    local root = killer and killer:FindFirstChild("HumanoidRootPart")
    return root ~= nil and (root.Position - pos).Magnitude <= opts.DodgeRadius * (scale or xDTaraZ.Config.DangerKeep)
end

function xDTaraZ.Survivor.GenUsable(gen)
    if not gen or not gen.Parent then return false end
    if xDTaraZ.Map.GenProgress(gen) >= xDTaraZ.Config.GenDone then return false end
    return osClock() >= (xDTaraZ.Survivor.Banned[gen] or 0)
end

---@return BasePart?  a free, safe point on this generator
function xDTaraZ.Survivor.PointOn(gen)
    local job = xDTaraZ.Survivor.Job
    for _, point in ipairs(xDTaraZ.Map.PointsOf(gen)) do
        local mine = job and job.Target == point
        if not mine and CollectionService:HasTag(point, "doing action") then continue end
        if xDTaraZ.Survivor.Danger(point.Position, xDTaraZ.Config.DangerPick) then continue end
        return point
    end
    return nil
end

---@param peek boolean?  don't change the committed generator
---@return BasePart?      keeps the committed generator until it is done or unsafe
function xDTaraZ.Survivor.PickGenPoint(pos, peek)
    local gen = xDTaraZ.Survivor.Gen
    local point = xDTaraZ.Survivor.GenUsable(gen) and xDTaraZ.Survivor.PointOn(gen)
    if point then return point end

    local best, bestScore = nil, mathHuge
    for _, candidate in ipairs(xDTaraZ.Map.Generators()) do
        if not xDTaraZ.Survivor.GenUsable(candidate) then continue end
        local spot = xDTaraZ.Survivor.PointOn(candidate)
        if not spot then continue end
        local score = (xDTaraZ.Config.GenDone - xDTaraZ.Map.GenProgress(candidate)) + (spot.Position - pos).Magnitude * xDTaraZ.Config.DistanceWeight
        if score < bestScore then best, bestScore = spot, score end
    end
    if not peek then xDTaraZ.Survivor.Gen = best and best:FindFirstAncestor("Generator") end
    return best
end

---@param downedOnly boolean  only teammates who are on the floor
---@return BasePart?            closest teammate worth healing, downed first
function xDTaraZ.Survivor.HealTarget(downedOnly)
    local me = xDTaraZ.Player.Root
    local best, bestScore = nil, mathHuge
    for _, char in ipairs(xDTaraZ.Player.Survivors()) do
        local hrp = char.HumanoidRootPart
        if hrp:GetAttribute("CanGetHealed") ~= true or char:GetAttribute("IsHooked") or char:GetAttribute("IsCarried") then continue end
        if char:GetAttribute("IsBeingHealed") or osClock() < (xDTaraZ.Survivor.Banned[char] or 0) then continue end
        local downed = char:GetAttribute("Knocked") == true
        if downedOnly and not downed then continue end
        if xDTaraZ.Survivor.Danger(hrp.Position, xDTaraZ.Config.DangerPick) then continue end
        local score = (downed and 0 or 1000) + (me and (hrp.Position - me.Position).Magnitude or 0)
        if score < bestScore then best, bestScore = hrp, score end
    end
    return best
end

function xDTaraZ.Survivor.UnhookTarget()
    local points = xDTaraZ.Map.Tagged("UnhookPoint")
    for _, char in ipairs(xDTaraZ.Player.Survivors()) do
        if char:GetAttribute("IsHooked") ~= true or osClock() < (xDTaraZ.Survivor.Banned[char] or 0) then continue end
        local point, dist = xDTaraZ.Map.Nearest(points, char.HumanoidRootPart.Position)
        if point and dist < xDTaraZ.Config.UnhookReach and not xDTaraZ.Survivor.Danger(point.Position, xDTaraZ.Config.DangerPick) then
            return point, char
        end
    end
    return nil
end

---@return boolean  current job still has something to do
function xDTaraZ.Survivor.JobAlive(job)
    local target = job.Target
    if not target.Parent or xDTaraZ.Survivor.Danger(target.Position) then return false end
    local age = osClock() - job.Since
    if job.Kind == "Heal" then
        local ok = age <= xDTaraZ.Config.HealMax and target:GetAttribute("CanGetHealed") == true
        if not ok and age < xDTaraZ.Config.HealMinUseful then
            xDTaraZ.Survivor.Banned[target.Parent] = osClock() + xDTaraZ.Config.HelpBan
        end
        return ok
    end
    if job.Kind == "Unhook" then
        if age < xDTaraZ.Config.UnhookHold then return true end
        if job.Char then xDTaraZ.Survivor.Banned[job.Char] = osClock() + xDTaraZ.Config.HelpBan end
        return false
    end
    return xDTaraZ.Survivor.GenUsable(target:FindFirstAncestor("Generator")) and xDTaraZ.Map.GensLeft() > 0
end

---@return table?  best new job, only if it should replace the current one
function xDTaraZ.Survivor.Candidate(pos)
    local opts, remote = xDTaraZ.Options, GameLib.Remote
    local job = xDTaraZ.Survivor.Job
    local rank = job and xDTaraZ.Survivor.Rank[job.Kind] or 0
    local finishing = job and job.Kind == "Repair"
        and xDTaraZ.Map.GenProgress(job.Target:FindFirstAncestor("Generator")) >= xDTaraZ.Config.FinishFirst

    if opts.AutoUnhook and rank < 3 and not finishing then
        local point, char = xDTaraZ.Survivor.UnhookTarget()
        if point then
            local unhook = xDTaraZ.Survivor.NewJob("Unhook", point, remote.Unhook)
            unhook.Char = char
            return unhook
        end
    end
    if opts.AutoHeal and rank < 2 and not finishing then
        local hrp = xDTaraZ.Survivor.HealTarget(true)
        if hrp then return xDTaraZ.Survivor.NewJob("Heal", hrp, remote.Heal) end
    end
    if job then return nil end
    if opts.AutoRepair and xDTaraZ.Map.GensLeft() > 0 then
        local point = xDTaraZ.Survivor.PickGenPoint(pos)
        if point then return xDTaraZ.Survivor.NewJob("Repair", point, remote.Repair) end
    end
    if opts.AutoHeal then
        local hrp = xDTaraZ.Survivor.HealTarget(false)
        if hrp then return xDTaraZ.Survivor.NewJob("Heal", hrp, remote.Heal) end
    end
    return nil
end

function xDTaraZ.Survivor.Watchdog(job)
    if job.Kind ~= "Repair" or osClock() - job.Checked < xDTaraZ.Config.StallTime then return end
    local gen = job.Target:FindFirstAncestor("Generator")
    local progress = xDTaraZ.Map.GenProgress(gen)
    job.Checked = osClock()
    if progress > job.Progress then
        job.Progress = progress
        return
    end
    xDTaraZ.Survivor.Banned[gen] = osClock() + xDTaraZ.Config.StallBan
    xDTaraZ.Survivor.Gen = nil
    xDTaraZ.Survivor.Finish()
end

function xDTaraZ.Survivor.Run(job)
    xDTaraZ.Survivor.Hold(job.Target, job.Fired and job.Kind ~= "Heal")
    if not job.Fired and osClock() - job.Since >= xDTaraZ.Config.Settle then
        job.Fired = true
        job.Progress = job.Kind == "Repair" and xDTaraZ.Map.GenProgress(job.Target:FindFirstAncestor("Generator")) or 0
        job.Checked = osClock()
        if job.Kind == "Unhook" then job.Remote:FireServer(job.Target) else job.Remote:FireServer(job.Target, true) end
    end
    if job.Fired then xDTaraZ.Survivor.Watchdog(job) end
    xDTaraZ.Survivor.Status = (job.Fired and job.Kind or "Moving to " .. job.Kind) .. " · gens left " .. xDTaraZ.Map.GensLeft()
end

---@return BasePart?  walk-through floor of the finish line
function xDTaraZ.Survivor.FinishLine()
    local hrp = xDTaraZ.Player.Root
    if not hrp then return nil end
    return xDTaraZ.Map.Nearest(xDTaraZ.Map.Tagged("EscapePart"), hrp.Position, function(part)
        return not part.CanCollide
    end)
end

function xDTaraZ.Survivor.EscapeNow()
    local line = xDTaraZ.Survivor.FinishLine()
    if not line then return false end
    xDTaraZ.Survivor.Finish()
    xDTaraZ.Player.Teleport(line.CFrame + vector3New(0, 3, 0))
    local hrp = xDTaraZ.Player.Root
    if Util.FireTouch and hrp then
        Util.FireTouch(hrp, line, 0)
        Util.FireTouch(hrp, line, 1)
    end
    return true
end

function xDTaraZ.Survivor.Enabled()
    local opts = xDTaraZ.Options
    return opts.AutoRepair or opts.AutoHeal or opts.AutoUnhook or opts.InstantEscape
end

---@return boolean  escaped this tick
function xDTaraZ.Survivor.TryEscape()
    local opts = xDTaraZ.Options
    local ready = opts.InstantEscape and (osClock() - xDTaraZ.Survivor.RoundStart >= opts.EscapeDelay or xDTaraZ.Map.GensLeft() == 0)
    if not ready then return false end
    if osClock() - xDTaraZ.Survivor.LastEscape < xDTaraZ.Config.EscapeRetry then return true end
    if not xDTaraZ.Survivor.EscapeNow() then return false end
    xDTaraZ.Survivor.LastEscape = osClock()
    xDTaraZ.Survivor.Escapes += 1
    xDTaraZ.Survivor.Status = "Escaped"
    return true
end

function xDTaraZ.Survivor.Step()
    if not xDTaraZ.Survivor.Enabled() then
        xDTaraZ.Survivor.Finish()
        xDTaraZ.Survivor.Status = "Off"
        return
    end
    local map = xDTaraZ.Map.Root()
    if map ~= xDTaraZ.Survivor.Map then
        xDTaraZ.Survivor.Map = map
        xDTaraZ.Survivor.RoundStart = osClock()
    end
    if not xDTaraZ.State.Alive or xDTaraZ.Player.Role() ~= "Survivors" or not xDTaraZ.Player:IsAlive() then
        xDTaraZ.Survivor.Gen = nil
        table.clear(xDTaraZ.Survivor.Banned)
        xDTaraZ.Survivor.Finish()
        xDTaraZ.Survivor.Status = "Not a survivor"
        return
    end
    if xDTaraZ.Player.Disabled(xDTaraZ.Player.Character) then
        xDTaraZ.Survivor.Finish()
        xDTaraZ.Survivor.Status = "Downed / hooked"
        return
    end
    if xDTaraZ.Survivor.TryEscape() then return end

    local job = xDTaraZ.Survivor.Job
    if job and not xDTaraZ.Survivor.JobAlive(job) then
        xDTaraZ.Survivor.Finish()
        job = nil
    end
    local better = xDTaraZ.Survivor.Candidate(xDTaraZ.Player.Root.Position)
    if better then
        xDTaraZ.Survivor.Finish()
        xDTaraZ.Survivor.Job = better
        job = better
    end
    if not job then
        xDTaraZ.Survivor.Status = "Waiting · gens left " .. xDTaraZ.Map.GensLeft()
        return
    end
    xDTaraZ.Survivor.Run(job)
end

xDTaraZ.Guard = { Dodges = 0, LastUnhook = 0, UnhookTries = 0, LastDodge = 0 }

---@return BasePart?  free point on the unfinished generator farthest from the killer
function xDTaraZ.Guard.SafeSpot(killerPos)
    local best, bestDist = nil, 0
    for _, gen in ipairs(xDTaraZ.Map.Generators()) do
        if not xDTaraZ.Survivor.GenUsable(gen) then continue end
        local point = xDTaraZ.Survivor.PointOn(gen)
        local dist = point and (point.Position - killerPos).Magnitude or 0
        if dist > bestDist then best, bestDist = point, dist end
    end
    return best
end

function xDTaraZ.Guard.Step()
    local opts = xDTaraZ.Options
    if not (opts.AutoDodge or opts.AutoSelfUnhook) or not xDTaraZ.State.Alive then return end
    if xDTaraZ.Player.Role() ~= "Survivors" or not xDTaraZ.Player:IsAlive() then return end
    local char, hrp = xDTaraZ.Player.Character, xDTaraZ.Player.Root

    if not char:GetAttribute("IsHooked") then xDTaraZ.Guard.UnhookTries = 0 end
    if opts.AutoSelfUnhook and char:GetAttribute("IsHooked") and xDTaraZ.Guard.UnhookTries < xDTaraZ.Config.SelfUnhookMax
        and osClock() - xDTaraZ.Guard.LastUnhook >= xDTaraZ.Config.SelfUnhookRetry then
        xDTaraZ.Guard.LastUnhook = osClock()
        xDTaraZ.Guard.UnhookTries += 1
        GameLib.Remote.SelfUnhook:FireServer()
        return
    end
    if not opts.AutoDodge or xDTaraZ.Player.Disabled(char) or osClock() - xDTaraZ.Guard.LastDodge < xDTaraZ.Config.DodgeCooldown then return end

    local killer = xDTaraZ.Player.Killer()
    local root = killer and killer:FindFirstChild("HumanoidRootPart")
    if not root or (root.Position - hrp.Position).Magnitude > opts.DodgeRadius then return end
    local spot = xDTaraZ.Guard.SafeSpot(root.Position)
    if not spot or (spot.Position - root.Position).Magnitude <= opts.DodgeRadius then return end
    xDTaraZ.Guard.LastDodge = osClock()
    xDTaraZ.Survivor.Finish()
    xDTaraZ.Survivor.Gen = spot:FindFirstAncestor("Generator")
    xDTaraZ.Player.Teleport(spot.CFrame + vector3New(0, 3, 0))
    xDTaraZ.Guard.Dodges += 1
end

xDTaraZ.Alert = { Near = false, Distance = nil }

function xDTaraZ.Alert.Step()
    local hrp = xDTaraZ.Player.Root
    local killer = xDTaraZ.Player.Killer()
    local root = killer and killer:FindFirstChild("HumanoidRootPart")
    if not (hrp and root) or xDTaraZ.Player.Role() ~= "Survivors" then
        xDTaraZ.Alert.Near, xDTaraZ.Alert.Distance = false, nil
        return
    end
    local dist = (root.Position - hrp.Position).Magnitude
    xDTaraZ.Alert.Distance = dist
    local near = dist <= xDTaraZ.Config.AlertRadius
    if near and not xDTaraZ.Alert.Near and xDTaraZ.Options.KillerAlert and xDTaraZ.Library then
        xDTaraZ.Library:Notify("Killer nearby", ("%d m away"):format(dist), 3, "Warning")
    end
    xDTaraZ.Alert.Near = near
end

xDTaraZ.SkillCheck = { Started = false, Checks = 0 }

function xDTaraZ.SkillCheck.OnGen(point, checkId)
    if not xDTaraZ.Options.PerfectSkillCheck then return end
    xDTaraZ.SkillCheck.Checks += 1
    GameLib.Remote.GenResult:FireServer("success", 1, point, checkId)
end

function xDTaraZ.SkillCheck.OnHeal(point)
    if not xDTaraZ.Options.PerfectSkillCheck then return end
    xDTaraZ.SkillCheck.Checks += 1
    GameLib.Remote.HealResult:FireServer("success", 1, point)
end

function xDTaraZ.SkillCheck.Start()
    local remote = GameLib.Remote
    if xDTaraZ.SkillCheck.Started or not (remote.GenCheck and remote.HealCheck and remote.GenResult and remote.HealResult) then return end
    xDTaraZ.SkillCheck.Started = true
    xDTaraZ.Block.Keep(xDTaraZ.SkillCheck.OnGen)
    xDTaraZ.Block.Keep(xDTaraZ.SkillCheck.OnHeal)
    xDTaraZ:Connect(remote.GenCheck.OnClientEvent, xDTaraZ.SkillCheck.OnGen)
    xDTaraZ:Connect(remote.HealCheck.OnClientEvent, xDTaraZ.SkillCheck.OnHeal)
end

function xDTaraZ.Survivor.Sacrifice()
    local hum = xDTaraZ.Player.Humanoid
    if not hum or xDTaraZ.Player.Role() ~= "Survivors" then return false end
    xDTaraZ.Survivor.Finish()
    hum.Health = 0
    return true
end

xDTaraZ.Parry = { Last = 0, Count = 0, Clients = setmetatable({}, { __mode = "k" }), Scanned = 0 }

function xDTaraZ.Parry.Remote()
    return GameLib.FindRemote("Items", "Parrying Dagger", "parry")
end

function xDTaraZ.Parry.Holding()
    return LocalPlayer:GetAttribute("EquippedItem") == "Parrying Dagger"
end

---@return boolean  killer is close and closing in fast
function xDTaraZ.Parry.Threat()
    local hrp = xDTaraZ.Player.Root
    local killer = xDTaraZ.Player.Killer()
    local root = killer and killer:FindFirstChild("HumanoidRootPart")
    if not (hrp and root) then return false end
    local offset = hrp.Position - root.Position
    if offset.Magnitude > xDTaraZ.Config.ParryRange then return false end
    local closing = root.AssemblyLinearVelocity:Dot(offset.Unit)
    return closing >= xDTaraZ.Config.ParryClosing or offset.Magnitude <= xDTaraZ.Config.ParryPanic
end

function xDTaraZ.Parry.FindClients()
    if not Util.Can("Gc") or osClock() - xDTaraZ.Parry.Scanned < xDTaraZ.Config.ParryScan then return end
    xDTaraZ.Parry.Scanned = osClock()
    for _, obj in ipairs(Util.GetGc(true)) do
        if type(obj) == "table" and rawget(obj, "isParryOnCooldown") ~= nil and rawget(obj, "parryEvent") then
            xDTaraZ.Parry.Clients[obj] = true
        end
    end
end

function xDTaraZ.Parry.ClearCooldowns()
    xDTaraZ.Parry.FindClients()
    for client in pairs(xDTaraZ.Parry.Clients) do
        client.isParryOnCooldown = false
        client.isParryResolving = false
        client.cooldownToken = (client.cooldownToken or 0) + 1
    end
end

function xDTaraZ.Parry.Step()
    local opts = xDTaraZ.Options
    if not (opts.AutoParry or opts.NoParryCooldown) or not xDTaraZ.State.Alive then return end
    if xDTaraZ.Player.Role() ~= "Survivors" or not xDTaraZ.Parry.Holding() then return end
    if opts.NoParryCooldown then xDTaraZ.Parry.ClearCooldowns() end
    if not opts.AutoParry or xDTaraZ.Player.Disabled(xDTaraZ.Player.Character) then return end

    local retry = opts.NoParryCooldown and xDTaraZ.Config.ParryFast or xDTaraZ.Config.ParryRetry
    if osClock() - xDTaraZ.Parry.Last < retry or not xDTaraZ.Parry.Threat() then return end
    local remote = xDTaraZ.Parry.Remote()
    if not remote then return end
    xDTaraZ.Parry.Last = osClock()
    xDTaraZ.Parry.Count += 1
    remote:FireServer()
end

xDTaraZ.Killer = { Status = "Off", LastSwing = 0, Hits = 0, Breaks = 0, Kicked = {} }

function xDTaraZ.Killer.Behind(targetRoot)
    local pos = targetRoot.Position - targetRoot.CFrame.LookVector * xDTaraZ.Config.AttackReach
    return cframeLookAt(pos, targetRoot.Position)
end

---@return Model?  nearest survivor matching state, inside range
function xDTaraZ.Killer.Pick(knocked, range)
    local hrp = xDTaraZ.Player.Root
    local best, bestDist = nil, range
    for _, char in ipairs(xDTaraZ.Player.Survivors()) do
        if (char:GetAttribute("Knocked") == true) ~= knocked then continue end
        if char:GetAttribute("IsHooked") or char:GetAttribute("IsCarried") then continue end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        local dist = (char.HumanoidRootPart.Position - hrp.Position).Magnitude
        if dist < bestDist then best, bestDist = char, dist end
    end
    return best
end

function xDTaraZ.Killer.Swing(target)
    local root = target.HumanoidRootPart
    local remote = GameLib.Remote
    local stop = osClock() + xDTaraZ.Config.LungeDelay + xDTaraZ.Config.SwingTail
    local fired = false
    remote.Lunge:FireServer()
    local start = osClock()
    while osClock() < stop and root.Parent and xDTaraZ.State.Alive and xDTaraZ.Options.KillAura do
        xDTaraZ.Player.Teleport(xDTaraZ.Killer.Behind(root))
        if not fired and osClock() - start >= xDTaraZ.Config.LungeDelay then
            fired = true
            remote.Attack:FireServer()
        end
        RunService.Heartbeat:Wait()
    end
    if target:GetAttribute("Knocked") then xDTaraZ.Killer.Hits += 1 end
end

---@return boolean  still allowed to act after a yield
function xDTaraZ.Killer.Live(option, hrp)
    return xDTaraZ.State.Alive and xDTaraZ.Options[option] and xDTaraZ.Player:IsAlive() and xDTaraZ.Player.Root == hrp
end

function xDTaraZ.Killer.Carry(target)
    local hrp = xDTaraZ.Player.Root
    xDTaraZ.Player.Teleport(xDTaraZ.Killer.Behind(target.HumanoidRootPart))
    task.wait(xDTaraZ.Config.Settle)
    if not xDTaraZ.Killer.Live("AutoHook", hrp) or not target:GetAttribute("Knocked") then return end
    GameLib.Remote.Carry:FireServer(target)
    task.wait(xDTaraZ.Config.CarryDelay)
end

---@param offset Vector3  where the game stands you relative to the point
---@return boolean  false if the action was abandoned
function xDTaraZ.Killer.Commit(option, point, offset, remote, commit)
    local hrp = xDTaraZ.Player.Root
    if not hrp then return false end
    local seat = point.CFrame * cframeNew(offset)
    xDTaraZ.Player.Teleport(seat * cframeNew(0, 0, 3))
    task.wait(xDTaraZ.Config.Settle)
    if not xDTaraZ.Killer.Live(option, hrp) then return false end
    remote:FireServer(point)
    local tween = TweenService:Create(hrp, TweenInfo.new(xDTaraZ.Config.HookTween), { CFrame = seat })
    tween:Play()
    tween.Completed:Wait()
    if not xDTaraZ.Killer.Live(option, hrp) then return false end
    commit:FireServer(point)
    return true
end

function xDTaraZ.Killer.Hook()
    local hrp = xDTaraZ.Player.Root
    local point = hrp and xDTaraZ.Map.Nearest(xDTaraZ.Map.Tagged("HookPoint"), hrp.Position)
    if not point then return end
    if xDTaraZ.Killer.Commit("AutoHook", point, vector3New(0, 0.6, 0), GameLib.Remote.Hook, GameLib.Remote.HookCommit) then
        task.wait(xDTaraZ.Config.HookRest)
    end
end

---@return BasePart?  point on the most-repaired unfinished generator
function xDTaraZ.Killer.GenToBreak()
    local best, bestProgress = nil, 0
    for _, point in ipairs(xDTaraZ.Map.Tagged("GeneratorPoint")) do
        local gen = point:FindFirstAncestor("Generator")
        local progress = gen and xDTaraZ.Map.GenProgress(gen) or 0
        local fresh = gen and osClock() - (xDTaraZ.Killer.Kicked[gen] or 0) > xDTaraZ.Config.KickRegress
        if fresh and progress > bestProgress and progress < xDTaraZ.Config.GenDone then
            best, bestProgress = point, progress
        end
    end
    return best
end

function xDTaraZ.Killer.BreakGen(point)
    if not xDTaraZ.Killer.Commit("AutoBreakGens", point, vector3New(0, 0, 1), GameLib.Remote.BreakGen, GameLib.Remote.BreakGenCommit) then return end
    task.wait(xDTaraZ.Config.GenBreakTime)
    xDTaraZ.Killer.Kicked[point:FindFirstAncestor("Generator")] = osClock()
    xDTaraZ.Killer.Breaks += 1
end

xDTaraZ.AntiStun = { Count = 0 }

function xDTaraZ.AntiStun.OnStun()
    if not xDTaraZ.Options.AntiStun or xDTaraZ.Player.Role() ~= "Killer" then return end
    xDTaraZ.AntiStun.Count += 1
    GameLib.Remote.StunOver:FireServer()
end

function xDTaraZ.AntiStun.Start()
    if not (GameLib.Remote.Stun and GameLib.Remote.StunOver) then return end
    xDTaraZ.Block.Keep(xDTaraZ.AntiStun.OnStun)
    xDTaraZ:Connect(GameLib.Remote.Stun.OnClientEvent, xDTaraZ.AntiStun.OnStun)
end

---@return Model?  survivor right in front of us inside lunge reach
function xDTaraZ.Killer.InFront()
    local hrp = xDTaraZ.Player.Root
    local look = hrp.CFrame.LookVector
    for _, char in ipairs(xDTaraZ.Player.Survivors()) do
        if char:GetAttribute("Knocked") or char:GetAttribute("IsHooked") or char:GetAttribute("IsCarried") then continue end
        local offset = char.HumanoidRootPart.Position - hrp.Position
        if offset.Magnitude <= xDTaraZ.Config.LegitReach and look:Dot(offset.Unit) >= xDTaraZ.Config.LegitAngle then return char end
    end
    return nil
end

---@param target Model  survivor in front; closed in on when Smart Hitbox is on
function xDTaraZ.Killer.LegitSwing(target)
    local remote = GameLib.Remote
    local root = target.HumanoidRootPart
    local function Close()
        local hrp = xDTaraZ.Player.Root
        if not (xDTaraZ.Options.SmartHitbox and hrp and root.Parent) then return end
        local offset = root.Position - hrp.Position
        if offset.Magnitude <= xDTaraZ.Config.ServerReach then return end
        local spot = root.Position - offset.Unit * xDTaraZ.Config.AttackReach
        xDTaraZ.Player.Teleport(cframeLookAt(vector3New(spot.X, hrp.Position.Y, spot.Z), vector3New(root.Position.X, hrp.Position.Y, root.Position.Z)))
    end
    Close()
    remote.Lunge:FireServer()
    task.wait(xDTaraZ.Config.LungeDelay)
    Close()
    remote.Attack:FireServer()
end

function xDTaraZ.Killer.Enabled()
    local opts = xDTaraZ.Options
    return opts.KillAura or opts.AutoHook or opts.AutoBreakGens
end

function xDTaraZ.Killer.Step()
    if not xDTaraZ.Killer.Enabled() then
        xDTaraZ.Killer.Status = "Off"
        return
    end
    if not xDTaraZ.State.Alive or xDTaraZ.Player.Role() ~= "Killer" or not xDTaraZ.Player:IsAlive() then
        xDTaraZ.Killer.Status = "Not the killer"
        return
    end
    local char, opts = xDTaraZ.Player.Character, xDTaraZ.Options

    if char:GetAttribute("CarriedSurvivorId") then
        if opts.AutoHook then xDTaraZ.Killer.Hook() end
        xDTaraZ.Killer.Status = "Carrying"
        return
    end

    if opts.AutoHook then
        local downed = xDTaraZ.Killer.Pick(true, opts.AuraRange)
        if downed then
            xDTaraZ.Killer.Status = "Picking up " .. downed.Name
            xDTaraZ.Killer.Carry(downed)
            return
        end
    end

    if opts.KillAura and GameLib.Remote.Lunge and GameLib.Remote.Attack and osClock() - xDTaraZ.Killer.LastSwing >= xDTaraZ.Config.AuraCooldown then
        local legit = opts.SlashMode == "Legit"
        local target = legit and xDTaraZ.Killer.InFront() or not legit and xDTaraZ.Killer.Pick(false, opts.AuraRange)
        if target then
            xDTaraZ.Killer.LastSwing = osClock()
            xDTaraZ.Killer.Status = "Hitting " .. target.Name
            if legit then xDTaraZ.Killer.LegitSwing(target) else xDTaraZ.Killer.Swing(target) end
            return
        end
    end
    if opts.AutoBreakGens then
        local point = xDTaraZ.Killer.GenToBreak()
        if point then
            xDTaraZ.Killer.Status = "Breaking generator"
            xDTaraZ.Killer.BreakGen(point)
            return
        end
    end
    xDTaraZ.Killer.Status = ("Hunting · downs %d · gens kicked %d"):format(xDTaraZ.Killer.Hits, xDTaraZ.Killer.Breaks)
end

xDTaraZ.Teleport = {}

function xDTaraZ.Teleport.Places()
    local names = { "Nearest Generator", "Best Generator", "Exit Gate", "Nearest Hook", "Killer", "Farthest From Killer" }
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then names[#names + 1] = player.Name end
    end
    return names
end

---@return CFrame?  stand spot for a teleport choice
function xDTaraZ.Teleport.Resolve(choice)
    local hrp = xDTaraZ.Player.Root
    if not hrp then return nil end
    local pos = hrp.Position
    local function At(part) return part and part.CFrame + vector3New(0, 3, 0) end

    if choice == "Nearest Generator" then
        return At(xDTaraZ.Map.Nearest(xDTaraZ.Map.Tagged("GeneratorPoint"), pos, function(point)
            local gen = point:FindFirstAncestor("Generator")
            return gen and xDTaraZ.Map.GenProgress(gen) < xDTaraZ.Config.GenDone
        end))
    elseif choice == "Best Generator" then
        return At(xDTaraZ.Survivor.PickGenPoint(pos, true))
    elseif choice == "Exit Gate" then
        local gate = xDTaraZ.Map.Models("Gate")[1]
        local part = gate and (gate:FindFirstChild("ExitLever", true) or gate:FindFirstChildWhichIsA("BasePart", true))
        return part and (part:IsA("Model") and part:GetPivot() or part.CFrame) + vector3New(0, 3, 0)
    elseif choice == "Nearest Hook" then
        return At(xDTaraZ.Map.Nearest(xDTaraZ.Map.Tagged("HookPoint"), pos))
    elseif choice == "Killer" then
        local killer = xDTaraZ.Player.Killer()
        return killer and At(killer:FindFirstChild("HumanoidRootPart"))
    elseif choice == "Farthest From Killer" then
        local killer = xDTaraZ.Player.Killer()
        local root = killer and killer:FindFirstChild("HumanoidRootPart")
        if not root then return nil end
        local best, bestDist = nil, 0
        for _, point in ipairs(xDTaraZ.Map.Tagged("GeneratorPoint")) do
            local dist = (point.Position - root.Position).Magnitude
            if dist > bestDist then best, bestDist = point, dist end
        end
        return At(best)
    end
    local player = Players:FindFirstChild(choice)
    return player and player.Character and At(player.Character:FindFirstChild("HumanoidRootPart"))
end

function xDTaraZ.Teleport.Go(choice)
    local cframe = xDTaraZ.Teleport.Resolve(choice)
    if not cframe then return false end
    xDTaraZ.Player.Teleport(cframe)
    return true
end

xDTaraZ.Esp = { Count = 0, Marks = {}, Folder = nil }

---@return table[]  players in the shape Library.Visuals expects
function xDTaraZ.Esp.Targets()
    local list = {}
    local mine = xDTaraZ.Player.Role()
    for _, player in ipairs(Players:GetPlayers()) do
        local char = player.Character
        local role = xDTaraZ.Player.Role(player)
        if player == LocalPlayer or not char or (role ~= "Survivors" and role ~= "Killer") then continue end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        local tag = role == "Killer" and "KILLER" or char:GetAttribute("IsHooked") and "Hooked"
            or char:GetAttribute("Knocked") and "Downed" or nil
        list[#list + 1] = {
            Model = char,
            Name = tag and (player.DisplayName .. " [" .. tag .. "]") or player.DisplayName,
            Health = hum.Health,
            MaxHealth = hum.MaxHealth > 0 and hum.MaxHealth or 100,
            Friendly = mine == role,
            Root = char:FindFirstChild("HumanoidRootPart"),
        }
    end
    xDTaraZ.Esp.Count = #list
    return list
end

xDTaraZ.Esp.Kinds = {
    { Option = "EspGenerators", Glow = true, Color = Color3.fromRGB(255, 196, 64), Find = xDTaraZ.Map.Generators, Label = function(model)
        local progress = xDTaraZ.Map.GenProgress(model)
        if progress >= xDTaraZ.Config.GenDone then return "Gen DONE" end
        return ("Gen %d%%"):format(progress)
    end },
    { Option = "EspHooks", Glow = true, Color = Color3.fromRGB(235, 70, 70), Find = function()
        local list = {}
        for _, point in ipairs(xDTaraZ.Map.Tagged("HookPoint")) do list[#list + 1] = point.Parent end
        return list
    end, Label = function() return "Hook" end },
    { Option = "EspGates", Glow = true, Color = Color3.fromRGB(90, 220, 120), Find = function() return xDTaraZ.Map.Models("Gate") end, Label = function() return "Exit Gate" end },
    { Option = "EspPallets", Color = Color3.fromRGB(200, 150, 90), Find = function()
        local list = {}
        for _, point in ipairs(xDTaraZ.Map.Tagged("PalletPoint")) do list[#list + 1] = point.Parent end
        return list
    end, Label = function() return "Pallet" end },
    { Option = "EspWindows", Color = Color3.fromRGB(110, 170, 255), Find = function()
        local list = {}
        for _, point in ipairs(xDTaraZ.Map.Tagged("VaultPoint")) do
            local model = point.Parent
            if model and model.Name == "Window" and not table.find(list, model) then list[#list + 1] = model end
        end
        return list
    end, Label = function() return "Window" end },
}

function xDTaraZ.Esp.Holder()
    local folder = xDTaraZ.Esp.Folder
    if folder and folder.Parent then return folder end
    folder = Instance.new("Folder")
    folder.Name = "NovaObjectEsp"
    Util.Mount(folder)
    xDTaraZ.Esp.Folder = folder
    return folder
end

function xDTaraZ.Esp.Make(model, kind)
    local holder = xDTaraZ.Esp.Holder()
    local light
    if kind.Glow then
        light = Instance.new("Highlight")
        light.Adornee = model
        light.FillColor = kind.Color
        light.FillTransparency = 0.75
        light.OutlineColor = kind.Color
        light.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        light.Parent = holder
    end

    local board = Instance.new("BillboardGui")
    board.Adornee = model:IsA("Model") and (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)) or model
    board.Size = UDim2.fromOffset(120, 22)
    board.StudsOffset = vector3New(0, 3, 0)
    board.AlwaysOnTop = true
    board.Parent = holder

    local text = Instance.new("TextLabel")
    text.BackgroundTransparency = 1
    text.Size = UDim2.fromScale(1, 1)
    text.Font = Enum.Font.GothamBold
    text.TextSize = 13
    text.TextColor3 = kind.Color
    text.TextStrokeTransparency = 0.3
    text.Parent = board
    return { Light = light, Board = board, Text = text }
end

function xDTaraZ.Esp.Drop(model)
    local mark = xDTaraZ.Esp.Marks[model]
    if not mark then return end
    if mark.Light then mark.Light:Destroy() end
    mark.Board:Destroy()
    xDTaraZ.Esp.Marks[model] = nil
end

function xDTaraZ.Esp.Step()
    local map = xDTaraZ.Map.Root()
    local seen = {}
    local hrp = xDTaraZ.Player.Root
    if map then
        for _, kind in ipairs(xDTaraZ.Esp.Kinds) do
            if not xDTaraZ.Options[kind.Option] then continue end
            for _, model in ipairs(kind.Find()) do
                seen[model] = true
                local mark = xDTaraZ.Esp.Marks[model] or xDTaraZ.Esp.Make(model, kind)
                xDTaraZ.Esp.Marks[model] = mark
                local label = kind.Label(model)
                local part = mark.Board.Adornee
                if hrp and part then label ..= (" · %dm"):format((part.Position - hrp.Position).Magnitude) end
                mark.Text.Text = label
            end
        end
    end
    for model in pairs(xDTaraZ.Esp.Marks) do
        if not seen[model] or not model.Parent then xDTaraZ.Esp.Drop(model) end
    end
end

function xDTaraZ.Esp.Clear()
    for model in pairs(xDTaraZ.Esp.Marks) do xDTaraZ.Esp.Drop(model) end
    if xDTaraZ.Esp.Folder then xDTaraZ.Esp.Folder:Destroy() end
    xDTaraZ.Esp.Folder = nil
end

function xDTaraZ.Esp.GetStatus()
    local visuals = xDTaraZ.Library and xDTaraZ.Library.Visuals
    local players = visuals and visuals:Get("Enabled") and (xDTaraZ.Esp.Count .. " players") or "players off"
    local objects = 0
    for _ in pairs(xDTaraZ.Esp.Marks) do objects += 1 end
    return players .. " · " .. objects .. " objects"
end

xDTaraZ.Shop = { Status = "Off", Maxed = {}, Owned = {}, LevelCost = {}, Bought = 0, Leveled = 0, Busy = false, LastWallet = nil }

function xDTaraZ.Shop.Remote(name)
    return GameLib.FindRemote("Shop", name)
end

---@return string[]  folder names under ReplicatedStorage.<folder>, dev entries skipped
function xDTaraZ.Shop.Names(folder)
    local list = {}
    local root = ReplicatedStorage:FindFirstChild(folder)
    for _, child in ipairs(root and root:GetChildren() or {}) do
        if not child.Name:find("^!") then list[#list + 1] = child.Name end
    end
    table.sort(list)
    return list
end

function xDTaraZ.Shop.Wallet()
    return tonumber(LocalPlayer:GetAttribute("Screws")) or 0, tonumber(LocalPlayer:GetAttribute("Gears")) or 0
end

---@return table?  { owned, level, price } from the server
function xDTaraZ.Shop.Info(getter, name)
    local remote = xDTaraZ.Shop.Remote(getter)
    if not remote then return nil end
    local ok, info = pcall(remote.InvokeServer, remote, name)
    return ok and type(info) == "table" and info or nil
end

---@return any  whatever fn returns, nil while another shop run is active
function xDTaraZ.Shop.Locked(fn, ...)
    if xDTaraZ.Shop.Busy then return 0 end
    xDTaraZ.Shop.Busy = true
    local ok, got = pcall(fn, ...)
    xDTaraZ.Shop.Busy = false
    if not ok then
        warn("[ViolenceDistrict] shop: " .. tostring(got))
        return 0
    end
    return got
end

function xDTaraZ.Shop.BuyPerks()
    local buy = xDTaraZ.Shop.Remote("PurchasePerk")
    if not buy then return 0 end
    local count = 0
    local _, gears = xDTaraZ.Shop.Wallet()
    for _, name in ipairs(xDTaraZ.Shop.Names("Perks")) do
        if not xDTaraZ.State.Alive then break end
        if xDTaraZ.Shop.Owned[name] then continue end
        local info = xDTaraZ.Shop.Info("GetPerkInfo", name)
        if info and info.owned then xDTaraZ.Shop.Owned[name] = true end
        if not info or info.owned or gears < (info.price or mathHuge) then continue end
        buy:FireServer(name)
        gears -= info.price
        count += 1
        task.wait(xDTaraZ.Config.ShopDelay)
    end
    xDTaraZ.Shop.Bought += count
    return count
end

function xDTaraZ.Shop.LevelPerks()
    local level = xDTaraZ.Shop.Remote("LevelUpPerk")
    if not level then return 0 end
    local count = 0
    for _, name in ipairs(xDTaraZ.Shop.Names("Perks")) do
        if xDTaraZ.Shop.Maxed[name] then continue end
        local screws = xDTaraZ.Shop.Wallet()
        local before = xDTaraZ.Shop.Info("GetPerkInfo", name)
        if not before or not before.owned then continue end
        if not xDTaraZ.State.Alive then break end
        local cost = xDTaraZ.Shop.LevelCost[name] or xDTaraZ.Shop.MaxCost()
        if screws - cost < xDTaraZ.Options.KeepScrews then continue end
        level:FireServer(name)
        task.wait(xDTaraZ.Config.ShopDelay)
        local after = xDTaraZ.Shop.Info("GetPerkInfo", name)
        local spent = screws - xDTaraZ.Shop.Wallet()
        if after and after.level ~= before.level then
            xDTaraZ.Shop.LevelCost[name] = math.max(spent, cost or 0)
            count += 1
        elseif spent == 0 and cost and screws > cost * 2 then
            xDTaraZ.Shop.Maxed[name] = true
        end
    end
    xDTaraZ.Shop.Leveled += count
    return count
end

---@param kind string  "Item" or "Killer"
function xDTaraZ.Shop.BuyList(kind, names)
    local buy = xDTaraZ.Shop.Remote("Purchase" .. kind)
    if not buy then return 0 end
    local count = 0
    for key, picked in pairs(names or {}) do
        local name = type(key) == "number" and picked or key
        if not picked or type(name) ~= "string" then continue end
        local owned
        if kind == "Killer" then
            local check = xDTaraZ.Shop.Remote("CheckKillerOwnership")
            local ok, got = pcall(function() return check and check:InvokeServer(name) end)
            owned = ok and got == true
        else
            local info = xDTaraZ.Shop.Info("GetItemInfo", name)
            owned = info and info.owned
        end
        local price = kind == "Killer" and xDTaraZ.Shop.KillerPrice(name) or (xDTaraZ.Shop.Info("GetItemInfo", name) or {}).price
        if owned or not price or xDTaraZ.Shop.Wallet() - price < xDTaraZ.Options.KeepScrews then continue end
        buy:FireServer(name)
        count += 1
        task.wait(xDTaraZ.Config.ShopDelay)
    end
    return count
end

---@return number  highest level-up cost seen so far, a safe guess for unknown perks
function xDTaraZ.Shop.MaxCost()
    local most = xDTaraZ.Config.FirstLevelCost
    for _, cost in pairs(xDTaraZ.Shop.LevelCost) do most = math.max(most, cost) end
    return most
end

function xDTaraZ.Shop.KillerPrice(name)
    local remote = xDTaraZ.Shop.Remote("GetKillerPrice")
    local ok, price = pcall(function() return remote and remote:InvokeServer(name) end)
    return ok and tonumber(price) or nil
end

function xDTaraZ.Shop.Step()
    local opts = xDTaraZ.Options
    if not (opts.AutoBuyPerks or opts.AutoLevelPerks) then
        xDTaraZ.Shop.Status = "Off"
        xDTaraZ.Shop.LastWallet = nil
        return
    end
    local wallet = table.concat({ xDTaraZ.Shop.Wallet() }, "/")
    if wallet == xDTaraZ.Shop.LastWallet then return end
    xDTaraZ.Shop.LastWallet = wallet
    if opts.AutoBuyPerks then xDTaraZ.Shop.Locked(xDTaraZ.Shop.BuyPerks) end
    if opts.AutoLevelPerks then xDTaraZ.Shop.Locked(xDTaraZ.Shop.LevelPerks) end
    local screws, gears = xDTaraZ.Shop.Wallet()
    xDTaraZ.Shop.Status = ("bought %d · leveled %d · %d screws · %d gears"):format(xDTaraZ.Shop.Bought, xDTaraZ.Shop.Leveled, screws, gears)
end

xDTaraZ.UI = { Labels = {}, FarmSaved = nil }
local Library, T

function xDTaraZ.UI.Detach(fn)
    return function(...)
        local packed = table.pack(...)
        task.defer(function()
            local ok, err = pcall(fn, table.unpack(packed, 1, packed.n))
            if not ok then warn("[ViolenceDistrict] ui: " .. tostring(err)) end
        end)
    end
end

---@return table  list read from the game, empty when reading failed
function xDTaraZ.UI.List(read, ...)
    local ok, list = pcall(read, ...)
    return ok and type(list) == "table" and list or {}
end

---@param allow    fun(value: any): boolean
---@param refusal  table  { title, message, value the widget snaps back to }
function xDTaraZ.UI.Guard(widget, allow, refusal)
    local function Refuse()
        Library:Notify(refusal[1], refusal[2], 4, "Warning")
        task.defer(widget.SetValue, widget, refusal[3])
    end

    if type(widget.AddGuard) == "function" then
        widget:AddGuard(function(value)
            if allow(value) then return true end
            Refuse()
            return false
        end)
        return widget
    end

    widget:OnChanged(function(value)
        if not allow(value) then Refuse() end
    end)
    return widget
end

---@param cap string|string[]  needed before the toggle may turn on
function xDTaraZ.UI.NeedCap(idx, cap)
    if Library.Compat then
        Library.Compat.NeedCap(idx, cap)
        return
    end
    local toggle = Library.Toggles[idx]
    if not toggle then return end
    local title = toggle.Info and toggle.Info.Text or "Nova Hub"
    xDTaraZ.UI.Guard(toggle, function(value)
        return value ~= true or Util.Can(cap)
    end, { title, T("Not supported on this executor", "ใช้กับ executor นี้ไม่ได้"), false })
end

---@param role table  RoleMode widget, kept on "Any" when the executor cannot press the game's button
function xDTaraZ.UI.GuardRole(role)
    return xDTaraZ.UI.Guard(role, function(value)
        return value == "Any" or xDTaraZ.Role.Supported()
    end, { "Nova Hub", T("Role choice is not supported on this executor", "เลือกบทบาทใช้กับ executor นี้ไม่ได้"), "Any" })
end

---@param widget table  option whose value mirrors an Options key
function xDTaraZ.UI.Bind(widget, key)
    xDTaraZ.Options[key] = widget.Value
    widget:OnChanged(function(value) xDTaraZ.Options[key] = value end)
    return widget
end

function xDTaraZ.UI.BuildMain(window)
    window:AddTabSection(T("Main", "หลัก"))
    local tab = window:AddTab(T("Main", "หลัก"), "mushroom", T("Status and links", "สถานะและลิงก์"))

    local farm = tab:AddLeftGroupbox(T("Auto Farm", "ฟาร์มอัตโนมัติ"), "star")
    farm:AddToggle("AutoFarm", { Text = T("Auto Farm", "ฟาร์มอัตโนมัติ"), Description = T("Plays both roles for you: repairs, escapes, hunts and hooks", "เล่นให้ทั้งสองฝั่ง ซ่อม หนี ล่า แขวน"), Risky = true, Callback = xDTaraZ.UI.Detach(xDTaraZ.UI.SetFarm) }):AddKeyPicker("AutoFarmKey", { Default = "None", Mode = "Toggle" })
    xDTaraZ.UI.GuardRole(farm:AddDropdown("RoleMode", { Text = T("Role", "บทบาท"), Description = T("Survivor only never gets killer; Prefer killer keeps you in the killer pool", "Survivor only ไม่ถูกสุ่มเป็นฆาตกร / Prefer killer อยู่ในกลุ่มสุ่มฆาตกรเสมอ"), Values = { "Any", "Survivor only", "Prefer killer" }, Default = "Any" }))
    farm:AddSlider("FarmEscapeAfter", { Text = T("Survivor: escape after", "ผู้รอด: หนีหลัง"), Description = T("0 = never escape, stay and farm the whole round", "0 = ไม่หนี อยู่ฟาร์มจนจบรอบ"), Min = 0, Max = 900, Default = 0, Suffix = "s" })

    local status = tab:AddLeftGroupbox(T("Round", "รอบนี้"), "star")
    local labels = xDTaraZ.UI.Labels
    labels.Role = status:AddParagraph({ Title = T("Role", "บทบาท"), Content = "-" })
    labels.Survivor = status:AddParagraph({ Title = T("Survivor", "ผู้รอดชีวิต"), Content = "-" })
    labels.Killer = status:AddParagraph({ Title = T("Killer", "ฆาตกร"), Content = "-" })

    local discord = tab:AddRightGroupbox(T("Discord", "ดิสคอร์ด"), "link")
    discord:AddLabel(xDTaraZ.Config.Discord)
    discord:AddButton({ Text = T("Copy Discord Link", "คัดลอกลิงก์ดิสคอร์ด"), Func = xDTaraZ.UI.Detach(function()
        if Util.Copy(xDTaraZ.Config.Discord) then
            Library:Notify(T("Discord", "ดิสคอร์ด"), T("Link copied", "คัดลอกลิงก์แล้ว"), 3, "Success")
        else
            Library:Notify(T("Discord", "ดิสคอร์ด"), xDTaraZ.Config.Discord, 6, "Info")
        end
    end) })

    local logBox = tab:AddRightGroupbox(T("Update Log", "อัปเดตล่าสุด"), "bell")
    for i = 1, math.min(2, #xDTaraZ.Config.UpdateLog) do
        local entry = xDTaraZ.Config.UpdateLog[i]
        logBox:AddParagraph({ Title = entry[1], Content = entry[2] })
    end

    local panic = tab:AddRightGroupbox(T("Quick", "ด่วน"), "bomb")
    panic:AddButton({ Text = T("Panic — all off", "ฉุกเฉิน ปิดทั้งหมด"), Style = "Danger", Func = xDTaraZ.UI.Detach(function()
        xDTaraZ.UI.FarmSaved = nil
        for _, toggle in pairs(Library.Toggles) do
            if toggle.Value == true then toggle:SetValue(false) end
        end
    end) })

    local activity = tab:AddRightGroupbox(T("Activity", "กิจกรรม"), "eye")
    labels.Esp = activity:AddParagraph({ Title = T("ESP", "ESP"), Content = "-" })
    labels.Shop = activity:AddParagraph({ Title = T("Shop", "ร้านค้า"), Content = "-" })
end

xDTaraZ.UI.FarmKeys = {
    "AutoRepair", "PerfectSkillCheck", "AutoHeal", "AutoUnhook", "AutoDodge", "AutoSelfUnhook", "InstantEscape", "NoSlow",
    "KillAura", "AutoHook", "AutoBreakGens", "AntiStun", "AntiAfk",
}

function xDTaraZ.UI.SetFarm(on)
    local options = Library.Options
    local tuned = { EscapeDelay = options.FarmEscapeAfter.Value, DodgeRadius = xDTaraZ.Config.FarmDodge }
    if on then
        if xDTaraZ.UI.FarmSaved then return end
        xDTaraZ.UI.FarmSaved = {}
        for key in pairs(tuned) do xDTaraZ.UI.FarmSaved[key] = options[key].Value end
        for _, key in ipairs(xDTaraZ.UI.FarmKeys) do xDTaraZ.UI.FarmSaved[key] = options[key].Value end
        for key, value in pairs(tuned) do options[key]:SetValue(value) end
        for _, key in ipairs(xDTaraZ.UI.FarmKeys) do options[key]:SetValue(true) end
        if options.FarmEscapeAfter.Value <= 0 then options.InstantEscape:SetValue(false) end
        return
    end
    local saved = xDTaraZ.UI.FarmSaved
    xDTaraZ.UI.FarmSaved = nil
    if not saved then return end
    for key, value in pairs(saved) do
        if options[key] then options[key]:SetValue(value) end
    end
end

function xDTaraZ.UI.BuildSurvivor(window)
    window:AddTabSection(T("Roles", "บทบาท"))
    local tab = window:AddTab(T("Survivor", "ผู้รอดชีวิต"), "heart", T("Generators, team and escape", "เครื่องปั่นไฟ ทีม และการหนี"))

    local work = tab:AddLeftGroupbox(T("Objectives", "ภารกิจ"), "gear")
    work:AddToggle("AutoRepair", { Text = T("Auto repair", "ซ่อมอัตโนมัติ"), Description = T("Repairs the best generator hands-free", "ซ่อมเครื่องที่ดีที่สุดให้เอง"), Risky = true })
    work:AddToggle("PerfectSkillCheck", { Text = T("Auto Skill Check", "สกิลเช็คอัตโนมัติ") })
    work:AddToggle("AutoHeal", { Text = T("Auto heal teammates", "รักษาเพื่อนอัตโนมัติ"), Risky = true })
    work:AddToggle("AutoUnhook", { Text = T("Auto unhook teammates", "ปลดเพื่อนจากตะขอ"), Risky = true })

    local escape = tab:AddLeftGroupbox(T("Escape", "หนี"), "flag")
    escape:AddToggle("InstantEscape", { Text = T("Instant escape", "หนีออกทันที"), Description = T("Leaves the round without repairing anything", "ออกจากรอบโดยไม่ต้องซ่อม"), Risky = true })
    escape:AddSlider("EscapeDelay", { Text = T("Escape after", "หนีหลังเริ่มรอบ"), Min = 0, Max = 900, Default = 0, Suffix = "s" })
    escape:AddButton({ Text = T("Escape Now", "หนีออกตอนนี้"), Style = "Warning", Func = xDTaraZ.UI.Detach(function()
        if not xDTaraZ.Survivor.EscapeNow() then
            Library:Notify(T("Escape", "หนี"), T("No exit found this round", "ไม่พบทางออกในรอบนี้"), 3, "Warning")
        end
    end) })

    local safety = tab:AddRightGroupbox(T("Safety", "ความปลอดภัย"), "boo")
    safety:AddToggle("AutoDodge", { Text = T("Auto dodge killer", "หลบฆาตกรอัตโนมัติ"), Description = T("Teleports away when the killer gets close and keeps other jobs away from him", "วาร์ปหนีเมื่อฆาตกรเข้าใกล้ และไม่ไปทำงานใกล้ฆาตกร"), Risky = true })
    safety:AddSlider("DodgeRadius", { Text = T("Dodge distance", "ระยะหลบ"), Min = 6, Max = 40, Default = 20, Suffix = "m" })
    safety:AddToggle("AutoSelfUnhook", { Text = T("Auto self-unhook", "ปลดตัวเองจากตะขอ"), Risky = true })
    safety:AddToggle("AutoParry", { Text = T("Auto parry (beta)", "ปัดป้องอัตโนมัติ (beta)"), Description = T("Needs the Parrying Dagger equipped", "ต้องใส่ Parrying Dagger") })
    safety:AddToggle("NoParryCooldown", { Text = T("No parry cooldown (beta)", "ปัดป้องไม่มีคูลดาวน์ (beta)") })
    xDTaraZ.UI.NeedCap("NoParryCooldown", "Gc")
    safety:AddToggle("KillerAlert", { Text = T("Killer alert", "เตือนฆาตกรเข้าใกล้") })
    safety:AddButton({ Text = T("Sacrifice Self", "สละชีพตัวเอง"), Style = "Danger", Func = xDTaraZ.UI.Detach(function()
        if not xDTaraZ.Survivor.Sacrifice() then
            Library:Notify(T("Sacrifice", "สละชีพ"), T("Only works as a survivor", "ใช้ได้ตอนเป็นผู้รอดเท่านั้น"), 3, "Warning")
        end
    end) })
end

function xDTaraZ.UI.BuildKiller(window)
    local tab = window:AddTab(T("Killer", "ฆาตกร"), "swords", T("Hunting and hooking", "ล่าและแขวน"))

    local hunt = tab:AddLeftGroupbox(T("Hunt", "ล่า"), "target")
    hunt:AddToggle("KillAura", { Text = T("Auto slash", "ฟันอัตโนมัติ"), Description = T("Rage jumps behind anyone in range, Legit only swings at whoever is in front of you", "Rage วาร์ปไปฟันทุกคนในระยะ / Legit ฟันเฉพาะคนตรงหน้า"), Risky = true }):AddKeyPicker("KillAuraKey", { Default = "None", Mode = "Toggle" })
    hunt:AddToggle("SmartHitbox", { Text = T("Reach Assist", "ช่วยเพิ่มระยะฟัน"), Description = T("Legit swings still land on targets a few studs out of reach", "โหมด Legit ฟันโดนแม้เป้าอยู่เกินระยะนิดหน่อย"), Risky = true })
    hunt:AddDropdown("SlashMode", { Text = T("Slash mode", "โหมดฟัน"), Values = { "Rage", "Legit" }, Default = "Rage" })
    hunt:AddSlider("AuraRange", { Text = T("Range", "ระยะ"), Min = 10, Max = 500, Default = 500, Suffix = "m" })

    local chores = tab:AddRightGroupbox(T("Hooks & Generators", "ตะขอและเครื่องปั่นไฟ"), "gear")
    chores:AddToggle("AutoHook", { Text = T("Auto carry + hook", "แบกและแขวนอัตโนมัติ"), Description = T("Picks up anyone downed and hooks them", "แบกคนล้มแล้วแขวนตะขอให้"), Risky = true })
    chores:AddToggle("AutoBreakGens", { Text = T("Auto kick generators", "เตะเครื่องปั่นไฟอัตโนมัติ"), Description = T("Kicks the most repaired generator when nobody is in range", "เตะเครื่องที่ซ่อมไปเยอะสุดตอนไม่มีเป้า"), Risky = true })

    local defense = tab:AddRightGroupbox(T("Defense", "ป้องกัน"), "shield")
    defense:AddToggle("AntiStun", { Text = T("Anti pallet stun (beta)", "กันพาเลทสตัน (beta)") })
    xDTaraZ.UI.NeedCap("AntiStun", "Connections")
    defense:AddToggle("AntiBlind", { Text = T("Anti blind (beta)", "กันแสงไฟฉาย (beta)"), Description = T("Flashlights no longer blind you", "ไม่โดนไฟฉายแยงตา") })
    xDTaraZ.UI.NeedCap("AntiBlind", "Connections")
    defense:AddToggle("FreeTurn", { Text = T("No turn limit", "หมุนตัวได้อิสระ"), Description = T("Keep turning while attacking or lunging", "หันตัวได้ตอนฟันและพุ่ง") })
end

function xDTaraZ.UI.BuildPlayer(window)
    window:AddTabSection(T("Player", "ผู้เล่น"))
    local tab = window:AddTab(T("Player", "ผู้เล่น"), "player", T("Movement, world and teleport", "การเคลื่อนที่ โลก และวาร์ป"))

    local move = tab:AddLeftGroupbox(T("Movement", "การเคลื่อนที่"), "zap")
    move:AddToggle("Speed", { Text = T("Speed", "วิ่งเร็ว"), Risky = true }):AddKeyPicker("SpeedKey", { Default = "None", Mode = "Toggle" })
    move:AddSlider("SpeedValue", { Text = T("Walk speed", "ความเร็ว"), Min = 16, Max = 60, Default = 24 })
    move:AddToggle("NoSlow", { Text = T("No slow", "ไม่โดนสโลว์"), Description = T("Never drops below your normal run speed", "ความเร็วไม่ต่ำกว่าวิ่งปกติ") })
    move:AddToggle("NoFall", { Text = T("No fall (beta)", "ไม่เซตอนตก (beta)"), Description = T("No landing stumble after a drop", "ลงพื้นแล้วไม่เซ") })
    xDTaraZ.UI.NeedCap("NoFall", "Namecall")
    move:AddToggle("Noclip", { Text = T("Noclip", "เดินทะลุ") }):AddKeyPicker("NoclipKey", { Default = "None", Mode = "Toggle" })
    move:AddToggle("InfiniteJump", { Text = T("Infinite jump", "กระโดดไม่จำกัด"), Description = T("Jump anywhere, even mid-air", "กระโดดได้ทุกที่ แม้กลางอากาศ") })

    local world = tab:AddRightGroupbox(T("World", "โลก"), "star")
    world:AddToggle("Fullbright", { Text = T("Fullbright", "สว่างทั้งแมพ") })
    world:AddToggle("AntiShake", { Text = T("Anti camera shake", "กันจอสั่น") })
    xDTaraZ.UI.NeedCap("AntiShake", "Connections")
    world:AddToggle("NoFog", { Text = T("No fog", "ไม่มีหมอก") })
    world:AddToggle("AntiAfk", { Text = T("Anti AFK", "กันหลุด AFK"), Callback = xDTaraZ.UI.Detach(xDTaraZ.Player.AntiAfk.Arm) })

    xDTaraZ.UI.BuildTeleport(tab)
end

function xDTaraZ.UI.BuildShop(window)
    local tab = window:AddTab(T("Shop", "ร้านค้า"), "shop", T("Perks, items and killers", "เพิร์ค ไอเทม ฆาตกร"))

    local perks = tab:AddLeftGroupbox(T("Perks", "เพิร์ค"), "star")
    perks:AddToggle("AutoBuyPerks", { Text = T("Auto buy perks", "ซื้อเพิร์คอัตโนมัติ"), Description = T("Unlocks every perk you can afford with Gears", "ปลดล็อกเพิร์คทุกตัวที่ Gears พอ") })
    perks:AddToggle("AutoLevelPerks", { Text = T("Auto level perks", "อัปเลเวลเพิร์คอัตโนมัติ"), Description = T("Spends Screws to level owned perks", "ใช้ Screws อัปเลเวลเพิร์คที่มี") })
    perks:AddSlider("KeepScrews", { Text = T("Keep Screws", "เก็บ Screws ไว้"), Description = T("Never spends below this", "ไม่ใช้ต่ำกว่าจำนวนนี้"), Min = 0, Max = 20000, Default = 0 })
    perks:AddButton({ Text = T("Buy + Level Now", "ซื้อ + อัปตอนนี้"), Style = "Primary", Func = xDTaraZ.UI.Detach(function()
        local bought, leveled = xDTaraZ.Shop.Locked(xDTaraZ.Shop.BuyPerks), xDTaraZ.Shop.Locked(xDTaraZ.Shop.LevelPerks)
        Library:Notify(T("Perks", "เพิร์ค"), ("Bought %d, leveled %d"):format(bought, leveled), 4, "Success")
    end) })

    local store = tab:AddRightGroupbox(T("Items & Killers", "ไอเทมและฆาตกร"), "coin")
    local items = store:AddDropdown("ShopItems", { Text = T("Items", "ไอเทม"), Values = xDTaraZ.UI.List(xDTaraZ.Shop.Names, "Items"), Multi = true, Default = {}, AllowNull = true, Searchable = true })
    store:AddButton({ Text = T("Buy Selected Items", "ซื้อไอเทมที่เลือก"), Func = xDTaraZ.UI.Detach(function()
        Library:Notify(T("Shop", "ร้านค้า"), ("Bought %d items"):format(xDTaraZ.Shop.Locked(xDTaraZ.Shop.BuyList, "Item", items.Value)), 4, "Coin")
    end) })
    local killers = store:AddDropdown("ShopKillers", { Text = T("Killers", "ฆาตกร"), Values = xDTaraZ.UI.List(xDTaraZ.Shop.Names, "Killers"), Multi = true, Default = {}, AllowNull = true, Searchable = true })
    store:AddButton({ Text = T("Buy Selected Killers", "ซื้อฆาตกรที่เลือก"), Func = xDTaraZ.UI.Detach(function()
        Library:Notify(T("Shop", "ร้านค้า"), ("Bought %d killers"):format(xDTaraZ.Shop.Locked(xDTaraZ.Shop.BuyList, "Killer", killers.Value)), 4, "Coin")
    end) })
    store:AddButton({ Text = T("Refresh lists", "รีเฟรชรายการ"), Func = xDTaraZ.UI.Detach(function()
        items:SetValues(xDTaraZ.Shop.Names("Items"))
        killers:SetValues(xDTaraZ.Shop.Names("Killers"))
    end) })
end

---@param tab table  Player tab, the teleport group sits on its right side
function xDTaraZ.UI.BuildTeleport(tab)
    local box = tab:AddRightGroupbox(T("Teleport", "วาร์ป"), "pipe")
    local places = box:AddDropdown("TeleportTarget", { Text = T("Destination", "ปลายทาง"), Values = xDTaraZ.UI.List(xDTaraZ.Teleport.Places), Default = "Nearest Generator", Searchable = true })
    box:AddButton({ Text = T("Teleport Now", "วาร์ปตอนนี้"), Style = "Primary", Func = xDTaraZ.UI.Detach(function()
        if not xDTaraZ.Teleport.Go(places.Value) then
            Library:Notify(T("Teleport", "วาร์ป"), T("Destination not found this round", "ไม่พบปลายทางในรอบนี้"), 3, "Warning")
        end
    end) }):AddButton({ Text = T("Refresh", "รีเฟรช"), Func = xDTaraZ.UI.Detach(function()
        places:SetValues(xDTaraZ.Teleport.Places())
    end) })
end

function xDTaraZ.UI.BuildVisuals(window)
    window:AddTabSection(T("Visuals", "การมองเห็น"))
    local tab = window:AddVisualsTab({ Provider = xDTaraZ.Esp.Targets, Preview = true })
    local objects = tab:AddLeftGroupbox(T("Objects", "วัตถุ"), "eye")
    objects:AddToggle("EspGenerators", { Text = T("Generators + progress", "เครื่องปั่นไฟ + ความคืบหน้า") })
    objects:AddToggle("EspHooks", { Text = T("Hooks", "ตะขอ") })
    objects:AddToggle("EspGates", { Text = T("Exit gates", "ประตูทางออก") })
    objects:AddToggle("EspPallets", { Text = T("Pallets", "พาเลท") })
    objects:AddToggle("EspWindows", { Text = T("Windows", "หน้าต่าง") })
end

function xDTaraZ.UI.RefreshStatus()
    local labels = xDTaraZ.UI.Labels
    if not (labels.Role and labels.Survivor and labels.Killer and labels.Esp and labels.Shop) then return end
    local dist = xDTaraZ.Alert.Distance
    labels.Role:SetContent((xDTaraZ.Player.Role() or "-") .. " · gens left " .. xDTaraZ.Map.GensLeft() .. (dist and (" · killer %dm"):format(dist) or ""))
    labels.Survivor:SetContent(("%s · checks %d · dodges %d · escapes %d"):format(xDTaraZ.Survivor.Status, xDTaraZ.SkillCheck.Checks, xDTaraZ.Guard.Dodges, xDTaraZ.Survivor.Escapes))
    labels.Killer:SetContent(xDTaraZ.Killer.Status .. " · stuns dodged " .. xDTaraZ.AntiStun.Count)
    labels.Esp:SetContent(xDTaraZ.Esp.GetStatus())
    labels.Shop:SetContent(xDTaraZ.Shop.Status)
end

---Flips the menu toggles of jobs the scheduler halted and says why; runs on the library's own clean thread.
function xDTaraZ.UI.DrainHalts()
    local halts = xDTaraZ.Scheduler.Halts
    if not halts[1] then return end
    xDTaraZ.Scheduler.Halts = {}
    for _, halt in ipairs(halts) do
        Util.Try("halt", function()
            for _, idx in ipairs(halt.Toggles) do
                local toggle = Library.Toggles[idx]
                if toggle and toggle.Value then toggle:SetValue(false) end
            end
            Library:Notify("Violence District", halt.Message, 6, "Warning")
        end)
    end
end

function xDTaraZ.UI.Pump()
    xDTaraZ.UI.DrainHalts()
    xDTaraZ.UI.RefreshStatus()
end

function xDTaraZ.UI.Build()
    local window = Library.Window
    for _, section in ipairs({ "BuildMain", "BuildSurvivor", "BuildKiller", "BuildPlayer", "BuildShop", "BuildVisuals" }) do
        Util.Try("ui " .. section, xDTaraZ.UI[section], window)
    end
    window:AddTabSection(T("Other", "อื่นๆ"))
    Util.Try("ui settings", window.AddSettingsTab, window)

    for key in pairs(xDTaraZ.Options) do
        local widget = Library.Options[key] or Library.Toggles[key]
        if widget then xDTaraZ.UI.Bind(widget, key) end
    end
    Util.Try("ui gate", xDTaraZ.UI.GateRemotes)
end

---Toggles whose game remote is gone refuse to turn on and say why, instead of erroring every tick.
function xDTaraZ.UI.GateRemotes()
    if not Library.Compat then return end
    local reason = T("Not found after a game update", "หาไม่เจอหลังเกมอัปเดต")
    for idx in pairs(GameLib.Needs) do
        local missing = GameLib.Missing(idx)
        if missing and Library.Toggles[idx] then
            Library.Compat.Block(idx, reason)
            warn("[ViolenceDistrict] " .. idx .. " off, missing remote " .. missing)
        end
    end
end

---@return boolean  false when the menu could not load
local function BuildInterface()
    Library = Util.LoadLibrary()
    if not Library then return false end
    pcall(NovaBanner.Step, "UI library")
    xDTaraZ.Library = Library
    T = function(en, th) return Library:T(en, th) end
    Library:CreateWindow({
        Title = "Nova Hub",
        SubTitle = "Violence District by xDTaraZ",
        MenuKey = Enum.KeyCode.LeftControl,
        ConfigFolder = xDTaraZ.Config.SaveFolder,
        Language = "Auto",
        Theme = "Nova",
        Intro = xDTaraZ.Config.Intro,
        OnUnlocked = function()
            xDTaraZ.UI.Build()
            task.defer(Util.Try, "boot", xDTaraZ.Boot)
            Library:Every(xDTaraZ.Config.StatusInterval, xDTaraZ.UI.Pump)
            task.defer(Util.Try, "autoload", Library.LoadAutoloadConfig, Library)
        end,
    })
    Library:OnUnload(function()
        xDTaraZ:Unload()
    end)
    return true
end

function xDTaraZ.Boot()
    xDTaraZ:Connect(LocalPlayer.CharacterAdded, function(character)
        xDTaraZ.Survivor.Job = nil
        xDTaraZ.Movement.Release()
        xDTaraZ.Player:Bind(character)
    end)

    xDTaraZ.Movement.Start()
    xDTaraZ.SkillCheck.Start()
    xDTaraZ.AntiStun.Start()

    xDTaraZ.Scheduler.Every("Survivor", xDTaraZ.Config.RepairTick, xDTaraZ.Survivor.Step, { "AutoRepair", "AutoHeal", "AutoUnhook", "InstantEscape" }, { Core = true, Restore = xDTaraZ.Survivor.Finish })
    xDTaraZ.Scheduler.Every("Guard", xDTaraZ.Config.GuardTick, xDTaraZ.Guard.Step, { "AutoDodge", "AutoSelfUnhook" })
    xDTaraZ.Scheduler.Every("Block", 1, xDTaraZ.Block.Step, { "PerfectSkillCheck", "AntiStun", "AntiBlind", "AntiShake", "NoFall" }, { Restore = xDTaraZ.Block.Release })
    xDTaraZ.Scheduler.Every("Parry", xDTaraZ.Config.GuardTick, xDTaraZ.Parry.Step, { "AutoParry", "NoParryCooldown" })
    xDTaraZ.Scheduler.Every("Killer", 0.1, xDTaraZ.Killer.Step, { "KillAura", "AutoHook", "AutoBreakGens" })
    xDTaraZ.Scheduler.Every("World", 0.5, xDTaraZ.World.Step, { "Fullbright", "NoFog" }, { Restore = xDTaraZ.World.Restore })
    xDTaraZ.Scheduler.Every("Role", 3, xDTaraZ.Role.Step)
    xDTaraZ.Scheduler.Every("Alert", 0.5, xDTaraZ.Alert.Step, { "KillerAlert" }, { Core = true })
    xDTaraZ.Scheduler.Every("Shop", xDTaraZ.Config.ShopInterval, xDTaraZ.Shop.Step, { "AutoBuyPerks", "AutoLevelPerks" })
    xDTaraZ.Scheduler.Every("ObjectEsp", xDTaraZ.Config.ObjectEspRefresh, xDTaraZ.Esp.Step, { "EspGenerators", "EspHooks", "EspGates", "EspPallets", "EspWindows" }, { Core = true })
    xDTaraZ.Scheduler.Boot()
end

function xDTaraZ:Unload()
    self.State.Alive = false
    if environment.ViolenceDistrictUnload == self.UnloadFn then environment.ViolenceDistrictUnload = nil end
    table.clear(xDTaraZ.Scheduler.Jobs)
    xDTaraZ.Survivor.Finish()
    xDTaraZ.Block.Release()
    xDTaraZ.Movement.Release()
    xDTaraZ.World.Restore()
    xDTaraZ.Esp.Clear()
    for _, connection in ipairs(self.State.Connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(self.State.Connections)
end

xDTaraZ.UnloadFn = function()
    if xDTaraZ.Library and not xDTaraZ.Library.Unloaded then
        xDTaraZ.Library:Unload()
    else
        xDTaraZ:Unload()
    end
end
environment.ViolenceDistrictUnload = xDTaraZ.UnloadFn

if LocalPlayer.Character then
    xDTaraZ.Player:Bind(LocalPlayer.Character)
end

pcall(NovaBanner.Step, "Systems")
if BuildInterface() then
    pcall(NovaBanner.Step, "Interface")
    pcall(NovaBanner.Ready)
end]==]

NOVA_HUB_MODULES[10708913337] = [==[if not game:IsLoaded() then
    game.Loaded:Wait()
end

if not LPH_OBFUSCATED then
    local function Passthrough(fn) return fn end
    LPH_JIT, LPH_JIT_MAX, LPH_NO_VIRTUALIZE = Passthrough, Passthrough, Passthrough
end

local environment = getgenv and getgenv() or _G
if type(environment.AnimeDiceUnload) == "function" then
    pcall(environment.AnimeDiceUnload)
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local GuiService = game:GetService("GuiService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local osClock = os.clock

if game.GameId ~= 10708913337 then
    LocalPlayer:Kick("Nova Hub: this script is for Anime Dice only")
    return
end

local NovaBanner = {
    Print = print,
    Started = os.clock(),
    Last = os.clock(),
    Done = 0,
    Total = 4,
}

do
    local ok, renv = pcall(getrenv)
    if ok and type(renv) == "table" and type(renv.print) == "function" then NovaBanner.Print = renv.print end
end

function NovaBanner.Show()
    local ok, executor = pcall(identifyexecutor)
    if not ok or type(executor) ~= "string" then executor = "Unknown" end
    local rule = string.rep("=", 54)
    NovaBanner.Print(table.concat({
        "",
        [[
                                                                     @%@
                                                                    @*-#@
                                          @@@@@@@@@@@@@          @@#+.:-*%@@      @@
                                   @@@@@%##***********##%@@@@@   @*--:-==+*@@@@#*+==+*%@@
                              @@@@#+=+==---==++++++++++++**+++#@@@@@%==+@@@@#:.......:::=%@@
                          @@%#+---::-=++++++++++************+***++#%@%+@@@#:..-+*****+-:::+%@
                      @@@#=-::.:-==++++++++++*************************#@@+::=*-:.:+-::-+:.:=#@
                    @@%-:...:-===+++++**#################****************%%*+::::+*++::-+..:=#@
                 @@%*-:...:--==++*########**+==--===+**#######************+#%+::-*==-:::=-::=+@@
               @@%+=-::---===+*###%#+-:...................:=+#####***********#@+++==----==:-+*@@
             @@%++=-======+*###%+:............................::+####**********#@*+=----=---**@@
            @%=++=++++++*####=:...................................:+###**********%@==--==--+**@@
          @@*+++++++++*###*:........................................:-*##**********%*==+--=**@@@
         @%+++++++++*##%+:............................................::*##*********%%+--=##%@+%@
       @@#+++++++++###*:.....-+==+*#-......................:**+**#+:....:=###********%%+*##%@*:+@@
      @@*++++++++*###:......-+:.:-=*#*-..................:+*--+**#%*:.....:+##********#@#%%+:.:--+#@
     @@+++++++++*##+:......-*::-=++++*##:...............=#=-++****#%*:.....:-##********#@@@%+=-++#@@
    @@+=-=+++++*##+.......:*-:==++++++*##+............-*+-=+*******#%+:.....:-##********#@  @#=#@@
    @*=:.=++++*##-.......:*=:=++++++++*+*##=........:**==+**********##=:.....::*#********%@  @#@
   @#+-.-++*+*##=........*+-++++++*********##-....:+*==+*************#%-:.....:-**********%@
  @@++-=++***##+........*+-++++++***********#%*::=#+-+****************#%-:.....:=**********@@
 @@*++=++***###........+*-+++++***************###+-=+*****************###-:.....:+*********%@
 @%++=+*****#%:.......=*-++++*******************==+********************#%*-:....:-#********#@@
@@**+++****##+.......=*=+++*********************************************#%+::....:+*********@@
@%**++*****##-......=#=++**********#%#********************%%*************#%+:....:-#********%@
@%**++*****#*:.....-*=++**********#%%%#*****************#%%%**************#%=:....-********##@@
@#**++*****#*:....:*++************%%%%%%#*************#%%%%%#**************##-:...-+*******#*@@
@#**+******#+:...:#++************#%%%@@%%##*********#%%%%%@%#**************#%#-:..:+*+*****#*@@
@#**+******#+:..:#+=************#%%%%%*%%%##*******%%%%%%#%%##**************#%#::.-+*+*****#*@@
@#*********#+:.:+*=*************%%%%%+==*%%###***#%%%%%#++*%##***************#%*::-+*+*****#*@@
@%*#*******#*:.+*=*************%%%%%*=----*%###%%%%%%#+====*###**************##%+--*++****###@@
@%*#********#-:####***********#%%%%#=-::.::=###%%%%#+==--:::####************#%%%#==*+*****###@@
@@##********#+:#%%%%#********#%%%%%=--:....::=%%%%+==--::..:-%###********#%%%%%%#=#++*****##%@
@@###********#-=#%%%%%%##****%%%%%*=-:.......::-==---::.....:+###*****##%%%%%%%#++#++****###@@
 @%###*******##::=+%%%%%%%##%%%%%#=-:...........:::::........:####*#%%%%%%%%%*+=+*+=*****##%@
 @@###********#+:.:-=*%%%%%%%%%%%+--:.........................=###%%%%%%%%*+====*=.=****###@@
  @@###********#+:..::-=*%%%%%%%*=-:..:::-------------::::...::*#%%%%%%*+==---=*+-=+***###%@
   @%###*******#%#*+-..::-=#%@@%#**++==----------------===+++**#%@@@#+===---+*#*++****####@@
    @%###**#%#=::-=+##*##+-:...:::-=+**---*###*=--++++=--=++++=--:::-=+#%**#-:..:=#%##%##@@
    @@%#%#+:...:-=++=:..::=*####+#=:..=@#%:....%@*....*%%#...:--=*##+------=+=:::::-=#%%@@
     @@%*=--::::-*::::::-%=...:%@#:...:@@#.....%@+....=@@=.........:*#=-----=+=:::-==++%@@
  @@%+--+==--:::-#=-::::-%+....+%%-....%@#....:@@+....+@@:...:%%....-@*---==+*+:::-=+++*=+#@@
 @%-:-==*+==-:::-+*--:::-*#:...........*@#....:@@+....+@%..........-%%+---==+*=::-=+++#*=-:-*@@
 @@#+===+*+==-::-=*=--::-=%-......:....+@%:....:-....:#@*....=+:...-%#=--==+**-:--=++#*+=-=*%@
   @@#*=++#+=-:::-+*------#+....+@%....-@@#:.......::*@@+....+#=.:::=%+-===+#+-:-=++***++*%@@
     @@#+++*==-::-=*=-----+%:...-@@-::-=@%%@#+=--==*%@%%=:::::::::::#%+===+**----=++#**#%@@
     @@*-=+*+=-::-=*+=----=%#+*#%@%@@@@@#+-=*%%@@@%#*==*@@%%%##*+*#@@*====+#+-:-=++***++%@
    @@*--=+++===++*#*=------#%%#+=-----===============----==+*#%%%#+=-===+*#*+++=++**+==*@@
    @%=:-==+***%%@@@#=-=====++*##%%%@@@@@@@@@@%%@@@@@@@@@%%%##**++=======+*@@@@%#*+#+=--=#@
    @*:---==+*###%@@@#*#%%@%%%%%%######*****++++++++***######%%%%%%%%%%#*#%@@@####**+=---+@@
   @@+--=**#%@@@@@  @@@%%%%%%%#*******************************####%%%%%%@@@  @@@@@%#**=--+%@
    @@%%@@@@@          @@@@%%%%%%###**********************####%%%%%%%@@@          @@@@@%%%@@
      @@                  @@@@@%%%%%%%%%###############%%%%%%%%%@@@@@                  @@@
                               @@@@@@%%%%%%%%%%%%%%%%%%%%%%@@@@@
                                    @@@@@@@@@@@@@@@@@@@@@@@
]],
        [[
  __  __    _    ____  ___ ___    _   _ _   _ ____
 |  \/  |  / \  |  _ \|_ _/ _ \  | | | | | | | __ )
 | |\/| | / _ \ | |_) || | | | | | |_| | | | |  _ \
 | |  | |/ ___ \|  _ < | | |_| | |  _  | |_| | |_) |
 |_|  |_/_/   \_\_| \_\___\___/  |_| |_|\___/|____/
]],
        rule,
        "   ANIME DICE  //  by xDTaraZ  //  discord.gg/FHVfmeSceA",
        "   executor: " .. executor .. "   //   player: " .. game:GetService("Players").LocalPlayer.Name,
        rule,
    }, "\n"))
end

---@param label string  what just finished loading
function NovaBanner.Step(label)
    local now = os.clock()
    NovaBanner.Done = math.min(NovaBanner.Done + 1, NovaBanner.Total)
    local filled = math.floor(NovaBanner.Done / NovaBanner.Total * 20 + 0.5)
    NovaBanner.Print(string.format("[Nova Hub] [%s] %3d%%  %-24s +%dms",
        string.rep("#", filled) .. string.rep(".", 20 - filled),
        math.floor(NovaBanner.Done / NovaBanner.Total * 100), label, math.floor((now - NovaBanner.Last) * 1000)))
    NovaBanner.Last = now
end

function NovaBanner.Ready()
    local rule = string.rep("=", 54)
    NovaBanner.Print(table.concat({
        rule,
        string.format("   >> READY in %dms", math.floor((os.clock() - NovaBanner.Started) * 1000)),
        rule,
    }, "\n"))
end

pcall(NovaBanner.Show)
pcall(NovaBanner.Step, "Core")

local xDTaraZ = setmetatable({}, {
    __newindex = function(self, key, value)
        rawset(self, key, type(value) == "function" and LPH_JIT(value) or value)
    end,
})

xDTaraZ.Config = {
    UiSource = "NovaHub://embedded-ui",
    Discord = "https://discord.gg/FHVfmeSceA",
    UpdateLog = {
        { "2026-10-05", "Added Rebirth Stats: auto spend points on the stat you pick\nAdded Reset Stats with Reset Token\nAdded auto use of gamepass items" },
        { "2026-10-03", "Classic Nova Hub UI is back\nBetter executor support\nAuto Roll stops at full storage\nFixed Group Reward\nImproved Fast Roll" },
    },
    ReloadSource = 'loadstring(game:HttpGet("NovaHub://embedded-loader"))()',
    RejoinDelay = 5,
    RejoinRetry = 30,
    WebhookColor = 0xE8A04C,
    GroupId = 33017480,
    SaveFolder = "Anime Dice",
    LoadTimeout = 10,
    AlertTries = 20,
    AlertGap = 0.5,
    JobFailLimit = 5,
    JobFailWindow = 10,
    StatusInterval = 1,
    RollLead = 0.1,
    GradeDelay = 0.3,
    TraitDelay = 0.3,
    FuseDelay = 0.55,
    BuyDelay = 0.3,
    LevelDelay = 0.2,
    RedeemDelay = 0.6,
    ClaimDelay = 0.25,
    TowerTick = 0.25,
    TowerRetry = 0.5,
    TowerStartCooldown = 3.2,
    ItemDelay = 0.6,
    StatDelay = 0.12,
    RewardsInterval = 5,
    SnapshotTtl = 0.4,
    StorageHeadroom = 6,
    StorageRefill = 0.7,
    TowerDemoteFloor = 5,
    RollStats = { Luck = true, ["Roll Duration"] = true, Rolls = true },
    UtilitySeconds = { Default = 120, Walkspeed = 10, ["Sell Multiplier"] = 60, ["Unit Storage"] = 180, Luck = 600, ["Roll Duration"] = 600 },
    UtilityFallbackShare = 0.05,
    SwapMargin = 1.15,
    FuseGain = 1.25,
    FuseMoneyShare = 0.05,
    SwapsPerPass = 4,
    PlaceDelay = 0.55,
    TowerActionTime = {
        floorStarted = 0.76,
        damageEnemy = 0.62,
        damagePlayer = 0.62,
        memberDefeated = 0.32,
        floorCompleted = 0.24,
    },
}

xDTaraZ.State = {
    Alive = true,
    Connections = {},
    Halted = {},
    Notices = {},
}

xDTaraZ.Options = {
    AntiAfk = false,
    DisableCutscene = false,

    WalkSpeed = false,
    WalkSpeedValue = 32,
    InfiniteJump = false,
    NoClip = false,
    Fly = false,
    FlySpeed = 60,

    AutoRoll = false,
    RollInterval = 0.02,

    AutoCollect = false,
    CollectInterval = 1,
    EquipBestUnitsAuto = false,
    EquipInterval = 5,
    PlacementMode = "Potential",
    AutoLevelUp = false,
    LevelMinRarity = "Common",
    LevelTarget = 10,

    AutoBuyDice = false,
    AutoEquipBestDice = false,
    AutoBuyUpgrades = false,
    UpgradeFilter = {},

    AutoSell = false,
    SellRarities = {},
    SellKeepMutations = {},
    KeepPerRarity = 0,
    SellInterval = 2,
    AutoClearStorage = false,
    ClearKeepRarity = "Mythical",
    LevelPayback = 180,
    UpgradePayback = 1800,

    AutoRebirth = false,
    AutoRebirthStats = false,
    RebirthStat = "Money",

    AutoGrade = false,
    GradeTarget = "S",
    GradeOverwrite = false,
    AutoTrait = false,
    TraitTarget = "Samurai",
    TraitOverwrite = false,
    AutoFuse = false,
    FuseRarities = {},

    AutoTower = false,
    TowerName = "Dragon Tower",
    TowerStopFloor = 100,
    TowerReequip = false,
    TowerSmart = false,

    AutoGear = false,
    AutoPotion = false,
    PotionFilter = {},
    AutoSpin = false,
    AutoGamepass = false,
    AutoTicketShop = false,
    TicketShopItems = {},

    AutoDaily = false,
    AutoGroup = false,
    AutoOffline = false,
    AutoQuest = false,

    RareNotify = false,
    NotifyRarities = {},
    NotifyMutations = {},
    WebhookUrl = "",
    AutoLock = false,
    LockRarity = "Secret I",
    LockMutations = {},
    AutoRejoin = false,

    Kaitun = false,
}

xDTaraZ.Util = {}
local Util = xDTaraZ.Util

---@return function?  first argument that is callable
local function Resolve(...)
    for index = 1, select("#", ...) do
        local candidate = select(index, ...)
        if type(candidate) == "function" then
            return candidate
        end
    end
    return nil
end

Util.Request = Resolve(request, http_request, syn and syn.request, http and http.request)
Util.SetClipboard = Resolve(setclipboard, toclipboard)
Util.QueueTeleport = Resolve(queue_on_teleport, queueonteleport, syn and syn.queue_on_teleport)

---@return string?, string?  body, or nil and why every transport failed
function Util.HttpGet(url)
    if url == "NovaHub://embedded-ui" then return NOVA_HUB_UI_SOURCE end
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if ok and type(body) == "string" then
        return body
    end
    if not Util.Request then return nil, "no http function" end

    local sent, response = pcall(Util.Request, { Url = url, Method = "GET" })
    if not sent or type(response) ~= "table" then return nil, tostring(response) end
    if response.StatusCode ~= 200 or type(response.Body) ~= "string" then
        return nil, "HTTP " .. tostring(response.StatusCode)
    end
    return response.Body
end

---@param detail any?  extra context for the console only
function Util.Alert(text, detail)
    warn("[AnimeDice] " .. text, detail or "")
    task.spawn(function()
        local starterGui = game:GetService("StarterGui")
        for _ = 1, xDTaraZ.Config.AlertTries do
            if pcall(starterGui.SetCore, starterGui, "SendNotification", { Title = "Nova Hub", Text = text, Duration = 10 }) then return end
            task.wait(xDTaraZ.Config.AlertGap)
        end
    end)
end

function Util.Copy(text)
    if not Util.SetClipboard then return false end
    return (pcall(Util.SetClipboard, text))
end

---@return boolean  fn finished without error
function Util.Try(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then warn("[AnimeDice] " .. label .. ":", err) end
    return ok
end

---@return table?, string?  UI library, or nil and a message for the player
function Util.LoadLibrary(url)
    local source, why = Util.HttpGet(url)
    if not source or not source:sub(-64):find("return%s+Library%s*$") then
        warn("[AnimeDice] ui download:", why or "truncated or not the library")
        return nil, "Could not download the menu. Check your connection and run it again."
    end
    local chunk, compileErr = loadstring(source)
    if not chunk then
        return nil, "The menu failed to load on this executor: " .. tostring(compileErr)
    end
    local ok, lib = pcall(chunk)
    if not ok or type(lib) ~= "table" then
        return nil, "The menu failed to load on this executor: " .. tostring(lib)
    end
    return lib
end

function Util.FormatNumber(value)
    value = tonumber(value) or 0
    if value >= 1e6 then
        local suffixes = { "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
        local tier = math.clamp(math.floor(math.log(value, 1000)) - 1, 1, #suffixes)
        return string.format("%.2f%s", value / (1000 ^ (tier + 1)), suffixes[tier])
    end
    local text = tostring(math.floor(value))
    local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (formatted:gsub("^,", ""))
end

---@return string[]  sorted keys, stable dropdown order
function Util.SortedKeys(map)
    local keys = {}
    for key in pairs(map or {}) do
        keys[#keys + 1] = tostring(key)
    end
    table.sort(keys)
    return keys
end

function Util.SetFromList(list)
    local set = {}
    for key, value in pairs(list or {}) do
        if type(key) == "number" then
            set[value] = true
        elseif value then
            set[key] = true
        end
    end
    return set
end

function xDTaraZ:Connect(signal, handler)
    local connection = signal:Connect(handler)
    table.insert(self.State.Connections, connection)
    return connection
end

xDTaraZ.GameLib = {}
local GameLib = xDTaraZ.GameLib

---@return Instance?  descendant at a dotted path, nil when any part is missing
function GameLib.Find(root, path)
    local node = root
    for part in path:gmatch("[^.]+") do
        if not node then return nil end
        node = node:FindFirstChild(part)
    end
    return node
end

---@return boolean, any  ok and module, required from a fresh identity-2 thread
function GameLib.RequireAsGame(module)
    if GameLib.CanSwitch == false then return false, nil end

    local done, ok, loaded = false, false, nil
    task.spawn(function()
        local switched = pcall(setthreadidentity, 2)
        local read, identity = pcall(getthreadidentity)
        if switched and read and identity == 2 then
            ok, loaded = pcall(require, module)
        else
            GameLib.CanSwitch = false
        end
        done = true
    end)
    local deadline = osClock() + xDTaraZ.Config.LoadTimeout
    while not done and osClock() < deadline do task.wait() end
    return ok, loaded
end

---@return any?  module, nil when it is missing or no identity can require it
function GameLib.Require(module)
    if not (module and module:IsA("ModuleScript")) then return nil end
    local ok, loaded = pcall(require, module)
    if ok then return loaded end
    local retried, again = GameLib.RequireAsGame(module)
    if retried then return again end
    warn("[AnimeDice] require " .. module:GetFullName() .. ":", loaded)
    return nil
end

do
    local framework = ReplicatedStorage:WaitForChild("Framework", xDTaraZ.Config.LoadTimeout)
    local features = framework and framework:WaitForChild("Features", xDTaraZ.Config.LoadTimeout)
    local function Load(path) return GameLib.Require(GameLib.Find(features, path)) end

    GameLib.Dice = Load("Rolling.Dice")
    GameLib.Rebirths = Load("Rebirth.Rebirths")
    GameLib.Upgrades = Load("Upgrades.Upgrades")
    GameLib.Tree = Load("Upgrades.TreeStructure")
    GameLib.Grades = Load("Grades.Grades")
    GameLib.Traits = Load("Traits.Traits")
    GameLib.Towers = Load("Towers.Towers")
    GameLib.Rarities = GameLib.Require(GameLib.Find(framework, "Other.Rarities"))
    GameLib.Entry = Load("Inventory.EntryRegistry")
    GameLib.Mutations = Load("Inventory.Kinds.Unit.Mutations")
    GameLib.UnitUtil = Load("Inventory.Kinds.Unit.UnitUtil")
    GameLib.Codes = Load("Codes.CodesConfig")
    GameLib.Quests = Load("Quests.QuestConfig")
    GameLib.RollController = Load("Rolling.RollController")
    GameLib.Buffs = Load("Buffs.BuffController")
    GameLib.BuffsConfig = Load("Buffs.BuffsConfig")
    GameLib.FusingConfig = Load("Fusing.FusingConfig")
    GameLib.RebirthStats = Load("Rebirth.RebirthStatsConfig")

    local rewards = GameLib.Find(features, "Rewards")
    GameLib.Daily = GameLib.Require(rewards and rewards:FindFirstChild("DailyRewardConfig", true))
    GameLib.Group = GameLib.Require(rewards and rewards:FindFirstChild("GroupRewardConfig", true))
    GameLib.DataClient = GameLib.Require(GameLib.Find(ReplicatedStorage, "Packages.Data.Client"))
end

GameLib.EntryCache = {}

function GameLib.EntryOf(name)
    local registry = GameLib.Entry
    if not registry or not name then return nil end
    local cached = GameLib.EntryCache[name]
    if cached ~= nil then return cached or nil end
    local ok, config = pcall(registry.getEntryConfig, name)
    GameLib.EntryCache[name] = ok and config or false
    return ok and config or nil
end

function GameLib.GradeOrder(gradeName)
    local grade = gradeName and GameLib.Grades and GameLib.Grades[gradeName]
    return type(grade) == "table" and tonumber(grade.order) or 0
end

---@return number  strongest multiplier, order breaks ties
function GameLib.TraitPower(traitName)
    local trait = traitName and GameLib.Traits and GameLib.Traits[traitName]
    if type(trait) ~= "table" then return 0 end
    local best = math.max(tonumber(trait.incomeMultiplier) or 0, tonumber(trait.damageMultiplier) or 0,
        tonumber(trait.healthMultiplier) or 0)
    return best + (tonumber(trait.order) or 0) / 1000
end

function GameLib.RarityOrder(rarityName)
    local rarities = GameLib.Rarities
    if not rarities or not rarityName then return 0 end
    local ok, entry = pcall(rarities.Get, rarityName)
    return ok and type(entry) == "table" and tonumber(entry.sortOrder) or 0
end

---@return string[]  names of every entry of a kind, sorted
function GameLib.NamesOfKind(kind)
    local registry = GameLib.Entry
    local names = {}
    if not registry then return names end
    local ok, entries = pcall(registry.entriesOfKind, kind)
    if ok and type(entries) == "table" then
        for name in pairs(entries) do names[#names + 1] = tostring(name) end
    end
    table.sort(names)
    return names
end

function GameLib.RebirthStatNames()
    local names = {}
    local config = GameLib.RebirthStats
    if not (config and type(config.Stats) == "table") then return names end
    for _, stat in ipairs(config.Stats) do names[#names + 1] = tostring(stat.name) end
    return names
end

function GameLib.GradeNames()
    local names = Util.SortedKeys(GameLib.Grades or {})
    table.sort(names, function(a, b) return GameLib.GradeOrder(a) < GameLib.GradeOrder(b) end)
    return names
end

function GameLib.TraitNames()
    local names = {}
    for name, trait in pairs(GameLib.Traits or {}) do
        if type(trait) == "table" and GameLib.TraitPower(name) > 0 then names[#names + 1] = name end
    end
    table.sort(names, function(a, b) return GameLib.TraitPower(a) < GameLib.TraitPower(b) end)
    return names
end

function GameLib.MutationNames()
    local names = {}
    for name, mutation in pairs(GameLib.Mutations or {}) do
        if type(mutation) == "table" then names[#names + 1] = name end
    end
    table.sort(names, function(a, b)
        return (tonumber(GameLib.Mutations[a].chance) or 0) < (tonumber(GameLib.Mutations[b].chance) or 0)
    end)
    return names
end

---@return string[]  unit rarities present in the registry, worst first
function GameLib.UnitRarities()
    local seen = {}
    local registry = GameLib.Entry
    if registry then
        local ok, units = pcall(registry.entriesOfKind, "Unit")
        if ok and type(units) == "table" then
            for _, config in pairs(units) do
                if type(config) == "table" and config.rarity then seen[config.rarity] = true end
            end
        end
    end
    local list = {}
    for rarity in pairs(seen) do list[#list + 1] = rarity end
    table.sort(list, function(a, b) return GameLib.RarityOrder(a) < GameLib.RarityOrder(b) end)
    return list
end

function GameLib.ShopNames()
    local names = {}
    local shop = GameLib.Quests and GameLib.Quests.Shop
    for _, item in ipairs(type(shop) == "table" and shop or {}) do
        if type(item) == "table" and item.name and not item.gamepass then names[#names + 1] = item.name end
    end
    return names
end

xDTaraZ.Net = { Cache = {} }
local Network = ReplicatedStorage:WaitForChild("Network", xDTaraZ.Config.LoadTimeout)

---@return Instance?  remote whose name and parent match the path tail, anywhere under Network
function xDTaraZ.Net.Search(path)
    if not Network then return nil end
    local parts = string.split(path, ".")
    local name, parent = parts[#parts], parts[#parts - 1]
    for _, node in ipairs(Network:GetDescendants()) do
        if node.Name == name and (not parent or (node.Parent and node.Parent.Name == parent)) then return node end
    end
    return nil
end

---@return Instance?  remote at a dotted path under Network
function xDTaraZ.Net.Get(path)
    local cached = xDTaraZ.Net.Cache[path]
    if cached and cached.Parent then return cached end

    local remote = GameLib.Find(Network, path) or xDTaraZ.Net.Search(path)
    xDTaraZ.Net.Cache[path] = remote
    return remote
end

function xDTaraZ.Net.Fire(path, ...)
    local remote = xDTaraZ.Net.Get(path)
    if remote then remote:FireServer(...) end
end

---@return boolean, any  invoke success, server reply
function xDTaraZ.Net.Invoke(path, ...)
    local remote = xDTaraZ.Net.Get(path)
    if not remote then return false, "no remote" end
    return pcall(remote.InvokeServer, remote, ...)
end

xDTaraZ.Data = {}

---@return any  raw replicated value of a top-level profile field
function xDTaraZ.Data.Read(field)
    local client = GameLib.DataClient
    if not client then return nil end
    local ok, proxy = pcall(function() return client:get({ field }) end)
    if not ok then return nil end
    if type(proxy) == "table" then
        local okCall, value = pcall(proxy)
        if okCall then return value end
    end
    return proxy
end

function xDTaraZ.Data.Table(field)
    local value = xDTaraZ.Data.Read(field)
    return type(value) == "table" and value or {}
end

function xDTaraZ.Data.Money()
    re