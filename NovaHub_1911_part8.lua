TaraZ.Game.Profile()
    local _, worldId = xDTaraZ.Game.World()
    local world = xDTaraZ.WorldById[worldId]
    if not (data and world and world.NextWorldId) or data[world.NextWorldId .. "Unlocked"] then return false end
    local milestones = world.Throw and world.Throw.DistanceMilestones or GameLib.Balance.Throw.DistanceMilestones
    local last = milestones[#milestones]
    return last ~= nil and (tonumber(data.Level) or 0) >= last.Level
end

---@return boolean  true if a throw is worth more than training right now
function xDTaraZ.Throw.NeedWins()
    local opt = State.Opt
    if opt.AutoTravel and xDTaraZ.Throw.PortalReachable() then return true end
    if opt.AutoBuyStone and xDTaraZ.Shop.NextStone() and not xDTaraZ.Shop.Affordable() then return true end
    if opt.AutoHatch then return true end
    return false
end

xDTaraZ.Farm = {}

function xDTaraZ.Farm.Step()
    local mode = State.Opt.FarmMode
    if mode ~= "Throw" and xDTaraZ.Shop.Pending() then
        local spot = xDTaraZ.Move.LaunchSpot()
        State.Status = "Rebirth / buying stones"
        if spot and xDTaraZ.Move.Travel(spot) then
            task.wait(0.5)
            xDTaraZ.Shop.IdleTasks()
        end
        return
    end
    if mode == "Train" then
        xDTaraZ.Train.Step()
        return
    end
    if mode == "Throw" or xDTaraZ.Throw.NeedWins() then
        if not xDTaraZ.Throw.Once() then task.wait(0.5) end
        return
    end
    xDTaraZ.Train.Step()
end

xDTaraZ.Shop = {}

---@return table?  cheapest unowned stone of this world
function xDTaraZ.Shop.NextStone()
    local data = xDTaraZ.Game.Profile()
    local _, worldId = xDTaraZ.Game.World()
    local world = xDTaraZ.WorldById[worldId]
    if not (data and world) then return nil end
    local owned = data.OwnedStones or {}
    for _, id in ipairs(world.StoneIds) do
        local stone = xDTaraZ.StoneById[id]
        if stone and not owned[id] then return stone end
    end
    return nil
end

function xDTaraZ.Shop.BestOwned()
    local data = xDTaraZ.Game.Profile()
    if not data then return nil end
    local best
    for id in pairs(data.OwnedStones or {}) do
        local stone = xDTaraZ.StoneById[id]
        if stone and (not best or stone.Multiplier > best.Multiplier) then best = stone end
    end
    return best
end

function xDTaraZ.Shop.BuyStones()
    local data = xDTaraZ.Game.Profile()
    if not data then return end
    if xDTaraZ.Game.Activity() ~= "Idle" then return end
    local pick = xDTaraZ.Shop.Affordable()
    if pick then
        xDTaraZ:Send("Buy", pick.Id)
        xDTaraZ:Notify("Bought " .. pick.Name)
        task.wait(0.5)
    end

    local best = xDTaraZ.Shop.BestOwned()
    if best and data.EquippedStone ~= best.Id then xDTaraZ:Send("Equip", best.Id) end
end

function xDTaraZ.Shop.Affordable()
    local data = xDTaraZ.Game.Profile()
    local _, worldId = xDTaraZ.Game.World()
    local world = xDTaraZ.WorldById[worldId]
    if not (data and world) then return nil end
    local budget = xDTaraZ.Game.Wins() - State.Opt.StoneReserve
    local owned = data.OwnedStones or {}
    local pick
    for _, id in ipairs(world.StoneIds) do
        local stone = xDTaraZ.StoneById[id]
        if stone and not owned[id] and stone.Price <= budget and (not pick or stone.Multiplier > pick.Multiplier) then
            pick = stone
        end
    end
    return pick
end

function xDTaraZ.Shop.CanRebirth()
    local data = xDTaraZ.Game.Profile()
    if not data then return false end
    if osClock() - (State.Last.RebirthSent or 0) < Config.RebirthInterval then return false end
    return (tonumber(data.Level) or 0) >= xDTaraZ.Game.RebirthLevel(data)
end

---@return boolean  something needs the player idle outside training
function xDTaraZ.Shop.Pending()
    local opt = State.Opt
    if opt.AutoBuyStone and xDTaraZ.Shop.Affordable() then return true end
    return opt.AutoRebirth and xDTaraZ.Shop.CanRebirth()
end

function xDTaraZ.Shop.IdleTasks()
    if State.Opt.AutoRebirth then xDTaraZ.Shop.Rebirth() end
    if State.Opt.AutoBuyStone then xDTaraZ.Shop.BuyStones() end
end

function xDTaraZ.Shop.Rebirth()
    local data = xDTaraZ.Game.Profile()
    if not data then return end
    if xDTaraZ.Game.Activity() ~= "Idle" or not xDTaraZ.Shop.CanRebirth() then return end
    local rebirths = tonumber(data.Rebirths) or 0
    State.Last.RebirthSent = osClock()
    xDTaraZ:Send("Rebirth", rebirths)
    xDTaraZ:Notify("Rebirth " .. (rebirths + 1))
end

function xDTaraZ.Shop.Travel()
    local data = xDTaraZ.Game.Profile()
    local _, worldId = xDTaraZ.Game.World()
    local world = xDTaraZ.WorldById[worldId]
    local nextId = world and world.NextWorldId
    if not (data and nextId and data[nextId .. "Unlocked"]) then return end
    if xDTaraZ.Shop.NextStone() then return end
    local current = xDTaraZ.Game.World()
    local prompt = current and current:FindFirstChild("WorldPortal") and current.WorldPortal:FindFirstChild("WorldTravelPrompt", true)
    if not prompt then return end
    State.Status = "Traveling to " .. nextId
    if not xDTaraZ.Move.Travel(prompt.Parent.WorldPosition) then return end
    if xDTaraZ:Can("Prompt") then
        fireproximityprompt(prompt)
    else
        prompt:InputHoldBegin()
        task.wait(prompt.HoldDuration)
        prompt:InputHoldEnd()
    end
    xDTaraZ:Notify("Traveling to " .. nextId)
end

xDTaraZ.Pets = {}

function xDTaraZ.Pets.EggList()
    local list = {}
    local world = xDTaraZ.Game.World()
    local displays = world and world:FindFirstChild("EggShop") and world.EggShop:FindFirstChild("Displays")
    if not displays then return list end
    for _, egg in ipairs(displays:GetChildren()) do
        if egg:GetAttribute("Wins") then table.insert(list, { egg.Name, egg:GetAttribute("Wins") }) end
    end
    table.sort(list, function(a, b) return a[2] < b[2] end)
    return list
end

---@return string?  chosen egg id, "Best" = priciest one you can afford
function xDTaraZ.Pets.PickEgg()
    local choice = State.Opt.HatchEgg
    if choice ~= "Best" then return choice end
    local spendable = xDTaraZ.Game.Wins() - State.Opt.HatchReserve
    local pick
    for _, egg in ipairs(xDTaraZ.Pets.EggList()) do
        if egg[2] <= spendable then pick = egg[1] end
    end
    return pick
end

function xDTaraZ.Pets.HatchShop()
    local data = xDTaraZ.Game.Profile()
    local eggId = xDTaraZ.Pets.PickEgg()
    local pos, egg = xDTaraZ.Move.EggSpot(eggId or "")
    if not (data and pos) then return end
    local price = egg:GetAttribute("Wins") or math.huge
    local function Batch()
        local spendable = xDTaraZ.Game.Wins() - State.Opt.HatchReserve
        return math.min(math.max(1, tonumber(data.MultiHatchCount) or 1), math.floor(spendable / price))
    end
    if Batch() < 1 then return end

    State.Status = "Hatching " .. eggId
    if not xDTaraZ.Move.Travel(pos) then return end
    for _ = 1, Config.HatchBurst do
        local count = Batch()
        if count < 1 or not xDTaraZ.Scheduler.Live() then break end
        State.HatchId = (State.HatchId or 0) + 1
        xDTaraZ:Send("HatchEgg", { EggId = eggId, Count = count, RequestId = State.HatchId })
        State.LastHatch = osClock()
        task.wait(Config.HatchCooldown)
        xDTaraZ.Game.SkipReveal()
        data = xDTaraZ.Game.Profile() or data
    end
end

function xDTaraZ.Pets.HatchInventory()
    local data = xDTaraZ.Game.Profile()
    if not data then return end
    for eggId, amount in pairs(data.Eggs or {}) do
        if (tonumber(amount) or 0) > 0 then
            xDTaraZ:Send("HatchInventoryEgg", eggId)
            State.LastHatch = osClock()
            task.wait(1)
            xDTaraZ.Game.SkipReveal()
            return
        end
    end
end

---@return table?  pet id -> catalog entry (SkillMultiplier, Variant, BasePetId, FusionEligible)
function xDTaraZ.Pets.Catalog()
    if GameLib.PetCatalog ~= nil then return GameLib.PetCatalog or nil end
    local util = GameLib.Require(GameLib.Module("PetCatalog"))
    local assets = ReplicatedStorage:FindFirstChild("Assets")
    local folder = assets and assets:FindFirstChild("Pets")
    local ok, catalog = pcall(function() return util.Read(folder, GameLib.Balance.PetFusion) end)
    GameLib.PetCatalog = ok and type(catalog) == "table" and catalog.ById or false
    if not ok then warn("[StoneSkipping] pet catalog:", catalog) end
    return GameLib.PetCatalog or nil
end

---Reveals every newly found pet in the index, then claims the luck milestone once enough are revealed.
function xDTaraZ.Pets.ClaimIndex()
    local data = xDTaraZ.Game.Profile()
    if not data then return end
    local pending, count = {}, 0
    for petId, mark in pairs(data.PetIndex or {}) do
        count += 1
        if mark == 1 then pending[#pending + 1] = petId end
    end
    if #pending > 0 then
        xDTaraZ:Send("RevealPets", pending)
        task.wait(Config.FuseGap)
    end

    local claimed = tonumber(data.PetIndexClaimed) or 0
    local earned = math.floor(count / GameLib.Balance.PetIndex.MilestoneStep)
    if earned <= claimed or State.Last.IndexClaimAt == claimed then return end
    State.Last.IndexClaimAt = claimed
    xDTaraZ:Send("ClaimPetIndex")
end

---@return table?  { variant, ids, name, power } strongest three-of-a-kind worth fusing; equipped pets are never used
function xDTaraZ.Pets.FusionPick(data, catalog)
    local equipped, weakest = {}, math.huge
    for _, id in ipairs(data.EquippedPets or {}) do equipped[id] = true end
    for _, pet in ipairs(data.Pets or {}) do
        local info = equipped[pet.Id] and catalog[pet.PetId]
        if info then weakest = math.min(weakest, tonumber(info.SkillMultiplier) or 0) end
    end
    if weakest == math.huge then weakest = 0 end

    local running, groups, need = data.PetFusions or {}, {}, GameLib.Balance.PetFusion.FusionPets or 3
    for _, pet in ipairs(data.Pets or {}) do
        local info = not equipped[pet.Id] and catalog[pet.PetId]
        local target = info and Config.FuseNext[info.Variant or "Normal"]
        if not target or running[target] or not State.Opt.FuseVariants[target] then continue end
        if target == "Golden" and info.FusionEligible == false then continue end
        local group = groups[pet.PetId]
        if not group then
            local result = catalog[target:lower() .. "__" .. (info.BasePetId or pet.PetId)]
            if not result then continue end
            group = { variant = target, ids = {}, name = result.Name, power = tonumber(result.SkillMultiplier) or 0 }
            groups[pet.PetId] = group
        end
        if #group.ids < need then table.insert(group.ids, pet.Id) end
    end

    local best
    for _, group in pairs(groups) do
        if #group.ids < need then continue end
        if State.Opt.FuseMode == "Upgrades only" and group.power <= weakest then continue end
        if not best or group.power > best.power then best = group end
    end
    return best
end

function xDTaraZ.Pets.Fuse()
    local data, catalog = xDTaraZ.Game.Profile(), xDTaraZ.Pets.Catalog()
    if not (data and catalog) then return end
    local now = workspace:GetServerTimeNow()
    for variant, run in pairs(data.PetFusions or {}) do
        if type(run) == "table" and (tonumber(run.EndsAt) or math.huge) <= now then
            xDTaraZ:Send("PetEquipment", { Kind = "ClaimFusion", Variant = variant })
            task.wait(Config.FuseGap)
        end
    end

    for _ in pairs(Config.FuseNext) do
        data = xDTaraZ.Game.Profile() or data
        local pick = xDTaraZ.Pets.FusionPick(data, catalog)
        if not pick then return end
        xDTaraZ:Send("PetEquipment", { Kind = "Fuse", Variant = pick.variant, Ids = pick.ids })
        table.insert(State.Messages, "Fusing " .. tostring(pick.name))
        task.wait(Config.FuseGap)
    end
end

xDTaraZ.Rewards = {}

function xDTaraZ.Rewards.Claim()
    local data = xDTaraZ.Game.Profile()
    if not data then return end
    local now = osTime()

    local gifts = GameLib.Balance.GiftRewards
    local claimed = data.GiftClaimed or {}
    local started = tonumber(data.GiftStartedAt) or now
    if now >= (tonumber(data.GiftCooldownUntil) or 0) then
        for i, unlock in ipairs(gifts.UnlockSeconds) do
            if not (claimed[i] or claimed[tostring(i)]) and now - started >= unlock then
                xDTaraZ:Send("ClaimGift", i)
                task.wait(0.3)
            end
        end
    end

    if now >= (tonumber(data.DailyNextClaimAt) or math.huge) then
        local day = (tonumber(data.DailyClaimed) or 0) % #GameLib.Balance.DailyRewards.Rewards + 1
        xDTaraZ:Send("ClaimDaily", { Day = day, Cycle = data.DailyCycle or 0 })
    end

    if (tonumber(data.OfflineSkill) or 0) > 0 then xDTaraZ:Send("ClaimOffline") end

    if not data.FreeRewardClaimed and not State.Last.FreeTried then
        State.Last.FreeTried = true
        xDTaraZ:Send("ClaimFreeReward")
    end
end

function xDTaraZ.Rewards.UsePotions()
    local data = xDTaraZ.Game.Profile()
    if not data then return end
    local active = data.BoostExpiresAt or {}
    local now = osTime()
    for kind, count in pairs(data.Potions or {}) do
        if State.Opt.Potions[kind] and (tonumber(count) or 0) > 0 and (tonumber(active[kind]) or 0) <= now then
            xDTaraZ:Send("UsePotion", kind)
            task.wait(0.5)
        end
    end
end

---@return string[]  known potion kinds plus any new kind found in your saved data
function xDTaraZ.Rewards.PotionKinds()
    local kinds = table.clone(Config.PotionKinds)
    local known = {}
    for _, kind in ipairs(kinds) do known[kind] = true end

    local data = xDTaraZ.Game.Profile()
    for kind in pairs(data and data.Potions or {}) do
        if not known[kind] then table.insert(kinds, kind) end
    end
    return kinds
end

function xDTaraZ.Rewards.RedeemAll()
    for _, code in ipairs(Config.Codes) do
        xDTaraZ:Send("RedeemCode", code)
        task.wait(1)
    end
    xDTaraZ:Notify(("Tried %d codes"):format(#Config.Codes))
end

xDTaraZ.Client = {}

function xDTaraZ.Client.Bind()
    if GameLib.Event then
        table.insert(State.Connections, GameLib.Event.OnClientEvent:Connect(function(action, info)
            if action == "CodeResult" or action == "GiftRewardResult" then
                local msg = type(info) == "table" and info.Message or info
                if msg ~= nil then table.insert(State.Messages, tostring(msg)) end
            elseif type(info) == "table" and (action == "Bounce" or action == "PracticeGain") then
                State.SkillEarned += tonumber(info.Skill) or 0
            end
        end))
    end

    table.insert(State.Connections, LocalPlayer.Idled:Connect(function()
        if not State.Opt.AntiAfk then return end
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.zero)
    end))

    table.insert(State.Connections, UserInputService.JumpRequest:Connect(function()
        if not State.Opt.InfJump then return end
        local _, hum = xDTaraZ:Character()
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end))

    table.insert(State.Connections, LocalPlayer.CharacterAdded:Connect(function(char)
        char:WaitForChild("Humanoid", Config.LoadTimeout)
        State.BaseSpeed = nil
        xDTaraZ.Move.ApplySpeed()
    end))

    table.insert(State.Connections, GuiService.ErrorMessageChanged:Connect(function()
        if not State.Opt.AutoRejoin or State.Rejoining or GuiService:GetErrorMessage() == "" then return end
        State.Rejoining = true
        task.wait(Config.RejoinDelay)
        local ok, err = pcall(TeleportService.Teleport, TeleportService, game.PlaceId, LocalPlayer)
        if ok then return end
        warn("[StoneSkipping] rejoin:", err)
        State.Rejoining = false
    end))

    table.insert(State.Connections, TeleportService.TeleportInitFailed:Connect(function(player, _, msg)
        if player ~= LocalPlayer or not State.Rejoining then return end
        warn("[StoneSkipping] rejoin failed:", msg)
        State.Rejoining = false
    end))
end

xDTaraZ.Scheduler = {}

xDTaraZ.Scheduler.RequestHandlers = {
    Speed = xDTaraZ.Move.ApplySpeed,
    ThrowNow = xDTaraZ.Throw.Once,
    TrainNow = xDTaraZ.Train.Step,
    StoneNow = xDTaraZ.Shop.BuyStones,
    RebirthNow = function()
        local data = xDTaraZ.Game.Profile()
        if data then xDTaraZ:Send("Rebirth", tonumber(data.Rebirths) or 0) end
    end,
    TravelNow = xDTaraZ.Shop.Travel,
    HatchNow = xDTaraZ.Pets.HatchShop,
    InventoryNow = xDTaraZ.Pets.HatchInventory,
    IndexNow = xDTaraZ.Pets.ClaimIndex,
    FuseNow = xDTaraZ.Pets.Fuse,
    PotionNow = xDTaraZ.Rewards.UsePotions,
    ClaimNow = xDTaraZ.Rewards.Claim,
    CodesNow = xDTaraZ.Rewards.RedeemAll,
    LaunchTp = function()
        local pos = xDTaraZ.Move.LaunchSpot()
        if pos then xDTaraZ.Move.Travel(pos) end
    end,
    EggTp = function()
        local cheapest = xDTaraZ.Pets.EggList()[1]
        local eggId = xDTaraZ.Pets.PickEgg() or (cheapest and cheapest[1])
        local pos = eggId and xDTaraZ.Move.EggSpot(eggId)
        if pos then xDTaraZ.Move.Travel(pos) end
    end,
}

---Runs one round of a job; a toggle that keeps failing for Config.FailWindow seconds is switched off and queued for the UI to report.
---@param key string  State.Opt flag of the feature, or a plain label for jobs without one
function xDTaraZ.Scheduler.Run(key, fn)
    State.Running = key
    local ok, err = pcall(fn)
    State.Running = nil
    local failures = State.Failures
    if ok then
        failures[key] = nil
        return
    end

    local streak = failures[key]
    if not streak then
        streak = { count = 0, since = osClock() }
        failures[key] = streak
        warn("[StoneSkipping]", key, err)
    end
    streak.count += 1
    if streak.count < Config.MaxFailures or osClock() - streak.since < Config.FailWindow then return end
    if State.Opt[key] ~= true then return end

    failures[key] = nil
    State.Opt[key] = false
    local reason = tostring(err):match("[^\n]*")
    warn("[StoneSkipping]", key, "stopped:", reason)
    table.insert(State.Halted, { key, reason })
end

---@return boolean  false once the hub unloads or the running job's toggle is switched off
function xDTaraZ.Scheduler.Live()
    return State.Alive and State.Opt[State.Running or ""] ~= false
end

---@param stamp string  State.Last field holding the last run time
---@param key string    passed on to Run
function xDTaraZ.Scheduler.Every(stamp, key, interval, fn)
    if osClock() - (State.Last[stamp] or 0) < interval then return end
    State.Last[stamp] = osClock()
    xDTaraZ.Scheduler.Run(key, fn)
end

function xDTaraZ.Scheduler.Summarize()
    local data = xDTaraZ.Game.Profile()
    if not data then
        State.Summary = xDTaraZ:Unsupported() or "Waiting for game data..."
        return
    end
    local cutoff = osClock() - Config.RateWindow
    local recent = 0
    for i = #State.EarnLog, 1, -1 do
        local entry = State.EarnLog[i]
        if entry[1] < cutoff then table.remove(State.EarnLog, i) else recent += entry[2] end
    end
    local stone = xDTaraZ.StoneById[data.EquippedStone]
    State.Summary = ("Level %s · Rebirth %s · Wins %s\nStone %s (x%s) · %s wins/min"):format(
        tostring(data.Level), tostring(data.Rebirths), xDTaraZ.Format(data.Wins),
        stone and stone.Name or "-", stone and xDTaraZ.Format(stone.Multiplier) or "-",
        xDTaraZ.Format(recent * 60 / Config.RateWindow))
end

function xDTaraZ.Scheduler.Step()
    local opt = State.Opt
    xDTaraZ.Scheduler.Run("Summary", xDTaraZ.Scheduler.Summarize)
    if State.FarmRan and not opt.AutoFarm then
        State.FarmRan = false
        State.Status = "Idle"
    end

    for name, handler in pairs(xDTaraZ.Scheduler.RequestHandlers) do
        if State.Requests[name] then
            State.Requests[name] = nil
            xDTaraZ.Scheduler.Run(name, handler)
        end
    end

    local _, hum = xDTaraZ:Character()
    if not hum then return end
    if opt.SpeedOn and hum.WalkSpeed ~= opt.WalkSpeed then xDTaraZ.Move.ApplySpeed() end
    if xDTaraZ.Game.Activity() == "Throw" then return end
    if xDTaraZ.Game.HatchActive() then
        local asked = osClock() - State.LastHatch < Config.HatchTimeout
        if asked or opt.AutoHatch or opt.AutoInventoryHatch then xDTaraZ.Scheduler.Run("Reveal", xDTaraZ.Game.SkipReveal) end
        return
    end

    if opt.AutoClaim then xDTaraZ.Scheduler.Every("Claim", "AutoClaim", Config.ClaimInterval, xDTaraZ.Rewards.Claim) end
    if opt.AutoPetIndex then xDTaraZ.Scheduler.Every("PetIndex", "AutoPetIndex", Config.IndexInterval, xDTaraZ.Pets.ClaimIndex) end
    if opt.AutoFuse then xDTaraZ.Scheduler.Every("Fuse", "AutoFuse", Config.FuseInterval, xDTaraZ.Pets.Fuse) end
    if opt.AutoPotions then xDTaraZ.Scheduler.Every("Potion", "AutoPotions", Config.PotionInterval, xDTaraZ.Rewards.UsePotions) end
    if xDTaraZ.Game.Activity() == "Idle" then xDTaraZ.Scheduler.Every("Idle", "IdleTasks", Config.BuyInterval, xDTaraZ.Shop.IdleTasks) end
    if opt.AutoTravel then xDTaraZ.Scheduler.Every("Travel", "AutoTravel", Config.BuyInterval, xDTaraZ.Shop.Travel) end
    if opt.AutoInventoryHatch then xDTaraZ.Scheduler.Every("Inventory", "AutoInventoryHatch", Config.BuyInterval, xDTaraZ.Pets.HatchInventory) end
    if opt.AutoHatch then xDTaraZ.Scheduler.Every("Hatch", "AutoHatch", Config.BuyInterval, xDTaraZ.Pets.HatchShop) end
    if opt.AutoFarm then
        State.FarmRan = true
        xDTaraZ.Scheduler.Run("AutoFarm", xDTaraZ.Farm.Step)
    end
end

function xDTaraZ.Scheduler.Boot()
    xDTaraZ.Client.Bind()
    task.spawn(function()
        while State.Alive do
            xDTaraZ.Scheduler.Step()
            task.wait(Config.TickDelay)
        end
    end)
end

function xDTaraZ.Scheduler.Stop()
    State.Alive = false
    for _, conn in ipairs(State.Connections) do conn:Disconnect() end
    table.clear(State.Connections)
    State.Opt.SpeedOn = false
    xDTaraZ.Move.ApplySpeed()
end

local function BuildInterface()
    local Library = xDTaraZ.Util.LoadLibrary()
    if not Library then return end
    xDTaraZ.Compat = Library.Compat
    pcall(NovaBanner.Step, "UI library")
    local Options = Library.Options
    local T = function(en, th) return Library:T(en, th) end
    local opt = State.Opt
    local statusLabel, runLabel
    local gated = {}
    for _, key in ipairs(Config.GatedFeatures) do gated[key] = true end

    local function Notify(text, kind)
        Library:Notify("Stone Skipping", text, 4, kind or "Info")
    end

    local function Request(name)
        return function() State.Requests[name] = true end
    end

    local function Toggle(group, key, text, description, onChange)
        local toggle = group:AddToggle(key, {
            Text = text,
            Description = description,
            Default = opt[key],
            Callback = function(value)
                opt[key] = value
                if onChange then onChange(value) end
            end,
        })
        toggle.Info = toggle.Info or { Text = text }
        return toggle
    end

    local function Feature(group, key, text, description)
        return Toggle(group, key, text, description)
    end

    local function TitleOf(toggle, idx)
        local title = toggle and toggle.Row and toggle.Row.Title
        return title and title.Text or idx
    end

    local function ReportHalts()
        for _, halt in ipairs(State.Halted) do
            local toggle = Options[halt[1]]
            if toggle and toggle.Value then toggle:SetValue(false) end
            Notify(("%s stopped: %s"):format(TitleOf(toggle, halt[1]), halt[2]), "Warning")
        end
        table.clear(State.Halted)
    end

    local function BuildMain(window)
        window:AddTabSection(T("Main", "หลัก"))
        local MainTab = window:AddTab(T("Main", "หลัก"), "house", T("Status and all-in-one mode", "สถานะและโหมดทำทุกอย่าง"))

        local statusBox = MainTab:AddLeftGroupbox(T("Status", "สถานะ"), "star")
        statusLabel = statusBox:AddLabel(T("Loading...", "กำลังโหลด..."))
        runLabel = statusBox:AddLabel("-")

        local kaitunBox = MainTab:AddRightGroupbox(T("Kaitun", "ไก่ตัน"), "oneup")
        kaitunBox:AddToggle("Kaitun", {
            Text = T("Kaitun (All-in-one)", "ไก่ตัน (ทำทุกอย่าง)"),
            Description = T("Trains, throws, upgrades, rebirths and claims rewards by itself", "ฝึก ปาหิน อัปเกรด รีเบิร์ธ และรับรางวัลให้เอง"),
            NoSave = true,
            Callback = function(value)
                State.KaitunSet = State.KaitunSet or {}
                for _, key in ipairs({ "AutoFarm", "AutoBuyStone", "AutoRebirth", "AutoTravel", "AutoInventoryHatch", "AutoPotions", "AutoClaim", "AutoPetIndex", "AutoFuse", "AntiAfk" }) do
                    local toggle = Options[key]
                    if not toggle or toggle.Blocked or (gated[key] and xDTaraZ:Unsupported()) then continue end
                    if value and not opt[key] then
                        toggle:SetValue(true)
                        State.KaitunSet[key] = toggle.Value == true or nil
                    elseif not value and State.KaitunSet[key] then
                        State.KaitunSet[key] = nil
                        toggle:SetValue(false)
                    end
                end
            end,
        })
        kaitunBox:AddButton({ Text = T("Panic - All Off", "ฉุกเฉิน ปิดทั้งหมด"), Style = "Danger", Func = function()
            for idx, toggle in pairs(Library.Toggles) do
                if toggle.Value == true and not tostring(idx):find("^Nova") then toggle:SetValue(false) end
            end
        end })

        local discordBox = MainTab:AddRightGroupbox(T("Discord", "Discord"), "link")
        discordBox:AddLabel(Config.Discord)
        discordBox:AddButton({ Text = T("Copy Discord Link", "คัดลอกลิงก์ Discord"), Style = "Primary", Func = function()
            local copy = setclipboard or toclipboard
            if copy then copy(Config.Discord) end
            Notify(copy and "Discord link copied" or Config.Discord)
        end })

        local logBox = MainTab:AddRightGroupbox(T("Update Log", "อัปเดตล่าสุด"), "bell")
        for i = 1, math.min(2, #Config.UpdateLog) do
            local entry = Config.UpdateLog[i]
            logBox:AddParagraph({ Title = entry[1], Content = entry[2] })
        end
    end

    local function BuildFarm(window)
        window:AddTabSection(T("Farming", "ฟาร์ม"))
        local FarmTab = window:AddTab(T("Auto Farm", "ฟาร์มอัตโนมัติ"), "star", T("Throwing and training", "ปาหินและฝึก"))

        local farmBox = FarmTab:AddLeftGroupbox(T("Auto Farm", "ฟาร์มอัตโนมัติ"), "star")
        Feature(farmBox, "AutoFarm", T("Auto Farm", "ฟาร์มอัตโนมัติ"), T("Earns skill and wins without stopping", "ฟาร์ม Skill และ Wins ไม่หยุด"))
        farmBox:AddDropdown("FarmMode", {
            Text = T("Farm Mode", "โหมดฟาร์ม"),
            Description = T("Smart: throws for wins when needed, trains otherwise", "Smart: ปาหินเมื่อต้องใช้ Wins นอกนั้นฝึก Skill"),
            Values = { "Smart", "Train", "Throw" },
            Default = 1,
            Callback = function(value) opt.FarmMode = value or "Smart" end,
        })
        farmBox:AddButton({ Text = T("Throw Now", "ปาหินเดี๋ยวนี้"), Style = "Primary", Func = Request("ThrowNow") })

        local function ZoneNames()
            local names = { "Best" }
            for _, zone in ipairs(xDTaraZ.Train.Zones()) do
                if not zone.Pass or State.OwnedPasses[zone.Pass] == true then names[#names + 1] = zone.Name end
            end
            return names
        end

        local trainBox = FarmTab:AddRightGroupbox(T("Training", "ฝึก"), "target")
        local zoneDropdown = trainBox:AddDropdown("TrainZone", {
            Text = T("Training Zone", "โซนฝึก"),
            Description = T("Best = strongest zone you have unlocked", "Best = โซนที่ดีที่สุดที่ปลดล็อกแล้ว"),
            Values = ZoneNames(),
            Default = 1,
            Callback = function(value) opt.TrainZone = value or "Best" end,
        })
        trainBox:AddButton({ Text = T("Refresh Zones", "รีเฟรชรายการโซน"), Func = function()
            table.clear(State.OwnedPasses)
            xDTaraZ.Train.CheckPasses()
            zoneDropdown:SetValues(ZoneNames())
        end })
        task.spawn(function()
            xDTaraZ.Train.CheckPasses()
            zoneDropdown:SetValues(ZoneNames())
        end)
        trainBox:AddButton({ Text = T("Go Train Now", "ไปฝึกเดี๋ยวนี้"), Func = Request("TrainNow") })
    end

    local function BuildStones(window)
        window:AddTabSection(T("Progression", "ความคืบหน้า"))
        local ShopTab = window:AddTab(T("Stones & Rebirth", "หินและรีเบิร์ธ"), "shop", T("Stones, rebirth and worlds", "หิน รีเบิร์ธ และโลก"))

        local stoneBox = ShopTab:AddLeftGroupbox(T("Stones", "หิน"), "coin")
        Feature(stoneBox, "AutoBuyStone", T("Auto Buy Best Stone", "ซื้อหินดีสุดอัตโนมัติ"), T("Buys and equips the strongest stone you can afford", "ซื้อและใส่หินที่แรงที่สุดที่ซื้อไหว"))
        stoneBox:AddSlider("StoneReserve", {
            Text = T("Keep Wins", "กัน Wins ไว้"),
            Min = 0, Max = 100000, Default = 0, Rounding = 0,
            Callback = function(value) opt.StoneReserve = tonumber(value) or 0 end,
        })
        stoneBox:AddButton({ Text = T("Buy Best Stone Now", "ซื้อหินดีสุดเดี๋ยวนี้"), Func = Request("StoneNow") })

        local rebirthBox = ShopTab:AddRightGroupbox(T("Rebirth & Worlds", "รีเบิร์ธและโลก"), "flag")
        Feature(rebirthBox, "AutoRebirth", T("Auto Rebirth", "รีเบิร์ธอัตโนมัติ"), T("Rebirths as soon as your level is high enough", "รีเบิร์ธทันทีเมื่อเลเวลถึง"))
        rebirthBox:AddButton({ Text = T("Rebirth Now", "รีเบิร์ธเดี๋ยวนี้"), Func = Request("RebirthNow") })
        Feature(rebirthBox, "AutoTravel", T("Auto Next World", "ไปโลกถัดไปอัตโนมัติ"), T("Moves to the next world once it is unlocked and this world's stones are done", "ย้ายไปโลกถัดไปเมื่อปลดล็อกและซื้อหินโลกนี้ครบแล้ว"))
        rebirthBox:AddButton({ Text = T("Next World Now", "ไปโลกถัดไปเดี๋ยวนี้"), Func = Request("TravelNow") })
    end

    local function EggNames()
        local names = { "Best" }
        for _, egg in ipairs(xDTaraZ.Pets.EggList()) do table.insert(names, egg[1]) end
        return names
    end

    local function BuildPets(window)
        local PetTab = window:AddTab(T("Pets & Rewards", "สัตว์เลี้ยงและรางวัล"), "mushroom", T("Eggs, potions, rewards and codes", "ไข่ ยา รางวัล และโค้ด"))

        local eggBox = PetTab:AddLeftGroupbox(T("Eggs", "ไข่"), "mushroom")
        Feature(eggBox, "AutoHatch", T("Auto Hatch", "ฟักไข่อัตโนมัติ"), T("Buys and hatches the selected egg with wins", "ซื้อและฟักไข่ที่เลือกด้วย Wins"))
        local eggDropdown = eggBox:AddDropdown("HatchEgg", {
            Text = T("Egg", "ไข่"),
            Values = EggNames(),
            Default = 1,
            Callback = function(value) opt.HatchEgg = value or "Best" end,
        })
        eggBox:AddButton({ Text = T("Refresh Eggs", "รีเฟรชรายการไข่"), Func = function() eggDropdown:SetValues(EggNames()) end })
        eggBox:AddSlider("HatchReserve", {
            Text = T("Keep Wins", "กัน Wins ไว้"),
            Min = 0, Max = 100000, Default = 0, Rounding = 0,
            Callback = function(value) opt.HatchReserve = tonumber(value) or 0 end,
        })
        eggBox:AddButton({ Text = T("Hatch Now", "ฟักเดี๋ยวนี้"), Func = Request("HatchNow") })
        Feature(eggBox, "AutoInventoryHatch", T("Auto Open Inventory Eggs", "เปิดไข่ในกระเป๋าอัตโนมัติ"), T("Opens eggs from codes, gifts and daily rewards", "เปิดไข่ที่ได้จากโค้ด ของขวัญ และรางวัลรายวัน"))
        eggBox:AddButton({ Text = T("Open Inventory Egg Now", "เปิดไข่ในกระเป๋าเดี๋ยวนี้"), Func = Request("InventoryNow") })

        local rewardBox = PetTab:AddRightGroupbox(T("Rewards", "รางวัล"), "coin")
        Feature(rewardBox, "AutoClaim", T("Auto Claim", "รับรางวัลอัตโนมัติ"), T("Claims playtime gifts, daily, offline and group rewards", "รับของขวัญเวลาเล่น รางวัลรายวัน ออฟไลน์ และกลุ่ม"))
        rewardBox:AddButton({ Text = T("Claim Now", "รับเดี๋ยวนี้"), Func = Request("ClaimNow") })
        Feature(rewardBox, "AutoPotions", T("Auto Use Potions", "ใช้ยาอัตโนมัติ"), T("Keeps the selected boosts running", "เปิดบูสต์ที่เลือกไว้ตลอด"))
        local potionKinds = xDTaraZ.Rewards.PotionKinds()
        for _, kind in ipairs(potionKinds) do opt.Potions[kind] = true end
        rewardBox:AddDropdown("Potions", {
            Text = T("Potions", "ยา"),
            Values = potionKinds,
            Multi = true,
            Default = potionKinds,
            Callback = function(selected) opt.Potions = selected end,
        })
        rewardBox:AddButton({ Text = T("Use Potions Now", "ใช้ยาเดี๋ยวนี้"), Func = Request("PotionNow") })
        rewardBox:AddButton({ Text = T("Redeem All Codes", "ใช้โค้ดทั้งหมด"), Style = "Primary", Func = Request("CodesNow") })

        local fuseBox = PetTab:AddRightGroupbox(T("Fusion & Index", "หลอมรวมและสมุดสัตว์"), "star")
        Feature(fuseBox, "AutoFuse", T("Auto Fuse", "หลอมสัตว์อัตโนมัติ"), T("Fuses three of a kind into Golden or Diamond and claims them", "รวมสัตว์ซ้ำ 3 ตัวเป็นทองหรือเพชรแล้วรับให้เอง"))
        local variants = {}
        local fusion = GameLib.Balance and GameLib.Balance.PetFusion
        for variant, enabled in pairs(fusion and fusion.EnabledVariants or {}) do
            if enabled then variants[#variants + 1] = variant end
        end
        table.sort(variants, function(a, b) return (fusion.Durations[a] or 0) < (fusion.Durations[b] or 0) end)
        fuseBox:AddDropdown("FuseVariants", {
            Text = T("Fuse Into", "หลอมเป็น"),
            Values = variants,
            Multi = true,
            Default = variants,
            Callback = function(selected) opt.FuseVariants = selected end,
        })
        fuseBox:AddDropdown("FuseMode", {
            Text = T("Which Pets", "สัตว์ที่จะหลอม"),
            Description = T("Upgrades only = only when the result beats your weakest equipped pet", "เฉพาะที่อัปเกรด = หลอมเมื่อได้ตัวที่แรงกว่าตัวอ่อนสุดที่ใส่อยู่"),
            Values = { "Upgrades only", "All duplicates" },
            Default = 1,
            Callback = function(value) opt.FuseMode = value or "Upgrades only" end,
        })
        fuseBox:AddButton({ Text = T("Fuse Now", "หลอมเดี๋ยวนี้"), Func = Request("FuseNow") })
        Feature(fuseBox, "AutoPetIndex", T("Auto Pet Index", "สมุดสัตว์อัตโนมัติ"), T("Reveals new pets and claims the luck bonus", "เปิดสัตว์ใหม่ในสมุดและรับโบนัสโชค"))
        fuseBox:AddButton({ Text = T("Claim Index Now", "รับโบนัสสมุดเดี๋ยวนี้"), Func = Request("IndexNow") })
    end

    local function BuildPlayer(window)
        window:AddTabSection(T("Misc", "อื่นๆ"))
        local PlayerTab = window:AddTab(T("Player", "ผู้เล่น"), "user", T("Movement and teleports", "การเคลื่อนที่และวาร์ป"))

        local moveBox = PlayerTab:AddLeftGroupbox(T("Movement", "การเคลื่อนที่"), "star")
        Toggle(moveBox, "SpeedOn", T("Speed", "ความเร็ว"), nil, Request("Speed"))
        moveBox:AddSlider("WalkSpeed", {
            Text = T("Walk Speed", "ความเร็วเดิน"),
            Min = 16, Max = 150, Default = opt.WalkSpeed, Rounding = 0,
            Callback = function(value)
                opt.WalkSpeed = tonumber(value) or opt.WalkSpeed
                State.Requests.Speed = true
            end,
        })
        Toggle(moveBox, "InfJump", T("Infinite Jump", "กระโดดไม่จำกัด"))

        local tpBox = PlayerTab:AddRightGroupbox(T("Teleport", "วาร์ป"), "teleport")
        tpBox:AddButton({ Text = T("Throw Zone", "โซนปาหิน"), Func = Request("LaunchTp") })
        tpBox:AddButton({ Text = T("Best Training Zone", "โซนฝึกที่ดีที่สุด"), Func = Request("TrainNow") })
        tpBox:AddButton({ Text = T("Selected Egg", "ไข่ที่เลือก"), Func = Request("EggTp") })
    end

    local function BuildSettings(window)
        local settingsTab = window:AddSettingsTab()
        local sessionBox = settingsTab:AddRightGroupbox(T("Session", "เซสชัน"), "gear")
        Toggle(sessionBox, "AntiAfk", T("Anti AFK", "กันหลุด AFK"), T("Stops the idle kick", "กันโดนเตะเพราะไม่ขยับ"))
        Toggle(sessionBox, "AutoRejoin", T("Auto Rejoin", "เข้าเกมใหม่อัตโนมัติ"), T("Rejoins by itself after a disconnect", "หลุดแล้วเข้าเกมใหม่เอง"))
    end

    local function GateFeatures()
        for _, idx in ipairs(Config.GatedFeatures) do
            local toggle = Options[idx]
            if not toggle then continue end
            toggle:AddGuard(function(value)
                if value ~= true then return true end
                local en, th = xDTaraZ:Unsupported()
                if not en then return true end
                local title = TitleOf(toggle, idx)
                Library:Notify("Nova Hub", T(("%s: %s"):format(title, en), ("%s: %s"):format(title, th)), 4, "Warn")
                task.defer(toggle.SetValue, toggle, false)
                return false
            end)
        end
        for idx, paths in pairs(GameLib.Ready and GameLib.Missing() or {}) do
            warn("[StoneSkipping]", idx, "blocked, missing:", table.concat(paths, ", "))
            Library.Compat.Block(idx, T("Not available after a game update", "ใช้ไม่ได้หลังเกมอัปเดต"))
        end
        local en, th = xDTaraZ:Unsupported()
        if not en then return end
        Library:Notify("Stone Skipping", T(("Farming is off: %s. Movement still works."):format(en), ("ฟาร์มใช้ไม่ได้: %s ส่วนการเคลื่อนที่ยังใช้ได้"):format(th)), 10, "Error")
    end

    local function Live()
        Library:Every(1, function()
            ReportHalts()
            while #State.Messages > 0 do
                Notify(table.remove(State.Messages, 1))
            end
            if statusLabel then statusLabel:SetText(State.Summary or "-") end
            if runLabel then
                runLabel:SetText(("%s\nThrows %d · Wins +%s · Skill +%s"):format(State.Status, State.Throws, xDTaraZ.Format(State.WinsEarned), xDTaraZ.Format(State.SkillEarned)))
            end
        end)
    end

    local function BuildTabs()
        local window = Library.Window
        for _, build in ipairs({ BuildMain, BuildFarm, BuildStones, BuildPets, BuildPlayer, BuildSettings }) do
            xDTaraZ.Try(build, window)
        end
        xDTaraZ.Try(GateFeatures)
        xDTaraZ.Try(Live)
    end

    local function UnloadSelf()
        Library:Unload()
    end

    Library:OnUnload(xDTaraZ.Scheduler.Stop)
    Library:OnUnload(function()
        if getgenv().StoneSkippingUnload == UnloadSelf then getgenv().StoneSkippingUnload = nil end
    end)
    getgenv().StoneSkippingUnload = UnloadSelf

    Library:CreateWindow({
        Title = "Nova Hub",
        SubTitle = "Stone Skipping by xDTaraZ",
        MenuKey = Enum.KeyCode.LeftControl,
        ConfigFolder = Config.SaveFolder,
        Language = "Auto",
        Theme = "Nova",
        OnUnlocked = function()
            BuildTabs()
            xDTaraZ.Try(xDTaraZ.Scheduler.Boot)
            Notify("Loaded", "Success")
            xDTaraZ.Try(Library.LoadAutoloadConfig, Library)
        end,
    })
end

if getgenv().StoneSkippingUnload then
    pcall(getgenv().StoneSkippingUnload)
end

pcall(NovaBanner.Step, "Systems")
task.spawn(xDTaraZ.Train.CheckPasses)
BuildInterface()
pcall(NovaBanner.Step, "Interface")
pcall(NovaBanner.Ready)]==]

NOVA_HUB_MODULES[10765288803] = [==[if not game:IsLoaded() then
    game.Loaded:Wait()
end

if game.GameId ~= 10765288803 then
    game:GetService("Players").LocalPlayer:Kick("Nova Hub: this script is for Break and Steal an Egg only")
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
        "   BREAK AND STEAL AN EGG  //  by xDTaraZ  //  discord.gg/FHVfmeSceA",
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
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")
local TeleportService = game:GetService("TeleportService")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local osClock = os.clock
local vector3New, cframeNew = Vector3.new, CFrame.new

local xDTaraZ = setmetatable({}, {
    __newindex = function(self, key, value)
        rawset(self, key, type(value) == "function" and LPH_JIT(value) or value)
    end,
})

xDTaraZ.Config = {
    Discord = "https://discord.gg/FHVfmeSceA",
    UpdateLog = {
        { "2026-10-03", "Classic Nova Hub UI is back\nBetter executor support\nNew Auto Upgrade system\nFixed stealing & movement" },
    },
    UiSource = "NovaHub://embedded-ui",
    SaveFolder = "Break and Steal an Egg",
    LoadTimeout = 30,
    RequireTimeout = 3,
    MaxFailures = 5,
    FailWindow = 10,
    AlertTries = 20,
    AlertDelay = 0.5,
    TickDelay = 0.05,
    TpSettle = 0.2,
    GrabTimeout = 2,
    CarryGrace = 2.5,
    StandRadius = 6,
    SpeedFallback = 120,
    SkipFor = 4,
    BankTimeout = 2.5,
    HitSlice = 1.2,
    TripCost = 1,
    EggOffset = vector3New(0, 3, 3.5),
    PromptMatch = 30,
    BreakPickupRadius = 40,
    EquipInterval = 2,
    BuyInterval = 1.5,
    ClaimInterval = 31,
    EggInterval = 5,
    EggSpacing = 8,
    SellInterval = 4,
    EspInterval = 0.4,
    BatRange = 15,
    BatGap = 0.72,
    RejoinDelay = 5,
}

xDTaraZ.State = {
    Alive = true,
    Connections = {},
    Requests = {},
    Messages = {},
    Failures = {},
    Halted = {},
    Last = {},
    Status = "Idle",
    Steals = 0,
    Broken = 0,
    Banked = 0,
    StartCash = nil,
    StartAt = osClock(),
    HitTokens = 3,
    HitStamp = osClock(),
    BreakSpot = nil,
    Opt = {
        AutoSteal = false,
        Take = "Upgrades Only",
        StealRarities = {},
        StealMinValue = 0,
        AutoBreak = false,
        BreakZone = "Best",
        MaxHits = 40,
        RobCarriers = false,
        AutoPlace = false,
        AutoSell = false,
        KeepRarities = {},
        AutoUpgrade = false,
        UpgradeTargets = { Pickaxe = true, Base = true, Trail = true, Treadmill = true },
        AutoBuyPickaxe = false,
        AutoUpgradePlot = false,
        AutoTrail = false,
        AutoTreadmill = false,
        CashReserve = 0,
        AutoClaim = false,
        AutoHatch = false,
        BatTarget = nil,
        BatLoop = false,
        BatAura = false,
        EspPickups = false,
        EspEggs = false,
        EspPlayers = false,
        EspMinRarity = "Common",
        SpeedOn = false,
        WalkSpeed = xDTaraZ.Config.SpeedFallback,
        InfJump = false,
        Noclip = false,
        AntiAfk = false,
        AutoRejoin = false,
    },
}

local Config, State = xDTaraZ.Config, xDTaraZ.State
local Shared = ReplicatedStorage:WaitForChild("Shared", Config.LoadTimeout)

xDTaraZ.GameLib = {
    Remote = setmetatable({}, {
        __index = function(self, name)
            local remote = ReplicatedStorage:FindFirstChild(name)
            if not remote then
                local nested = ReplicatedStorage:FindFirstChild(name, true)
                remote = nested and (nested:IsA("BaseRemoteEvent") or nested:IsA("RemoteFunction")) and nested or nil
            end
            if remote then rawset(self, name, remote) end
            return remote
        end,
    }),
}

---@return boolean, any  ok + module, retried from an identity-2 thread when the executor can really switch
function xDTaraZ.GameLib.RequireAsGame(module)
    local done, ok, loaded = false, false, nil
    task.spawn(function()
        pcall(setthreadidentity, 2)
        local read, identity = pcall(getthreadidentity)
        if read and identity == 2 then
            ok, loaded = pcall(require, module)
        end
        done = true
    end)
    local deadline = osClock() + Config.RequireTimeout
    while not done and osClock() < deadline do
        task.wait()
    end
    return ok, loaded
end

---@param name string  module under ReplicatedStorage.Shared
---@return table?      nil when it is missing or this executor can't require it
function xDTaraZ.GameLib.Require(name)
    local module = Shared and Shared:FindFirstChild(name)
    if not module then
        local nested = Shared and Shared:FindFirstChild(name, true)
        module = nested and nested:IsA("ModuleScript") and nested or nil
    end
    if not module then
        warn("[BreakStealEgg] missing game module", name)
        return nil
    end
    local ok, loaded = pcall(require, module)
    if ok then return loaded end
    local okAgain, again = xDTaraZ.GameLib.RequireAsGame(module)
    if okAgain then return again end
    warn("[BreakStealEgg] require", name, loaded)
    return nil
end

local GameLib = xDTaraZ.GameLib

do
    local modules = {
        Eggs = "EggConfig", Rewards = "EggRewards", Rarity = "EggRarity", Pickaxe = "PickaxeConfig", Zones = "ZonesConfig",
        Plot = "PlotUpgradeConfig", Treadmill = "TreadmillUpgradeConfig", Trails = "TrailsConfig", Bat = "BatConfig", Speed = "SpeedConfig",
    }
    for key, name in pairs(modules) do
        GameLib[key] = GameLib.Require(name)
    end
    State.Opt.WalkSpeed = GameLib.Speed and GameLib.Speed.MaxWalkSpeed or Config.SpeedFallback
end

GameLib.Needs = {
    AutoSteal = { "Rewards" },
    AutoBreak = { "Pickaxe", "Eggs", "Rewards", "Remote.EggHitRequest" },
    RobCarriers = { "Bat", "Remote.BatHitRequest" },
    AutoPlace = { "Remote.PetsInventoryRemote" },
    AutoSell = { "Rewards", "Remote.BackpackSellRemote" },
    AutoClaim = { "Remote.IndexRemote", "Remote.OfflineRewardRemote" },
    AutoHatch = { "Remote.MergeMachineRemote" },
    AutoBuyPickaxe = { "Pickaxe" },
    AutoUpgradePlot = { "Plot" },
    AutoTrail = { "Trails" },
    AutoTreadmill = { "Treadmill" },
    SpeedOn = { "Speed" },
    EspEggs = { "Pickaxe" },
    BatLoop = { "Bat", "Remote.BatHitRequest" },
    BatAura = { "Bat", "Remote.BatHitRequest" },
}

---@return string?  first module ("Rewards") or remote ("Remote.EggHitRequest") the feature needs that is gone
function GameLib.Missing(idx)
    for _, key in ipairs(GameLib.Needs[idx] or {}) do
        local node = GameLib
        for part in key:gmatch("[^.]+") do
            node = type(node) == "table" and node[part] or nil
        end
        if node == nil then return key end
    end
    return nil
end

xDTaraZ.RarityLadder = GameLib.Rarity and GameLib.Rarity.Ladder() or {}
xDTaraZ.RarityRank = {}
do
    for i, name in ipairs(xDTaraZ.RarityLadder) do
        xDTaraZ.RarityRank[name] = i
    end
end

xDTaraZ.ZoneList = {}
do
    for index, zone in pairs(GameLib.Zones and GameLib.Zones.Zones or {}) do
        table.insert(xDTaraZ.ZoneList, { Index = index, Name = zone.Name or ("Zone" .. index), Rarity = zone.Rarity, Power = zone.RequiredPower or 0 })
    end
    table.sort(xDTaraZ.ZoneList, function(a, b) return a.Index < b.Index end)
end

xDTaraZ.ZonePool = {}
do
    for _, entry in ipairs(GameLib.Rewards and GameLib.Rewards.Pool or {}) do
        local zone = entry.Zone
        if not zone then continue end
        xDTaraZ.ZonePool[zone] = xDTaraZ.ZonePool[zone] or {}
        table.insert(xDTaraZ.ZonePool[zone], { Name = entry.Name, Chance = entry.Chance or 1 })
    end
end

function xDTaraZ.Format(n)
    n = tonumber(n) or 0
    local units = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
    local i = 1
    while math.abs(n) >= 1000 and i < #units do
        n /= 1000
        i += 1
    end
    return (i == 1 and "%d%s" or "%.2f%s"):format(n, units[i])
end

function xDTaraZ:Notify(msg)
    table.insert(State.Messages, msg)
end

xDTaraZ.Util = {}

---@return string?, string?  body, or nil + why every transport failed
function xDTaraZ.Util.HttpGet(url)
    if url == "NovaHub://embedded-ui" then return NOVA_HUB_UI_SOURCE end
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if ok and type(body) == "string" then return body end

    local send = request or http_request or (syn and syn.request) or (http and http.request)
    if not send then return nil, tostring(body) end
    local sent, response = pcall(send, { Url = url, Method = "GET" })
    if not sent then return nil, tostring(response) end
    if type(response) ~= "table" or response.StatusCode ~= 200 or type(response.Body) ~= "string" then
        return nil, "HTTP " .. tostring(type(response) == "table" and response.StatusCode)
    end
    return response.Body
end

---Shows a Roblox notification even when the menu never loaded; SetCore fails for a while after joining.
function xDTaraZ.Util.Alert(text, detail)
    warn("[BreakStealEgg] menu:", text, detail or "")
    task.spawn(function()
        for _ = 1, Config.AlertTries do
            if pcall(StarterGui.SetCore, StarterGui, "SendNotification", { Title = "Nova Hub", Text = text, Duration = 10 }) then return end
            task.wait(Config.AlertDelay)
        end
    end)
end

---@return boolean, any  pcall result, warns with the label when it fails
function xDTaraZ.Util.Try(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then warn("[BreakStealEgg] " .. label .. ":", err) end
    return ok, err
end

---@return table?  the UI library, nil after telling the player why
function xDTaraZ.Util.LoadLibrary()
    local body, err = xDTaraZ.Util.HttpGet(Config.UiSource)
    if not body or not body:sub(-64):find("return Library%s*$") then
        xDTaraZ.Util.Alert("Could not download the menu. Check your connection and run it again.", err or "truncated body")
        return nil
    end
    local chunk, compileErr = loadstring(body)
    if not chunk then
        xDTaraZ.Util.Alert("The menu failed to load on this executor: " .. tostring(compileErr))
        return nil
    end
    local ok, library = pcall(chunk)
    if ok and type(library) == "table" then return library end
    xDTaraZ.Util.Alert("The menu failed to load on this executor: " .. tostring(library))
    return nil
end

function xDTaraZ:Character()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not (hum and hrp and hum.Health > 0) then return nil end
    return char, hum, hrp
end

function xDTaraZ:Connect(signal, handler)
    local conn = signal:Connect(handler)
    table.insert(State.Connections, conn)
    return conn
end

function xDTaraZ:Fire(name, ...)
    local remote = GameLib.Remote[name]
    if remote then remote:FireServer(...) end
end

function xDTaraZ.Attr(name, fallback)
    local value = LocalPlayer:GetAttribute(name)
    if value == nil then return fallback end
    return value
end

function xDTaraZ.Spendable()
    return xDTaraZ.Attr("Cash", 0) - (State.Opt.CashReserve or 0)
end

xDTaraZ.Move = {}

function xDTaraZ.Move.To(cf)
    local _, _, hrp = xDTaraZ:Character()
    if not hrp then return false end
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.CFrame = cf
    return true
end

---@return number  speed the game itself gives the player now, never lower than what SpeedPower earns
function xDTaraZ.Move.NaturalSpeed()
    local earned = GameLib.Speed and GameLib.Speed.SpeedPowerToWalkSpeed(xDTaraZ.Attr("SpeedPower", 0)) or 0
    return math.max(State.NaturalSpeed or 0, earned)
end

function xDTaraZ.Move.ApplySpeed()
    local _, hum = xDTaraZ:Character()
    if not hum then return end
    if State.Opt.SpeedOn then
        if not State.SpeedWritten then State.NaturalSpeed = hum.WalkSpeed end
        State.SpeedWritten = math.max(State.Opt.WalkSpeed, xDTaraZ.Move.NaturalSpeed())
        hum.WalkSpeed = State.SpeedWritten
    elseif State.SpeedWritten then
        State.SpeedWritten = nil
        hum.WalkSpeed = xDTaraZ.Move.NaturalSpeed()
    end
end

function xDTaraZ.Move.HoldSpeed(hum)
    if State.SpeedConn then State.SpeedConn:Disconnect() end
    State.SpeedWritten = nil
    State.SpeedConn = hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
        if hum.WalkSpeed == State.SpeedWritten then return end
        State.NaturalSpeed = hum.WalkSpeed
        if State.Opt.SpeedOn then xDTaraZ.Move.ApplySpeed() end
    end)
end

function xDTaraZ.Move.SetNoclip(on)
    local char = LocalPlayer.Character
    if not char then return end
    for _, part in ipairs(char:GetChildren()) do
        if part:IsA("BasePart") then
            if on then
                if part.CanCollide then
                    State.NoclipParts = State.NoclipParts or {}
                    State.NoclipParts[part] = true
                    part.CanCollide = false
                end
            elseif State.NoclipParts and State.NoclipParts[part] then
                part.CanCollide = true
            end
        end
    end
    if not on then State.NoclipParts = nil end
end

xDTaraZ.Base = {}

function xDTaraZ.Base.Own()
    local cached = State.Plot
    if cached and cached.Parent and cached:GetAttribute("OwnerUserId") == LocalPlayer.UserId then return cached end
    for _, plot in ipairs(Workspace.Plots:GetChildren()) do
        if plot:GetAttribute("OwnerUserId") == LocalPlayer.UserId then
            State.Plot = plot
            return plot
        end
    end
    return nil
end

function xDTaraZ.Base.Hitbox()
    local plot = xDTaraZ.Base.Own()
    if not plot then return nil end
    local cached = State.Hitbox
    if cached and cached[1] == plot and cached[2]:IsDescendantOf(plot) then return cached[2] end

    local hitbox = plot:FindFirstChild("Hitbox", true)
    State.Hitbox = hitbox and { plot, hitbox } or nil
    return hitbox
end

function xDTaraZ.Base.Home()
    local hitbox = xDTaraZ.Base.Hitbox()
    if hitbox then xDTaraZ.Move.To(hitbox.CFrame + vector3New(0, 2, 0)) end
end

---@return number  cash/s an animal must beat to be worth taking
function xDTaraZ.Base.Floor()
    if State.Opt.Take == "Everything" then return -1 end
    return xDTaraZ.Base.Weakest()
end

---@return number  weakest placed cash/s, 0 while slots are free
function xDTaraZ.Base.Weakest()
    local cached = State.FloorCache
    if cached and osClock() - cached[1] < 1 then return cached[2] end
    local plot = xDTaraZ.Base.Own()
    local placed = plot and plot:FindFirstChild("PlacedAnimals")
    local floor = 0
    if placed and #placed:GetChildren() >= (plot:GetAttribute("MaxAnimals") or math.huge) then
        floor = math.huge
        for _, animal in ipairs(placed:GetChildren()) do
            floor = math.min(floor, animal:GetAttribute("CashPerSecond") or 0)
        end
    end
    State.FloorCache = { osClock(), floor }
    return floor
end

function xDTaraZ.Base.Carry()
    return xDTaraZ.Attr("CarryCount", 0), xDTaraZ.Attr("SatchelCapacity", 1)
end

---@return boolean  true once everything carried is banked
function xDTaraZ.Base.Bank()
    local hitbox = xDTaraZ.Base.Hitbox()
    if not hitbox then return false end
    State.Status = "Banking"
    local before = xDTaraZ.Base.Carry()
    local deadline = osClock() + Config.BankTimeout
    repeat
        xDTaraZ.Move.To(hitbox.CFrame + vector3New(0, 2, 0))
        task.wait()
    until xDTaraZ.Base.Carry() == 0 or osClock() > deadline
    local done = xDTaraZ.Base.Carry() == 0
    if done then
        State.Banked += before
        State.BreakSpot = nil
        State.Last.Banked = osClock()
        State.Requests.Place = State.Opt.AutoPlace or nil
    end
    return done
end

xDTaraZ.Pickup = {}

---@return number  cash per second once placed
function xDTaraZ.Pickup.Value(model)
    local name = model:GetAttribute("AnimalName")
    if type(name) ~= "string" then return 0 end
    local ok, value = pcall(GameLib.Rewards.PlacedCashPerSecond, name, model:GetAttribute("SizeMult") or 1, model:GetAttribute("Mutation"), model:GetAttribute("WeightKg"), model:GetAttribute("Variant"))
    return ok and value or 0
end

function xDTaraZ.Pickup.PromptFor(model)
    local pos = model:GetPivot().Position
    local best, bestDist = nil, Config.PromptMatch
    for _, prompt in ipairs(CollectionService:GetTagged("SmartPrompt")) do
        local anchor = prompt.Name == "StealPrompt" and prompt.Parent
        if anchor and anchor:IsA("BasePart") then
            local dist = (anchor.Position - pos).Magnitude
            if dist < bestDist then best, bestDist = prompt, dist end
        end
    end
    return best
end

function xDTaraZ.Pickup.Allowed(model, value)
    local opt = State.Opt
    if next(opt.StealRarities) and not opt.StealRarities[model:GetAttribute("Rarity") or ""] then return false end
    return value >= (opt.StealMinValue or 0)
end

---@return Model?  best pickup to take next
function xDTaraZ.Pickup.Next()
    local opt = State.Opt
    local folder = Workspace:FindFirstChild("AnimalPickups")
    if not folder then return nil end
    local floor = xDTaraZ.Base.Floor()
    local best, bestValue = nil, floor
    for _, model in ipairs(folder:GetChildren()) do
        local value = xDTaraZ.Pickup.Value(model)
        if value <= bestValue or osClock() < (State.Skip and State.Skip[model] or 0) then continue end
        local fromBreak = State.BreakSpot and (model:GetPivot().Position - State.BreakSpot).Magnitude < Config.BreakPickupRadius
        if (opt.AutoSteal and xDTaraZ.Pickup.Allowed(model, value)) or (opt.AutoBreak and fromBreak) then
            best, bestValue = model, value
        end
    end
    return best
end

function xDTaraZ.Pickup.Trigger(prompt)
    if xDTaraZ.Compat and xDTaraZ.Compat.Caps.Prompt then
        fireproximityprompt(prompt)
        return
    end
    prompt:InputHoldBegin()
    task.wait(prompt.HoldDuration)
    prompt:InputHoldEnd()
end

---@return number  animals the other players carry right now
function xDTaraZ.Pickup.OthersCarrying()
    local total = 0
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then total += player:GetAttribute("CarryCount") or 0 end
    end
    return total
end

---@param before number  CarryCount read before the prompt fired
---@param others number  OthersCarrying read before the prompt fired
---@return boolean       true once the satchel shows the animal; a pickup that vanished without it keeps waiting for the count unless another player picked it up
function xDTaraZ.Pickup.AwaitCarry(model, before, others)
    local fired = osClock()
    local goneAt
    repeat
        task.wait()
        if xDTaraZ.Base.Carry() > before then return true end
        if not model.Parent then
            goneAt = goneAt or osClock()
            if xDTaraZ.Pickup.OthersCarrying() > others then return false end
        end
    until osClock() > (goneAt and goneAt + Config.CarryGrace or fired + Config.GrabTimeout)
    return false
end

---@return boolean  true if it ended up in the satchel
function xDTaraZ.Pickup.Grab(model)
    local prompt = xDTaraZ.Pickup.PromptFor(model)
    State.Skip = State.Skip or setmetatable({}, { __mode = "k" })
    if not prompt then
        State.Skip[model] = osClock() + Config.SkipFor
        return false
    end
    State.Status = "Stealing " .. tostring(model:GetAttribute("AnimalName"))
    local before = xDTaraZ.Base.Carry()
    xDTaraZ.Move.To(cframeNew(prompt.Parent.Position + vector3New(0, 2, 0)))
    task.wait(Config.TpSettle)
    local others = xDTaraZ.Pickup.OthersCarrying()
    xDTaraZ.Pickup.Trigger(prompt)
    local got = xDTaraZ.Pickup.AwaitCarry(model, before, others)
    if got then State.Steals += 1 else State.Skip[model] = osClock() + Config.SkipFor end
    return got
end

xDTaraZ.Break = {}

function xDTaraZ.Break.Damage()
    return GameLib.Pickaxe.GetDamage(xDTaraZ.Attr("PickaxeTier", 1))
end

function xDTaraZ.Break.Alive(egg)
    return egg.Parent ~= nil and not egg:GetAttribute("Broken") and (egg:GetAttribute("Health") or 0) > 0
end

---@return number  average cash/s of what hatches from it
function xDTaraZ.Break.Expected(egg)
    State.EggWorth = State.EggWorth or setmetatable({}, { __mode = "k" })
    local cached = State.EggWorth[egg]
    if cached then return cached end
    local zone, weight = egg:GetAttribute("ZoneIndex"), egg:GetAttribute("WeightKg")
    local total, chances = 0, 0
    for _, entry in ipairs(xDTaraZ.ZonePool[zone] or {}) do
        local ok, value = pcall(GameLib.Rewards.PlacedCashPerSecond, entry.Name, nil, nil, weight)
        if ok then
            total += entry.Chance * value
            chances += entry.Chance
        end
    end
    local worth = chances > 0 and total / chances or 0
    State.EggWorth[egg] = worth
    return worth
end

---@return BasePart?  egg with the most cash per second spent that beats the base
function xDTaraZ.Break.Pick()
    local opt = State.Opt
    local damage = xDTaraZ.Break.Damage()
    local floor = xDTaraZ.Base.Floor()
    local burst, cooldown = GameLib.Eggs.HitBurst, GameLib.Eggs.HitCooldown
    local wantZone = opt.BreakZone ~= "Best" and tonumber(tostring(opt.BreakZone):match("%d+")) or nil
    local best, bestScore
    for _, egg in ipairs(CollectionService:GetTagged("BreakableEgg")) do
        if not xDTaraZ.Break.Alive(egg) then continue end
        if wantZone and egg:GetAttribute("ZoneIndex") ~= wantZone then continue end
        local hits = math.ceil(egg:GetAttribute("Health") / damage)
        if hits > opt.MaxHits then continue end
        local worth = xDTaraZ.Break.Expected(egg)
        if worth <= floor then continue end
        local score = worth / (math.max(hits - burst, 0) * cooldown + Config.TripCost)
        if not best or score > bestScore then best, bestScore = egg, score end
    end
    return best
end

function xDTaraZ.Break.EquipPickaxe()
    local char, hum = xDTaraZ:Character()
    if not char then return false end
    if char:FindFirstChild(GameLib.Pickaxe.ToolName) then return true end
    local tool = LocalPlayer.Backpack:FindFirstChild(GameLib.Pickaxe.ToolName)
    if not tool then return false end
    hum:EquipTool(tool)
    return true
end

function xDTaraZ.Break.TakeToken()
    local now = osClock()
    local cooldown = GameLib.Eggs.HitCooldown
    State.HitTokens = math.min(GameLib.Eggs.HitBurst, State.HitTokens + (now - State.HitStamp) / cooldown)
    State.HitStamp = now
    if State.HitTokens >= 1 then
        State.HitTokens -= 1
        return 0
    end
    return (1 - State.HitTokens) * cooldown
end

function xDTaraZ.Break.Hit(egg)
    if not xDTaraZ.Break.EquipPickaxe() then
        State.Status = "No pickaxe"
        return
    end
    State.Status = ("Breaking %s (Zone %s)"):format(tostring(egg:GetAttribute("EggType")), tostring(egg:GetAttribute("ZoneIndex")))
    State.BreakSpot = egg.Position
    local remote = GameLib.Remote.EggHitRequest
    local stop = osClock() + Config.HitSlice
    while xDTaraZ.Break.Alive(egg) and State.Opt.AutoBreak and osClock() < stop do
        xDTaraZ.Move.To(cframeNew(egg.Position + Config.EggOffset, egg.Position))
        local waitFor
        repeat
            waitFor = xDTaraZ.Break.TakeToken()
            if waitFor > 0 then task.wait(waitFor) end
        until waitFor == 0
        remote:FireServer(egg)
    end
    if not xDTaraZ.Break.Alive(egg) then State.Broken += 1 end
end

xDTaraZ.Bat = {}

function xDTaraZ.Bat.Equip()
    local char, hum = xDTaraZ:Character()
    if not char then return false end
    if char:FindFirstChild(GameLib.Bat.ToolName) then return true end
    local tool = LocalPlayer.Backpack:FindFirstChild(GameLib.Bat.ToolName)
    if not tool then return false end
    hum:EquipTool(tool)
    return true
end

function xDTaraZ.Bat.RootOf(player)
    local char = player and player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not (hum and hrp and hum.Health > 0) then return nil end
    return hrp
end

---@return boolean  true if a swing went out
function xDTaraZ.Bat.Swing(player, approach)
    local target = xDTaraZ.Bat.RootOf(player)
    if not target then return false end
    if osClock() - (State.Last.Bat or 0) < Config.BatGap then return false end
    if not xDTaraZ.Bat.Equip() then return false end
    if approach then
        xDTaraZ.Move.To(target.CFrame * cframeNew(0, 0, 3))
        task.wait(Config.TpSettle)
    end
    State.Last.Bat = osClock()
    xDTaraZ:Fire("BatHitRequest", player)
    return true
end

function xDTaraZ.Bat.Carrier()
    local best, bestCount = nil, 0
    for _, player in ipairs(Players:GetPlayers()) do
        local count = player ~= LocalPlayer and (player:GetAttribute("CarryCount") or 0) or 0
        if count > bestCount and xDTaraZ.Bat.RootOf(player) then best, bestCount = player, count end
    end
    return best
end

function xDTaraZ.Bat.Aura()
    local _, _, hrp = xDTaraZ:Character()
    if not hrp then return end
    local range = Config.BatRange * (xDTaraZ.Attr("BatHitboxMultiplier", 1)) + GameLib.Bat.Targeting.HitTolerance
    for _, player in ipairs(Players:GetPlayers()) do
        local root = player ~= LocalPlayer and xDTaraZ.Bat.RootOf(player)
        if root and (root.Position - hrp.Position).Magnitude <= range then
            if xDTaraZ.Bat.Swing(player, false) then return end
        end
    end
end

xDTaraZ.Farm = {}

---Once every farm toggle is off: banks what is carried or walks back to where the farm picked the character up, then shows Idle.
function xDTaraZ.Farm.Stand()
    local origin = State.FarmOrigin
    if not origin then return end
    State.FarmOrigin = nil
    State.BreakSpot = nil
    local _, _, hrp = xDTaraZ:Character()
    if hrp and not (xDTaraZ.Base.Carry() > 0 and xDTaraZ.Base.Bank()) and (hrp.Position - origin.Position).Magnitude > Config.StandRadius then
        xDTaraZ.Move.To(origin)
    end
    State.Status = "Idle"
end

function xDTaraZ.Farm.Rest()
    local opt = State.Opt
    if not (opt.AutoSteal or opt.AutoBreak or opt.RobCarriers) then State.Status = "Idle" end
end

function xDTaraZ.Farm.Step()
    local opt = State.Opt
    if not (opt.AutoSteal or opt.AutoBreak or opt.RobCarriers) then
        xDTaraZ.Farm.Stand()
        return
    end
    local _, _, hrp = xDTaraZ:Character()
    if not hrp then
        State.Status = "Waiting for respawn"
        return
    end
    State.FarmOrigin = State.FarmOrigin or hrp.CFrame

    local carry, cap = xDTaraZ.Base.Carry()
    local nextPickup = (carry < cap) and xDTaraZ.Pickup.Next() or nil
    if carry >= cap or (carry > 0 and not nextPickup) or xDTaraZ.Attr("BeingChased", false) and carry > 0 then
        xDTaraZ.Base.Bank()
        return
    end
    if nextPickup then
        xDTaraZ.Pickup.Grab(nextPickup)
        return
    end
    if opt.RobCarriers then
        local victim = xDTaraZ.Bat.Carrier()
        if victim then
            State.Status = "Robbing " .. victim.Name
            local root = xDTaraZ.Bat.RootOf(victim)
            if root then State.BreakSpot = root.Position end
            xDTaraZ.Bat.Swing(victim, true)
            return
        end
    end
    if opt.AutoBreak then
        local egg = xDTaraZ.Break.Pick()
        if egg then
            xDTaraZ.Break.Hit(egg)
            return
        end
        State.Status = "No egg beats your base yet"
        return
    end
    State.Status = "Waiting for animals better than your base"
end

xDTaraZ.Shop = {}

function xDTaraZ.Shop.Pickaxe()
    local tier = xDTaraZ.Attr("PickaxeTier", 1)
    local cash = xDTaraZ.Spendable()
    local best
    for nextTier = tier + 1, #GameLib.Pickaxe.Tiers do
        if GameLib.Pickaxe.GetPrice(nextTier) > cash then break end
        best = nextTier
    end
    if not best then return false end
    xDTaraZ:Fire("PickaxeShopRequest", "Buy", best)
    return true
end

function xDTaraZ.Shop.Plot()
    local plot = xDTaraZ.Base.Own()
    if not plot then return false end
    local cost = GameLib.Plot.UpgradeCost(plot:GetAttribute("PlotLevel") or 1)
    if not cost or cost > xDTaraZ.Spendable() then return false end
    xDTaraZ:Fire("UpgradePlotRequest")
    return true
end

function xDTaraZ.Shop.Trail()
    local owned = {}
    for id in tostring(xDTaraZ.Attr("OwnedTrails", "")):gmatch("%d+") do owned[tonumber(id)] = true end
    local pick
    for _, trail in ipairs(GameLib.Trails.Trails) do
        if not owned[trail.Id] and trail.Price <= xDTaraZ.Spendable() and (not pick or trail.Multiplier > pick.Multiplier) then pick = trail end
    end
    local equipped = xDTaraZ.Attr("EquippedTrail", 1)
    local bestOwned
    for _, trail in ipairs(GameLib.Trails.Trails) do
        if owned[trail.Id] and (not bestOwned or trail.Multiplier > bestOwned.Multiplier) then bestOwned = trail end
    end
    if pick then
        xDTaraZ:Fire("TrailShopRequest", "Buy", pick.Id)
        task.wait(0.3)
        xDTaraZ:Fire("TrailShopRequest", "Equip", pick.Id)
        return true
    end
    if bestOwned and bestOwned.Id ~= equipped then xDTaraZ:Fire("TrailShopRequest", "Equip", bestOwned.Id) end
    return false
end

function xDTaraZ.Shop.Treadmill()
    local plot = xDTaraZ.Base.Own()
    if not plot then return false end
    if not plot:GetAttribute("TreadmillUnlocked") then
        xDTaraZ:Fire("UnlockTreadmillRequest")
        return true
    end
    local level = plot:GetAttribute("TreadmillLevel") or 1
    if level >= GameLib.Treadmill.MaxLevel then return false end
    if GameLib.Treadmill.UpgradeCost(level) > xDTaraZ.Spendable() then return false end
    xDTaraZ:Fire("UpgradeTreadmillRequest")
    return true
end

---Dropdown entry -> the flag Shop.Step reads; order = menu order.
xDTaraZ.Shop.Targets = {
    { Key = "Pickaxe", Flag = "AutoBuyPickaxe" },
    { Key = "Base", Flag = "AutoUpgradePlot" },
    { Key = "Trail", Flag = "AutoTrail" },
    { Key = "Treadmill", Flag = "AutoTreadmill" },
}

---Turns the Auto Upgrade toggle + target dropdown into the per-shop flags; targets whose game module is missing stay off.
function xDTaraZ.Shop.Sync()
    local opt = State.Opt
    for _, target in ipairs(xDTaraZ.Shop.Targets) do
        opt[target.Flag] = opt.AutoUpgrade and opt.UpgradeTargets[target.Key] == true and not GameLib.Missing(target.Flag)
    end
end

---One pass over the picked targets, cheapest win first like Shop.Step; nil when nothing was affordable.
function xDTaraZ.Shop.Now()
    local picked = State.Opt.UpgradeTargets
    local bought = false
    if picked.Base and not GameLib.Missing("AutoUpgradePlot") and xDTaraZ.Shop.Plot() then bought = true end
    if picked.Pickaxe and not GameLib.Missing("AutoBuyPickaxe") and xDTaraZ.Shop.Pickaxe() then bought = true end
    if picked.Trail and not GameLib.Missing("AutoTrail") and xDTaraZ.Shop.Trail() then bought = true end
    if picked.Treadmill and not GameLib.Missing("AutoTreadmill") and xDTaraZ.Shop.Treadmill() then bought = true end
    if not bought then xDTaraZ:Notify("Nothing to upgrade yet: not enough cash or already maxed") end
end

function xDTaraZ.Shop.Step()
    local opt = State.Opt
    local plot = xDTaraZ.Base.Own()
    local plotCost = plot and GameLib.Plot and GameLib.Plot.UpgradeCost(plot:GetAttribute("PlotLevel") or 1) or math.huge
    local pickTier = xDTaraZ.Attr("PickaxeTier", 1)
    local pickaxes = GameLib.Pickaxe
    local pickCost = pickaxes and pickTier < #pickaxes.Tiers and pickaxes.GetPrice(pickTier + 1) or math.huge
    if opt.AutoUpgradePlot and plotCost <= pickCost and xDTaraZ.Shop.Plot() then return end
    if opt.AutoBuyPickaxe and xDTaraZ.Shop.Pickaxe() then return end
    if opt.AutoUpgradePlot and xDTaraZ.Shop.Plot() then return end
    if opt.AutoTrail and xDTaraZ.Shop.Trail() then return end
    if opt.AutoTreadmill then xDTaraZ.Shop.Treadmill() end
end

xDTaraZ.Pets = {}

function xDTaraZ.Pets.Tools()
    local list = {}
    for _, tool in ipairs(LocalPlayer.Backpack:GetChildren()) do
        if tool:IsA("Tool") and CollectionService:HasTag(tool, "AnimalTool") then list[#list + 1] = tool end
    end
    return list
end

function xDTaraZ.Pets.Place()
    if #xDTaraZ.Pets.Tools() == 0 then return end
    xDTaraZ:Fire("PetsInventoryRemote", "EquipBest", nil)
end

---@return number  tools sent to sell
function xDTaraZ.Pets.Sell()
    local keep = State.Opt.KeepRarities
    if State.Opt.AutoPlace and osClock() - (State.Last.Banked or 0) < Config.EquipInterval * 2 then return 0 end
    local floor = State.Opt.AutoPlace and xDTaraZ.Base.Weakest() or math.huge
    local batch = {}
    for _, tool in ipairs(xDTaraZ.Pets.Tools()) do
        if keep[tool:GetAttribute("Rarity") or ""] or xDTaraZ.Pickup.Value(tool) > floor then continue end
        batch[#batch + 1] = tool
    end
    if #batch == 0 then return 0 end
    local remote = GameLib.Remote.BackpackSellRemote
    if not remote then return 0 end
    local ok, err = pcall(remote.InvokeServer, remote, batch)
    if not ok then warn("[BreakStealEgg] sell:", err) end
    return ok and #batch or 0
end

xDTaraZ.Rewards = {}

function xDTaraZ.Rewards.Claim()
    xDTaraZ:Fire("IndexRemote", "ClaimAll", nil)
    xDTaraZ:Fire("OfflineRewardRemote", "Claim")
    if not State.GroupClaimed then
        xDTaraZ:Fire("GroupRewardRemote", "Joined")
        xDTaraZ:Fire("GroupRewardRemote", "Claim")
    end
    if not State.DiscordClaimed then xDTaraZ:Fire("DiscordRewardRemote", "Verify", LocalPlayer.Name) end
end

function xDTaraZ.Rewards.Watch()
    local function Track(remote, key)
        if not remote then return end
        xDTaraZ:Connect(remote.OnClientEvent, function(kind, info)
            if kind == "State" and type(info) == "table" and info.Claimed then State[key] = true end
        end)
        remote:FireServer("Get")
    end
    Track(GameLib.Remote.GroupRewardRemote, "GroupClaimed")
    Track(GameLib.Remote.DiscordRewardRemote, "DiscordClaimed")
end

xDTaraZ.Eggs = {}

function xDTaraZ.Eggs.Tools()
    local list = {}
    for _, tool in ipairs(LocalPlayer.Backpack:GetChildren()) do
        if tool:IsA("Tool") and CollectionService:HasTag(tool, "MergeEggTool") then list[#list + 1] = tool end
    end
    return list
end

---@return number  eggs that got placed or hatched
function xDTaraZ.Eggs.Step()
    local done = 0
    local now = Workspace:GetServerTimeNow()
    for _, egg in ipairs(CollectionService:GetTagged("MergeEggPlaced")) do
        if egg:GetAttribute("OwnerUserId") == LocalPlayer.UserId and (egg:GetAttribute("ReadyAtServerTime") or math.huge) <= now then
            xDTaraZ:Fire("MergeMachineRemote", "HatchEgg", egg:GetAttribute("EggId"))
            done += 1
        end
    end
    local tools = xDTaraZ.Eggs.Tools()
    local hitbox = #tools > 0 and xDTaraZ.Base.Hitbox()
    if not hitbox then return done end
    local _, hum = xDTaraZ:Character()
    for i, tool in ipairs(tools) do
        if hum then hum:EquipTool(tool) end
        local offset = vector3New((i % 3 - 1) * Config.EggSpacing, -hitbox.Size.Y / 2 + 0.5, math.floor(i / 3) * Config.EggSpacing)
        xDTaraZ:Fire("MergeMachineRemote", "PlaceEgg", tool, hitbox.Position + offset)
        done += 1
        task.wait(0.2)
    end
    return done
end

xDTaraZ.Teleport = {}

function xDTaraZ.Teleport.Zones()
    local names = {}
    for _, zone in ipairs(xDTaraZ.ZoneList) do names[#names + 1] = zone.Name end
    return names
end

function xDTaraZ.Teleport.Zone(name)
    local builds = Workspace:FindFirstChild("Build") and Workspace.Build:FindFirstChild("ZoneBuilds")
    local zone = builds and builds:FindFirstChild(name)
    if not zone then return end
    local eggs = zone:FindFirstChild("Eggs")
    local spot = eggs and eggs:FindFirstChildWhichIsA("BasePart", true)
    local pos = spot and spot.Position or zone:GetPivot().Position
    xDTaraZ.Move.To(cframeNew(pos + vector3New(0, 6, 0)))
end

function xDTaraZ.Teleport.Places()
    local list = { "My Base" }
    local booths = Workspace:FindFirstChild("Booths")
    if booths then
        for _, booth in ipairs(booths:GetChildren()) do list[#list + 1] = booth.Name end
    end
    if Workspace:FindFirstChild("EggMachine") then list[#list + 1] = "Egg Machine" end
    return list
end

function xDTaraZ.Teleport.Place(name)
    if name == "My Base" then
        xDTaraZ.Base.Home()
        return
    end
    local target = name == "Egg Machine" and Workspace:FindFirstChild("EggMachine") or (Workspace:FindFirstChild("Booths") and Workspace.Booths:FindFirstChild(name))
    if target then xDTaraZ.Move.To(cframeNew(target:GetPivot().Position + vector3New(0, 4, 6))) end
end

function xDTaraZ.Teleport.Player(name)
    local player = Players:FindFirstChild(name or "")
    local root = xDTaraZ.Bat.RootOf(player)
    if root then xDTaraZ.Move.To(root.CFrame * cframeNew(0, 0, 3)) end
end

xDTaraZ.Esp = { Tags = {} }

function xDTaraZ.Esp.Folder()
    local folder = State.EspFolder
    if folder and folder.Parent then return folder end
    folder = Instance.new("Folder")
    folder.Name = "NovaEsp"
    local ok = pcall(function() folder.Parent = (gethui and gethui()) or CoreGui end)
    if not ok then folder.Parent = LocalPlayer:WaitForChild("PlayerGui", Config.LoadTimeout) end
    State.EspFolder = folder
    return folder
end

function xDTaraZ.Esp.Tag(adornee, text, color)
    local tag = xDTaraZ.Esp.Tags[adornee]
    if not tag then
        tag = Instance.new("BillboardGui")
        tag.AlwaysOnTop = true
        tag.Size = UDim2.fromOffset(200, 34)
        tag.StudsOffset = vector3New(0, 3, 0)
        tag.MaxDistance = 5000
        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.fromScale(1, 1)
        label.Font = Enum.Font.GothamBold
        label.TextSize = 13
        label.TextStrokeTransparency = 0.3
        label.Parent = tag
        tag.Parent = xDTaraZ.Esp.Folder()
        xDTaraZ.Esp.Tags[adornee] = tag
    end
    tag.Adornee = adornee
    tag.TextLabel.Text = text
    tag.TextLabel.TextColor3 = color
    return tag
end

xDTaraZ.Esp.RarityColors = {
    Common = Color3.fromRGB(200, 200, 200), Uncommon = Color3.fromRGB(110, 230, 110), Rare = Color3.fromRGB(80, 170, 255),
    Epic = Color3.fromRGB(190, 110, 255), Legendary = Color3.fromRGB(255, 190, 60), Mythic = Color3.fromRGB(255, 80, 120),
}

function xDTaraZ.Esp.Step()
    local opt = State.Opt
    local _, _, hrp = xDTaraZ:Character()
    local origin = hrp and hrp.Position or Vector3.zero
    local seen = {}
    local minRank = xDTaraZ.RarityRank[opt.EspMinRarity] or 1

    if opt.EspPickups and Workspace:FindFirstChild("AnimalPickups") then
        for _, model in ipairs(Workspace.AnimalPickups:GetChildren()) do
            local rarity = model:GetAttribute("Rarity") or "Common"
            local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
            if part and (xDTaraZ.RarityRank[rarity] or 1) >= minRank then
                seen[part] = true
                xDTaraZ.Esp.Tag(part, ("%s [%s] %.0fkg\n$%s/s · %dm"):format(tostring(model:GetAttribute("AnimalName")), rarity, model:GetAttribute("WeightKg") or 0, xDTaraZ.Format(xDTaraZ.Pickup.Value(model)), (part.Position - origin).Magnitude), xDTaraZ.Esp.RarityColors[rarity] or Color3.fromRGB(255, 120, 255))
            end
        end
    end

    if opt.EspEggs then
        local damage = xDTaraZ.Break.Damage()
        for _, egg in ipairs(CollectionService:GetTagged("BreakableEgg")) do
            if xDTaraZ.Break.Alive(egg) then
                seen[egg] = true
                local hits = math.ceil(egg:GetAttribute("Health") / damage)
                xDTaraZ.Esp.Tag(egg, ("%s · Z%s\n%s HP · %d hits"):format(tostring(egg:GetAttribute("EggType")), tostring(egg:GetAttribute("ZoneIndex")), xDTaraZ.Format(egg:GetAttribute("Health")), hits), hits <= opt.MaxHits and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(255, 120, 100))
            end
        end
    end

    if opt.EspPlayers then
        for _, player in ipairs(Players:GetPlayers()) do
            local root = player ~= LocalPlayer and xDTaraZ.Bat.RootOf(player)
            if root then
                seen[root] = true
                local carry = player:GetAttribute("CarryCount") or 0
                xDTaraZ.Esp.Tag(root, ("%s · %dm%s"):format(player.DisplayName, (root.Position - origin).Magnitude, carry > 0 and ("\nCarrying " .. tostring(player:GetAttribute("Carrying"))) or ""), carry > 0 and Color3.fromRGB(255, 200, 60) or Color3.fromRGB(255, 255, 255))
            end
        end
    end

    for adornee, tag in pairs(xDTaraZ.Esp.Tags) do
        if not seen[adornee] or not adornee.Parent then
            tag:Destroy()
            xDTaraZ.Esp.Tags[adornee] = nil
        end
    end
end

function xDTaraZ.Esp.Clear()
    for adornee, tag in pairs(xDTaraZ.Esp.Tags) do
        tag:Destroy()
        xDTaraZ.Esp.Tags[adornee] = nil
    end
end

xDTaraZ.Session = {}

function xDTaraZ.Session.Rejoin()
    if #Players:GetPlayers() <= 1 then
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    else
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
    end
end

function xDTaraZ.Session.Bind()
    xDTaraZ:Connect(LocalPlayer.Idled, function()
        if not State.Opt.AntiAfk then return end
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
    xDTaraZ:Connect(UserInputService.JumpRequest, function()
        if not State.Opt.InfJump then return end
        local _, hum = xDTaraZ:Character()
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end)
    xDTaraZ:Connect(RunService.Stepped, function()
        if State.Opt.Noclip then xDTaraZ.Move.SetNoclip(true) end
    end)
    xDTaraZ:Connect(LocalPlayer.CharacterAdded, function(char)
        State.NoclipParts = nil
        local hum = char:WaitForChild("Humanoid", 10)
        if not hum then return end
        xDTaraZ.Move.HoldSpeed(hum)
        if State.Opt.SpeedOn then State.Requests.Speed = true end
    end)
    local _, hum = xDTaraZ:Character()
    if hum then xDTaraZ.Move.HoldSpeed(hum) end
    local overlay = CoreGui:FindFirstChild("RobloxPromptGui")
    overlay = overlay and overlay:FindFirstChild("promptOverlay")
    if overlay then
        xDTaraZ:Connect(overlay.ChildAdded, function(child)
            if child.Name ~= "ErrorPrompt" or not State.Opt.AutoRejoin or State.Rejoining then return end
            State.Rejoining = true
            task.delay(Config.RejoinDelay, xDTaraZ.Session.Rejoin)
        end)
    end
end

xDTaraZ.Scheduler = {}

xDTaraZ.Scheduler.RequestHandlers = {
    Speed = xDTaraZ.Move.ApplySpeed,
    Place = xDTaraZ.Pets.Place,
    SellNow = function() xDTaraZ:Notify(("Sold %d animals"):format(xDTaraZ.Pets.Sell())) end,
    UpgradeNow = xDTaraZ.Shop.Now,
    ClaimNow = xDTaraZ.Rewards.Claim,
}

xDTaraZ.Scheduler.MoveHandlers = {
    StealNow = function()
        local folder = Workspace:FindFirstChild("AnimalPickups")
        local best, bestValue = nil, -1
        for _, model in ipairs(folder and folder:GetChildren() or {}) do
            local value = xDTaraZ.Pickup.Value(model)
            if value > bestValue then best, bestValue = model, value end
        end
        if best and xDTaraZ.Pickup.Grab(best) then xDTaraZ.Base.Bank() end
        xDTaraZ.Farm.Rest()
    end,
    BankNow = function()
        xDTaraZ.Base.Bank()
        xDTaraZ.Farm.Rest()
    end,
    HatchNow = function() xDTaraZ:Notify(("Eggs handled: %d"):format(xDTaraZ.Eggs.Step())) end,
    BatNow = function() xDTaraZ.Bat.Swing(Players:FindFirstChild(State.Opt.BatTarget or ""), true) end,
    Goto = function()
        local job = State.Goto
        State.Goto = nil
        if job then job() end
    end,
}

function xDTaraZ.Scheduler.Drain(handlers)
    for name, handler in pairs(handlers) do
        if State.Requests[name] then
            State.Requests[name] = nil
            xDTaraZ.Scheduler.Run(name, handler)
        end
    end
end

---Runs one round of a job, warning once per failure streak; toggles that keep failing for Config.FailWindow seconds are switched off and queued for the UI to report.
---@param key string|string[]  State.Opt flag(s) of the feature, or a plain label for jobs without one
function xDTaraZ.Scheduler.Run(key, fn)
    local ok, err = pcall(fn)
    local label = type(key) == "table" and key[1] or key
    local failures = State.Failures
    if ok then
        failures[label] = nil
        return
    end

    local streak = failures[label]
    if not streak then
        streak = { count = 0, since = osClock() }
        failures[label] = streak
        warn("[BreakStealEgg]", label, err)
    end
    streak.count += 1
    if streak.count < Config.MaxFailures or osClock() - streak.since < Config.FailWindow then return end

    local reason = tostring(err):match("[^\n]*")
    for _, flag in ipairs(type(key) == "table" and key or { key }) do
        if State.Opt[flag] ~= true then continue end
        failures[label] = nil
        State.Opt[flag] = false
        warn("[BreakStealEgg]", flag, "stopped:", reason)
        table.insert(State.Halted, { flag, reason })
    end
end

---@param stamp string  State.Last field holding the last run time
---@param key string|string[]  passed on to Run
function xDTaraZ.Scheduler.Every(stamp, key, interval, fn)
    if osClock() - (State.Last[stamp] or 0) < interval then return end
    State.Last[stamp] = osClock()
    xDTaraZ.Scheduler.Run(key, fn)
end

xDTaraZ.Scheduler.ShopFlags = { "AutoUpgrade" }
xDTaraZ.Scheduler.EspFlags = { "EspPickups", "EspEggs", "EspPlayers" }
xDTaraZ.Scheduler.FarmFlags = { "AutoSteal", "AutoBreak", "RobCarriers" }

function xDTaraZ.Scheduler.Summarize()
    local cash = xDTaraZ.Attr("Cash", 0)
    State.StartCash = State.StartCash or cash
    local plot = xDTaraZ.Base.Own()
    local minutes = math.max((osClock() - State.StartAt) / 60, 1 / 60)
    local carry, cap = xDTaraZ.Base.Carry()
    local tier = xDTaraZ.Attr("PickaxeTier", 1)
    local pickaxe = GameLib.Pickaxe and GameLib.Pickaxe.Tiers[tier]
    State.Summary = ("Cash %s · %s/s\n%s (%s dmg) · Carry %d/%d\nBase %s/%s animals · Level %s"):format(
        xDTaraZ.Format(cash), xDTaraZ.Format(xDTaraZ.Attr("CashPerSecond", 0)),
        pickaxe and pickaxe.Name or "-", pickaxe and xDTaraZ.Format(xDTaraZ.Break.Damage()) or "-", carry, cap,
        tostring(plot and plot:GetAttribute("AnimalsPlaced") or "-"), tostring(plot and plot:GetAttribute("MaxAnimals") or "-"),
        tostring(plot and plot:GetAttribute("PlotLevel") or "-"))
    State.RunText = ("%s\nSteals %d · Eggs %d · Banked %d · +%s/min"):format(
        State.Status, State.Steals, State.Broken, State.Banked, xDTaraZ.Format((cash - State.StartCash) / minutes))
end

function xDTaraZ.Scheduler.Side()
    local opt = State.Opt
    xDTaraZ.Scheduler.Every("Summary", "Summary", 0.5, xDTaraZ.Scheduler.Summarize)
    xDTaraZ.Scheduler.Drain(xDTaraZ.Scheduler.RequestHandlers)
    if opt.AutoPlace then xDTaraZ.Scheduler.Every("Place", "AutoPlace", Config.EquipInterval, xDTaraZ.Pets.Place) end
    if opt.AutoSell then xDTaraZ.Scheduler.Every("Sell", "AutoSell", Config.SellInterval, xDTaraZ.Pets.Sell) end
    if opt.AutoBuyPickaxe or opt.AutoUpgradePlot or opt.AutoTrail or opt.AutoTreadmill then xDTaraZ.Scheduler.Every("Shop", xDTaraZ.Scheduler.ShopFlags, Config.BuyInterval, xDTaraZ.Shop.Step) end
    if opt.AutoClaim then xDTaraZ.Scheduler.Every("Claim", "AutoClaim", Config.ClaimInterval, xDTaraZ.Rewards.Claim) end
    if opt.EspPickups or opt.EspEggs or opt.EspPlayers then
        xDTaraZ.Scheduler.Every("Esp", xDTaraZ.Scheduler.EspFlags, Config.EspInterval, xDTaraZ.Esp.Step)
    elseif next(xDTaraZ.Esp.Tags) then
        xDTaraZ.Esp.Clear()
    end
end

function xDTaraZ.Scheduler.Control()
    local opt = State.Opt
    xDTaraZ.Scheduler.Drain(xDTaraZ.Scheduler.MoveHandlers)
    if opt.BatLoop and opt.BatTarget then
        xDTaraZ.Scheduler.Run("BatLoop", function() xDTaraZ.Bat.Swing(Players:FindFirstChild(opt.BatTarget), true) end)
        return
    end
    if opt.BatAura then xDTaraZ.Scheduler.Run("BatAura", xDTaraZ.Bat.Aura) end
    if opt.AutoHatch then xDTaraZ.Scheduler.Every("Eggs", "AutoHatch", Config.EggInterval, xDTaraZ.Eggs.Step) end
    xDTaraZ.Scheduler.Run(xDTaraZ.Scheduler.FarmFlags, xDTaraZ.Farm.Step)
end

function xDTaraZ.Scheduler.Boot()
    xDTaraZ.Session.Bind()
    xDTaraZ.Scheduler.Run("Watch", xDTaraZ.Rewards.Watch)
    task.spawn(function()
        while State.Alive do
            xDTaraZ.Scheduler.Side()
            task.wait(0.1)
        end
    end)
    task.spawn(function()
        while State.Alive do
            xDTaraZ.Scheduler.Control()
            task.wait(Config.TickDelay)
        end
    end)
end

function xDTaraZ.Scheduler.Stop()
    State.Alive = false
    for _, conn in ipairs(State.Connections) do conn:Disconnect() end
    if State.SpeedConn then State.SpeedConn:Disconnect() end
    table.clear(State.Connections)
    State.Opt.SpeedOn = false
    xDTaraZ.Move.ApplySpeed()
    xDTaraZ.Move.SetNoclip(false)
    xDTaraZ.Esp.Clear()
    if State.EspFolder then State.EspFolder:Destroy() end
end

local function BuildInterface()
    local Library = xDTaraZ.Util.LoadLibrary()
    if not Library then return end
    xDTaraZ.Compat = Library.Compat
    pcall(NovaBanner.Step, "UI library")
    local Options = Library.Options
    local T = function(en, th) return Library:T(en, th) end
    local opt = State.Opt
    local names = {}

    local function Notify(text, kind)
        Library:Notify("Break and Steal an Egg", text, 4, kind or "Info")
    end

    local function Request(name)
        return function() State.Requests[name] = true end
    end

    local function Toggle(group, key, info, onChange)
        names[key] = info.Text
        info.Default = false
        info.Callback = function(value)
            opt[key] = value
            if onChange then onChange(value) end
        end
        return group:AddToggle(key, info)
    end

    ---@return table  toggle with an unbound key saved as <key>Key
    local function Feature(group, key, info, onChange)
        return Toggle(group, key, info, onChange):AddKeyPicker(key .. "Key", { Default = "None", Mode = "Toggle" })
    end

    local function ToSet(selected)
        local set = {}
        if type(selected) ~= "table" then return set end
        for k, v in pairs(selected) do
            if v == true then set[k] = true elseif type(v) == "string" then set[v] = true end
        end
        return set
    end

    local function Goto(fn, arg)
        State.Goto = function() fn(arg) end
        State.Requests.Goto = true
    end

    local function PlayerNames()
        local list = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then list[#list + 1] = player.Name end
        end
        table.sort(list)
        return list
    end

    ---@return table  { Summary, Run } labels the pump refreshes
    local function BuildMain(window)
        window:AddTabSection(T("Main", "หลัก"))
        local tab = window:AddTab(T("Main", "หลัก"), "house", T("Status and all-in-one mode", "สถานะและโหมดทำทุกอย่าง"))

        local statusBox = tab:AddLeftGroupbox(T("Status", "สถานะ"), "star")
        local labels = {
            Summary = statusBox:AddLabel(T("Loading...", "กำลังโหลด...")),
            Run = statusBox:AddLabel("-"),
        }

        local kaitunBox = tab:AddRightGroupbox(T("Kaitun", "ไก่ตัน"), "oneup")
        kaitunBox:AddToggle("Kaitun", {
            Text = T("Kaitun (All-in-one)", "ไก่ตัน (ทำทุกอย่าง)"),
            Description = T("Steals, breaks eggs, places, sells, upgrades and claims rewards by itself", "ขโมย ทุบไข่ วางสัตว์ ขาย อัปเกรด และรับรางวัลให้เองทั้งหมด"),
            NoSave = true,
            Callback = function(value)
                State.KaitunSet = State.KaitunSet or {}
                for _, key in ipairs({ "AutoSteal", "AutoBreak", "AutoPlace", "AutoSell", "AutoUpgrade", "AutoClaim", "AutoHatch", "AntiAfk" }) do
                    if value and not opt[key] then
                        State.KaitunSet[key] = true
                        Options[key]:SetValue(true)
                    elseif not value and State.KaitunSet[key] then
                        State.KaitunSet[key] = nil
                        Options[key]:SetValue(false)
                    end
                end
            end,
        }):AddKeyPicker("KaitunKey", { Default = "None", Mode = "Toggle" })

        local discordBox = tab:AddRightGroupbox(T("Discord", "Discord"), "link")
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

        return labels
    end

    local function BuildFarm(window)
        window:AddTabSection(T("Farming", "ฟาร์ม"))
        local tab = window:AddTab(T("Steal & Break", "ขโมยและทุบไข่"), "star", T("Steal animals and break eggs", "ขโมยสัตว์และทุบไข่"))

        local stealBox = tab:AddLeftGroupbox(T("Auto Steal", "ขโมยอัตโนมัติ"), "star")
        Feature(stealBox, "AutoSteal", { Text = T("Auto Steal", "ขโมยอัตโนมัติ"), Description = T("Grabs the most valuable animals on the map and brings them home instantly", "คว้าสัตว์ที่มีค่าที่สุดบนแมพแล้วพากลับฐานทันที") })
        stealBox:AddDropdown("Take", {
            Text = T("Take", "เก็บ"),
            Description = T("Upgrades Only = only animals that earn more than your weakest one", "Upgrades Only = เฉพาะตัวที่ทำเงินมากกว่าตัวที่อ่อนสุดบนฐาน"),
            Values = { "Upgrades Only", "Everything" },
            Default = 1,
            Callback = function(value) opt.Take = value or "Upgrades Only" end,
        })
        stealBox:AddDropdown("StealRarities", {
            Text = T("Only Rarities", "เฉพาะ rarity"),
            Description = T("Empty = take everything", "ไม่เลือก = เอาทุกตัว"),
            Values = xDTaraZ.RarityLadder,
            Multi = true,
            Default = {},
            Callback = function(selected) opt.StealRarities = ToSet(selected) end,
        })
        stealBox:AddInput("StealMinValue", {
            Text = T("Min Cash/s", "เงินต่อวิขั้นต่ำ"),
            Placeholder = "0",
            Numeric = true,
            Callback = function(value) opt.StealMinValue = tonumber(value) or 0 end,
        })
        stealBox:AddButton({ Text = T("Steal Best Now", "ขโมยตัวดีสุดเดี๋ยวนี้"), Style = "Primary", Func = Request("StealNow") })
        stealBox:AddButton({ Text = T("Bank Now", "เก็บเข้าฐานเดี๋ยวนี้"), Func = Request("BankNow") })

        local breakBox = tab:AddRightGroupbox(T("Auto Break", "ทุบไข่อัตโนมัติ"), "qblock")
        Feature(breakBox, "AutoBreak", { Text = T("Auto Break Eggs", "ทุบไข่อัตโนมัติ"), Description = T("Breaks eggs in any zone at max speed and takes the animal home", "ทุบไข่ได้ทุกโซนด้วยความเร็วสูงสุดแล้วพาสัตว์กลับฐาน") })
        local zoneChoices = { "Best" }
        for _, name in ipairs(xDTaraZ.Teleport.Zones()) do table.insert(zoneChoices, name) end
        breakBox:AddDropdown("BreakZone", {
            Text = T("Zone", "โซน"),
            Description = T("Best = most worth for the time spent", "Best = คุ้มที่สุดต่อเวลาที่ใช้"),
            Values = zoneChoices,
            Default = 1,
            Callback = function(value) opt.BreakZone = value or "Best" end,
        })
        breakBox:AddSlider("MaxHits", {
            Text = T("Max Hits Per Egg", "จำนวนตีสูงสุดต่อไข่"),
            Description = T("Skips eggs that take longer than this", "ข้ามไข่ที่ใช้นานกว่านี้"),
            Min = 1, Max = 200, Default = opt.MaxHits, Rounding = 0,
            Callback = function(value) opt.MaxHits = tonumber(value) or opt.MaxHits end,
        })

        local robBox = tab:AddRightGroupbox(T("Rob Players", "ปล้นผู้เล่น"), "swords")
        Toggle(robBox, "RobCarriers", { Text = T("Rob Carriers", "ปล้นคนที่แบกสัตว์"), Description = T("Bats players carrying animals and takes what they drop", "ตีผู้เล่นที่แบกสัตว์แล้วเก็บของที่หล่น"), Risky = true })
    end

    local function BuildBase(window)
        window:AddTabSection(T("Progression", "ความคืบหน้า"))
        local tab = window:AddTab(T("Base & Shop", "ฐานและร้านค้า"), "shop", T("Placing, selling, upgrades and rewards", "วางสัตว์ ขาย อัปเกรด และรางวัล"))

        local placeBox = tab:AddLeftGroupbox(T("Animals", "สัตว์"), "mushroom")
        Feature(placeBox, "AutoPlace", { Text = T("Auto Place Best", "วางตัวดีสุดอัตโนมัติ"), Description = T("Keeps the best earners standing on your base", "วางตัวที่ทำเงินดีสุดไว้บนฐานตลอด") })
        placeBox:AddButton({ Text = T("Place Best Now", "วางตัวดีสุดเดี๋ยวนี้"), Func = Request("Place") })

        local sellBox = tab:AddLeftGroupbox(T("Sell", "ขาย"), "coin")
        Feature(sellBox, "AutoSell", { Text = T("Auto Sell Leftovers", "ขายตัวที่เหลืออัตโนมัติ"), Description = T("Sells animals in your backpack that did not fit on the base", "ขายสัตว์ในกระเป๋าที่ไม่ได้วางบนฐาน") })
        sellBox:AddDropdown("KeepRarities", {
            Text = T("Never Sell", "ไม่ขาย"),
            Values = xDTaraZ.RarityLadder,
            Multi = true,
            Default = {},
            Callback = function(selected) opt.KeepRarities = ToSet(selected) end,
        })
        sellBox:AddButton({ Text = T("Sell All Now", "ขายทั้งหมดเดี๋ยวนี้"), Func = Request("SellNow") })

        local shopBox = tab:AddRightGroupbox(T("Upgrades", "อัปเกรด"), "coin")
        Feature(shopBox, "AutoUpgrade", { Text = T("Auto Upgrade", "อัปเกรดอัตโนมัติ"), Description = T("Buys the picked upgrades as soon as you can pay", "ซื้ออัปเกรดที่เลือกทันทีที่เงินพอ") }, xDTaraZ.Shop.Sync)
        shopBox:AddDropdown("UpgradeTargets", {
            Text = T("Upgrade", "อัปเกรด"),
            Description = T("Pickaxe jumps to the best you can afford, Trail buys and wears the strongest", "Pickaxe ข้ามไปตัวดีสุดที่ซื้อไหว Trail ซื้อและใส่ตัวแรงสุด"),
            Values = { "Pickaxe", "Base", "Trail", "Treadmill" },
            Multi = true,
            Default = { "Pickaxe", "Base", "Trail", "Treadmill" },
            Callback = function(selected)
                opt.UpgradeTargets = ToSet(selected)
                xDTaraZ.Shop.Sync()
            end,
        })
        shopBox:AddButton({ Text = T("Upgrade Now", "อัปเกรดเดี๋ยวนี้"), Func = Request("UpgradeNow") })
        shopBox:AddInput("CashReserve", {
            Text = T("Keep Cash", "กันเงินไว้"),
            Description = T("Upgrades never spend below this", "อัปเกรดจะไม่ใช้เงินต่ำกว่านี้"),
            Placeholder = "0",
            Numeric = true,
            Callback = function(value) opt.CashReserve = tonumber(value) or 0 end,
        })

        local hatchBox = tab:AddLeftGroupbox(T("Eggs", "ไข่"), "mushroom")
        Feature(hatchBox, "AutoHatch", { Text = T("Auto Hatch Eggs", "ฟักไข่อัตโนมัติ"), Description = T("Places eggs from your backpack on your base and hatches them when ready", "วางไข่ในกระเป๋าบนฐานแล้วฟักเมื่อพร้อม") })
        hatchBox:AddButton({ Text = T("Hatch Eggs Now", "ฟักไข่เดี๋ยวนี้"), Func = Request("HatchNow") })

        local rewardBox = tab:AddRightGroupbox(T("Rewards", "รางวัล"), "star")
        Feature(rewardBox, "AutoClaim", { Text = T("Auto Claim", "รับรางวัลอัตโนมัติ"), Description = T("Claims index, offline, group and community rewards, no joining needed", "รับรางวัล Index ออฟไลน์ กลุ่ม และคอมมูนิตี้ ไม่ต้องเข้ากลุ่ม") })
        rewardBox:AddButton({ Text = T("Claim Now", "รับเดี๋ยวนี้"), Func = Request("ClaimNow") })
    end

    local function BuildPlayer(window)
        local tab = window:AddTab(T("Player", "ผู้เล่น"), "user", T("Movement and teleports", "การเคลื่อนที่และวาร์ป"))

        local moveBox = tab:AddLeftGroupbox(T("Movement", "การเคลื่อนที่"), "star")
        Feature(moveBox, "SpeedOn", { Text = T("Speed", "ความเร็ว") }, Request("Speed"))
        moveBox:AddSlider("WalkSpeed", {
            Text = T("Walk Speed", "ความเร็วเดิน"),
            Min = 16, Max = 300, Default = opt.WalkSpeed, Rounding = 0,
            Callback = function(value)
                opt.WalkSpeed = tonumber(value) or opt.WalkSpeed
                if opt.SpeedOn then State.Requests.Speed = true end
            end,
        })
        Feature(moveBox, "InfJump", { Text = T("Infinite Jump", "กระโดดไม่จำกัด") })
        Feature(moveBox, "Noclip", { Text = T("Noclip", "ทะลุกำแพง") }, function(on) if not on then xDTaraZ.Move.SetNoclip(false) end end)

        local tpBox = tab:AddRightGroupbox(T("Teleport", "วาร์ป"), "teleport")
        tpBox:AddDropdown("TpZone", {
            AllowNull = true,
            Text = T("Zone", "โซน"),
            Values = xDTaraZ.Teleport.Zones(),
            Searchable = true,
            NoSave = true,
            Callback = function(value) if value then Goto(xDTaraZ.Teleport.Zone, value) end end,
        })
        tpBox:AddDropdown("TpPlace", {
            AllowNull = true,
            Text = T("Place", "สถานที่"),
            Values = xDTaraZ.Teleport.Places(),
            NoSave = true,
            Callback = function(value) if value then Goto(xDTaraZ.Teleport.Place, value) end end,
        })
        local tpPlayer = tpBox:AddDropdown("TpPlayer", {
            AllowNull = true,
            Text = T("Player", "ผู้เล่น"),
            Values = PlayerNames(),
            Searchable = true,
            NoSave = true,
            Callback = function(value) if value then Goto(xDTaraZ.Teleport.Player, value) end end,
        })
        tpBox:AddButton({ Text = T("Refresh Players", "รีเฟรชผู้เล่น"), Func = function() tpPlayer:SetValues(PlayerNames()) end })
    end

    local function BuildVisuals(window)
        local tab = window:AddTab(T("Visuals", "มองเห็น"), "eye", T("See animals, eggs and players", "มองเห็นสัตว์ ไข่ และผู้เล่น"))
        local espBox = tab:AddLeftGroupbox(T("ESP", "ESP"), "eye")
        Toggle(espBox, "EspPickups", { Text = T("Animals", "สัตว์"), Description = T("Name, rarity, weight and cash per second", "ชื่อ rarity น้ำหนัก และเงินต่อวิ") })
        espBox:AddDropdown("EspMinRarity", {
            Text = T("Min Rarity", "rarity ขั้นต่ำ"),
            Values = xDTaraZ.RarityLadder,
            Default = 1,
            Callback = function(value) opt.EspMinRarity = value or "Common" end,
        })

        local worldEspBox = tab:AddRightGroupbox(T("Eggs & Players", "ไข่และผู้เล่น"), "eye")
        Toggle(worldEspBox, "EspEggs", { Text = T("Eggs", "ไข่"), Description = T("HP and how many hits it takes", "HP และจำนวนครั้งที่ต้องตี") })
        Toggle(worldEspBox, "EspPlayers", { Text = T("Players", "ผู้เล่น"), Description = T("Distance and what they carry", "ระยะและสิ่งที่แบกอยู่") })
    end

    local function BuildTroll(window)
        local tab = window:AddTab(T("Troll", "ป่วน"), "troll", T("Bat other players", "ตีผู้เล่นอื่น"))
        local batBox = tab:AddLeftGroupbox(T("Bat", "ไม้ตี"), "swords")
        local batTarget = batBox:AddDropdown("BatTarget", {
            AllowNull = true,
            Text = T("Target", "เป้าหมาย"),
            Values = PlayerNames(),
            Searchable = true,
            NoSave = true,
            Callback = function(value) opt.BatTarget = value end,
        })
        batBox:AddButton({ Text = T("Refresh Players", "รีเฟรชผู้เล่น"), Func = function() batTarget:SetValues(PlayerNames()) end })
        Feature(batBox, "BatLoop", { Text = T("Loop Bat Target", "ตีเป้าหมายวนไป"), Description = T("Follows the target and keeps knocking them over", "ตามเป้าหมายแล้วตีล้มไม่หยุด"), Risky = true })
        batBox:AddButton({ Text = T("Bat Target Now", "ตีเป้าหมายเดี๋ยวนี้"), Func = Request("BatNow") })

        local auraBox = tab:AddRightGroupbox(T("Bat Aura", "ออร่าไม้ตี"), "swords")
        Feature(auraBox, "BatAura", { Text = T("Bat Aura", "ออร่าไม้ตี"), Description = T("Knocks over anyone who gets close", "ตีล้มทุกคนที่เข้าใกล้"), Risky = true })
    end

    local function BuildSettings(window)
        local tab = window:AddSettingsTab()
        local sessionBox = tab:AddRightGroupbox(T("Session", "เซสชัน"), "gear")
        Toggle(sessionBox, "AntiAfk", { Text = T("Anti AFK", "กันหลุด AFK"), Description = T("Stops the idle kick", "กันโดนเตะเพราะไม่ขยับ") })
        Toggle(sessionBox, "AutoRejoin", { Text = T("Auto Rejoin", "เข้าเกมใหม่อัตโนมัติ"), Description = T("Rejoins by itself after a disconnect", "หลุดแล้วเข้าเกมใหม่เอง") })
        sessionBox:AddButton({ Text = T("Rejoin Now", "เข้าเกมใหม่เดี๋ยวนี้"), Func = xDTaraZ.Session.Rejoin })
    end

    local function ReportHalts()
        for _, halt in ipairs(State.Halted) do
            local flag, reason = halt[1], halt[2]
            local toggle = Options[flag]
            if toggle and toggle.Value then toggle:SetValue(false) end
            Notify(("%s stopped: %s"):format(names[flag] and names[flag].EN or flag, reason), "Warning")
        end
        table.clear(State.Halted)
    end

    ---@return number  features blocked because a game module did not load
    local function GateModules()
        local gated = 0
        for idx in pairs(GameLib.Needs) do
            local missing = GameLib.Missing(idx)
            if not (missing and Options[idx]) then continue end
            warn("[BreakStealEgg] " .. idx .. " disabled, missing: " .. missing)
            local reason = missing:find("^Remote%.") and T("Not available after a game update", "ใช้ไม่ได้หลังเกมอัปเดต")
                or T("Not available on this executor", "ใช้กับ executor นี้ไม่ได้")
            if Library.Compat then
                Library.Compat.Block(idx, reason)
            else
                local toggle = Options[idx]
                toggle:OnChanged(function(on)
                    if not on then return end
                    toggle:SetValue(false)
                    Notify(reason.EN or "Not available on this executor", "Warning")
                end)
            end
            gated += 1
        end
        return gated
    end

    local function BuildTabs()
        local window = Library.Window
        local try = xDTaraZ.Util.Try
        local _, labels = try("ui main", BuildMain, window)
        try("ui farm", BuildFarm, window)
        try("ui base", BuildBase, window)

        window:AddTabSection(T("Misc", "อื่นๆ"))
        for _, build in ipairs({ BuildPlayer, BuildVisuals, BuildTroll, BuildSettings }) do
            try("ui misc", build, window)
        end

        local _, gated = try("ui gate", GateModules)
        if type(gated) == "number" and gated > 0 then
            Library:Notify("Break and Steal an Egg", "Some features can't find the game parts they need and are turned off.", 8, "Warning")
        end

        Library:Every(0.5, function()
            ReportHalts()
            while #State.Messages > 0 do
                Notify(table.remove(State.Messages, 1))
            end
            if type(labels) ~= "table" then return end
            labels.Summary:SetText(State.Summary or "-")
            labels.Run:SetText(State.RunText or State.Status)
        end)
    end

    local function Unload()
        Library:Unload()
    end
    Library:OnUnload(function()
        xDTaraZ.Scheduler.Stop()
        if getgenv().BreakStealEggUnload == Unload then getgenv().BreakStealEggUnload = nil end
    end)
    getgenv().BreakStealEggUnload = Unload

    Library:CreateWindow({
        Title = "Nova Hub",
        SubTitle = "Break and Steal an Egg by xDTaraZ",
        MenuKey = Enum.KeyCode.LeftControl,
        ConfigFolder = Config.SaveFolder,
        Language = "Auto",
        Theme = "Nova",
        OnUnlocked = function()
            xDTaraZ.Util.Try("build", BuildTabs)
            if xDTaraZ.Util.Try("boot", xDTaraZ.Scheduler.Boot) then Notify("Loaded", "Success") end
            xDTaraZ.Util.Try("autoload", Library.LoadAutoloadConfig, Library)
        end,
    })
end

if getgenv().BreakStealEggUnload then
    pcall(getgenv().BreakStealEggUnload)
end

pcall(NovaBanner.Step, "Systems")
BuildInterface()
pcall(NovaBanner.Step, "Interface")
pcall(NovaBanner.Ready)]==]

NOVA_HUB_MODULES[10765012427] = [==[if not game:IsLoaded() then
    game.Loaded:Wait()
end

if game.GameId ~= 10765012427 then
    game:GetService("Players").LocalPlayer:Kick("Nova Hub: this script is for Build the Pyramid only")
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
        "   BUILD THE PYRAMID  //  by xDTaraZ  //  discord.gg/FHVfmeSceA",
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
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local VirtualUser = game:GetService("VirtualUser")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local osClock = os.clock
local vector3New = Vector3.new

local xDTaraZ = setmetatable({}, {
    __newindex = function(self, key, value)
        rawset(self, key, type(value) == "function" and LPH_JIT(value) or value)
    end,
})

xDTaraZ.Config = {
    Discord = "https://discord.gg/FHVfmeSceA",
    UpdateLog = {
        { "2026-10-04", "Auto Farm twice as fast\nPlace Distance option\nBalanced mode trains Strength only when it pays back\nAuto Upgrade buys the best upgrade first\nPick your Bench and Treadmill gym\nSpend Banked Blocks & Claim Free Gift\nRemoved keybinds from auto features" },
        { "2026-10-03", "Classic Nova Hub UI is back\nBetter executor support\nBug fixes & better UI" },
    },
    UiSource = "NovaHub://embedded-ui",
    ReloadSource = [[
local url = "NovaHub://embedded-loader"
local ok, body = pcall(game.HttpGet, game, url)
if not (ok and type(body) == "string") then
    local requester = request or http_request or (syn and syn.request) or (http and http.request)
    local sent, reply = pcall(requester, { Url = url, Method = "GET" })
    body = sent and type(reply) == "table" and reply.Body
end
if type(body) == "string" then loadstring(body)() end]],
    SaveFolder = "Build the Pyramid",
    TickDelay = 0.1,
    LoadTimeout = 10,
    AlertTries = 20,
    AlertGap = 0.5,
    FailLimit = 5,
    FailWindow = 10,
    SettleDelay = 0.15,
    StreamWait = 2,
    StreamDistance = 200,
    CameraShieldJump = 100,
    PickupRetries = 3,
    PickupTimeout = 2,
    BenchBase = 3.75,
    LevelProbe = 1000,
    SmartRefresh = 2,
    RateSample = 15,
    SaveSeconds = 600,
    UpgradePriority = { "bulkPlace", "placementRange", "bulkPickup" },
    QuarryJitter = 0.35,
    RetryDelay = 1,
    RetryMax = 8,
    StallLimit = 120,
    PlaceTimeout = 3,
    PlaceRetries = 3,
    SlotSpacing = 2,
    SlotSearchCells = 150,
    EngineRadiusLimit = 15000,
    HoverHeight = 6,
    StandHeight = 3,
    QuarrySpot = vector3New(-234, -16, 38),
    BenchRange = 12,
    BenchRetry = 2,
    StandRadius = 4,
    UpgradeInterval = 2,
    UpgradeGap = 0.3,
    UpgradeBurst = 36,
    CodeGap = 1.1,
    ActivityInterval = 60,
    RateWindow = 60,
    RejoinDelay = 5,
    SlowRequests = { UpgradeNow = true, CodesNow = true, BankNow = true, GiftNow = true },
    ExtraCodes = { "SUNGOD", "SORRYFORUPDATEBUG", "FREECODE", "WELCOME", "DEADBYMELOL", "UPDATE15", "PYRAMID1500" },
}

xDTaraZ.State = {
    Alive = true,
    Connections = {},
    MoveConns = {},
    Requests = {},
    Running = {},
    Messages = {},
    Last = {},
    Stats = {},
    CoinLog = {},
    Fails = {},
    FailSince = {},
    Halted = {},
    HaltQueue = {},
    Status = "Idle",
    Task = "None",
    Placed = 0,
    FarmWait = 0,
    Opt = {
        AutoFarm = false,
        ReturnOnStop = false,
        PlaceReach = 30,
        BenchStation = "Best Unlocked",
        TreadmillStation = "Best Unlocked",
        AutoUpgrade = false,
        Upgrades = {},
        UpgradeOrder = "Best Value",
        KeepCoins = 0,
        AutoStrength = false,
        AutoSpeed = false,
        Priority = "Balanced",
        SmartMinutes = 30,
        AlternateMinutes = 5,
        AutoPool = false,
        SpeedOn = false,
        WalkSpeed = 100,
        Fly = false,
        FlySpeed = 60,
        Noclip = false,
        InfJump = false,
        AntiAfk = false,
        AutoRejoin = false,
        NoRender = false,
    },
}

local Config, State = xDTaraZ.Config, xDTaraZ.State

xDTaraZ.Util = {}

---@return string?, string?  body, or nil and why every transport failed
function xDTaraZ.Util.HttpGet(url)
    if url == "NovaHub://embedded-ui" then return NOVA_HUB_UI_SOURCE end
    local ok, body = pcall(game.HttpGet, game, url)
    if ok and type(body) == "string" then return body end
    local requester = request or http_request or (syn and syn.request) or (http and http.request)
    if not requester then return nil, "no http function" end

    local sent, reply = pcall(requester, { Url = url, Method = "GET" })
    if not sent or type(reply) ~= "table" then return nil, tostring(reply) end
    if reply.StatusCode ~= 200 or type(reply.Body) ~= "string" then return nil, "HTTP " .. tostring(reply.StatusCode) end
    return reply.Body
end

---@param detail any?  extra context for the console only
function xDTaraZ.Util.Alert(text, detail)
    warn("[BuildThePyramid]", text, detail or "")
    task.spawn(function()
        local starterGui = game:GetService("StarterGui")
        for _ = 1, Config.AlertTries do
            local shown = pcall(starterGui.SetCore, starterGui, "SendNotification", { Title = "Nova Hub", Text = text, Duration = 10 })
            if shown then return end
            task.wait(Config.AlertGap)
        end
    end)
end

---@return boolean  fn finished without error
function xDTaraZ.Util.Try(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then warn("[BuildThePyramid] " .. label .. ":", err) end
    return ok
end

---@return table?, string?  UI library, or nil and a message for the player
function xDTaraZ.Util.LoadLibrary(url)
    local source, why = xDTaraZ.Util.HttpGet(url)
    if not source or not source:sub(-64):find("return%s+Library%s*$") then
        warn("[BuildThePyramid] ui download:", why or "truncated or not the library")
        return nil, "Could not download the menu. Check your connection and run it again."
    end
    local chunk, compileErr = loadstring(source)
    if not chunk then return nil, "The menu failed to load on this executor: " .. tostring(compileErr) end
    local ok, lib = pcall(chunk)
    if not ok or type(lib) ~= "table" then return nil, "The menu failed to load on this executor: " .. tostring(lib) end
    return lib
end

---@return boolean  the hub is queued to load again after the next teleport
function xDTaraZ.Util.QueueReload()
    local queue = queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport)
    if not queue then return false end
    return (pcall(queue, Config.ReloadSource))
end

function xDTaraZ.Util.Copy(text)
    local copy = setclipboard or toclipboard
    if not copy then return false end
    return (pcall(copy, text))
end

local bootMissed = false

---@return Instance?  child, nil once Config.LoadTimeout runs out; no waiting after the first miss
local function Wait(parent, name)
    if not parent then return nil end
    if bootMissed then return parent:FindFirstChild(name) end
    local child = parent:WaitForChild(name, Config.LoadTimeout)
    if not child then bootMissed = true end
    return child
end

---@return Instance?  Services folder of whichever knit version the game ships
local function FindKnitServices()
    local index = Wait(Wait(ReplicatedStorage, "Packages"), "_Index")
    if not index then return nil end
    local fallback
    for _, package in ipairs(index:GetChildren()) do
        if not package.Name:find("^sleitnick_knit") then continue end
        local knit = package:FindFirstChild("knit")
        local services = knit and knit:FindFirstChild("Services")
        if services then return services end
        fallback = fallback or knit
    end
    return Wait(fallback, "Services")
end

local Shared = Wait(ReplicatedStorage, "Shared")
local SharedConfig = Wait(Shared, "Config")
local KnitServices = FindKnitServices()

if not (SharedConfig and KnitServices) then
    xDTaraZ.Util.Alert("Build the Pyramid was updated and this script needs an update too. Join discord.gg/FHVfmeSceA",
        SharedConfig and "knit Services folder not found" or "Shared.Config not found")
    return
end

---@return Instance?  RF/RE under a Knit service, found by name when the service moved; nil if renamed
local function Remote(service, kind, name)
    local remote = Wait(Wait(Wait(KnitServices, service), kind), name)
    if remote then return remote end
    for _, node in ipairs(KnitServices:GetDescendants()) do
        if node.Name == name and node.Parent and node.Parent.Name == kind then return node end
    end
    return nil
end

xDTaraZ.GameLib = {}
local GameLib = xDTaraZ.GameLib

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
    local deadline = osClock() + Config.LoadTimeout
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
    warn("[BuildThePyramid] require " .. module.Name .. ":", loaded)
    return nil
end

do
    local modules = {
        Pyramid = Wait(SharedConfig, "PyramidConfig"),
        Carry = Wait(SharedConfig, "CarryConfig"),
        Upgrades = Wait(SharedConfig, "UpgradeCatalog"),
        Gym = Wait(SharedConfig, "GymConfig"),
        Codes = Wait(SharedConfig, "CodesConfig"),
        Completion = Wait(SharedConfig, "PyramidCompletionConfig"),
        GymAccess = Wait(Wait(Shared, "Gym"), "GymAccess"),
        Runtime = Wait(Wait(Shared, "Placement"), "PyramidRuntime"),
        CarryState = Wait(Wait(Shared, "Books"), "CarryState"),
        Regions = Wait(Shared, "RegionRegistry"),
        Knit = Wait(Wait(ReplicatedStorage, "Packages"), "Knit"),
        Progression = Wait(Wait(Shared, "Stats"), "StatProgression"),
    }
    for key, module in pairs(modules) do
        GameLib[key] = GameLib.Require(module)
    end
end

GameLib.Pickup = Remote("BookService", "RF", "Pickup")
GameLib.Place = Remote("PyramidService", "RF", "Place")
GameLib.Purchase = Remote("DataService", "RF", "PurchaseUpgrade")
GameLib.StartBench = Remote("GymService", "RF", "StartBench")
GameLib.StopBench = Remote("GymService", "RF", "StopBench")
GameLib.Redeem = Remote("CodesService", "RF", "Redeem")
GameLib.Activity = Remote("AFKService", "RE", "Activity")
GameLib.SpendBlocks = Remote("PyramidService", "RF", "SpendBankedBlocks")
GameLib.SpendSeconds = Remote("PyramidService", "RF", "SpendBankedSeconds")
GameLib.GiftClaim = Remote("FreeGiftService", "RF", "Claim")
GameLib.GiftStep = Remote("FreeGiftService", "RF", "MarkStep")

xDTaraZ.UpgradeByName = {}
xDTaraZ.UpgradeNames = {}
do
    for _, upgrade in ipairs(GameLib.Upgrades and GameLib.Upgrades.Upgrades or {}) do
        xDTaraZ.UpgradeByName[upgrade.DisplayName] = upgrade
        table.insert(xDTaraZ.UpgradeNames, upgrade.DisplayName)
    end
end

xDTaraZ.CodeList = {}
do
    local seen = {}
    local function Add(code)
        if seen[code] then return end
        seen[code] = true
        xDTaraZ.CodeList[#xDTaraZ.CodeList + 1] = code
    end
    for code in pairs(GameLib.Codes and GameLib.Codes.Codes or {}) do Add(code) end
    for _, code in ipairs(Config.ExtraCodes) do Add(code) end
end

xDTaraZ.Gate = {
    Needs = {
        AutoFarm = { "Pyramid", "Carry", "CarryState", "Runtime", "Regions", "Upgrades", "Pickup", "Place" },
        AutoStrength = { "Gym", "GymAccess", "StartBench", "StopBench" },
        AutoSpeed = { "Gym", "GymAccess" },
        AutoPool = { "Pyramid", "Completion" },
        AutoUpgrade = { "Upgrades", "Purchase", "Knit" },
    },
}

---@return string?  first game module or remote the option needs that was not found
function xDTaraZ.Gate.Missing(idx)
    for _, key in ipairs(xDTaraZ.Gate.Needs[idx] or {}) do
        if GameLib[key] == nil then return key end
    end
    return nil
end

function xDTaraZ.Gate.Ready(idx)
    return xDTaraZ.Gate.Missing(idx) == nil
end

function xDTaraZ.Format(n)
    n = tonumber(n) or 0
    local units = { "", "K", "M", "B", "T", "Qa", "Qi" }
    local i = 1
    while math.abs(n) >= 1000 and i < #units do
        n /= 1000
        i += 1
    end
    return (i == 1 and "%d%s" or "%.2f%s"):format(n, units[i])
end

function xDTaraZ:Notify(msg)
    table.insert(self.State.Messages, msg)
end

function xDTaraZ:Character()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not (hum and hrp and hum.Health > 0) then return nil end
    return char, hum, hrp
end

function xDTaraZ:Invoke(remote, ...)
    if not remote then return false, "missing remote" end
    local packed = table.pack(pcall(remote.InvokeServer, remote, ...))
    if not packed[1] then
        warn("[BuildThePyramid]", remote.Name, packed[2])
        return false, packed[2]
    end
    return table.unpack(packed, 2, packed.n)
end

xDTaraZ.Game = {}

function xDTaraZ.Game.Attr(name)
    return LocalPlayer:GetAttribute(name)
end

function xDTaraZ.Game.UpgradeLevel(upgrade)
    return tonumber(LocalPlayer:GetAttribute(GameLib.Upgrades.AttributePrefix .. upgrade.Attribute)) or 0
end

function xDTaraZ.Game.Capacity()
    local base = GameLib.Carry and tonumber(GameLib.Carry.Capacity) or 0
    return base + (tonumber(xDTaraZ.Game.Attr("StrengthLevel")) or 0)
end

function xDTaraZ.Game.Carried()
    if State.Carry then return State.Carry end
    if GameLib.CarryState then
        local ok, state = pcall(GameLib.CarryState.read, LocalPlayer)
        local count = ok and type(state) == "table" and tonumber(state.count)
        if count then return count end
    end
    return tonumber(xDTaraZ.Game.Attr("CarriedCount")) or 0
end

function xDTaraZ.Game.Coins()
    return tonumber(State.Stats.Coins) or 0
end

function xDTaraZ.Game.Benching()
    if not GameLib.Gym then return nil end
    local station = xDTaraZ.Game.Attr(GameLib.Gym.BenchStationAttribute)
    return type(station) == "string" and station ~= "" and station or nil
end

function xDTaraZ.Game.Model()
    return Workspace:FindFirstChild(GameLib.Pyramid.ModelName)
end

---@return boolean  completion window running (pool is open)
function xDTaraZ.Game.Completed()
    local model = xDTaraZ.Game.Model()
    if not model then return false end
    if model:GetAttribute(GameLib.Pyramid.CompleteAttribute) == true then return true end
    local endsAt = tonumber(model:GetAttribute(GameLib.Completion.CompletionEndsAtAttribute)) or 0
    return endsAt > Workspace:GetServerTimeNow()
end

---@param carryState any  "revision:count:..." string from a Pickup/Place reply
---@return number?         blocks held, nil when the reply carries no state
function xDTaraZ.Game.ReadCarry(carryState)
    if type(carryState) ~= "string" then return nil end
    local ok, decoded = pcall(GameLib.CarryState.decode, carryState)
    return ok and type(decoded) == "table" and tonumber(decoded.count) or nil
end

function xDTaraZ.Game.WatchStats()
    local ok, err = pcall(function()
        GameLib.Knit.OnStart():await()
        local prop = GameLib.Knit.GetService("DataService").StatValues
        local conn = prop:Observe(function(values)
            if type(values) ~= "table" then return end
            local before = tonumber(State.Stats.Coins)
            local now = tonumber(values.Coins)
            if before and now and now > before then table.insert(State.CoinLog, { osClock(), now - before }) end
            State.Stats = values
        end)
        table.insert(State.Connections, conn)
    end)
    if not ok then warn("[BuildThePyramid] stats:", err) end
end

xDTaraZ.Move = {}

---@param pos Vector3  streams the area in the background, gives up after Config.StreamWait
function xDTaraZ.Move.Stream(pos)
    local finished = false
    task.spawn(function()
        pcall(LocalPlayer.RequestStreamAroundAsync, LocalPlayer, pos, Config.StreamWait)
        finished = true
    end)
    local deadline = osClock() + Config.StreamWait
    while not finished and osClock() < deadline do task.wait() end
end

---Holds the camera script off for two frames so a long jump does not make the game's held-item shield query an out-of-range radius.
function xDTaraZ.Move.FreezeCamera()
    local camera = Workspace.CurrentCamera
    if not camera or camera.CameraType ~= Enum.CameraType.Custom then return end
    camera.CameraType = Enum.CameraType.Scriptable
    task.spawn(function()
        RunService.RenderStepped:Wait()
        RunService.RenderStepped:Wait()
        if camera.CameraType == Enum.CameraType.Scriptable then camera.CameraType = Enum.CameraType.Custom end
    end)
end

---@param stream boolean?  ask the engine to load the destination first (far targets only)
function xDTaraZ.Move.To(pos, stream)
    local _, _, hrp = xDTaraZ:Character()
    if not hrp then return false end
    if stream and (hrp.Position - pos).Magnitude > Config.StreamDistance then xDTaraZ.Move.Stream(pos) end
    hrp.AssemblyLinearVelocity = Vector3.zero
    local freezeCamera = (hrp.Position - pos).Magnitude > Config.CameraShieldJump
    if freezeCamera then xDTaraZ.Move.FreezeCamera() end
    hrp.CFrame = CFrame.new(pos) * hrp.CFrame.Rotation
    return true
end

function xDTaraZ.Move.Near(pos, radius)
    local _, _, hrp = xDTaraZ:Character()
    return hrp ~= nil and (hrp.Position - pos).Magnitude <= (radius or Config.StandRadius)
end

---@param jitter boolean?  pick a random spot inside the region instead of its centre
function xDTaraZ.Move.QuarrySpot(jitter)
    local region = GameLib.Regions.getPart("Quarry")
    if not (region and region:IsA("BasePart")) then return Config.QuarrySpot end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LocalPlayer.Character, region, Workspace:FindFirstChild(GameLib.Pyramid.QuarryFolderName) }

    local top = region.Position + vector3New(0, region.Size.Y / 2, 0)
    if jitter then
        local spread = Config.QuarryJitter
        top += region.CFrame:VectorToWorldSpace(vector3New(
            (math.random() * 2 - 1) * region.Size.X * spread, 0, (math.random() * 2 - 1) * region.Size.Z * spread))
    end
    local hit = Workspace:Raycast(top, vector3New(0, -region.Size.Y - 50, 0), params)
    local spot = hit and hit.Position + vector3New(0, Config.StandHeight, 0)
    if spot and GameLib.Regions.isWithin("Quarry", spot) then return spot end
    return Config.QuarrySpot
end

function xDTaraZ.Move.GymPart(folder, model, part)
    local gym = Workspace:FindFirstChild(GameLib.Gym.GymFolderName)
    local station = gym and gym:FindFirstChild(folder)
    local machine = station and station:FindFirstChild(model)
    local found = machine and machine:FindFirstChild(part)
    return found and found:IsA("BasePart") and found or nil
end

function xDTaraZ.Move.PoolSpot()
    local display = Workspace:FindFirstChild(GameLib.Completion.CompletedDisplayName)
    local hitbox = display and display:FindFirstChild(GameLib.Completion.PoolHitboxName)
    return hitbox and hitbox:IsA("BasePart") and hitbox.Position or nil
end

function xDTaraZ.Move.Frame()
    local char, hum, hrp = xDTaraZ:Character()
    if not char then return end
    if State.Opt.SpeedOn and not State.Opt.Fly and hum.MoveDirection.Magnitude > 0 then
        local velocity = hrp.AssemblyLinearVelocity
        local speed = math.max(State.Opt.WalkSpeed, hum.WalkSpeed)
        hrp.AssemblyLinearVelocity = vector3New(hum.MoveDirection.X * speed, velocity.Y, hum.MoveDirection.Z * speed)
    end
    if State.Opt.Noclip then
        for _, part in ipairs(char:GetChildren()) do
            if part:IsA("BasePart") and part.CanCollide then
                State.Collided[part] = true
                part.CanCollide = false
            end
        end
    end
    if not State.Opt.Fly then return end
    local cam = Workspace.CurrentCamera
    local dir = hum.MoveDirection
    local lift = cam and dir.Magnitude > 0 and cam.CFrame.LookVector.Y * dir.Magnitude or 0
    hum.PlatformStand = true
    hrp.AssemblyLinearVelocity = (dir + vector3New(0, lift, 0)) * State.Opt.FlySpeed
end

function xDTaraZ.Move.Refresh()
    local opt = State.Opt
    local want = opt.Fly or opt.Noclip or opt.SpeedOn
    if want and #State.MoveConns == 0 then
        State.Collided = State.Collided or {}
        table.insert(State.MoveConns, RunService.Stepped:Connect(xDTaraZ.Move.Frame))
    elseif not want then
        for _, conn in ipairs(State.MoveConns) do conn:Disconnect() end
        table.clear(State.MoveConns)
    end
    if not opt.Noclip and State.Collided then
        for part in pairs(State.Collided) do
            if part.Parent then part.CanCollide = true end
        end
        table.clear(State.Collided)
    end
    local _, hum = xDTaraZ:Character()
    if hum and not opt.Fly and hum.PlatformStand then hum.PlatformStand = false end
end

xDTaraZ.Farm = {}

function xDTaraZ.Farm.Progress()
    State.StallSince, State.Backoff = nil, nil
end

---@param reason string  shown while the farm waits; raised once the stall passes Config.StallLimit
---@return boolean       always false, so lower jobs get the character meanwhile
function xDTaraZ.Farm.Hold(reason)
    local now = osClock()
    State.StallSince = State.StallSince or now
    if now - State.StallSince > Config.StallLimit then
        State.Waiting = nil
        error(reason:lower() .. " for " .. Config.StallLimit .. "s", 0)
    end
    State.Backoff = State.Backoff and math.min(State.Backoff * 2, Config.RetryMax) or Config.RetryDelay
    State.FarmWait = now + State.Backoff
    State.Waiting = reason .. ", retrying"
    return false
end

---@return boolean  the server had you flagged AFK and was told you are back
function xDTaraZ.Farm.Wake()
    if xDTaraZ.Game.Attr("IsAFK") ~= true or not GameLib.Activity then return false end
    GameLib.Activity:FireServer()
    return true
end

function xDTaraZ.Farm.Park()
    if State.Parked then return end
    State.Parked = true
    xDTaraZ.Move.To(xDTaraZ.Move.QuarrySpot())
end

---@param calls number  pickups fired in the same frame; the server stops granting at capacity
---@return number       blocks carried after the batch
function xDTaraZ.Farm.GrabAll(region, calls)
    local pending, carried, granted = calls, xDTaraZ.Game.Carried(), false
    for _ = 1, calls do
        task.spawn(function()
            local ok, carryState = xDTaraZ:Invoke(GameLib.Pickup, region)
            if ok == true then
                granted = true
                carried = math.max(carried, xDTaraZ.Game.ReadCarry(carryState) or 0)
            end
            pending -= 1
        end)
    end
    local deadline = osClock() + Config.PickupTimeout
    while pending > 0 and osClock() < deadline do task.wait() end
    if granted then
        State.Carry = carried
        xDTaraZ.Farm.Progress()
    end
    return carried
end

---@return boolean, string?  holding at least one block, else why not
function xDTaraZ.Farm.Gather()
    if xDTaraZ.Game.Benching() then xDTaraZ:Invoke(GameLib.StopBench) end
    local cap = xDTaraZ.Game.Capacity()
    if xDTaraZ.Game.Carried() >= cap then return true end

    State.Status = "Picking up blocks"
    if not xDTaraZ.Move.To(xDTaraZ.Move.QuarrySpot(State.Backoff ~= nil)) then return false, "Character not ready" end
    task.wait(Config.SettleDelay)

    local region = GameLib.Regions.getPart("Quarry")
    local grant = 1 + xDTaraZ.Game.UpgradeLevel(GameLib.Upgrades.ById.bulkPickup)
    local carried = xDTaraZ.Farm.GrabAll(region, math.ceil((cap - xDTaraZ.Game.Carried()) / grant) + Config.PickupRetries)
    if carried > 0 then return true end

    State.Carry = nil
    if xDTaraZ.Game.Carried() > 0 then return true end
    if xDTaraZ.Farm.Wake() then return false, "Marked AFK, waking up" end
    return false, "Quarry refused blocks"
end

---@return table?  geometry of the tier being built, same one the slot resolver uses
function xDTaraZ.Farm.Geometry()
    local context = GameLib.Runtime.getContext(Workspace)
    return context and context.geometry
end

---@param cells number  ring count wanted
---@return number       ring count whose stud radius stays inside the engine's spatial query limit
function xDTaraZ.Farm.ClampCells(cells)
    return math.min(cells, math.floor(Config.EngineRadiusLimit / GameLib.Pyramid.BlockSize))
end

---@return number  rings that reach every cell of the current layer
function xDTaraZ.Farm.SearchCells()
    local geometry = xDTaraZ.Farm.Geometry()
    local layer = GameLib.Runtime.getCurrentLayer(Workspace)
    local side = geometry and layer and geometry.getLayerSide(layer) or Config.SlotSearchCells
    return xDTaraZ.Farm.ClampCells(math.min(side, Config.SlotSearchCells))
end

---@param from Vector3  used until the first block lands
---@return table?        free slot on the current layer, searched from the last placed block
function xDTaraZ.Farm.FirstSlot(from)
    return GameLib.Runtime.resolveNearestSlot(State.LastSlot or from, Workspace, nil, xDTaraZ.Farm.SearchCells())
end

---@param origin Vector3  where the character stands
---@param count number     slots wanted
---@return table[]         free slots in reach, far enough apart that bulk fills do not overlap
function xDTaraZ.Farm.Slots(origin, count, radius)
    local picked, cells, rejected = {}, {}, {}
    local geometry = xDTaraZ.Farm.Geometry()
    if not geometry then return picked end
    local function Skip(layer, index)
        if rejected[layer .. ":" .. index] then return true end
        local col, row = geometry.fromSlotIndex(layer, index)
        if not (col and row) then return false end
        for _, cell in ipairs(cells) do
            if cell.layer == layer and math.max(math.abs(cell.col - col), math.abs(cell.row - row)) < Config.SlotSpacing then
                return true
            end
        end
        return false
    end
    for _ = 1, count * 3 do
        if #picked >= count then break end
        local slot = GameLib.Runtime.resolveNearestSlot(origin, Workspace, Skip, xDTaraZ.Farm.ClampCells(radius))
        if not slot then break end
        local flat = vector3New(slot.position.X - origin.X, 0, slot.position.Z - origin.Z)
        local col, row = geometry.fromSlotIndex(slot.layer, slot.slotIndex)
        if col and row and flat.Magnitude <= State.Opt.PlaceReach then
            table.insert(cells, { layer = slot.layer, col = col, row = row })
            table.insert(picked, slot)
        else
            rejected[slot.layer .. ":" .. slot.slotIndex] = true
        end
    end
    return picked
end

---@return number  blocks still carried
function xDTaraZ.Farm.PlaceBatch(slots)
    local pending, left, known = #slots, xDTaraZ.Game.Carried(), false
    for _, slot in ipairs(slots) do
        task.spawn(function()
            local ok, carryState = xDTaraZ:Invoke(GameLib.Place, slot.layer, slot.slotIndex, slot.generation)
            if ok == true then
                State.Placed += 1
                State.LastSlot = slot.position
            end
            local count = xDTaraZ.Game.ReadCarry(carryState)
            if count then left, known = math.min(left, count), true end
            pending -= 1
        end)
    end

    local deadline = osClock() + Config.PlaceTimeout
    while pending > 0 and osClock() < deadline do task.wait() end
    State.Carry = known and left or nil
    return xDTaraZ.Game.Carried()
end

---@return boolean, string?  placed at least one block (or nothing left to place), else why not
function xDTaraZ.Farm.Deliver()
    local _, _, hrp = xDTaraZ:Character()
    if not hrp then return false, "Character not ready" end
    local perPlace = 1 + xDTaraZ.Game.UpgradeLevel(GameLib.Upgrades.ById.bulkPlace)
    local before, why = State.Placed, "Pyramid refused blocks"

    for _ = 1, Config.PlaceRetries do
        local carried = xDTaraZ.Game.Carried()
        if carried <= 0 or not State.Opt.AutoFarm then return true end
        local first = xDTaraZ.Farm.FirstSlot(hrp.Position)
        if not first then
            why = "No free slot on the pyramid"
            break
        end

        State.Status = ("Placing on layer %d"):format(first.layer)
        local stand = first.position + vector3New(0, Config.HoverHeight, 0)
        xDTaraZ.Move.To(stand)
        local arrived = osClock()

        local reach = math.ceil(State.Opt.PlaceReach / GameLib.Pyramid.BlockSize)
        local slots = xDTaraZ.Farm.Slots(stand, math.ceil(carried / perPlace), reach)
        local remaining = Config.SettleDelay - (osClock() - arrived)
        if remaining > 0 then task.wait(remaining) end
        if #slots == 0 then
            why = "No free slot on the pyramid"
            break
        end
        if xDTaraZ.Farm.PlaceBatch(slots) <= 0 then break end
    end

    if State.Placed == before then return false, why end
    xDTaraZ.Farm.Progress()
    return true
end

---@return boolean  did work this tick
function xDTaraZ.Farm.Step()
    if osClock() < State.FarmWait then return false end
    if not GameLib.Runtime.getCurrentLayer(Workspace) then
        xDTaraZ.Farm.Progress()
        State.Waiting = "Waiting for the next pyramid"
        xDTaraZ.Farm.Park()
        return false
    end

    State.Waiting, State.Parked = nil, false
    if not State.FarmOrigin then
        local _, _, hrp = xDTaraZ:Character()
        State.FarmOrigin = hrp and hrp.CFrame
    end
    local holding, why = xDTaraZ.Farm.Gather()
    if not holding then return xDTaraZ.Farm.Hold(why) end

    local placed, reason = xDTaraZ.Farm.Deliver()
    if placed then return true end
    return xDTaraZ.Farm.Hold(reason)
end

function xDTaraZ.Farm.Stop()
    local origin = State.FarmOrigin
    State.FarmOrigin, State.Waiting, State.Parked, State.FarmWait = nil, nil, false, 0
    xDTaraZ.Farm.Progress()
    if not (origin and State.Opt.ReturnOnStop) then return end
    local _, _, hrp = xDTaraZ:Character()
    if hrp then hrp.CFrame = origin end
end

xDTaraZ.Train = {}

function xDTaraZ.Train.HasAccess(folder)
    local access = GameLib.Gym.Access[folder]
    if not access then return false end
    local owned = GameLib.GymAccess.purchasedFromAttribute(xDTaraZ.Game.Attr(GameLib.Gym.GymUnlocksAttribute), folder)
        or GameLib.GymAccess.ownsGamePass(LocalPlayer, access.ProductKey)
    local done = tonumber(xDTaraZ.Game.Attr("Pyramids")) or 0
    return GameLib.GymAccess.hasAccess(access, done, owned)
end

---@param stations table  GymConfig station list
---@return string?        gym folder with the highest multiplier you can use
function xDTaraZ.Train.Best(stations, key)
    local best, bestMult
    for _, station in ipairs(stations) do
        if xDTaraZ.Train.HasAccess(station.GymFolder) and (not bestMult or station[key] > bestMult) then
            best, bestMult = station.GymFolder, station[key]
        end
    end
    return best, bestMult
end

---@param chosen string  dropdown value, "Best Unlocked" or a gym folder
---@return string?       the chosen gym when you can use it, else the best one you can
function xDTaraZ.Train.Pick(stations, key, chosen)
    for _, station in ipairs(stations) do
        if station.GymFolder == chosen and xDTaraZ.Train.HasAccess(station.GymFolder) then
            return station.GymFolder, station[key]
        end
    end
    return xDTaraZ.Train.Best(stations, key)
end

---@param value number  current Strength value
---@return number       value that reaches the next Strength level
function xDTaraZ.Train.NextLevelValue(value)
    local progression = GameLib.Progression
    local base = progression.levelForValue(value)
    local low, high = value, math.max(value * 2, value + Config.LevelProbe)
    while high - low > 1 do
        local mid = math.floor((low + high) / 2)
        if progression.levelForValue(mid) > base then high = mid else low = mid end
    end
    return high
end

---@return number?  Strength per second gained on the bench so far, nil until it has run long enough
function xDTaraZ.Train.MeasuredRate(value, now)
    if not xDTaraZ.Game.Benching() then
        State.BenchRef = nil
        return State.BenchRate
    end
    local ref = State.BenchRef
    if not ref then
        State.BenchRef = { at = now, value = value }
        return State.BenchRate
    end
    if now - ref.at >= Config.RateSample and value > ref.value then
        State.BenchRate = (value - ref.value) / (now - ref.at)
        State.BenchRef = { at = now, value = value }
    end
    return State.BenchRate
end

---@return boolean  the next Strength level pays back its training time inside the payback time
function xDTaraZ.Train.Worth()
    local now = osClock()
    local cached = State.SmartCache
    if cached and now - cached.at < Config.SmartRefresh then return cached.worth end

    local worth = false
    local value = tonumber(State.Stats.Strength)
    local _, mult = xDTaraZ.Train.Pick(GameLib.Gym.BenchpressStations, "StrengthMultiplier", State.Opt.BenchStation)
    if GameLib.Progression and value and mult then
        local rate = xDTaraZ.Train.MeasuredRate(value, now) or Config.BenchBase * mult
        local seconds = (xDTaraZ.Train.NextLevelValue(value) - value) / rate
        worth = seconds * xDTaraZ.Game.Capacity() < State.Opt.SmartMinutes * 60
    end
    State.SmartCache = { at = now, worth = worth }
    return worth
end

function xDTaraZ.Train.Strength()
    local folder, mult = xDTaraZ.Train.Pick(GameLib.Gym.BenchpressStations, "StrengthMultiplier", State.Opt.BenchStation)
    if not folder then return false end
    State.Status = ("Bench press x%d"):format(mult)
    local current = xDTaraZ.Game.Benching()
    if current == folder then return true end
    if current then xDTaraZ:Invoke(GameLib.StopBench) end

    if osClock() - (State.Last.BenchTry or 0) < Config.BenchRetry then return true end
    State.Last.BenchTry = osClock()

    local seat = xDTaraZ.Move.GymPart(folder, GameLib.Gym.BenchpressModelName, GameLib.Gym.AlignPartName)
    if not seat then return false end
    if not xDTaraZ.Move.Near(seat.Position, Config.BenchRange) then
        xDTaraZ.Move.To(seat.Position + vector3New(0, Config.StandHeight, 0))
        task.wait(Config.SettleDelay)
    end
    local ok = xDTaraZ:Invoke(GameLib.StartBench, folder)
    if not ok then State.Status = "Bench refused, retrying" end
    return true
end

function xDTaraZ.Train.Speed()
    local folder, mult = xDTaraZ.Train.Pick(GameLib.Gym.TreadmillStations, "SpeedMultiplier", State.Opt.TreadmillStation)
    local hitbox = folder and xDTaraZ.Move.GymPart(folder, GameLib.Gym.TreadmillModelName, GameLib.Gym.HitboxName)
    if not hitbox then return false end
    if xDTaraZ.Game.Benching() then xDTaraZ:Invoke(GameLib.StopBench) end
    State.Status = ("Treadmill x%d"):format(mult)
    if not xDTaraZ.Move.Near(hitbox.Position) then xDTaraZ.Move.To(hitbox.Position) end
    return true
end

function xDTaraZ.Train.Step()
    local opt = State.Opt
    if opt.Priority == "Balanced" and opt.AutoStrength then return xDTaraZ.Train.Strength() end
    if opt.AutoStrength and opt.AutoSpeed then
        local str = tonumber(xDTaraZ.Game.Attr("StrengthLevel")) or 0
        local spd = tonumber(xDTaraZ.Game.Attr("SpeedLevel")) or 0
        if spd < str then return xDTaraZ.Train.Speed() end
        return xDTaraZ.Train.Strength()
    end
    if opt.AutoStrength then return xDTaraZ.Train.Strength() end
    if opt.AutoSpeed then return xDTaraZ.Train.Speed() end
    return false
end

function xDTaraZ.Train.Leave()
    if xDTaraZ.Game.Benching() then xDTaraZ:Invoke(GameLib.StopBench) end
end

function xDTaraZ.Train.Pool()
    if not xDTaraZ.Game.Completed() then return false end
    local spot = xDTaraZ.Move.PoolSpot()
    if not spot then return false end
    if xDTaraZ.Game.Benching() then xDTaraZ:Invoke(GameLib.StopBench) end
    State.Status = "Training in the pool"
    if not xDTaraZ.Move.Near(spot) then xDTaraZ.Move.To(spot) end
    return true
end

xDTaraZ.Tasks = {}

function xDTaraZ.Tasks.Order()
    local opt = State.Opt
    local order = {}
    if opt.AutoPool then table.insert(order, "Pool") end
    local trainFirst = opt.Priority == "Train"
    if opt.Priority == "Balanced" then trainFirst = opt.AutoStrength and xDTaraZ.Train.Worth() end
    if opt.Priority == "Alternate" then
        local slice = math.floor(osClock() / (opt.AlternateMinutes * 60))
        trainFirst = slice % 2 == 1
    end
    if trainFirst then
        order[#order + 1] = "Train"
        order[#order + 1] = "Farm"
    else
        order[#order + 1] = "Farm"
        order[#order + 1] = "Train"
    end
    return order
end

xDTaraZ.Tasks.Jobs = {
    Pool = { On = function() return State.Opt.AutoPool end, Step = xDTaraZ.Train.Pool },
    Farm = { On = function() return State.Opt.AutoFarm end, Step = xDTaraZ.Farm.Step },
    Train = { On = function() return State.Opt.AutoStrength or State.Opt.AutoSpeed end, Step = xDTaraZ.Train.Step },
}

function xDTaraZ.Tasks.Step()
    for _, name in ipairs(xDTaraZ.Tasks.Order()) do
        local job = xDTaraZ.Tasks.Jobs[name]
        if not job.On() or State.Halted[name] then continue end
        local ok, worked = pcall(job.Step)
        if not ok then
            xDTaraZ.Scheduler.Fail(name, worked)
            return
        end
        State.Fails[name], State.FailSince[name] = nil, nil
        if worked then
            State.Task = name
            return
        end
    end
    State.Task = "None"
    State.Status = State.Opt.AutoFarm and State.Waiting or "Idle"
end

xDTaraZ.Upgrade = {}

---@param budget number  coins free to spend
---@return table?, number?, boolean?  best upgrade you can afford, its cost, true when waiting for a better one is faster
function xDTaraZ.Upgrade.PickByValue(budget)
    local income = State.CoinRate or 0
    for _, id in ipairs(Config.UpgradePriority) do
        for _, upgrade in pairs(xDTaraZ.UpgradeByName) do
            if upgrade.Id ~= id or not State.Opt.Upgrades[upgrade.DisplayName] then continue end
            local cost = upgrade.Costs[xDTaraZ.Game.UpgradeLevel(upgrade) + 1]
            if not cost then continue end
            if cost <= budget then return upgrade, cost end
            if income > 0 and (cost - budget) / income <= Config.SaveSeconds then return nil, nil, true end
        end
    end
    return nil
end

---@return table?, number?  wanted upgrade to buy next by the chosen order, and its cost
function xDTaraZ.Upgrade.Pick()
    local budget = xDTaraZ.Game.Coins() - State.Opt.KeepCoins
    if State.Opt.UpgradeOrder == "Best Value" then
        local upgrade, cost, saving = xDTaraZ.Upgrade.PickByValue(budget)
        if upgrade or saving then return upgrade, cost end
    end
    local pick, pickCost
    for _, name in ipairs(xDTaraZ.UpgradeNames) do
        local upgrade = xDTaraZ.UpgradeByName[name]
        if not State.Opt.Upgrades[name] then continue end
        local cost = upgrade.Costs[xDTaraZ.Game.UpgradeLevel(upgrade) + 1]
        if not cost or cost > budget then continue end
        if State.Opt.UpgradeOrder == "In Order" then return upgrade, cost end
        if not pickCost or cost < pickCost then pick, pickCost = upgrade, cost end
    end
    return pick, pickCost
end

function xDTaraZ.Upgrade.Buy(upgrade, cost)
    local level = xDTaraZ.Game.UpgradeLevel(upgrade) + 1
    local reply = xDTaraZ:Invoke(GameLib.Purchase, upgrade.Id)
    if not (type(reply) == "table" and reply.ok == true) then return false end
    xDTaraZ:Notify(("Bought %s %d"):format(upgrade.DisplayName, level))
    local coins = tonumber(State.Stats.Coins)
    if coins then State.Stats.Coins = tostring(coins - cost) end
    return true
end

function xDTaraZ.Upgrade.Step()
    local upgrade, cost = xDTaraZ.Upgrade.Pick()
    if upgrade then xDTaraZ.Upgrade.Buy(upgrade, cost) end
end

function xDTaraZ.Upgrade.Now()
    local bought = 0
    repeat
        local upgrade, cost = xDTaraZ.Upgrade.Pick()
        if not (upgrade and xDTaraZ.Upgrade.Buy(upgrade, cost)) then break end
        bought += 1
        task.wait(Config.UpgradeGap)
    until bought >= Config.UpgradeBurst
    if bought == 0 then xDTaraZ:Notify("Nothing to buy") end
end

xDTaraZ.Codes = {}

function xDTaraZ.Codes.RedeemAll()
    local got = 0
    for _, code in ipairs(xDTaraZ.CodeList) do
        local reply = xDTaraZ:Invoke(GameLib.Redeem, code)
        if type(reply) == "table" and reply.ok then
            got += 1
            xDTaraZ:Notify(code .. ": redeemed")
        else
            xDTaraZ:Notify(("%s: %s"):format(code, type(reply) == "table" and tostring(reply.reason) or "no reply"))
        end
        task.wait(Config.CodeGap)
    end
    xDTaraZ:Notify(("Codes done, %d new"):format(got))
end

xDTaraZ.Bank = {}

function xDTaraZ.Bank.Spend()
    local spent = 0
    for _, entry in ipairs({ { GameLib.SpendBlocks, "banked blocks" }, { GameLib.SpendSeconds, "banked time" } }) do
        local ok, reason = xDTaraZ:Invoke(entry[1])
        if ok == true then
            spent += 1
            xDTaraZ:Notify(entry[2] .. " spent")
        elseif reason == "NothingBanked" or reason == "PyramidComplete" then
            xDTaraZ:Notify(("%s: %s"):format(entry[2], reason == "NothingBanked" and "none to spend" or "wait for the next pyramid"))
        end
    end
    return spent
end

function xDTaraZ.Bank.FreeGift()
    for _, step in ipairs({ "liked", "favorited" }) do
        xDTaraZ:Invoke(GameLib.GiftStep, step)
    end
    local reply, reason = xDTaraZ:Invoke(GameLib.GiftClaim)
    if reply == true or (type(reply) == "table" and reply.ok) then
        xDTaraZ:Notify("Free gift claimed")
    else
        local text = type(reply) == "table" and tostring(reply.reason) or tostring(reason)
        xDTaraZ:Notify(text == "GroupRequired" and "Join the Janitors Studios group to claim the free gift" or ("Free gift: " .. text))
    end
end

xDTaraZ.Teleport = {}

function xDTaraZ.Teleport.Quarry()
    xDTaraZ.Move.To(xDTaraZ.Move.QuarrySpot())
end

function xDTaraZ.Teleport.Pyramid()
    local _, _, hrp = xDTaraZ:Character()
    if not hrp then return end
    local slot = xDTaraZ.Farm.FirstSlot(hrp.Position)
    if slot then
        xDTaraZ.Move.To(slot.position + vector3New(0, Config.HoverHeight, 0))
        return
    end
    local model = xDTaraZ.Game.Model()
    if model then xDTaraZ.Move.To(model:GetPivot().Position + vector3New(0, Config.HoverHeight, 0)) end
end

function xDTaraZ.Teleport.Pool()
    local spot = xDTaraZ.Move.PoolSpot()
    if not spot then
        xDTaraZ:Notify(xDTaraZ.Game.Completed() and "Pool is not loaded yet, try again in a moment" or "Pool opens when a pyramid is completed")
        return
    end
    xDTaraZ.Move.To(spot, true)
end

function xDTaraZ.Teleport.Gym()
    local folder = State.GymTarget
    local seat = folder and xDTaraZ.Move.GymPart(folder, GameLib.Gym.BenchpressModelName, GameLib.Gym.AlignPartName)
    local belt = folder and xDTaraZ.Move.GymPart(folder, GameLib.Gym.TreadmillModelName, GameLib.Gym.HitboxName)
    local target = seat or belt
    if target then xDTaraZ.Move.To(target.Position + vector3New(0, Config.StandHeight, 0)) end
end

function xDTaraZ.Teleport.Player()
    local target = State.PlayerTarget and Players:FindFirstChild(State.PlayerTarget)
    local root = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
    if not root then
        xDTaraZ:Notify("Player not found")
        return
    end
    xDTaraZ.Move.To(root.Position + vector3New(0, Config.StandHeight, 0), true)
end

xDTaraZ.Server = {}

function xDTaraZ.Server.Rejoin()
    if #Players:GetPlayers() > 1 then
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
    else
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end
end

function xDTaraZ.Server.Hop()
    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&limit=100"):format(game.PlaceId)
    local body = xDTaraZ.Util.HttpGet(url)
    local ok, page = pcall(HttpService.JSONDecode, HttpService, body or "")
    if not (ok and type(page) == "table" and page.data) then
        xDTaraZ:Notify("Server list unavailable")
        return
    end
    local options = {}
    for _, server in ipairs(page.data) do
        if server.id ~= game.JobId and (server.playing or 0) < (server.maxPlayers or 0) then
            table.insert(options, server.id)
        end
    end
    if #options == 0 then
        xDTaraZ:Notify("No other server found")
        return
    end
    TeleportService:TeleportToPlaceInstance(game.PlaceId, options[math.random(#options)], LocalPlayer)
end

function xDTaraZ.Server.Boost()
    local saved = State.Boosted
    if not saved then
        saved = { Shadows = Lighting.GlobalShadows, FogEnd = Lighting.FogEnd, Effects = {}, Materials = {} }
        State.Boosted = saved
    end
    Lighting.GlobalShadows = false
    Lighting.FogEnd = 1e6

    local plastic, smooth = Enum.Material.Plastic, Enum.Material.SmoothPlastic
    for _, inst in ipairs(Workspace:GetDescendants()) do
        if inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Smoke") or inst:IsA("Fire") then
            if not inst.Enabled then continue end
            saved.Effects[inst] = true
            inst.Enabled = false
        elseif inst:IsA("BasePart") and inst.Material ~= plastic and inst.Material ~= smooth then
            saved.Materials[inst] = inst.Material
            inst.Material = smooth
        end
    end
    xDTaraZ:Notify("FPS boost applied")
end

function xDTaraZ.Server.Unboost()
    local saved = State.Boosted
    if not saved then return end
    State.Boosted = nil
    Lighting.GlobalShadows, Lighting.FogEnd = saved.Shadows, saved.FogEnd
    for inst in pairs(saved.Effects) do
        if inst.Parent then inst.Enabled = true end
    end
    for part, material in pairs(saved.Materials) do
        if part.Parent then part.Material = material end
    end
end

xDTaraZ.Client = {}

function xDTaraZ.Client.Bind()
    table.insert(State.Connections, LocalPlayer.Idled:Connect(function()
        if not State.Opt.AntiAfk then return end
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.zero)
    end))

    table.insert(State.Connections, UserInputService.JumpRequest:Connect(function()
        if not State.Opt.InfJump then return end
        local _, hum = xDTaraZ:Character()
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end))

    table.insert(State.Connections, LocalPlayer.CharacterAdded:Connect(function(char)
        char:WaitForChild("Humanoid", Config.LoadTimeout)
        if State.Collided then table.clear(State.Collided) end
    end))

    table.insert(State.Connections, GuiService.ErrorMessageChanged:Connect(function()
        if not State.Opt.AutoRejoin or State.Rejoining or GuiService:GetErrorMessage() == "" then return end
        State.Rejoining = true
        if not xDTaraZ.Util.QueueReload() then warn("[BuildThePyramid] auto rejoin: this executor cannot reload the hub after teleport") end
        task.wait(Config.RejoinDelay)
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end))
end

xDTaraZ.Scheduler = {}

xDTaraZ.Scheduler.RequestHandlers = {
    Movement = xDTaraZ.Move.Refresh,
    FarmStop = xDTaraZ.Farm.Stop,
    TrainStop = xDTaraZ.Train.Leave,
    UpgradeNow = xDTaraZ.Upgrade.Now,
    CodesNow = xDTaraZ.Codes.RedeemAll,
    BankNow = xDTaraZ.Bank.Spend,
    GiftNow = xDTaraZ.Bank.FreeGift,
    TpQuarry = xDTaraZ.Teleport.Quarry,
    TpPyramid = xDTaraZ.Teleport.Pyramid,
    TpPool = xDTaraZ.Teleport.Pool,
    TpGym = xDTaraZ.Teleport.Gym,
    TpPlayer = xDTaraZ.Teleport.Player,
    Rejoin = xDTaraZ.Server.Rejoin,
    Hop = xDTaraZ.Server.Hop,
    Boost = xDTaraZ.Server.Boost,
}

xDTaraZ.Scheduler.Toggles = {
    Farm = { "AutoFarm" },
    Train = { "AutoStrength", "AutoSpeed" },
    Pool = { "AutoPool" },
    Upgrade = { "AutoUpgrade" },
    Activity = { "AntiAfk" },
    Summary = {},
}

---@param key string?  job name; repeated failures stop it and switch its toggles off
function xDTaraZ.Scheduler.Run(fn, key)
    if key and State.Halted[key] then return end
    local ok, err = pcall(fn)
    if ok then
        if key then State.Fails[key], State.FailSince[key] = nil, nil end
        return
    end
    if key then
        xDTaraZ.Scheduler.Fail(key, err)
    else
        warn("[BuildThePyramid]", err)
    end
end

---@return boolean  one of the job's toggles is on; core jobs have none
function xDTaraZ.Scheduler.Wanted(key)
    for _, idx in ipairs(xDTaraZ.Scheduler.Toggles[key] or {}) do
        if State.Opt[idx] == true then return true end
    end
    return false
end

function xDTaraZ.Scheduler.Fail(key, err)
    local fails = (State.Fails[key] or 0) + 1
    State.Fails[key] = fails
    State.FailSince[key] = State.FailSince[key] or osClock()
    if fails == 1 then warn("[BuildThePyramid] " .. key .. " failing:", err) end

    if fails < Config.FailLimit or osClock() - State.FailSince[key] < Config.FailWindow then return end
    if not xDTaraZ.Scheduler.Wanted(key) then return end
    State.Halted[key] = true
    for _, idx in ipairs(xDTaraZ.Scheduler.Toggles[key] or {}) do State.Opt[idx] = false end
    table.insert(State.HaltQueue, { key, tostring(err):match("^[^\n]*") })
end

function xDTaraZ.Scheduler.Resume(idx)
    for key, toggles in pairs(xDTaraZ.Scheduler.Toggles) do
        if table.find(toggles, idx) then
            State.Halted[key], State.Fails[key], State.FailSince[key] = nil, nil, nil
        end
    end
end

function xDTaraZ.Scheduler.RunOnce(name, fn)
    if State.Running[name] then return end
    State.Running[name] = true
    task.spawn(function()
        xDTaraZ.Scheduler.Run(fn)
        State.Running[name] = nil
    end)
end

function xDTaraZ.Scheduler.Every(key, interval, fn)
    if osClock() - (State.Last[key] or 0) < interval then return end
    State.Last[key] = osClock()
    xDTaraZ.Scheduler.Run(fn, key)
end

function xDTaraZ.Scheduler.Summarize()
    local cutoff = osClock() - Config.RateWindow
    local recent = 0
    for i = #State.CoinLog, 1, -1 do
        local entry = State.CoinLog[i]
        if entry[1] < cutoff then table.remove(State.CoinLog, i) else recent += entry[2] end
    end
    State.CoinRate = recent / Config.RateWindow
    local carried, cap = xDTaraZ.Game.Carried(), xDTaraZ.Game.Capacity()
    State.Summary = ("Coins %s · %s/min\nStrength Lv %s · Speed Lv %s · Carry %d/%d\nPyramids %s · Placed %d"):format(
        xDTaraZ.Format(State.Stats.Coins), xDTaraZ.Format(recent * 60 / Config.RateWindow),
        tostring(xDTaraZ.Game.Attr("StrengthLevel") or 0), tostring(xDTaraZ.Game.Attr("SpeedLevel") or 0),
        carried, cap, tostring(xDTaraZ.Game.Attr("Pyramids") or 0), State.Placed)
end

function xDTaraZ.Scheduler.Step()
    local opt = State.Opt
    xDTaraZ.Scheduler.Run(xDTaraZ.Scheduler.Summarize, "Summary")

    for name, handler in pairs(xDTaraZ.Scheduler.RequestHandlers) do
        if State.Requests[name] then
            State.Requests[name] = nil
            if Config.SlowRequests[name] then
                xDTaraZ.Scheduler.RunOnce(name, handler)
            else
                xDTaraZ.Scheduler.Run(handler)
            end
        end
    end

    if opt.AntiAfk and GameLib.Activity then
        xDTaraZ.Scheduler.Every("Activity", Config.ActivityInterval, function() GameLib.Activity:FireServer() end)
    end
    if opt.AutoUpgrade then xDTaraZ.Scheduler.Every("Upgrade", Config.UpgradeInterval, xDTaraZ.Upgrade.Step) end

    local _, hum = xDTaraZ:Character()
    if not hum then return end
    xDTaraZ.Scheduler.Run(xDTaraZ.Tasks.Step)
end

function xDTaraZ.Scheduler.Boot()
    xDTaraZ.Client.Bind()
    task.defer(function()
        xDTaraZ.Game.WatchStats()
        while State.Alive do
            xDTaraZ.Scheduler.Step()
            task.wait(Config.TickDelay)
        end
    end)
end

function xDTaraZ.Scheduler.Stop()
    State.Alive = false
    for _, conn in ipairs(State.Connections) do conn:Disconnect() end
    table.clear(State.Connections)
    local opt = State.Opt
    opt.SpeedOn, opt.Fly, opt.Noclip = false, false, false
    xDTaraZ.Move.Refresh()
    RunService:Set3dRenderingEnabled(true)
    xDTaraZ.Util.Try("fps boost restore", xDTaraZ.Server.Unboost)
end

local function BuildInterface()
    local Library, problem = xDTaraZ.Util.LoadLibrary(Config.UiSource)
    if not Library then
        xDTaraZ.Util.Alert(problem)
        return
    end
    pcall(NovaBanner.Step, "UI library")
    local T = function(en, th) return Library:T(en, th) end
    local opt = State.Opt
    local statusLabel, runLabel

    local function Notify(text, kind)
        Library:Notify("Build the Pyramid", text, 4, kind or "Info")
    end

    local function Request(name)
        return function() State.Requests[name] = true end
    end

    local function Toggle(group, key, text, description, onChange)
        return group:AddToggle(key, {
            Text = text,
            Description = description,
            Default = false,
            Callback = function(value)
                if value == true and not xDTaraZ.Gate.Ready(key) then
                    Notify(T("Needs a script update (game changed)", "ต้องอัปเดตสคริปต์ (เกมเปลี่ยน)"), "Warning")
                    task.defer(function() Library.Toggles[key]:SetValue(false) end)
                    return
                end
                opt[key] = value
                if value == true then xDTaraZ.Scheduler.Resume(key) end
                if onChange then onChange(value) end
            end,
        })
    end

    local function PlayerNames()
        local names = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then names[#names + 1] = plr.Name end
        end
        table.sort(names)
        return names
    end

    local function GymNames()
        local names = {}
        for _, station in ipairs(GameLib.Gym.BenchpressStations) do
            table.insert(names, ("Gym %s (x%d)"):format(station.GymFolder, station.StrengthMultiplier))
        end
        return names
    end

    ---@return table  list from a game-data source, empty when it errors
    local function Values(source)
        local ok, list = pcall(source)
        return ok and type(list) == "table" and list or {}
    end

    local function Gate()
        local blocked = 0
        for idx in pairs(xDTaraZ.Gate.Needs) do
            local missing = xDTaraZ.Gate.Missing(idx)
            if not Library.Options[idx] or not missing then continue end
            blocked += 1
            warn("[BuildThePyramid] " .. idx .. " blocked, missing " .. missing)
            if Library.Compat then Library.Compat.Block(idx, T("Needs a script update (game changed)", "ต้องอัปเดตสคริปต์ (เกมเปลี่ยน)")) end
        end
        if blocked == 0 then return end
        Library:Notify("Nova Hub", T(blocked .. " features need a script update (game changed)", blocked .. " ฟีเจอร์ต้องอัปเดตสคริปต์ (เกมเปลี่ยน)"), 8, "Warning")
    end

    local function DrainHalted()
        while #State.HaltQueue > 0 do
            local key, reason = table.unpack(table.remove(State.HaltQueue, 1))
            for _, idx in ipairs(xDTaraZ.Scheduler.Toggles[key] or {}) do
                local toggle = Library.Toggles[idx]
                if toggle and toggle.Value == true then toggle:SetValue(false) end
            end
            Notify(key .. " stopped: " .. reason, "Error")
        end
    end

    local function BuildMain(window)
        window:AddTabSection(T("Main", "หลัก"))
        local MainTab = window:AddTab(T("Main", "หลัก"), "house", T("Status and Discord", "สถานะและ Discord"))

        local statusBox = MainTab:AddLeftGroupbox(T("Status", "สถานะ"), "star")
        statusLabel = statusBox:AddLabel(T("Loading...", "กำลังโหลด..."))
        runLabel = statusBox:AddLabel("-")

        local discordBox = MainTab:AddRightGroupbox(T("Discord", "Discord"), "link")
        discordBox:AddLabel(Config.Discord)
        discordBox:AddButton({ Text = T("Copy Discord Link", "คัดลอกลิงก์ Discord"), Style = "Primary", Func = function()
            Notify(xDTaraZ.Util.Copy(Config.Discord) and "Discord link copied" or Config.Discord)
        end })

        local logBox = MainTab:AddRightGroupbox(T("Update Log", "อัปเดตล่าสุด"), "bell")
        for i = 1, math.min(2, #Config.UpdateLog) do
            local entry = Config.UpdateLog[i]
            logBox:AddParagraph({ Title = entry[1], Content = entry[2] })
        end
    end

    local function BuildFarm(window)
        window:AddTabSection(T("Farming", "ฟาร์ม"))
        local FarmTab = window:AddTab(T("Auto Farm", "ฟาร์มอัตโนมัติ"), "brick", T("Blocks and coins", "บล็อกและเหรียญ"))

        local farmBox = FarmTab:AddLeftGroupbox(T("Auto Farm", "ฟาร์มอัตโนมัติ"), "brick")
        farmBox:AddToggle("AutoFarm", {
            Text = T("Auto Farm", "ฟาร์มอัตโนมัติ"),
            Description = T("Grabs blocks and builds the pyramid for coins", "หยิบบล็อกแล้วสร้างพีระมิดเพื่อเหรียญ"),
            Default = false,
            Risky = true,
            Callback = function(value)
                opt.AutoFarm = value
                if value then xDTaraZ.Scheduler.Resume("AutoFarm") else State.Requests.FarmStop = true end
            end,
        })
        Toggle(farmBox, "ReturnOnStop", T("Return On Stop", "กลับที่เดิมเมื่อหยุด"), T("Goes back to where you started", "กลับไปจุดที่เริ่มฟาร์ม"))
        farmBox:AddSlider("PlaceReach", {
            Text = T("Place Distance", "ระยะวางบล็อก"),
            Description = T("Lower it if blocks get refused, raise it for fewer repositions", "ลดถ้าวางไม่ติด เพิ่มเพื่อขยับน้อยลง"),
            Min = 16, Max = 36, Default = opt.PlaceReach, Rounding = 0, Suffix = " studs",
            Callback = function(value) opt.PlaceReach = tonumber(value) or opt.PlaceReach end,
        })
        farmBox:AddButton({ Text = T("Spend Banked Blocks", "ใช้บล็อกที่เก็บไว้"), Func = Request("BankNow") })

        local orderBox = FarmTab:AddRightGroupbox(T("Farm vs Training", "ฟาร์มกับฝึก"), "sliders-horizontal")
        local altSlider, smartSlider
        orderBox:AddDropdown("Priority", {
            Text = T("When Both Are On", "เมื่อเปิดทั้งคู่"),
            Description = T("Balanced trains Strength only while the extra blocks pay it back", "Balanced ฝึกพลังเฉพาะตอนที่คุ้มกับบล็อกที่ได้เพิ่ม"),
            Values = { "Balanced", "Farm", "Train", "Alternate" },
            Default = 1,
            Callback = function(value)
                opt.Priority = value or "Balanced"
                if altSlider then altSlider:SetVisible(opt.Priority == "Alternate") end
                if smartSlider then smartSlider:SetVisible(opt.Priority == "Balanced") end
            end,
        })
        smartSlider = orderBox:AddSlider("SmartMinutes", {
            Text = T("Payback Time (min)", "คืนทุนภายใน (นาที)"),
            Description = T("Train while one more Strength level repays itself within this time", "ฝึกเมื่อเลเวลพลังที่เพิ่มคืนทุนภายในเวลานี้"),
            Min = 5, Max = 240, Default = opt.SmartMinutes, Rounding = 0,
            Callback = function(value) opt.SmartMinutes = tonumber(value) or 30 end,
        })
        altSlider = orderBox:AddSlider("AlternateMinutes", {
            Text = T("Alternate Every (min)", "สลับทุก (นาที)"),
            Min = 1, Max = 30, Default = opt.AlternateMinutes, Rounding = 0,
            Callback = function(value) opt.AlternateMinutes = tonumber(value) or 5 end,
        })
        altSlider:SetVisible(opt.Priority == "Alternate")
    end

    local function BuildTraining(window)
        local GymTab = window:AddTab(T("Training", "ฝึก"), "heart", T("Strength, speed and the pool", "พลัง ความเร็ว และสระ"))

        local gymBox = GymTab:AddLeftGroupbox(T("Gym", "ยิม"), "heart")
        Toggle(gymBox, "AutoStrength", T("Auto Train Strength", "ฝึกพลังอัตโนมัติ"), T("Bench press at your strongest gym", "ยกน้ำหนักที่ยิมแรงสุดที่ใช้ได้"), function(on)
            if not on then State.Requests.TrainStop = true end
        end)
        Toggle(gymBox, "AutoSpeed", T("Auto Train Speed", "ฝึกความเร็วอัตโนมัติ"), T("Runs on your strongest treadmill", "วิ่งบนลู่ที่แรงสุดที่ใช้ได้"))

        local function StationLabels(stations, key)
            local labels = { "Best Unlocked" }
            for _, station in ipairs(stations) do
                table.insert(labels, ("Gym %s (x%d)"):format(station.GymFolder, station[key]))
            end
            return labels
        end
        local function StationPick(optionKey)
            return function(value)
                opt[optionKey] = value and value:match("^Gym (%S+)") or "Best Unlocked"
            end
        end
        gymBox:AddDropdown("BenchStationPick", {
            Text = T("Bench Gym", "ยิมยกน้ำหนัก"),
            Values = StationLabels(GameLib.Gym.BenchpressStations, "StrengthMultiplier"),
            Default = 1,
            Callback = StationPick("BenchStation"),
        })
        gymBox:AddDropdown("TreadmillStationPick", {
            Text = T("Treadmill Gym", "ยิมลู่วิ่ง"),
            Values = StationLabels(GameLib.Gym.TreadmillStations, "SpeedMultiplier"),
            Default = 1,
            Callback = StationPick("TreadmillStation"),
        })

        local poolBox = GymTab:AddRightGroupbox(T("Waters of Nu", "สระ Waters of Nu"), "pipe")
        Toggle(poolBox, "AutoPool", T("Auto Join Pool", "ลงสระอัตโนมัติ"), T("Trains in the pool when a pyramid is finished", "ฝึกในสระเมื่อพีระมิดสร้างเสร็จ"))
        poolBox:AddButton({ Text = T("Go To Pool", "ไปสระ"), Func = Request("TpPool") })
    end

    local function BuildShop(window)
        window:AddTabSection(T("Progression", "ความคืบหน้า"))
        local ShopTab = window:AddTab(T("Upgrades & Codes", "อัปเกรดและโค้ด"), "shop", T("Spend coins and redeem codes", "ใช้เหรียญและใส่โค้ด"))

        local upgradeBox = ShopTab:AddLeftGroupbox(T("Upgrades", "อัปเกรด"), "coin")
        Toggle(upgradeBox, "AutoUpgrade", T("Auto Upgrade", "อัปเกรดอัตโนมัติ"), T("Buys the selected upgrades with coins", "ซื้ออัปเกรดที่เลือกด้วยเหรียญ"))
        opt.Upgrades = {}
        for _, name in ipairs(xDTaraZ.UpgradeNames) do opt.Upgrades[name] = true end
        upgradeBox:AddDropdown("Upgrades", {
            Text = T("Upgrades", "อัปเกรด"),
            Values = xDTaraZ.UpgradeNames,
            Multi = true,
            Default = xDTaraZ.UpgradeNames,
            Callback = function(selected) opt.Upgrades = selected or {} end,
        })
        upgradeBox:AddButton({ Text = T("Buy Now", "ซื้อเดี๋ยวนี้"), Func = Request("UpgradeNow") })

        local rulesBox = ShopTab:AddRightGroupbox(T("Spending", "การใช้เหรียญ"), "coin")
        rulesBox:AddDropdown("UpgradeOrder", {
            Text = T("Order", "ลำดับ"),
            Description = T("Best Value buys what speeds up farming most and saves up when it is close", "Best Value ซื้อตัวที่ช่วยฟาร์มเร็วสุด และเก็บเงินรอถ้าใกล้พอซื้อ"),
            Values = { "Best Value", "Cheapest First", "In Order" },
            Default = 1,
            Callback = function(value) opt.UpgradeOrder = value or "Best Value" end,
        })
        rulesBox:AddSlider("KeepCoins", {
            Text = T("Keep Coins", "กันเหรียญไว้"),
            Min = 0, Max = 1000000, Default = 0, Rounding = 0,
            Callback = function(value) opt.KeepCoins = tonumber(value) or 0 end,
        })

        local codeBox = ShopTab:AddRightGroupbox(T("Codes", "โค้ด"), "code")
        codeBox:AddButton({ Text = T("Redeem All Codes", "ใช้โค้ดทั้งหมด"), Style = "Primary", Func = Request("CodesNow") })
        codeBox:AddButton({ Text = T("Claim Free Gift", "รับของขวัญฟรี"), Func = Request("GiftNow") })
    end

    local function BuildPlayer(window)
        window:AddTabSection(T("Misc", "อื่นๆ"))
        local PlayerTab = window:AddTab(T("Player", "ผู้เล่น"), "user", T("Movement and teleports", "การเคลื่อนที่และวาร์ป"))

        local moveBox = PlayerTab:AddLeftGroupbox(T("Movement", "การเคลื่อนที่"), "star")
        Toggle(moveBox, "SpeedOn", T("Speed", "ความเร็ว"), nil, Request("Movement"))
            :AddKeyPicker("SpeedOnKey", { Default = "None", Mode = "Toggle" })
        moveBox:AddSlider("WalkSpeed", {
            Text = T("Walk Speed", "ความเร็วเดิน"),
            Min = 16, Max = 200, Default = opt.WalkSpeed, Rounding = 0,
            Callback = function(value) opt.WalkSpeed = tonumber(value) or opt.WalkSpeed end,
        })
        Toggle(moveBox, "Fly", T("Fly", "บิน"), nil, Request("Movement"))
            :AddKeyPicker("FlyKey", { Default = "None", Mode = "Toggle" })
        moveBox:AddSlider("FlySpeed", {
            Text = T("Fly Speed", "ความเร็วบิน"),
            Min = 10, Max = 200, Default = opt.FlySpeed, Rounding = 0,
            Callback = function(value) opt.FlySpeed = tonumber(value) or opt.FlySpeed end,
        })
        Toggle(moveBox, "Noclip", T("Noclip", "ทะลุกำแพง"), nil, Request("Movement"))
            :AddKeyPicker("NoclipKey", { Default = "None", Mode = "Toggle" })
        Toggle(moveBox, "InfJump", T("Infinite Jump", "กระโดดไม่จำกัด"))

        local tpBox = PlayerTab:AddRightGroupbox(T("Teleport", "วาร์ป"), "teleport")
        tpBox:AddButton({ Text = T("Quarry", "เหมืองหิน"), Func = Request("TpQuarry") })
        tpBox:AddButton({ Text = T("Pyramid", "พีระมิด"), Func = Request("TpPyramid") })
        tpBox:AddButton({ Text = T("Pool", "สระ"), Func = Request("TpPool") })
        local gymDropdown = tpBox:AddDropdown("GymTarget", {
            Text = T("Gym", "ยิม"),
            Values = Values(GymNames),
            Default = 1,
            Callback = function(value) State.GymTarget = value and value:match("^Gym (%S+)") end,
        })
        State.GymTarget = gymDropdown.Value and gymDropdown.Value:match("^Gym (%S+)")
        tpBox:AddButton({ Text = T("Go To Gym", "ไปยิม"), Func = Request("TpGym") })

        local playerDropdown = tpBox:AddDropdown("PlayerTarget", {
            Text = T("Player", "ผู้เล่น"),
            Values = PlayerNames(),
            Searchable = true,
            AllowNull = true,
            Callback = function(value) State.PlayerTarget = value end,
        })
        tpBox:AddButton({ Text = T("Refresh Players", "รีเฟรชผู้เล่น"), Func = function() playerDropdown:SetValues(PlayerNames()) end })
        tpBox:AddButton({ Text = T("Go To Player", "ไปหาผู้เล่น"), Func = Request("TpPlayer") })
    end

    local function BuildSettings(window)
        local settingsTab = window:AddSettingsTab()
        local sessionBox = settingsTab:AddRightGroupbox(T("Session", "เซสชัน"), "gear")
        Toggle(sessionBox, "AntiAfk", T("Anti AFK", "กันหลุด AFK"), T("Stops the idle kick", "กันโดนเตะเพราะไม่ขยับ"))
        Toggle(sessionBox, "AutoRejoin", T("Auto Rejoin", "เข้าเกมใหม่อัตโนมัติ"), T("Rejoins by itself after a disconnect", "หลุดแล้วเข้าเกมใหม่เอง"))
        Toggle(sessionBox, "NoRender", T("Disable 3D Rendering", "ปิดการเรนเดอร์ 3D"), T("Saves battery and CPU while farming", "ประหยัดแบตและ CPU ตอนฟาร์ม"), function(on)
            RunService:Set3dRenderingEnabled(not on)
        end)
        sessionBox:AddButton({ Text = T("FPS Boost", "เพิ่ม FPS"), Func = Request("Boost") })
        sessionBox:AddButton({ Text = T("Rejoin", "เข้าเซิร์ฟเดิมใหม่"), Func = Request("Rejoin") })
        sessionBox:AddButton({ Text = T("Server Hop", "ย้ายเซิร์ฟ"), Func = Request("Hop") })
    end

    local function Live()
        Library:Every(1, function()
            while #State.Messages > 0 do
                Notify(table.remove(State.Messages, 1))
            end
            DrainHalted()
            if statusLabel then statusLabel:SetText(State.Summary or "-") end
            if not runLabel then return end
            runLabel:SetText(State.Task == "None" and State.Status or ("%s: %s"):format(State.Task, State.Status))
        end)
    end

    local function BuildTabs()
        local window = Library.Window
        xDTaraZ.Util.Try("ui main", BuildMain, window)
        xDTaraZ.Util.Try("ui farm", BuildFarm, window)
        xDTaraZ.Util.Try("ui training", BuildTraining, window)
        xDTaraZ.Util.Try("ui shop", BuildShop, window)
        xDTaraZ.Util.Try("ui player", BuildPlayer, window)
        xDTaraZ.Util.Try("ui settings", BuildSettings, window)
        xDTaraZ.Util.Try("ui gate", Gate)
        xDTaraZ.Util.Try("ui live", Live)
    end

    local function UnloadHub()
        Library:Unload()
    end
    Library:OnUnload(xDTaraZ.Scheduler.Stop)
    Library:OnUnload(function()
        if getgenv().BuildThePyramidUnload == UnloadHub then getgenv().BuildThePyramidUnload = nil end
    end)
    getgenv().BuildThePyramidUnload = UnloadHub

    Library:CreateWindow({
        Title = "Nova Hub",
        SubTitle = "Nova Hub",
        MenuKey = Enum.KeyCode.LeftControl,
        ConfigFolder = Config.SaveFolder,
        Language = "Auto",
        Theme = "Nova",
        OnUnlocked = function()
            BuildTabs()
            xDTaraZ.Util.Try("boot", xDTaraZ.Scheduler.Boot)
            Notify("Loaded", "Success")
            xDTaraZ.Util.Try("autoload config", Library.LoadAutoloadConfig, Library)
        end,
    })
    return true
end

if getgenv().BuildThePyramidUnload then
    pcall(getgenv().BuildThePyramidUnload)
end

pcall(NovaBanner.Step, "Systems")
if BuildInterface() then
    pcall(NovaBanner.Step, "Interface")
    pcall(NovaBanner.Ready)
end]==]

--//==================================================
--// NOVA HUB ORIGINAL PLATOBOOST KEY SYSTEM
--// Restored from the user's original Nova Hub flow.
--// Service: 33571
--//==================================================
do
    local SERVICE_ID = 33571
    local Players = game:GetService("Players")
    local HttpService = game:GetService("HttpService")
    local UserInputService = game:GetService("UserInputService")
    local LocalPlayer = Players.LocalPlayer

    local function requestJson(url, method, body)
        local req = (syn and syn.request) or (http and http.request) or http_request or request
        if req then
            local payload = {Url=url, Method=method or "GET", Headers={['Content-Type']='application/json'}}
            if body then payload.Body = HttpService:JSONEncode(body) end
            local r = req(payload)
            local code = tonumber(r.StatusCode or r.status_code or 0) or 0
            local raw = r.Body or r.body or ""
            local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
            return code, data, raw
        end
        if method == "POST" then
            local raw = game:HttpGet(url)
            local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
            return 200, ok and data or nil, raw
        end
        local raw = game:HttpGet(url)
        local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
        return 200, ok and data or nil, raw
    end

    local function getIdentifier()
        local hw = getgenv and getgenv().gethwid
        if type(hw) == "function" then
            local ok, id = pcall(hw)
            if ok and id and tostring(id) ~= "" then return tostring(id) end
        end
        return tostring(LocalPlayer.UserId)
    end

    local function normalizeKey(key)
        -- Original Nova behavior: case-insensitive and tolerant of - / _ formatting.
        return tostring(key or ""):lower():gsub("[%s_-]", "")
    end

    --// NOVA HUB OWNER BYPASS
    --// Entering 1911 unlocks Nova Hub without contacting Platoboost.
    --// Keep this code private if the script is publicly distributed.
    local OWNER_BYPASS_CODE = "1911"

    local function verifyKey(key)
        local identifier = getIdentifier()
        local clean = normalizeKey(key)

        -- Owner code is checked locally before the online key verification.
        if clean == normalizeKey(OWNER_BYPASS_CODE) then
            return true, "Owner code accepted!"
        end

        if clean == "" then return false, "Enter a key first." end
        local url = string.format("https://auth.platorelay.com/public/whitelist/%d?identifier=%s&key=%s", SERVICE_ID, HttpService:UrlEncode(identifier), HttpService:UrlEncode(clean))
        local code, data = requestJson(url, "GET")
        if code < 200 or code >= 300 or type(data) ~= "table" then
            return false, "Verification service unavailable."
        end
        local valid = data.valid == true or (type(data.data) == "table" and data.data.valid == true)
        return valid, valid and "Key verified!" or "Invalid or expired key."
    end

    -- Platoboost moved its public API from the old auth.platorelay.com
    -- endpoint to api.platoboost.com / api.platoboost.net.
    -- The old endpoint can return a non-JSON/redirect response, which caused
    -- the Nova Hub "Could not generate key link." message on Delta.
    local PLATO_API

    local function detectPlatoApi()
        local candidates = {
            "https://api.platoboost.com",
            "https://api.platoboost.net",
        }

        for _, base in ipairs(candidates) do
            local code = requestJson(base .. "/public/connectivity", "GET")
            if tonumber(code) == 200 or tonumber(code) == 429 then
                return base
            end
        end

        return candidates[1]
    end

    local function getKeyLink()
        local identifier = getIdentifier()
        PLATO_API = PLATO_API or detectPlatoApi()

        local function tryStart(base)
            local req = (syn and syn.request) or (http and http.request) or http_request or request
            if type(req) ~= "function" then
                return nil, "HTTP request function unavailable."
            end

            local payload = {
                Url = base .. "/public/start",
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json",
                    ["User-Agent"] = "Roblox/Exploit",
                },
                Body = HttpService:JSONEncode({
                    service = SERVICE_ID,
                    identifier = identifier,
                }),
            }

            local ok, response = pcall(req, payload)
            if not ok or type(response) ~= "table" then
                return nil, "HTTP request failed."
            end

            local code = tonumber(response.StatusCode or response.status_code or 0) or 0
            local raw = response.Body or response.body or ""

            if code == 429 then
                return nil, "Rate limited. Please wait a few seconds and try again."
            end

            if code ~= 200 then
                return nil, "Platoboost returned HTTP " .. tostring(code) .. "."
            end

            local decodedOk, data = pcall(HttpService.JSONDecode, HttpService, raw)
            if not decodedOk or type(data) ~= "table" then
                return nil, "Platoboost returned an invalid response."
            end

            if data.success == true
                and type(data.data) == "table"
                and type(data.data.url) == "string"
                and data.data.url ~= "" then
                return data.data.url, nil
            end

            if type(data.data) == "table"
                and type(data.data.url) == "string"
                and data.data.url ~= "" then
                return data.data.url, nil
            end

            return nil, tostring(data.message or "Platoboost did not return a key link.")
        end

        local link, err = tryStart(PLATO_API)
        if link then
            return link, 200
        end

        -- Try the secondary API host if the primary host is unavailable.
        local fallback = PLATO_API == "https://api.platoboost.com"
            and "https://api.platoboost.net"
            or "https://api.platoboost.com"

        local retryLink, retryErr = tryStart(fallback)
        if retryLink then
            PLATO_API = fallback
            return retryLink, 200
        end

        return nil, err or retryErr or "Unable to generate key link."
    end

    local function clipboard(text)
        local f = setclipboard or toclipboard or (syn and syn.set_clipboard)
        if type(f) == "function" then pcall(f, text); return true end
        return false
    end

    local function keyGui()
        local gui = Instance.new("ScreenGui")
        gui.Name = "NovaHub_KeySystem"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        pcall(function() gui.Parent = game:GetService("CoreGui") end)
        if not gui.Parent then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

        local dim = Instance.new("Frame", gui)
        dim.Size = UDim2.fromScale(1,1); dim.BackgroundColor3=Color3.new(0,0,0); dim.BackgroundTransparency=.3

        local card = Instance.new("Frame", dim)
        card.AnchorPoint=Vector2.new(.5,.5); card.Position=UDim2.fromScale(.5,.5); card.Size=UDim2.fromOffset(390,245)
        card.BackgroundColor3=Color3.fromRGB(16,12,25)
        Instance.new("UICorner",card).CornerRadius=UDim.new(0,14)
        local stroke=Instance.new("UIStroke",card); stroke.Color=Color3.fromRGB(145,75,255); stroke.Thickness=2

        local title=Instance.new("TextLabel",card); title.BackgroundTransparency=1; title.Position=UDim2.fromOffset(20,16); title.Size=UDim2.new(1,-40,0,32); title.Text="✦ NOVA HUB"; title.TextColor3=Color3.fromRGB(190,135,255); title.TextSize=25; title.Font=Enum.Font.GothamBold
        local sub=Instance.new("TextLabel",card); sub.BackgroundTransparency=1; sub.Position=UDim2.fromOffset(20,50); sub.Size=UDim2.new(1,-40,0,24); sub.Text="Enter your key or owner code to continue"; sub.TextColor3=Color3.fromRGB(190,185,200); sub.TextSize=14; sub.Font=Enum.Font.Gotham

        local box=Instance.new("TextBox",card); box.Position=UDim2.fromOffset(20,86); box.Size=UDim2.new(1,-40,0,42); box.BackgroundColor3=Color3.fromRGB(27,22,38); box.PlaceholderText="Enter your KEY_..."; box.PlaceholderColor3=Color3.fromRGB(120,110,130); box.TextColor3=Color3.fromRGB(245,240,255); box.TextSize=15; box.Font=Enum.Font.Gotham; box.ClearTextOnFocus=false; Instance.new("UICorner",box).CornerRadius=UDim.new(0,9)

        local get=Instance.new("TextButton",card); get.Position=UDim2.fromOffset(20,140); get.Size=UDim2.new(.47,-25,0,40); get.BackgroundColor3=Color3.fromRGB(55,38,78); get.Text="GET KEY"; get.TextColor3=Color3.fromRGB(235,220,255); get.TextSize=14; get.Font=Enum.Font.GothamBold; Instance.new("UICorner",get).CornerRadius=UDim.new(0,9)
        local verify=Instance.new("TextButton",card); verify.Position=UDim2.new(.53,5,0,140); verify.Size=UDim2.new(.47,-25,0,40); verify.BackgroundColor3=Color3.fromRGB(105,55,170); verify.Text="VERIFY KEY"; verify.TextColor3=Color3.new(1,1,1); verify.TextSize=14; verify.Font=Enum.Font.GothamBold; Instance.new("UICorner",verify).CornerRadius=UDim.new(0,9)
        local status=Instance.new("TextLabel",card); status.BackgroundTransparency=1; status.Position=UDim2.fromOffset(20,190); status.Size=UDim2.new(1,-40,0,36); status.Text=""; status.TextWrapped=true; status.TextColor3=Color3.fromRGB(180,170,195); status.TextSize=13; status.Font=Enum.Font.Gotham

        get.MouseButton1Click:Connect(function()
            status.Text="Generating key link..."
            task.spawn(function()
                local link, result = getKeyLink()
                if link then
                    if clipboard(link) then
                        status.Text="Key link copied to clipboard."
                    else
                        status.Text=link
                    end
                else
                    status.Text=tostring(result or "Could not generate key link.")
                end
            end)
        end)
        local verified=false
        verify.MouseButton1Click:Connect(function()
            if verified then return end
            status.Text="Checking key..."
            task.spawn(function()
                local ok,msg=verifyKey(box.Text)
                status.Text=msg
                if ok then
                    verified=true
                    task.wait(.25)
                    gui:Destroy()
                    local cache= "NovaHub_KeyCache.txt"
                    local wf=writefile
                    if type(wf)=="function" then pcall(wf,cache,normalizeKey(box.Text)) end
                    _G.NovaHubKeyUnlocked=true
                end
            end)
        end)
        return gui
    end

    -- Cached-key check keeps the original convenience behavior.
    local cached
    if type(isfile)=="function" and isfile("NovaHub_KeyCache.txt") and type(readfile)=="function" then
        local ok,v=pcall(readfile,"NovaHub_KeyCache.txt"); if ok then cached=v end
    end
    local unlocked=false
    if cached and normalizeKey(cached) ~= "" then
        unlocked=select(1,verifyKey(cached))
    end
    if not unlocked then
        keyGui()
        repeat task.wait(.1) until _G.NovaHubKeyUnlocked or not game:IsLoaded()
    end
end

local gameId = game.GameId
local gameSource = NOVA_HUB_MODULES[gameId]

if not gameSource then
local gameId = game.GameId
local gameSource = NOVA_HUB_MODULES[gameId]

if not gameSource then
    --//==============================================================
    --// NOVA HUB UNIVERSAL FALLBACK
    --// Uses the EXACT SAME Nova UI library, theme, window,
    --// tabs, animations and settings system as supported games.
    --//==============================================================

    local function LoadUniversalNovaUI()
        -- IMPORTANT:
        -- Do NOT use env.NOVA_HUB_UI_SOURCE here.
        -- Part 8 already has the real Nova loader:
        -- xDTaraZ.Util.LoadLibrary()
        local Library = xDTaraZ.Util.LoadLibrary()

        if not Library then
            xDTaraZ.Util.Alert(
                "Nova Hub UI could not be loaded.",
                "Universal fallback"
            )
            return false
        end

        -- Close a previous universal instance if one exists.
        if getgenv and getgenv().NovaHubUniversalUnload then
            pcall(getgenv().NovaHubUniversalUnload)
        end

        local Players = game:GetService("Players")
        local TeleportService = game:GetService("TeleportService")
        local Lighting = game:GetService("Lighting")
        local RunService = game:GetService("RunService")

        local LocalPlayer = Players.LocalPlayer

        local T = function(en, th)
            return Library:T(en, th)
        end

        local function Notify(text, kind)
            pcall(function()
                Library:Notify(
                    "Nova Hub",
                    tostring(text),
                    4,
                    kind or "Info"
                )
            end)
        end

        local function GetHumanoid()
            local character = LocalPlayer.Character
            if not character then
                return nil
            end

            return character:FindFirstChildOfClass("Humanoid")
        end

        local function AddInfo(group, title, value)
            group:AddLabel(
                T(title, title) ..
                "\n" ..
                tostring(value)
            )
        end

        --==============================================================
        -- BUILD UNIVERSAL TABS
        --==============================================================

        local function BuildTabs()
            local window = Library.Window

            if not window then
                error("Nova Hub Window was not created")
            end

            --==========================================================
            -- MAIN
            --==========================================================

            window:AddTabSection(
                T("Universal", "สากล")
            )

            local HomeTab = window:AddTab(
                T("Home", "หน้าหลัก"),
                "house",
                T(
                    "Universal Nova Hub",
                    "Nova Hub สากล"
                )
            )

            local StatusBox = HomeTab:AddLeftGroupbox(
                T("Game Status", "สถานะเกม"),
                "info"
            )

            AddInfo(
                StatusBox,
                "Game",
                game.Name
            )

            AddInfo(
                StatusBox,
                "Game ID",
                game.GameId
            )

            AddInfo(
                StatusBox,
                "Place ID",
                game.PlaceId
            )

            AddInfo(
                StatusBox,
                "Job ID",
                game.JobId ~= "" and game.JobId or "Studio / unavailable"
            )

            AddInfo(
                StatusBox,
                "Player",
                LocalPlayer.Name
            )

            AddInfo(
                StatusBox,
                "User ID",
                LocalPlayer.UserId
            )

            local UniversalBox = HomeTab:AddRightGroupbox(
                T("Nova Hub", "Nova Hub"),
                "star"
            )

            UniversalBox:AddLabel(
                T(
                    "Universal Mode is active.\n" ..
                    "This game does not currently have a dedicated Nova Hub module.",
                    "โหมดสากลกำลังทำงาน\n" ..
                    "เกมนี้ยังไม่มีโมดูล Nova Hub โดยเฉพาะ"
                )
            )

            UniversalBox:AddButton({
                Text = T(
                    "Copy Game ID",
                    "คัดลอก Game ID"
                ),

                Style = "Primary",

                Func = function()
                    local copy =
                        setclipboard
                        or toclipboard
                        or (syn and syn.set_clipboard)

                    if type(copy) == "function" then
                        local ok = pcall(
                            copy,
                            tostring(game.GameId)
                        )

                        if ok then
                            Notify(
                                "Game ID copied.",
                                "Success"
                            )
                            return
                        end
                    end

                    Notify(
                        "Game ID: " .. tostring(game.GameId),
                        "Info"
                    )
                end,
            })

            UniversalBox:AddButton({
                Text = T(
                    "Copy Place ID",
                    "คัดลอก Place ID"
                ),

                Func = function()
                    local copy =
                        setclipboard
                        or toclipboard
                        or (syn and syn.set_clipboard)

                    if type(copy) == "function" then
                        local ok = pcall(
                            copy,
                            tostring(game.PlaceId)
                        )

                        if ok then
                            Notify(
                                "Place ID copied.",
                                "Success"
                            )
                            return
                        end
                    end

                    Notify(
                        "Place ID: " .. tostring(game.PlaceId),
                        "Info"
                    )
                end,
            })

            UniversalBox:AddButton({
                Text = T(
                    "Rejoin Server",
                    "เข้าร่วมเซิร์ฟเวอร์ใหม่"
                ),

                Func = function()
                    pcall(function()
                        TeleportService:TeleportToPlaceInstance(
                            game.PlaceId,
                            game.JobId,
                            LocalPlayer
                        )
                    end)
                end,
            })

            UniversalBox:AddButton({
                Text = T(
                    "Rejoin Game",
                    "เข้าเกมใหม่"
                ),

                Func = function()
                    pcall(function()
                        TeleportService:Teleport(
                            game.PlaceId,
                            LocalPlayer
                        )
                    end)
                end,
            })

            --==========================================================
            -- PLAYER
            --==========================================================

            window:AddTabSection(
                T("Player", "ผู้เล่น")
            )

            local PlayerTab = window:AddTab(
                T("Player", "ผู้เล่น"),
                "user",
                T(
                    "Universal player controls",
                    "เครื่องมือผู้เล่นสากล"
                )
            )

            local MovementBox = PlayerTab:AddLeftGroupbox(
                T("Movement", "การเคลื่อนที่"),
                "person-running"
            )

            MovementBox:AddSlider(
                "NovaUniversalWalkSpeed",
                {
                    Text = T(
                        "Walk Speed",
                        "ความเร็วเดิน"
                    ),

                    Default = 16,
                    Min = 0,
                    Max = 150,
                    Rounding = 0,

                    Callback = function(value)
                        local hum = GetHumanoid()

                        if hum then
                            hum.WalkSpeed =
                                tonumber(value) or 16
                        end
                    end,
                }
            )

            MovementBox:AddSlider(
                "NovaUniversalJumpPower",
                {
                    Text = T(
                        "Jump Power",
                        "พลังการกระโดด"
                    ),

                    Default = 50,
                    Min = 0,
                    Max = 150,
                    Rounding = 0,

                    Callback = function(value)
                        local hum = GetHumanoid()

                        if hum then
                            pcall(function()
                                hum.UseJumpPower = true
                            end)

                            hum.JumpPower =
                                tonumber(value) or 50
                        end
                    end,
                }
            )

            MovementBox:AddButton({
                Text = T(
                    "Reset Movement",
                    "รีเซ็ตการเคลื่อนที่"
                ),

                Style = "Primary",

                Func = function()
                    local hum = GetHumanoid()

                    if hum then
                        hum.WalkSpeed = 16

                        pcall(function()
                            hum.UseJumpPower = true
                        end)

                        hum.JumpPower = 50
                    end

                    -- Force the actual Nova sliders back to their
                    -- original values as well.
                    pcall(function()
                        if Library.Options.NovaUniversalWalkSpeed then
                            Library.Options.NovaUniversalWalkSpeed:SetValue(16)
                        end
                    end)

                    pcall(function()
                        if Library.Options.NovaUniversalJumpPower then
                            Library.Options.NovaUniversalJumpPower:SetValue(50)
                        end
                    end)

                    Notify(
                        "Movement reset to 16 WalkSpeed / 50 JumpPower.",
                        "Success"
                    )
                end,
            })

            local CharacterBox = PlayerTab:AddRightGroupbox(
                T("Character", "ตัวละคร"),
                "user"
            )

            CharacterBox:AddButton({
                Text = T(
                    "Respawn Character",
                    "เกิดใหม่"
                ),

                Func = function()
                    local hum = GetHumanoid()

                    if hum then
                        hum.Health = 0
                    end
                end,
            })

            CharacterBox:AddButton({
                Text = T(
                    "Refresh Character",
                    "รีเฟรชตัวละคร"
                ),

                Func = function()
                    pcall(function()
                        LocalPlayer:LoadCharacter()
                    end)
                end,
            })

            --==========================================================
            -- VISUALS
            --==========================================================

            window:AddTabSection(
                T("Visuals", "ภาพ")
            )

            local VisualTab = window:AddTab(
                T("Visuals", "ภาพ"),
                "eye",
                T(
                    "Universal visual controls",
                    "เครื่องมือภาพสากล"
                )
            )

            local OriginalLighting = {
                Brightness = Lighting.Brightness,
                ClockTime = Lighting.ClockTime,
                FogEnd = Lighting.FogEnd,
                GlobalShadows = Lighting.GlobalShadows,
                OutdoorAmbient = Lighting.OutdoorAmbient,
            }

            local LightingBox = VisualTab:AddLeftGroupbox(
                T("Lighting", "แสง"),
                "sun"
            )

            LightingBox:AddToggle(
                "NovaUniversalFullBright",
                {
                    Text = T(
                        "FullBright",
                        "FullBright"
                    ),

                    Default = false,

                    Callback = function(enabled)
                        if enabled then
                            Lighting.Brightness = 2
                            Lighting.ClockTime = 14
                            Lighting.FogEnd = 100000
                            Lighting.GlobalShadows = false
                            Lighting.OutdoorAmbient =
                                Color3.new(1, 1, 1)
                        else
                            pcall(function()
                                Lighting.Brightness =
                                    OriginalLighting.Brightness
                                Lighting.ClockTime =
                                    OriginalLighting.ClockTime
                                Lighting.FogEnd =
                                    OriginalLighting.FogEnd
                                Lighting.GlobalShadows =
                                    OriginalLighting.GlobalShadows
                                Lighting.OutdoorAmbient =
                                    OriginalLighting.OutdoorAmbient
                            end)
                        end
                    end,
                }
            )

            LightingBox:AddButton({
                Text = T(
                    "Restore Lighting",
                    "คืนค่าแสง"
                ),

                Func = function()
                    pcall(function()
                        Lighting.Brightness =
                            OriginalLighting.Brightness

                        Lighting.ClockTime =
                            OriginalLighting.ClockTime

                        Lighting.FogEnd =
                            OriginalLighting.FogEnd

                        Lighting.GlobalShadows =
                            OriginalLighting.GlobalShadows

                        Lighting.OutdoorAmbient =
                            OriginalLighting.OutdoorAmbient
                    end)

                    pcall(function()
                        if Library.Options.NovaUniversalFullBright then
                            Library.Options.NovaUniversalFullBright:SetValue(false)
                        end
                    end)

                    Notify(
                        "Lighting restored.",
                        "Success"
                    )
                end,
            })

            --==========================================================
            -- SERVER
            --==========================================================

            window:AddTabSection(
                T("Server", "เซิร์ฟเวอร์")
            )

            local ServerTab = window:AddTab(
                T("Server", "เซิร์ฟเวอร์"),
                "server",
                T(
                    "Universal server utilities",
                    "เครื่องมือเซิร์ฟเวอร์สากล"
                )
            )

            local ServerInfo = ServerTab:AddLeftGroupbox(
                T("Server Information", "ข้อมูลเซิร์ฟเวอร์"),
                "server"
            )

            AddInfo(
                ServerInfo,
                "Players",
                #Players:GetPlayers()
            )

            AddInfo(
                ServerInfo,
                "Max Players",
                Players.MaxPlayers
            )

            AddInfo(
                ServerInfo,
                "Job ID",
                game.JobId ~= "" and game.JobId or "Unavailable"
            )

            local ServerActions = ServerTab:AddRightGroupbox(
                T("Actions", "การทำงาน"),
                "refresh"
            )

            ServerActions:AddButton({
                Text = T(
                    "Rejoin Current Server",
                    "เข้าร่วมเซิร์ฟเวอร์ปัจจุบัน"
                ),

                Func = function()
                    pcall(function()
                        TeleportService:TeleportToPlaceInstance(
                            game.PlaceId,
                            game.JobId,
                            LocalPlayer
                        )
                    end)
                end,
            })

            ServerActions:AddButton({
                Text = T(
                    "Copy Job ID",
                    "คัดลอก Job ID"
                ),

                Func = function()
                    local copy =
                        setclipboard
                        or toclipboard
                        or (syn and syn.set_clipboard)

                    if type(copy) == "function" then
                        pcall(
                            copy,
                            tostring(game.JobId)
                        )

                        Notify(
                            "Job ID copied.",
                            "Success"
                        )
                    else
                        Notify(
                            "Job ID: " .. tostring(game.JobId),
                            "Info"
                        )
                    end
                end,
            })

            --==========================================================
            -- SETTINGS
            --==========================================================

            local SettingsTab = window:AddSettingsTab()

            local SessionBox = SettingsTab:AddLeftGroupbox(
                T("Session", "เซสชัน"),
                "settings"
            )

            SessionBox:AddButton({
                Text = T(
                    "Rejoin Game",
                    "เข้าเกมใหม่"
                ),

                Func = function()
                    pcall(function()
                        TeleportService:Teleport(
                            game.PlaceId,
                            LocalPlayer
                        )
                    end)
                end,
            })

            SessionBox:AddButton({
                Text = T(
                    "Unload Nova Hub",
                    "ปิด Nova Hub"
                ),

                Style = "Primary",

                Func = function()
                    pcall(function()
                        Library:Unload()
                    end)
                end,
            })
        end

        --==============================================================
        -- UNIVERSAL UNLOAD
        --==============================================================

        local function UnloadUniversal()
            pcall(function()
                Library:Unload()
            end)
        end

        getgenv().NovaHubUniversalUnload =
            UnloadUniversal

        Library:OnUnload(function()
            if getgenv().NovaHubUniversalUnload ==
                UnloadUniversal then

                getgenv().NovaHubUniversalUnload = nil
            end
        end)

        --==============================================================
        -- SAME NOVA WINDOW CONFIGURATION
        --==============================================================

        Library:CreateWindow({
            Title = "Nova Hub",
            SubTitle = "Nova Hub",
            MenuKey = Enum.KeyCode.LeftControl,

            -- Use the SAME config folder used by the actual
            -- Nova Hub configuration instead of making a
            -- separate generic fallback configuration.
            ConfigFolder = Config.SaveFolder,

            Language = "Auto",
            Theme = "Nova",

            OnUnlocked = function()
                xDTaraZ.Util.Try(
                    "universal ui",
                    BuildTabs
                )

                Notify(
                    "Universal Nova Hub loaded.",
                    "Success"
                )

                -- Keep the same autoload behavior as the
                -- supported Nova Hub interface.
                xDTaraZ.Util.Try(
                    "autoload config",
                    Library.LoadAutoloadConfig,
                    Library
                )
            end,
        })

        return true
    end

    if LoadUniversalNovaUI() then
        xDTaraZ.Util.Alert(
            "Universal Nova Hub loaded.",
            "Game ID: " .. tostring(game.GameId)
        )
    end

    return
end

--==============================================================
-- SUPPORTED GAME MODULE
--==============================================================

local chunk, compileErr = loadstring(gameSource)

if not chunk then
    xDTaraZ.Util.Alert(
        "Nova Hub compile error.",
        tostring(compileErr)
    )
    return
end

local ok, err = xpcall(
    chunk,
    function(e)
        return debug.traceback(
            tostring(e),
            2
        )
    end
)

if not ok then
    local shortError =
        tostring(err):match("^[^\n]*")

    xDTaraZ.Util.Alert(
        "Nova Hub stopped.",
        shortError
    )

    warn(
        "[Nova Hub] " ..
        tostring(err)
    )
end
