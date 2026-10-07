  NoclipParts = { "Head", "Torso", "UpperTorso", "LowerTorso", "HumanoidRootPart" },
    Fullbright = { Brightness = 2, ClockTime = 14, FogEnd = 1e5, GlobalShadows = false, Ambient = Color3.fromRGB(178, 178, 178) },
    KaitunKeys = {
        "AutoLoot", "AutoSellEggs", "AutoTrain", "AutoHatch", "AutoBuyTool", "AutoPickaxe", "AutoUpgrade",
        "AutoRebirth", "AutoClaim", "AutoSpin", "AutoPass", "AutoEquipBest",
    },
}

xDTaraZ.State = {
    Alive = true,
    Busy = false,
    Conns = {},
    Requests = {},
    Messages = {},
    Halted = {},
    Summary = "Loading...",
    StartCash = nil,
    StartPower = nil,
    Looted = 0,
    Picked = 0,
    LootFull = nil,
    LootReserved = 0,
    Resume = { last = 0, fails = 0, retryAt = 0 },
    SpeedBase = nil,
    PlotFull = nil,
    Trained = false,
    SpeedPinned = false,
    LightingSaved = nil,
    UpgradeNames = {},
    UpgradesChanged = false,
    PotionNames = {},
    Opt = {
        AutoLoot = false,
        LootKeep = {},
        AutoSellEggs = false,
        SellKeep = {},
        AutoSellBrainrots = false,
        AutoEquipBest = false,
        AutoUpgrade = false,
        UpgradePick = {},
        CashReserve = 0,
        AutoRebirth = false,
        AutoTrain = false,
        AutoHatch = false,
        AutoBuyTool = false,
        AutoPickaxe = false,
        AutoPotion = false,
        PotionPick = {},
        AutoClaim = false,
        AutoSpin = false,
        AutoPass = false,
        AutoPickups = false,
        Speed = false,
        SpeedValue = 60,
        InfJump = false,
        Noclip = false,
        Fullbright = false,
        AntiAfk = false,
        CodeInput = "",
        TeleportTarget = nil,
    },
}

local Config, State = xDTaraZ.Config, xDTaraZ.State
State.UpgradeNames = table.clone(Config.FallbackUpgrades)

xDTaraZ.GameLib = {}
local GameLib = xDTaraZ.GameLib

---Plain require first; identity-3 executors get "Cannot require a non-RobloxScript module", so retry once from a fresh identity-2 thread.
---@return table?  module, nil when this executor cannot load it
function GameLib.Require(module)
    if not module or not module:IsA("ModuleScript") then return nil end
    local ok, loaded = pcall(require, module)
    if ok then return loaded end
    local setIdentity = setthreadidentity or setidentity
    local getIdentity = getthreadidentity or getidentity
    if type(setIdentity) ~= "function" or type(getIdentity) ~= "function" then
        warn("[OpenSea] require " .. module.Name .. ":", loaded)
        return nil
    end
    local done, retried = false, nil
    task.spawn(function()
        pcall(setIdentity, 2)
        local again, value = false, nil
        if select(2, pcall(getIdentity)) == 2 then again, value = pcall(require, module) end
        done, retried = true, again and value or nil
    end)
    local deadline = os.clock() + Config.LoadTimeout
    repeat
        if not done then task.wait() end
    until done or os.clock() > deadline
    if not retried then warn("[OpenSea] require " .. module.Name .. ":", loaded) end
    return retried
end

do
    local packages = ReplicatedStorage:WaitForChild("Packages", Config.LoadTimeout)
    local configs = ReplicatedStorage:WaitForChild("Configs", Config.LoadTimeout)
    local function Load(name)
        return GameLib.Require(configs and configs:FindFirstChild(name))
    end

    GameLib.Knit = GameLib.Require(packages and packages:WaitForChild("Knit", Config.LoadTimeout))
    GameLib.Eggs = Load("EggsConfig")
    GameLib.Brainrots = Load("BrainrotsConfig")
    GameLib.Rarities = Load("RaritiesConfig")
    GameLib.Mutations = Load("MutationConfig")
    GameLib.Sizes = Load("SizeConfig")
    GameLib.Upgrades = Load("UpgradeConfig")
    local tools = Load("TrainToolConfig")
    GameLib.TrainTools = tools and tools.TRAIN_TOOLS
    GameLib.Staffs = Load("StaffConfig")
    GameLib.Potions = Load("PotionsConfig")
    GameLib.SeasonPass = Load("SeasonPassConfig")
    GameLib.PlayerStates = Load("PlayerStateConfig")
    GameLib.Modifiers = GameLib.Require(ReplicatedStorage:FindFirstChild("Modifiers"))
end

do
    local describe = { "Knit", "Eggs", "Brainrots", "Mutations", "Sizes" }
    local score = { "Knit", "Eggs", "Brainrots", "Mutations", "Sizes", "Rarities" }
    GameLib.Needs = {
        Kaitun = { "Knit" },
        AutoLoot = score,
        AutoHatch = score,
        AutoEquipBest = { "Knit" },
        AutoSellEggs = describe,
        AutoSellBrainrots = describe,
        AutoUpgrade = { "Knit", "Upgrades" },
        AutoTrain = { "Knit" },
        AutoBuyTool = { "Knit", "TrainTools" },
        AutoPickaxe = { "Knit", "Staffs" },
        AutoPotion = { "Knit", "Potions" },
        AutoRebirth = { "Knit" },
        AutoClaim = { "Knit" },
        AutoSpin = { "Knit" },
        AutoPass = { "Knit", "SeasonPass", "Modifiers" },
    }
end

GameLib.Remotes = {
    AutoLoot = { WaveService = { "Start", "Finished" } },
    AutoHatch = { EggService = { "HatchEgg", "PlaceEgg" }, PlotService = { "GetPlayerPlot" } },
    AutoEquipBest = { AnimalService = { "EquipBest" } },
    AutoSellEggs = { InventoryService = { "SellEgg" } },
    AutoSellBrainrots = { InventoryService = { "SellBrainrot" } },
    AutoUpgrade = { UpgradesService = { "Upgrade" } },
    AutoTrain = { TrainingService = { "StartTraining", "StopTraining" } },
    AutoBuyTool = { TrainingService = { "BuyTrainTool", "EquipTrainTool" } },
    AutoPickaxe = { PickaxeService = { "BuyPickaxe", "EquipPickaxe" } },
    AutoPotion = { PotionService = { "UsePotion" } },
    AutoRebirth = { RebirthService = { "Rebirth" } },
    AutoClaim = { DailyRewardService = { "ClaimReward" }, PlaytimeRewardService = { "ClaimGift" } },
    AutoSpin = { SpinWheelService = { "SpinAll" } },
    AutoPass = { SeasonPassService = { "ClaimPassReward" } },
}

---@return Instance?  Knit Services folder, wherever the package version put it
function GameLib.FindServices()
    local packages = ReplicatedStorage:FindFirstChild("Packages")
    for _, node in ipairs(packages and packages:GetDescendants() or {}) do
        if node.Name == "Services" and node.Parent and node.Parent.Name:lower() == "knit" then return node end
    end
    return nil
end
GameLib.ServiceFolder = GameLib.FindServices()

---@return string?  "Service.Method" the feature calls that the game no longer has
function GameLib.MissingRemote(idx)
    local folder = GameLib.ServiceFolder
    if not folder then return nil end
    for service, methods in pairs(GameLib.Remotes[idx] or {}) do
        local node = folder:FindFirstChild(service)
        for _, method in ipairs(methods) do
            if not (node and node:FindFirstChild(method, true)) then return service .. "." .. method end
        end
    end
    return nil
end

---@return string?  first game module the feature needs that did not load
function GameLib.Missing(idx)
    for _, name in ipairs(GameLib.Needs[idx] or {}) do
        if not GameLib[name] then return name end
    end
    return nil
end

for _, name in ipairs({ "Util", "Data", "Loot", "Sell", "Progress", "Gear", "Boost", "Claim", "Hatch", "Pickup", "Movement", "World", "Scheduler" }) do
    xDTaraZ[name] = {}
end

local services = {}
local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

function xDTaraZ.Util.Try(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then warn("[OpenSea]", err) end
    return ok, err
end

function xDTaraZ.Util.Service(name)
    if not GameLib.Knit then error("game services did not load on this executor", 2) end
    services[name] = services[name] or GameLib.Knit.GetService(name)
    return services[name]
end

---@return string?  body, nil when every way to fetch failed
function xDTaraZ.Util.HttpGet(url)
    if url == "NovaHub://embedded-ui" then return NOVA_HUB_UI_SOURCE end
    local ok, body = pcall(game.HttpGet, game, url)
    if ok and type(body) == "string" then return body end
    local send = (type(request) == "function" and request) or (type(http_request) == "function" and http_request)
        or (type(syn) == "table" and syn.request)
    if type(send) ~= "function" then return nil end
    local sent, response = pcall(send, { Url = url, Method = "GET" })
    if sent and type(response) == "table" and tonumber(response.StatusCode) == 200 and type(response.Body) == "string" then
        return response.Body
    end
    return nil
end

---@param text string  shown as a Roblox notification, works before the menu exists
function xDTaraZ.Util.Alert(text)
    warn("[OpenSea] " .. text)
    task.spawn(function()
        local starterGui = game:GetService("StarterGui")
        for _ = 1, Config.AlertTries do
            if pcall(starterGui.SetCore, starterGui, "SendNotification", { Title = "Nova Hub", Text = text, Duration = 10 }) then return end
            task.wait(Config.AlertRetry)
        end
    end)
end

---@return table?  UI library, nil after telling the player why
function xDTaraZ.Util.LoadLibrary()
    local source = xDTaraZ.Util.HttpGet(Config.UiSource)
    if not source or not source:sub(-64):find("return Library%s*$") then
        xDTaraZ.Util.Alert("Could not download the menu. Check your connection and run it again.")
        return nil
    end
    local chunk, err = loadstring(source)
    if not chunk then
        xDTaraZ.Util.Alert("The menu failed to load on this executor: " .. tostring(err))
        return nil
    end
    local ok, library = pcall(chunk)
    if not ok or type(library) ~= "table" then
        xDTaraZ.Util.Alert("The menu failed to load on this executor: " .. tostring(library))
        return nil
    end
    return library
end

---@return boolean  false when the executor has no clipboard
function xDTaraZ.Util.Copy(text)
    local copy = setclipboard or toclipboard
    if type(copy) ~= "function" then return false end
    return (pcall(copy, text))
end

function xDTaraZ.Util.Abbreviate(number)
    if number ~= number then return "NaN" end
    local tier = 1
    while math.abs(number) >= 1000 and tier < #SUFFIXES do
        number, tier = number / 1000, tier + 1
    end
    return tier == 1 and ("%d"):format(number) or ("%.2f%s"):format(number, SUFFIXES[tier])
end

function xDTaraZ.Util.Count(tbl)
    local n = 0
    for _ in pairs(tbl) do n += 1 end
    return n
end

---@param kind string?  Info (default), Success, Warning or Error
function xDTaraZ.Util.Notify(text, kind)
    State.Messages[#State.Messages + 1] = { Text = text, Kind = kind }
end

---@return string[]  lowest rarity first
function xDTaraZ.Util.RarityNames()
    local names = {}
    if not GameLib.Rarities then return names end
    for name in pairs(GameLib.Rarities) do names[#names + 1] = name end
    table.sort(names, function(a, b) return GameLib.Rarities[a] < GameLib.Rarities[b] end)
    return names
end

function xDTaraZ.Util.MutationNames()
    local names = {}
    for id, entry in pairs(GameLib.Mutations or {}) do
        if type(entry) == "table" then names[#names + 1] = entry.name or id end
    end
    table.sort(names)
    return names
end

function xDTaraZ.Util.PotionNames()
    local names = {}
    for id, potion in pairs(GameLib.Potions or {}) do
        if type(potion) == "table" then table.insert(names, id) end
    end
    table.sort(names)
    return names
end

function xDTaraZ.Data.Get()
    if not GameLib.Knit then error("game data did not load on this executor", 2) end
    return GameLib.Knit.GetController("ReplicaController"):GetPlayerData()
end

function xDTaraZ.Data.Cash()
    return xDTaraZ.Data.Get().Currencies.Cash
end

---@return any  modifier value, nil when Modifiers did not load
function xDTaraZ.Data.Modifier(name)
    local modifiers = GameLib.Modifiers
    if not modifiers then return nil end
    local ok, value = pcall(modifiers.Get, LocalPlayer, name)
    return ok and value or nil
end

function xDTaraZ.Data.InventoryLimit()
    return xDTaraZ.Data.Modifier("InventoryLimit") or Config.InventoryLimit
end

function xDTaraZ.Data.MaxPickup()
    local carry = xDTaraZ.Data.Get().Upgrades.Carry or 1
    if carry ~= carry then return math.huge end
    return math.max(1, carry)
end

---@return number  cash the player may spend after Keep Cash
function xDTaraZ.Data.Budget(profile)
    return (profile or xDTaraZ.Data.Get()).Currencies.Cash - State.Opt.CashReserve
end

---@return string, string, table?, table?  rarity, mutation, size, config
function xDTaraZ.Data.Describe(entity)
    local entry = entity.eggType and GameLib.Eggs.EGGS[entity.eggType]
        or entity.brainrotType and GameLib.Brainrots.CONFIG[entity.brainrotType]
    local mutation = entity.mutation and GameLib.Mutations[entity.mutation]
    local size = GameLib.Sizes.SIZES[entity.size or "baby"]
    return entry and entry.rarity or "Common", mutation and mutation.name or "Normal", size, entry
end

function xDTaraZ.Data.Score(entity)
    local rarity, _, size, entry = xDTaraZ.Data.Describe(entity)
    local mutation = entity.mutation and GameLib.Mutations[entity.mutation]
    local rank = GameLib.Rarities[rarity] or 1
    local mutationMulti = mutation and mutation.cashMulti or 1
    local sizeMulti = size and size.cashMulti or 1
    local bossBonus = entity.isBossItem and 2 or 1
    return rank * 1000 * mutationMulti * sizeMulti * bossBonus + (entry and entry.tier or 1)
end

---@return boolean  true when the item matches a picked rarity or mutation
function xDTaraZ.Data.Matches(entity, picks)
    local rarity, mutation = xDTaraZ.Data.Describe(entity)
    return picks[rarity] or picks[mutation] or false
end

function xDTaraZ.Loot.Wanted(entity)
    local keep = State.Opt.LootKeep
    if next(keep) == nil then return true end
    return xDTaraZ.Data.Matches(entity, keep)
end

---@return string[]  item ids, best first
function xDTaraZ.Loot.PickBest(spawns, limit)
    local ranked = {}
    for id, spawn in pairs(spawns) do
        local entity = spawn.entity
        entity.isBossItem = spawn.isBossItem
        if xDTaraZ.Loot.Wanted(entity) then ranked[#ranked + 1] = { id, xDTaraZ.Data.Score(entity) } end
    end
    table.sort(ranked, function(a, b) return a[2] > b[2] end)

    local picked = {}
    for i = 1, math.min(limit, #ranked) do picked[i] = ranked[i][1] end
    return picked
end

---@return number  slots no other worker holds; 0 when full (the first full reading per pause tells the player once)
function xDTaraZ.Loot.FreeSlots()
    local count, limit = xDTaraZ.Util.Count(xDTaraZ.Data.Get().Inventory), xDTaraZ.Data.InventoryLimit()
    if count < limit then
        State.LootFull = nil
        return limit - count - State.LootReserved
    end
    local full = State.LootFull or { notified = false }
    State.LootFull = full
    full.count, full.limit = count, limit
    if full.notified or not State.Opt.AutoLoot then return 0 end

    full.notified = true
    local selling = State.Opt.AutoSellEggs or State.Opt.AutoSellBrainrots
    xDTaraZ.Util.Notify(("Inventory is full (%d/%d), Auto Loot %s"):format(count, limit,
        selling and "resumes after Auto Sell frees space" or "waits for free space"), "Warning")
    return 0
end

function xDTaraZ.Loot.MayBeTraining()
    if State.Trained or State.Opt.AutoTrain then return true end
    if not GameLib.Knit then return false end
    local ok, training = pcall(function()
        return GameLib.Knit.GetController("TrainingController"):IsTraining()
    end)
    return ok and training == true
end

---@return table?  picked ids, nil when the server refused the wave
function xDTaraZ.Loot.RunWave(take)
    local waves = xDTaraZ.Util.Service("WaveService")
    local wave = waves:Start(Config.WaveExtension)
    if type(wave) ~= "table" or not wave.spawns then return nil end

    local picked = xDTaraZ.Loot.PickBest(wave.spawns, take)
    waves:Finished(picked)
    return picked
end

---@return number?, string?  items taken this wave; nil and "full", "busy" or "refused" when no wave ran
function xDTaraZ.Loot.RunOnce()
    local free = xDTaraZ.Loot.FreeSlots()
    if State.LootFull then return nil, "full" end
    if free <= 0 then return nil, "busy" end

    local take = math.min(xDTaraZ.Data.MaxPickup(), free)
    State.LootReserved += take
    local ok, picked = pcall(xDTaraZ.Loot.RunWave, take)
    State.LootReserved -= take
    if not ok then error(picked, 0) end
    if not picked then return nil, "refused" end

    State.Looted += #picked
    if xDTaraZ.Loot.MayBeTraining() then State.Requests.ResumeTraining = true end
    return #picked
end

function xDTaraZ.Loot.RestartTraining()
    if State.Trained or xDTaraZ.Progress.ServerTraining() then
        xDTaraZ.Util.Service("TrainingService"):StartTraining()
    end
end

---@return boolean  false when throttled or backing off; never fails the farm
function xDTaraZ.Loot.ResumeTraining()
    local resume, now = State.Resume, os.clock()
    if now < resume.retryAt then return false end
    if now - resume.last < Config.ResumeInterval then
        State.Requests.ResumeTraining = true
        return false
    end
    resume.last = now

    local ok, err = pcall(xDTaraZ.Loot.RestartTraining)
    if ok then
        resume.fails = 0
        return true
    end
    resume.fails += 1
    if resume.fails < Config.JobFailLimit then return false end

    resume.fails, resume.retryAt = 0, now + Config.ResumeBackoff
    warn("[OpenSea] resume training:", err)
    return false
end

---@param generation number  worker exits once SetEnabled starts a newer generation
function xDTaraZ.Loot.Worker(generation)
    local fails, firstFail = 0, 0
    while State.Alive and State.Opt.AutoLoot and State.LootGeneration == generation do
        local ok, took = pcall(xDTaraZ.Loot.RunOnce)
        fails = ok and 0 or fails + 1
        if fails == 1 then firstFail = os.clock() end
        if fails >= Config.JobFailLimit and os.clock() - firstFail >= Config.JobFailWindow then
            xDTaraZ.Scheduler.Halt("Auto Loot", "AutoLoot", took)
            break
        end
        if not ok then
            task.wait(1)
        elseif not took then
            task.wait(Config.LootIdle)
        end
        task.wait()
    end
end

function xDTaraZ.Loot.SetEnabled(enabled)
    State.Opt.AutoLoot = enabled
    State.LootGeneration = (State.LootGeneration or 0) + 1
    if not enabled then return end
    if State.LootFull then State.LootFull.notified = false end
    for _ = 1, Config.LootWorkers do task.spawn(xDTaraZ.Loot.Worker, State.LootGeneration) end
end

function xDTaraZ.Hatch.MyPlot()
    local plotId = tostring(xDTaraZ.Util.Service("PlotService"):GetPlayerPlot())
    local plots = Workspace:FindFirstChild("Plots")
    local holder = plots and plots:FindFirstChild(plotId)
    return holder and holder:FindFirstChild(plotId)
end

---@return number  eggs hatched
function xDTaraZ.Hatch.HatchReady()
    local eggs = xDTaraZ.Util.Service("EggService")
    local now, hatched = Workspace:GetServerTimeNow(), 0
    for key, egg in pairs(xDTaraZ.Data.Get().PlacedEggs) do
        if egg.startTime and egg.startTime + (egg.duration or 0) <= now and eggs:HatchEgg(key) then
            hatched += 1
        end
    end
    return hatched
end

---@return table[]  inventory eggs, most valuable first
function xDTaraZ.Hatch.RankedEggs()
    local ranked = {}
    for id, entry in pairs(xDTaraZ.Data.Get().Inventory) do
        local inner = entry.innerEntity
        if entry.itemType == "Egg" and inner and inner.eggType then
            ranked[#ranked + 1] = { id = id, score = GameLib.Eggs.GetSellPrice(inner.eggType) * xDTaraZ.Data.Score(inner) }
        end
    end
    table.sort(ranked, function(a, b) return a.score > b.score end)
    return ranked
end

---@return boolean  true while the plot still holds as many eggs as when the last place was rejected
function xDTaraZ.Hatch.PlotFull(profile)
    local full = State.PlotFull
    if not full then return false end

    local stale = xDTaraZ.Util.Count(profile.PlacedEggs) < full.placed
        or profile.Upgrades.PlotUpgrade ~= full.level
        or os.clock() - full.at >= Config.PlotRecheck
    if stale then State.PlotFull = nil end
    return not stale
end

function xDTaraZ.Hatch.Surface()
    local plot = xDTaraZ.Hatch.MyPlot()
    local surface = plot and plot:FindFirstChild("PlotSurface")
    if not surface then return nil end
    return surface:IsA("BasePart") and surface or surface:FindFirstChildWhichIsA("BasePart", true)
end

---@return number  eggs placed
function xDTaraZ.Hatch.PlaceBest()
    if xDTaraZ.Hatch.PlotFull(xDTaraZ.Data.Get()) then return 0 end
    local part = xDTaraZ.Hatch.Surface()
    if not part then return 0 end

    local eggs, placed = xDTaraZ.Util.Service("EggService"), 0
    for i, egg in ipairs(xDTaraZ.Hatch.RankedEggs()) do
        if i > Config.PlaceEggTries then break end
        local offset = Vector3.new((math.random() - 0.5) * part.Size.X * 0.8, part.Size.Y / 2 + 1, (math.random() - 0.5) * part.Size.Z * 0.8)
        if not eggs:PlaceEgg(egg.id, CFrame.new(part.Position + offset)) then
            local profile = xDTaraZ.Data.Get()
            State.PlotFull = { placed = xDTaraZ.Util.Count(profile.PlacedEggs), level = profile.Upgrades.PlotUpgrade, at = os.clock() }
            break
        end
        placed += 1
    end
    return placed
end

function xDTaraZ.Hatch.Step()
    local hatched = xDTaraZ.Hatch.HatchReady()
    xDTaraZ.Hatch.PlaceBest()
    if hatched > 0 then xDTaraZ.Progress.EquipBest() end
end

---@param kind string  "Egg" or "Brainrot"
---@return number      items sold
function xDTaraZ.Sell.Kind(kind, method)
    local inventory, keep, sold = xDTaraZ.Util.Service("InventoryService"), State.Opt.SellKeep, 0
    for id, entry in pairs(xDTaraZ.Data.Get().Inventory) do
        if entry.itemType ~= kind or entry.locked then continue end
        if xDTaraZ.Data.Matches(entry.innerEntity or {}, keep) then continue end
        inventory[method](inventory, id)
        sold += 1
    end
    return sold
end

function xDTaraZ.Sell.EggsNow()
    return xDTaraZ.Sell.Kind("Egg", "SellEgg")
end

function xDTaraZ.Sell.BrainrotsNow()
    return xDTaraZ.Sell.Kind("Brainrot", "SellBrainrot")
end

---@param profile table  replicated data; unknown upgrade names are appended for the UI pump
function xDTaraZ.Progress.LearnUpgrades(profile)
    for name, level in pairs(profile.Upgrades or {}) do
        if type(name) ~= "string" or type(level) ~= "number" or table.find(State.UpgradeNames, name) then continue end
        table.insert(State.UpgradeNames, name)
        State.UpgradesChanged = true
    end
end

---@return number?  price of the next level, nil when maxed, unknown or the level is not a real number
function xDTaraZ.Progress.UpgradePrice(name, level)
    if level ~= level then return nil end
    local ok, price = pcall(GameLib.Upgrades.GetPrice, name, level)
    if not ok or type(price) ~= "number" or price ~= price then return nil end
    return price
end

---@return number  upgrades bought
function xDTaraZ.Progress.UpgradeNow()
    local upgrades, bought = xDTaraZ.Util.Service("UpgradesService"), 0
    for _, name in ipairs(State.UpgradeNames) do
        if not State.Opt.UpgradePick[name] then continue end
        local price = xDTaraZ.Progress.UpgradePrice(name, xDTaraZ.Data.Get().Upgrades[name])
        if price and xDTaraZ.Data.Budget() - price >= 0 then
            upgrades:Upgrade(name, 1)
            bought += 1
        end
    end
    return bought
end

---@return boolean  false when Carry is already unlimited
function xDTaraZ.Progress.UnlockCarry()
    local carry = xDTaraZ.Data.Get().Upgrades.Carry
    if carry ~= carry then return false end
    xDTaraZ.Util.Service("UpgradesService"):Upgrade("Carry", 0 / 0)
    return true
end

function xDTaraZ.Progress.StartTraining()
    xDTaraZ.Util.Service("TrainingService"):StartTraining()
    State.Trained = true
end

function xDTaraZ.Progress.StopTraining()
    xDTaraZ.Util.Service("TrainingService"):StopTraining()
    State.Trained = false
end

---@return boolean  true while the server counts the player as training
function xDTaraZ.Progress.ServerTraining()
    local states = GameLib.PlayerStates
    if not states then return false end
    return xDTaraZ.Util.Service("PlayerStateService"):GetState() == states.STATES.TRAINING
end

---@return boolean  true if a treadmill session was ended
function xDTaraZ.Progress.ReleaseTreadmill()
    if not GameLib.Knit then return false end
    local controller = GameLib.Knit.GetController("TrainingController")
    if not controller:IsTraining() then return false end

    controller:StopTraining(true)
    if not State.Opt.AutoTrain then State.Trained = false end
    return true
end

---@return string?  strongest dumbbell owned or within budget, nil when the equipped one is best
function xDTaraZ.Progress.BestTool(profile)
    local owned = profile.OwnedTrainTools or {}
    local budget = xDTaraZ.Data.Budget(profile)
    local current = GameLib.TrainTools[profile.EquippedTrainTool]
    local bestName, bestGain = nil, current and current.gainPerTrain or 0
    for name, tool in pairs(GameLib.TrainTools) do
        local reachable = owned[name] or (tool.cost and tool.cost <= budget)
        if reachable and (tool.gainPerTrain or 0) > bestGain then
            bestName, bestGain = name, tool.gainPerTrain
        end
    end
    return bestName
end

---@return string?  dumbbell equipped
function xDTaraZ.Progress.BuyBestTool()
    local profile = xDTaraZ.Data.Get()
    local name = xDTaraZ.Progress.BestTool(profile)
    if not name then return nil end

    local training = xDTaraZ.Util.Service("TrainingService")
    if not (profile.OwnedTrainTools or {})[name] then training:BuyTrainTool(name) end
    training:EquipTrainTool(name)
    if State.Opt.AutoTrain then xDTaraZ.Progress.StartTraining() end
    return name
end

function xDTaraZ.Progress.RebirthNow()
    return xDTaraZ.Util.Service("RebirthService"):Rebirth()
end

function xDTaraZ.Progress.EquipBest()
    xDTaraZ.Util.Service("AnimalService"):EquipBest()
end

---@return number  luck first, reach breaks ties
function xDTaraZ.Gear.Score(staff)
    return (staff.luck or 0) * 1e4 + (staff.reach or 0)
end

---@return boolean  false for event pickaxes and ones locked behind a higher rebirth
function xDTaraZ.Gear.Usable(staff, rebirth)
    if type(staff) ~= "table" or staff.isSpecial then return false end
    return (staff.rebirthRequired or 0) <= rebirth
end

---@return string?  best pickaxe owned or within budget, nil when the equipped one is best
function xDTaraZ.Gear.BestPickaxe(profile)
    local owned, rebirth = profile.OwnedPickaxes or {}, profile.Rebirth or 0
    local budget = xDTaraZ.Data.Budget(profile)
    local current = GameLib.Staffs[profile.EquippedPickaxe]
    local bestId, bestScore = nil, current and xDTaraZ.Gear.Score(current) or -1
    for id, staff in pairs(GameLib.Staffs) do
        if not xDTaraZ.Gear.Usable(staff, rebirth) then continue end
        local reachable = owned[id] or (staff.cost and staff.cost <= budget)
        local score = xDTaraZ.Gear.Score(staff)
        if reachable and score > bestScore then bestId, bestScore = id, score end
    end
    return bestId
end

---@return string?  pickaxe name equipped
function xDTaraZ.Gear.PickaxeNow()
    local profile = xDTaraZ.Data.Get()
    local id = xDTaraZ.Gear.BestPickaxe(profile)
    if not id then return nil end

    local pickaxes = xDTaraZ.Util.Service("PickaxeService")
    if not (profile.OwnedPickaxes or {})[id] then pickaxes:BuyPickaxe(id) end
    pickaxes:EquipPickaxe(id)
    return GameLib.Staffs[id].name or id
end

---@return boolean  true while a potion of this type is still running
function xDTaraZ.Boost.Active(profile, potionType)
    for _, active in pairs(profile.ActivePotions or {}) do
        if type(active) == "table" and active.type == potionType and (active.remaining or 1) > 0 then return true end
    end
    return false
end

---@return number  potions drunk
function xDTaraZ.Boost.Step()
    local profile = xDTaraZ.Data.Get()
    local stock, used = profile.PotionInventory or {}, 0
    for potionType in pairs(State.Opt.PotionPick) do
        if (stock[potionType] or 0) <= 0 or xDTaraZ.Boost.Active(profile, potionType) then continue end
        xDTaraZ.Util.Service("PotionService"):UsePotion(potionType)
        used += 1
    end
    return used
end

function xDTaraZ.Claim.Daily()
    local daily = xDTaraZ.Data.Get().DailyReward
    local nextDay = (daily.LastClaimedDay or 0) % Config.DailyDays + 1
    xDTaraZ.Util.Service("DailyRewardService"):ClaimReward(nextDay)
end

function xDTaraZ.Claim.Playtime()
    local playtime = xDTaraZ.Util.Service("PlaytimeRewardService")
    for slot = 1, Config.PlaytimeSlots do playtime:ClaimGift(slot) end
end

---@return boolean  false when there are not enough tickets for one spin
function xDTaraZ.Claim.Spin()
    local coins = xDTaraZ.Data.Get().Currencies.LuminousCoins or 0
    if coins < Config.SpinCost then return false end
    xDTaraZ.Util.Service("SpinWheelService"):SpinAll()
    return true
end

---@return number  free season pass rewards claimed
function xDTaraZ.Claim.Pass()
    local pass = GameLib.SeasonPass.Pass
    local level = tonumber(xDTaraZ.Data.Modifier("SeasonPassLevel")) or 0
    local claimed = (xDTaraZ.Data.Get().SeasonPass or {}).Free or {}
    local service, count = xDTaraZ.Util.Service("SeasonPassService"), 0
    for index = 1, math.min(level, type(pass) == "table" and #pass or 0) do
        if claimed[tostring(index)] then continue end
        service:ClaimPassReward("Free", index)
        count += 1
    end
    return count
end

function xDTaraZ.Claim.All()
    xDTaraZ.Util.Try(xDTaraZ.Claim.Daily)
    xDTaraZ.Util.Try(xDTaraZ.Claim.Playtime)
    xDTaraZ.Util.Try(xDTaraZ.Claim.Spin)
    xDTaraZ.Util.Try(function() xDTaraZ.Util.Service("AnimalService"):CollectOfflineCash() end)
end

---@return number  codes redeemed
function xDTaraZ.Claim.RedeemCodes(codes)
    local svc, redeemed = xDTaraZ.Util.Service("CodesService"), 0
    for _, code in ipairs(codes) do
        local ok, reply = pcall(svc.RedeemCode, svc, code)
        if ok and reply then redeemed += 1 end
    end
    return redeemed
end

function xDTaraZ.Movement.Humanoid()
    local char = LocalPlayer.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

function xDTaraZ.Movement.Root()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

---@return BasePart?  first part of a pickup that has not been collected yet
function xDTaraZ.Pickup.LivePart(model)
    if not model.Parent then return nil end
    local part = model:IsA("BasePart") and model or model:FindFirstChildWhichIsA("BasePart", true)
    if not part or part.Transparency >= 1 then return nil end
    return part
end

---@param force boolean?  run once even when the toggle is off
---@return number          pickups touched this tick
function xDTaraZ.Pickup.Step(force)
    local folder = Workspace:FindFirstChild("CollectEventPickups")
    local hrp = xDTaraZ.Movement.Root()
    if not folder or not hrp then return 0 end

    local home, touched = hrp.CFrame, 0
    for _, model in ipairs(folder:GetChildren()) do
        if touched >= Config.PickupsPerTick or not (force or State.Opt.AutoPickups) then break end
        local part = xDTaraZ.Pickup.LivePart(model)
        if not part then continue end
        hrp.CFrame = CFrame.new(part.Position)
        touched += 1
        task.wait(Config.PickupHop)
    end
    if touched > 0 and hrp.Parent then hrp.CFrame = home end
    State.Picked += touched
    return touched
end

function xDTaraZ.Movement.OnPinned()
    if State.SpeedPinned then return end
    State.SpeedPinned = true
    State.Requests.ReleaseTreadmill = true
end

function xDTaraZ.Movement.ApplySpeed(hum)
    if State.SpeedBase == nil then State.SpeedBase = hum.WalkSpeed > 0 and hum.WalkSpeed or false end
    if hum.WalkSpeed == 0 then
        xDTaraZ.Movement.OnPinned()
    else
        State.SpeedPinned = false
    end
    hum.WalkSpeed = State.Opt.SpeedValue
end

function xDTaraZ.Movement.Step()
    local hum = xDTaraZ.Movement.Humanoid()
    if not hum then return end
    if State.Opt.Speed then xDTaraZ.Movement.ApplySpeed(hum) end
    if not State.Opt.Noclip then return end

    for _, part in ipairs(LocalPlayer.Character:GetChildren()) do
        if part:IsA("BasePart") then part.CanCollide = false end
    end
end

function xDTaraZ.Movement.RestoreCollision()
    local char = LocalPlayer.Character
    if not char then return end
    for _, name in ipairs(Config.NoclipParts) do
        local part = char:FindFirstChild(name)
        if part and part:IsA("BasePart") then part.CanCollide = true end
    end
end

function xDTaraZ.Movement.Bind()
    table.insert(State.Conns, RunService.Stepped:Connect(xDTaraZ.Movement.Step))
    table.insert(State.Conns, UserInputService.JumpRequest:Connect(function()
        local hum = xDTaraZ.Movement.Humanoid()
        if State.Opt.InfJump and hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end))
    table.insert(State.Conns, LocalPlayer.Idled:Connect(function()
        if not State.Opt.AntiAfk then return end
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.zero)
    end))
end

function xDTaraZ.Movement.ResetSpeed()
    local hum = xDTaraZ.Movement.Humanoid()
    local base = State.SpeedBase
    State.SpeedBase = nil
    if not hum then return end
    hum.WalkSpeed = base or xDTaraZ.Data.Get().Upgrades.MovementSpeed or 16
end

function xDTaraZ.World.ApplyFullbright()
    if not State.LightingSaved then
        local saved = {}
        for prop in pairs(Config.Fullbright) do saved[prop] = Lighting[prop] end
        State.LightingSaved = saved
    end
    for prop, value in pairs(Config.Fullbright) do Lighting[prop] = value end
end

function xDTaraZ.World.RestoreLighting()
    local saved = State.LightingSaved
    State.LightingSaved = nil
    if not saved then return end
    for prop, value in pairs(saved) do Lighting[prop] = value end
end

function xDTaraZ.World.ToBase()
    xDTaraZ.Util.Service("PlotService"):TeleportToPlot()
end

function xDTaraZ.World.ToShop()
    xDTaraZ.Util.Service("WarpService"):WarpToLocation("Shop")
end

---@return boolean  false when the player or their character is gone
function xDTaraZ.World.ToPlayer(name)
    local target = name and Players:FindFirstChild(name)
    local theirRoot = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
    local hrp = xDTaraZ.Movement.Root()
    if not theirRoot or not hrp then return false end
    xDTaraZ.Util.Try(xDTaraZ.Progress.ReleaseTreadmill)
    hrp.CFrame = theirRoot.CFrame * CFrame.new(0, 0, 3)
    return true
end

function xDTaraZ.World.PlayerNames()
    local names = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then names[#names + 1] = player.Name end
    end
    table.sort(names)
    return names
end

function xDTaraZ.World.Rejoin()
    TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
end

---@return string?  job id of another public server with room, nil when none was found
function xDTaraZ.World.FindServer()
    local body = xDTaraZ.Util.HttpGet(Config.ServerList:format(game.PlaceId))
    if not body then return nil end
    local ok, page = pcall(HttpService.JSONDecode, HttpService, body)
    if not ok or type(page) ~= "table" then return nil end

    local pool = {}
    for _, server in ipairs(page.data or {}) do
        local room = (server.maxPlayers or 0) - (server.playing or 0)
        if server.id ~= game.JobId and room > 0 then table.insert(pool, server.id) end
    end
    return #pool > 0 and pool[math.random(#pool)] or nil
end

---@return boolean  false when no other server was found
function xDTaraZ.World.Hop()
    local jobId = xDTaraZ.World.FindServer()
    if not jobId then return false end
    TeleportService:TeleportToPlaceInstance(game.PlaceId, jobId, LocalPlayer)
    return true
end

local function Report(fn, okText, failText)
    return function()
        local ok, got = xDTaraZ.Util.Try(fn)
        if ok and got then
            xDTaraZ.Util.Notify(type(okText) == "function" and okText(got) or okText)
        else
            xDTaraZ.Util.Notify(failText)
        end
    end
end

local function Counted(fn, format)
    return function()
        local ok, count = xDTaraZ.Util.Try(fn)
        xDTaraZ.Util.Notify(ok and format:format(tonumber(count) or 0) or "Request failed")
    end
end

xDTaraZ.Scheduler.Requests = {
    LootOnce = function()
        local ok, count, reason = xDTaraZ.Util.Try(xDTaraZ.Loot.RunOnce)
        if ok and count then
            xDTaraZ.Util.Notify(("Collected %d item(s)"):format(count))
        elseif ok and reason == "full" then
            xDTaraZ.Util.Notify(("Inventory is full (%d/%d)"):format(State.LootFull.count, State.LootFull.limit), "Warning")
        else
            xDTaraZ.Util.Notify("Wave not ready")
        end
    end,
    SellEggs = Counted(xDTaraZ.Sell.EggsNow, "Sold %d egg(s)"),
    SellBrainrots = Counted(xDTaraZ.Sell.BrainrotsNow, "Sold %d brainrot(s)"),
    HatchNow = function()
        local ok, hatched = xDTaraZ.Util.Try(xDTaraZ.Hatch.HatchReady)
        local _, placed = xDTaraZ.Util.Try(xDTaraZ.Hatch.PlaceBest)
        xDTaraZ.Util.Notify(("Hatched %d, placed %d egg(s)"):format(ok and hatched or 0, tonumber(placed) or 0))
    end,
    EquipBestNow = Report(function() xDTaraZ.Progress.EquipBest() return true end, "Best animals placed", "Could not place animals"),
    UpgradeNow = Counted(xDTaraZ.Progress.UpgradeNow, "Bought %d upgrade(s)"),
    UnlockCarry = Report(xDTaraZ.Progress.UnlockCarry, "Unlimited Carry requested", "Carry is already unlimited"),
    ToolNow = Report(xDTaraZ.Progress.BuyBestTool, function(name) return "Equipped " .. name end, "Nothing better to buy"),
    PickaxeNow = Report(xDTaraZ.Gear.PickaxeNow, function(name) return "Equipped " .. name end, "Nothing better to buy"),
    PotionNow = Counted(xDTaraZ.Boost.Step, "Used %d potion(s)"),
    RebirthNow = Report(xDTaraZ.Progress.RebirthNow, "Rebirthed", "Requirement not met"),
    ClaimNow = function()
        xDTaraZ.Claim.All()
        xDTaraZ.Util.Notify("Rewards claimed")
    end,
    SpinNow = Report(xDTaraZ.Claim.Spin, "Wheel spun", "Not enough tickets"),
    PassNow = Counted(xDTaraZ.Claim.Pass, "Claimed %d pass reward(s)"),
    PickupNow = Counted(function() return xDTaraZ.Pickup.Step(true) end, "Picked up %d event item(s)"),
    RedeemAll = function()
        xDTaraZ.Util.Notify(("Redeemed %d/%d code(s)"):format(xDTaraZ.Claim.RedeemCodes(Config.Codes), #Config.Codes))
    end,
    RedeemInput = function()
        local codes = {}
        for code in State.Opt.CodeInput:gmatch("[^,%s]+") do codes[#codes + 1] = code end
        xDTaraZ.Util.Notify(("Redeemed %d/%d code(s)"):format(xDTaraZ.Claim.RedeemCodes(codes), #codes))
    end,
    ToBase = function() xDTaraZ.Util.Try(xDTaraZ.World.ToBase) end,
    ToShop = function() xDTaraZ.Util.Try(xDTaraZ.World.ToShop) end,
    ToPlayer = Report(function() return xDTaraZ.World.ToPlayer(State.Opt.TeleportTarget) end, "Teleported", "Player not found"),
    Hop = Report(xDTaraZ.World.Hop, "Joining another server", "No other server found"),
    RestoreLighting = function() xDTaraZ.Util.Try(xDTaraZ.World.RestoreLighting) end,
    ResetSpeed = function() xDTaraZ.Util.Try(xDTaraZ.Movement.ResetSpeed) end,
    StopTrain = function() xDTaraZ.Util.Try(xDTaraZ.Progress.StopTraining) end,
    ReleaseTreadmill = function()
        local ok, released = xDTaraZ.Util.Try(xDTaraZ.Progress.ReleaseTreadmill)
        if not (ok and released) then
            State.SpeedPinned = false
            return
        end
        xDTaraZ.Util.Notify("Left the treadmill so Speed works")
    end,
    ResumeTraining = function() xDTaraZ.Loot.ResumeTraining() end,
}

---@return string  equipped pickaxe and dumbbell names
function xDTaraZ.Scheduler.GearLine(profile)
    local staff = GameLib.Staffs and GameLib.Staffs[profile.EquippedPickaxe]
    local pickaxe = staff and staff.name or tostring(profile.EquippedPickaxe or "-")
    return ("Pickaxe %s · Dumbbell %s"):format(pickaxe, tostring(profile.EquippedTrainTool or "-"))
end

function xDTaraZ.Scheduler.Summarize()
    local profile = xDTaraZ.Data.Get()
    local cash, power = profile.Currencies.Cash, profile.Power or 0
    xDTaraZ.Progress.LearnUpgrades(profile)
    State.StartCash = State.StartCash or cash
    State.StartPower = State.StartPower or power

    local abbr = xDTaraZ.Util.Abbreviate
    local lines = {
        ("Cash %s (+%s)"):format(abbr(cash), abbr(cash - State.StartCash)),
        ("Power %s (+%s)"):format(abbr(power), abbr(power - State.StartPower)),
        ("Rebirth %d · Carry %s"):format(profile.Rebirth or 0, abbr(profile.Upgrades.Carry or 1)),
        xDTaraZ.Scheduler.GearLine(profile),
        ("Inventory %d/%d · Looted %d"):format(xDTaraZ.Util.Count(profile.Inventory), xDTaraZ.Data.InventoryLimit(), State.Looted),
    }
    if State.Picked > 0 then lines[#lines + 1] = ("Event pickups %d"):format(State.Picked) end
    if State.Opt.AutoLoot and State.LootFull then lines[#lines + 1] = "WARNING: inventory full, Auto Loot paused" end
    State.Summary = table.concat(lines, "\n")
end

xDTaraZ.Scheduler.Jobs = {
    { "Status", nil, xDTaraZ.Scheduler.Summarize, 0 },
    { "Fullbright", "Fullbright", xDTaraZ.World.ApplyFullbright, Config.FullbrightInterval },
    { "Auto Hatch", "AutoHatch", xDTaraZ.Hatch.Step, Config.SellInterval },
    { "Auto Sell Eggs", "AutoSellEggs", xDTaraZ.Sell.EggsNow, Config.SellInterval },
    { "Auto Sell Brainrots", "AutoSellBrainrots", xDTaraZ.Sell.BrainrotsNow, Config.SellInterval },
    { "Auto Place Best", "AutoEquipBest", xDTaraZ.Progress.EquipBest, Config.SellInterval },
    { "Auto Upgrade", "AutoUpgrade", xDTaraZ.Progress.UpgradeNow, Config.UpgradeInterval },
    { "Auto Rebirth", "AutoRebirth", xDTaraZ.Progress.RebirthNow, Config.UpgradeInterval },
    { "Auto Buy Dumbbell", "AutoBuyTool", xDTaraZ.Progress.BuyBestTool, Config.UpgradeInterval },
    { "Auto Pickaxe", "AutoPickaxe", xDTaraZ.Gear.PickaxeNow, Config.UpgradeInterval },
    { "Auto Train", "AutoTrain", xDTaraZ.Progress.StartTraining, Config.UpgradeInterval },
    { "Auto Potion", "AutoPotion", xDTaraZ.Boost.Step, Config.PotionInterval },
    { "Event Pickups", "AutoPickups", xDTaraZ.Pickup.Step, Config.PickupInterval },
    { "Auto Spin", "AutoSpin", xDTaraZ.Claim.Spin, Config.ClaimInterval },
    { "Season Pass", "AutoPass", xDTaraZ.Claim.Pass, Config.ClaimInterval },
    { "Auto Claim", "AutoClaim", xDTaraZ.Claim.All, Config.ClaimInterval },
}

---Switches a failing feature off from the scheduler thread; the UI pump flips the toggle (this thread has touched game modules).
function xDTaraZ.Scheduler.Halt(label, idx, err)
    if idx and not State.Opt[idx] then return end
    local reason = tostring(err):match("^[^\n]*")
    if idx then
        State.Opt[idx] = false
        State.Halted[#State.Halted + 1] = idx
    end
    warn("[OpenSea] " .. label .. " stopped:", reason)
    xDTaraZ.Util.Notify(label .. " stopped: " .. reason)
end

---@param job table  { label, toggle idx, step, interval }; a feature halts after Config.JobFailLimit errors spanning Config.JobFailWindow seconds, the status job only goes quiet
function xDTaraZ.Scheduler.Run(job, now)
    if job[2] and not State.Opt[job[2]] then
        job.Streak = nil
        return
    end
    if now - (job.Last or 0) < job[4] then return end
    job.Last = now

    local ok, err = pcall(job[3])
    if ok then
        job.Streak = nil
        return
    end
    local streak = job.Streak
    if not streak then
        streak = { count = 0, since = now }
        job.Streak = streak
        warn("[OpenSea] " .. job[1] .. ":", err)
    end
    streak.count += 1
    if not job[2] or streak.count < Config.JobFailLimit or now - streak.since < Config.JobFailWindow then return end
    job.Streak = nil
    xDTaraZ.Scheduler.Halt(job[1], job[2], err)
end

function xDTaraZ.Scheduler.Step()
    for name, handler in pairs(xDTaraZ.Scheduler.Requests) do
        if State.Requests[name] then
            State.Requests[name] = nil
            xDTaraZ.Util.Try(handler)
        end
    end

    local now = os.clock()
    for _, job in ipairs(xDTaraZ.Scheduler.Jobs) do
        xDTaraZ.Scheduler.Run(job, now)
    end
end

function xDTaraZ.Scheduler.Boot()
    xDTaraZ.Movement.Bind()
    task.spawn(function()
        while State.Alive do
            if not State.Busy then
                State.Busy = true
                xDTaraZ.Util.Try(xDTaraZ.Scheduler.Step)
                State.Busy = false
            end
            task.wait(Config.TickDelay)
        end
    end)
end

function xDTaraZ.Scheduler.Stop()
    State.Alive = false
    getgenv().OpenSeaUnload = nil
    State.Opt.AutoLoot = false
    State.Opt.AutoPickups = false
    for _, conn in ipairs(State.Conns) do conn:Disconnect() end
    table.clear(State.Conns)
    if State.Opt.Noclip then xDTaraZ.Movement.RestoreCollision() end
    if State.Opt.Speed then xDTaraZ.Util.Try(xDTaraZ.Movement.ResetSpeed) end
    xDTaraZ.Util.Try(xDTaraZ.World.RestoreLighting)
    if State.Trained then task.spawn(xDTaraZ.Util.Try, xDTaraZ.Progress.StopTraining) end
end

---@return boolean  false when the menu could not load
local function BuildInterface()
    local Library = xDTaraZ.Util.LoadLibrary()
    if not Library then return false end
    pcall(NovaBanner.Step, "UI library")
    local Options = Library.Options
    local T = function(en, th) return Library:T(en, th) end
    local opt = State.Opt
    local widgets = {}

    local keepValues = {}
    xDTaraZ.Util.Try(function()
        for _, name in ipairs(xDTaraZ.Util.RarityNames()) do keepValues[#keepValues + 1] = name end
        for _, name in ipairs(xDTaraZ.Util.MutationNames()) do table.insert(keepValues, name) end
    end)

    local function Notify(text, kind)
        Library:Notify("Open Sea For Animals", text, 4, kind or "Info")
    end

    ---@param idx string?  feature whose game modules the request needs
    local function Request(name, idx)
        return function()
            if idx and GameLib.Missing(idx) then
                Notify("Not available on this executor", "Warning")
                return
            end
            State.Requests[name] = true
        end
    end

    local function Toggle(group, key, text, description, onChange, risky)
        return group:AddToggle(key, {
            Text = text,
            Description = description,
            Default = false,
            Risky = risky,
            Callback = function(value)
                opt[key] = value
                if onChange then onChange(value) end
            end,
        })
    end

    local function Live(group, key, text, description, onChange)
        return Toggle(group, key, text, description, onChange):AddKeyPicker(key .. "Key", { Default = "None", Mode = "Toggle" })
    end

    local function MultiSelect(group, key, text, description, values, default)
        return group:AddDropdown(key, {
            Text = text,
            Description = description,
            Values = values,
            Multi = true,
            Default = default or {},
            Searchable = #values > 8,
            Callback = function(selected) opt[key] = selected end,
        })
    end

    local function NowButton(group, text, request, idx)
        return group:AddButton({ Text = text, Style = "Primary", Func = Request(request, idx) })
    end

    local function BuildMain(window)
        window:AddTabSection(T("Farm", "ฟาร์ม"))
        local tab = window:AddTab(T("Main", "หลัก"), "house", T("Loot farm and status", "ฟาร์มของและสถานะ"))

        local statusBox = tab:AddLeftGroupbox(T("Status", "สถานะ"))
        widgets.Status = statusBox:AddLabel("Loading...")

        local lootBox = tab:AddLeftGroupbox(T("Sea Loot", "เก็บของในทะเล"))
        Toggle(lootBox, "AutoLoot", T("Auto Loot", "เก็บของอัตโนมัติ"),
            T("Collects the top eggs and brainrots from every wave", "เก็บไข่และ brainrot ที่ดีที่สุดทุกคลื่น"),
            xDTaraZ.Loot.SetEnabled)
        NowButton(lootBox, T("Loot Once", "เก็บหนึ่งรอบ"), "LootOnce", "AutoLoot")
        MultiSelect(lootBox, "LootKeep", T("Only Collect", "เก็บเฉพาะ"),
            T("Empty takes the top item, otherwise only these", "เว้นว่าง = เอาชิ้นดีสุด ถ้าเลือกจะเก็บเฉพาะที่เลือก"), keepValues)

        local discordBox = tab:AddRightGroupbox(T("Discord", "ดิสคอร์ด"), "link")
        discordBox:AddLabel(Config.Discord)
        discordBox:AddButton({ Text = T("Copy Discord Link", "คัดลอกลิงก์ Discord"), Style = "Primary", Func = function()
            local copied = xDTaraZ.Util.Copy(Config.Discord)
            Notify(copied and "Discord link copied" or Config.Discord)
        end })

        local logBox = tab:AddRightGroupbox(T("Update Log", "อัปเดตล่าสุด"), "bell")
        for i = 1, math.min(2, #Config.UpdateLog) do
            local entry = Config.UpdateLog[i]
            logBox:AddParagraph({ Title = entry[1], Content = entry[2] })
        end

        local kaitunBox = tab:AddRightGroupbox(T("Kaitun", "ไก่ตัน"))
        kaitunBox:AddToggle("Kaitun", {
            Text = T("Kaitun", "ไก่ตัน"),
            Description = T("Loot, sell, gear, upgrades, rebirth and rewards together", "เก็บของ ขาย อุปกรณ์ อัปเกรด รีเบิร์ธ และรางวัลพร้อมกัน"),
            Default = false,
            NoSave = true,
            Callback = function(value)
                for _, key in ipairs(Config.KaitunKeys) do
                    local toggle = Options[key]
                    if toggle then toggle:SetValue(value) end
                end
            end,
        })
    end

    local function BuildAnimals(window)
        local tab = window:AddTab(T("Animals", "สัตว์"), "heart", T("Sell, hatch and place", "ขาย ฟัก และวาง"))

        local sellBox = tab:AddLeftGroupbox(T("Sell", "ขาย"))
        Toggle(sellBox, "AutoSellEggs", T("Auto Sell Eggs", "ขายไข่อัตโนมัติ"), T("Sells eggs as they come in, except kept ones", "ขายไข่ที่ได้มาทันที ยกเว้นที่เลือกเก็บไว้"))
        NowButton(sellBox, T("Sell Eggs Now", "ขายไข่เดี๋ยวนี้"), "SellEggs", "AutoSellEggs")
        Toggle(sellBox, "AutoSellBrainrots", T("Auto Sell Brainrots", "ขาย brainrot อัตโนมัติ"), T("Sells unlocked brainrots, except kept ones", "ขาย brainrot ที่ไม่ได้ล็อก ยกเว้นที่เลือกเก็บไว้"))
        NowButton(sellBox, T("Sell Brainrots Now", "ขาย brainrot เดี๋ยวนี้"), "SellBrainrots", "AutoSellBrainrots")
        MultiSelect(sellBox, "SellKeep", T("Keep", "เก็บไว้"), T("Rarities and mutations that are never sold", "rarity และ mutation ที่จะไม่ขาย"), keepValues)

        local hatchBox = tab:AddRightGroupbox(T("Hatching", "ฟักไข่"))
        Toggle(hatchBox, "AutoHatch", T("Auto Hatch", "ฟักไข่อัตโนมัติ"), T("Places your most valuable eggs and hatches them", "วางไข่ที่มีค่าที่สุดแล้วฟักให้"))
        NowButton(hatchBox, T("Hatch Now", "ฟักเดี๋ยวนี้"), "HatchNow", "AutoHatch")

        local placeBox = tab:AddRightGroupbox(T("Animals", "สัตว์"))
        Toggle(placeBox, "AutoEquipBest", T("Auto Equip Best", "ใส่ตัวดีสุดอัตโนมัติ"), T("Keeps your top animals placed on your plot", "วางสัตว์ตัวที่ดีที่สุดบนพื้นที่เสมอ"))
        NowButton(placeBox, T("Equip Best Now", "ใส่ตัวดีสุดเดี๋ยวนี้"), "EquipBestNow", "AutoEquipBest")
    end

    local function BuildUpgrade(window)
        window:AddTabSection(T("Progress", "ความคืบหน้า"))
        local tab = window:AddTab(T("Upgrade", "อัปเกรด"), "sliders-horizontal", T("Upgrades, rebirth and potions", "อัปเกรด รีเบิร์ธ และยา"))

        local upgradeBox = tab:AddLeftGroupbox(T("Upgrades", "อัปเกรด"))
        Toggle(upgradeBox, "AutoUpgrade", T("Auto Upgrade", "อัปเกรดอัตโนมัติ"), T("Buys the selected upgrades when you can afford them", "ซื้ออัปเกรดที่เลือกทุกครั้งที่เงินพอ"))
        NowButton(upgradeBox, T("Upgrade Now", "อัปเกรดเดี๋ยวนี้"), "UpgradeNow", "AutoUpgrade")
        widgets.Upgrades = MultiSelect(upgradeBox, "UpgradePick", T("Upgrades", "อัปเกรด"), T("Carry brings back more items per wave", "Carry ทำให้ขนของกลับได้มากขึ้นต่อคลื่น"), table.clone(State.UpgradeNames), table.clone(State.UpgradeNames))
        for _, name in ipairs(State.UpgradeNames) do opt.UpgradePick[name] = true end
        upgradeBox:AddInput("CashReserve", {
            Text = T("Keep Cash", "กันเงินไว้"),
            Description = T("Never spend below this amount", "ไม่ใช้เงินจนต่ำกว่าจำนวนนี้"),
            Default = "0",
            Numeric = true,
            Finished = true,
            Callback = function(value) opt.CashReserve = math.max(0, tonumber(value) or 0) end,
        })
        upgradeBox:AddButton({ Text = T("Unlimited Carry", "ขนของไม่จำกัด"), Risky = true, Func = Request("UnlockCarry", "AutoUpgrade") })

        local rebirthBox = tab:AddRightGroupbox(T("Rebirth", "รีเบิร์ธ"))
        Toggle(rebirthBox, "AutoRebirth", T("Auto Rebirth", "รีเบิร์ธอัตโนมัติ"), T("Rebirths as soon as you meet the requirement", "รีเบิร์ธทันทีเมื่อครบเงื่อนไข"))
        NowButton(rebirthBox, T("Rebirth Now", "รีเบิร์ธเดี๋ยวนี้"), "RebirthNow", "AutoRebirth")

        local potionBox = tab:AddRightGroupbox(T("Potions", "ยา"))
        Toggle(potionBox, "AutoPotion", T("Auto Potion", "ใช้ยาอัตโนมัติ"), T("Drinks the selected potions you own when they run out", "ดื่มยาที่เลือกเมื่อหมดเวลา ใช้ของที่มีอยู่"))
        NowButton(potionBox, T("Use Potions Now", "ใช้ยาเดี๋ยวนี้"), "PotionNow", "AutoPotion")
        MultiSelect(potionBox, "PotionPick", T("Potions", "ยา"), nil, xDTaraZ.Util.PotionNames())
    end

    local function BuildGear(window)
        local tab = window:AddTab(T("Gear", "อุปกรณ์"), "zap", T("Power, dumbbells and pickaxes", "พลัง ดัมเบลล์ และพลั่ว"))

        local powerBox = tab:AddLeftGroupbox(T("Power", "พลัง"))
        Toggle(powerBox, "AutoTrain", T("Auto Train", "ฝึกอัตโนมัติ"), T("Gains power anywhere, more power reaches further out", "เพิ่มพลังได้ทุกที่ พลังยิ่งเยอะยิ่งเอื้อมได้ไกล"), function(value)
            if not value and State.Trained then State.Requests.StopTrain = true end
        end)
        Toggle(powerBox, "AutoBuyTool", T("Auto Dumbbell", "ดัมเบลล์อัตโนมัติ"), T("Buys and equips the strongest dumbbell you can get", "ซื้อและใส่ดัมเบลล์ที่แรงที่สุดที่ได้"))
        NowButton(powerBox, T("Dumbbell Now", "ดัมเบลล์เดี๋ยวนี้"), "ToolNow", "AutoBuyTool")

        local pickBox = tab:AddRightGroupbox(T("Pickaxe", "พลั่ว"))
        Toggle(pickBox, "AutoPickaxe", T("Auto Pickaxe", "พลั่วอัตโนมัติ"), T("Buys and equips the luckiest pickaxe you can get", "ซื้อและใส่พลั่วที่โชคดีที่สุดที่ได้"))
        NowButton(pickBox, T("Pickaxe Now", "พลั่วเดี๋ยวนี้"), "PickaxeNow", "AutoPickaxe")
    end

    local function BuildRewards(window)
        local tab = window:AddTab(T("Rewards", "รางวัล"), "shop", T("Rewards, codes and events", "รางวัล โค้ด และอีเวนต์"))

        local claimBox = tab:AddLeftGroupbox(T("Rewards", "รางวัล"))
        Toggle(claimBox, "AutoClaim", T("Auto Claim", "รับรางวัลอัตโนมัติ"), T("Daily, playtime, free shop, packs and offline cash", "รายวัน เวลาเล่น ร้านฟรี แพ็ก และเงินตอนออฟไลน์"))
        NowButton(claimBox, T("Claim All Now", "รับทั้งหมดเดี๋ยวนี้"), "ClaimNow", "AutoClaim")
        claimBox:AddButton({ Text = T("Redeem All Codes", "ใช้โค้ดทั้งหมด"), Func = Request("RedeemAll", "AutoClaim") })
        claimBox:AddInput("CodeBox", {
            Text = T("Redeem Codes", "ใส่โค้ด"),
            Description = T("Separate codes with commas", "คั่นโค้ดด้วยจุลภาค"),
            Default = "",
            Placeholder = T("CODE1, CODE2", "โค้ด1, โค้ด2"),
            Finished = true,
            Callback = function(value)
                opt.CodeInput = value
                if value ~= "" then State.Requests.RedeemInput = true end
            end,
        })

        local spinBox = tab:AddRightGroupbox(T("Wheel and Pass", "วงล้อและพาส"))
        Toggle(spinBox, "AutoSpin", T("Auto Spin", "หมุนวงล้ออัตโนมัติ"), T("Spins the wheel whenever you have tickets", "หมุนวงล้อทุกครั้งที่มีตั๋ว"))
        NowButton(spinBox, T("Spin Now", "หมุนเดี๋ยวนี้"), "SpinNow", "AutoSpin")
        Toggle(spinBox, "AutoPass", T("Auto Season Pass", "รับรางวัลพาสอัตโนมัติ"), T("Claims every free pass reward you reached", "รับรางวัลพาสฟรีทุกขั้นที่ถึงแล้ว"))
        NowButton(spinBox, T("Claim Pass Now", "รับพาสเดี๋ยวนี้"), "PassNow", "AutoPass")

        local eventBox = tab:AddRightGroupbox(T("Event", "อีเวนต์"))
        Toggle(eventBox, "AutoPickups", T("Auto Event Pickups", "เก็บของอีเวนต์อัตโนมัติ"), T("Grabs event items around the map, then returns", "เก็บของอีเวนต์รอบแมพแล้วกลับที่เดิม"), nil, true)
        NowButton(eventBox, T("Pick Up Now", "เก็บเดี๋ยวนี้"), "PickupNow")
    end

    local function BuildPlayer(window)
        window:AddTabSection(T("Other", "อื่นๆ"))
        local tab = window:AddTab(T("Player", "ผู้เล่น"), "user", T("Movement and visuals", "การเคลื่อนที่และภาพ"))

        local moveBox = tab:AddLeftGroupbox(T("Movement", "การเคลื่อนที่"))
        Live(moveBox, "Speed", T("Speed", "ความเร็ว"), nil, function(value)
            State.SpeedPinned = false
            if not value then State.Requests.ResetSpeed = true end
        end)
        moveBox:AddSlider("SpeedValue", {
            Text = T("Walk Speed", "ความเร็วเดิน"),
            Default = opt.SpeedValue,
            Min = 16,
            Max = 300,
            Rounding = 0,
            Callback = function(value) opt.SpeedValue = tonumber(value) or opt.SpeedValue end,
        })
        Live(moveBox, "InfJump", T("Infinite Jump", "กระโดดไม่จำกัด"))

        local bodyBox = tab:AddRightGroupbox(T("Body and World", "ตัวละครและโลก"))
        Live(bodyBox, "Noclip", T("Noclip", "ทะลุวัตถุ"), nil, function(value)
            if not value then xDTaraZ.Movement.RestoreCollision() end
        end)
        Toggle(bodyBox, "Fullbright", T("Fullbright", "สว่างทั้งแมพ"), nil, function(value)
            if not value then State.Requests.RestoreLighting = true end
        end)
    end

    local function BuildTeleport(window)
        local tab = window:AddTab(T("Teleport", "วาร์ป"), "teleport", T("Places and players", "สถานที่และผู้เล่น"))

        local placeBox = tab:AddLeftGroupbox(T("Places", "สถานที่"))
        placeBox:AddButton({ Text = T("My Base", "ฐานของฉัน"), Style = "Primary", Func = Request("ToBase", "AutoClaim") })
        placeBox:AddButton({ Text = T("Shop", "ร้านค้า"), Func = Request("ToShop", "AutoClaim") })

        local playerBox = tab:AddRightGroupbox(T("Players", "ผู้เล่น"))
        widgets.Players = playerBox:AddDropdown("TeleportTarget", {
            Text = T("Player", "ผู้เล่น"),
            Values = xDTaraZ.World.PlayerNames(),
            Searchable = true,
            Callback = function(value) opt.TeleportTarget = value end,
        })
        playerBox:AddButton({ Text = T("Teleport", "วาร์ป"), Style = "Primary", Func = Request("ToPlayer") })
            :AddButton({ Text = T("Refresh", "รีเฟรช"), Func = function()
                widgets.Players:SetValues(xDTaraZ.World.PlayerNames())
            end })
    end

    local function BuildSettings(window)
        local tab = window:AddSettingsTab()
        local sessionBox = tab:AddRightGroupbox(T("Session", "เซสชัน"))
        Toggle(sessionBox, "AntiAfk", T("Anti AFK", "กันหลุด AFK"), T("Stay in the server while idle", "อยู่ในเซิร์ฟต่อได้แม้ไม่ได้ขยับ"))
        sessionBox:AddButton({ Text = T("Rejoin", "เข้าเซิร์ฟเดิมใหม่"), Func = function() xDTaraZ.Util.Try(xDTaraZ.World.Rejoin) end })
        sessionBox:AddButton({ Text = T("Server Hop", "ย้ายเซิร์ฟ"), Func = Request("Hop") })
    end

    ---Features whose game module or remote is gone refuse to turn on instead of erroring every tick.
    local function GateModules()
        for idx in pairs(GameLib.Needs) do
            if not Options[idx] then continue end
            local missing = GameLib.Missing(idx)
            if missing then
                warn("[OpenSea] " .. idx .. " disabled, module missing: " .. missing)
                Library.Compat.Block(idx, T("Not available on this executor", "ใช้กับ executor นี้ไม่ได้"))
                continue
            end
            local gone = GameLib.MissingRemote(idx)
            if gone then
                warn("[OpenSea] " .. idx .. " disabled, remote missing: " .. gone)
                Library.Compat.Block(idx, T("The game changed, waiting for a script update", "เกมอัปเดต รอสคริปต์อัปเดต"))
            end
        end
        if not GameLib.ServiceFolder then warn("[OpenSea] knit Services folder not found, remote check skipped") end
        if not GameLib.Knit then State.Summary = "Game data is not available on this executor" end
    end

    local function RefreshUpgrades()
        local drop = widgets.Upgrades
        if not State.UpgradesChanged or not drop then return end
        State.UpgradesChanged = false
        local picked = table.clone(drop.Value or {})
        drop:SetValues(table.clone(State.UpgradeNames))
        drop:SetValue(picked)
    end

    local function Pump()
        while #State.Messages > 0 do
            local message = table.remove(State.Messages, 1)
            Notify(message.Text, message.Kind)
        end

        while #State.Halted > 0 do
            local toggle = Library.Toggles[table.remove(State.Halted, 1)]
            if toggle and toggle.Value then toggle:SetValue(false) end
        end

        if widgets.Status then widgets.Status:SetText(State.Summary) end
        RefreshUpgrades()
    end

    local function BuildTabs()
        local window = Library.Window
        local try = xDTaraZ.Util.Try
        try(BuildMain, window)
        try(BuildAnimals, window)
        try(BuildUpgrade, window)
        try(BuildGear, window)
        try(BuildRewards, window)
        try(BuildPlayer, window)
        try(BuildTeleport, window)
        try(BuildSettings, window)
        try(GateModules)

        Library:Every(1, Pump)
    end

    Library:OnUnload(xDTaraZ.Scheduler.Stop)
    getgenv().OpenSeaUnload = function()
        Library:Unload()
    end

    Library:CreateWindow({
        Title = "Nova Hub",
        SubTitle = "Open Sea For Animals by xDTaraZ",
        MenuKey = Enum.KeyCode.LeftControl,
        ConfigFolder = Config.SaveFolder,
        Language = "Auto",
        Theme = "Nova",
        OnUnlocked = function()
            BuildTabs()
            xDTaraZ.Util.Try(xDTaraZ.Scheduler.Boot)
            Notify("Loaded")
            xDTaraZ.Util.Try(Library.LoadAutoloadConfig, Library)
        end,
    })
    return true
end

if getgenv().OpenSeaUnload then
    pcall(getgenv().OpenSeaUnload)
end

pcall(NovaBanner.Step, "Systems")
if BuildInterface() then
    pcall(NovaBanner.Step, "Interface")
    pcall(NovaBanner.Ready)
end]==]

NOVA_HUB_MODULES[66654135] = [==[if not game:IsLoaded() then
    game.Loaded:Wait()
end

if game.GameId ~= 66654135 then
    game:GetService("Players").LocalPlayer:Kick("Nova Hub: this script is for Murder Mystery 2 only")
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
    if ok and type(renv) == "table" and type(renv.print) == "function" then
        NovaBanner.Print = renv.print
    end
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
        "   MURDER MYSTERY 2  //  by xDTaraZ  //  discord.gg/FHVfmeSceA",
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

if not LPH_OBFUSCATED then
    local function Passthrough(fn) return fn end
    LPH_JIT, LPH_JIT_MAX, LPH_NO_VIRTUALIZE = Passthrough, Passthrough, Passthrough
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer

local xDTaraZ = setmetatable({}, {
    __newindex = function(self, key, value)
        rawset(self, key, type(value) == "function" and LPH_JIT(value) or value)
    end,
})

xDTaraZ.Config = {
    Discord = "https://discord.gg/FHVfmeSceA",
    UpdateLog = {
        { "2026-10-03", "Classic Nova Hub UI is back\nBetter executor support\nImproved Farming, Combat & Movement" },
    },
    UiSource = "NovaHub://embedded-ui",
    SaveFolder = "Murder Mystery 2",
    LoadTimeout = 10,
    AlertTries = 20,
    AlertRetry = 0.5,
    JobFailLimit = 5,
    JobFailWindow = 10,
    StatusRefresh = 1,
    TickDelay = 0.5,
    RoleRefresh = 1,
    ShootStands = { Vector3.new(0, 0, 6), Vector3.new(0, 0, -6), Vector3.new(6, 0, 0), Vector3.new(-6, 0, 0), Vector3.new(0, 6, 3) },
    ShootAttempts = 3,
    ShootConfirm = 0.8,
    ShootSettle = 0.25,
    ShootReturn = 0.3,
    ShootCooldown = 1.2,
    StabCooldown = 0.9,
    BusyTimeout = 6,
    StabOffset = 2,
    KillAuraRange = 18,
    GunGrabHold = 0.35,
    FarmSpeed = 25,
    FarmSpeedMax = 28,
    FarmMurdererRadius = 30,
    FarmArrive = 1.5,
    FarmBrake = 20,
    FarmGroundLift = 4,
    FarmGroundReach = 400,
    FarmIdleWait = 0.3,
    FarmSettle = 0.15,
    FarmSkipTime = 4,
    FlingVelocityCap = 120,
    XRayTransparency = 0.6,
    DodgeRange = 22,
    DodgeCooldown = 2.5,
    VictimPriority = { Sheriff = 1, Hero = 1, Innocent = 2 },
    FlingForce = 9e4,
    FlingTime = 2.5,
    FlySpeed = 70,
    SpeedDefault = 16,
    JumpDefault = 50,
    LobbyName = "RegularLobby",
    Colors = {
        Murderer = Color3.fromHSV(0, 0.75, 1),
        Sheriff = Color3.fromHSV(0.6, 0.7, 1),
        Hero = Color3.fromHSV(0.14, 0.8, 1),
        Innocent = Color3.fromHSV(0.33, 0.6, 0.95),
        Gun = Color3.fromHSV(0.12, 0.9, 1),
        Coin = Color3.fromHSV(0.15, 0.6, 1),
    },
}

local Config = xDTaraZ.Config

xDTaraZ.State = {
    Alive = true,
    Conns = {},
    Roles = {},
    LastRoleFetch = 0,
    LastShoot = 0,
    LastStab = 0,
    ActionBusy = false,
    BusySince = 0,
    ShootBusy = false,
    LastDodge = 0,
    FarmBusy = false,
    FarmHome = nil,
    FarmMover = nil,
    Bag = { Current = 0, Max = 0 },
    SkippedCoins = {},
    XRayMap = nil,
    XRayParts = {},
    Skins = {},
    KillBusy = false,
    NoclipConn = nil,
    NoclipSaved = {},
    FlyConn = nil,
    FlyVelocity = nil,
    StickTarget = nil,
    Hook = nil,
    Esp = { Players = {}, Gun = nil },
    LightingDefaults = nil,
    Halted = {},
    Opt = {
        AutoGrabGun = false,
        AutoShoot = false,
        SilentAim = false,
        AutoKillAll = false,
        KillAura = false,
        KnifeAim = false,
        AutoDodge = false,
        Kaitun = false,
        AutoFarm = false,
        FarmSpeed = 25,
        ResetWhenFull = false,
        AntiFling = false,
        XRay = false,
        Aimbot = false,
        AimSmooth = 70,
        SkinSource = nil,
        EspPlayers = false,
        EspGun = false,
        RoleNotify = false,
        SpeedOn = false,
        WalkSpeed = 24,
        JumpOn = false,
        JumpPower = 70,
        InfJump = false,
        Noclip = false,
        Fly = false,
        Fullbright = false,
        AntiAfk = false,
        TrollTarget = nil,
        TeleportTarget = nil,
    },
}

local State = xDTaraZ.State

for _, name in ipairs({ "Util", "Round", "Sheriff", "Murderer", "Troll", "Survive", "Kaitun", "Farm", "Aim", "Skin", "Teleport", "Movement", "Esp", "Visual", "Session", "Scheduler" }) do
    xDTaraZ[name] = {}
end

function xDTaraZ.Util.Try(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        warn("[MM2]", err)
    end
    return ok, err
end

---@param text string  shown as a Roblox notification, works before the menu exists
function xDTaraZ.Util.Alert(text)
    warn("[MM2] " .. text)
    task.spawn(function()
        local starterGui = game:GetService("StarterGui")
        for _ = 1, Config.AlertTries do
            if pcall(starterGui.SetCore, starterGui, "SendNotification", { Title = "Nova Hub", Text = text, Duration = 10 }) then
                return
            end
            task.wait(Config.AlertRetry)
        end
    end)
end

---@return string?  body, nil when every way to fetch failed
function xDTaraZ.Util.HttpGet(url)
    if url == "NovaHub://embedded-ui" then return NOVA_HUB_UI_SOURCE end
    local ok, body = pcall(game.HttpGet, game, url)
    if ok and type(body) == "string" then
        return body
    end
    local send = (type(request) == "function" and request) or (type(http_request) == "function" and http_request)
        or (type(syn) == "table" and syn.request) or (type(http) == "table" and http.request)
    if type(send) ~= "function" then
        return nil
    end
    local sent, response = pcall(send, { Url = url, Method = "GET" })
    if sent and type(response) == "table" and tonumber(response.StatusCode) == 200 and type(response.Body) == "string" then
        return response.Body
    end
    return nil
end

---@return table?  UI library, nil after telling the player why
function xDTaraZ.Util.LoadLibrary()
    local source = xDTaraZ.Util.HttpGet(Config.UiSource)
    if not source or not source:sub(-64):find("return Library%s*$") then
        xDTaraZ.Util.Alert("Could not download the menu. Check your connection and run it again.")
        return nil
    end
    local chunk, err = loadstring(source)
    if not chunk then
        xDTaraZ.Util.Alert("The menu failed to load on this executor: " .. tostring(err))
        return nil
    end
    local ok, library = pcall(chunk)
    if not ok or type(library) ~= "table" then
        xDTaraZ.Util.Alert("The menu failed to load on this executor: " .. tostring(library))
        return nil
    end
    if type(library.Compat) ~= "table" then
        xDTaraZ.Util.Alert("The menu is out of date. Wait a few minutes and run the script again.")
        return nil
    end
    return library
end

---@param instance Instance  parented to gethui, then CoreGui, then PlayerGui
function xDTaraZ.Util.Mount(instance)
    local ok, hui = pcall(gethui)
    if ok and typeof(hui) == "Instance" and pcall(function() instance.Parent = hui end) then
        return
    end
    if pcall(function() instance.Parent = game:GetService("CoreGui") end) then
        return
    end
    instance.Parent = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", Config.LoadTimeout)
end

xDTaraZ.GameLib = {}
local GameLib = xDTaraZ.GameLib

---@param class string  RemoteFunction or BaseRemoteEvent
---@return Instance?    remote in its usual folder, else the first with that name anywhere in ReplicatedStorage
function GameLib.Remote(folder, name, class)
    local remote = folder and folder:FindFirstChild(name)
    remote = remote or ReplicatedStorage:FindFirstChild(name, true)
    return remote and remote:IsA(class) and remote or nil
end

do
    local remotes = ReplicatedStorage:WaitForChild("Remotes", Config.LoadTimeout)
    local gameplay = remotes and remotes:WaitForChild("Gameplay", Config.LoadTimeout)
    local extras = remotes and remotes:FindFirstChild("Extras")
    GameLib.PlayerData = GameLib.Remote(gameplay, "GetCurrentPlayerData", "RemoteFunction")
    GameLib.CoinCollected = GameLib.Remote(gameplay, "CoinCollected", "BaseRemoteEvent")
    GameLib.CoinsStarted = GameLib.Remote(gameplay, "CoinsStarted", "BaseRemoteEvent")
    GameLib.RoundStart = GameLib.Remote(gameplay, "RoundStart", "BaseRemoteEvent")
    GameLib.RedeemCode = GameLib.Remote(extras, "RedeemCode", "RemoteFunction")
end

GameLib.Needs = {
    RoleNotify = { "RoundStart" },
    ResetWhenFull = { "CoinCollected" },
}

---@return string?  first remote the feature needs that is gone
function GameLib.Missing(idx)
    for _, name in ipairs(GameLib.Needs[idx] or {}) do
        if not GameLib[name] then return name end
    end
    return nil
end

function xDTaraZ.Util.Connect(signal, fn)
    local conn = signal:Connect(fn)
    table.insert(State.Conns, conn)
    return conn
end

function xDTaraZ.Util.Root(player)
    local character = (player or LocalPlayer).Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

function xDTaraZ.Util.Humanoid(player)
    local character = (player or LocalPlayer).Character
    return character and character:FindFirstChildOfClass("Humanoid")
end

function xDTaraZ.Util.Tool(player, name)
    local character = player.Character
    local backpack = player:FindFirstChild("Backpack")
    return (character and character:FindFirstChild(name)) or (backpack and backpack:FindFirstChild(name))
end

function xDTaraZ.Round.RefreshRoles()
    if os.clock() - State.LastRoleFetch < Config.RoleRefresh then
        return
    end
    State.LastRoleFetch = os.clock()
    if not GameLib.PlayerData then return end
    local ok, roster = pcall(GameLib.PlayerData.InvokeServer, GameLib.PlayerData)
    if ok and type(roster) == "table" then
        State.Roles = roster
    end
end

---@return string?  role, falls back to the tools in their backpack
function xDTaraZ.Round.RoleOf(player)
    local entry = State.Roles[player.Name]
    if entry and not entry.Dead and entry.Role then
        return entry.Role
    end
    if xDTaraZ.Util.Tool(player, "Knife") then
        return "Murderer"
    end
    if xDTaraZ.Util.Tool(player, "Gun") then
        return "Sheriff"
    end
    return entry and entry.Dead and "Dead" or "Innocent"
end

function xDTaraZ.Round.FindByRole(role)
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and xDTaraZ.Round.RoleOf(player) == role and xDTaraZ.Util.Root(player) then
            return player
        end
    end
    return nil
end

function xDTaraZ.Round.Map()
    for _, child in ipairs(workspace:GetChildren()) do
        if child.Name ~= Config.LobbyName and child:IsA("Model") and child:FindFirstChild("CoinContainer") then
            return child
        end
    end
    return nil
end

---@return Model?  lobby by its usual name, else any workspace model named like a lobby
function xDTaraZ.Round.Lobby()
    local lobby = workspace:FindFirstChild(Config.LobbyName)
    if lobby then return lobby end
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("Model") and child.Name:find("Lobby") then return child end
    end
    return nil
end

function xDTaraZ.Round.IAmPlaying()
    local entry = State.Roles[LocalPlayer.Name]
    local humanoid = xDTaraZ.Util.Humanoid()
    return xDTaraZ.Round.Map() ~= nil and humanoid ~= nil and humanoid.Health > 0 and entry ~= nil and not entry.Dead
end

function xDTaraZ.Round.GunDrop()
    local map = xDTaraZ.Round.Map()
    local drop = (map and map:FindFirstChild("GunDrop", true)) or workspace:FindFirstChild("GunDrop")
    return drop
end

function xDTaraZ.Movement.SetNoclip(enabled)
    if State.NoclipConn then
        State.NoclipConn:Disconnect()
        State.NoclipConn = nil
    end
    if not enabled then
        xDTaraZ.Movement.RestoreCollision()
        return
    end
    local saved = State.NoclipSaved
    State.NoclipConn = xDTaraZ.Util.Connect(RunService.Stepped, function()
        local character = LocalPlayer.Character
        if not character then return end
        for _, part in ipairs(character:GetChildren()) do
            if not part:IsA("BasePart") then continue end
            if saved[part] == nil then
                saved[part] = part.CanCollide
            end
            part.CanCollide = false
        end
    end)
end

function xDTaraZ.Movement.RestoreCollision()
    for part, canCollide in pairs(State.NoclipSaved) do
        if part.Parent then part.CanCollide = canCollide end
    end
    table.clear(State.NoclipSaved)
end

function xDTaraZ.Movement.RefreshNoclip()
    xDTaraZ.Movement.SetNoclip(State.Opt.Noclip or State.FarmBusy)
end

function xDTaraZ.Movement.Apply()
    local humanoid = xDTaraZ.Util.Humanoid()
    if not humanoid then
        return
    end
    local opt = State.Opt
    if opt.SpeedOn then
        humanoid.WalkSpeed = opt.WalkSpeed
    end
    if opt.JumpOn then
        humanoid.UseJumpPower = true
        humanoid.JumpPower = opt.JumpPower
    end
end

function xDTaraZ.Movement.RestoreSpeed()
    local humanoid = xDTaraZ.Util.Humanoid()
    if humanoid then
        humanoid.WalkSpeed = Config.SpeedDefault
    end
end

function xDTaraZ.Movement.RestoreJump()
    local humanoid = xDTaraZ.Util.Humanoid()
    if humanoid then
        humanoid.JumpPower = Config.JumpDefault
    end
end

function xDTaraZ.Movement.InitInfJump()
    xDTaraZ.Util.Connect(UserInputService.JumpRequest, function()
        local humanoid = xDTaraZ.Util.Humanoid()
        if State.Opt.InfJump and humanoid then
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end)
end

function xDTaraZ.Movement.SetFly(enabled)
    if State.FlyConn then
        State.FlyConn:Disconnect()
        State.FlyConn = nil
    end
    if State.FlyVelocity then
        State.FlyVelocity:Destroy()
        State.FlyVelocity = nil
    end
    local humanoid = xDTaraZ.Util.Humanoid()
    if humanoid then
        humanoid.PlatformStand = false
    end
    if not enabled then
        return
    end
    local mover = Instance.new("BodyVelocity")
    mover.MaxForce = Vector3.one * 1e9
    mover.Velocity = Vector3.zero
    State.FlyVelocity = mover
    State.FlyConn = xDTaraZ.Util.Connect(RunService.RenderStepped, function()
        local root, hum = xDTaraZ.Util.Root(), xDTaraZ.Util.Humanoid()
        if not root or not hum then
            return
        end
        mover.Parent = root
        hum.PlatformStand = true
        local vertical = (UserInputService:IsKeyDown(Enum.KeyCode.Space) and 1 or 0) - (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) and 1 or 0)
        mover.Velocity = (hum.MoveDirection + Vector3.yAxis * vertical) * Config.FlySpeed
    end)
end

function xDTaraZ.Util.Busy()
    return State.ActionBusy and os.clock() - State.BusySince < Config.BusyTimeout
end

function xDTaraZ.Util.SetBusy(busy)
    State.ActionBusy = busy
    State.BusySince = os.clock()
end

---@return any  result of action, character moved back after
function xDTaraZ.Util.WarpAndReturn(targetCFrame, action)
    local root = xDTaraZ.Util.Root()
    if not root or not targetCFrame or xDTaraZ.Util.Busy() then
        return false
    end
    xDTaraZ.Util.SetBusy(true)
    local home = root.CFrame
    local ok = xDTaraZ.Util.Try(function()
        root.CFrame = targetCFrame
        root.AssemblyLinearVelocity = Vector3.zero
        action()
    end)
    local current = xDTaraZ.Util.Root()
    if current then
        current.CFrame = home
    end
    xDTaraZ.Util.SetBusy(false)
    return ok
end

function xDTaraZ.Sheriff.Gun()
    return xDTaraZ.Util.Tool(LocalPlayer, "Gun")
end

function xDTaraZ.Sheriff.Equip(tool)
    local humanoid = xDTaraZ.Util.Humanoid()
    if humanoid and tool.Parent ~= LocalPlayer.Character then
        humanoid:EquipTool(tool)
    end
end

function xDTaraZ.Sheriff.ClearStand(target, targetRoot)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LocalPlayer.Character, target.Character }
    for _, offset in ipairs(Config.ShootStands) do
        local position = (targetRoot.CFrame * CFrame.new(offset)).Position
        if not workspace:Raycast(position, targetRoot.Position - position, params) then
            return CFrame.lookAt(position, targetRoot.Position)
        end
    end
    return CFrame.lookAt((targetRoot.CFrame * CFrame.new(Config.ShootStands[1])).Position, targetRoot.Position)
end

function xDTaraZ.Sheriff.ShootTarget(target)
    local gun, targetRoot = xDTaraZ.Sheriff.Gun(), xDTaraZ.Util.Root(target)
    if not gun or not targetRoot or os.clock() - State.LastShoot < Config.ShootCooldown then
        return false
    end
    State.LastShoot = os.clock()
    xDTaraZ.Sheriff.Equip(gun)
    return xDTaraZ.Util.WarpAndReturn(xDTaraZ.Sheriff.ClearStand(target, targetRoot), function()
        task.wait(Config.ShootSettle)
        local root = xDTaraZ.Util.Root()
        local attachment = root and root:FindFirstChild("GunRaycastAttachment")
        local aimRoot = xDTaraZ.Util.Root(target) or targetRoot
        gun.Shoot:FireServer(attachment and attachment.WorldCFrame or root.CFrame, aimRoot.CFrame)
        task.wait(Config.ShootReturn)
    end)
end

function xDTaraZ.Util.IsDead(player)
    local humanoid = xDTaraZ.Util.Humanoid(player)
    return not humanoid or humanoid.Health <= 0
end

function xDTaraZ.Sheriff.ShootMurderer()
    xDTaraZ.Round.RefreshRoles()
    local murderer = xDTaraZ.Round.FindByRole("Murderer")
    if not murderer then
        return false, "No murderer found"
    end
    for _ = 1, Config.ShootAttempts do
        if not xDTaraZ.Sheriff.Gun() then
            break
        end
        xDTaraZ.Sheriff.ShootTarget(murderer)
        task.wait(Config.ShootConfirm)
        if xDTaraZ.Util.IsDead(murderer) then
            return true, murderer.Name
        end
        task.wait(math.max(0, Config.ShootCooldown - Config.ShootConfirm))
    end
    return false, murderer.Name .. " survived"
end

function xDTaraZ.Sheriff.AutoShootStep()
    if not State.Opt.AutoShoot or State.ShootBusy or not xDTaraZ.Sheriff.Gun() or not xDTaraZ.Round.IAmPlaying() then
        return
    end
    State.ShootBusy = true
    task.spawn(function()
        xDTaraZ.Util.Try(xDTaraZ.Sheriff.ShootMurderer)
        State.ShootBusy = false
    end)
end

function xDTaraZ.Sheriff.GrabGun()
    local drop = xDTaraZ.Round.GunDrop()
    if not drop or xDTaraZ.Sheriff.Gun() or not xDTaraZ.Round.IAmPlaying() then
        return false
    end
    local part = drop:IsA("BasePart") and drop or drop:FindFirstChildWhichIsA("BasePart", true)
    if not part then
        return false
    end
    return xDTaraZ.Util.WarpAndReturn(part.CFrame, function()
        local root = xDTaraZ.Util.Root()
        if root and xDTaraZ.Library.Compat.Caps.Touch then
            firetouchinterest(root, part, 0)
            firetouchinterest(root, part, 1)
        end
        task.wait(Config.GunGrabHold)
    end)
end

function xDTaraZ.Sheriff.AutoGrabStep()
    if State.Opt.AutoGrabGun and xDTaraZ.Round.RoleOf(LocalPlayer) ~= "Murderer" and xDTaraZ.Round.GunDrop() then
        task.spawn(xDTaraZ.Sheriff.GrabGun)
    end
end

function xDTaraZ.Murderer.Knife()
    return xDTaraZ.Util.Tool(LocalPlayer, "Knife")
end

function xDTaraZ.Murderer.Stab(target)
    local knife, targetRoot = xDTaraZ.Murderer.Knife(), xDTaraZ.Util.Root(target)
    if not knife or not targetRoot then
        return false
    end
    xDTaraZ.Sheriff.Equip(knife)
    local events = knife:FindFirstChild("Events")
    if not events then
        return false
    end
    local stand = targetRoot.CFrame * CFrame.new(0, 0, Config.StabOffset)
    return xDTaraZ.Util.WarpAndReturn(stand, function()
        events.KnifeStabbed:FireServer()
        task.wait()
        local aimRoot = xDTaraZ.Util.Root(target) or targetRoot
        events.HandleTouched:FireServer(aimRoot)
        task.wait(Config.StabCooldown)
    end)
end

function xDTaraZ.Murderer.Victims()
    local victims = {}
    for _, player in ipairs(Players:GetPlayers()) do
        local humanoid = xDTaraZ.Util.Humanoid(player)
        local entry = State.Roles[player.Name]
        local inRound = entry == nil or not entry.Dead
        if player ~= LocalPlayer and humanoid and humanoid.Health > 0 and inRound and xDTaraZ.Util.Root(player) then
            table.insert(victims, player)
        end
    end
    table.sort(victims, function(a, b)
        return (Config.VictimPriority[xDTaraZ.Round.RoleOf(a)] or 3) < (Config.VictimPriority[xDTaraZ.Round.RoleOf(b)] or 3)
    end)
    return victims
end

function xDTaraZ.Murderer.KillAll()
    if not xDTaraZ.Murderer.Knife() then
        return 0
    end
    local kills = 0
    for _, victim in ipairs(xDTaraZ.Murderer.Victims()) do
        if not State.Alive or not xDTaraZ.Murderer.Knife() then
            break
        end
        if xDTaraZ.Murderer.Stab(victim) then
            kills = kills + 1
        end
    end
    return kills
end

function xDTaraZ.Murderer.AutoKillStep()
    if not State.Opt.AutoKillAll or State.KillBusy or not xDTaraZ.Murderer.Knife() or not xDTaraZ.Round.IAmPlaying() then
        return
    end
    State.KillBusy = true
    task.spawn(function()
        xDTaraZ.Util.Try(xDTaraZ.Murderer.KillAll)
        State.KillBusy = false
    end)
end

function xDTaraZ.Murderer.KillAuraStep()
    local knife, root = xDTaraZ.Murderer.Knife(), xDTaraZ.Util.Root()
    if not State.Opt.KillAura or not knife or not root or os.clock() - State.LastStab < Config.StabCooldown then
        return
    end
    local events = knife:FindFirstChild("Events")
    for _, victim in ipairs(xDTaraZ.Murderer.Victims()) do
        local victimRoot = xDTaraZ.Util.Root(victim)
        if events and victimRoot and (victimRoot.Position - root.Position).Magnitude <= Config.KillAuraRange then
            State.LastStab = os.clock()
            xDTaraZ.Sheriff.Equip(knife)
            events.KnifeStabbed:FireServer()
            events.HandleTouched:FireServer(victimRoot)
            return
        end
    end
end

function xDTaraZ.Murderer.NearestVictimRoot(origin)
    local best, bestDistance
    for _, victim in ipairs(xDTaraZ.Murderer.Victims()) do
        local victimRoot = xDTaraZ.Util.Root(victim)
        local distance = victimRoot and (victimRoot.Position - origin).Magnitude
        if distance and (not bestDistance or distance < bestDistance) then
            best, bestDistance = victimRoot, distance
        end
    end
    return best
end

---Hooked only while Silent Aim or Knife Throw Aim is on, the original goes back when both are off.
function xDTaraZ.Sheriff.SyncAimHook()
    local wanted = State.Alive and (State.Opt.SilentAim or State.Opt.KnifeAim)
    if wanted and not State.Hook then
        xDTaraZ.Util.Try(xDTaraZ.Sheriff.InstallAimHook)
    elseif not wanted and State.Hook then
        local restore = State.Hook
        State.Hook = nil
        xDTaraZ.Util.Try(restore)
    end
end

function xDTaraZ.Sheriff.InstallAimHook()
    if not xDTaraZ.Library.Compat.Has({ "Namecall", "CheckCaller" }) then return end
    local original, restore
    original, restore = xDTaraZ.Library.Compat.HookMeta(game, "__namecall", function(self, ...)
        if not State.Alive or getnamecallmethod() ~= "FireServer" or checkcaller() then
            return original(self, ...)
        end
        local parent = self.Parent
        local opt = State.Opt
        if opt.SilentAim and self.Name == "Shoot" and parent and parent.Name == "Gun" then
            local murderer = xDTaraZ.Round.FindByRole("Murderer")
            local murdererRoot = murderer and xDTaraZ.Util.Root(murderer)
            if murdererRoot then
                local origin = ...
                return original(self, origin, murdererRoot.CFrame)
            end
        elseif opt.KnifeAim and self.Name == "KnifeThrown" and parent and parent.Name == "Events" then
            local origin = ...
            local victimRoot = xDTaraZ.Murderer.NearestVictimRoot(origin.Position)
            if victimRoot then
                return original(self, origin, victimRoot.Position)
            end
        end
        return original(self, ...)
    end)
    State.Hook = restore
end

function xDTaraZ.Survive.SafestSpot(threatPosition)
    local map = xDTaraZ.Round.Map()
    local best, bestDistance
    for _, coin in ipairs(map and map.CoinContainer:GetChildren() or {}) do
        if coin:IsA("BasePart") then
            local distance = (coin.Position - threatPosition).Magnitude
            if not bestDistance or distance > bestDistance then
                best, bestDistance = coin, distance
            end
        end
    end
    return best and CFrame.new(best.Position + Vector3.new(0, 3, 0))
end

function xDTaraZ.Survive.DodgeStep()
    local root = xDTaraZ.Util.Root()
    local murderer = xDTaraZ.Round.FindByRole("Murderer")
    local threat = murderer and xDTaraZ.Util.Root(murderer)
    if not State.Opt.AutoDodge or not root or not threat or xDTaraZ.Murderer.Knife() or xDTaraZ.Util.Busy() then
        return
    end
    if os.clock() - State.LastDodge < Config.DodgeCooldown or (threat.Position - root.Position).Magnitude > Config.DodgeRange then
        return
    end
    local spot = xDTaraZ.Survive.SafestSpot(threat.Position)
    if spot then
        State.LastDodge = os.clock()
        root.CFrame = spot
        root.AssemblyLinearVelocity = Vector3.zero
    end
end

function xDTaraZ.Kaitun.Step()
    if not State.Opt.Kaitun or not xDTaraZ.Round.IAmPlaying() then
        return
    end
    local opt = State.Opt
    opt.AutoKillAll = xDTaraZ.Murderer.Knife() ~= nil
    opt.AutoShoot = xDTaraZ.Sheriff.Gun() ~= nil
    opt.AutoGrabGun = true
    opt.AutoDodge = true
    opt.AutoFarm = true
end

function xDTaraZ.Farm.NearestCoin(map, origin)
    local murderer = not xDTaraZ.Murderer.Knife() and xDTaraZ.Round.FindByRole("Murderer")
    local threat = murderer and xDTaraZ.Util.Root(murderer)
    local best, bestDistance
    for _, coin in ipairs(map.CoinContainer:GetChildren()) do
        local visual = coin:FindFirstChild("CoinVisual")
        local skippedAt = State.SkippedCoins[coin]
        local skipped = skippedAt and os.clock() - skippedAt < Config.FarmSkipTime
        local dangerous = threat and (coin.Position - threat.Position).Magnitude < Config.FarmMurdererRadius
        if coin:IsA("BasePart") and visual and not visual:GetAttribute("Collected") and not skipped and not dangerous then
            local distance = (coin.Position - origin).Magnitude
            if not bestDistance or distance < bestDistance then
                best, bestDistance = coin, distance
            end
        end
    end
    return best
end

function xDTaraZ.Farm.BagFull()
    return State.Bag.Max > 0 and State.Bag.Current >= State.Bag.Max
end

function xDTaraZ.Farm.CanRun()
    return State.Alive and State.Opt.AutoFarm and xDTaraZ.Round.IAmPlaying() and not xDTaraZ.Farm.BagFull()
end

function xDTaraZ.Farm.AttachMover(root)
    local attachment = Instance.new("Attachment")
    attachment.Parent = root
    local mover = Instance.new("LinearVelocity")
    mover.Attachment0 = attachment
    mover.MaxForce = math.huge
    mover.RelativeTo = Enum.ActuatorRelativeTo.World
    mover.VectorVelocity = Vector3.zero
    mover.Parent = root
    State.FarmMover = { Attachment = attachment, Velocity = mover }
    return mover
end

function xDTaraZ.Farm.DetachMover()
    local mover = State.FarmMover
    if mover then
        mover.Velocity:Destroy()
        mover.Attachment:Destroy()
        State.FarmMover = nil
    end
end

function xDTaraZ.Farm.GlideTo(position)
    local root = xDTaraZ.Util.Root()
    local mover = State.FarmMover
    if not root or not mover or mover.Velocity.Parent ~= root then
        xDTaraZ.Farm.DetachMover()
        mover = root and { Velocity = xDTaraZ.Farm.AttachMover(root) }
    end
    while mover and xDTaraZ.Farm.CanRun() and root.Parent do
        local delta = position - root.Position
        if delta.Magnitude <= Config.FarmArrive then
            break
        end
        mover.Velocity.VectorVelocity = delta.Unit * math.min(State.Opt.FarmSpeed, delta.Magnitude * Config.FarmBrake)
        RunService.Heartbeat:Wait()
    end
    if mover then
        mover.Velocity.VectorVelocity = Vector3.zero
    end
end

function xDTaraZ.Farm.Run()
    local root = xDTaraZ.Util.Root()
    if root then
        xDTaraZ.Farm.AttachMover(root)
    end
    xDTaraZ.Movement.RefreshNoclip()
    State.FarmHome = root and root.CFrame
    while xDTaraZ.Farm.CanRun() do
        local map, hrp = xDTaraZ.Round.Map(), xDTaraZ.Util.Root()
        local coin = map and hrp and xDTaraZ.Farm.NearestCoin(map, hrp.Position)
        if coin and not xDTaraZ.Util.Busy() then
            xDTaraZ.Farm.GlideTo(coin.Position)
            task.wait(Config.FarmSettle)
            State.SkippedCoins[coin] = os.clock()
        else
            local mover = State.FarmMover
            if mover then
                mover.Velocity.VectorVelocity = Vector3.zero
            end
            task.wait(Config.FarmIdleWait)
        end
    end
end

---Leaves the character standing on something: back to where the farm started when there is no ground below.
function xDTaraZ.Farm.Settle()
    local root, home = xDTaraZ.Util.Root(), State.FarmHome
    State.FarmHome = nil
    if not root then return end
    root.AssemblyLinearVelocity = Vector3.zero
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LocalPlayer.Character }
    local ground = workspace:Raycast(root.Position + Vector3.new(0, Config.FarmGroundLift, 0), Vector3.new(0, -Config.FarmGroundReach, 0), params)
    if ground or not home then return end
    root.CFrame = home
end

function xDTaraZ.Farm.Step()
    if State.FarmBusy or not xDTaraZ.Farm.CanRun() then return end
    State.FarmBusy = true
    task.spawn(function()
        local ok = xDTaraZ.Util.Try(xDTaraZ.Farm.Run)
        xDTaraZ.Farm.DetachMover()
        xDTaraZ.Farm.Settle()
        State.FarmBusy = false
        xDTaraZ.Movement.RefreshNoclip()

        local humanoid = xDTaraZ.Util.Humanoid()
        if ok and humanoid and State.Opt.ResetWhenFull and xDTaraZ.Farm.BagFull() then
            humanoid.Health = 0
        end
    end)
end

function xDTaraZ.Farm.InitBagTracking()
    if GameLib.CoinCollected then
        xDTaraZ.Util.Connect(GameLib.CoinCollected.OnClientEvent, function(_, current, maximum)
            State.Bag.Current = tonumber(current) or 0
            State.Bag.Max = tonumber(maximum) or 0
        end)
    end
    if GameLib.CoinsStarted then
        xDTaraZ.Util.Connect(GameLib.CoinsStarted.OnClientEvent, function()
            State.Bag.Current, State.Bag.Max = 0, 0
            table.clear(State.SkippedCoins)
        end)
    end
    if not GameLib.RoundStart then return end
    xDTaraZ.Util.Connect(GameLib.RoundStart.OnClientEvent, function()
        State.Bag.Current, State.Bag.Max = 0, 0
        table.clear(State.Roles)
    end)
end

function xDTaraZ.Movement.AntiFlingStep()
    if not State.Opt.AntiFling then
        return
    end
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player ~= LocalPlayer and player.Character
        if character then
            for _, part in ipairs(character:GetChildren()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                end
            end
        end
    end
    local root = xDTaraZ.Util.Root()
    if root and not xDTaraZ.Util.Busy() and not State.Opt.Fly and root.AssemblyLinearVelocity.Magnitude > Config.FlingVelocityCap then
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
end

---@return Player?  next victim with the knife, otherwise the murderer
function xDTaraZ.Aim.Target()
    if xDTaraZ.Murderer.Knife() then
        return xDTaraZ.Murderer.Victims()[1]
    end
    return xDTaraZ.Round.FindByRole("Murderer")
end

function xDTaraZ.Aim.Step(dt)
    if not State.Opt.Aimbot then
        return
    end
    local target = xDTaraZ.Aim.Target()
    local head = target and target.Character and target.Character:FindFirstChild("Head")
    if not head then
        return
    end
    local camera = workspace.CurrentCamera
    local goal = CFrame.lookAt(camera.CFrame.Position, head.Position)
    local alpha = 1 - (State.Opt.AimSmooth / 100) ^ (dt * 60)
    camera.CFrame = camera.CFrame:Lerp(goal, math.clamp(alpha, 0, 1))
end

function xDTaraZ.Visual.ClearXRay()
    for part, original in pairs(State.XRayParts) do
        if part.Parent then
            part.Transparency = original
        end
    end
    table.clear(State.XRayParts)
    State.XRayMap = nil
end

function xDTaraZ.Visual.XRayStep()
    if not State.Opt.XRay then
        if State.XRayMap then
            xDTaraZ.Visual.ClearXRay()
        end
        return
    end
    local map = xDTaraZ.Round.Map() or xDTaraZ.Round.Lobby()
    if not map or State.XRayMap == map then
        return
    end
    xDTaraZ.Visual.ClearXRay()
    State.XRayMap = map
    local coins = map:FindFirstChild("CoinContainer")
    for _, part in ipairs(map:GetDescendants()) do
        if part:IsA("BasePart") and not (coins and part:IsDescendantOf(coins)) then
            State.XRayParts[part] = part.Transparency
            part.Transparency = math.max(part.Transparency, Config.XRayTransparency)
        end
    end
end

function xDTaraZ.Skin.MeshOf(tool)
    local handle = tool and tool:FindFirstChild("Handle")
    return handle and handle:FindFirstChildWhichIsA("SpecialMesh")
end

function xDTaraZ.Skin.Copy(sourceName, weaponName)
    local source = sourceName and Players:FindFirstChild(sourceName)
    local mesh = source and xDTaraZ.Skin.MeshOf(xDTaraZ.Util.Tool(source, weaponName))
    if not mesh then
        return false
    end
    State.Skins[weaponName] = { MeshId = mesh.MeshId, TextureId = mesh.TextureId, Scale = mesh.Scale }
    return true
end

function xDTaraZ.Skin.ApplyStep()
    for weaponName, look in pairs(State.Skins) do
        local mesh = xDTaraZ.Skin.MeshOf(xDTaraZ.Util.Tool(LocalPlayer, weaponName))
        if mesh and mesh.MeshId ~= look.MeshId then
            mesh.MeshId, mesh.TextureId, mesh.Scale = look.MeshId, look.TextureId, look.Scale
        end
    end
end

function xDTaraZ.Troll.Target()
    return State.Opt.TrollTarget and Players:FindFirstChild(State.Opt.TrollTarget)
end

function xDTaraZ.Troll.Fling(target)
    local root, targetRoot = xDTaraZ.Util.Root(), xDTaraZ.Util.Root(target)
    if not root or not targetRoot or xDTaraZ.Util.Busy() then
        return false
    end
    xDTaraZ.Util.SetBusy(true)
    local home = root.CFrame
    local spin = Instance.new("BodyAngularVelocity")
    spin.MaxTorque = Vector3.one * math.huge
    spin.AngularVelocity = Vector3.new(0, Config.FlingForce, 0)
    spin.Parent = root
    xDTaraZ.Movement.SetNoclip(true)
    local started = os.clock()
    while os.clock() - started < Config.FlingTime do
        local currentTarget = xDTaraZ.Util.Root(target)
        if not currentTarget or not root.Parent then
            break
        end
        root.CFrame = currentTarget.CFrame
        root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        RunService.Heartbeat:Wait()
    end
    spin:Destroy()
    if root.Parent then
        root.AssemblyAngularVelocity = Vector3.zero
        root.AssemblyLinearVelocity = Vector3.zero
        root.CFrame = home
    end
    xDTaraZ.Util.SetBusy(false)
    xDTaraZ.Movement.RefreshNoclip()
    return true
end

function xDTaraZ.Troll.Spectate(target)
    local humanoid = target and xDTaraZ.Util.Humanoid(target) or xDTaraZ.Util.Humanoid()
    if humanoid then
        workspace.CurrentCamera.CameraSubject = humanoid
    end
end

function xDTaraZ.Troll.StickStep()
    local target = State.StickTarget and Players:FindFirstChild(State.StickTarget)
    local root, targetRoot = xDTaraZ.Util.Root(), target and xDTaraZ.Util.Root(target)
    if root and targetRoot and not xDTaraZ.Util.Busy() then
        root.CFrame = targetRoot.CFrame * CFrame.new(0, 0, 2)
    end
end

function xDTaraZ.Teleport.To(cframe)
    local root = xDTaraZ.Util.Root()
    if root and cframe then
        root.CFrame = cframe + Vector3.new(0, 3, 0)
        return true
    end
    return false
end

function xDTaraZ.Teleport.ToPlayer(name)
    local player = name and Players:FindFirstChild(name)
    local root = player and xDTaraZ.Util.Root(player)
    return xDTaraZ.Teleport.To(root and root.CFrame)
end

function xDTaraZ.Teleport.ToLobby()
    local lobby = xDTaraZ.Round.Lobby()
    local spawnPart = lobby and (lobby:FindFirstChild("Spawns", true) or lobby:FindFirstChildWhichIsA("SpawnLocation", true))
    local part = spawnPart and (spawnPart:IsA("BasePart") and spawnPart or spawnPart:FindFirstChildWhichIsA("BasePart"))
    if not part and lobby then
        part = lobby:FindFirstChildWhichIsA("BasePart", true)
    end
    return xDTaraZ.Teleport.To(part and part.CFrame)
end

function xDTaraZ.Teleport.ToMap()
    local map = xDTaraZ.Round.Map()
    local spawns = map and map:FindFirstChild("Spawns")
    local part = spawns and spawns:FindFirstChildWhichIsA("BasePart") or (map and map.CoinContainer:FindFirstChildWhichIsA("BasePart"))
    return xDTaraZ.Teleport.To(part and part.CFrame)
end

function xDTaraZ.Esp.Init()
    xDTaraZ.Esp.Folder = Instance.new("Folder")
    xDTaraZ.Esp.Folder.Name = HttpService:GenerateGUID(false)
    xDTaraZ.Util.Mount(xDTaraZ.Esp.Folder)
end

function xDTaraZ.Esp.MakeHighlight(adornee, color)
    local highlight = Instance.new("Highlight")
    highlight.FillColor = color
    highlight.OutlineColor = color
    highlight.FillTransparency = 0.65
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Adornee = adornee
    highlight.Parent = xDTaraZ.Esp.Folder
    return highlight
end

function xDTaraZ.Esp.MakeLabel(adornee, color)
    local gui = Instance.new("BillboardGui")
    gui.Size = UDim2.fromOffset(180, 36)
    gui.StudsOffset = Vector3.new(0, 3.5, 0)
    gui.AlwaysOnTop = true
    gui.Adornee = adornee
    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.TextColor3 = color
    label.TextStrokeTransparency = 0.4
    label.Font = Enum.Font.GothamBold
    label.TextSize = 13
    label.Parent = gui
    gui.Parent = xDTaraZ.Esp.Folder
    return gui, label
end

function xDTaraZ.Esp.DropEntry(entry)
    if entry then
        entry.Highlight:Destroy()
        entry.Gui:Destroy()
    end
end

function xDTaraZ.Esp.RefreshPlayers()
    local entries = State.Esp.Players
    local myRoot = xDTaraZ.Util.Root()
    for _, player in ipairs(Players:GetPlayers()) do
        local character, root = player.Character, xDTaraZ.Util.Root(player)
        local entry = entries[player]
        local role = xDTaraZ.Round.RoleOf(player)
        local visible = State.Opt.EspPlayers and player ~= LocalPlayer and character and root and role ~= "Dead"
        if not visible then
            xDTaraZ.Esp.DropEntry(entry)
            entries[player] = nil
        else
            if not entry or entry.Character ~= character then
                xDTaraZ.Esp.DropEntry(entry)
                local gui, label = xDTaraZ.Esp.MakeLabel(root, Color3.new(1, 1, 1))
                entry = { Character = character, Highlight = xDTaraZ.Esp.MakeHighlight(character, Color3.new(1, 1, 1)), Gui = gui, Label = label }
                entries[player] = entry
            end
            local color = Config.Colors[role] or Config.Colors.Innocent
            local distance = myRoot and math.floor((root.Position - myRoot.Position).Magnitude) or 0
            entry.Highlight.FillColor, entry.Highlight.OutlineColor, entry.Label.TextColor3 = color, color, color
            entry.Label.Text = string.format("%s [%s] %dm", player.DisplayName, role, distance)
        end
    end
    for player, entry in pairs(entries) do
        if not player.Parent then
            xDTaraZ.Esp.DropEntry(entry)
            entries[player] = nil
        end
    end
end

function xDTaraZ.Esp.RefreshGun()
    local drop = State.Opt.EspGun and xDTaraZ.Round.GunDrop()
    local entry = State.Esp.Gun
    if entry and entry.Adornee == drop then
        return
    end
    xDTaraZ.Esp.DropEntry(entry)
    State.Esp.Gun = nil
    if drop then
        local gui, label = xDTaraZ.Esp.MakeLabel(drop, Config.Colors.Gun)
        label.Text = "GUN DROP"
        State.Esp.Gun = { Adornee = drop, Highlight = xDTaraZ.Esp.MakeHighlight(drop, Config.Colors.Gun), Gui = gui }
    end
end

function xDTaraZ.Esp.Destroy()
    if xDTaraZ.Esp.Folder then
        xDTaraZ.Esp.Folder:Destroy()
    end
    table.clear(State.Esp.Players)
    State.Esp.Gun = nil
end

function xDTaraZ.Visual.SetFullbright(enabled)
    if enabled and not State.LightingDefaults then
        State.LightingDefaults = { Ambient = Lighting.Ambient, Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime, FogEnd = Lighting.FogEnd, GlobalShadows = Lighting.GlobalShadows }
        Lighting.Ambient = Color3.new(1, 1, 1)
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.FogEnd = 1e9
        Lighting.GlobalShadows = false
    elseif not enabled and State.LightingDefaults then
        for property, value in pairs(State.LightingDefaults) do
            Lighting[property] = value
        end
        State.LightingDefaults = nil
    end
end

function xDTaraZ.Session.RedeemCode(code)
    local remote = GameLib.RedeemCode
    if not remote then return "The code box was not found in this game version" end
    local ok, message = pcall(remote.InvokeServer, remote, code)
    return ok and tostring(message) or "Request failed"
end

function xDTaraZ.Session.Rejoin()
    TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
end

function xDTaraZ.Session.Hop()
    local url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&limit=100", game.PlaceId)
    local body = xDTaraZ.Util.HttpGet(url)
    local ok, servers = pcall(HttpService.JSONDecode, HttpService, body or "")
    if not ok or type(servers) ~= "table" then
        return
    end
    for _, server in ipairs(servers.data or {}) do
        if server.id ~= game.JobId and server.playing < server.maxPlayers then
            TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, LocalPlayer)
            return
        end
    end
end

function xDTaraZ.Session.InitAntiAfk()
    xDTaraZ.Util.Connect(LocalPlayer.Idled, function()
        if State.Opt.AntiAfk then
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end
    end)
end

function xDTaraZ.Session.InitRoleNotify(notify)
    if not GameLib.RoundStart then return end
    xDTaraZ.Util.Connect(GameLib.RoundStart.OnClientEvent, function()
        task.wait(2)
        State.LastRoleFetch = 0
        xDTaraZ.Round.RefreshRoles()
        if not State.Opt.RoleNotify then
            return
        end
        local murderer, sheriff = xDTaraZ.Round.FindByRole("Murderer"), xDTaraZ.Round.FindByRole("Sheriff")
        notify(string.format("Murderer: %s | Sheriff: %s | You: %s", murderer and murderer.Name or "?", sheriff and sheriff.Name or "?", xDTaraZ.Round.RoleOf(LocalPlayer)))
    end)
end

xDTaraZ.Scheduler.Jobs = {
    Tick = {
        { "Roles", xDTaraZ.Round.RefreshRoles },
        { "Auto Win", xDTaraZ.Kaitun.Step, "Kaitun" },
        { "Auto Farm", xDTaraZ.Farm.Step, "AutoFarm" },
        { "X-Ray", xDTaraZ.Visual.XRayStep, "XRay" },
        { "Skins", xDTaraZ.Skin.ApplyStep },
        { "Movement", xDTaraZ.Movement.Apply, { "SpeedOn", "JumpOn" } },
        { "Auto Grab Gun", xDTaraZ.Sheriff.AutoGrabStep, "AutoGrabGun" },
        { "Auto Shoot", xDTaraZ.Sheriff.AutoShootStep, "AutoShoot" },
        { "Auto Kill All", xDTaraZ.Murderer.AutoKillStep, "AutoKillAll" },
        { "Role ESP", xDTaraZ.Esp.RefreshPlayers, "EspPlayers" },
        { "Gun ESP", xDTaraZ.Esp.RefreshGun, "EspGun" },
    },
    Stepped = { { "Anti Fling", xDTaraZ.Movement.AntiFlingStep, "AntiFling" } },
    Render = { { "Aimbot", xDTaraZ.Aim.Step, "Aimbot" } },
    Heartbeat = {
        { "Kill Aura", xDTaraZ.Murderer.KillAuraStep, "KillAura" },
        { "Auto Dodge", xDTaraZ.Survive.DodgeStep, "AutoDodge" },
        { "Stick To Player", xDTaraZ.Troll.StickStep, "StickTo" },
    },
}

---@param job table  { label, step, toggle idx or list }
---@return table     toggles of the job that are on
function xDTaraZ.Scheduler.OnToggles(job)
    local on = {}
    if not xDTaraZ.Library or job[3] == nil then return on end
    for _, idx in ipairs(type(job[3]) == "table" and job[3] or { job[3] }) do
        local toggle = xDTaraZ.Library.Toggles[idx]
        if toggle and toggle.Value then
            on[#on + 1] = toggle
        end
    end
    return on
end

---Queues the job's toggles to be switched off by the UI pump (their callbacks restore the game state); a job with none on rests until one turns on.
function xDTaraZ.Scheduler.Halt(job, err)
    local reason = tostring(err):match("^[^\n]*")
    job.Streak = nil
    if #xDTaraZ.Scheduler.OnToggles(job) == 0 then
        job.Stopped = true
        warn("[MM2] " .. job[1] .. " paused until turned on:", reason)
        return
    end

    job.Halting = true
    warn("[MM2] " .. job[1] .. " stopped:", reason)
    table.insert(State.Halted, { job, reason })
end

---@param job table  { label, step, toggle idx or list }; toggle jobs halt after Config.JobFailLimit errors spanning Config.JobFailWindow seconds
function xDTaraZ.Scheduler.Run(job, ...)
    if job.Halting then return end
    if job.Stopped then
        if #xDTaraZ.Scheduler.OnToggles(job) == 0 then return end
        job.Stopped = nil
    end

    local ok, err = pcall(job[2], ...)
    if ok then
        job.Streak = nil
        return
    end

    local streak = job.Streak
    if not streak then
        streak = { count = 0, since = os.clock() }
        job.Streak = streak
        warn("[MM2] " .. job[1] .. ":", err)
    end
    streak.count += 1
    if job[3] == nil or streak.count < Config.JobFailLimit or os.clock() - streak.since < Config.JobFailWindow then return end
    xDTaraZ.Scheduler.Halt(job, err)
end

function xDTaraZ.Scheduler.RunLane(lane, ...)
    for _, job in ipairs(xDTaraZ.Scheduler.Jobs[lane]) do
        xDTaraZ.Scheduler.Run(job, ...)
    end
end

function xDTaraZ.Scheduler.Boot(notify)
    xDTaraZ.Esp.Init()
    xDTaraZ.Farm.InitBagTracking()
    xDTaraZ.Util.Connect(RunService.Stepped, function()
        xDTaraZ.Scheduler.RunLane("Stepped")
    end)
    xDTaraZ.Movement.InitInfJump()
    xDTaraZ.Session.InitAntiAfk()
    xDTaraZ.Session.InitRoleNotify(notify)
    xDTaraZ.Util.Connect(RunService.RenderStepped, function(dt)
        xDTaraZ.Scheduler.RunLane("Render", dt)
    end)
    xDTaraZ.Util.Connect(RunService.Heartbeat, function()
        xDTaraZ.Scheduler.RunLane("Heartbeat")
    end)
    task.spawn(function()
        while State.Alive do
            xDTaraZ.Scheduler.RunLane("Tick")
            task.wait(Config.TickDelay)
        end
    end)
end

function xDTaraZ.Scheduler.Stop()
    State.Alive = false
    getgenv().MurderMystery2Unload = nil
    xDTaraZ.Sheriff.SyncAimHook()
    State.StickTarget = nil
    xDTaraZ.Movement.SetFly(false)
    xDTaraZ.Movement.SetNoclip(false)
    for _, conn in ipairs(State.Conns) do
        conn:Disconnect()
    end
    table.clear(State.Conns)
    if State.Opt.SpeedOn then
        xDTaraZ.Movement.RestoreSpeed()
    end
    if State.Opt.JumpOn then
        xDTaraZ.Movement.RestoreJump()
    end
    xDTaraZ.Troll.Spectate(nil)
    xDTaraZ.Visual.SetFullbright(false)
    xDTaraZ.Visual.ClearXRay()
    xDTaraZ.Farm.DetachMover()
    xDTaraZ.Esp.Destroy()
end

local function BuildInterface()
    local Library = xDTaraZ.Util.LoadLibrary()
    if not Library then return false end
    xDTaraZ.Library = Library
    pcall(NovaBanner.Step, "UI library")
    local T = function(en, th) return Library:T(en, th) end
    local opt = State.Opt
    local live = {}

    local function Notify(text, kind)
        Library:Notify("Murder Mystery 2", text, 5, kind or "Info")
    end

    local function Bind(idx)
        return function(value)
            opt[idx] = value
        end
    end

    local function AimHookBind(idx)
        return function(value)
            opt[idx] = value
            xDTaraZ.Sheriff.SyncAimHook()
        end
    end

    ---@return string?  live dropdown value, the list can change without a callback
    local function Picked(idx)
        local option = Library.Options[idx]
        opt[idx] = option and option.Value or nil
        return opt[idx]
    end

    local function FlingAsync(target)
        if target then task.spawn(xDTaraZ.Troll.Fling, target) end
    end

    local function BuildCombatTab(window)
        local tab = window:AddTab(T("Combat", "ต่อสู้"), "crosshair", T("Sheriff and murderer tools", "เครื่องมือนายอำเภอและฆาตกร"))

        local gunBox = tab:AddLeftGroupbox(T("Sheriff / Hero", "นายอำเภอ / ฮีโร่"))
        gunBox:AddToggle("SilentAim", {
            Text = T("Silent Aim", "ยิงล็อกเป้า"),
            Description = T("Every shot you fire goes to the murderer", "ทุกนัดที่ยิงไปโดนฆาตกร"),
            Default = false,
            Callback = AimHookBind("SilentAim"),
        }):AddKeyPicker("SilentAimKey", { Default = "None", Mode = "Toggle" })
        Library.Compat.NeedCap("SilentAim", { "Namecall", "CheckCaller" })
        gunBox:AddToggle("AutoShoot", {
            Text = T("Auto Shoot Murderer", "ยิงฆาตกรอัตโนมัติ"),
            Description = T("Kills the murderer as soon as you hold the gun", "ยิงฆาตกรทันทีที่ได้ถือปืน"),
            Default = false,
            Risky = true,
            Callback = Bind("AutoShoot"),
        }):AddKeyPicker("AutoShootKey", { Default = "None", Mode = "Toggle" })
        gunBox:AddButton({ Text = T("Shoot Murderer Now", "ยิงฆาตกรเดี๋ยวนี้"), Style = "Primary", Func = function()
            local ok, detail = xDTaraZ.Sheriff.ShootMurderer()
            Notify(ok and ("Shot " .. tostring(detail)) or tostring(detail or "You need the gun"), ok and "Success" or "Warning")
        end })
        gunBox:AddToggle("AutoGrabGun", {
            Text = T("Auto Grab Gun", "เก็บปืนอัตโนมัติ"),
            Description = T("Picks up the dropped gun the moment the sheriff dies", "เก็บปืนที่ตกทันทีที่นายอำเภอตาย"),
            Default = false,
            Callback = Bind("AutoGrabGun"),
        }):AddKeyPicker("AutoGrabGunKey", { Default = "None", Mode = "Toggle" })
        gunBox:AddButton({ Text = T("Grab Gun Now", "เก็บปืนเดี๋ยวนี้"), Func = function()
            local got = xDTaraZ.Sheriff.GrabGun()
            Notify(got and "Gun grabbed" or "No gun on the ground", got and "Success" or "Warning")
        end })

        local knifeBox = tab:AddRightGroupbox(T("Murderer", "ฆาตกร"))
        knifeBox:AddToggle("AutoKillAll", {
            Text = T("Auto Kill All", "ฆ่าทุกคนอัตโนมัติ"),
            Description = T("Ends the round by killing everyone when you are the murderer", "จบรอบด้วยการฆ่าทุกคนเมื่อเราเป็นฆาตกร"),
            Default = false,
            Risky = true,
            Callback = Bind("AutoKillAll"),
        }):AddKeyPicker("AutoKillAllKey", { Default = "None", Mode = "Toggle" })
        knifeBox:AddButton({ Text = T("Kill All Now", "ฆ่าทุกคนเดี๋ยวนี้"), Style = "Primary", Func = function()
            task.spawn(function()
                Notify(string.format("Killed %d players", xDTaraZ.Murderer.KillAll()))
            end)
        end })
        knifeBox:AddToggle("KillAura", {
            Text = T("Kill Aura", "ออร่าฆ่า"),
            Description = T("Kills anyone who gets close while you hold the knife", "ฆ่าใครก็ตามที่เข้าใกล้ตอนถือมีด"),
            Default = false,
            Risky = true,
            Callback = Bind("KillAura"),
        }):AddKeyPicker("KillAuraKey", { Default = "None", Mode = "Toggle" })
        knifeBox:AddToggle("KnifeAim", {
            Text = T("Knife Throw Aim", "ปามีดล็อกเป้า"),
            Description = T("Thrown knives fly to the nearest player", "มีดที่ปาพุ่งไปหาคนที่ใกล้ที่สุด"),
            Default = false,
            Callback = AimHookBind("KnifeAim"),
        })
        Library.Compat.NeedCap("KnifeAim", { "Namecall", "CheckCaller" })

        local aimBox = tab:AddRightGroupbox(T("Aimbot", "ล็อกกล้อง"))
        aimBox:AddToggle("Aimbot", {
            Text = T("Aimbot", "ล็อกกล้อง"),
            Description = T("Locks your camera on the murderer, or on the next victim when you hold the knife", "ล็อกกล้องไปที่ฆาตกร หรือเหยื่อคนถัดไปตอนถือมีด"),
            Default = false,
            Callback = Bind("Aimbot"),
        }):AddKeyPicker("AimbotKey", { Default = "Q", Mode = "Hold" })
        aimBox:AddSlider("AimSmooth", {
            Text = T("Smoothness", "ความนุ่ม"),
            Min = 0, Max = 95, Default = opt.AimSmooth, Rounding = 0, Suffix = "%",
            Callback = function(value)
                opt.AimSmooth = tonumber(value) or 0
            end,
        })

        local smartBox = tab:AddLeftGroupbox(T("Auto Play", "เล่นอัตโนมัติ"))
        smartBox:AddToggle("Kaitun", {
            Text = T("Auto Win", "ชนะอัตโนมัติ"),
            Description = T("Plays every round for you in any role", "เล่นทุกรอบให้เองทุกบทบาท"),
            Default = false,
            Risky = true,
            Callback = function(value)
                opt.Kaitun = value
                if value then
                    return
                end
                for _, idx in ipairs({ "AutoKillAll", "AutoShoot", "AutoGrabGun", "AutoDodge", "AutoFarm" }) do
                    opt[idx] = Library.Options[idx].Value
                end
            end,
        }):AddKeyPicker("KaitunKey", { Default = "None", Mode = "Toggle" })
        smartBox:AddToggle("AutoDodge", {
            Text = T("Auto Dodge Murderer", "หลบฆาตกรอัตโนมัติ"),
            Description = T("Escapes to the far side of the map when the murderer gets close", "หนีไปอีกฝั่งของแมพเมื่อฆาตกรเข้าใกล้"),
            Default = false,
            Callback = Bind("AutoDodge"),
        }):AddKeyPicker("AutoDodgeKey", { Default = "None", Mode = "Toggle" })
    end

    local function BuildTeleportTab(window)
        local tab = window:AddTab(T("Teleport", "วาร์ป"), "globe", T("Map, lobby and players", "แมพ ล็อบบี้ และผู้เล่น"))

        local placeBox = tab:AddLeftGroupbox(T("Places", "สถานที่"))
        placeBox:AddButton({ Text = T("Lobby", "ล็อบบี้"), Func = xDTaraZ.Teleport.ToLobby }):AddButton({ Text = T("Map", "แมพ"), Func = xDTaraZ.Teleport.ToMap })
        placeBox:AddButton({ Text = T("To Murderer", "ไปหาฆาตกร"), Func = function()
            local target = xDTaraZ.Round.FindByRole("Murderer")
            xDTaraZ.Teleport.ToPlayer(target and target.Name)
        end }):AddButton({ Text = T("To Sheriff", "ไปหานายอำเภอ"), Func = function()
            local target = xDTaraZ.Round.FindByRole("Sheriff")
            xDTaraZ.Teleport.ToPlayer(target and target.Name)
        end })

        local playerBox = tab:AddRightGroupbox(T("Players", "ผู้เล่น"))
        playerBox:AddDropdown("TeleportTarget", {
            Text = T("Player", "ผู้เล่น"),
            SpecialType = "Player",
            Searchable = true,
            Callback = Bind("TeleportTarget"),
        })
        playerBox:AddButton({ Text = T("Teleport", "วาร์ป"), Style = "Primary", Func = function()
            xDTaraZ.Teleport.ToPlayer(Picked("TeleportTarget"))
        end })
    end

    local function BuildTrollTab(window)
        local tab = window:AddTab(T("Troll", "ป่วน"), "zap", T("Fling, stick and spectate", "ดีด เกาะติด และส่อง"))

        local box = tab:AddLeftGroupbox(T("Target", "เป้าหมาย"))
        box:AddDropdown("TrollTarget", {
            Text = T("Player", "ผู้เล่น"),
            SpecialType = "Player",
            Searchable = true,
            Callback = function(value)
                opt.TrollTarget = value
                local stick, spectate = Library.Options.StickTo, Library.Options.Spectate
                if stick and stick.Value then State.StickTarget = value end
                if spectate and spectate.Value then xDTaraZ.Troll.Spectate(xDTaraZ.Troll.Target()) end
            end,
        })
        box:AddButton({ Text = T("Fling", "ดีดกระเด็น"), Style = "Primary", Func = function()
            Picked("TrollTarget")
            FlingAsync(xDTaraZ.Troll.Target())
        end }):AddButton({ Text = T("Fling Murderer", "ดีดฆาตกร"), Func = function()
            FlingAsync(xDTaraZ.Round.FindByRole("Murderer"))
        end })
        box:AddButton({ Text = T("Fling Everyone", "ดีดทุกคน"), Style = "Warning", DoubleClick = true, Func = function()
            task.spawn(function()
                for _, player in ipairs(Players:GetPlayers()) do
                    if player == LocalPlayer or not xDTaraZ.Util.Root(player) then continue end
                    xDTaraZ.Troll.Fling(player)
                end
            end)
        end })

        local followBox = tab:AddRightGroupbox(T("Follow", "ติดตาม"))
        followBox:AddToggle("StickTo", {
            Text = T("Stick To Player", "เกาะติดผู้เล่น"),
            Description = T("Stays glued right behind the selected player", "เกาะอยู่ข้างหลังผู้เล่นที่เลือกตลอด"),
            Default = false,
            Callback = function(value)
                State.StickTarget = value and Picked("TrollTarget") or nil
            end,
        })
        followBox:AddToggle("Spectate", {
            Text = T("Spectate", "ส่องผู้เล่น"),
            Default = false,
            Callback = function(value)
                Picked("TrollTarget")
                xDTaraZ.Troll.Spectate(value and xDTaraZ.Troll.Target() or nil)
            end,
        })
    end

    local function BuildPlayerTab(window)
        local tab = window:AddTab(T("Player", "ผู้เล่น"), "user", T("Movement", "การเคลื่อนที่"))

        local moveBox = tab:AddLeftGroupbox(T("Movement", "การเคลื่อนที่"))
        moveBox:AddToggle("SpeedOn", {
            Text = T("Walk Speed", "ความเร็วเดิน"),
            Default = false,
            Callback = function(value)
                opt.SpeedOn = value
                if not value then
                    xDTaraZ.Movement.RestoreSpeed()
                end
            end,
        })
        moveBox:AddSlider("WalkSpeed", {
            Text = T("Speed", "ความเร็ว"), Min = 16, Max = 120, Default = opt.WalkSpeed, Rounding = 0,
            Callback = function(value)
                opt.WalkSpeed = tonumber(value) or Config.SpeedDefault
            end,
        })
        moveBox:AddToggle("JumpOn", {
            Text = T("Jump Power", "แรงกระโดด"),
            Default = false,
            Callback = function(value)
                opt.JumpOn = value
                if not value then
                    xDTaraZ.Movement.RestoreJump()
                end
            end,
        })
        moveBox:AddSlider("JumpPower", {
            Text = T("Power", "แรง"), Min = 50, Max = 200, Default = opt.JumpPower, Rounding = 0,
            Callback = function(value)
                opt.JumpPower = tonumber(value) or Config.JumpDefault
            end,
        })

        local extraBox = tab:AddRightGroupbox(T("Extra", "เพิ่มเติม"))
        extraBox:AddToggle("AntiFling", {
            Text = T("Anti Fling", "กันโดนดีด"),
            Description = T("Other players cannot push or launch you", "ผู้เล่นอื่นดันหรือดีดเราไม่ได้"),
            Default = false,
            Callback = Bind("AntiFling"),
        })
        extraBox:AddToggle("InfJump", { Text = T("Infinite Jump", "กระโดดไม่จำกัด"), Default = false, Callback = Bind("InfJump") })
        extraBox:AddToggle("Noclip", {
            Text = T("Noclip", "ทะลุวัตถุ"),
            Default = false,
            Callback = function(value)
                opt.Noclip = value
                xDTaraZ.Movement.RefreshNoclip()
            end,
        }):AddKeyPicker("NoclipKey", { Default = "None", Mode = "Toggle" })
        extraBox:AddToggle("Fly", {
            Text = T("Fly", "บิน"),
            Description = T("Space to go up, Left Ctrl to go down", "Space ขึ้น, Left Ctrl ลง"),
            Default = false,
            Callback = function(value)
                opt.Fly = value
                xDTaraZ.Movement.SetFly(value)
            end,
        }):AddKeyPicker("FlyKey", { Default = "None", Mode = "Toggle" })
    end

    local function BuildVisualTab(window)
        local tab = window:AddTab(T("Visuals", "ภาพ"), "eye", T("Roles and gun", "บทบาทและปืน"))

        local espBox = tab:AddLeftGroupbox(T("ESP", "ESP"))
        espBox:AddToggle("EspPlayers", {
            Text = T("Role ESP", "มองเห็นบทบาท"),
            Description = T("Murderer red, sheriff blue, hero yellow, innocents green", "ฆาตกรแดง นายอำเภอน้ำเงิน ฮีโร่เหลือง คนธรรมดาเขียว"),
            Default = false,
            Callback = Bind("EspPlayers"),
        })
        espBox:AddToggle("EspGun", {
            Text = T("Gun Drop ESP", "มองเห็นปืนที่ตก"),
            Default = false,
            Callback = Bind("EspGun"),
        })
        espBox:AddToggle("RoleNotify", {
            Text = T("Role Notify", "แจ้งบทบาท"),
            Description = T("Tells you who the murderer and sheriff are at round start", "บอกว่าใครเป็นฆาตกรและนายอำเภอตอนเริ่มรอบ"),
            Default = false,
            Callback = Bind("RoleNotify"),
        })

        local worldBox = tab:AddRightGroupbox(T("World", "โลก"))
        worldBox:AddToggle("XRay", {
            Text = T("X-Ray", "มองทะลุ"),
            Description = T("See through walls on every map", "มองทะลุกำแพงได้ทุกแมพ"),
            Default = false,
            Callback = Bind("XRay"),
        })
        worldBox:AddToggle("Fullbright", {
            Text = T("Fullbright", "สว่างเต็มจอ"),
            Default = false,
            Callback = function(value)
                opt.Fullbright = value
                xDTaraZ.Visual.SetFullbright(value)
            end,
        })

        local skinBox = tab:AddRightGroupbox(T("Skins", "สกิน"))
        skinBox:AddDropdown("SkinSource", {
            Text = T("Copy From", "ก๊อปจาก"),
            SpecialType = "Player",
            Searchable = true,
            Callback = Bind("SkinSource"),
        })
        skinBox:AddButton({ Text = T("Copy Knife", "ก๊อปมีด"), Style = "Primary", Func = function()
            local ok = xDTaraZ.Skin.Copy(Picked("SkinSource"), "Knife")
            Notify(ok and "Knife skin applied" or "That player has no knife loaded", ok and "Success" or "Warning")
        end }):AddButton({ Text = T("Copy Gun", "ก๊อปปืน"), Func = function()
            local ok = xDTaraZ.Skin.Copy(Picked("SkinSource"), "Gun")
            Notify(ok and "Gun skin applied" or "That player has no gun loaded", ok and "Success" or "Warning")
        end })
        skinBox:AddButton({ Text = T("Reset Skins", "รีเซ็ตสกิน"), Func = function()
            table.clear(State.Skins)
        end })
    end

    local function BuildFarmTab(window)
        local tab = window:AddTab(T("Farm", "ฟาร์ม"), "cookie", T("Coins every round", "เหรียญทุกรอบ"))

        local coinBox = tab:AddLeftGroupbox(T("Coin Farm", "ฟาร์มเหรียญ"))
        coinBox:AddToggle("AutoFarm", {
            Text = T("Auto Farm Coins", "ฟาร์มเหรียญอัตโนมัติ"),
            Description = T("Glides smoothly to every coin until your bag is full and stays away from the murderer", "ไหลไปเก็บเหรียญทุกเหรียญจนเต็มถุง และอยู่ห่างจากฆาตกร"),
            Default = false,
            Callback = Bind("AutoFarm"),
        }):AddKeyPicker("AutoFarmKey", { Default = "None", Mode = "Toggle" })
        coinBox:AddSlider("FarmSpeed", {
            Text = T("Farm Speed", "ความเร็วฟาร์ม"),
            Min = 16, Max = Config.FarmSpeedMax, Default = Config.FarmSpeed, Rounding = 0,
            Callback = function(value)
                opt.FarmSpeed = tonumber(value) or Config.FarmSpeed
            end,
        })
        coinBox:AddToggle("ResetWhenFull", {
            Text = T("Reset When Bag Full", "รีเซ็ตตัวเมื่อถุงเต็ม"),
            Description = T("Respawns after the bag fills so the murderer cannot catch you", "เกิดใหม่หลังถุงเต็ม ฆาตกรจะได้ตามไม่ทัน"),
            Default = false,
            Callback = Bind("ResetWhenFull"),
        })
        live.Bag = coinBox:AddProgressBar("StatusBag", { Text = T("Coin Bag", "ถุงเหรียญ"), Max = 1, Default = 0 })

        local discordBox = tab:AddRightGroupbox("Discord", "link")
        discordBox:AddLabel(Config.Discord)
        discordBox:AddButton({ Text = T("Copy Discord Link", "คัดลอกลิงก์ Discord"), Style = "Primary", Func = function()
            local copy = setclipboard or toclipboard
            if copy then copy(Config.Discord) end
            Notify(copy and "Discord link copied" or Config.Discord)
        end })

        local logBox = tab:AddRightGroupbox(T("Update Log", "อัปเดตล่าสุด"), "bell")
        for i = 1, math.min(2, #Config.UpdateLog) do
            local entry = Config.UpdateLog[i]
            logBox:AddParagraph({ Title = entry[1], Content = entry[2] })
        end

        local roundBox = tab:AddRightGroupbox(T("Round", "รอบนี้"))
        live.Role = roundBox:AddLabel("You: -")
        live.Murderer = roundBox:AddLabel("Murderer: ?")
        live.Sheriff = roundBox:AddLabel("Sheriff: ?")
        live.BagCount = roundBox:AddLabel("Bag: 0 / 0")
    end

    local function BuildMiscTab(window)
        local tab = window:AddTab(T("Misc", "อื่นๆ"), "sliders-horizontal", T("Session tools", "เครื่องมือเซสชัน"))

        local box = tab:AddLeftGroupbox(T("Session", "เซสชัน"))
        box:AddToggle("AntiAfk", {
            Text = T("Anti AFK", "กันหลุด AFK"),
            Default = false,
            Callback = Bind("AntiAfk"),
        })
        box:AddButton({ Text = T("Rejoin", "เข้าเซิร์ฟเดิมใหม่"), DoubleClick = true, Func = xDTaraZ.Session.Rejoin })
            :AddButton({ Text = T("Server Hop", "ย้ายเซิร์ฟ"), DoubleClick = true, Func = xDTaraZ.Session.Hop })
        box:AddButton({ Text = T("Panic - All Off", "ฉุกเฉิน ปิดทั้งหมด"), Style = "Danger", Func = function()
            for _, toggle in pairs(Library.Toggles) do
                if toggle.Value == true then toggle:SetValue(false) end
            end
        end })

        local codeBox = tab:AddRightGroupbox(T("Codes", "โค้ด"))
        local codeText = ""
        codeBox:AddInput("RedeemCodeInput", {
            Text = T("Code", "โค้ด"),
            Default = "",
            Placeholder = T("Enter code", "ใส่โค้ด"),
            NoSave = true,
            Callback = function(value)
                codeText = value
            end,
        })
        codeBox:AddButton({ Text = T("Redeem", "ใช้โค้ด"), Style = "Primary", Func = function()
            if codeText == "" then return end
            Notify(xDTaraZ.Session.RedeemCode(codeText))
        end })
    end

    local function ReportHalts()
        while #State.Halted > 0 do
            local halt = table.remove(State.Halted, 1)
            local job = halt[1]
            for _, toggle in ipairs(xDTaraZ.Scheduler.OnToggles(job)) do
                toggle:SetValue(false)
            end
            job.Halting = nil
            Notify(job[1] .. " stopped: " .. halt[2], "Warning")
        end
    end

    local shown = {}
    local function Show(key, text)
        if shown[key] == text or not live[key] then return end
        shown[key] = text
        live[key]:SetText(text)
    end

    local function RefreshRound()
        local running = xDTaraZ.Round.Map() ~= nil
        local murderer = running and xDTaraZ.Round.FindByRole("Murderer")
        local sheriff = running and (xDTaraZ.Round.FindByRole("Sheriff") or xDTaraZ.Round.FindByRole("Hero"))
        local role = xDTaraZ.Round.IAmPlaying() and tostring(xDTaraZ.Round.RoleOf(LocalPlayer)) or "Lobby"
        local current, capacity = running and State.Bag.Current or 0, running and State.Bag.Max or 0
        Show("Role", "You: " .. role)
        Show("Murderer", "Murderer: " .. (murderer and murderer.Name or "?"))
        Show("Sheriff", "Sheriff: " .. (sheriff and sheriff.Name or "?"))
        Show("BagCount", string.format("Bag: %d / %d", current, capacity))

        local fill = capacity > 0 and math.min(current / capacity, 1) or 0
        if live.Bag and live.Bag.Value ~= fill then
            live.Bag:SetValue(fill)
        end
    end

    local function GateRemotes()
        local reason = T("Not found after a game update", "หาไม่เจอหลังเกมอัปเดต")
        for idx in pairs(GameLib.Needs) do
            local missing = GameLib.Missing(idx)
            if missing and Library.Options[idx] then
                Library.Compat.Block(idx, reason)
                warn("[MM2] " .. idx .. " off, missing remote " .. missing)
            end
        end
        for _, name in ipairs({ "PlayerData", "CoinsStarted", "RedeemCode" }) do
            if not GameLib[name] then warn("[MM2] missing remote " .. name) end
        end
    end

    local function StartLive()
        Library:Every(Config.StatusRefresh, function()
            ReportHalts()
            if live.Role then RefreshRound() end
        end)
    end

    local function BuildTabs()
        local window = Library.Window
        window:AddTabSection(T("Game", "เกม"))
        xDTaraZ.Util.Try(BuildFarmTab, window)
        xDTaraZ.Util.Try(BuildCombatTab, window)
        xDTaraZ.Util.Try(BuildTeleportTab, window)
        xDTaraZ.Util.Try(BuildTrollTab, window)
        window:AddTabSection(T("Other", "อื่นๆ"))
        xDTaraZ.Util.Try(BuildPlayerTab, window)
        xDTaraZ.Util.Try(BuildVisualTab, window)
        xDTaraZ.Util.Try(BuildMiscTab, window)
        xDTaraZ.Util.Try(window.AddSettingsTab, window)
        xDTaraZ.Util.Try(GateRemotes)
        xDTaraZ.Util.Try(StartLive)
    end

    Library:OnUnload(xDTaraZ.Scheduler.Stop)
    getgenv().MurderMystery2Unload = function()
        Library:Unload()
    end

    Library:CreateWindow({
        Title = "Nova Hub",
        SubTitle = "Murder Mystery 2 by xDTaraZ",
        MenuKey = Enum.KeyCode.LeftControl,
        ConfigFolder = Config.SaveFolder,
        Language = "Auto",
        Theme = "Nova",
        OnUnlocked = function()
            BuildTabs()
            xDTaraZ.Util.Try(xDTaraZ.Scheduler.Boot, Notify)
            Notify("Loaded")
            xDTaraZ.Util.Try(Library.LoadAutoloadConfig, Library)
        end,
    })
    return true
end

if getgenv().MurderMystery2Unload then
    pcall(getgenv().MurderMystery2Unload)
end

pcall(NovaBanner.Step, "Systems")
if BuildInterface() then
    pcall(NovaBanner.Step, "Interface")
    pcall(NovaBanner.Ready)
end]==]

NOVA_HUB_MODULES[1202096104] = [==[if not game:IsLoaded() then
    game.Loaded:Wait()
end

if game.GameId ~= 1202096104 then
    game:GetService("Players").LocalPlayer:Kick("Nova Hub : this script is for Driving Empire only")
    return
end

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
        "   DRIVING EMPIRE  //  by xDTaraZ  //  discord.gg/FHVfmeSceA",
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

if not LPH_OBFUSCATED then
    local function Passthrough(fn) return fn end
    LPH_JIT, LPH_JIT_MAX, LPH_NO_VIRTUALIZE = Passthrough, Passthrough, Passthrough
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local xDTaraZ = setmetatable({}, {
    __newindex = function(self, key, value)
        rawset(self, key, type(value) == "function" and LPH_JIT(value) or value)
    end,
})

xDTaraZ.Config = {
    Discord = "https://discord.gg/FHVfmeSceA",
    UpdateLog = {
        { "2026-10-03", "Classic Nova Hub UI is back\nBetter executor support\nFixed Noclip restore\nAuto-detect Jobs & Teleports" },
    },
    UiSource = "NovaHub://embedded-ui",
    SaveFolder = "Driving Empire",
    LoadTimeout = 10,
    AlertTries = 20,
    AlertRetry = 0.5,
    JobFailLimit = 5,
    JobFailWindow = 10,
    SpawnerCacheFile = "Driving Empire/atm_spawners.json",
    TickDelay = 0.5,
    BustWait = 2.6,
    DebounceTimeout = 6,
    StreamWait = 0.5,
    SweepStep = 800,
    SweepHeight = 400,
    SweepDelay = 0.35,
    SweepMin = Vector3.new(-3500, 0, -6500),
    SweepMax = Vector3.new(7500, 0, 5000),
    CashOutCrimes = 5,
    DropOffStage = 8,
    DropOffSettle = 2.5,
    DropOffPayWait = 4,
    DropOffTries = 2,
    WantedSafety = 25,
    CopAvoidRadius = 45,
    RewardInterval = 60,
    EspInterval = 1,
    HopDelay = 4,
    DriveSpeed = 200,
    DriveAlign = 2,
    DriveLift = 3,
    DriveEdge = 120,
    DriveRoadMin = 1200,
    DriveRoadWidth = 30,
    DriveRoadFlat = 0.05,
    DriveRoadSeed = Vector3.new(-822, 21, -487),
    SpawnWait = 10,
    SpawnTries = 2,
    DropOffSeeds = {
        Vector3.new(-2543.3, 11.9, 4030.3),
        Vector3.new(7322.1, 197.8, -2811.6),
    },
    PlaceSeeds = {
        ["Job: Criminal"] = Vector3.new(135.2, 21.5, -1852.0),
        ["Job: Security"] = Vector3.new(148.2, 21.5, -1991.5),
        ["Job: Delivery"] = Vector3.new(122.5, 21.8, -1922.7),
        ["Job: Security HQ"] = Vector3.new(-109.8, 25.1, -956.8),
        ["Spawn Dealership"] = Vector3.new(-482, 14, -1767),
    },
    Codes = {
        "RAMBO", "AIRDROP", "UWU", "RECORD", "USA250", "10KITS", "MARCH2026", "HAPPY2026", "CALL911", "GOBBLEGOBBLE",
        "SPOOKY", "VEGAS2025", "WHOOPS", "RDCNASCAR25", "2MLIKES", "NASCAR100M", "CUSTOMIZATION2025",
        "200KMEMBERS", "NEWYEAR2025", "ZOOM", "HAPPYXMAS",
        "1MILLIONLIKES", "1MILCASH",
    },
    CodeDelay = 1.5,
}

local Config = xDTaraZ.Config

xDTaraZ.State = {
    Alive = true,
    Messages = {},
    Halted = {},
    Busy = false,
    Stats = nil,
    Spawners = {},
    LastReward = 0,
    LastEsp = 0,
    AtmSession = { Busted = 0, Earned = 0, CashedOut = 0, StartCash = 0 },
    AtmWarn = nil,
    Banking = false,
    BankOnStop = false,
    DriveConn = nil,
    DriveRoad = nil,
    CollideBackup = setmetatable({}, { __mode = "k" }),
    Conns = {},
    EspObjects = {},
    LightingBackup = nil,
    Opt = {
        AtmFarm = false,
        HopWhenEmpty = false,
        AvoidCops = false,
        CashOutCrimes = 10,
        DriveFarm = false,
        DriveCar = nil,
        AutoPlaytime = false,
        AutoClaimMisc = false,
        Code = "",
        WalkSpeed = 16,
        JumpPower = 50,
        SpeedEnabled = false,
        Noclip = false,
        InfiniteJump = false,
        Fullbright = false,
        AntiAfk = false,
        AutoRejoin = false,
        EspAtm = false,
        EspCops = false,
        EspDropOff = false,
        CarSpeed = 0,
    },
}

local State = xDTaraZ.State

for _, name in ipairs({ "Util", "Player", "Vehicle", "Jobs", "Atm", "Drive", "Rewards", "Teleport", "Esp", "Movement", "Session", "Scheduler" }) do
    xDTaraZ[name] = {}
end

function xDTaraZ.Util.Try(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        warn("[Driving Empire]", err)
    end
    return ok, err
end

---@return string?  body, nil when every way to fetch failed
function xDTaraZ.Util.HttpGet(url)
    if url == "NovaHub://embedded-ui" then return NOVA_HUB_UI_SOURCE end
    local ok, body = pcall(game.HttpGet, game, url)
    if ok and type(body) == "string" then
        return body
    end
    local requestFn = (type(request) == "function" and request) or (type(http_request) == "function" and http_request)
        or (type(syn) == "table" and syn.request)
    if type(requestFn) ~= "function" then
        return nil
    end
    local sent, response = pcall(requestFn, { Url = url, Method = "GET" })
    if not sent or type(response) ~= "table" or tonumber(response.StatusCode) ~= 200 or type(response.Body) ~= "string" then
        return nil
    end
    return response.Body
end

---@param text string  shown as a Roblox notification, works before the menu exists
function xDTaraZ.Util.Alert(text)
    warn("[Driving Empire] " .. text)
    task.spawn(function()
        local starterGui = game:GetService("StarterGui")
        for _ = 1, Config.AlertTries do
            if pcall(starterGui.SetCore, starterGui, "SendNotification", { Title = "Nova Hub", Text = text, Duration = 10 }) then
                return
            end
            task.wait(Config.AlertRetry)
        end
    end)
end

---@return table?  UI library, nil after telling the player why
function xDTaraZ.Util.LoadLibrary()
    local source = xDTaraZ.Util.HttpGet(Config.UiSource)
    if not source or not source:sub(-64):find("return Library%s*$") then
        xDTaraZ.Util.Alert("Could not download the menu. Check your connection and run it again.")
        return nil
    end
    local chunk, err = loadstring(source)
    if not chunk then
        xDTaraZ.Util.Alert("The menu failed to load on this executor: " .. tostring(err))
        return nil
    end
    local ok, library = pcall(chunk)
    if not ok or type(library) ~= "table" then
        xDTaraZ.Util.Alert("The menu failed to load on this executor: " .. tostring(library))
        return nil
    end
    return library
end

---@param instance Instance  parented to gethui, then CoreGui, then PlayerGui
function xDTaraZ.Util.Mount(instance)
    local ok, hui = pcall(gethui)
    if ok and typeof(hui) == "Instance" and pcall(function() instance.Parent = hui end) then
        return
    end
    if pcall(function() instance.Parent = game:GetService("CoreGui") end) then
        return
    end
    instance.Parent = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", Config.LoadTimeout)
end

function xDTaraZ.Util.Stats()
    if State.Stats and State.Stats.Parent then return State.Stats end
    local folder = LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild(LocalPlayer.Name .. "'s Stats")
    local data = xDTaraZ.GameLib.Data
    State.Stats = folder or (data and data.GetLoadedStatsFolder(LocalPlayer))
    return State.Stats
end

function xDTaraZ.Util.Cash()
    local stats = xDTaraZ.Util.Stats()
    local cash = stats and stats:FindFirstChild("Cash")
    return cash and cash.Value or 0
end

function xDTaraZ.Util.Commas(number)
    local text = tostring(math.floor(number))
    repeat
        local count
        text, count = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    until count == 0
    return text
end

xDTaraZ.GameLib = {}
local GameLib = xDTaraZ.GameLib

---@return Instance?  child at the end of the path, nil when any step is missing
function GameLib.Find(root, ...)
    local node = root
    for _, name in ipairs({ ... }) do
        node = node and node:FindFirstChild(name)
    end
    return node
end

---@return Instance?  module at the path, else the first ModuleScript with that name anywhere under root
function GameLib.Locate(root, ...)
    local found = GameLib.Find(root, ...)
    if found or not root then return found end
    local name = select(select("#", ...), ...)
    for _, desc in ipairs(root:GetDescendants()) do
        if desc.Name == name and desc:IsA("ModuleScript") then return desc end
    end
    return nil
end

---@return RemoteEvent?  by name in the Remotes folder, else anywhere in ReplicatedStorage
function GameLib.Remote(name)
    local remote = GameLib.RemoteFolder and GameLib.RemoteFolder:FindFirstChild(name)
    remote = remote or ReplicatedStorage:FindFirstChild(name, true)
    return remote and remote:IsA("RemoteEvent") and remote or nil
end

---Plain require first; identity-3 executors get "Cannot require a non-RobloxScript module", so retry once from a fresh identity-2 thread.
---@return table?  module, nil when this executor cannot load it
function GameLib.Require(module)
    if not module or not module:IsA("ModuleScript") then return nil end
    local ok, loaded = pcall(require, module)
    if ok then return loaded end
    local setIdentity = setthreadidentity or setidentity
    local getIdentity = getthreadidentity or getidentity
    if type(setIdentity) ~= "function" or type(getIdentity) ~= "function" then return nil end
    local done, retried = false, nil
    task.spawn(function()
        pcall(setIdentity, 2)
        local switched = select(2, pcall(getIdentity)) == 2
        local again, value = false, nil
        if switched then again, value = pcall(require, module) end
        done, retried = true, again and value or nil
    end)
    local deadline = os.clock() + Config.LoadTimeout
    repeat
        if not done then task.wait() end
    until done or os.clock() > deadline
    return retried
end

do
    local modules = ReplicatedStorage:WaitForChild("Modules", Config.LoadTimeout)
    GameLib.RemoteFolder = ReplicatedStorage:WaitForChild("Remotes", Config.LoadTimeout)
    GameLib.Remotes = GameLib.Require(GameLib.Locate(modules, "Shared", "Remotes"))
    GameLib.Data = GameLib.Require(GameLib.Locate(modules, "Shared", "Data"))
    GameLib.JobsController = GameLib.Require(GameLib.Locate(modules, "Client", "Jobs", "JobsController"))
    GameLib.JobsConstants = GameLib.Require(GameLib.Locate(modules, "Shared", "Jobs", "JobsConstants"))
    GameLib.VehicleController = GameLib.Require(GameLib.Locate(modules, "Client", "Vehicles", "VehicleController"))
    GameLib.TeleportGuard = GameLib.Require(GameLib.Locate(modules, "Client", "Exploit", "VehicleTeleportDetectionController"))
    GameLib.PlayRewardUtil = GameLib.Require(GameLib.Locate(modules, "Shared", "PlayRewards", "PlayRewardUtil"))

    GameLib.VehicleEvent = GameLib.Remote("VehicleEvent")
    GameLib.CodeRemote = GameLib.Remote("Code")
    GameLib.AtmFolder = GameLib.Find(workspace, "Game", "Jobs", "CriminalATMSpawners") or workspace:FindFirstChild("CriminalATMSpawners", true)
end

GameLib.Needs = {
    AtmFarm = { "Remotes", "JobsController", "AtmFolder" },
    DriveFarm = { "VehicleController", "TeleportGuard", "JobsController", "VehicleEvent" },
    AutoPlaytime = { "Remotes", "PlayRewardUtil" },
    AutoClaimMisc = { "Remotes" },
    EspAtm = { "AtmFolder" },
}

GameLib.Parts = {
    VehicleEvent = "remote VehicleEvent",
    CodeRemote = "remote Code",
    AtmFolder = "folder CriminalATMSpawners",
}

---@return string?  first game module the feature needs that did not load
function GameLib.Missing(idx)
    for _, name in ipairs(GameLib.Needs[idx] or {}) do
        if not GameLib[name] then return name end
    end
    return nil
end

---@return Instance[]  ATM spawners, empty when the folder is gone
function GameLib.AtmSpawners()
    local folder = GameLib.AtmFolder
    if not folder or not folder.Parent then
        folder = GameLib.Find(workspace, "Game", "Jobs", "CriminalATMSpawners")
        GameLib.AtmFolder = folder
    end
    return folder and folder:GetChildren() or {}
end

function xDTaraZ.Player.Character()
    local character = LocalPlayer.Character
    if character and character.Parent and character:FindFirstChild("HumanoidRootPart") then
        return character
    end
    return nil
end

function xDTaraZ.Player.Humanoid()
    local character = xDTaraZ.Player.Character()
    return character and character:FindFirstChildOfClass("Humanoid")
end

function xDTaraZ.Player.Root()
    local character = xDTaraZ.Player.Character()
    return character and character.HumanoidRootPart
end

function xDTaraZ.Player.TeleportTo(cframe)
    local root = xDTaraZ.Player.Root()
    if not root then
        return false
    end
    if xDTaraZ.Vehicle.IsSeated() then
        xDTaraZ.Vehicle.Despawn()
        task.wait(1)
    end
    root.CFrame = cframe
    root.AssemblyLinearVelocity = Vector3.zero
    return true
end

function xDTaraZ.Vehicle.Current()
    if not GameLib.VehicleController then return nil end
    local vehicle = GameLib.VehicleController.getVehicle()
    return vehicle and vehicle.Object
end

function xDTaraZ.Vehicle.IsSeated()
    local humanoid = xDTaraZ.Player.Humanoid()
    return humanoid ~= nil and humanoid.SeatPart ~= nil
end

function xDTaraZ.Vehicle.Owned()
    local owned = {}
    local stats = xDTaraZ.Util.Stats()
    if not stats then
        return owned
    end
    local vehicles = stats:FindFirstChild("Vehicles")
    if not vehicles then return owned end
    for _, entry in ipairs(vehicles:GetChildren()) do
        if entry.Value == true then
            table.insert(owned, entry.Name)
        end
    end
    table.sort(owned)
    return owned
end

function xDTaraZ.Vehicle.Spawn(vehicleId)
    if not vehicleId or not GameLib.VehicleEvent then
        return nil
    end
    GameLib.VehicleEvent:FireServer("Spawn", vehicleId)
    local deadline = os.clock() + Config.SpawnWait
    repeat
        task.wait(0.25)
    until xDTaraZ.Vehicle.Current() or os.clock() > deadline
    return xDTaraZ.Vehicle.Current()
end

function xDTaraZ.Vehicle.Despawn()
    if not GameLib.VehicleEvent then return end
    GameLib.VehicleEvent:FireServer("Despawn")
end

---@return boolean  moved the car, or the character when on foot
function xDTaraZ.Vehicle.TeleportTo(cframe)
    local car = xDTaraZ.Vehicle.Current()
    if not car or not xDTaraZ.Vehicle.IsSeated() then
        local root = xDTaraZ.Player.Root()
        if root then
            root.CFrame = cframe
        end
        return root ~= nil
    end
    if not GameLib.TeleportGuard then
        return xDTaraZ.Player.TeleportTo(cframe)
    end
    GameLib.TeleportGuard.AuthorizeNextTeleport()
    car:PivotTo(cframe)
    if car.PrimaryPart then
        car.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
    end
    return true
end

function xDTaraZ.Vehicle.ApplySpeed()
    local car = xDTaraZ.Vehicle.Current()
    local boost = State.Opt.CarSpeed
    if not car or not car.PrimaryPart or boost <= 0 or not xDTaraZ.Vehicle.IsSeated() then
        return
    end
    if not UserInputService:IsKeyDown(Enum.KeyCode.W) then
        return
    end
    local root = car.PrimaryPart
    local flat = root.CFrame.LookVector * Vector3.new(1, 0, 1)
    if flat.Magnitude < 0.1 then
        return
    end
    local velocity = root.AssemblyLinearVelocity
    local forward = velocity:Dot(flat.Unit)
    local target = math.max(forward, boost)
    root.AssemblyLinearVelocity = flat.Unit * target + Vector3.new(0, velocity.Y, 0)
end

function xDTaraZ.Jobs.Current()
    return LocalPlayer:GetAttribute("JobId")
end

---@return string[]  job ids the game defines plus any job pad on the map, sorted
function xDTaraZ.Jobs.List()
    local seen, list = {}, {}
    local function Add(jobId)
        if type(jobId) ~= "string" or seen[jobId] then return end
        seen[jobId] = true
        list[#list + 1] = jobId
    end
    local constants = GameLib.JobsConstants
    for _, jobId in pairs(constants and constants.JobIds or {}) do
        Add(jobId)
    end
    for _, pad in ipairs(CollectionService:GetTagged("JobPad")) do
        Add(pad:GetAttribute("JobId"))
    end
    table.sort(list)
    return list
end

function xDTaraZ.Jobs.Start(jobId)
    if xDTaraZ.Jobs.Current() == jobId then
        return true
    end
    if not GameLib.JobsController then
        return false
    end
    GameLib.JobsController.RequestStartJobSession(jobId, "jobPad")
    local deadline = os.clock() + 4
    repeat
        task.wait(0.2)
    until xDTaraZ.Jobs.Current() == jobId or os.clock() > deadline
    return xDTaraZ.Jobs.Current() == jobId
end

function xDTaraZ.Jobs.Leave()
    if xDTaraZ.Jobs.Current() and GameLib.JobsController then
        GameLib.JobsController.RequestEndJobSession("jobPad")
    end
end

function xDTaraZ.Atm.LoadCache()
    local read, text = pcall(function()
        return isfile(Config.SpawnerCacheFile) and readfile(Config.SpawnerCacheFile)
    end)
    if not read or type(text) ~= "string" then
        return
    end
    local ok, decoded = pcall(HttpService.JSONDecode, HttpService, text)
    if not ok or type(decoded) ~= "table" then
        return
    end
    for id, coords in pairs(decoded) do
        State.Spawners[id] = Vector3.new(coords[1], coords[2], coords[3])
    end
end

function xDTaraZ.Atm.SaveCache()
    local encoded = {}
    for id, position in pairs(State.Spawners) do
        encoded[id] = { position.X, position.Y, position.Z }
    end
    local saved, err = pcall(function()
        if not isfolder("Driving Empire") then
            makefolder("Driving Empire")
        end
        writefile(Config.SpawnerCacheFile, HttpService:JSONEncode(encoded))
    end)
    if not saved then
        warn("[Driving Empire] atm cache:", err)
    end
end

function xDTaraZ.Atm.SpawnerCount()
    local count = 0
    for _ in pairs(State.Spawners) do
        count += 1
    end
    return count
end

local function RecordStreamedSpawners()
    for _, spawner in ipairs(GameLib.AtmSpawners()) do
        local id = spawner:GetAttribute("ComponentServerId")
        if id then
            State.Spawners[id] = spawner.Position
        end
    end
end

function xDTaraZ.Atm.Sweep()
    local root = xDTaraZ.Player.Root()
    if not root then
        return 0
    end
    if xDTaraZ.Vehicle.IsSeated() then
        xDTaraZ.Vehicle.Despawn()
        task.wait(1)
    end
    for x = Config.SweepMin.X, Config.SweepMax.X, Config.SweepStep do
        for z = Config.SweepMin.Z, Config.SweepMax.Z, Config.SweepStep do
            if not State.Alive then
                return xDTaraZ.Atm.SpawnerCount()
            end
            root.CFrame = CFrame.new(x, Config.SweepHeight, z)
            root.AssemblyLinearVelocity = Vector3.zero
            task.wait(Config.SweepDelay)
            RecordStreamedSpawners()
        end
    end
    xDTaraZ.Atm.SaveCache()
    return xDTaraZ.Atm.SpawnerCount()
end

local function FindAtm(spawnerId)
    for _, spawner in ipairs(GameLib.AtmSpawners()) do
        if spawner:GetAttribute("ComponentServerId") == spawnerId then
            return spawner:FindFirstChild("CriminalATM")
        end
    end
    return nil
end

function xDTaraZ.Atm.IsAvailable(atm)
    if not atm or atm:GetAttribute("State") ~= "Normal" then
        return false
    end
    local engaging = atm:GetAttribute("EngagingPlayerId")
    return engaging == nil or engaging == LocalPlayer.UserId
end

function xDTaraZ.Atm.CopNearby(position)
    for _, other in ipairs(Players:GetPlayers()) do
        local character = other ~= LocalPlayer and other.Character
        if character and other:GetAttribute("JobId") == "Security" then
            local root = character:FindFirstChild("HumanoidRootPart")
            if root and (root.Position - position).Magnitude < Config.CopAvoidRadius then
                return true
            end
        end
    end
    return false
end

local function WaitForDebounce(character)
    local deadline = os.clock() + Config.DebounceTimeout
    while character:GetAttribute("ATMBustDebounce") and os.clock() < deadline do
        task.wait(0.1)
    end
end

---@return boolean, string?  robbed, else the server's reason
function xDTaraZ.Atm.Bust(atm)
    local character = xDTaraZ.Player.Character()
    if not GameLib.Remotes then
        return false, "Not available on this executor"
    end
    if not character or not xDTaraZ.Atm.IsAvailable(atm) then
        return false, "Unavailable"
    end
    local attachment = atm:FindFirstChild("PromptAttachment")
    local target = attachment and attachment.WorldPosition or atm:GetPivot().Position
    if State.Opt.AvoidCops and xDTaraZ.Atm.CopNearby(target) then
        return false, "CopNearby"
    end
    WaitForDebounce(character)
    character.HumanoidRootPart.CFrame = CFrame.lookAt(target + atm:GetPivot().LookVector * 3, target)
    task.wait(0.25)
    local started, reason = GameLib.Remotes.invokeServer("AttemptATMBustStart", atm)
    if not started then
        return false, reason
    end
    task.wait(Config.BustWait)
    local earnedBefore = character:GetAttribute("CurrencyEarned") or 0
    local done, failReason = GameLib.Remotes.invokeServer("AttemptATMBustComplete", atm)
    if not done then
        return false, failReason
    end
    State.AtmSession.Busted += 1
    task.defer(function()
        task.wait(0.5)
        State.AtmSession.Earned += math.max(0, (character:GetAttribute("CurrencyEarned") or 0) - earnedBefore)
    end)
    return true
end

function xDTaraZ.Atm.DropOffPositions()
    local positions = {}
    for _, point in ipairs(CollectionService:GetTagged("CriminalDropOffPoint")) do
        table.insert(positions, point:GetPivot().Position)
    end
    if #positions == 0 then
        return Config.DropOffSeeds
    end
    return positions
end

function xDTaraZ.Atm.NearestDropOff()
    local root = xDTaraZ.Player.Root()
    local best, bestDistance = nil, math.huge
    for _, position in ipairs(xDTaraZ.Atm.DropOffPositions()) do
        local distance = root and (position - root.Position).Magnitude or 0
        if distance < bestDistance then
            best, bestDistance = position, distance
        end
    end
    return best
end

function xDTaraZ.Atm.Crimes()
    local character = xDTaraZ.Player.Character()
    return character and character:GetAttribute("CrimesCommitted") or 0
end

---@return boolean        paid
---@return number|string  cash gained, or why it did not pay
function xDTaraZ.Atm.CashOut()
    if xDTaraZ.Atm.Crimes() < Config.CashOutCrimes then
        return false, "Need 5 stars first"
    end
    local seed = xDTaraZ.Atm.NearestDropOff()
    if not seed then return false, "No drop-off found" end

    local stage = Vector3.new(0, 3, Config.DropOffStage)
    local cashBefore = xDTaraZ.Util.Cash()
    State.Banking = true
    xDTaraZ.Player.TeleportTo(CFrame.new(seed + stage))
    task.wait(Config.StreamWait)
    local target = xDTaraZ.Atm.NearestDropOff() or seed

    for _ = 1, Config.DropOffTries do
        xDTaraZ.Player.TeleportTo(CFrame.new(target + stage))
        task.wait(Config.DropOffSettle)
        xDTaraZ.Player.TeleportTo(CFrame.new(target + Vector3.new(0, 3, 0)))
        local deadline = os.clock() + Config.DropOffPayWait
        repeat
            task.wait(0.25)
        until xDTaraZ.Util.Cash() > cashBefore or os.clock() > deadline
        if xDTaraZ.Util.Cash() > cashBefore or xDTaraZ.Atm.Crimes() < Config.CashOutCrimes then break end
    end
    State.Banking = false

    local gained = xDTaraZ.Util.Cash() - cashBefore
    if gained <= 0 then return false, "The drop-off did not pay" end
    State.AtmSession.CashedOut += gained
    return true, gained
end

function xDTaraZ.Atm.RunPass()
    if not xDTaraZ.Jobs.Start("Criminal") then
        State.AtmWarn = "Could not start the Criminal job"
        error(State.AtmWarn, 0)
    end
    State.AtmWarn = nil
    if xDTaraZ.Atm.SpawnerCount() == 0 then
        xDTaraZ.Atm.Sweep()
    end
    local busted = 0
    for id, position in pairs(State.Spawners) do
        if not State.Opt.AtmFarm or not State.Alive then
            break
        end
        xDTaraZ.Player.TeleportTo(CFrame.new(position + Vector3.new(0, 6, 0)))
        local atm
        local deadline = os.clock() + Config.StreamWait
        repeat
            task.wait(0.1)
            atm = FindAtm(id)
        until atm or os.clock() > deadline
        RecordStreamedSpawners()
        if xDTaraZ.Atm.IsAvailable(atm) and xDTaraZ.Atm.Bust(atm) then
            busted += 1
        end
        local crimes = xDTaraZ.Atm.Crimes()
        if crimes >= State.Opt.CashOutCrimes or (crimes >= Config.CashOutCrimes and xDTaraZ.Atm.WantedLeft() < Config.WantedSafety) then
            xDTaraZ.Atm.CashOut()
        end
    end
    return busted
end

function xDTaraZ.Atm.WantedLeft()
    local character = xDTaraZ.Player.Character()
    local expire = character and character:GetAttribute("CriminalExpireEpoch")
    return expire and expire - workspace:GetServerTimeNow() or math.huge
end

function xDTaraZ.Atm.FarmStep()
    local busted = xDTaraZ.Atm.RunPass()
    if not State.Opt.AtmFarm then
        return
    end
    if xDTaraZ.Atm.Crimes() >= State.Opt.CashOutCrimes then
        xDTaraZ.Atm.CashOut()
    end
    if busted == 0 and State.Opt.HopWhenEmpty and xDTaraZ.Atm.Crimes() == 0 then
        xDTaraZ.Session.Hop()
    end
end

function xDTaraZ.Atm.NearestAvailable()
    local root = xDTaraZ.Player.Root()
    if not root then return nil end
    local best, bestDistance
    for _, spawner in ipairs(GameLib.AtmSpawners()) do
        local atm = spawner:FindFirstChild("CriminalATM")
        if xDTaraZ.Atm.IsAvailable(atm) then
            local distance = (spawner.Position - root.Position).Magnitude
            if not bestDistance or distance < bestDistance then
                best, bestDistance = atm, distance
            end
        end
    end
    return best
end

---@return boolean, string?  robbed, else why not
function xDTaraZ.Atm.RobNearest()
    if not xDTaraZ.Jobs.Start("Criminal") then
        return false, "Could not start the Criminal job"
    end
    local atm = xDTaraZ.Atm.NearestAvailable()
    if not atm then
        return false, "No ATM nearby"
    end
    return xDTaraZ.Atm.Bust(atm)
end

---@return table?  Center, Axis, Half, Top of the longest flat asphalt road; nil if none is loaded
function xDTaraZ.Drive.FindRoad()
    local road = State.DriveRoad
    if road and road.Part.Parent then return road end
    local best, bestLength = nil, Config.DriveRoadMin
    for _, part in ipairs((workspace:FindFirstChild("Map") or workspace):GetDescendants()) do
        if not part:IsA("BasePart") or part.Material ~= Enum.Material.Asphalt or not part.CanCollide then continue end
        local size = part.Size
        local length, width = math.max(size.X, size.Z), math.min(size.X, size.Z)
        local axis = size.X >= size.Z and part.CFrame.RightVector or part.CFrame.LookVector
        if length > bestLength and width >= Config.DriveRoadWidth and math.abs(axis.Y) < Config.DriveRoadFlat then
            best, bestLength = { Part = part, Axis = (axis * Vector3.new(1, 0, 1)).Unit, Length = length }, length
        end
    end
    if not best then return nil end
    local part = best.Part
    State.DriveRoad = {
        Part = part,
        Center = part.Position,
        Axis = best.Axis,
        Half = best.Length / 2 - Config.DriveEdge,
        Top = part.Position.Y + part.Size.Y / 2 + Config.DriveLift,
    }
    return State.DriveRoad
end

---@return table?  road, streamed in when it is not loaded yet
function xDTaraZ.Drive.LoadRoad()
    local road = xDTaraZ.Drive.FindRoad()
    if road then return road end
    pcall(LocalPlayer.RequestStreamAroundAsync, LocalPlayer, Config.DriveRoadSeed, Config.LoadTimeout)
    task.wait(Config.StreamWait)
    return xDTaraZ.Drive.FindRoad()
end

function xDTaraZ.Drive.Warp(road)
    local start = road.Center - road.Axis * road.Half
    local spot = Vector3.new(start.X, road.Top, start.Z)
    xDTaraZ.Vehicle.TeleportTo(CFrame.lookAt(spot, spot + road.Axis))
end

function xDTaraZ.Drive.Step(road)
    local car = xDTaraZ.Vehicle.Current()
    local root = car and car.PrimaryPart
    if not root or not xDTaraZ.Vehicle.IsSeated() then return end
    local offset = root.Position - road.Center
    local along = offset:Dot(road.Axis)
    if along > road.Half then
        xDTaraZ.Drive.Warp(road)
        return
    end
    local side = offset - road.Axis * along
    side = Vector3.new(side.X, 0, side.Z)
    local fall = math.min(root.AssemblyLinearVelocity.Y, 0)
    root.AssemblyLinearVelocity = road.Axis * Config.DriveSpeed - side * Config.DriveAlign + Vector3.new(0, fall, 0)
end

function xDTaraZ.Drive.Board()
    local carId = State.Opt.DriveCar or xDTaraZ.Vehicle.Owned()[1]
    for _ = 1, Config.SpawnTries do
        local car = xDTaraZ.Vehicle.Spawn(carId)
        if car then return car end
    end
    return nil
end

---@return boolean, string?  started, else why not
function xDTaraZ.Drive.Start()
    if State.DriveConn then return true end
    xDTaraZ.Jobs.Leave()
    local road = xDTaraZ.Drive.LoadRoad()
    if not road then return false, "No paved road found" end
    local car = xDTaraZ.Vehicle.Current()
    if not car or not xDTaraZ.Vehicle.IsSeated() then
        car = xDTaraZ.Drive.Board()
    end
    if not car then return false, "No car to drive" end
    task.wait(1)
    xDTaraZ.Drive.Warp(road)
    task.wait(1)
    if not State.Opt.DriveFarm or State.DriveConn then return true end
    State.DriveConn = RunService.Heartbeat:Connect(function()
        xDTaraZ.Drive.Step(road)
    end)
    return true
end

function xDTaraZ.Drive.Stop()
    if State.DriveConn then
        State.DriveConn:Disconnect()
        State.DriveConn = nil
    end
    local car = xDTaraZ.Vehicle.Current()
    if car and car.PrimaryPart then
        car.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
    end
end

function xDTaraZ.Rewards.ClaimPlaytime()
    local ok, unclaimed = pcall(function()
        local pending = GameLib.PlayRewardUtil.getUnclaimedRewards(LocalPlayer)
        if type(pending) == "table" and pending.expect then
            pending = pending:expect()
        end
        return pending
    end)
    if not ok or type(unclaimed) ~= "table" then
        return 0
    end
    local count = 0
    for index in pairs(unclaimed) do
        GameLib.Remotes.fireServer("PlayRewards", tonumber(index) or index, false)
        count += 1
        task.wait(0.5)
    end
    return count
end

function xDTaraZ.Rewards.ClaimMisc()
    if not GameLib.Remotes then return end
    GameLib.Remotes.fireServer("ClaimRewards")
    GameLib.Remotes.fireServer("RaceLeaderboardClaimRewards")
end

function xDTaraZ.Rewards.Redeemed()
    local stats = xDTaraZ.Util.Stats()
    local codes = stats and stats:FindFirstChild("Codes")
    local ok, decoded = pcall(HttpService.JSONDecode, HttpService, codes and codes.Value or "")
    return ok and type(decoded) == "table" and decoded or {}
end

---@return number, number  new codes redeemed, cash gained
function xDTaraZ.Rewards.RedeemCodes(codes)
    if not GameLib.CodeRemote then return 0, 0 end
    local redeemedBefore = xDTaraZ.Rewards.Redeemed()
    local cashBefore = xDTaraZ.Util.Cash()
    local success = 0
    for _, code in ipairs(codes) do
        if not redeemedBefore[code] then
            GameLib.CodeRemote:FireServer(code)
            task.wait(Config.CodeDelay)
            if xDTaraZ.Rewards.Redeemed()[code] then
                success += 1
            end
        end
    end
    return success, xDTaraZ.Util.Cash() - cashBefore
end

function xDTaraZ.Teleport.Destinations()
    local destinations = {}
    local names = {}
    local function Add(name, position)
        if position and not destinations[name] then
            destinations[name] = position
            table.insert(names, name)
        end
    end
    local padCount = {}
    for _, pad in ipairs(CollectionService:GetTagged("JobPad")) do
        local jobId = pad:GetAttribute("JobId")
        if jobId and pad:IsA("BasePart") then
            padCount[jobId] = (padCount[jobId] or 0) + 1
            Add(padCount[jobId] == 1 and "Job: " .. jobId or ("Job: %s %d"):format(jobId, padCount[jobId]), pad.Position)
        end
    end
    for name, position in pairs(Config.PlaceSeeds) do
        Add(name, position)
    end
    for index, position in ipairs(xDTaraZ.Atm.DropOffPositions()) do
        Add(("Criminal Drop-off %d"):format(index), position)
    end
    local heist = GameLib.Find(workspace, "Game", "Heists", "BankHeist")
    local heistStart = heist and heist:FindFirstChild("HeistStartTeleport", true)
    if heistStart then
        Add("Bank Heist", heistStart.Position)
    end
    local dealerships = workspace.Game:FindFirstChild("Dealerships")
    dealerships = dealerships and dealerships:FindFirstChild("Dealerships")
    if dealerships then
        for _, dealership in ipairs(dealerships:GetChildren()) do
            local part = dealership:FindFirstChildWhichIsA("BasePart", true)
            if part then
                Add("Dealership: " .. dealership.Name, part.Position)
            end
        end
    end
    table.sort(names)
    return names, destinations
end

function xDTaraZ.Teleport.Go(position)
    if not position then
        return
    end
    LocalPlayer:RequestStreamAroundAsync(position, 5)
    xDTaraZ.Vehicle.TeleportTo(CFrame.new(position + Vector3.new(0, 5, 0)))
end

function xDTaraZ.Teleport.ToPlayer(name)
    local target = Players:FindFirstChild(name)
    local root = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
    if root then
        xDTaraZ.Teleport.Go(root.Position + Vector3.new(0, 0, 4))
    end
end

function xDTaraZ.Movement.Step()
    local opt = State.Opt
    local character = xDTaraZ.Player.Character()
    local humanoid = xDTaraZ.Player.Humanoid()
    if not character or not humanoid then
        return
    end
    if opt.SpeedEnabled and not xDTaraZ.Vehicle.IsSeated() then
        humanoid.WalkSpeed = opt.WalkSpeed
        humanoid.UseJumpPower = true
        humanoid.JumpPower = opt.JumpPower
    end
    if opt.Noclip then
        for _, part in ipairs(character:GetChildren()) do
            if part:IsA("BasePart") and part.CanCollide then
                State.CollideBackup[part] = true
                part.CanCollide = false
            end
        end
    end
    xDTaraZ.Vehicle.ApplySpeed()
end

function xDTaraZ.Movement.SetNoclip(enabled)
    if enabled then return end
    for part, original in pairs(State.CollideBackup) do
        if part.Parent then
            part.CanCollide = original
        end
    end
    table.clear(State.CollideBackup)
end

function xDTaraZ.Movement.ResetSpeed()
    local humanoid = xDTaraZ.Player.Humanoid()
    if humanoid then
        humanoid.WalkSpeed = 16
        humanoid.JumpPower = 50
    end
end

function xDTaraZ.Movement.SetFullbright(enabled)
    if enabled then
        State.LightingBackup = State.LightingBackup or {
            Brightness = Lighting.Brightness,
            ClockTime = Lighting.ClockTime,
            GlobalShadows = Lighting.GlobalShadows,
            Ambient = Lighting.Ambient,
        }
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.GlobalShadows = false
        Lighting.Ambient = Color3.fromRGB(180, 180, 180)
        return
    end
    if State.LightingBackup then
        for property, value in pairs(State.LightingBackup) do
            Lighting[property] = value
        end
        State.LightingBackup = nil
    end
end

function xDTaraZ.Movement.Bind()
    table.insert(State.Conns, RunService.Stepped:Connect(function()
        xDTaraZ.Scheduler.Run(xDTaraZ.Scheduler.MovementJob)
    end))
    table.insert(State.Conns, UserInputService.JumpRequest:Connect(function()
        local humanoid = xDTaraZ.Player.Humanoid()
        if State.Opt.InfiniteJump and humanoid then
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end))
end

local function EspMark(key, adornee, text, color)
    local entry = State.EspObjects[key]
    if entry and entry.Highlight.Parent and entry.Highlight.Adornee == adornee then
        entry.Label.Text = text
        return
    end
    if entry then
        entry.Highlight:Destroy()
        entry.Billboard:Destroy()
    end
    local highlight = Instance.new("Highlight")
    highlight.FillColor = color
    highlight.FillTransparency = 0.6
    highlight.OutlineColor = color
    highlight.Adornee = adornee
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    xDTaraZ.Util.Mount(highlight)
    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.fromOffset(160, 28)
    billboard.StudsOffset = Vector3.new(0, 5, 0)
    billboard.AlwaysOnTop = true
    billboard.Adornee = adornee
    xDTaraZ.Util.Mount(billboard)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.TextColor3 = color
    label.TextStrokeTransparency = 0.3
    label.Font = Enum.Font.GothamBold
    label.TextSize = 13
    label.Text = text
    label.Parent = billboard
    State.EspObjects[key] = { Highlight = highlight, Billboard = billboard, Label = label }
end

function xDTaraZ.Esp.Refresh()
    local opt = State.Opt
    local root = xDTaraZ.Player.Root()
    local alive = {}
    local function Distance(position)
        return root and math.floor((position - root.Position).Magnitude) or 0
    end
    if opt.EspAtm then
        for _, spawner in ipairs(GameLib.AtmSpawners()) do
            local atm = spawner:FindFirstChild("CriminalATM")
            if xDTaraZ.Atm.IsAvailable(atm) then
                local key = "atm" .. tostring(spawner:GetAttribute("ComponentServerId"))
                alive[key] = true
                EspMark(key, atm, ("ATM %s · %dm"):format(tostring(atm:GetAttribute("Rarity")), Distance(spawner.Position)), Color3.fromRGB(90, 220, 120))
            end
        end
    end
    if opt.EspCops then
        for _, other in ipairs(Players:GetPlayers()) do
            local character = other.Character
            local job = other:GetAttribute("JobId")
            if other ~= LocalPlayer and character and character:FindFirstChild("HumanoidRootPart") and job then
                local key = "plr" .. other.UserId
                alive[key] = true
                local color = job == "Security" and Color3.fromRGB(80, 140, 255) or job == "Criminal" and Color3.fromRGB(255, 90, 90) or Color3.fromRGB(232, 160, 76)
                EspMark(key, character, ("%s [%s] · %dm"):format(other.DisplayName, job, Distance(character.HumanoidRootPart.Position)), color)
            end
        end
    end
    if opt.EspDropOff then
        for index, point in ipairs(CollectionService:GetTagged("CriminalDropOffPoint")) do
            local key = "drop" .. index
            alive[key] = true
            EspMark(key, point, ("Drop-off · %dm"):format(Distance(point:GetPivot().Position)), Color3.fromRGB(255, 210, 80))
        end
    end
    for key, entry in pairs(State.EspObjects) do
        if not alive[key] then
            entry.Highlight:Destroy()
            entry.Billboard:Destroy()
            State.EspObjects[key] = nil
        end
    end
end

function xDTaraZ.Session.Bind()
    table.insert(State.Conns, LocalPlayer.Idled:Connect(function()
        if State.Opt.AntiAfk then
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.zero)
        end
    end))
    table.insert(State.Conns, GuiService.ErrorMessageChanged:Connect(function()
        if not State.Opt.AutoRejoin then
            return
        end
        task.wait(Config.HopDelay)
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end))
end

function xDTaraZ.Session.Hop()
    local body = xDTaraZ.Util.HttpGet(("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&limit=100"):format(game.PlaceId))
    local ok, decoded = pcall(HttpService.JSONDecode, HttpService, body or "")
    if not ok or type(decoded) ~= "table" then
        return false
    end
    local candidates = {}
    for _, server in ipairs(decoded.data or {}) do
        if server.id ~= game.JobId and server.playing < server.maxPlayers - 1 then
            table.insert(candidates, server.id)
        end
    end
    if #candidates == 0 then
        return false
    end
    TeleportService:TeleportToPlaceInstance(game.PlaceId, candidates[math.random(#candidates)], LocalPlayer)
    return true
end

function xDTaraZ.Scheduler.AtmStep()
    if State.Opt.AtmFarm then
        xDTaraZ.Atm.FarmStep()
        return
    end
    if not State.BankOnStop then return end
    State.BankOnStop = false
    if xDTaraZ.Atm.Crimes() < Config.CashOutCrimes then return end

    local ok, got = xDTaraZ.Atm.CashOut()
    if ok then
        xDTaraZ.UI.Notify("Banked $" .. xDTaraZ.Util.Commas(got) .. " before stopping", "Success")
    else
        xDTaraZ.UI.Notify("Wanted cash not banked: " .. got, "Warning")
    end
end

function xDTaraZ.Scheduler.RewardStep()
    local opt = State.Opt
    local now = os.clock()
    if not (opt.AutoPlaytime or opt.AutoClaimMisc) or now - State.LastReward <= Config.RewardInterval then
        return
    end
    State.LastReward = now
    if opt.AutoPlaytime then
        xDTaraZ.Rewards.ClaimPlaytime()
    end
    if opt.AutoClaimMisc then
        xDTaraZ.Rewards.ClaimMisc()
    end
end

function xDTaraZ.Scheduler.EspStep()
    local now = os.clock()
    if now - State.LastEsp > Config.EspInterval then
        State.LastEsp = now
        xDTaraZ.Esp.Refresh()
    end
end

xDTaraZ.Scheduler.Jobs = {
    { "ATM Farm", xDTaraZ.Scheduler.AtmStep, { "AtmFarm" } },
    { "Rewards", xDTaraZ.Scheduler.RewardStep, { "AutoPlaytime", "AutoClaimMisc" } },
    { "ESP", xDTaraZ.Scheduler.EspStep, { "EspAtm", "EspCops", "EspDropOff" }, Core = true },
}

xDTaraZ.Scheduler.MovementJob = { "Movement", xDTaraZ.Movement.Step, { "SpeedEnabled", "Noclip" } }

---@param job table  { label, step, toggle idxs }
---@return boolean   any of the job's features is on
function xDTaraZ.Scheduler.Wanted(job)
    for _, idx in ipairs(job[3]) do
        if State.Opt[idx] then return true end
    end
    return false
end

---Turns the job's features off after Config.JobFailLimit errors spanning Config.JobFailWindow seconds; the UI pump flips the toggles (this thread has touched game modules) and their callbacks restore.
---@param job table  { label, step, toggle idxs, Core = never rests }
function xDTaraZ.Scheduler.Run(job)
    if job.Stopped then
        if not xDTaraZ.Scheduler.Wanted(job) then return end
        job.Stopped = nil
    end
    local ok, err = pcall(job[2])
    if ok then
        job.Streak = nil
        return
    end

    local streak = job.Streak
    if not streak then
        streak = { count = 0, since = os.clock() }
        job.Streak = streak
        warn("[Driving Empire] " .. job[1] .. ":", err)
    end
    streak.count += 1
    if streak.count < Config.JobFailLimit or os.clock() - streak.since < Config.JobFailWindow then return end

    local switched = xDTaraZ.Scheduler.Wanted(job)
    if job.Core and not switched then return end
    job.Streak = nil
    job.Stopped = not job.Core and not switched
    for _, idx in ipairs(job[3]) do
        if State.Opt[idx] then
            State.Opt[idx] = false
            table.insert(State.Halted, idx)
        end
    end

    local reason = tostring(err):match("^[^\n]*")
    warn("[Driving Empire] " .. job[1] .. " stopped:", reason)
    if switched then xDTaraZ.UI.Notify(job[1] .. " stopped: " .. reason, "Warning") end
end

function xDTaraZ.Scheduler.Boot()
    xDTaraZ.Atm.LoadCache()
    xDTaraZ.Movement.Bind()
    xDTaraZ.Session.Bind()
    task.spawn(function()
        while State.Alive do
            if not State.Busy then
                State.Busy = true
                for _, job in ipairs(xDTaraZ.Scheduler.Jobs) do
                    xDTaraZ.Scheduler.Run(job)
                end
                State.Busy = false
            end
            task.wait(Config.TickDelay)
        end
    end)
end

function xDTaraZ.Scheduler.Stop()
    State.Alive = false
    for key in pairs(State.Opt) do
        if type(State.Opt[key]) == "boolean" and key ~= "AntiAfk" then
            State.Opt[key] = false
        end
    end
    xDTaraZ.Drive.Stop()
    xDTaraZ.Movement.SetNoclip(false)
    xDTaraZ.Movement.ResetSpeed()
    xDTaraZ.Movement.SetFullbright(false)
    for _, conn in ipairs(State.Conns) do
        conn:Disconnect()
    end
    table.clear(State.Conns)
    xDTaraZ.Esp.Refresh()
end

xDTaraZ.UI = {}
local Library, T

---@param kind string?  Info, Success, Warning or Error
function xDTaraZ.UI.Notify(text, kind)
    State.Messages[#State.Messages + 1] = { text, kind }
end

function xDTaraZ.UI.Spawn(action)
    return function()
        task.spawn(xDTaraZ.Util.Try, action)
    end
end

function xDTaraZ.UI.StartDrive()
    local started, reason = xDTaraZ.Drive.Start()
    if started then return end
    State.Opt.DriveFarm = false
    table.insert(State.Halted, "DriveFarm")
    xDTaraZ.UI.Notify(reason or "Could not start driving", "Warning")
end

---@param onChange function?  runs after State.Opt is updated
function xDTaraZ.UI.Toggle(group, key, text, description, onChange, risky)
    return group:AddToggle(key, {
        Text = text,
        Description = description,
        Default = State.Opt[key],
        Risky = risky,
        Callback = function(value)
            State.Opt[key] = value
            if onChange then
                xDTaraZ.Util.Try(onChange, value)
            end
        end,
    })
end

function xDTaraZ.UI.Slider(group, key, text, description, min, max)
    local opt = State.Opt
    return group:AddSlider(key, {
        Text = text,
        Description = description,
        Min = min, Max = max, Default = opt[key], Rounding = 0,
        Callback = function(value)
            opt[key] = tonumber(value) or opt[key]
        end,
    })
end

function xDTaraZ.UI.Panic()
    for idx, toggle in pairs(Library.Toggles) do
        if type(State.Opt[idx]) == "boolean" and toggle.Value == true then
            toggle:SetValue(false)
        end
    end
end

---@return string  one line for the status label
function xDTaraZ.UI.AtmStatus()
    if State.Banking then return "Cashing out" end
    if State.AtmWarn then return "Warn: " .. State.AtmWarn end
    if not State.Opt.AtmFarm then return "Off" end
    return ("Robbing · %d stars"):format(xDTaraZ.Atm.Crimes())
end

function xDTaraZ.UI.StatusText()
    local session = State.AtmSession
    local char = xDTaraZ.Player.Character()
    local carried = char and char:GetAttribute("CurrencyEarned") or 0
    return ("ATM Farm: %s · Drive: %s\nCash $%s · Job %s · Stars %d\nATMs robbed %d · Wanted cash $%s · Cashed out $%s\nATM spots known %d"):format(
        xDTaraZ.UI.AtmStatus(), State.Opt.DriveFarm and "Driving" or "Off",
        xDTaraZ.Util.Commas(xDTaraZ.Util.Cash()), tostring(xDTaraZ.Jobs.Current() or "Citizen"), xDTaraZ.Atm.Crimes(),
        session.Busted, xDTaraZ.Util.Commas(carried), xDTaraZ.Util.Commas(session.CashedOut), xDTaraZ.Atm.SpawnerCount())
end

function xDTaraZ.UI.BuildAtm(farmTab)
    local atmBox = farmTab:AddLeftGroupbox(T("ATM Farm", "ฟาร์ม ATM"))
    local wasOn = false
    xDTaraZ.UI.Toggle(atmBox, "AtmFarm", T("Auto ATM Farm", "ฟาร์ม ATM อัตโนมัติ"), T("Robs every ATM on the map with the full crime bonus, then cashes out", "ปล้น ATM ทุกตู้ในแมพพร้อมโบนัสอาชญากรรมเต็ม แล้วส่งเงิน"), function(on)
        if on then State.AtmWarn = nil end
        State.BankOnStop = wasOn and not on and xDTaraZ.Atm.Crimes() >= Config.CashOutCrimes
        wasOn = on
    end, true):AddKeyPicker("AtmFarmKey", { Default = "None", Mode = "Toggle" })
    xDTaraZ.UI.Slider(atmBox, "CashOutCrimes", T("Cash Out At Robberies", "ส่งเงินเมื่อปล้นครบ"), T("Banks the loot after this many robberies (higher = more risk)", "ส่งเงินหลังปล้นครบจำนวนนี้ (ยิ่งมากยิ่งเสี่ยง)"), 5, 30)

    atmBox:AddButton({ Text = T("Rob Nearest ATM", "ปล้น ATM ที่ใกล้ที่สุด"), Style = "Primary", Func = xDTaraZ.UI.Spawn(function()
        local ok, reason = xDTaraZ.Atm.RobNearest()
        xDTaraZ.UI.Notify(ok and "ATM robbed" or ("Failed: " .. tostring(reason)), ok and "Success" or "Warning")
    end) }):AddButton({ Text = T("Cash Out Now", "ส่งเงินเดี๋ยวนี้"), Func = xDTaraZ.UI.Spawn(function()
        local ok, got = xDTaraZ.Atm.CashOut()
        xDTaraZ.UI.Notify(ok and ("Cashed out $" .. xDTaraZ.Util.Commas(got)) or got, ok and "Success" or "Warning")
    end) })
    atmBox:AddButton({ Text = T("Scan Map For ATMs", "สแกนหา ATM ทั้งแมพ"), Func = xDTaraZ.UI.Spawn(function()
        xDTaraZ.UI.Notify(("Found %d ATM spots"):format(xDTaraZ.Atm.Sweep()))
    end) })
end

function xDTaraZ.UI.BuildAtmSafety(farmTab)
    local safetyBox = farmTab:AddRightGroupbox(T("ATM Safety", "ความปลอดภัย ATM"))
    xDTaraZ.UI.Toggle(safetyBox, "HopWhenEmpty", T("Server Hop When Empty", "ย้ายเซิร์ฟเมื่อ ATM หมด"), T("Moves to a new server once every ATM is taken", "ย้ายไปเซิร์ฟใหม่เมื่อ ATM ถูกปล้นหมดแล้ว"))
    xDTaraZ.UI.Toggle(safetyBox, "AvoidCops", T("Avoid Police", "หลบตำรวจ"), T("Skips ATMs with police standing close", "ข้าม ATM ที่มีตำรวจอยู่ใกล้"))
end

function xDTaraZ.UI.BuildFarm(window)
    local farmTab = window:AddTab(T("Farm", "ฟาร์ม"), "zap", T("Money farming", "ฟาร์มเงิน"))

    local statusBox = farmTab:AddLeftGroupbox(T("Status", "สถานะ"))
    xDTaraZ.UI.StatusLabel = statusBox:AddLabel("Loading...", true)
    statusBox:AddButton({ Text = T("Panic - All Off", "ฉุกเฉิน ปิดทั้งหมด"), Style = "Danger", Func = xDTaraZ.UI.Panic })

    xDTaraZ.UI.BuildAtm(farmTab)

    local discordBox = farmTab:AddRightGroupbox(T("Discord", "Discord"), "link")
    discordBox:AddLabel(Config.Discord)
    discordBox:AddButton({ Text = T("Copy Discord Link", "คัดลอกลิงก์ Discord"), Style = "Primary", Func = function()
        local copy = setclipboard or toclipboard
        local copied = type(copy) == "function" and pcall(copy, Config.Discord)
        xDTaraZ.UI.Notify(copied and "Discord link copied" or Config.Discord)
    end })

    local logBox = farmTab:AddRightGroupbox(T("Update Log", "อัปเดตล่าสุด"), "bell")
    for i = 1, math.min(2, #Config.UpdateLog) do
        local entry = Config.UpdateLog[i]
        logBox:AddParagraph({ Title = entry[1], Content = entry[2] })
    end

    xDTaraZ.UI.BuildAtmSafety(farmTab)

    local jobBox = farmTab:AddRightGroupbox(T("Jobs", "อาชีพ"))
    local jobDropdown = jobBox:AddDropdown("JobPick", {
        Text = T("Switch Job", "เปลี่ยนอาชีพ"),
        Values = xDTaraZ.Jobs.List(),
        Default = 1,
        Callback = function(value)
            State.Opt.JobPick = value
        end,
    })
    jobBox:AddButton({ Text = T("Start Job", "เริ่มงาน"), Style = "Primary", Func = xDTaraZ.UI.Spawn(function()
        xDTaraZ.UI.Notify(xDTaraZ.Jobs.Start(State.Opt.JobPick or "Criminal") and "Job started" or "Could not start job")
    end) }):AddButton({ Text = T("Quit Job", "ออกจากงาน"), Func = xDTaraZ.UI.Spawn(xDTaraZ.Jobs.Leave) })
        :AddButton({ Text = T("Refresh", "รีเฟรช"), Func = function()
            jobDropdown:SetValues(xDTaraZ.Jobs.List())
        end })

    local driveBox = farmTab:AddRightGroupbox(T("Drive Farm", "ฟาร์มขับรถ"))
    xDTaraZ.UI.Toggle(driveBox, "DriveFarm", T("Auto Drive", "ขับรถอัตโนมัติ"), T("Drives nonstop for passive cash", "ขับไม่หยุดเพื่อรับเงินจากการขับ"), function(on)
        if not on then
            xDTaraZ.Drive.Stop()
            return
        end
        task.spawn(xDTaraZ.Util.Try, xDTaraZ.UI.StartDrive)
    end):AddKeyPicker("DriveFarmKey", { Default = "None", Mode = "Toggle" })
end

function xDTaraZ.UI.BuildRewards(window)
    local rewardTab = window:AddTab(T("Rewards", "รางวัล"), "bell", T("Codes and claims", "โค้ดและรับรางวัล"))

    local codeBox = rewardTab:AddLeftGroupbox(T("Codes", "โค้ด"))
    codeBox:AddButton({ Text = T("Redeem All Codes", "ใช้โค้ดทั้งหมด"), Style = "Primary", Func = xDTaraZ.UI.Spawn(function()
        if not GameLib.CodeRemote then
            xDTaraZ.UI.Notify("The code box was not found in this game version", "Warning")
            return
        end
        local count, cash = xDTaraZ.Rewards.RedeemCodes(Config.Codes)
        xDTaraZ.UI.Notify(("Redeemed %d new codes (+$%s)"):format(count, xDTaraZ.Util.Commas(cash)))
    end) })
    codeBox:AddInput("Code", {
        Text = T("Custom Code", "ใส่โค้ดเอง"),
        Default = "",
        Finished = true,
        NoSave = true,
        Callback = function(value)
            State.Opt.Code = value
        end,
    })
    codeBox:AddButton({ Text = T("Redeem", "ใช้โค้ด"), Func = xDTaraZ.UI.Spawn(function()
        local count = xDTaraZ.Rewards.RedeemCodes({ State.Opt.Code })
        xDTaraZ.UI.Notify(count > 0 and "Code redeemed" or "Code invalid or already used")
    end) })

    local claimBox = rewardTab:AddRightGroupbox(T("Claims", "รับรางวัล"))
    xDTaraZ.UI.Toggle(claimBox, "AutoPlaytime", T("Auto Playtime Rewards", "รับรางวัลเวลาเล่นอัตโนมัติ"), T("Claims cash, cars and packs as soon as they unlock", "รับเงิน รถ และแพ็กทันทีที่ปลดล็อก"))
        :AddKeyPicker("AutoPlaytimeKey", { Default = "None", Mode = "Toggle" })
    xDTaraZ.UI.Toggle(claimBox, "AutoClaimMisc", T("Auto Claim Pending", "รับรางวัลค้างอัตโนมัติ"), T("Claims pending race and event rewards", "รับรางวัลแข่งและอีเวนต์ที่ค้างอยู่"))
    claimBox:AddButton({ Text = T("Claim All Now", "รับทั้งหมดเดี๋ยวนี้"), Style = "Primary", Func = xDTaraZ.UI.Spawn(function()
        local count = xDTaraZ.Rewards.ClaimPlaytime()
        xDTaraZ.Rewards.ClaimMisc()
        xDTaraZ.UI.Notify(("Claimed %d playtime rewards"):format(count))
    end) })
end

function xDTaraZ.UI.BuildVehicle(window)
    local carTab = window:AddTab(T("Vehicle", "รถ"), "play", T("Cars and driving", "รถและการขับ"))
    local read, owned = pcall(xDTaraZ.Vehicle.Owned)
    owned = read and owned or {}
    State.Opt.DriveCar = owned[1]

    local carBox = carTab:AddLeftGroupbox(T("Garage", "โรงรถ"))
    local carDropdown = carBox:AddDropdown("DriveCar", {
        Text = T("Car", "รถ"),
        Values = owned,
        Default = 1,
        Searchable = true,
        Callback = function(value)
            State.Opt.DriveCar = value
        end,
    })
    carBox:AddButton({ Text = T("Spawn Car", "เรียกรถ"), Style = "Primary", Func = xDTaraZ.UI.Spawn(function()
        xDTaraZ.UI.Notify(xDTaraZ.Vehicle.Spawn(State.Opt.DriveCar) and "Car spawned" or "Spawn failed")
    end) }):AddButton({ Text = T("Despawn", "เก็บรถ"), Func = xDTaraZ.UI.Spawn(xDTaraZ.Vehicle.Despawn) })
        :AddButton({ Text = T("Refresh", "รีเฟรช"), Func = function()
            carDropdown:SetValues(xDTaraZ.Vehicle.Owned())
        end })

    local tuneBox = carTab:AddRightGroupbox(T("Performance", "สมรรถนะ"))
    xDTaraZ.UI.Slider(tuneBox, "CarSpeed", T("Car Speed Boost", "เร่งความเร็วรถ"), T("Holds this speed while pressing W (0 = off)", "คงความเร็วนี้ขณะกด W (0 = ปิด)"), 0, 600)
end

local function PlayerNames()
    local names = {}
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= LocalPlayer then table.insert(names, other.Name) end
    end
    return names
end

function xDTaraZ.UI.BuildTeleport(window)
    local teleportTab = window:AddTab(T("Teleport", "วาร์ป"), "globe", T("Go anywhere", "ไปได้ทุกที่"))
    local read, destNames, destinations = pcall(xDTaraZ.Teleport.Destinations)
    if not read then destNames, destinations = {}, {} end

    local placeBox = teleportTab:AddLeftGroupbox(T("Places", "สถานที่"))
    local placeDropdown = placeBox:AddDropdown("Place", {
        Text = T("Destination", "จุดหมาย"),
        Values = destNames,
        Default = 1,
        Searchable = true,
        Callback = function(value)
            State.Opt.Place = value
        end,
    })
    placeBox:AddButton({ Text = T("Teleport", "วาร์ป"), Style = "Primary", Func = xDTaraZ.UI.Spawn(function()
        xDTaraZ.Teleport.Go(destinations[State.Opt.Place or destNames[1]])
    end) }):AddButton({ Text = T("Refresh", "รีเฟรช"), Func = function()
        destNames, destinations = xDTaraZ.Teleport.Destinations()
        placeDropdown:SetValues(destNames)
    end })

    local playerBox = teleportTab:AddRightGroupbox(T("Players", "ผู้เล่น"))
    local playerDropdown = playerBox:AddDropdown("TargetPlayer", {
        Text = T("Player", "ผู้เล่น"),
        Values = PlayerNames(),
        Searchable = true,
        AllowNull = true,
        NoSave = true,
        Callback = function(value)
            State.Opt.TargetPlayer = value
        end,
    })
    playerBox:AddButton({ Text = T("Teleport To Player", "วาร์ปไปหาผู้เล่น"), Style = "Primary", Func = xDTaraZ.UI.Spawn(function()
        xDTaraZ.Teleport.ToPlayer(State.Opt.TargetPlayer)
    end) }):AddButton({ Text = T("Refresh", "รีเฟรช"), Func = function()
        playerDropdown:SetValues(PlayerNames())
    end })
end

function xDTaraZ.UI.BuildPlayer(window)
    local playerTab = window:AddTab(T("Player", "ผู้เล่น"), "user", T("Movement", "การเคลื่อนที่"))

    local moveBox = playerTab:AddLeftGroupbox(T("Movement", "การเคลื่อนที่"))
    xDTaraZ.UI.Toggle(moveBox, "SpeedEnabled", T("Custom Speed", "ปรับความเร็วเอง"), T("Uses the speed and jump below while on foot", "ใช้ความเร็วและแรงกระโดดด้านล่างตอนเดิน"), function(on)
        if not on then xDTaraZ.Movement.ResetSpeed() end
    end):AddKeyPicker("SpeedEnabledKey", { Default = "None", Mode = "Toggle" })
    xDTaraZ.UI.Slider(moveBox, "WalkSpeed", T("Walk Speed", "ความเร็วเดิน"), nil, 16, 200)
    xDTaraZ.UI.Slider(moveBox, "JumpPower", T("Jump Power", "แรงกระโดด"), nil, 50, 300)

    local abilityBox = playerTab:AddRightGroupbox(T("Abilities", "ความสามารถ"))
    xDTaraZ.UI.Toggle(abilityBox, "Noclip", T("Noclip", "ทะลุวัตถุ"), T("Walk through walls", "เดินทะลุกำแพง"), xDTaraZ.Movement.SetNoclip)
    xDTaraZ.UI.Toggle(abilityBox, "InfiniteJump", T("Infinite Jump", "กระโดดไม่จำกัด"), T("Jump again in mid air", "กระโดดซ้ำกลางอากาศได้"))

    local worldBox = playerTab:AddRightGroupbox(T("World", "โลก"))
    xDTaraZ.UI.Toggle(worldBox, "Fullbright", T("Fullbright", "สว่างเต็มจอ"), T("Always daylight", "กลางวันตลอด"), xDTaraZ.Movement.SetFullbright)
end

function xDTaraZ.UI.BuildVisuals(window)
    local visualTab = window:AddTab(T("Visuals", "ภาพ"), "eye", T("ESP", "ESP"))
    local espBox = visualTab:AddLeftGroupbox(T("Robbery", "การปล้น"))
    xDTaraZ.UI.Toggle(espBox, "EspAtm", T("ATMs", "ATM"), T("Shows every ATM you can rob with its rarity", "โชว์ ATM ที่ปล้นได้ทุกตู้พร้อมระดับ"))
    xDTaraZ.UI.Toggle(espBox, "EspDropOff", T("Drop-off Points", "จุดส่งเงิน"), T("Where outlaws cash out", "จุดที่โจรไปส่งเงิน"))

    local peopleBox = visualTab:AddRightGroupbox(T("Players", "ผู้เล่น"))
    xDTaraZ.UI.Toggle(peopleBox, "EspCops", T("Players By Job", "ผู้เล่นตามอาชีพ"), T("Blue = police, red = outlaw, orange = delivery", "น้ำเงิน = ตำรวจ, แดง = โจร, ส้ม = ส่งของ"))
end

function xDTaraZ.UI.BuildSettings(window)
    local settingsTab = window:AddSettingsTab()
    local sessionBox = settingsTab:AddRightGroupbox(T("Session", "เซสชัน"))
    xDTaraZ.UI.Toggle(sessionBox, "AntiAfk", T("Anti AFK", "กันหลุด AFK"), T("Never get kicked for idling", "ไม่โดนเตะเพราะยืนนิ่ง"))
    xDTaraZ.UI.Toggle(sessionBox, "AutoRejoin", T("Auto Rejoin", "เข้าเกมใหม่อัตโนมัติ"), T("Rejoins after a disconnect", "หลุดแล้วเข้าเกมใหม่เอง"))
    sessionBox:AddButton({ Text = T("Server Hop", "ย้ายเซิร์ฟ"), Func = xDTaraZ.UI.Spawn(xDTaraZ.Session.Hop) })
end

---Features whose game module or remote is missing refuse to turn on and say why, instead of erroring every tick.
function xDTaraZ.UI.GateModules()
    local noExecutor = T("Not available on this executor", "ใช้กับ executor นี้ไม่ได้")
    local changed = T("Not found after a game update", "หาไม่เจอหลังเกมอัปเดต")
    local en, th = {}, {}
    for idx in pairs(GameLib.Needs) do
        local option = Library.Options[idx]
        local missing = option and GameLib.Missing(idx)
        if missing then
            Library.Compat.Block(option, GameLib.Parts[missing] and changed or noExecutor)
            warn("[Driving Empire] " .. idx .. " off, missing " .. (GameLib.Parts[missing] or "module " .. missing))
            en[#en + 1] = option.Info.Text.EN
            table.insert(th, option.Info.Text.TH)
        end
    end
    if not GameLib.CodeRemote then warn("[Driving Empire] Redeem off, missing remote Code") end
    if #en == 0 then return end

    Library:Notify("Driving Empire", T("Not available on this executor: " .. table.concat(en, ", "), "ใช้กับ executor นี้ไม่ได้: " .. table.concat(th, ", ")), 8, "Warning")
end

---Runs on the UI's own thread: game-module threads cannot touch widgets, so halts and messages wait here.
function xDTaraZ.UI.Pump()
    while #State.Messages > 0 do
        local msg = table.remove(State.Messages, 1)
        Library:Notify("Driving Empire", msg[1], 5, msg[2])
    end
    while #State.Halted > 0 do
        local toggle = Library.Toggles[table.remove(State.Halted, 1)]
        if toggle and toggle.Value then toggle:SetValue(false) end
    end
    local label = xDTaraZ.UI.StatusLabel
    if label then label:SetText(xDTaraZ.UI.StatusText()) end
end

function xDTaraZ.UI.Build()
    local window = Library.Window
    local try = xDTaraZ.Util.Try
    window:AddTabSection(T("Main", "หลัก"))
    for _, build in ipairs({ xDTaraZ.UI.BuildFarm, xDTaraZ.UI.BuildRewards, xDTaraZ.UI.BuildVehicle, xDTaraZ.UI.BuildTeleport, xDTaraZ.UI.BuildPlayer, xDTaraZ.UI.BuildVisuals, xDTaraZ.UI.BuildSettings }) do
        try(build, window)
    end
    try(xDTaraZ.UI.GateModules)
    Library:Every(1, xDTaraZ.UI.Pump)
end

---@return boolean  false when the menu could not load
local function BuildInterface()
    Library = xDTaraZ.Util.LoadLibrary()
    if not Library then return false end
    xDTaraZ.Library = Library
    pcall(NovaBanner.Step, "UI library")
    T = function(en, th) return Library:T(en, th) end

    Library:OnUnload(function()
        xDTaraZ.Scheduler.Stop()
        getgenv().DrivingEmpireUnload = nil
    end)
    getgenv().DrivingEmpireUnload = function()
        Library:Unload()
    end

    Library:CreateWindow({
        Title = "Nova Hub",
        SubTitle = "Driving Empire by xDTaraZ",
        MenuKey = Enum.KeyCode.LeftControl,
        ConfigFolder = Config.SaveFolder,
        Language = "Auto",
        Theme = "Nova",
        Intro = true,
        OnUnlocked = function()
            xDTaraZ.UI.Build()
            xDTaraZ.Util.Try(xDTaraZ.Scheduler.Boot)
            xDTaraZ.UI.Notify("Loaded", "Success")
            xDTaraZ.Util.Try(Library.LoadAutoloadConfig, Library)
        end,
    })
    return true
end

if getgenv().DrivingEmpireUnload then
    pcall(getgenv().DrivingEmpireUnload)
end

pcall(NovaBanner.Step, "Systems")
if BuildInterface() then
    pcall(NovaBanner.Step, "Interface")
    pcall(NovaBanner.Ready)
end]==]

NOVA_HUB_MODULES[9534705677] = [==[if not game:IsLoaded() then
    game.Loaded:Wait()
end

if game.GameId ~= 9534705677 then
    game:GetService("Players").LocalPlayer:Kick("Nova Hub: this script is for Sniper Arena only")
    return
end

if not LPH_OBFUSCATED then
    local function Passthrough(fn) return fn end
    LPH_JIT, LPH_JIT_MAX, LPH_NO_VIRTUALIZE = Passthrough, Passthrough, Passthrough
end

local environment = getgenv and getgenv() or _G
if type(environment.SniperArenaUnload) == "function" then
    pcall(environment.SniperArenaUnload)
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local osClock = os.clock

local xDTaraZ = setmetatable({}, {
    __newindex = function(self, key, value)
        rawset(self, key, type(value) == "function" and LPH_JIT(value) or value)
    end,
})

xDTaraZ.Config = {
    UiSource = "NovaHub://embedded-ui",
    Discord = "https://discord.gg/FHVfmeSceA",
    UpdateLog = {
        { "2026-10-03", "Classic Nova Hub UI is back\nBetter executor support\nImproved Combat & Movement" },
    },
    SaveFolder = "Sniper Arena",
    Intro = true,
    LoadTimeout = 10,
    AlertTries = 20,
    AlertGap = 0.5,
    RequireTimeout = 5,
    RequireBudget = 15,
    MaxFails = 5,
    FailWindow = 10,
    FovColor = Color3.fromRGB(232, 160, 76),
    BannerCaps = { "HookFunction", "Namecall", "Gc", "Upvalues", "Drawing", "Connections", "FileSystem" },
    PanicNova = { NovaEsp = true, NovaRadar = true },
    CombatToggles = { "Aimbot", "SilentAim", "Ragebot", "TriggerBot", "NoRecoil", "NoSpread", "InstantScope" },
    ModuleFeatures = {
        EntityService = { "Aimbot", "SilentAim", "Ragebot", "TriggerBot" },
        CombatService = { "SilentAim", "Ragebot", "TriggerBot", "NoRecoil", "NoSpread", "InstantScope", "SkinChanger" },
        CameraController = { "SilentAim", "Ragebot" },
        WeaponConfig = { "SkinChanger" },
        GachaService =