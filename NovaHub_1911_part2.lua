k.defer(option.SetValue, option, false)
        return false
    end)
end

---Requires a game module; identity-3 executors get "Cannot require a non-RobloxScript module", so it retries from an identity-2 thread when the executor can really switch.
---@return boolean ok, any module or the error
function Compat.Require(module)
    local ok, loaded = pcall(require, module)
    if ok or not Compat.Caps.Identity then
        return ok, loaded
    end
    local finished, okAgain, again = Util.Await(Compat.CallTimeout, function()
        Compat.Api.SetIdentity(2)
        return pcall(require, module)
    end)
    if finished and okAgain then
        return true, again
    end
    return false, loaded
end

---Calls a game function inline; one that throws "non-RobloxScript" (it requires lazily inside) is rerun from a deferred identity-2 thread and remembered per function.
---The deferred thread keeps the caller untainted.
function Compat.Call(fn, ...)
    if not Compat.Deferred[fn] then
        local result = table.pack(pcall(fn, ...))
        if result[1] then
            return table.unpack(result, 2, result.n)
        end
        if not Compat.Caps.Identity or not tostring(result[2]):find("non-RobloxScript", 1, true) then
            error(result[2], 0)
        end
        Compat.Deferred[fn] = true
    end
    local args = table.pack(...)
    local box
    task.defer(function()
        Compat.Api.SetIdentity(2)
        box = table.pack(pcall(fn, table.unpack(args, 1, args.n)))
    end)
    local deadline = os.clock() + Compat.CallTimeout
    while not box and os.clock() < deadline do
        task.wait()
    end
    if not box then
        error("game call timed out", 0)
    end
    if not box[1] then
        error(box[2], 0)
    end
    return table.unpack(box, 2, box.n)
end

local function Wrap(handler)
    local okWrap, wrapped = pcall(Compat.Api.NewCClosure or error, handler)
    return okWrap and type(wrapped) == "function" and wrapped or handler
end

---Undoes a hook: the executor's restorefunction first, else `rehook`.
function Compat.Unhook(target, rehook)
    local api = Compat.Api
    if target and api.RestoreFunction and pcall(api.RestoreFunction, target) then
        if not api.IsFunctionHooked then
            return
        end
        local ok, still = pcall(api.IsFunctionHooked, target)
        if ok and not still then
            return
        end
    end
    rehook()
end

local function Track(putBack)
    table.insert(Compat.Restores, putBack)
    return function()
        local index = table.find(Compat.Restores, putBack)
        if not index then
            return
        end
        table.remove(Compat.Restores, index)
        Util.Try(putBack)
    end
end

---Hooks one metamethod only when Caps.Namecall proved hookmetamethod returns the real original.
---@return function?  original, nil when refused
---@return function?  restore
function Compat.HookMeta(object, method, handler)
    if not Compat.Caps.Namecall then
        return nil
    end
    local api = Compat.Api
    local ok, original = pcall(api.HookMetamethod, object, method, Wrap(handler))
    if not ok or type(original) ~= "function" then
        return nil
    end
    return original, Track(function()
        api.HookMetamethod(object, method, original)
    end)
end

---Hooks one function only when Caps.HookFunction proved hookfunction works.
---@return function?  original, nil when refused
---@return function?  restore
function Compat.HookFunction(target, handler)
    if not Compat.Caps.HookFunction then
        return nil
    end
    local api = Compat.Api
    local ok, original = pcall(api.HookFunction, target, Wrap(handler))
    if not ok or type(original) ~= "function" then
        return nil
    end
    return original, Track(function()
        Compat.Unhook(target, function()
            pcall(api.HookFunction, target, original)
        end)
    end)
end

function Compat.RestoreAll()
    for index = #Compat.Restores, 1, -1 do
        Util.Try(Compat.Restores[index])
    end
    table.clear(Compat.Restores)
end

---Yields up to `timeout` seconds watching for one outgoing packet; without RakNet enabled in Potassium the hooks never fire.
---@return boolean
function Compat.RaknetLive(timeout)
    if not Compat.Caps.Raknet then
        return false
    end
    local seen = false
    local function Watch()
        seen = true
    end
    if not pcall(raknet.add_send_hook, Watch) then
        return false
    end
    local deadline = os.clock() + (timeout or 2)
    while not seen and os.clock() < deadline do
        task.wait(0.1)
    end
    pcall(raknet.remove_send_hook, Watch)
    return seen
end

---Runs every probe deferred so the first toggle press does not pay for one.
function Compat.Warm()
    for name in pairs(Compat.Probes) do
        task.defer(function()
            local _ = Compat.Caps[name]
        end)
    end
end

--@return {EN,TH} ข้อความจาก Lang.Strings ที่ format แล้วทั้งสองภาษา
function Lang.Format(key, ...)
    local spec = Lang.Strings[key] or { EN = key, TH = key }
    local args = table.pack(...)
    return {
        EN = string.format(spec.EN, table.unpack(args, 1, args.n)),
        TH = string.format(spec.TH or spec.EN, table.unpack(args, 1, args.n)),
    }
end

function Configs.SetFolder(name)
    Configs.Folder = Config.ConfigRoot .. "/" .. Util.Sanitize(name)
    if Util.FileApi() then
        Util.EnsureFolder(Configs.Folder)
    end
end

function Configs.Path(name)
    return Configs.Folder .. "/" .. Util.Sanitize(name) .. ".json"
end

function Configs.Save(name)
    if not Util.FileApi() then
        return false, Lang.Get("NoFileApi")
    end
    local snapshot = {}
    for idx, option in pairs(Library.Options) do
        if not option.NoSave and option.Serialize then
            snapshot[idx] = { Type = option.Type, Value = option:Serialize() }
        end
    end
    return (pcall(writefile, Configs.Path(name), HttpService:JSONEncode(snapshot)))
end

function Configs.Load(name)
    local path = Configs.Path(name)
    if not Util.FileApi() or not Util.Exists(path) then
        return false, Lang.Get("ConfigMissing")
    end
    local read, raw = pcall(readfile, path)
    local ok, snapshot = pcall(HttpService.JSONDecode, HttpService, read and raw or "")
    if not ok or type(snapshot) ~= "table" then
        return false, Lang.Get("ConfigBroken")
    end
    for idx, saved in pairs(snapshot) do
        local option = Library.Options[idx]
        if option and not option.NoSave and option.Type == saved.Type then
            Util.Try(option.Deserialize, option, saved.Value)
        end
    end
    return true
end

function Configs.Delete(name)
    local path = Configs.Path(name)
    if type(delfile) ~= "function" or not Util.FileApi() or not Util.Exists(path) then
        return false, Lang.Get("ConfigMissing")
    end
    return (pcall(delfile, path))
end

function Configs.List()
    if type(listfiles) ~= "function" or not Util.FileApi() then
        return {}
    end
    local ok, files = pcall(listfiles, Configs.Folder)
    local names = {}
    for _, path in ipairs(ok and files or {}) do
        local name = path:match("([^/\\]+)%.json$")
        if name then
            table.insert(names, name)
        end
    end
    table.sort(names)
    return names
end

function Configs.SetAutoload(name)
    if not Util.FileApi() then
        return false, Lang.Get("NoFileApi")
    end
    return (pcall(writefile, Configs.Folder .. "/autoload.txt", name))
end

function Configs.GetAutoload()
    local path = Configs.Folder .. "/autoload.txt"
    if not Util.FileApi() or not Util.Exists(path) then
        return nil
    end
    local ok, name = pcall(readfile, path)
    return ok and type(name) == "string" and name ~= "" and name or nil
end

function Configs.BuildSection(group)
    local nameInput = group:AddInput("NovaConfigName", { Text = Lang.Strings.ConfigName, Placeholder = "default", NoSave = true })
    local list = group:AddListBox("NovaConfigList", { Text = Lang.Strings.SavedConfigs, Values = Configs.List(), Height = 4, NoSave = true })
    local autoload = group:AddLabel(Lang.Format("Autoload", Configs.GetAutoload() or Lang.Get("None")))
    local function Selected()
        local typed = nameInput.Value:gsub("^%s+", ""):gsub("%s+$", "")
        return typed ~= "" and typed or list.Value
    end
    local function Run(actionKey, handler)
        local name = Selected()
        if not name then
            Library:Notify(Lang.Strings.Configs, Lang.Strings.PickConfig, 3, "Warning")
            return
        end
        local ok, reason = handler(name)
        local action = Lang.Strings[actionKey]
        local message = ok and { EN = action.EN .. ": " .. name, TH = action.TH .. ": " .. name }
            or { EN = action.EN .. " failed: " .. tostring(reason), TH = action.TH .. " ไม่สำเร็จ: " .. tostring(reason) }
        Library:Notify(Lang.Strings.Configs, message, 3, ok and "Success" or "Error")
        list:SetValues(Configs.List())
    end
    group:AddButton({ Text = Lang.Strings.Save, Style = "Primary", Func = function()
        Run("Save", Configs.Save)
    end }):AddButton({ Text = Lang.Strings.Load, Style = "Success", Func = function()
        Run("Load", Configs.Load)
    end })
    group:AddButton({ Text = Lang.Strings.Delete, Style = "Danger", DoubleClick = true, Func = function()
        Run("Delete", Configs.Delete)
    end }):AddButton({ Text = Lang.Strings.Refresh, Func = function()
        list:SetValues(Configs.List())
    end })
    group:AddButton({ Text = Lang.Strings.SetAutoload, Style = "Warning", Func = function()
        Run("SetAutoload", function(name)
            local ok, reason = Configs.SetAutoload(name)
            if ok then
                autoload:SetText(Lang.Format("Autoload", name))
            end
            return ok, reason
        end)
    end })
end

function Window:AddSettingsTab()
    local tab = self:AddTab(Lang.Strings.Settings, "gear", Lang.Strings.SettingsDesc)
    local interface = tab:AddLeftGroupbox(Lang.Strings.Interface, "mushroom")
    interface:AddDropdown("NovaLanguage", {
        Text = Lang.Strings.Language,
        Values = { "English", "ไทย" },
        Default = State.Language == "TH" and "ไทย" or "English",
        Callback = function(value)
            Library:SetLanguage(value == "ไทย" and "TH" or "EN")
        end,
    })
    interface:AddDropdown("NovaTheme", { Text = Lang.Strings.ThemeName, Values = Themes.Order, Default = State.ThemeName, Callback = function(name)
        Library:SetTheme(name)
    end })
    interface:AddSlider("NovaScale", { Text = Lang.Strings.Scale, Min = Config.ScaleRange.Min * 100, Max = Config.ScaleRange.Max * 100, Default = State.UserScale * 100, Suffix = "%", Finished = true, Callback = function(value)
        self:SetScale(value / 100)
    end })
    interface:AddKeybind("NovaMenuKey", { Text = Lang.Strings.MenuKey, Default = State.MenuKey, Mode = "Always", ChangedCallback = function(name)
        State.MenuKey = name
    end })
    interface:AddToggle("NovaWatermark", { Text = Lang.Strings.Watermark, Description = Lang.Strings.WatermarkDesc, Default = Watermark.Frame ~= nil and Watermark.Frame.Visible, Callback = Watermark.SetVisible })
    interface:AddToggle("NovaParticles", { Text = Lang.Strings.Particles, Description = Lang.Strings.ParticlesDesc, Default = Particles.Enabled, Callback = Particles.SetEnabled })
    interface:AddToggle("NovaFloat", { Text = Lang.Strings.FloatButton, Description = Lang.Strings.FloatDesc, Default = Float.Button ~= nil and Float.Button.Visible, Callback = Float.SetVisible })
    local about = tab:AddLeftGroupbox(Lang.Strings.About, "star")
    about:AddLabel(string.format("%s v%s - %s", self.Title, Library.Version, self.SubTitle ~= "" and self.SubTitle or tostring(game.PlaceId)))
    about:AddLabel(Lang.Format("Device", State.Touch and "Mobile" or "PC"))
    about:AddButton({ Text = Lang.Strings.Rejoin, Func = function()
        game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
    end }):AddButton({ Text = Lang.Strings.Unload, Style = "Danger", DoubleClick = true, Func = function()
        Library:Unload()
    end })
    Configs.BuildSection(tab:AddRightGroupbox(Lang.Strings.Configs, "qblock"))
    return tab
end

function KeyGate.ReadSaved()
    if not Util.FileApi() or not Util.Exists(Config.KeyCache) then
        return nil
    end
    local ok, raw = pcall(readfile, Config.KeyCache)
    local key = ok and type(raw) == "string" and raw:gsub("%s", "") or ""
    return key ~= "" and key or nil
end

function KeyGate.Verify(settings, key)
    local ok, valid, message = pcall(settings.Verify, key)
    if not ok then
        return false, tostring(valid)
    end
    return valid == true, message
end

function KeyGate.Show(settings, onUnlocked)
    local saved = settings.SaveKey ~= false and KeyGate.ReadSaved()
    if saved and KeyGate.Verify(settings, saved) then
        onUnlocked()
        return
    end
    local dim = Draw.New("Frame", { Name = "KeyGate", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = Config.Layer.Key, Parent = State.Gui })
    Anim.Tween(dim, { BackgroundTransparency = 0.45 }, Config.Tween.Slide)
    local width = State.Touch and 300 or 360
    local card, face, scale = Popup.Card(width, 120)
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.Position = UDim2.fromScale(0.5, 0.5)
    card.Parent = dim
    scale.Scale = 0.8 * State.UserScale
    Anim.Tween(scale, { Scale = State.UserScale }, Config.Tween.Pop, "Back")
    local header = KeyGate.BuildHeader(face, settings)
    local host = Draw.New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, header), Size = UDim2.new(1, 0, 1, -header), Parent = face })
    local body = Container.New(host, { PadX = 16, PadY = 12, OnHeight = function(height)
        card.Size = UDim2.fromOffset(width + Config.Group.Shadow, header + height + Config.Group.Shadow)
    end })
    body:SetWidth(width)
    KeyGate.BuildBody(body, settings, function()
        local fade = Anim.Tween(scale, { Scale = 0.8 * State.UserScale }, 0.16, "In")
        Anim.Tween(dim, { BackgroundTransparency = 1 }, 0.2)
        fade.Completed:Once(function()
            dim:Destroy()
            if not Library.Unloaded then
                onUnlocked()
            end
        end)
    end, face)
end

function KeyGate.BuildHeader(face, settings)
    local height = 58
    local bar = Draw.Box("Frame", { Size = UDim2.new(1, 0, 0, height), Parent = face }, "Accent", nil, 12)
    Draw.Box("Frame", { Position = UDim2.new(0, 0, 1, -12), Size = UDim2.new(1, 0, 0, 12), Parent = bar }, "Accent")
    Draw.Box("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 3), Parent = bar }, "Outline")
    local block = Sprite.New(bar, "key", 36)
    block.Position = UDim2.fromOffset(14, 10)
    Anim.Tween(block, { Position = UDim2.fromOffset(14, 6) }, 0.8, "Sine", -1, true)
    local title = Draw.Text({ Position = UDim2.fromOffset(60, 0), Size = UDim2.new(1, -70, 1, -3), Parent = bar }, "Display", 24, "White", settings.Title or Lang.Strings.KeyTitle)
    Draw.Stroke(title, "Ink", 2)
    return height
end

function KeyGate.BuildBody(body, settings, onPass, face)
    body:AddLabel(settings.Note or Lang.Strings.KeyNote)
    local input = body:AddInput(nil, { Placeholder = Lang.Strings.KeyPlaceholder })
    local status
    local checking = false
    body:AddButton({ Text = Lang.Strings.GetKey, Style = "Warning", Func = function()
        local link = type(settings.Link) == "function" and settings.Link() or settings.Link
        if link and Util.Clipboard(link) then
            status:SetText(Lang.Strings.KeyCopied)
        else
            status:SetText(tostring(link or "-"))
        end
    end }):AddButton({ Text = Lang.Strings.CheckKey, Style = "Success", Func = function()
        if checking then
            return
        end
        checking = true
        status:SetText(Lang.Strings.KeyChecking)
        local key = input.Value:gsub("%s", "")
        task.spawn(function()
            local valid, message = KeyGate.Verify(settings, key)
            status:SetText(message or Lang.Strings[valid and "KeyValid" or "KeyInvalid"])
            if not valid then
                checking = false
                Anim.Shake(face)
                return
            end
            if settings.SaveKey ~= false and Util.FileApi() then
                Util.EnsureFolder(Config.Root)
                pcall(writefile, Config.KeyCache, key)
            end
            onPass()
        end)
    end })
    status = body:AddLabel("")
end

function Library:CreateWindow(options)
    options = options or {}
    local language = options.Language
    if language == "Auto" then
        language = tostring(LocalPlayer.LocaleId):sub(1, 2) == "th" and "TH" or "EN"
    end
    State.Language = language == "TH" and "TH" or "EN"
    State.UserScale = math.clamp(options.Scale or 1, Config.ScaleRange.Min, Config.ScaleRange.Max)
    Theme.Apply(options.Theme or "Nova")
    Assets.Configure(Config.DefaultAssets)
    Assets.Configure(options.Assets)
    Window.DetectTouch(options.Layout)
    Gui.Setup()
    Library:OnUnload(Compat.RestoreAll)
    task.delay(3, Compat.Warm)
    if State.Language == "TH" then
        Fonts.LoadThaiAsync()
    end
    local window = Window.New(options)
    self.Window = window
    Float.Build()
    Watermark.Build(options.WatermarkTitle or window.Title)
    Watermark.SetVisible(options.Watermark ~= false)
    Configs.SetFolder(options.ConfigFolder or window.Title)
    local function Build()
        if Library.Unloaded then
            return
        end
        Util.Try(options.OnUnlocked)
        Layout.Flush()
    end
    local function Reveal()
        if Library.Unloaded then
            return
        end
        window.Ready = true
        window:SetVisible(true)
        Library:Notify(window.Title, Lang.Format(State.Touch and "ReadyTouch" or "Ready", Keybinds.Short(State.MenuKey)), 5, "Power")
    end
    local function Open()
        if Library.Unloaded then
            return
        end
        if options.Intro == false then
            Build()
            Reveal()
            return
        end
        local built = false
        task.spawn(function()
            Build()
            built = true
        end)
        local function WaitBuilt()
            while not built and not Library.Unloaded do
                task.wait()
            end
        end
        local steps = Lang.Strings.IntroSteps
        task.spawn(Intro.Play, {
            Title = window.Title,
            SubTitle = window.SubTitle,
            Steps = {
                { Label = { EN = steps.EN[1], TH = steps.TH[1] } },
                { Label = { EN = steps.EN[2], TH = steps.TH[2] } },
                { Label = { EN = steps.EN[3], TH = steps.TH[3] }, Run = WaitBuilt },
                { Label = { EN = steps.EN[4], TH = steps.TH[4] } },
            },
            OnDone = Reveal,
        })
    end
    local keySystem = options.KeySystem
    if keySystem and keySystem.Enabled ~= false and type(keySystem.Verify) == "function" then
        KeyGate.Show(keySystem, Open)
    else
        Open()
    end
    return window
end

function Library:SetLanguage(code)
    if code ~= "EN" and code ~= "TH" then
        return
    end
    Lang.Set(code)
    local option = self.Options.NovaLanguage
    if option then
        option.Value = code == "TH" and "ไทย" or "English"
        option:Render()
    end
end

function Library:GetLanguage()
    return State.Language
end

function Library:T(english, thai)
    return { EN = english, TH = thai or english }
end

function Library:SetTheme(name)
    Theme.Apply(name)
    local option = self.Options.NovaTheme
    if option and option.Value ~= State.ThemeName then
        option.Value = State.ThemeName
        option:Render()
    end
end

function Library:SetAssets(map)
    Assets.Configure(map)
end

function Library:Notify(info, content, duration, kind)
    if type(info) == "table" and not info.EN then
        info, content, duration, kind = info.Title, info.Content or info.Description, info.Duration, info.Type or info.Icon
    end
    if self.Unloaded or not State.NotifyHost then
        return
    end
    Notify.Push(Lang.Resolve(info), content, duration, kind)
end

function Library:Toggle()
    if self.Window then
        self.Window:Toggle()
    end
end

function Library:Every(interval, callback)
    Util.Every(interval, callback)
end

function Library:SaveConfig(name)
    return Configs.Save(name)
end

function Library:LoadConfig(name)
    return Configs.Load(name)
end

function Library:LoadAutoloadConfig()
    local name = Configs.GetAutoload()
    if not name then
        return
    end
    local ok, reason = Configs.Load(name)
    local message = ok and { EN = "Autoloaded: " .. name, TH = "โหลดอัตโนมัติ: " .. name } or { EN = "Autoload failed: " .. tostring(reason), TH = "โหลดอัตโนมัติไม่สำเร็จ: " .. tostring(reason) }
    self:Notify(Lang.Strings.Configs, message, 3, ok and "Success" or "Error")
end

function Library:OnUnload(callback)
    table.insert(State.UnloadHooks, callback)
end

function Library:Unload()
    if self.Unloaded then
        return
    end
    self.Unloaded = true
    for _, callback in ipairs(State.UnloadHooks) do
        Util.Try(callback)
    end
    for _, connection in ipairs(State.Connections) do
        connection:Disconnect()
    end
    table.clear(State.Connections)
    table.clear(State.KeyPickers)
    table.clear(State.Tasks)
    table.clear(Layout.Dirty)
    State.Drag, State.Binding, State.Popup, State.Window, State.NotifyHost = nil, nil, nil, nil, nil
    if State.Gui then
        State.Gui:Destroy()
        State.Gui = nil
    end
end

Library.Themes = Themes.Order

return Library]==]

-- Embedded UI loader used by the imported game modules.
local env = (type(getgenv) == "function" and getgenv()) or _G
env.NOVA_HUB_UI_SOURCE = NOVA_HUB_UI_SOURCE

env.NOVA_HUB_NOTIFY = function(text)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {Title="Nova Hub", Text=tostring(text), Duration=7})
    end)
end

local NOVA_HUB_MODULES = {}

NOVA_HUB_MODULES[10418224975] = [==[if not game:IsLoaded() then
    game.Loaded:Wait()
end

if game.GameId ~= 10418224975 then
    game:GetService("Players").LocalPlayer:Kick("Nova Hub: this script is for TNT Mining only")
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
        "   TNT MINING  //  by xDTaraZ  //  discord.gg/FHVfmeSceA",
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
local VirtualUser = game:GetService("VirtualUser")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local vector3New, cframeNew = Vector3.new, CFrame.new
local mathMin, mathMax, mathCeil = math.min, math.max, math.ceil

local xDTaraZ = setmetatable({}, {
    __newindex = function(self, key, value)
        rawset(self, key, type(value) == "function" and LPH_JIT(value) or value)
    end,
})

xDTaraZ.Config = {
    Discord = "https://discord.gg/FHVfmeSceA",
    UpdateLog = {
        { "2026-10-03", "Classic Nova Hub UI is back\nBetter executor support\nBug fixes & better UI" },
    },
    UiSource = "NovaHub://embedded-ui",
    SaveFolder = "TNT Mining",
    LoadTimeout = 30,
    RequireTimeout = 3,
    GameCallTimeout = 8,
    MaxFailures = 5,
    FailWindow = 10,
    AlertTries = 20,
    AlertDelay = 0.5,
    TickDelay = 0.1,
    ClicksPerBatch = 25,
    ClickInterval = 1,
    ExplodeTimeout = 3,
    DropSettle = 0.35,
    IdConfirmTimeout = 3,
    SolverYieldEvery = 1500,
    HotbarSlots = 4,
    PurchaseInterval = 3,
    ClaimInterval = 60,
    HatchInterval = 1,
    MineStandOffset = 3,
    RejoinDelay = 5,
    RateWindow = 60,
    Needs = {
        AutoMine = { "Blocks", "Areas", "AreaRenderer", "Mine.Collectible", ":PlaceBomb", ":IgniteBomb", ":LeaveMine", ":CollectBlocks", ":GetBombExplosionRadius" },
        AutoSell = { ":SellBlocks" },
        AutoCollect = { "Mine.Collectible", ":CollectBlocks" },
        SecretAlert = { "Blocks" },
        AutoClick = { ":ApplyDataUpdate" },
        AutoRebirth = { "Rebirth", ":PerformRebirth" },
        AutoBomb = { "Bombs", ":BuyBomb", ":EquipBomb", ":OwnsBomb" },
        AutoUpgrade = { "Upgrades", ":BuyUpgrade" },
        AutoArea = { "Areas", ":PurchaseArea" },
        AutoLuck = { "Upgrades.MineLuck", ":BuyUpgrade" },
        AutoHatch = { "Areas", ":HatchPetEgg" },
        AutoEquipPets = { ":EquipBestPets" },
        AutoSellPets = { "Pets", ":SellPets", ":GetPetDamagePerClickMultiplier" },
        AutoClaim = { "Areas", ":IsAreaIndexComplete", ":ClaimIndexReward" },
    },
}

xDTaraZ.State = {
    Alive = true,
    Busy = false,
    NeedRefill = true,
    MineOrigin = nil,
    Connections = {},
    Requests = {},
    Messages = {},
    Failures = {},
    Halted = {},
    Status = "Idle",
    Summary = "Loading...",
    Bombs = 0,
    Earned = 0,
    LastPurchase = 0,
    LastClaim = 0,
    LastHatch = 0,
    EarnLog = {},
    SecretSeen = {},
    Opt = {
        AutoMine = false,
        MineArea = "Best",
        TargetShards = false,
        AutoSell = false,
        AutoCollect = false,
        AutoClick = false,
        AutoRebirth = false,
        AutoBomb = false,
        AutoUpgrade = false,
        Upgrades = {},
        AutoArea = false,
        AutoLuck = false,
        AutoHatch = false,
        AutoEquipPets = false,
        AutoSellPets = false,
        KeepPets = 10,
        KeepPetRarities = {},
        SecretAlert = false,
        AutoRejoin = false,
        LowGraphics = false,
        AutoClaim = false,
        SpeedOn = false,
        WalkSpeed = 60,
        InfJump = false,
    },
}

local Config, State = xDTaraZ.Config, xDTaraZ.State

xDTaraZ.GameLib = { Deferred = {} }

---Runs `fn` on a fresh thread switched to identity 2; game code that requires lazily fails from executor identities.
---@return boolean, any  pcall-style, false when the executor can't really switch or it timed out
function xDTaraZ.GameLib.RunAsGame(timeout, fn, ...)
    local args = table.pack(...)
    local box
    task.spawn(function()
        pcall(setthreadidentity, 2)
        local read, identity = pcall(getthreadidentity)
        if not (read and identity == 2) then
            box = { false, "identity switch unavailable", n = 2 }
            return
        end
        box = table.pack(pcall(fn, table.unpack(args, 1, args.n)))
    end)

    local deadline = os.clock() + timeout
    while not box and os.clock() < deadline do
        task.wait()
    end
    if not box then return false, "game call timed out" end
    return table.unpack(box, 1, box.n)
end

---@param path string  dotted path from ReplicatedStorage
---@return table?      nil when it is missing or this executor can't require it
function xDTaraZ.GameLib.Require(path)
    local module = ReplicatedStorage
    for name in path:gmatch("[^.]+") do
        module = module and module:FindFirstChild(name)
    end
    if not module then
        local root = ReplicatedStorage:FindFirstChild(path:match("^[^.]+"))
        local found = root and root:FindFirstChild(path:match("[^.]+$"), true)
        module = found and found:IsA("ModuleScript") and found or nil
    end
    if not module then
        warn("[TNTMining] missing game module", path)
        return nil
    end

    local ok, loaded = pcall(require, module)
    if ok then return loaded end
    local okAgain, again = xDTaraZ.GameLib.RunAsGame(Config.RequireTimeout, require, module)
    if okAgain then return again end
    warn("[TNTMining] require", path, loaded)
    return nil
end

---Calls a game function inline; one that hits "non-RobloxScript" moves to an identity-2 thread for good.
function xDTaraZ.GameLib.Call(fn, ...)
    local deferred = xDTaraZ.GameLib.Deferred
    if not deferred[fn] then
        local result = table.pack(pcall(fn, ...))
        if result[1] then return table.unpack(result, 2, result.n) end
        if not tostring(result[2]):find("non-RobloxScript", 1, true) then error(result[2], 0) end
        deferred[fn] = true
    end

    local result = table.pack(xDTaraZ.GameLib.RunAsGame(Config.GameCallTimeout, fn, ...))
    if not result[1] then error(result[2], 0) end
    return table.unpack(result, 2, result.n)
end

do
    ReplicatedStorage:WaitForChild("Logic", Config.LoadTimeout)
    ReplicatedStorage:WaitForChild("ClientLogic", Config.LoadTimeout)

    local GameLib = xDTaraZ.GameLib
    GameLib.Session = GameLib.Require("Logic.Classes.PlayerSession")
    GameLib.Network = GameLib.Require("Logic.Network")
    GameLib.MineState = GameLib.Require("ClientLogic.Services.MineStateService")
    GameLib.AreaRenderer = GameLib.Require("Logic.Services.AreaRenderer")
    GameLib.Blocks = GameLib.Require("Logic.Configs.BlocksConfig")
    GameLib.Bombs = GameLib.Require("Logic.Configs.BombsConfig")
    GameLib.Areas = GameLib.Require("Logic.Configs.AreasConfig")
    GameLib.Upgrades = GameLib.Require("Logic.Configs.UpgradesConfig")
    GameLib.Mine = GameLib.Require("Logic.Configs.MineConfig")
    GameLib.Rebirth = GameLib.Require("Logic.Configs.RebirthConfig")
    GameLib.Pets = GameLib.Require("Logic.Configs.PetsConfig")
    GameLib.Ready = GameLib.Session ~= nil and GameLib.Network ~= nil and GameLib.MineState ~= nil
end

local GameLib = xDTaraZ.GameLib

---@param need string  GameLib field path, or ":Method" on the player session
---@return boolean     false only when it is known to be gone
function xDTaraZ.GameLib.Has(need, session)
    local method = need:match("^:(.+)")
    if method then return session == nil or type(session[method]) == "function" end
    local node = GameLib
    for part in need:gmatch("[^.]+") do
        node = type(node) == "table" and node[part] or nil
    end
    return node ~= nil
end

---@return table  option idx -> missing needs
function xDTaraZ.GameLib.Missing()
    local ok, session = pcall(function() return GameLib.Session.GetClient() end)
    if not ok then session = nil end
    local missing = {}
    for idx, needs in pairs(Config.Needs) do
        for _, need in ipairs(needs) do
            if not xDTaraZ.GameLib.Has(need, session) then
                missing[idx] = missing[idx] or {}
                table.insert(missing[idx], need)
            end
        end
    end
    return missing
end

xDTaraZ.AreaOrder = GameLib.Areas and GameLib.Areas.GetOrderedNames() or {}

xDTaraZ.BombOrder = {}
do
    for name, bomb in pairs(GameLib.Bombs or {}) do
        if type(bomb) == "table" and not bomb.IsPremium and bomb.Price then
            table.insert(xDTaraZ.BombOrder, name)
        end
    end
    table.sort(xDTaraZ.BombOrder, function(a, b) return GameLib.Bombs[a].Price < GameLib.Bombs[b].Price end)
end

xDTaraZ.UpgradeNames = {}
do
    for name, upgrade in pairs(GameLib.Upgrades or {}) do
        if type(upgrade) == "table" and not upgrade.AreaSpecific then
            table.insert(xDTaraZ.UpgradeNames, name)
        end
    end
    table.sort(xDTaraZ.UpgradeNames, function(a, b)
        return (GameLib.Upgrades[a].LayoutOrder or 0) < (GameLib.Upgrades[b].LayoutOrder or 0)
    end)
end

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

function xDTaraZ:Session()
    return GameLib.Session.GetClient()
end

function xDTaraZ:Invoke(action, args)
    return GameLib.Network.ClientAction.Invoke({ action, args })
end

function xDTaraZ.Format(number)
    number = tonumber(number) or 0
    local tier = 1
    while number >= 1000 and tier < #SUFFIXES do
        number, tier = number / 1000, tier + 1
    end
    return tier == 1 and ("%d"):format(number) or ("%.2f%s"):format(number, SUFFIXES[tier])
end

function xDTaraZ:Notify(text)
    State.Messages[#State.Messages + 1] = text
end

function xDTaraZ:Connect(signal, handler)
    local conn = signal:Connect(handler)
    table.insert(State.Connections, conn)
    return conn
end

function xDTaraZ.Try(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then warn("[TNTMining]", err) end
    return ok, err
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
    warn("[TNTMining] menu:", text, detail or "")
    task.spawn(function()
        for _ = 1, Config.AlertTries do
            if pcall(StarterGui.SetCore, StarterGui, "SendNotification", { Title = "Nova Hub", Text = text, Duration = 10 }) then return end
            task.wait(Config.AlertDelay)
        end
    end)
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

function xDTaraZ:Root()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

function xDTaraZ:Humanoid()
    local char = LocalPlayer.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

function xDTaraZ:AreaModel(areaName)
    local map = Workspace:FindFirstChild("Map")
    local areas = map and map:FindFirstChild("Areas") or Workspace:FindFirstChild("Areas", true)
    if not areas then return nil end
    for _, area in ipairs(areas:GetChildren()) do
        if area:GetAttribute("AreaName") == areaName then return area end
    end
    return nil
end

xDTaraZ.Mine = {}

---@return string  best owned area for current damage
function xDTaraZ.Mine.PickArea(session)
    local picked = State.Opt.MineArea
    if picked ~= "Best" and session.OwnedAreas[picked] then return picked end

    local best = xDTaraZ.AreaOrder[1]
    for _, name in ipairs(xDTaraZ.AreaOrder) do
        if session.OwnedAreas[name] and session.Damage >= GameLib.Areas[name].ExplosionDamage.Start then
            best = name
        end
    end
    return best
end

---@return boolean  mine loaded
function xDTaraZ.Mine.Enter(areaName)
    local area = xDTaraZ:AreaModel(areaName)
    if not area then
        GameLib.AreaRenderer.RenderArea(areaName)
        area = xDTaraZ:AreaModel(areaName)
    end

    local mineArea = area and area:FindFirstChild("MineArea", true)
    local hrp = xDTaraZ:Root()
    if not (mineArea and hrp) then return false end

    if not State.MineOrigin and not xDTaraZ:Session():IsInMineArea() then State.MineOrigin = hrp.CFrame end
    hrp.CFrame = cframeNew(mineArea.Position + vector3New(0, mineArea.Size.Y / 2 + Config.MineStandOffset, 0))
    hrp.AssemblyLinearVelocity = Vector3.zero

    local mineState = GameLib.MineState
    local giveUp = os.clock() + 8
    repeat
        if mineState.IsLoaded() and mineState.GetAreaName() == areaName then return true end
        task.wait(0.2)
    until os.clock() > giveUp
    return false
end

function xDTaraZ.Mine.BlockValue(block, shardValue)
    if block.BlockType == "EggShard" then return shardValue end
    local info = GameLib.Blocks[block.BlockType]
    return info and info.SellValue or 0
end

---@param count number  max spots
---@return Vector3[]    best first, no overlap
function xDTaraZ.Mine.FindBatch(session, count)
    local mineState = GameLib.MineState
    local damage = session.Damage
    local radius = session:GetBombExplosionRadius(session.EquippedBomb, session.EnchantedBombs > 0)
    local reach, radiusSq = mathCeil(radius), radius * radius

    local shardValue = 0
    if State.Opt.TargetShards then
        for _, info in pairs(GameLib.Blocks) do
            shardValue = mathMax(shardValue, info.SellValue or 0)
        end
    end

    local offsets = {}
    for dx = -reach, reach do
        for dy = -reach, reach do
            for dz = -reach, reach do
                if dx * dx + dy * dy + dz * dz <= radiusSq then
                    offsets[#offsets + 1] = { dx, dy, dz }
                end
            end
        end
    end

    local scores, seen = {}, 0
    for _, block in pairs(mineState.GetBlocks()) do
        if not block.Alive then continue end

        local worth = xDTaraZ.Mine.BlockValue(block, shardValue) * mathMin(1, damage / mathMax(block.Health, 1))
        if worth > 0 then
            local gx, gy, gz = block.GridX, block.GridY, block.GridZ
            for i = 1, #offsets do
                local o = offsets[i]
                local center = mineState.GetBlockAt(gx + o[1], gy + o[2], gz + o[3])
                if center then scores[center] = (scores[center] or 0) + worth end
            end
        end

        seen += 1
        if seen % Config.SolverYieldEvery == 0 then task.wait() end
    end

    local ranked = {}
    for block, score in pairs(scores) do
        ranked[#ranked + 1] = { block, score }
    end
    table.sort(ranked, function(a, b) return a[2] > b[2] end)

    local spots, spacingSq = {}, (2 * radius) ^ 2
    for _, entry in ipairs(ranked) do
        if #spots >= count then break end

        local block, tooClose = entry[1], false
        for _, other in ipairs(spots) do
            local dx, dy, dz = block.GridX - other.GridX, block.GridY - other.GridY, block.GridZ - other.GridZ
            if dx * dx + dy * dy + dz * dz < spacingSq then
                tooClose = true
                break
            end
        end
        if not tooClose then spots[#spots + 1] = block end
    end

    for i, block in ipairs(spots) do
        spots[i] = block.Position
    end
    return spots
end

---@return string?  nil if rejected
function xDTaraZ.Mine.WaitServerId(bomb)
    local giveUp = os.clock() + Config.IdConfirmTimeout
    while os.clock() < giveUp and not bomb.IsDestroyed do
        if not tostring(bomb.Id):match("^P") then return bomb.Id end
        task.wait()
    end
    return nil
end

---@return number  drops collected
function xDTaraZ.Mine.Collect(session)
    local folder = Workspace:FindFirstChild("ClientCollectibleBlocks")
    if not folder then return 0 end

    local ids = {}
    for _, drop in ipairs(folder:GetChildren()) do
        ids[#ids + 1] = drop.Name
    end

    local batchSize = GameLib.Mine.Collectible.PickupBatchSize or 20
    local got = 0
    for first = 1, #ids, batchSize do
        local reply = session:CollectBlocks(table.move(ids, first, mathMin(first + batchSize - 1, #ids), 1, {}), false, Config.HotbarSlots)
        got += reply and reply.Collected or 0
    end
    return got
end

function xDTaraZ.Mine.Sell(session)
    local before = session.Money
    session:SellBlocks(nil)

    local gained = mathMax(session.Money - before, 0)
    State.Earned += gained
    State.EarnLog[#State.EarnLog + 1] = { os.clock(), gained }
end

---@return number  money per minute
function xDTaraZ.Mine.EarnRate()
    local log, cutoff = State.EarnLog, os.clock() - Config.RateWindow
    while log[1] and log[1][1] < cutoff do
        table.remove(log, 1)
    end

    local total = 0
    for _, entry in ipairs(log) do total += entry[2] end
    return total * 60 / Config.RateWindow
end

function xDTaraZ.Mine.ScanSecrets()
    for _, block in pairs(GameLib.MineState.GetBlocks()) do
        local info = GameLib.Blocks[block.BlockType]
        local id = block.CollectibleId
        if block.Alive and info and info.Rarity == "Secret" and not State.SecretSeen[id] then
            State.SecretSeen[id] = true
            xDTaraZ:Notify(("Secret block spawned: %s (%s)"):format(block.BlockType, xDTaraZ.Format(info.SellValue)))
        end
    end
end

---Brings the character back to where Auto Mine entered the mine from; keeps the origin while the character is respawning.
function xDTaraZ.Mine.ReturnHome()
    local origin = State.MineOrigin
    if not origin then return end

    local hrp = xDTaraZ:Root()
    if not hrp then return end

    local session = xDTaraZ:Session()
    if session:IsInMineArea() then
        session:LeaveMine()
        hrp.CFrame = origin
        hrp.AssemblyLinearVelocity = Vector3.zero
    end
    State.MineOrigin = nil
end

function xDTaraZ.Mine.Cycle()
    local session = xDTaraZ:Session()
    local areaName = xDTaraZ.Mine.PickArea(session)

    if session:GetMineAreaName() ~= areaName or GameLib.MineState.GetAreaName() ~= areaName then
        State.Status = "Entering " .. areaName
        if not xDTaraZ.Mine.Enter(areaName) then
            State.Status = "Could not enter " .. areaName
            return
        end
    end

    if State.NeedRefill or session.HeldBombs < session.MaxActiveBombs then
        State.NeedRefill = false
        xDTaraZ.Mine.Collect(session)
        session:LeaveMine()
    end

    for id, bomb in pairs(session.ActiveBombs) do
        if not bomb.IsFused and not tostring(id):match("^P") then session:IgniteBomb(id) end
    end

    State.Status = "Bombing " .. areaName
    local placed = xDTaraZ.Mine.PlaceBatch(session)
    if #placed == 0 then
        State.Status = "Resetting mine run"
        session:LeaveMine()
        task.wait(1)
        return
    end

    for _, bomb in ipairs(placed) do
        local serverId = xDTaraZ.Mine.WaitServerId(bomb)
        if serverId then
            session:IgniteBomb(serverId)
            State.Bombs += 1
        else
            State.NeedRefill = true
        end
    end

    xDTaraZ.Mine.WaitExploded(placed)
    xDTaraZ.Mine.Collect(session)
    if State.Opt.AutoSell then xDTaraZ.Mine.Sell(session) end
end

---@return table[]  placed bombs
function xDTaraZ.Mine.PlaceBatch(session)
    local placed = {}
    for _, pos in ipairs(xDTaraZ.Mine.FindBatch(session, mathMin(session.HeldBombs, session.MaxActiveBombs))) do
        local reply = session:PlaceBomb(cframeNew(pos))
        local bomb = reply and reply.Success and session.ActiveBombs[reply.Id]
        if not bomb then break end
        placed[#placed + 1] = bomb
    end
    return placed
end

function xDTaraZ.Mine.WaitExploded(bombs)
    local giveUp = os.clock() + Config.ExplodeTimeout
    local function anyLeft()
        for _, bomb in ipairs(bombs) do
            if not bomb.IsDestroyed then return true end
        end
        return false
    end

    while anyLeft() and os.clock() < giveUp do
        task.wait()
    end
    task.wait(Config.DropSettle)
end

xDTaraZ.Progress = {}

function xDTaraZ.Progress.Click()
    local reply = xDTaraZ:Invoke("ApplyClicks", { Config.ClicksPerBatch })
    if not (reply and reply.Success) then return end
    xDTaraZ:Session():ApplyDataUpdate({ Damage = reply.Damage, Level = reply.Level })
end

function xDTaraZ.Progress.StartClicking()
    task.spawn(function()
        while State.Alive and State.Opt.AutoClick do
            xDTaraZ.Scheduler.Run("AutoClick", xDTaraZ.Progress.Click)
            task.wait(Config.ClickInterval)
        end
    end)
end

---@return boolean  rebirth sent
function xDTaraZ.Progress.Rebirth()
    local session = xDTaraZ:Session()
    if session.Level < GameLib.Rebirth.GetRebirthLevelRequirement(session.Rebirths) then return false end
    session:PerformRebirth()
    return true
end

function xDTaraZ.Progress.BuyBestBomb()
    local session = xDTaraZ:Session()
    local target
    for _, name in ipairs(xDTaraZ.BombOrder) do
        if session:OwnsBomb(name) or session.Money >= GameLib.Bombs[name].Price then
            target = name
        end
    end
    if not target then return end

    if not session:OwnsBomb(target) then
        session:BuyBomb(target)
    elseif session.EquippedBomb ~= target and not session:IsPremiumBombEquipped() then
        session:EquipBomb(target)
    end
end

function xDTaraZ.Progress.BuyUpgrades()
    local session = xDTaraZ:Session()
    for _, name in ipairs(xDTaraZ.UpgradeNames) do
        if State.Opt.Upgrades[name] then session:BuyUpgrade(name) end
    end
end

function xDTaraZ.Progress.BuyLuck()
    local session = xDTaraZ:Session()
    session:BuyUpgrade("MineLuck", xDTaraZ.Mine.PickArea(session))
end

function xDTaraZ.Progress.BuyNextArea()
    local session = xDTaraZ:Session()
    for _, name in ipairs(xDTaraZ.AreaOrder) do
        if not session.OwnedAreas[name] then
            if session.Money >= GameLib.Areas[name].Price then session:PurchaseArea(name) end
            return
        end
    end
end

xDTaraZ.Pets = {}

function xDTaraZ.Pets.Hatch()
    local session = xDTaraZ:Session()
    local egg
    for _, name in ipairs(xDTaraZ.AreaOrder) do
        local price = GameLib.Areas[name].PetEggPrice
        if price and session.OwnedAreas[name] and session.EggShards >= price then egg = name end
    end
    if egg then session:HatchPetEgg(egg) end
end

function xDTaraZ.Pets.EquipBest()
    local session = xDTaraZ:Session()
    GameLib.Call(session.EquipBestPets, session)
end

---@return number  pets sold
function xDTaraZ.Pets.SellExtras()
    local session = xDTaraZ:Session()
    local keepRarity = State.Opt.KeepPetRarities

    local equipped = {}
    for _, id in ipairs(session.EquippedPets or {}) do equipped[id] = true end

    local pool = {}
    for id, petName in pairs(session.OwnedPets) do
        local info = GameLib.Pets[petName]
        if not equipped[id] and not (info and keepRarity[info.Rarity]) then
            pool[#pool + 1] = { id, session:GetPetDamagePerClickMultiplier(id) }
        end
    end
    table.sort(pool, function(a, b) return a[2] > b[2] end)

    local sell = {}
    for i = State.Opt.KeepPets + 1, #pool do
        sell[#sell + 1] = pool[i][1]
    end
    if #sell > 0 then session:SellPets(sell) end
    return #sell
end

xDTaraZ.Claim = {}

function xDTaraZ.Claim.All()
    local session = xDTaraZ:Session()
    pcall(session.ClaimDailyReward, session)
    pcall(session.ClaimGroupReward, session)

    for _, name in ipairs(xDTaraZ.AreaOrder) do
        if not session.ClaimedIndexRewards[name] and session:IsAreaIndexComplete(name) then
            session:ClaimIndexReward(name)
        end
    end
end

xDTaraZ.Client = {}

function xDTaraZ.Client.SetLowGraphics(enabled)
    RunService:Set3dRenderingEnabled(not enabled)
end

function xDTaraZ.Client.Bind()
    xDTaraZ:Connect(GuiService.ErrorMessageChanged, function(msg)
        if not State.Opt.AutoRejoin or msg == "" then return end
        task.delay(Config.RejoinDelay, TeleportService.Teleport, TeleportService, game.PlaceId, LocalPlayer)
    end)
end

xDTaraZ.Movement = {}

function xDTaraZ.Movement.Apply()
    local hum = xDTaraZ:Humanoid()
    if not hum then return end
    hum.WalkSpeed = State.Opt.SpeedOn and State.Opt.WalkSpeed or xDTaraZ:Session():GetUpgradeValue("WalkSpeed")
end

function xDTaraZ.Movement.Bind()
    xDTaraZ:Connect(UserInputService.JumpRequest, function()
        local hum = xDTaraZ:Humanoid()
        if State.Opt.InfJump and hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end)

    xDTaraZ:Connect(LocalPlayer.CharacterAdded, function()
        task.wait(1)
        if State.Opt.SpeedOn then State.Requests.Speed = true end
    end)

    xDTaraZ:Connect(LocalPlayer.Idled, function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.zero)
    end)
end

xDTaraZ.Scheduler = {}

xDTaraZ.Scheduler.RequestHandlers = {
    Speed = xDTaraZ.Movement.Apply,
    BombNow = xDTaraZ.Progress.BuyBestBomb,
    UpgradeNow = xDTaraZ.Progress.BuyUpgrades,
    AreaNow = xDTaraZ.Progress.BuyNextArea,
    LuckNow = xDTaraZ.Progress.BuyLuck,
    HatchNow = xDTaraZ.Pets.Hatch,
    ClaimNow = xDTaraZ.Claim.All,
    EquipPetsNow = xDTaraZ.Pets.EquipBest,

    SellNow = function()
        local session = xDTaraZ:Session()
        xDTaraZ.Mine.Collect(session)
        xDTaraZ.Mine.Sell(session)
        xDTaraZ:Notify("Sold all blocks")
    end,
    RebirthNow = function()
        xDTaraZ:Notify(xDTaraZ.Progress.Rebirth() and "Rebirthed" or "Level too low to rebirth")
    end,
    SellPetsNow = function()
        xDTaraZ:Notify(("Sold %d pets"):format(xDTaraZ.Pets.SellExtras()))
    end,
    CollectNow = function()
        xDTaraZ:Notify(("Collected %d drops"):format(xDTaraZ.Mine.Collect(xDTaraZ:Session())))
    end,
}

---Runs one round of a job; a toggle that keeps failing for Config.FailWindow seconds is switched off and queued for the UI to report.
---@param key string  State.Opt flag of the feature, or a plain label for jobs without one
function xDTaraZ.Scheduler.Run(key, fn)
    local ok, err = pcall(fn)
    local failures = State.Failures
    if ok then
        failures[key] = nil
        return
    end

    local streak = failures[key]
    if not streak then
        streak = { count = 0, since = os.clock() }
        failures[key] = streak
        warn("[TNTMining]", key, err)
    end
    streak.count += 1
    if streak.count < Config.MaxFailures or os.clock() - streak.since < Config.FailWindow then return end
    if State.Opt[key] ~= true then return end

    failures[key] = nil
    State.Opt[key] = false
    local reason = tostring(err):match("[^\n]*")
    warn("[TNTMining]", key, "stopped:", reason)
    table.insert(State.Halted, { key, reason })
end

---@param key string  State field holding last run time
---@return boolean    true once per interval
function xDTaraZ.Scheduler.Due(key, interval)
    local now = os.clock()
    if now - State[key] < interval then return false end
    State[key] = now
    return true
end

function xDTaraZ.Scheduler.Request(name, handler)
    local ok, err = pcall(handler)
    if ok then return end
    warn("[TNTMining]", name, err)
    xDTaraZ:Notify(("%s failed: %s"):format(name, tostring(err):match("[^\n]*")))
end

function xDTaraZ.Scheduler.Summarize()
    local session = xDTaraZ:Session()
    local fmt = xDTaraZ.Format
    State.Summary = ("Level %d · Rebirth %d · Damage %s\nMoney %s · Shards %d\nMoney/min %s"):format(
        session.Level, session.Rebirths, fmt(session.Damage),
        fmt(session.Money), session.EggShards,
        fmt(xDTaraZ.Mine.EarnRate()))
end

xDTaraZ.Scheduler.PurchaseJobs = {
    { "AutoBomb", xDTaraZ.Progress.BuyBestBomb },
    { "AutoUpgrade", xDTaraZ.Progress.BuyUpgrades },
    { "AutoArea", xDTaraZ.Progress.BuyNextArea },
    { "AutoLuck", xDTaraZ.Progress.BuyLuck },
    { "AutoEquipPets", xDTaraZ.Pets.EquipBest },
    { "AutoSellPets", xDTaraZ.Pets.SellExtras },
    { "SecretAlert", function()
        if GameLib.MineState.IsLoaded() then xDTaraZ.Mine.ScanSecrets() end
    end },
}

function xDTaraZ.Scheduler.Purchases()
    for _, job in ipairs(xDTaraZ.Scheduler.PurchaseJobs) do
        if State.Opt[job[1]] then xDTaraZ.Scheduler.Run(job[1], job[2]) end
    end
end

function xDTaraZ.Scheduler.CollectDrops()
    xDTaraZ.Mine.Collect(xDTaraZ:Session())
end

function xDTaraZ.Scheduler.Step()
    local opt = State.Opt
    xDTaraZ.Scheduler.Run("Summary", xDTaraZ.Scheduler.Summarize)

    for name, handler in pairs(xDTaraZ.Scheduler.RequestHandlers) do
        if State.Requests[name] then
            State.Requests[name] = nil
            xDTaraZ.Scheduler.Request(name, handler)
        end
    end

    if opt.AutoRebirth then xDTaraZ.Scheduler.Run("AutoRebirth", xDTaraZ.Progress.Rebirth) end
    if xDTaraZ.Scheduler.Due("LastPurchase", Config.PurchaseInterval) then xDTaraZ.Scheduler.Purchases() end
    if opt.AutoHatch and xDTaraZ.Scheduler.Due("LastHatch", Config.HatchInterval) then xDTaraZ.Scheduler.Run("AutoHatch", xDTaraZ.Pets.Hatch) end
    if opt.AutoClaim and xDTaraZ.Scheduler.Due("LastClaim", Config.ClaimInterval) then xDTaraZ.Scheduler.Run("AutoClaim", xDTaraZ.Claim.All) end

    if opt.AutoMine then
        xDTaraZ.Scheduler.Run("AutoMine", xDTaraZ.Mine.Cycle)
        return
    end

    if State.MineOrigin then xDTaraZ.Scheduler.Run("MineReturn", xDTaraZ.Mine.ReturnHome) end

    State.Status = "Idle"
    if opt.AutoCollect then xDTaraZ.Scheduler.Run("AutoCollect", xDTaraZ.Scheduler.CollectDrops) end
end

function xDTaraZ.Scheduler.Boot()
    xDTaraZ.Movement.Bind()
    xDTaraZ.Client.Bind()

    task.spawn(function()
        while State.Alive do
            if not State.Busy then
                State.Busy = true
                xDTaraZ.Scheduler.Step()
                State.Busy = false
            end
            task.wait(Config.TickDelay)
        end

        if State.MineOrigin then xDTaraZ.Scheduler.Run("MineReturn", xDTaraZ.Mine.ReturnHome) end
    end)
end

function xDTaraZ.Scheduler.Stop()
    State.Alive = false
    State.Opt.AutoClick = false

    for _, conn in ipairs(State.Connections) do conn:Disconnect() end
    table.clear(State.Connections)

    if State.Opt.LowGraphics then xDTaraZ.Client.SetLowGraphics(false) end

    local hum = xDTaraZ:Humanoid()
    if hum and State.Opt.SpeedOn and GameLib.Upgrades and GameLib.Upgrades.WalkSpeed then hum.WalkSpeed = GameLib.Upgrades.WalkSpeed.BaseValue end
end

local function BuildInterface()
    local Library = xDTaraZ.Util.LoadLibrary()
    if not Library then return end
    pcall(NovaBanner.Step, "UI library")
    local Options = Library.Options
    local T = function(en, th) return Library:T(en, th) end
    local opt = State.Opt

    local kaitunKeys = { "AutoMine", "AutoSell", "AutoClick", "AutoRebirth", "AutoBomb", "AutoUpgrade", "AutoArea", "AutoLuck", "AutoClaim", "AutoHatch", "AutoEquipPets", "AutoSellPets" }
    local featureNames = {}

    local function Notify(text, kind)
        Library:Notify("TNT Mining", text, 4, kind or "Info")
    end

    local function ReportHalts()
        for _, halt in ipairs(State.Halted) do
            local key, reason = halt[1], halt[2]
            local toggle = Options[key]
            if toggle and toggle.Value then toggle:SetValue(false) end

            local name = featureNames[key]
            Notify(("%s stopped: %s"):format(name and name.EN or key, reason), "Warning")
        end
        table.clear(State.Halted)
    end

    local function BlockWithoutGameData()
        if GameLib.Ready then return end
        local reason = T("Not available on this executor", "ใช้กับ executor นี้ไม่ได้")
        for _, key in ipairs({ "Kaitun", "AutoCollect", "SecretAlert", table.unpack(kaitunKeys) }) do
            Library.Compat.Block(key, reason)
        end
        Library:Notify("TNT Mining", "This executor can't read the game's data, so farming is off. Movement still works.", 10, "Error")
    end

    local function BlockMissing()
        if not GameLib.Ready then return end
        for idx, needs in pairs(xDTaraZ.GameLib.Missing()) do
            warn("[TNTMining]", idx, "blocked, missing:", table.concat(needs, ", "))
            Library.Compat.Block(idx, T("Not available after a game update", "ใช้ไม่ได้หลังเกมอัปเดต"))
        end
    end

    local function Request(name)
        return function()
            State.Requests[name] = true
        end
    end

    local function Toggle(group, key, text, description, onChange)
        featureNames[key] = text
        return group:AddToggle(key, {
            Text = text,
            Description = description,
            Default = opt[key],
            Callback = function(value)
                opt[key] = value
                if onChange then onChange(value) end
            end,
        })
    end

    local function Feature(group, key, text, description, onChange)
        return Toggle(group, key, text, description, onChange):AddKeyPicker(key .. "Key", { Default = "None", Mode = "Toggle" })
    end

    local function BuildMain(window)
        window:AddTabSection(T("Farm", "ฟาร์ม"))
        local tab = window:AddTab(T("Main", "หลัก"), "house", T("Status and all-in-one mode", "สถานะและโหมดทำทุกอย่าง"))

        local statusBox = tab:AddLeftGroupbox(T("Status", "สถานะ"))
        local statusLabel = statusBox:AddLabel("Loading...")
        local runLabel = statusBox:AddLabel("-")

        local kaitunBox = tab:AddRightGroupbox("Kaitun")
        kaitunBox:AddToggle("Kaitun", {
            Text = T("Kaitun (All-in-one)", "ไก่ตัน (ทำทุกอย่าง)"),
            Description = T("Mines, sells, trains, buys bombs, upgrades and areas, and rebirths by itself", "ขุด ขาย ฝึก ซื้อระเบิด อัปเกรด พื้นที่ และรีเบิร์ธให้เองทั้งหมด"),
            NoSave = true,
            Callback = function(value)
                for _, key in ipairs(kaitunKeys) do
                    if Options[key] then Options[key]:SetValue(value) end
                end
            end,
        })

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

        return { Summary = statusLabel, Run = runLabel }
    end

    local function BuildMining(window)
        local tab = window:AddTab(T("Mining", "ขุด"), "bomb", T("Auto mining and selling", "ขุดและขายอัตโนมัติ"))

        local mineBox = tab:AddLeftGroupbox(T("Auto Mine", "ขุดอัตโนมัติ"), "bomb")
        Feature(mineBox, "AutoMine", T("Auto Mine", "ขุดอัตโนมัติ"), T("Blasts the most valuable spots in the mine and picks up every drop", "ระเบิดจุดที่มีค่าที่สุดในเหมืองแล้วเก็บของดรอปทั้งหมด"))
        local areaChoices = { "Best" }
        for _, areaName in ipairs(xDTaraZ.AreaOrder) do table.insert(areaChoices, areaName) end
        mineBox:AddDropdown("MineArea", {
            Text = T("Mine Area", "พื้นที่ขุด"),
            Description = T("Best = strongest area your damage can handle", "Best = พื้นที่ดีสุดที่ดาเมจตอนนี้ขุดไหว"),
            Values = areaChoices,
            Default = 1,
            Searchable = true,
            Callback = function(value) opt.MineArea = value or "Best" end,
        })
        Toggle(mineBox, "SecretAlert", T("Secret Block Alert", "แจ้งเตือนบล็อก Secret"), T("Notifies you when a secret block spawns in your mine", "แจ้งเมื่อมีบล็อก Secret เกิดในเหมือง"))
        Toggle(mineBox, "TargetShards", T("Prioritize Egg Shards", "เน้นเศษไข่"), T("Goes for egg shards first", "ไล่เก็บเศษไข่ก่อน"))

        local sellBox = tab:AddRightGroupbox(T("Sell", "ขาย"), "coin")
        Feature(sellBox, "AutoSell", T("Auto Sell", "ขายอัตโนมัติ"), T("Sells blocks right after every blast, from anywhere. Favorited blocks are kept", "ขายบล็อกทันทีหลังระเบิดทุกครั้ง ขายได้จากทุกที่ บล็อกที่กดชอบจะเก็บไว้"))
        sellBox:AddButton({ Text = T("Sell All Now", "ขายทั้งหมดเดี๋ยวนี้"), Style = "Primary", Func = Request("SellNow") })

        local dropBox = tab:AddRightGroupbox(T("Drops", "ของดรอป"), "bomb")
        featureNames.AutoCollect = T("Auto Collect", "เก็บของอัตโนมัติ")
        dropBox:AddToggle("AutoCollect", {
            Text = featureNames.AutoCollect,
            Description = T("Instantly picks up every drop in the mine from anywhere, even when you bomb by hand", "เก็บของดรอปทั้งเหมืองทันทีจากทุกที่ แม้วางระเบิดเอง"),
            Risky = true,
            Default = false,
            Callback = function(value) opt.AutoCollect = value end,
        }):AddKeyPicker("AutoCollectKey", { Default = "None", Mode = "Toggle" })
        dropBox:AddButton({ Text = T("Collect Drops Now", "เก็บของดรอปเดี๋ยวนี้"), Func = Request("CollectNow") })
    end

    local function BuildUpgrades(window)
        window:AddTabSection(T("Progress", "ความคืบหน้า"))
        local tab = window:AddTab(T("Upgrades", "อัปเกรด"), "sliders-horizontal", T("Bombs, upgrades, areas and rebirth", "ระเบิด อัปเกรด พื้นที่ และรีเบิร์ธ"))

        local trainBox = tab:AddLeftGroupbox(T("Damage & Rebirth", "ดาเมจและรีเบิร์ธ"), "star")
        Feature(trainBox, "AutoClick", T("Auto Click", "คลิกอัตโนมัติ"), T("Trains damage at the fastest speed the game allows", "เพิ่มดาเมจเร็วสุดเท่าที่เกมยอม"), function(value)
            if value then xDTaraZ.Progress.StartClicking() end
        end)
        Feature(trainBox, "AutoRebirth", T("Auto Rebirth", "รีเบิร์ธอัตโนมัติ"), T("Rebirths as soon as your level is high enough", "รีเบิร์ธทันทีเมื่อเลเวลถึง"))
        trainBox:AddButton({ Text = T("Rebirth Now", "รีเบิร์ธเดี๋ยวนี้"), Func = Request("RebirthNow") })

        local shopBox = tab:AddRightGroupbox(T("Shop", "ร้านค้า"), "shop")
        Feature(shopBox, "AutoBomb", T("Auto Buy Best Bomb", "ซื้อระเบิดดีสุดอัตโนมัติ"), T("Buys and equips the strongest bomb you can afford", "ซื้อและใส่ระเบิดที่แรงที่สุดที่ซื้อไหว"))
        shopBox:AddButton({ Text = T("Buy Best Bomb Now", "ซื้อระเบิดดีสุดเดี๋ยวนี้"), Func = Request("BombNow") })
        Feature(shopBox, "AutoArea", T("Auto Buy Next Area", "ซื้อพื้นที่ถัดไปอัตโนมัติ"), T("Unlocks the next area when you have the money", "ปลดล็อกพื้นที่ถัดไปเมื่อเงินพอ"))
        shopBox:AddButton({ Text = T("Buy Next Area Now", "ซื้อพื้นที่ถัดไปเดี๋ยวนี้"), Func = Request("AreaNow") })
        Feature(shopBox, "AutoLuck", T("Auto Buy Mine Luck", "ซื้อโชคเหมืองอัตโนมัติ"), T("Upgrades luck for the area you mine", "อัปโชคของพื้นที่ที่กำลังขุด"))
        shopBox:AddButton({ Text = T("Buy Mine Luck Now", "ซื้อโชคเหมืองเดี๋ยวนี้"), Func = Request("LuckNow") })

        local upgradeBox = tab:AddLeftGroupbox(T("Upgrades", "อัปเกรด"), "gear")
        local upgradeDefault = {}
        opt.Upgrades = {}
        for _, name in ipairs({ "MaxHeldBombs", "MaxActiveBombs" }) do
            if GameLib.Upgrades and GameLib.Upgrades[name] then
                table.insert(upgradeDefault, name)
                opt.Upgrades[name] = true
            end
        end
        upgradeBox:AddDropdown("Upgrades", {
            Text = T("Upgrades To Buy", "อัปเกรดที่จะซื้อ"),
            Values = xDTaraZ.UpgradeNames,
            Multi = true,
            Default = upgradeDefault,
            Callback = function(selected) opt.Upgrades = selected end,
        })
        Feature(upgradeBox, "AutoUpgrade", T("Auto Buy Upgrades", "ซื้ออัปเกรดอัตโนมัติ"), T("Buys the selected upgrades whenever possible", "ซื้ออัปเกรดที่เลือกทุกครั้งที่ซื้อได้"))
        upgradeBox:AddButton({ Text = T("Buy Upgrades Now", "ซื้ออัปเกรดเดี๋ยวนี้"), Func = Request("UpgradeNow") })
    end

    local function BuildPets(window)
        local tab = window:AddTab(T("Pets & Rewards", "สัตว์เลี้ยงและรางวัล"), "star", T("Eggs, pets and free rewards", "ไข่ สัตว์เลี้ยง และรางวัลฟรี"))

        local hatchBox = tab:AddLeftGroupbox(T("Eggs", "ไข่"), "mushroom")
        Feature(hatchBox, "AutoHatch", T("Auto Hatch", "ฟักไข่อัตโนมัติ"), T("Hatches the best egg you can afford with egg shards", "ฟักไข่ที่ดีที่สุดที่เศษไข่พอ"))
        hatchBox:AddButton({ Text = T("Hatch Now", "ฟักเดี๋ยวนี้"), Func = Request("HatchNow") })

        local petBox = tab:AddLeftGroupbox(T("Pets", "สัตว์เลี้ยง"), "mushroom")
        Feature(petBox, "AutoEquipPets", T("Auto Equip Best Pets", "ใส่สัตว์เลี้ยงดีสุดอัตโนมัติ"), T("Always uses your strongest pets", "ใช้สัตว์เลี้ยงที่แรงที่สุดเสมอ"))
        petBox:AddButton({ Text = T("Equip Best Pets Now", "ใส่สัตว์เลี้ยงดีสุดเดี๋ยวนี้"), Func = Request("EquipPetsNow") })

        local petSellBox = tab:AddRightGroupbox(T("Sell Pets", "ขายสัตว์เลี้ยง"), "coin")
        Feature(petSellBox, "AutoSellPets", T("Auto Sell Pets", "ขายสัตว์เลี้ยงอัตโนมัติ"), T("Keeps your strongest pets and sells the rest so hatching never stops", "เก็บตัวที่แรงที่สุดไว้ ขายที่เหลือ ฟักไข่ได้ไม่มีวันเต็ม"))
        petSellBox:AddSlider("KeepPets", {
            Text = T("Keep Best Pets", "จำนวนตัวดีสุดที่เก็บไว้"),
            Min = 0, Max = 50, Default = opt.KeepPets, Rounding = 0,
            Callback = function(value) opt.KeepPets = tonumber(value) or opt.KeepPets end,
        })

        local rarityTable = GameLib.Pets and GameLib.Pets.Rarities or {}
        local petRarities = {}
        for rarity in pairs(rarityTable) do table.insert(petRarities, rarity) end
        table.sort(petRarities, function(a, b) return rarityTable[a].Weight > rarityTable[b].Weight end)
        petSellBox:AddDropdown("KeepPetRarities", {
            Text = T("Never Sell Rarity", "rarity ที่ห้ามขาย"),
            Values = petRarities,
            Multi = true,
            Default = {},
            Callback = function(selected) opt.KeepPetRarities = selected end,
        })
        petSellBox:AddButton({ Text = T("Sell Extra Pets Now", "ขายสัตว์เลี้ยงส่วนเกินเดี๋ยวนี้"), Func = Request("SellPetsNow") })

        local rewardBox = tab:AddRightGroupbox(T("Rewards", "รางวัล"), "flag")
        Feature(rewardBox, "AutoClaim", T("Auto Claim", "รับรางวัลอัตโนมัติ"), T("Claims daily, group and index rewards", "รับรางวัลรายวัน กลุ่ม และสมุดสะสม"))
        rewardBox:AddButton({ Text = T("Claim Now", "รับเดี๋ยวนี้"), Func = Request("ClaimNow") })
    end

    local function BuildPlayer(window)
        window:AddTabSection(T("Other", "อื่นๆ"))
        local tab = window:AddTab(T("Player", "ผู้เล่น"), "user", T("Movement", "การเคลื่อนที่"))

        local moveBox = tab:AddLeftGroupbox(T("Movement", "การเคลื่อนที่"), "star")
        Feature(moveBox, "SpeedOn", T("Speed", "ความเร็ว"), nil, Request("Speed"))
        moveBox:AddSlider("WalkSpeed", {
            Text = T("Walk Speed", "ความเร็วเดิน"),
            Min = 16, Max = 200, Default = opt.WalkSpeed, Rounding = 0,
            Callback = function(value)
                opt.WalkSpeed = tonumber(value) or opt.WalkSpeed
                State.Requests.Speed = true
            end,
        })

        local jumpBox = tab:AddRightGroupbox(T("Jump", "กระโดด"), "star")
        Feature(jumpBox, "InfJump", T("Infinite Jump", "กระโดดไม่จำกัด"))
    end

    local function BuildSettings(window)
        local tab = window:AddSettingsTab()
        local sessionBox = tab:AddRightGroupbox(T("Session", "เซสชัน"), "gear")
        Toggle(sessionBox, "AutoRejoin", T("Auto Rejoin", "เข้าเกมใหม่อัตโนมัติ"), T("Rejoins by itself after a disconnect", "หลุดแล้วเข้าเกมใหม่เอง"))
        Toggle(sessionBox, "LowGraphics", T("FPS Boost", "เพิ่ม FPS"), T("Turns off 3D rendering to save CPU and GPU", "ปิดการแสดงผล 3D ประหยัด CPU/GPU"), xDTaraZ.Client.SetLowGraphics)
    end

    local function BuildTabs()
        local window = Library.Window
        local _, labels = xDTaraZ.Try(BuildMain, window)
        for _, build in ipairs({ BuildMining, BuildUpgrades, BuildPets, BuildPlayer, BuildSettings }) do
            xDTaraZ.Try(build, window)
        end
        xDTaraZ.Try(BlockWithoutGameData)
        xDTaraZ.Try(BlockMissing)

        Library:Every(1, function()
            ReportHalts()
            while #State.Messages > 0 do
                Notify(table.remove(State.Messages, 1))
            end
            if type(labels) ~= "table" then return end
            labels.Summary:SetText(State.Summary)
            labels.Run:SetText(("%s\nBombs %d · Earned %s"):format(State.Status, State.Bombs, xDTaraZ.Format(State.Earned)))
        end)
    end

    Library:OnUnload(xDTaraZ.Scheduler.Stop)
    local function UnloadHub()
        Library:Unload()
    end
    getgenv().TNTMiningUnload = UnloadHub
    Library:OnUnload(function()
        if getgenv().TNTMiningUnload == UnloadHub then getgenv().TNTMiningUnload = nil end
    end)

    Library:CreateWindow({
        Title = "Nova Hub",
        SubTitle = "TNT Mining by xDTaraZ",
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

if getgenv().TNTMiningUnload then
    pcall(getgenv().TNTMiningUnload)
end

pcall(NovaBanner.Step, "Systems")
BuildInterface()
pcall(NovaBanner.Step, "Interface")
pcall(NovaBanner.Ready)]==]

NOVA_HUB_MODULES[10684750879] = [==[if not game:IsLoaded() then
    game.Loaded:Wait()
end

if game.GameId ~= 10684750879 then
    game:GetService("Players").LocalPlayer:Kick("Nova Hub: this script is for Loot To Forge only")
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
        "   LOOT TO FORGE  //  by xDTaraZ  //  discord.gg/FHVfmeSceA",
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
local VirtualUser = game:GetService("VirtualUser")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer

local xDTaraZ = setmetatable({}, {
    __newindex = function(self, key, value)
        rawset(self, key, type(value) == "function" and LPH_JIT(value) or value)
    end,
})

xDTaraZ.Config = {
    SaveFolder = "Loot To Forge",
    Discord = "https://discord.gg/FHVfmeSceA",
    UpdateLog = {
        { "2026-10-06", "Updated for the new game version\nSpawn Items now lists only items that still work (ores and runes)\nDupe Whole Inventory skips items the game no longer allows" },
        { "2026-10-04", "Spawn Scrolls, Tickets & Stones\nDupe Whole Inventory\nAdd Season Coins (OP)\nFaster Tower farm\nRemoved keybinds from auto features\nMax Gear picks Exclusive gear\nSpawn Gear (OP)\nPotions (OP)\nFixed Auto World Boss\nBoss Server Hop\nAuto Sell keeps your best base gear\nMax Gear now goes to +20, much faster\nFixed freeze when loading the script\nUpdated for the new game version\nAuto Sell keeps items you locked\nSteadier Boss Server Hop" },
    },
    UiSource = "NovaHub://embedded-ui",
    ReloadSource = [[
if not game:IsLoaded() then game.Loaded:Wait() end
task.wait(2)
local url = "NovaHub://embedded-loader"
local ok, body = pcall(game.HttpGet, game, url)
if not (ok and type(body) == "string") then
    local requester = request or http_request or (syn and syn.request) or (http and http.request)
    local sent, reply = pcall(requester, { Url = url, Method = "GET" })
    body = sent and type(reply) == "table" and reply.Body
end
if type(body) == "string" then loadstring(body)() end]],
    LoadTimeout = 30,
    RemoteTimeout = 10,
    RequireTimeout = 3,
    MaxFailures = 5,
    FailWindow = 10,
    AlertTries = 20,
    AlertDelay = 0.5,
    TickDelay = 0.2,
    StatusInterval = 2,
    PumpInterval = 0.25,
    RefillAmount = 100000,
    OwnedOresLabel = "Owned ores",
    AcquireRounds = 300,
    StoneWorkers = 8,
    StoneCallsPerWorker = 15,
    TowerWorkers = 128,
    CoinFarmTimeout = 600,
    PotionStack = 100000,
    TowerCallsPerWorker = 25,
    GearForgeTries = 15,
    GearEnhanceTries = 2,
    GearEnhanceWorkers = 8,
    SlotEnhanceRounds = 200,
    ClickInterval = 0.16,
    ForgeTargets = {
        { name = "Great Weapon", forgeType = "Weapon", ores = 13 },
        { name = "Katana", forgeType = "Weapon", ores = 4 },
        { name = "Armor", forgeType = "Armor", ores = 11 },
        { name = "Hat", forgeType = "Armor", ores = 4 },
    },
    GearSlots = {
        { slot = "Weapon", forgeType = "Weapon", ores = 13 },
        { slot = "Armor", forgeType = "Armor", ores = 11 },
        { slot = "Hat", forgeType = "Armor", ores = 4 },
    },
    GearTypes = { "Weapon", "Armor", "Hat" },
    EnchantPriority = { "Poison_3", "Thunder_3", "Ice_3", "Fire_3", "Poison_2", "Thunder_2", "Ice_2", "Fire_2" },
    RuneMinTier = 2,
    EnchantRefill = 50,
    ForgeCountMax = 30,
    PlanSlice = 0.004,
    HuntBatch = 40,
    HuntWorkers = 4,
    HuntMaxForges = 4000,
    HuntTargetHits = 3,
    IndexInterval = 60,
    IndexLevelClaims = 50,
    ClaimIdScan = 20,
    ClaimInterval = 30,
    SeasonInterval = 60,
    BossCards = 8,
    BossAttackIds = { Katana = "K_ATK_1", Great = "G_ATK_1" },
    BossHitsPerTick = 30,
    BossHitGap = 0.02,
    BossJoinSettle = 1,
    BossClaimDelay = 3.5,
    BossStandHeight = 3,
    BossStandBack = 8,
    BossReach = 25,
    UpgradeInterval = 5,
    EquipInterval = 3,
    SellInterval = 1,
    RebirthInterval = 2,
    BossInterval = 1,
    BossHopInterval = 5,
    BossHopLead = 150,
    BossHopAfter = 8,
    BossHopFlag = "bosshop.txt",
    BossHopResume = 180,
    BossHopServers = "bossservers.json",
    HopListTtl = 120,
    HopBackoffStart = 5,
    HopBackoffMax = 60,
    HopGiveUp = 8,
    HopStall = 30,
    HopGap = 15,
    TrainRejoinDelay = 0.3,
    TrainWatchdog = 3,
    TrainAcceptWait = 1.5,
    TrainExitTries = 3,
    TrainSettle = 0.5,
    WarnCooldown = 30,
    WarnMemory = 64,
    KillAuraInterval = 0.25,
    KillDamage = 1e30,
    RaceRollDelay = 0.45,
    RejoinDelay = 5,
    CodeReplyWait = 1.5,
    Codes = { "100000CCU", "50000CCU", "30000CCU", "20000CCU" },
    Needs = {
        CollectOre = { "Remote.Stage.StageFinishedRF", "Remote.Stage.GetOreRF", "Remote.Stage.ClaimedAllOreRE", "Config.Stage.Helper", "Config.Ore.Config" },
        SuperLootAura = { "Remote.SuperLoot.KillSuperLootRE", "Remote.SuperLoot.RefreshSuperLootRE", "Remote.Stage.GetOreRF" },
        AutoWorldBoss = { "Remote.WorldBoss.IntoWorldBossFight", "Remote.WorldBoss.ExitWorldBossFight", "Remote.WorldBoss.BossDeadRE", "Remote.Attack.UseAnyATKRE", "Remote.Attack.AttackEnemyServiceRE" },
        AutoIndex = { "Remote.Forge.ForgeRF", "Remote.Index.TryClaimIndexExpRF", "Utils.ForgeUtils", "Config.Weapon.Config", "Config.Armor.Config" },
        MaxGear = { "Utils.BalanceUtils", "Remote.Forge.ForgeRF", "Remote.Backpack.EnhantEquipmentRF", "Remote.Backpack.EnchantRE", "Config.Enhant.Config", "Config.EnchStone.Show" },
        AutoEquip = { "Utils.BalanceUtils", "Remote.Backpack.TryEquipItemRE", "Config.Weapon.Helper", "Config.Armor.Helper" },
        AutoForge = { "Remote.Forge.ForgeRF", "Remote.Backpack.TrySellItemRE", "Config.Ore.Config" },
        AutoSell = { "Remote.Backpack.TrySellItemRE", "Config.Weapon.Config", "Config.Armor.Config" },
        AutoTrain = { "Remote.Train.IntoAutoTrainRE", "Remote.Train.ExitAutoTrainRE", "Config.TrainArea.Config" },
        AutoRebirth = { "Remote.Rebirth.TryRebirthRE", "Config.Rebirth.Helper" },
        AutoUpgrade = { "Remote.Upgrade.UpgradeOnceRE", "Config.Upgrade.Config" },
        AutoTower = { "Remote.Dungeon.TryIntoDungeonRF", "Remote.Dungeon.StartRoundRE", "Remote.Dungeon.CompleteRoundRF", "Config.Dungeon.Config.LootTab" },
        AutoSeason = { "Remote.Season.TryClaimDailyTicRE", "Remote.Season.ExchangeGoodsRE", "Remote.Season.LuckRE", "Config.Season.GoodsConfig" },
        AutoClaim = { "Remote.Offline.TryClaimOfflineRewardRE", "Remote.Online.TryClaimRE" },
        AutoRace = { "Remote.Class.LuckOnceRE", "Config.Class.Config" },
        AutoBestRace = { "Remote.Class.ChangeEquipedIndexRE", "Config.Class.Config" },
        KeepOre = { "Remote.Stage.LostAllOreRF" },
    },
    KaitunToggles = { "MaxGear", "AutoEquip", "AutoForge", "AutoSell", "AutoTrain", "AutoRebirth", "AutoUpgrade", "AutoClaim", "AutoSeason", "KillAura", "SuperLootAura", "AutoWorldBoss", "AutoTower", "GodMode", "AutoBestRace" },
}

local Config = xDTaraZ.Config
local Remote = ReplicatedStorage:WaitForChild("Remote", Config.LoadTimeout)
local GameConfig = ReplicatedStorage:WaitForChild("Config", Config.LoadTimeout)

xDTaraZ.State = {
    Alive = true,
    Busy = false,
    Lock = nil,
    Failures = {},
    Halted = {},
    InTower = false,
    Entering = false,
    GearForged = false,
    TrainArea = nil,
    TrainPending = nil,
    TrainEntering = false,
    TrainGen = 0,
    TrainFiredAt = 0,
    TrainRebirth = nil,
    BossReturn = nil,
    TrainLevel = nil,
    TrainNilSince = nil,
    Warned = {},
    WarnedCount = 0,
    LastRun = {},
    Profile = nil,
    GearNote = nil,
    IndexNote = nil,
    TowerLoot = 0,
    OreLabels = {},
    SpawnLabels = {},
    GearLabels = {},
    BossHopping = false,
    HopFails = 0,
    HopBackoff = nil,
    HopBlockedUntil = 0,
    HopQueued = false,
    BossDone = nil,
    MissingLabels = {},
    OreStage = {},
    Plans = {},
    Runes = nil,
    Conns = {},
    Opt = {
        MaxGear = false,
        AutoEquip = false,
        EnhanceTarget = 20,
        GearForge = true,
        GearEnchant = true,
        GearEnhance = true,
        EnchantPriority = {},
        EnhanceSlot = "Weapon",
        ForgeSellJunk = false,
        ForgePerTick = 10,
        BossCards = true,
        SeasonSpin = true,
        SeasonGoods = { ["4"] = true, ["7"] = true },
        AutoBestRace = false,
        GodMode = false,
        KeepOre = false,
        CollectOre = false,
        Stage = nil,
        CollectRarities = {},
        KillAura = false,
        SuperLootAura = false,
        AutoWorldBoss = false,
        BossHop = false,
        AutoForge = false,
        ForgeTarget = "Great Weapon",
        ForgeOre = nil,
        ForgeRarities = {},
        KeepPerOre = 0,
        BestOreFirst = false,
        AutoSell = false,
        SellTypes = { Weapon = true, Armor = true, Hat = true },
        SellRarities = {},
        KeepPerItem = 1,
        AutoIndex = false,
        IndexTypes = { Weapon = true, Armor = true, Hat = true },
        MissingItem = nil,
        AutoTrain = false,
        AutoClick = false,
        AutoRebirth = false,
        AutoUpgrade = false,
        Upgrades = {},
        AutoClaim = false,
        AutoSeason = false,
        AutoTower = false,
        AutoRace = false,
        TargetRace = nil,
        SpawnItem = nil,
        SpawnAmount = 100000,
        CoinTarget = 1000000,
        SpawnGear = nil,
        GearCopies = 1,
        SpeedOn = false,
        WalkSpeed = 60,
        InfJump = false,
        AutoRejoin = false,
        LowGraphics = false,
    },
}

local State = xDTaraZ.State

xDTaraZ.GameLib = { Loaded = {}, Failed = {}, Apis = {}, Deferred = {} }

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
    local deadline = os.clock() + Config.RequireTimeout
    while not done and os.clock() < deadline do
        task.wait()
    end
    return ok, loaded
end

---@return table?  nil when this executor can't require it; the failure is warned once
function xDTaraZ.GameLib.Require(module)
    local cached = xDTaraZ.GameLib.Loaded[module]
    if cached ~= nil or xDTaraZ.GameLib.Failed[module] then return cached end

    local ok, loaded = pcall(require, module)
    if not ok then
        local firstErr = loaded
        ok, loaded = xDTaraZ.GameLib.RequireAsGame(module)
        if not ok then
            xDTaraZ.GameLib.Failed[module] = tostring(firstErr)
            warn("[LootToForge] require", module:GetFullName(), firstErr)
            return nil
        end
    end
    xDTaraZ.GameLib.Loaded[module] = loaded
    return loaded
end

---@return boolean, any ...  pcall-style results
function xDTaraZ.GameLib.CallAsGame(fn, ...)
    local args = table.pack(...)
    local box
    task.defer(function()
        pcall(setthreadidentity, 2)
        box = table.pack(pcall(fn, table.unpack(args, 1, args.n)))
    end)
    local deadline = os.clock() + Config.RequireTimeout
    while not box and os.clock() < deadline do
        task.wait()
    end
    if not box then return false, "game call timed out" end
    return table.unpack(box, 1, box.n)
end

function xDTaraZ.GameLib.Call(fn, ...)
    if not xDTaraZ.GameLib.Deferred[fn] then
        local result = table.pack(pcall(fn, ...))
        if result[1] or not tostring(result[2]):find("non-RobloxScript", 1, true) then
            if not result[1] then error(result[2], 0) end
            return table.unpack(result, 2, result.n)
        end
        xDTaraZ.GameLib.Deferred[fn] = true
    end
    local result = table.pack(xDTaraZ.GameLib.CallAsGame(fn, ...))
    if not result[1] then error(result[2], 0) end
    return table.unpack(result, 2, result.n)
end

---@return table  function fields go through GameLib.Call; for helper/controller modules, not config tables
function xDTaraZ.GameLib.Api(module)
    local api = xDTaraZ.GameLib.Apis[module]
    if api then return api end
    local loaded = xDTaraZ.GameLib.Need(module)
    api = setmetatable({}, {
        __index = function(self, key)
            local value = loaded[key]
            if type(value) ~= "function" then return value end
            local wrapped = function(...)
                return xDTaraZ.GameLib.Call(value, ...)
            end
            rawset(self, key, wrapped)
            return wrapped
        end,
    })
    xDTaraZ.GameLib.Apis[module] = api
    return api
end

---@return table  errors with a readable reason instead of returning nil
function xDTaraZ.GameLib.Need(module)
    local loaded = xDTaraZ.GameLib.Require(module)
    if loaded == nil then
        error(("game data %s.%s can't be read on this executor"):format(module.Parent.Name, module.Name), 0)
    end
    return loaded
end

---@param path string  dotted path under ReplicatedStorage, e.g. "Config.Ore.Config"
---@return Instance?
function xDTaraZ.GameLib.Find(path)
    local node = ReplicatedStorage
    for part in path:gmatch("[^%.]+") do
        node = node and node:FindFirstChild(part)
    end
    if node then return node end
    local folder, name = path:match("^Remote%.([^%.]+)%.([^%.]+)$")
    return folder and xDTaraZ.Util.FindRemote(folder, name)
end

---@return table  option idx -> missing paths
function xDTaraZ.GameLib.Missing()
    local missing = {}
    for idx, paths in pairs(Config.Needs) do
        for _, path in ipairs(paths) do
            if not xDTaraZ.GameLib.Find(path) then
                missing[idx] = missing[idx] or {}
                table.insert(missing[idx], path)
            end
        end
    end
    return missing
end

for _, name in ipairs({ "Util", "Data", "Stage", "Ore", "Spawn", "Potion", "Forge", "Sell", "Gear", "Index", "Level", "Upgrade", "Tower", "Boss", "Season", "Claim", "SuperLoot", "Combat", "Guard", "Race", "Movement", "Session", "Scheduler" }) do
    xDTaraZ[name] = {}
end

---@return Instance?  nil when missing; a renamed folder is searched by remote name
function xDTaraZ.Util.FindRemote(folder, name)
    if not Remote then return nil end
    local holder = Remote:FindFirstChild(folder)
    if holder then return holder:FindFirstChild(name) end
    return Remote:FindFirstChild(name, true)
end

function xDTaraZ.Util.Remote(folder, name)
    local remote = xDTaraZ.Util.FindRemote(folder, name)
    if remote then return remote end

    local holder = Remote and Remote:WaitForChild(folder, Config.RemoteTimeout)
    remote = holder and holder:WaitForChild(name, Config.RemoteTimeout) or xDTaraZ.Util.FindRemote(folder, name)
    if not remote then error(("remote %s.%s not found"):format(folder, name), 0) end
    return remote
end

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

function xDTaraZ.Util.Alert(text, detail)
    warn("[LootToForge] menu:", text, detail or "")
    task.spawn(function()
        for _ = 1, Config.AlertTries do
            local shown = pcall(StarterGui.SetCore, StarterGui, "SendNotification", { Title = "Nova Hub", Text = text, Duration = 10 })
            if shown then return end
            task.wait(Config.AlertDelay)
        end
    end)
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
    if not ok or type(library) ~= "table" then
        xDTaraZ.Util.Alert("The menu failed to load on this executor: " .. tostring(library))
        return nil
    end
    return library
end

---Warns a job failure once per Config.WarnCooldown so a feature that flips between failing and succeeding can't flood the console.
function xDTaraZ.Util.WarnJob(key, err)
    local stamp = key .. tostring(err):match("[^\n]*")
    local now = os.clock()
    if now - (State.Warned[stamp] or -Config.WarnCooldown) < Config.WarnCooldown then return end

    if not State.Warned[stamp] then
        State.WarnedCount += 1
        if State.WarnedCount > Config.WarnMemory then
            table.clear(State.Warned)
            State.WarnedCount = 1
        end
    end
    State.Warned[stamp] = now
    warn("[LootToForge]", key, err)
end

function xDTaraZ.Util.Try(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        warn("[LootToForge]", err)
    end
    return ok, err
end

function xDTaraZ.Util.Tier(id)
    return tonumber(tostring(id):match("%d+")) or 0
end

function xDTaraZ.Util.Abbreviate(number)
    local units = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp" }
    local index = 1
    while number >= 1000 and index < #units do
        number /= 1000
        index += 1
    end
    return (index == 1 and "%d%s" or "%.2f%s"):format(number, units[index])
end

function xDTaraZ.Util.HighestKey(configTable)
    local bestKey, bestTier = nil, -1
    for key in pairs(configTable) do
        local tier = xDTaraZ.Util.Tier(key)
        if tier > bestTier then
            bestKey, bestTier = key, tier
        end
    end
    return bestKey
end

function xDTaraZ.Util.WaitAll(workers, job)
    local pending = workers
    for _ = 1, workers do
        task.spawn(function()
            xDTaraZ.Util.Try(job)
            pending -= 1
        end)
    end
    local deadline = os.clock() + Config.RemoteTimeout * 3
    while pending > 0 and os.clock() < deadline do
        task.wait(0.1)
    end
end

function xDTaraZ.Util.RarityNames()
    local helper = xDTaraZ.GameLib.Api(GameConfig.Rarity.Helper)
    local names = {}
    for level = 1, 20 do
        local name = helper.GetRarityByLevel(level)
        if not name then break end
        table.insert(names, name)
    end
    return names
end

function xDTaraZ.Util.AllSet(list)
    local set = {}
    for _, name in ipairs(list) do
        set[name] = true
    end
    return set
end

---@param name string  shown in status while it runs
---@return boolean     false if another long job holds the character
function xDTaraZ.Util.Exclusive(name, fn, ...)
    if State.Lock then return false end
    State.Lock = name
    local ok = xDTaraZ.Util.Try(fn, ...)
    State.Lock = nil
    return ok
end

function xDTaraZ.Data.Get()
    State.Profile = xDTaraZ.Util.Remote("Profile", "GetTotalDataRF"):InvokeServer()
    return State.Profile
end

function xDTaraZ.Data.Count(profile, itemId)
    local total = 0
    for _, entry in pairs(profile.Backpack.have) do
        if entry.ID == itemId then
            total += entry.Number or 1
        end
    end
    return total
end

function xDTaraZ.Data.Uuid(profile, itemId)
    for uuid, entry in pairs(profile.Backpack.have) do
        if entry.ID == itemId and (entry.Number or 0) >= 1 then
            return uuid
        end
    end
    return nil
end

function xDTaraZ.Data.Snapshot()
    local seen = {}
    for uuid in pairs(xDTaraZ.Data.Get().Backpack.have) do
        seen[uuid] = true
    end
    return seen
end

---@return table  { [uuid] = entry } gear that appeared after the snapshot
function xDTaraZ.Data.NewGear(before)
    local fresh = {}
    for uuid, entry in pairs(xDTaraZ.Data.Get().Backpack.have) do
        if not before[uuid] and entry.Type ~= "Ore" and entry.Type ~= "Material" and entry.Type ~= "EnchStone" then
            fresh[uuid] = entry
        end
    end
    return fresh
end

function xDTaraZ.Ore.Rarity(oreId)
    local oreConfig = xDTaraZ.GameLib.Need(GameConfig.Ore.Config)[oreId]
    return oreConfig and xDTaraZ.GameLib.Api(GameConfig.Rarity.Helper).GetRarityByLevel(oreConfig.Rarity)
end

function xDTaraZ.Ore.Owned(profile)
    local ores = {}
    for uuid, entry in pairs(profile.Backpack.have) do
        if entry.Type == "Ore" and (entry.Number or 0) >= 1 then
            table.insert(ores, {
                uuid = uuid,
                id = entry.ID,
                tier = xDTaraZ.Util.Tier(entry.ID),
                number = math.floor(entry.Number),
                rarity = xDTaraZ.Ore.Rarity(entry.ID),
            })
        end
    end
    table.sort(ores, function(a, b) return a.tier > b.tier end)
    return ores
end

function xDTaraZ.Ore.Ids()
    local ids = {}
    for oreId in pairs(xDTaraZ.GameLib.Need(GameConfig.Ore.Config)) do
        table.insert(ids, oreId)
    end
    table.sort(ids, function(a, b) return xDTaraZ.Util.Tier(a) > xDTaraZ.Util.Tier(b) end)
    return ids
end

function xDTaraZ.Ore.Choices()
    local oreShow = xDTaraZ.GameLib.Need(GameConfig.Ore.Show)
    local labels, idByLabel = {}, {}
    for _, oreId in ipairs(xDTaraZ.Ore.Ids()) do
        local label = ("%s (%s)"):format(oreShow[oreId] and oreShow[oreId].DisplayName or oreId, xDTaraZ.Ore.Rarity(oreId) or "?")
        if idByLabel[label] then
            label = ("%s #%d"):format(label, xDTaraZ.Util.Tier(oreId))
        end
        idByLabel[label] = oreId
        table.insert(labels, label)
    end
    State.OreLabels = idByLabel
    return labels
end

function xDTaraZ.Ore.ForgeChoices()
    local labels = xDTaraZ.Ore.Choices()
    table.insert(labels, 1, Config.OwnedOresLabel)
    return labels
end

function xDTaraZ.Ore.Add(uuid, amount)
    xDTaraZ.Util.Remote("Backpack", "TrySellItemRE"):FireServer(uuid, -math.abs(amount))
end

---@param need number  how many must be in the stack afterwards
---@return string?     stack uuid, nil if the ore never dropped
function xDTaraZ.Ore.Ensure(oreId, need)
    local profile = xDTaraZ.Data.Get()
    local uuid = xDTaraZ.Data.Uuid(profile, oreId)
    if not uuid then
        if not xDTaraZ.Stage.AcquireOre(oreId) then return nil end
        task.wait(0.4)
        profile = xDTaraZ.Data.Get()
        uuid = xDTaraZ.Data.Uuid(profile, oreId)
    end
    if uuid and xDTaraZ.Data.Count(profile, oreId) < need then
        xDTaraZ.Ore.Add(uuid, math.max(Config.RefillAmount, need))
        task.wait(0.4)
    end
    return uuid
end

function xDTaraZ.Ore.Top(minimum)
    local top = xDTaraZ.Ore.Owned(xDTaraZ.Data.Get())[1]
    if not top then
        xDTaraZ.Stage.Collect(xDTaraZ.Stage.Best(), nil)
        top = xDTaraZ.Ore.Owned(xDTaraZ.Data.Get())[1]
    end
    if top and top.number < minimum then
        xDTaraZ.Ore.Add(top.uuid, Config.RefillAmount)
        task.wait(0.4)
    end
    return top
end

function xDTaraZ.Spawn.Choices()
    local labels, byLabel = xDTaraZ.Ore.Choices(), {}
    for label, oreId in pairs(State.OreLabels) do
        byLabel[label] = { id = oreId, kind = "Ore" }
    end
    local stoneShow = xDTaraZ.GameLib.Need(GameConfig.EnchStone.Show)
    local stones = {}
    for stoneId in pairs(stoneShow) do
        table.insert(stones, stoneId)
    end
    table.sort(stones, function(a, b)
        local ta, tb = xDTaraZ.Util.Tier(a), xDTaraZ.Util.Tier(b)
        if ta ~= tb then return ta > tb end
        return a < b
    end)
    for _, stoneId in ipairs(stones) do
        local label = stoneShow[stoneId].DisplayName or stoneId
        byLabel[label] = { id = stoneId, kind = "EnchStone" }
        table.insert(labels, label)
    end
    State.SpawnLabels = byLabel
    return labels
end

---@return boolean  false if the item was never owned and can't be found
function xDTaraZ.Spawn.Give(itemId, kind, amount)
    if kind == "Ore" then
        local uuid = xDTaraZ.Ore.Ensure(itemId, 0)
        if not uuid then return false end
        xDTaraZ.Ore.Add(uuid, amount)
        return true
    end
    local uuid = xDTaraZ.Data.Uuid(xDTaraZ.Data.Get(), itemId)
    if not uuid then return false end
    xDTaraZ.Ore.Add(uuid, amount)
    return true
end

---@return string[]  potion ids you own at least once (the rest can't be added)
function xDTaraZ.Potion.Owned()
    local owned = {}
    local stock = xDTaraZ.Data.Get().Potion or {}
    for potionId in pairs(xDTaraZ.GameLib.Need(GameConfig.Potion.Config)) do
        if stock[potionId] ~= nil then table.insert(owned, potionId) end
    end
    table.sort(owned)
    return owned
end

function xDTaraZ.Potion.Add(potionId, amount)
    xDTaraZ.Util.Remote("Potion", "TryUsePotionRE"):FireServer(potionId, -math.abs(amount))
end

---@return number  potions boosted for about a year each
function xDTaraZ.Potion.MaxBuffs()
    local use = xDTaraZ.Util.Remote("Potion", "TryUsePotionRE")
    local owned = xDTaraZ.Potion.Owned()
    for _, potionId in ipairs(owned) do
        xDTaraZ.Potion.Add(potionId, Config.PotionStack)
        use:FireServer(potionId, Config.PotionStack)
    end
    return #owned
end

---@return number  stacks touched
function xDTaraZ.Spawn.DupeAll(amount)
    local touched = 0
    for uuid, entry in pairs(xDTaraZ.Data.Get().Backpack.have) do
        if type(entry) ~= "table" or not entry.Number or entry.Type == "Material" then continue end
        touched += 1
        xDTaraZ.Ore.Add(uuid, amount)
    end
    return touched
end

function xDTaraZ.Stage.List()
    local stages = {}
    for stageId in pairs(xDTaraZ.GameLib.Api(GameConfig.Stage.Helper).GetStageEnemyConfig()) do
        table.insert(stages, stageId)
    end
    table.sort(stages, function(a, b) return xDTaraZ.Util.Tier(a) > xDTaraZ.Util.Tier(b) end)
    return stages
end

function xDTaraZ.Stage.Best()
    return xDTaraZ.Stage.List()[1]
end

function xDTaraZ.Stage.Collect(stageId, rarities)
    local drops = xDTaraZ.Util.Remote("Stage", "StageFinishedRF"):InvokeServer(stageId)
    if type(drops) ~= "table" then return end
    for uuid, drop in pairs(drops) do
        if type(drop) == "table" then
            xDTaraZ.Util.Remote("Stage", "GetEnhantStoneRE"):FireServer(uuid)
        elseif not rarities or rarities[xDTaraZ.Ore.Rarity(drop)] then
            xDTaraZ.Util.Remote("Stage", "GetOreRF"):InvokeServer(uuid)
        end
    end
    xDTaraZ.Util.Remote("Stage", "ClaimedAllOreRE"):FireServer()
end

function xDTaraZ.Stage.FarmStones(stageId)
    local finished = xDTaraZ.Util.Remote("Stage", "StageFinishedRF")
    local pickStone = xDTaraZ.Util.Remote("Stage", "GetEnhantStoneRE")
    xDTaraZ.Util.WaitAll(Config.StoneWorkers, function()
        for _ = 1, Config.StoneCallsPerWorker do
            local drops = finished:InvokeServer(stageId)
            for uuid, drop in pairs(type(drops) == "table" and drops or {}) do
                if type(drop) == "table" then
                    pickStone:FireServer(uuid)
                end
            end
        end
    end)
end

function xDTaraZ.Stage.AcquireOre(oreId)
    local stages = xDTaraZ.Stage.List()
    local known = State.OreStage[oreId]
    local target = xDTaraZ.Util.Tier(oreId) * #stages / xDTaraZ.Util.Tier(xDTaraZ.Util.HighestKey(xDTaraZ.GameLib.Need(GameConfig.Ore.Config)))
    table.sort(stages, function(a, b)
        if a == known or b == known then return a == known end
        return math.abs(xDTaraZ.Util.Tier(a) - target) < math.abs(xDTaraZ.Util.Tier(b) - target)
    end)

    local finished = xDTaraZ.Util.Remote("Stage", "StageFinishedRF")
    local pickOre = xDTaraZ.Util.Remote("Stage", "GetOreRF")
    for round = 1, Config.AcquireRounds do
        local stageId = stages[(round - 1) % math.min(#stages, 4) + 1]
        local drops = finished:InvokeServer(stageId)
        for uuid, drop in pairs(type(drops) == "table" and drops or {}) do
            if drop == oreId and pickOre:InvokeServer(uuid) then
                xDTaraZ.Util.Remote("Stage", "ClaimedAllOreRE"):FireServer()
                State.OreStage[oreId] = stageId
                return true
            end
        end
    end
    return false
end

function xDTaraZ.Stage.ExitFight()
    xDTaraZ.GameLib.Api(LocalPlayer.PlayerScripts.Manager.StageManager.StageUtils).ExitFight(true)
end

function xDTaraZ.Forge.Target()
    for _, target in ipairs(Config.ForgeTargets) do
        if target.name == State.Opt.ForgeTarget then
            return target
        end
    end
    return Config.ForgeTargets[1]
end

function xDTaraZ.Forge.Run(forgeType, oreList)
    return xDTaraZ.Util.Remote("Forge", "ForgeRF"):InvokeServer({ ConfigType = forgeType, UUIDList = oreList })
end

function xDTaraZ.Forge.PickOwned(profile, count)
    local opt = State.Opt
    local candidates = {}
    for _, ore in ipairs(xDTaraZ.Ore.Owned(profile)) do
        local spare = ore.number - opt.KeepPerOre
        if opt.ForgeRarities[ore.rarity] and spare > 0 then
            ore.spare = spare
            table.insert(candidates, ore)
        end
    end
    if not opt.BestOreFirst then
        table.sort(candidates, function(a, b) return a.tier < b.tier end)
    end

    local pick, need = {}, count
    for _, ore in ipairs(candidates) do
        if need <= 0 then break end
        local take = math.min(need, ore.spare)
        pick[ore.uuid] = take
        need -= take
    end
    return need <= 0 and pick or nil
end

---@return table?  { [uuid] = count }, nil when no ore fits
function xDTaraZ.Forge.Pick(count)
    local oreId = State.OreLabels[State.Opt.ForgeOre]
    if not oreId then
        return xDTaraZ.Forge.PickOwned(xDTaraZ.Data.Get(), count)
    end
    local uuid = xDTaraZ.Ore.Ensure(oreId, count * State.Opt.ForgePerTick)
    return uuid and { [uuid] = count }
end

function xDTaraZ.Forge.Once()
    local target = xDTaraZ.Forge.Target()
    local pick = xDTaraZ.Forge.Pick(target.ores)
    return pick ~= nil and xDTaraZ.Forge.Run(target.forgeType, pick) ~= nil
end

function xDTaraZ.Forge.Burst()
    local target = xDTaraZ.Forge.Target()
    local perTick = State.Opt.ForgePerTick
    local pick = xDTaraZ.Forge.Pick(target.ores * perTick)
    if not pick then return end
    local uuid = next(pick)
    if next(pick, uuid) == nil then
        for _ = 1, perTick do
            xDTaraZ.Forge.Run(target.forgeType, { [uuid] = target.ores })
        end
        return
    end
    for _ = 1, perTick do
        if not xDTaraZ.Forge.Once() then break end
    end
end

function xDTaraZ.Forge.Step()
    if not State.Opt.ForgeSellJunk then return xDTaraZ.Forge.Burst() end
    local before = xDTaraZ.Data.Snapshot()
    xDTaraZ.Forge.Burst()
    local fresh = xDTaraZ.Data.NewGear(before)
    local profile = State.Profile
    local keep = {}
    for uuid, entry in pairs(fresh) do
        local worn = profile.Backpack.equiped[entry.Type]
        local wornEntry = worn and profile.Backpack.have[worn]
        if not wornEntry or xDTaraZ.Gear.Score(entry, true) > xDTaraZ.Gear.Score(wornEntry, true) then
            keep[uuid] = true
        end
    end
    xDTaraZ.Sell.Fresh(fresh, keep)
end

function xDTaraZ.Sell.Rarity(entry)
    local folder = entry.Type == "Weapon" and "Weapon" or "Armor"
    local itemConfig = xDTaraZ.GameLib.Need(GameConfig[folder].Config)[entry.ID]
    return itemConfig and itemConfig.Rarity
end

---@return table<string, boolean>  uuids of the strongest normal piece per slot, which exclusive gear takes its power from
function xDTaraZ.Sell.Anchors(profile)
    local anchors, bestPower = {}, {}
    for uuid, entry in pairs(profile.Backpack.have) do
        if not (entry.Type == "Weapon" or entry.Type == "Armor" or entry.Type == "Hat") then continue end
        local helper = xDTaraZ.GameLib.Api(entry.Type == "Weapon" and GameConfig.Weapon.Helper or GameConfig.Armor.Helper)
        local ok, percent = pcall(helper.CheckIsBestPercent, entry.ID)
        if not ok or percent then continue end
        local powerOk, power = pcall(helper.GetMainAffix, entry.ID)
        if powerOk and type(power) == "number" and power > (bestPower[entry.Type] or 0) then
            bestPower[entry.Type] = power
            anchors[entry.Type] = uuid
        end
    end
    local keep = {}
    for _, uuid in pairs(anchors) do
        keep[uuid] = true
    end
    local backpack = xDTaraZ.GameLib.Require(ReplicatedStorage.LocalData.BackpackData)
    if type(backpack) == "table" and type(backpack.IsLocked) == "function" then
        for uuid in pairs(profile.Backpack.have) do
            local ok, locked = pcall(backpack.IsLocked, uuid)
            if ok and locked then keep[uuid] = true end
        end
    end
    return keep
end

function xDTaraZ.Sell.Run(profile)
    local opt = State.Opt
    local equipped = xDTaraZ.Sell.Anchors(profile)
    for _, uuid in pairs(profile.Backpack.equiped) do
        equipped[uuid] = true
    end

    local byId = {}
    for uuid, entry in pairs(profile.Backpack.have) do
        if opt.SellTypes[entry.Type] and not equipped[uuid] then
            byId[entry.ID] = byId[entry.ID] or {}
            table.insert(byId[entry.ID], { uuid = uuid, entry = entry })
        end
    end

    local sell = xDTaraZ.Util.Remote("Backpack", "TrySellItemRE")
    for _, items in pairs(byId) do
        table.sort(items, function(a, b) return (a.entry.Level or 0) > (b.entry.Level or 0) end)
        for index, gear in ipairs(items) do
            if index > opt.KeepPerItem and opt.SellRarities[xDTaraZ.Sell.Rarity(gear.entry)] then
                sell:FireServer(gear.uuid, 1)
            end
        end
    end
end

---@param keep table?  { [uuid] = true } never sold
function xDTaraZ.Sell.Fresh(fresh, keep)
    local equipped = xDTaraZ.Sell.Anchors(State.Profile)
    for _, uuid in pairs(State.Profile.Backpack.equiped) do
        equipped[uuid] = true
    end
    local sell = xDTaraZ.Util.Remote("Backpack", "TrySellItemRE")
    for uuid in pairs(fresh) do
        if not equipped[uuid] and not (keep and keep[uuid]) then
            sell:FireServer(uuid, 1)
        end
    end
end

---@param atTarget boolean?  score as if enhanced to the target, so exclusive gear isn't skipped for a higher-level common piece
---@return number           power from the game's own formula
function xDTaraZ.Gear.Score(entry, atTarget)
    local balance = xDTaraZ.GameLib.Api(ReplicatedStorage.Utils.BalanceUtils)
    local backpack = (State.Profile or xDTaraZ.Data.Get()).Backpack
    local potential = table.clone(entry)
    if atTarget then potential.Level = math.max(entry.Level or 0, State.Opt.EnhanceTarget) end
    local value = entry.Type == "Weapon" and balance.GetWeaponTrainValue or balance.GetArmorValue
    local ok, power = pcall(value, LocalPlayer, potential, backpack)
    if not ok or type(power) ~= "number" then return 0 end
    return power * (1 + (entry.Level or 0) * 1e-6 + #(entry.EnchanceList or {}) * 1e-9)
end

function xDTaraZ.Gear.BestOwned(profile, slot, atTarget)
    local bestUuid, bestScore = nil, -1
    for uuid, entry in pairs(profile.Backpack.have) do
        if entry.Type == slot then
            local score = xDTaraZ.Gear.Score(entry, atTarget)
            if score > bestScore then
                bestUuid, bestScore = uuid, score
            end
        end
    end
    return bestUuid, bestScore
end

---@return number  slots changed
function xDTaraZ.Gear.EquipBest()
    local profile = xDTaraZ.Data.Get()
    local equip = xDTaraZ.Util.Remote("Backpack", "TryEquipItemRE")
    local changed = 0
    local atTarget = State.Opt.MaxGear and State.Opt.GearEnhance
    for _, slot in ipairs(Config.GearTypes) do
        local best, bestScore = xDTaraZ.Gear.BestOwned(profile, slot, atTarget)
        local current = profile.Backpack.equiped[slot]
        local currentEntry = current and profile.Backpack.have[current]
        if best and best ~= current and bestScore > (currentEntry and xDTaraZ.Gear.Score(currentEntry, atTarget) or -1) then
            equip:FireServer(best, slot)
            changed += 1
        end
    end
    return changed
end

function xDTaraZ.Gear.ForgeBest()
    local before = xDTaraZ.Data.Snapshot()
    for _, spec in ipairs(Config.GearSlots) do
        local top = xDTaraZ.Ore.Top(spec.ores * Config.GearForgeTries)
        if top then
            for _ = 1, Config.GearForgeTries do
                xDTaraZ.Forge.Run(spec.forgeType, { [top.uuid] = spec.ores })
            end
        end
        local best = xDTaraZ.Gear.BestOwned(xDTaraZ.Data.Get(), spec.slot, true)
        if best then
            xDTaraZ.Util.Remote("Backpack", "TryEquipItemRE"):FireServer(best, spec.slot)
        end
    end
    task.wait(1)
    xDTaraZ.Sell.Fresh(xDTaraZ.Data.NewGear(before))
end

function xDTaraZ.Gear.MissingForEnhance(profile, level)
    local cost = xDTaraZ.GameLib.Need(GameConfig.Enhant.Config)[level + 1]
    if not cost then return nil end
    if xDTaraZ.Data.Count(profile, "EnhantStone_2") < (cost.EnhantStone_2 or 0) then return "EnhantStone_2" end
    if xDTaraZ.Data.Count(profile, "EnhantStone_1") < (cost.EnhantStone_1 or 0) then return "EnhantStone_1" end
    if profile.Eco.coin < (cost.NeedCoin or 0) then return "Coin" end
    return nil
end

function xDTaraZ.Gear.Gather(missing)
    State.GearNote = missing
    if missing == "Coin" then
        xDTaraZ.Forge.Step()
        xDTaraZ.Sell.Run(xDTaraZ.Data.Get())
    elseif missing == "EnhantStone_1" then
        xDTaraZ.Stage.FarmStones(xDTaraZ.Stage.Best())
    elseif not xDTaraZ.Tower.FarmStep() then
        State.GearNote = "NoTicket"
    end
end

---@return string[]  every rune the game has from RuneMinTier up, strongest tier first
function xDTaraZ.Gear.RuneOrder()
    if State.Runes then return State.Runes end
    local show = xDTaraZ.GameLib.Find("Config.EnchStone.Show")
    local stones = show and xDTaraZ.GameLib.Require(show)
    if not stones then return Config.EnchantPriority end

    local known = {}
    for index, stoneId in ipairs(Config.EnchantPriority) do
        known[stoneId] = index
    end
    local runes = {}
    for stoneId in pairs(stones) do
        if xDTaraZ.Util.Tier(stoneId) >= Config.RuneMinTier then runes[#runes + 1] = stoneId end
    end
    table.sort(runes, function(a, b)
        local ta, tb = xDTaraZ.Util.Tier(a), xDTaraZ.Util.Tier(b)
        if ta ~= tb then return ta > tb end
        local ka, kb = known[a] or math.huge, known[b] or math.huge
        if ka ~= kb then return ka < kb end
        return a < b
    end)
    State.Runes = runes
    return runes
end

function xDTaraZ.Gear.Priority()
    return #State.Opt.EnchantPriority > 0 and State.Opt.EnchantPriority or xDTaraZ.Gear.RuneOrder()
end

function xDTaraZ.Gear.StockEnchants(profile)
    for _, stoneId in ipairs(xDTaraZ.Gear.Priority()) do
        local uuid = xDTaraZ.Data.Uuid(profile, stoneId)
        if uuid and xDTaraZ.Data.Count(profile, stoneId) < Config.EnchantRefill then
            xDTaraZ.Ore.Add(uuid, Config.EnchantRefill)
        end
    end
end

function xDTaraZ.Gear.Enchant(profile, uuid)
    local entry = profile.Backpack.have[uuid]
    local used = {}
    for slot = 1, entry.EnchanceNum or 0 do
        local current = entry.EnchanceList and entry.EnchanceList[slot]
        local currentId = current and current.ID
        local wanted
        for _, stoneId in ipairs(xDTaraZ.Gear.Priority()) do
            if not used[stoneId] and (stoneId == currentId or xDTaraZ.Data.Count(profile, stoneId) > 0) then
                wanted = stoneId
                break
            end
        end
        if wanted then
            used[wanted] = true
            if wanted ~= currentId then
                if currentId then
                    xDTaraZ.Util.Remote("Backpack", "UnEnchantRE"):FireServer(uuid, slot)
                    task.wait(0.3)
                end
                xDTaraZ.Util.Remote("Backpack", "EnchantRE"):FireServer(uuid, xDTaraZ.Data.Uuid(profile, wanted), slot)
                task.wait(0.3)
            end
        end
    end
end

function xDTaraZ.Gear.Enhance(profile)
    local target = math.min(State.Opt.EnhanceTarget, xDTaraZ.Util.Tier(xDTaraZ.Util.HighestKey(xDTaraZ.GameLib.Need(GameConfig.Enhant.Config))))
    local enhance = xDTaraZ.Util.Remote("Backpack", "EnhantEquipmentRF")
    for _, spec in ipairs(Config.GearSlots) do
        local uuid = profile.Backpack.equiped[spec.slot]
        local entry = uuid and profile.Backpack.have[uuid]
        if entry and (entry.Level or 0) < target then
            local missing = xDTaraZ.Gear.MissingForEnhance(profile, entry.Level or 0)
            if missing then
                xDTaraZ.Gear.Gather(missing)
                return false
            end
            State.GearNote = "Enhancing"
            local useProtect = xDTaraZ.Data.Count(profile, "EnhantProtect") > 0 and (entry.Level or 0) >= xDTaraZ.GameLib.Api(GameConfig.Enhant.Helper).GetFailLevel()
            xDTaraZ.Util.WaitAll(Config.GearEnhanceWorkers, function()
                for _ = 1, Config.GearEnhanceTries do
                    if not enhance:InvokeServer(uuid, { UseProtect = useProtect }) then return end
                end
            end)
            return false
        end
    end
    return true
end

function xDTaraZ.Gear.MaxStep()
    local opt = State.Opt
    if opt.GearForge and not State.GearForged then
        xDTaraZ.Gear.ForgeBest()
        State.GearForged = true
    end
    if opt.GearEnchant then
        local profile = xDTaraZ.Data.Get()
        xDTaraZ.Gear.StockEnchants(profile)
        profile = xDTaraZ.Data.Get()
        for _, spec in ipairs(Config.GearSlots) do
            local uuid = profile.Backpack.equiped[spec.slot]
            if uuid then xDTaraZ.Gear.Enchant(profile, uuid) end
        end
    end
    if not opt.GearEnhance or xDTaraZ.Gear.Enhance(xDTaraZ.Data.Get()) then
        State.GearNote = "Done"
    end
end

---@return number?  level reached, nil if nothing equipped there
function xDTaraZ.Gear.EnhanceSlot(slot, target)
    local enhance = xDTaraZ.Util.Remote("Backpack", "EnhantEquipmentRF")
    local failLevel = xDTaraZ.GameLib.Api(GameConfig.Enhant.Helper).GetFailLevel()
    local level = 0
    for _ = 1, Config.SlotEnhanceRounds do
        local profile = xDTaraZ.Data.Get()
        local uuid = profile.Backpack.equiped[slot]
        local entry = uuid and profile.Backpack.have[uuid]
        if not entry then return nil end
        level = entry.Level or 0
        if level >= target then return level end
        local missing = xDTaraZ.Gear.MissingForEnhance(profile, level)
        if missing == "EnhantStone_1" then
            xDTaraZ.Stage.FarmStones(xDTaraZ.Stage.Best())
        elseif missing then
            return level
        else
            enhance:InvokeServer(uuid, { UseProtect = level >= failLevel and xDTaraZ.Data.Count(profile, "EnhantProtect") > 0 })
        end
    end
    return level
end

function xDTaraZ.Gear.EquippedNames(profile)
    local names = {}
    for _, spec in ipairs(Config.GearSlots) do
        local uuid = profile.Backpack.equiped[spec.slot]
        local entry = uuid and profile.Backpack.have[uuid]
        if entry then
            local shows = xDTaraZ.GameLib.Require(GameConfig[entry.Type == "Weapon" and "Weapon" or "Armor"].Show)
            local show = shows and shows[entry.ID]
            table.insert(names, ("%s +%d"):format(show and show.DisplayName or entry.ID, entry.Level or 0))
        end
    end
    return table.concat(names, " · ")
end

function xDTaraZ.Index.GearCatalog()
    local gear = {}
    local armorHelper = xDTaraZ.GameLib.Api(GameConfig.Armor.Helper)
    for weaponId, weapon in pairs(xDTaraZ.GameLib.Need(GameConfig.Weapon.Config)) do
        table.insert(gear, { id = weaponId, slot = "Weapon", forgeType = "Weapon", forgeable = weapon.TLevel ~= nil })
    end
    for armorId, armor in pairs(xDTaraZ.GameLib.Need(GameConfig.Armor.Config)) do
        table.insert(gear, { id = armorId, slot = armorHelper.GetBigType(armorId) or "Armor", forgeType = "Armor", forgeable = armor.TLevel ~= nil })
    end
    return gear
end

---@return table[]  gear the index still lacks, filtered by IndexTypes
function xDTaraZ.Index.Missing()
    local unlocked = xDTaraZ.Data.Get().Index.unlocked
    local missing = {}
    for _, gear in ipairs(xDTaraZ.Index.GearCatalog()) do
        if State.Opt.IndexTypes[gear.slot] and not unlocked[gear.slot .. "-" .. gear.id] then
            table.insert(missing, gear)
        end
    end
    table.sort(missing, function(a, b)
        if a.forgeable ~= b.forgeable then return a.forgeable end
        return a.id < b.id
    end)
    return missing
end

---@return number, string?, number?  chance per forge, ore id, ore count
function xDTaraZ.Index.Plan(gear)
    local cached = State.Plans[gear.id]
    if cached then return cached[1], cached[2], cached[3] end

    local forgeUtils = xDTaraZ.GameLib.Api(ReplicatedStorage.Utils.ForgeUtils)
    local helper = xDTaraZ.GameLib.Api(gear.forgeType == "Weapon" and GameConfig.Weapon.Helper or GameConfig.Armor.Helper)
    local bestChance, bestOre, bestCount = 0, nil, nil
    local sliceStart = os.clock()
    for count = 1, Config.ForgeCountMax do
        local split = helper.GetForgePercentByNumber(count)
        if not split then continue end
        for _, oreId in ipairs(xDTaraZ.Ore.Ids()) do
            if os.clock() - sliceStart > Config.PlanSlice then
                task.wait()
                sliceStart = os.clock()
            end
            local list = { [oreId] = count }
            local ok, chance = pcall(function()
                local low, high = forgeUtils.GetForgeOreResult(list)
                local power = forgeUtils.GetOreAvgPower(list)
                local total = 0
                for subType, share in pairs(split) do
                    if share > 0 then
                        total += share * (forgeUtils.GetEquPercent(gear.forgeType, count, low, high, power, subType)[gear.id] or 0)
                    end
                end
                return total
            end)
            if ok and chance > bestChance then
                bestChance, bestOre, bestCount = chance, oreId, count
            end
        end
    end
    State.Plans[gear.id] = { bestChance, bestOre, bestCount }
    return bestChance, bestOre, bestCount
end

function xDTaraZ.Index.Label(gear)
    local show = xDTaraZ.GameLib.Need(GameConfig[gear.forgeType].Show)[gear.id]
    local name = ("%s [%s]"):format(show and show.DisplayName or gear.id, gear.slot)
    if not gear.forgeable then return name .. " - event" end
    local chance = xDTaraZ.Index.Plan(gear)
    return chance > 0 and ("%s - %.2f%%"):format(name, chance * 100) or name .. " - no recipe"
end

function xDTaraZ.Index.Choices()
    local labels, byLabel = {}, {}
    for _, gear in ipairs(xDTaraZ.Index.Missing()) do
        local label = xDTaraZ.Index.Label(gear)
        byLabel[label] = gear
        table.insert(labels, label)
    end
    State.MissingLabels = byLabel
    return labels
end

---@param copies number?  keep forging until this many new copies, ignoring the index
---@return boolean        true once the index has it, or all copies were made
function xDTaraZ.Index.Hunt(gear, copies)
    local chance, oreId, count = xDTaraZ.Index.Plan(gear)
    if chance <= 0 then return false end
    local budget = math.min(Config.HuntMaxForges * (copies or 1), math.ceil(Config.HuntTargetHits * (copies or 1) / chance))
    local key = gear.slot .. "-" .. gear.id
    local forged, got = 0, 0
    while forged < budget and State.Alive do
        local uuid = xDTaraZ.Ore.Ensure(oreId, count * Config.HuntBatch)
        if not uuid then return false end
        local before = xDTaraZ.Data.Snapshot()
        local perWorker = math.ceil(Config.HuntBatch / Config.HuntWorkers)
        xDTaraZ.Util.WaitAll(Config.HuntWorkers, function()
            for _ = 1, perWorker do
                xDTaraZ.Forge.Run(gear.forgeType, { [uuid] = count })
            end
        end)
        forged += perWorker * Config.HuntWorkers
        State.IndexNote = ("%s %d/%d"):format(gear.id, forged, budget)
        local fresh = xDTaraZ.Data.NewGear(before)
        local keep = {}
        for freshUuid, entry in pairs(fresh) do
            if entry.ID == gear.id and (not copies or got < copies) then
                keep[freshUuid] = true
                got += 1
            end
        end
        xDTaraZ.Sell.Fresh(fresh, keep)
        if copies then
            State.IndexNote = ("%s %d/%d"):format(gear.id, got, copies)
            if got >= copies then return true end
        elseif State.Profile.Index.unlocked[key] or next(keep) then
            return true
        end
    end
    return false
end

---@param slot string  "Weapon", "Armor" or "Hat"
---@return string[]    every forgeable piece of that slot, strongest first
function xDTaraZ.Spawn.GearChoices(slot)
    local labels, byLabel, list = {}, {}, {}
    for _, gear in ipairs(xDTaraZ.Index.GearCatalog()) do
        if not gear.forgeable or gear.slot ~= slot then continue end
        local helper = xDTaraZ.GameLib.Api(gear.forgeType == "Weapon" and GameConfig.Weapon.Helper or GameConfig.Armor.Helper)
        local ok, power = pcall(helper.GetMainAffix, gear.id)
        table.insert(list, { gear, ok and tonumber(power) or 0 })
    end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    for _, pair in ipairs(list) do
        local label = xDTaraZ.Index.Label(pair[1])
        byLabel[label] = pair[1]
        table.insert(labels, label)
    end
    State.GearLabels = byLabel
    return labels
end

---@return number, number  found, tried
function xDTaraZ.Index.HuntAll()
    local found, tried = 0, 0
    for _, gear in ipairs(xDTaraZ.Index.Missing()) do
        if not State.Opt.AutoIndex and State.Lock ~= "Index" then break end
        if gear.forgeable and xDTaraZ.Index.Plan(gear) > 0 then
            tried += 1
            if xDTaraZ.Index.Hunt(gear) then found += 1 end
        end
    end
    xDTaraZ.Index.ClaimAll()
    if tried > 0 then State.IndexNote = ("Found %d/%d"):format(found, tried) end
    return found, tried
end

function xDTaraZ.Index.CollectOres()
    for _, stageId in ipairs(xDTaraZ.Stage.List()) do
        xDTaraZ.Stage.Collect(stageId, nil)
    end
    xDTaraZ.Index.ClaimAll()
end

function xDTaraZ.Index.ClaimAll()
    local index = xDTaraZ.Data.Get().Index
    local claimExp = xDTaraZ.Util.Remote("Index", "TryClaimIndexExpRF")
    for key in pairs(index.unlocked) do
        local itemType, itemId = key:match("^(.-)%-(.+)$")
        if itemType and not index.claimed[key] then
            claimExp:InvokeServer(itemType, itemId)
        end
    end
    local claimLevel = xDTaraZ.Util.Remote("Index", "TryClaimLevelRewardRF")
    for _ = 1, Config.IndexLevelClaims do
        if not claimLevel:InvokeServer() then break end
    end
end

function xDTaraZ.Index.Progress()
    local index = xDTaraZ.Data.Get().Index
    local unlocked = 0
    for _ in pairs(index.unlocked) do
        unlocked += 1
    end
    return unlocked, index.level
end

---@param gen number  State.TrainGen at the start; a newer one aborts the search
---@return number?    area entered, nil when none accepted or AutoTrain was toggled meanwhile
function xDTaraZ.Level.FindBestArea(gen)
    local areas = xDTaraZ.GameLib.Need(GameConfig.TrainArea.Config)
    local ids = {}
    for areaId in pairs(areas) do
        table.insert(ids, tonumber(areaId))
    end
    table.sort(ids, function(a, b) return areas[a].Basic > areas[b].Basic end)

    local function Live()
        return State.Opt.AutoTrain and State.TrainGen == gen
    end

    local into = xDTaraZ.Util.Remote("Train", "IntoAutoTrainRE")
    for _, areaId in ipairs(ids) do
        if not Live() then return nil end
        State.TrainPending = areaId
        into:FireServer(areaId)
        local deadline = os.clock() + Config.TrainAcceptWait
        while Live() and os.clock() < deadline and LocalPlayer:GetAttribute("AutoTrainAreaID") ~= areaId do
            task.wait(0.1)
        end
        if LocalPlayer:GetAttribute("AutoTrainAreaID") == areaId then
            State.TrainPending = nil
            return areaId
        end
    end
    State.TrainPending = nil
    return nil
end

function xDTaraZ.Level.Enter()
    if not State.Opt.AutoTrain or State.TrainEntering then return end
    if State.TrainArea then
        if os.clock() - State.TrainFiredAt < Config.TrainAcceptWait then return end
        State.TrainFiredAt = os.clock()
        xDTaraZ.Util.Remote("Train", "IntoAutoTrainRE"):FireServer(State.TrainArea)
        return
    end

    local gen = State.TrainGen
    State.TrainEntering = true
    local ok, areaId = pcall(xDTaraZ.Level.FindBestArea, gen)
    State.TrainEntering = false
    if not ok then error(areaId, 0) end
    if State.TrainGen == gen and areaId then
        State.TrainArea = areaId
        State.TrainFiredAt = os.clock()
    end
end

---Exits the training area and keeps resending until the server drops it; stops if AutoTrain is turned back on or the hub unloaded.
function xDTaraZ.Level.Leave()
    local exit = xDTaraZ.Util.Remote("Train", "ExitAutoTrainRE")
    for _ = 1, Config.TrainExitTries do
        local areaId = LocalPlayer:GetAttribute("AutoTrainAreaID") or State.TrainPending or State.TrainArea
        if not areaId then return end
        exit:FireServer(areaId)
        if not State.Alive then
            State.TrainPending = nil
            return
        end

        task.wait(Config.TrainSettle)
        if State.Opt.AutoTrain then return end
        if not LocalPlayer:GetAttribute("AutoTrainAreaID") then
            State.TrainPending = nil
            return
        end
    end
    warn("[LootToForge] training area still set after", Config.TrainExitTries, "exits")
end

function xDTaraZ.Level.SetTraining(enabled)
    State.TrainGen += 1
    if enabled then
        xDTaraZ.Level.Enter()
    else
        xDTaraZ.Level.Leave()
    end
end

function xDTaraZ.Level.Bind()
    table.insert(State.Conns, LocalPlayer:GetAttributeChangedSignal("AutoTrainAreaID"):Connect(function()
        if not State.Opt.AutoTrain or LocalPlayer:GetAttribute("AutoTrainAreaID") then return end
        task.delay(Config.TrainRejoinDelay, function()
            if State.Opt.AutoTrain and not LocalPlayer:GetAttribute("AutoTrainAreaID") then
                xDTaraZ.Util.Try(xDTaraZ.Level.Enter)
            end
        end)
    end))
end

function xDTaraZ.Level.UsePotions(profile)
    local potionConfig = xDTaraZ.GameLib.Need(GameConfig.Potion.Config)
    local now = workspace:GetAttribute("ServerTime") or os.time()
    local buffs = profile.Buff or {}
    for potionName, count in pairs(profile.Potion or {}) do
        local buffId = potionConfig[potionName] and potionConfig[potionName].BuffID
        local active = buffId and type(buffs[buffId]) == "number" and buffs[buffId] > now
        if type(count) == "number" and count > 0 and not active then
            xDTaraZ.Util.Remote("Potion", "TryUsePotionRE"):FireServer(potionName, 1)
        end
    end
end

function xDTaraZ.Level.TrainStep()
    local profile = xDTaraZ.Data.Get()
    xDTaraZ.Level.UsePotions(profile)
    if profile.Eco.rebirth ~= State.TrainRebirth or profile.Eco.level ~= State.TrainLevel then
        State.TrainRebirth = profile.Eco.rebirth
        State.TrainLevel = profile.Eco.level
        State.TrainArea = nil
    end

    if LocalPlayer:GetAttribute("AutoTrainAreaID") then
        State.TrainNilSince = nil
        return
    end
    State.TrainNilSince = State.TrainNilSince or os.clock()
    if os.clock() - State.TrainNilSince < Config.TrainWatchdog then return end
    xDTaraZ.Level.Enter()
end

function xDTaraZ.Level.Rebirth()
    xDTaraZ.Util.Remote("Rebirth", "TryRebirthRE"):FireServer()
end

function xDTaraZ.Level.RebirthStep()
    local profile = xDTaraZ.Data.Get()
    local ok, needLevel = pcall(xDTaraZ.GameLib.Api(GameConfig.Rebirth.Helper).GetNeedLevel, profile.Eco.rebirth + 1)
    if ok and needLevel and profile.Eco.level >= needLevel then
        xDTaraZ.Level.Rebirth()
    end
end

function xDTaraZ.Level.ClickOnce()
    xDTaraZ.GameLib.Api(ReplicatedStorage.CTRL.TrainCTRL).TrainOnce()
end

function xDTaraZ.Level.StartClicking()
    if State.ClickLoop then return end
    State.ClickLoop = task.defer(function()
        while State.Alive and State.Opt.AutoClick do
            xDTaraZ.Scheduler.Run("AutoClick", xDTaraZ.Level.ClickOnce)
            task.wait(Config.ClickInterval)
        end
        State.ClickLoop = nil
    end)
end

function xDTaraZ.Upgrade.Names()
    local names = {}
    for name in pairs(xDTaraZ.GameLib.Need(GameConfig.Upgrade.Config)) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

function xDTaraZ.Upgrade.BuySelected()
    local buy = xDTaraZ.Util.Remote("Upgrade", "UpgradeOnceRE")
    for name, selected in pairs(State.Opt.Upgrades) do
        if selected then buy:FireServer(name) end
    end
end

---@return number  highest floor that still has a loot table
function xDTaraZ.Tower.LastRound()
    return #xDTaraZ.GameLib.Need(GameConfig.Dungeon.Config.LootTab)
end

function xDTaraZ.Tower.Enter()
    local deadline = os.clock() + 10
    while State.Entering and os.clock() < deadline do
        task.wait(0.1)
    end
    if State.InTower then return true end
    State.Entering = true
    local ok, entered = pcall(function()
        return xDTaraZ.Util.Remote("Dungeon", "TryIntoDungeonRF"):InvokeServer(1)
    end)
    State.Entering = false
    State.InTower = ok and entered and true or false
    return State.InTower
end

function xDTaraZ.Tower.Exit()
    if not State.InTower then return end
    State.InTower = false
    xDTaraZ.Util.Remote("Dungeon", "ExitDungeonRE"):FireServer()
end

function xDTaraZ.Tower.FarmStep()
    if not xDTaraZ.Tower.Enter() then return false end
    local round = xDTaraZ.Tower.LastRound()
    local start = xDTaraZ.Util.Remote("Dungeon", "StartRoundRE")
    local complete = xDTaraZ.Util.Remote("Dungeon", "CompleteRoundRF")
    start:FireServer(round)
    xDTaraZ.Util.WaitAll(Config.TowerWorkers, function()
        for _ = 1, Config.TowerCallsPerWorker do
            if complete:InvokeServer(round) then
                State.TowerLoot += 1
            end
        end
    end)
    return true
end

---@return number  season coins gained
function xDTaraZ.Tower.FarmCoins(target)
    local start = (xDTaraZ.Season.Current() or {}).SeasonCoin or 0
    local deadline = os.clock() + Config.CoinFarmTimeout
    local gained = 0
    while gained < target and os.clock() < deadline do
        if not State.InTower and xDTaraZ.Data.Count(xDTaraZ.Data.Get(), "Dungeon_Ticket") < 1 then break end
        if not xDTaraZ.Tower.FarmStep() then break end
        gained = ((xDTaraZ.Season.Current() or {}).SeasonCoin or 0) - start
    end
    xDTaraZ.Tower.Exit()
    return gained
end

---@return string?  basic attack id of the equipped weapon, nil for an unknown weapon type
function xDTaraZ.Boss.AttackId()
    local weapon = LocalPlayer:GetAttribute("WeaponType")
    return Config.BossAttackIds[weapon]
end

function xDTaraZ.Boss.Join()
    xDTaraZ.Util.Remote("WorldBoss", "IntoWorldBossFight"):FireServer()
    local char = LocalPlayer.Character
    if char and not State.BossReturn then State.BossReturn = char:GetPivot() end
end

---@param boss Model
function xDTaraZ.Boss.StandNear(boss)
    local char = LocalPlayer.Character
    if not char then return end
    local pos = boss:GetPivot().Position
    if (char:GetPivot().Position - pos).Magnitude > Config.BossReach then
        char:PivotTo(CFrame.new(pos + Vector3.new(0, Config.BossStandHeight, Config.BossStandBack), pos))
    end
end

function xDTaraZ.Boss.Step()
    local bossName = workspace:GetAttribute("CurrentWorldBoss")
    if not bossName then return end
    local attackId = xDTaraZ.Boss.AttackId()
    if not attackId then return end
    if LocalPlayer:GetAttribute("IntoFight") ~= "WorldBoss" then
        xDTaraZ.Boss.Join()
        task.wait(Config.BossJoinSettle)
    end

    local boss = workspace.EnemyFolder_Server:FindFirstChild(bossName)
    if not boss or boss:GetAttribute("Dead") then return end
    xDTaraZ.Boss.StandNear(boss)
    local announce = xDTaraZ.Util.Remote("Attack", "UseAnyATKRE")
    local attack = xDTaraZ.Util.Remote("Attack", "AttackEnemyServiceRE")
    for _ = 1, Config.BossHitsPerTick do
        if not (State.Opt.AutoWorldBoss and boss.Parent) then return end
        announce:FireServer(attackId, workspace:GetServerTimeNow())
        attack:FireServer({ bossName }, { Phase = 1, SkillID = attackId, Attacker = LocalPlayer }, workspace:GetServerTimeNow())
        task.wait(Config.BossHitGap)
    end
end

function xDTaraZ.Boss.ClaimCards()
    local claim = xDTaraZ.Util.Remote("WorldBoss", "TryClaimBossRewardRE")
    for card = 1, Config.BossCards do
        task.spawn(claim.FireServer, claim, tostring(card))
    end
end

function xDTaraZ.Boss.Leave()
    xDTaraZ.Util.Remote("WorldBoss", "ExitWorldBossFight"):FireServer()
    LocalPlayer:SetAttribute("IntoFight", nil)
    local char = LocalPlayer.Character
    if State.BossReturn and char then char:PivotTo(State.BossReturn) end
    State.BossReturn = nil
end

function xDTaraZ.Boss.Bind()
    table.insert(State.Conns, xDTaraZ.Util.Remote("WorldBoss", "BossDeadRE").OnClientEvent:Connect(function()
        if not State.Opt.AutoWorldBoss then return end
        task.delay(Config.BossClaimDelay, function()
            if State.Opt.BossCards then xDTaraZ.Util.Try(xDTaraZ.Boss.ClaimCards) end
            xDTaraZ.Util.Try(xDTaraZ.Boss.Leave)
            State.BossDone = os.clock()
        end)
    end))
    table.insert(State.Conns, xDTaraZ.Util.Remote("WorldBoss", "BossEscapeRE").OnClientEvent:Connect(function()
        if State.Opt.AutoWorldBoss then xDTaraZ.Util.Try(xDTaraZ.Boss.Leave) end
    end))
end

function xDTaraZ.Season.Current()
    local seasons = xDTaraZ.Data.Get().Season or {}
    local bestKey = xDTaraZ.Util.HighestKey(seasons)
    return bestKey and seasons[bestKey]
end

function xDTaraZ.Season.Goods()
    local goods = xDTaraZ.GameLib.Need(GameConfig.Season.GoodsConfig)
    local ids = {}
    for goodId in pairs(goods) do
        table.insert(ids, goodId)
    end
    table.sort(ids, function(a, b) return tonumber(a) < tonumber(b) end)
    local labels, byLabel = {}, {}
    for _, goodId in ipairs(ids) do
        local good = goods[goodId]
        local label = ("%s x%d (%d coin)"):format(good.ID, good.Number, good.NeedSeasonCoin)
        byLabel[label] = goodId
        table.insert(labels, label)
    end
    return labels, byLabel
end

---@return number  exclusive gear bought, farming the coins first when short
function xDTaraZ.Season.BuyExclusive()
    local goods = xDTaraZ.GameLib.Need(GameConfig.Season.GoodsConfig)
    local exchange = xDTaraZ.Util.Remote("Season", "ExchangeGoodsRE")
    local bought = 0
    for goodId, good in pairs(goods) do
        if good.Type ~= "Weapon" and good.Type ~= "Armor" and good.Type ~= "Hat" then continue end
        local season = xDTaraZ.Season.Current()
        if not season or ((season.Goods or {})[goodId] or 0) >= (good.Store or 1) then continue end
        local short = good.NeedSeasonCoin - (season.SeasonCoin or 0)
        if short > 0 then xDTaraZ.Tower.FarmCoins(short) end
        exchange:FireServer(goodId)
        bought += 1
        task.wait(0.5)
    end
    return bought
end

function xDTaraZ.Season.BuyGoods()
    local goods = xDTaraZ.GameLib.Need(GameConfig.Season.GoodsConfig)
    local exchange = xDTaraZ.Util.Remote("Season", "ExchangeGoodsRE")
    for goodId, wanted in pairs(State.Opt.SeasonGoods) do
        local good = goods[goodId]
        if not (wanted and good) then continue end
        for _ = 1, good.Store or 1 do
            local season = xDTaraZ.Season.Current()
            if not season or (season.SeasonCoin or 0) < good.NeedSeasonCoin then break end
            exchange:FireServer(goodId)
            task.wait(0.3)
        end
    end
end

function xDTaraZ.Season.Step()
    xDTaraZ.Util.Remote("Season", "TryClaimDailyTicRE"):FireServer()
    xDTaraZ.Util.Remote("Season", "TryClaimAllRewardRE"):FireServer()
    task.wait(0.5)
    xDTaraZ.Season.BuyGoods()
    local season = xDTaraZ.Season.Current()
    if not (season and State.Opt.SeasonSpin) then return end
    local luck = xDTaraZ.Util.Remote("Season", "LuckRE")
    for _ = 1, season.SeasonTicket or 0 do
        luck:FireServer(1)
        task.wait(0.5)
    end
end

function xDTaraZ.Claim.All()
    xDTaraZ.Util.Remote("Offline", "TryClaimOfflineRewardRE"):FireServer()
    xDTaraZ.Util.Remote("Dungeon", "TryClaimDailyDunTicRE"):FireServer()
    xDTaraZ.Util.Try(xDTaraZ.Index.ClaimAll)

    local claimQuest = xDTaraZ.Util.Remote("EnhantEvent", "TryClaimQuestRE")
    local claimUpdate = xDTaraZ.Util.Remote("UpdateLog", "TryClaimUPDRewardRE")
    for id = 1, Config.ClaimIdScan do
        claimQuest:FireServer(id)
        claimUpdate:FireServer(id)
    end

    local ok, rewards = pcall(xDTaraZ.GameLib.Api(GameConfig.Online.Helper).GetOnlineRewardConfig)
    for rewardName in pairs(ok and type(rewards) == "table" and rewards or {}) do
        xDTaraZ.Util.Remote("Online", "TryClaimRE"):FireServer(rewardName)
    end
end

---@return string  the server's message for this code ("no reply" when it stayed silent)
function xDTaraZ.Claim.Code(code)
    local message
    local hasListener, messageEvent = pcall(xDTaraZ.Util.Remote, "Message", "MessageRE")
    local conn = hasListener and messageEvent.OnClientEvent:Connect(function(text)
        message = message or tostring(text)
    end)
    local ok, err = pcall(function()
        return xDTaraZ.Util.Remote("Code", "TryUseCodeRF"):InvokeServer(code)
    end)
    local deadline = os.clock() + Config.CodeReplyWait
    while conn and not message and os.clock() < deadline do task.wait(0.05) end
    if conn then conn:Disconnect() end
    if not ok then return "failed: " .. tostring(err) end
    return message or "no reply"
end

function xDTaraZ.Claim.AllCodes()
    local results = {}
    for _, code in ipairs(Config.Codes) do
        table.insert(results, ("%s: %s"):format(code, xDTaraZ.Claim.Code(code)))
    end
    return table.concat(results, "\n")
end

function xDTaraZ.SuperLoot.Kill(uuid)
    xDTaraZ.Util.Remote("SuperLoot", "KillSuperLootRE"):FireServer(uuid)
    task.wait(0.2)
    xDTaraZ.Util.Remote("Stage", "GetOreRF"):InvokeServer(uuid)
    xDTaraZ.Util.Remote("Stage", "ClaimedAllOreRE"):FireServer()
end

function xDTaraZ.SuperLoot.KillExisting()
    for _, enemy in ipairs(workspace.EnemyFolder:GetChildren()) do
        local enemyId = enemy:GetAttribute("EnemyID")
        if enemyId and enemyId:find("^Super") then
            task.spawn(xDTaraZ.Util.Try, xDTaraZ.SuperLoot.Kill, enemy.Name)
        end
    end
end

function xDTaraZ.SuperLoot.Bind()
    table.insert(State.Conns, xDTaraZ.Util.Remote("SuperLoot", "RefreshSuperLootRE").OnClientEvent:Connect(function(_, uuid)
        if State.Opt.SuperLootAura then
            task.spawn(xDTaraZ.Util.Try, xDTaraZ.SuperLoot.Kill, uuid)
        end
    end))
end

function xDTaraZ.Combat.KillAll()
    local hit = xDTaraZ.GameLib.Api(ReplicatedStorage.Utils.CommunicationUtils).TryGetBindableEvent("Attack", "EnemyHitBE")
    local hitInfo = { SkillID = "K_ATK_1", IsCrit = true, Damage = Config.KillDamage }
    for _, enemy in ipairs(workspace.EnemyFolder:GetChildren()) do
        local enemyId = enemy:GetAttribute("EnemyID")
        if enemyId and not enemyId:find("^Super") then
            hit:Fire(enemy.Name, Config.KillDamage, hitInfo)
        end
    end
end

function xDTaraZ.Combat.Start()
    if State.AuraLoop then return end
    State.AuraLoop = task.defer(function()
        while State.Alive and State.Opt.KillAura do
            xDTaraZ.Scheduler.Run("KillAura", xDTaraZ.Combat.KillAll)
            task.wait(Config.KillAuraInterval)
        end
        State.AuraLoop = nil
    end)
end

---@return boolean  false when the game's damage function can't be reached
function xDTaraZ.Guard.HookDamage()
    if State.RestoreDamage then return true end
    local hpCtrl = xDTaraZ.GameLib.Require(ReplicatedStorage.CTRL.HPCTRL)
    local damageOnce = hpCtrl and hpCtrl.DamageOnce
    if type(damageOnce) ~= "function" then return false end

    hpCtrl.DamageOnce = function(target, damage)
        if target == LocalPlayer and State.Opt.GodMode then return false end
        return damageOnce(target, damage)
    end
    State.RestoreDamage = function()
        hpCtrl.DamageOnce = damageOnce
        State.RestoreDamage = nil
    end
    return true
end

---@return boolean  false when the executor can't hook namecall or the remote is missing
function xDTaraZ.Guard.HookOreLoss()
    if State.RestoreNamecall then return true end
    local compat = xDTaraZ.Compat
    if not (compat and compat.Caps.Namecall) then return false end
    local found, lostOre = pcall(xDTaraZ.Util.Remote, "Stage", "LostAllOreRF")
    if not found then
        warn("[LootToForge] keep ore:", lostOre)
        return false
    end

    local original, restore
    original, restore = compat.HookMeta(game, "__namecall", function(self, ...)
        if self == lostOre and State.Opt.KeepOre and getnamecallmethod() == "InvokeServer" then
            return {}
        end
        return original(self, ...)
    end)
    if not original then return false end

    State.RestoreNamecall = function()
        State.RestoreNamecall = nil
        restore()
    end
    return true
end

function xDTaraZ.Guard.UnhookOreLoss()
    if State.RestoreNamecall then State.RestoreNamecall() end
end

function xDTaraZ.Guard.Stop()
    if State.RestoreDamage then State.RestoreDamage() end
    xDTaraZ.Guard.UnhookOreLoss()
end

function xDTaraZ.Race.Choices()
    local classConfig = xDTaraZ.GameLib.Need(GameConfig.Class.Config)
    local show = xDTaraZ.GameLib.Need(GameConfig.Class.Show)
    local ids = {}
    for classId in pairs(classConfig) do
        table.insert(ids, classId)
    end
    table.sort(ids, function(a, b) return classConfig[a].Weight < classConfig[b].Weight end)

    local labels, idByLabel = {}, {}
    for _, classId in ipairs(ids) do
        local label = ("%s (%s)"):format(show[classId] and show[classId].DisplayName or classId, classConfig[classId].Rarity)
        idByLabel[label] = classId
        table.insert(labels, label)
    end
    return labels, idByLabel
end

function xDTaraZ.Race.EquipBest()
    local classData = xDTaraZ.Data.Get().Class
    local classConfig = xDTaraZ.GameLib.Need(GameConfig.Class.Config)
    local bestSlot, bestWeight = nil, math.huge
    for slot, classId in pairs(classData.have) do
        local weight = classConfig[classId] and classConfig[classId].Weight or math.huge
        if weight < bestWeight then bestSlot, bestWeight = slot, weight end
    end
    if not bestSlot or tostring(bestSlot) == tostring(classData.equiped) then return false end
    xDTaraZ.Util.Remote("Class", "ChangeEquipedIndexRE"):FireServer(tostring(bestSlot))
    return true
end

function xDTaraZ.Race.RollUntil(targetId)
    local roll = xDTaraZ.Util.Remote("Class", "LuckOnceRE")
    while State.Opt.AutoRace do
        local classData = xDTaraZ.Data.Get().Class
        if classData.have[classData.equiped] == targetId then return "got" end
        if (classData.luckTimes or 0) <= 0 then return "empty" end
        roll:FireServer(tostring(classData.equiped))
        task.wait(Config.RaceRollDelay)
    end
    return "stopped"
end

function xDTaraZ.Movement.Humanoid()
    return LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
end

function xDTaraZ.Movement.Apply()
    local hum = xDTaraZ.Movement.Humanoid()
    if not hum then return end
    hum.WalkSpeed = State.Opt.SpeedOn and State.Opt.WalkSpeed or (LocalPlayer:GetAttribute("OriWalkSpeed") or 22)
end

function xDTaraZ.Movement.Bind()
    table.insert(State.Conns, UserInputService.JumpRequest:Connect(function()
        local hum = xDTaraZ.Movement.Humanoid()
        if State.Opt.InfJump and hum then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end))
    table.insert(State.Conns, LocalPlayer.CharacterAdded:Connect(function()
        task.wait(1)
        xDTaraZ.Movement.Apply()
    end))
end

function xDTaraZ.Session.SetLowGraphics(enabled)
    RunService:Set3dRenderingEnabled(not enabled)
end

function xDTaraZ.Session.Rejoin()
    local queue = queue_on_teleport or queueonteleport
    if queue then queue(Config.ReloadSource) end
    TeleportService:Teleport(game.PlaceId, LocalPlayer)
end

function xDTaraZ.Boss.HopFlag(enabled)
    local flag = Config.SaveFolder .. "/" .. Config.BossHopFlag
    pcall(function()
        if enabled then
            if not isfolder(Config.SaveFolder) then makefolder(Config.SaveFolder) end
            writefile(flag, tostring(os.time()))
        elseif isfile(flag) then
            delfile(flag)
        end
    end)
end

---@return number?  seconds since the last hop, nil when no hop is pending
function xDTaraZ.Boss.SinceLastHop()
    local ok, stamp = pcall(readfile, Config.SaveFolder .. "/" .. Config.BossHopFlag)
    if not ok or not tonumber(stamp) then return nil end
    return os.time() - tonumber(stamp)
end

---@return boolean  true only right after a hop, so a fresh launch never starts hopping by itself
function xDTaraZ.Boss.HopWanted()
    local since = xDTaraZ.Boss.SinceLastHop()
    return since ~= nil and since < Config.BossHopResume
end

---@return string[], number  unvisited servers from the saved list, and when it was fetched
function xDTaraZ.Boss.LoadServers()
    local ok, text = pcall(readfile, Config.SaveFolder .. "/" .. Config.BossHopServers)
    if not ok then return {}, 0 end
    local decoded
    ok, decoded = pcall(HttpService.JSONDecode, HttpService, text)
    if not ok or type(decoded) ~= "table" or type(decoded.ids) ~= "table" then return {}, 0 end
    local fetchedAt = tonumber(decoded.at) or 0
    if os.time() - fetchedAt > Config.HopListTtl then return {}, 0 end
    return decoded.ids, fetchedAt
end

---@param ids string[]    servers still unvisited
---@param fetchedAt number  when the list came from the API
function xDTaraZ.Boss.SaveServers(ids, fetchedAt)
    pcall(function()
        if not isfolder(Config.SaveFolder) then makefolder(Config.SaveFolder) end
        writefile(Config.SaveFolder .. "/" .. Config.BossHopServers, HttpService:JSONEncode({ at = fetchedAt, ids = ids }))
    end)
end

---@return string[]  public servers with room; empty while the API refuses (waits 2x longer after each refusal)
function xDTaraZ.Boss.FetchServers()
    if os.clock() < State.HopBlockedUntil then return {} end
    local body = xDTaraZ.Util.HttpGet(("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(game.PlaceId))
    local ok, list = pcall(HttpService.JSONDecode, HttpService, body or "")
    local ids = {}
    for _, server in ipairs(ok and type(list) == "table" and type(list.data) == "table" and list.data or {}) do
        if server.id ~= game.JobId and server.playing < server.maxPlayers then table.insert(ids, server.id) end
    end
    if #ids > 0 then
        State.HopFails, State.HopBackoff = 0, nil
        return ids
    end
    State.HopFails += 1
    State.HopBackoff = math.min((State.HopBackoff or Config.HopBackoffStart / 2) * 2, Config.HopBackoffMax)
    State.HopBlockedUntil = os.clock() + State.HopBackoff
    warn("[LootToForge] server list refused, retry in", State.HopBackoff, "s, fail", State.HopFails)
    return {}
end

---@return string?  a public server with room, not this one
function xDTaraZ.Boss.PickServer()
    local ids, fetchedAt = xDTaraZ.Boss.LoadServers()
    if #ids == 0 then
        ids, fetchedAt = xDTaraZ.Boss.FetchServers(), os.time()
    end
    while #ids > 0 do
        local serverId = table.remove(ids, math.random(#ids))
        if serverId ~= game.JobId then
            xDTaraZ.Boss.SaveServers(ids, fetchedAt)
            return serverId
        end
    end
    xDTaraZ.Boss.SaveServers(ids, fetchedAt)
    return nil
end

function xDTaraZ.Boss.Hop()
    local serverId = xDTaraZ.Boss.PickServer()
    if not serverId then return end
    State.BossHopping = os.clock()
    xDTaraZ.Boss.HopFlag(true)
    local queue = queue_on_teleport or queueonteleport
    if queue and not State.HopQueued then
        queue(Config.ReloadSource)
        State.HopQueued = true
    end
    TeleportService:TeleportToPlaceInstance(game.PlaceId, serverId, LocalPlayer)
end

---@return boolean  true when this server is worth staying in: boss up, boss about to spawn, or still collecting
function xDTaraZ.Boss.WorthStaying()
    local boss = workspace:GetAttribute("CurrentWorldBoss")
    if boss and not State.BossDone then return true end
    if State.BossDone then return os.clock() - State.BossDone < Config.BossHopAfter end
    local nextTick, serverTime = workspace:GetAttribute("NextWorldBossTick"), workspace:GetAttribute("ServerTime")
    if not nextTick or not serverTime then return true end
    return nextTick - serverTime <= Config.BossHopLead
end

function xDTaraZ.Boss.HopGiveUp()
    State.Opt.BossHop = false
    xDTaraZ.Boss.HopFlag(false)
    table.insert(State.Halted, { "BossHop", "no server list from Roblox, try again later" })
end

function xDTaraZ.Boss.HopStep()
    if State.BossHopping then
        if os.clock() - State.BossHopping < Config.HopStall then return end
        State.BossHopping = false
    end
    if xDTaraZ.Boss.WorthStaying() then return end
    if (xDTaraZ.Boss.SinceLastHop() or Config.HopGap) < Config.HopGap then return end
    if State.HopFails >= Config.HopGiveUp then
        xDTaraZ.Boss.HopGiveUp()
        return
    end
    xDTaraZ.Boss.Hop()
end

function xDTaraZ.Session.Bind()
    table.insert(State.Conns, TeleportService.TeleportInitFailed:Connect(function()
        if not State.BossHopping then return end
        State.BossHopping = false
        task.delay(1, xDTaraZ.Util.Try, xDTaraZ.Boss.HopStep)
    end))
    table.insert(State.Conns, LocalPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end))
    table.insert(State.Conns, GuiService.ErrorMessageChanged:Connect(function(msg)
        if State.Opt.AutoRejoin and msg ~= "" then
            task.delay(Config.RejoinDelay, xDTaraZ.Session.Rejoin)
        end
    end))
end

xDTaraZ.Scheduler.Jobs = {
    { key = "MaxGear", every = 0, run = function() xDTaraZ.Gear.MaxStep() end },
    { key = "CollectOre", every = 0, run = function() xDTaraZ.Stage.Collect(State.Opt.Stage or xDTaraZ.Stage.Best(), State.Opt.CollectRarities) end },
    { key = "AutoForge", every = 0, run = function() xDTaraZ.Forge.Step() end },
    { key = "AutoEquip", every = Config.EquipInterval, run = function() xDTaraZ.Gear.EquipBest() end },
    { key = "AutoSell", every = Config.SellInterval, run = function() xDTaraZ.Sell.Run(xDTaraZ.Data.Get()) end },
    { key = "AutoTrain", every = 1, run = function() xDTaraZ.Level.TrainStep() end },
    { key = "AutoRebirth", every = Config.RebirthInterval, run = function() xDTaraZ.Level.RebirthStep() end },
    { key = "AutoUpgrade", every = Config.UpgradeInterval, run = function() xDTaraZ.Upgrade.BuySelected() end },
    { key = "AutoTower", every = 0, run = function() xDTaraZ.Tower.FarmStep() end },
    { key = "AutoWorldBoss", every = Config.BossInterval, run = function() xDTaraZ.Boss.Step() end },
    { key = "BossHop", every = Config.BossHopInterval, run = function() xDTaraZ.Boss.HopStep() end },
    { key = "AutoClaim", every = Config.ClaimInterval, run = function() xDTaraZ.Claim.All() end },
    { key = "AutoSeason", every = Config.SeasonInterval, run = function() xDTaraZ.Season.Step() end },
    { key = "AutoBestRace", every = 10, run = function() xDTaraZ.Race.EquipBest() end },
    { key = "AutoIndex", every = Config.IndexInterval, run = function() xDTaraZ.Util.Exclusive("Index", xDTaraZ.Index.HuntAll) end },
}

---Runs one round of a feature; one that keeps failing for Config.FailWindow seconds is switched off and queued for the UI to report.
---@param key string  State.Opt flag of the feature
function xDTaraZ.Scheduler.Run(key, fn)
    local ok, err = pcall(fn)
    local failures = State.Failures
    if ok then
        failures[key] = nil
        return
    end

    local streak = failures[key]
    if not streak then
        streak = { count = 0, since = os.clock() }
        failures[key] = streak
        xDTaraZ.Util.WarnJob(key, err)
    end
    streak.count += 1
    if streak.count < Config.MaxFailures or os.clock() - streak.since < Config.FailWindow then return end

    failures[key] = nil
    State.Opt[key] = false
    local reason = tostring(err):match("[^\n]*")
    warn("[LootToForge]", key, "stopped:", reason)
    table.insert(State.Halted, { key, reason })
end

function xDTaraZ.Scheduler.Step()
    if State.Lock then return end
    local now = os.clock()
    for _, job in ipairs(xDTaraZ.Scheduler.Jobs) do
        if not State.Opt[job.key] or State.Lock then continue end
        if now - (State.LastRun[job.key] or 0) < job.every then continue end
        State.LastRun[job.key] = now
        xDTaraZ.Scheduler.Run(job.key, job.run)
    end
end

function xDTaraZ.Scheduler.Start()
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

function xDTaraZ.Scheduler.Boot()
    for _, bind in ipairs({ xDTaraZ.Movement.Bind, xDTaraZ.Level.Bind, xDTaraZ.SuperLoot.Bind, xDTaraZ.Boss.Bind, xDTaraZ.Session.Bind }) do
        xDTaraZ.Util.Try(bind)
    end
    xDTaraZ.Scheduler.Start()
end

function xDTaraZ.Scheduler.Stop()
    State.Alive = false
    for _, conn in ipairs(State.Conns) do
        conn:Disconnect()
    end
    table.clear(State.Conns)
    if State.Opt.AutoTrain then
        State.Opt.AutoTrain = false
        task.spawn(xDTaraZ.Util.Try, xDTaraZ.Level.SetTraining, false)
    end
    if State.Opt.SpeedOn then
        State.Opt.SpeedOn = false
        xDTaraZ.Movement.Apply()
    end
    if State.Opt.LowGraphics then
        xDTaraZ.Session.SetLowGraphics(false)
    end
    xDTaraZ.Util.Try(xDTaraZ.Tower.Exit)
    if LocalPlayer:GetAttribute("IntoFight") == "WorldBoss" then xDTaraZ.Util.Try(xDTaraZ.Boss.Leave) end
    xDTaraZ.Guard.Stop()
end

local function BuildInterface()
    local Library = xDTaraZ.Util.LoadLibrary()
    if not Library then return end
    xDTaraZ.Compat = Library.Compat or { Caps = {}, Block = function() end, NeedCap = function() end }
    pcall(NovaBanner.Step, "UI library")
    local Options = Library.Options
    local T = function(en, th) return Library:T(en, th) end
    local opt = State.Opt
    local featureNames = {}
    local uiQueue = {}
    local statusLabel, gearLabel, taskLabel

    ---@return table, table  empty tables when the game data can't be read
    local function Source(fn)
        local ok, first, second = pcall(fn)
        if not ok then
            warn("[LootToForge] menu data:", first)
            return {}, {}
        end
        return first or {}, second or {}
    end

    local rarityNames = Source(xDTaraZ.Util.RarityNames)

    local function Later(fn, ...)
        local args = table.pack(...)
        table.insert(uiQueue, function()
            fn(table.unpack(args, 1, args.n))
        end)
    end

    local function Notify(text, kind, seconds)
        Later(Library.Notify, Library, "Loot To Forge", text, seconds or 4, kind or "Info")
    end

    local function TurnOff(key)
        local toggle = Options[key]
        if toggle and toggle.Value then toggle:SetValue(false) end
    end

    ---@param pickFirst boolean?  also select the first entry
    local function SetList(idx, values, pickFirst)
        local dropdown = Options[idx]
        if not dropdown then return end
        dropdown:SetValues(values)
        if pickFirst and values[1] then
            dropdown:SetValue(values[1])
        elseif dropdown.Value ~= opt[idx] then
            dropdown:SetValue(dropdown.Value)
        end
    end

    ---@param module Instance  game module the feature can't run without
    local function NeedModule(option, module)
        if xDTaraZ.GameLib.Require(module) then return end
        xDTaraZ.Compat.Block(option, T("Not available on this executor", "ใช้กับ executor นี้ไม่ได้"))
    end

    local function BlockMissing()
        for idx, paths in pairs(xDTaraZ.GameLib.Missing()) do
            warn("[LootToForge]", idx, "blocked, missing:", table.concat(paths, ", "))
            if Options[idx] then xDTaraZ.Compat.Block(Options[idx], T("Not available after a game update", "ใช้ไม่ได้หลังเกมอัปเดต")) end
        end
    end

    local function Pump()
        for _, halt in ipairs(State.Halted) do
            TurnOff(halt[1])
            Notify(("%s stopped: %s"):format(featureNames[halt[1]] or halt[1], halt[2]), "Warning")
        end
        table.clear(State.Halted)

        local jobs = uiQueue
        uiQueue = {}
        for _, job in ipairs(jobs) do
            xDTaraZ.Util.Try(job)
        end
    end

    local function Action(action)
        return function()
            task.defer(xDTaraZ.Util.Try, action)
        end
    end

    ---@param name string  lock name, also the busy message
    local function LongAction(name, action, done)
        return function()
            task.defer(function()
                if State.Lock then return Notify("Busy: " .. State.Lock, "Warning") end
                Notify(name .. "...")
                local outcome
                xDTaraZ.Util.Exclusive(name, function() outcome = action() end)
                if done then Notify(done(outcome), "Success") end
            end)
        end
    end

    local function Toggle(group, key, text, description, onChange, risky)
        featureNames[key] = text.EN
        return group:AddToggle(key, {
            Text = text,
            Description = description,
            Risky = risky,
            Default = opt[key],
            Callback = function(value)
                opt[key] = value
                if onChange then
                    onChange(value)
                end
            end,
        })
    end

    local Feature = Toggle

    local function HotkeyFeature(group, key, text, description, onChange, risky)
        return Toggle(group, key, text, description, onChange, risky):AddKeyPicker(key .. "Key", { Default = "None", Mode = "Toggle" })
    end

    local function Check(group, key, text)
        return group:AddCheckbox(key, {
            Text = text,
            Default = opt[key],
            Callback = function(value)
                opt[key] = value
            end,
        })
    end

    local function MultiSelect(group, key, text, description, values)
        opt[key] = xDTaraZ.Util.AllSet(values)
        return group:AddDropdown(key, {
            Text = text,
            Description = description,
            Values = values,
            Multi = true,
            Default = values,
            Searchable = #values > 8,
            Callback = function(selected)
                opt[key] = selected
            end,
        })
    end

    ---@param source function  returns the dropdown values, read safely
    local function Pick(group, key, text, description, source, noSave, risky)
        local values = Source(source)
        opt[key] = values[1]
        return group:AddDropdown(key, {
            Text = text,
            Description = description,
            Risky = risky,
            Values = values,
            Default = 1,
            Searchable = #values > 8,
            NoSave = noSave,
            Callback = function(value)
                opt[key] = value
            end,
        })
    end

    local function NumberInput(group, key, text, description, minimum)
        return group:AddInput(key, {
            Text = text,
            Description = description,
            Default = tostring(opt[key]),
            Numeric = true,
            Finished = true,
            Callback = function(value)
                opt[key] = math.max(minimum or 0, math.floor(tonumber(value) or opt[key]))
            end,
        })
    end

    local function RefreshButton(idx, list)
        return { Text = T("Refresh", "รีเฟรช"), Func = function()
            task.defer(function()
                Later(SetList, idx, (Source(list)))
            end)
        end }
    end

    local function BuildMain(tab)
        local statusBox = tab:AddLeftGroupbox(T("Status", "สถานะ"))
        statusLabel = statusBox:AddLabel("Loading...")
        gearLabel = statusBox:AddLabel("Equipped: -")
        taskLabel = statusBox:AddLabel("Working on: Idle")

        local kaitunBox = tab:AddLeftGroupbox(T("Kaitun", "ไก่ตัน"))
        kaitunBox:AddToggle("Kaitun", {
            Text = T("Kaitun (All-in-one)", "ไก่ตัน (ทำทุกอย่าง)"),
            Description = T("Best gear, money, level, rewards and bosses all at once", "ของดีสุด เงิน เลเวล รางวัล และบอส ทำพร้อมกันทั้งหมด"),
            NoSave = true,
            Callback = function(value)
                for _, key in ipairs(Config.KaitunToggles) do
                    if Options[key] then Options[key]:SetValue(value) end
                end
            end,
        })
        kaitunBox:AddButton({ Text = T("Panic - All Off", "ฉุกเฉิน ปิดทั้งหมด"), Style = "Danger", Func = function()
            TurnOff("Kaitun")
            for key in pairs(featureNames) do
                TurnOff(key)
            end
        end })

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

        local gearBox = tab:AddRightGroupbox(T("Max Gear", "อุปกรณ์สูงสุด"))
        Feature(gearBox, "MaxGear", T("Max Gear", "อุปกรณ์สูงสุด"),
            T("Best gear and runes, enhanced to your target. Finds anything missing by itself", "ของดีสุด รูนดีสุด ตีบวกถึงเป้า ขาดอะไรหาเองหมด"),
            function()
                State.GearForged = false
            end)
        Check(gearBox, "GearForge", T("Forge best gear", "หลอมของดีสุด"))
        Check(gearBox, "GearEnchant", T("Best runes", "ใส่รูนดีสุด"))
        Check(gearBox, "GearEnhance", T("Enhance", "ตีบวก"))
        gearBox:AddSlider("EnhanceTarget", {
            Text = T("Enhance Target", "ตีบวกถึง"),
            Description = T("Above +10 the success rate gets very low and can take a long time", "เกิน +10 โอกาสสำเร็จต่ำมาก อาจใช้เวลานาน"),
            Min = 5, Max = 20, Default = opt.EnhanceTarget, Rounding = 0, Prefix = "+",
            Callback = function(value)
                opt.EnhanceTarget = value
            end,
        })
        local runes = xDTaraZ.Gear.RuneOrder()
        opt.EnchantPriority = table.clone(runes)
        gearBox:AddDropdown("EnchantPriority", {
            Text = T("Runes To Use", "รูนที่ใช้"),
            Description = T("Stronger runes go in first", "รูนที่แรงกว่าใส่ก่อน"),
            Values = runes,
            Multi = true,
            Default = runes,
            Searchable = #runes > 8,
            Callback = function(selected)
                local order = {}
                for _, stoneId in ipairs(runes) do
                    if selected[stoneId] then order[#order + 1] = stoneId end
                end
                if #order == 0 then Notify("No rune selected, using all runes", "Warning") end
                opt.EnchantPriority = order
            end,
        })

        local equipBox = tab:AddLeftGroupbox(T("Equip", "ใส่ของ"))
        Feature(equipBox, "AutoEquip", T("Auto Equip Best", "ใส่ของดีสุดอัตโนมัติ"), T("Always wears your strongest weapon, armor and hat, counting enhance level", "ใส่อาวุธ เกราะ และหมวกที่แรงที่สุดเสมอ นับระดับตีบวกด้วย"))
        equipBox:AddButton({ Text = T("Equip Best Now", "ใส่ของดีสุดเดี๋ยวนี้"), Func = function()
            task.defer(function()
                local changed = xDTaraZ.Gear.EquipBest()
                Notify(changed > 0 and ("Equipped %d better item(s)"):format(changed) or "Already wearing your best gear")
            end)
        end })

        equipBox:AddDivider()
        equipBox:AddDropdown("EnhanceSlot", {
            Text = T("Enhance Slot", "ช่องที่ตีบวก"),
            Values = Config.GearTypes,
            Default = opt.EnhanceSlot,
            Callback = function(value)
                opt.EnhanceSlot = value or opt.EnhanceSlot
            end,
        })
        equipBox:AddButton({ Text = T("Enhance To Target", "ตีบวกถึงเป้า"), Style = "Primary", Func = LongAction("Enhance", function()
            return xDTaraZ.Gear.EnhanceSlot(opt.EnhanceSlot, opt.EnhanceTarget)
        end, function(level) return level and ("%s is +%d"):format(opt.EnhanceSlot, level) or "Nothing equipped there" end) })

        local rewardBox = tab:AddRightGroupbox(T("Rewards", "รางวัล"))
        Feature(rewardBox, "AutoClaim", T("Auto Claim", "รับรางวัลอัตโนมัติ"), T("Claims every free reward, including index", "รับรางวัลฟรีทุกอย่าง รวมสมุดสะสม"))
        rewardBox:AddButton({ Text = T("Claim Now", "รับเดี๋ยวนี้"), Style = "Success", Func = Action(xDTaraZ.Claim.All) })
        rewardBox:AddButton({ Text = T("Redeem All Codes", "ใช้โค้ดทั้งหมด"), Style = "Primary", Func = Action(function()
            Notify(xDTaraZ.Claim.AllCodes(), "Success", 6)
        end) })
        rewardBox:AddInput("Code", {
            Text = T("Redeem Code", "ใส่โค้ด"),
            Placeholder = T("Code", "โค้ด"),
            Finished = true,
            NoSave = true,
            Callback = function(value)
                if value == "" then return end
                task.defer(function()
                    Notify("Code: " .. tostring(xDTaraZ.Claim.Code(value)))
                end)
            end,
        })
    end

    local function BuildFarm(tab)
        local stageBox = tab:AddLeftGroupbox(T("Stage", "ด่าน"))
        Pick(stageBox, "Stage", T("Stage", "ด่าน"), T("Any stage, no unlock needed", "เลือกด่านไหนก็ได้ ไม่ต้องปลดล็อก"), xDTaraZ.Stage.List)
        Feature(stageBox, "CollectOre", T("Auto Collect Ore", "เก็บแร่อัตโนมัติ"), T("Clears the stage and collects its ores nonstop", "เคลียร์ด่านแล้วเก็บแร่ไม่หยุด"))
        MultiSelect(stageBox, "CollectRarities", T("Ore Rarity Filter", "กรอง rarity แร่"), T("Only collect these rarities", "เก็บเฉพาะ rarity ที่เลือก"), rarityNames)

        local combatBox = tab:AddLeftGroupbox(T("Combat", "ต่อสู้"))
        local killAura = Feature(combatBox, "KillAura", T("Kill Aura", "ฆ่ารอบตัว"), T("Every monster in your fight dies instantly", "มอนสเตอร์ทุกตัวในการต่อสู้ตายทันที"), function(value)
            if value then xDTaraZ.Combat.Start() end
        end)
        NeedModule(killAura, ReplicatedStorage.Utils.CommunicationUtils)
        Feature(combatBox, "SuperLootAura", T("Kill Ore Boss", "ฆ่าบอสแร่"), T("Kills rare ore bosses the moment they spawn", "ฆ่าบอสแร่หายากทันทีที่เกิด"), function(value)
            if value then xDTaraZ.SuperLoot.KillExisting() end
        end)
        combatBox:AddButton({ Text = T("Exit Fight Now", "ออกจากการต่อสู้เดี๋ยวนี้"), Style = "Warning", Func = Action(xDTaraZ.Stage.ExitFight) })

        local bossBox = tab:AddRightGroupbox(T("World Boss", "บอสโลก"))
        Feature(bossBox, "AutoWorldBoss", T("Auto World Boss", "บอสโลกอัตโนมัติ"), T("Joins every world boss and kills it", "เข้าบอสโลกทุกรอบแล้วฆ่า"), function(value)
            if not value and LocalPlayer:GetAttribute("IntoFight") == "WorldBoss" then task.spawn(xDTaraZ.Util.Try, xDTaraZ.Boss.Leave) end
        end)
        Check(bossBox, "BossCards", T("Take every reward card", "เปิดการ์ดรางวัลทุกใบ"))
        Feature(bossBox, "BossHop", T("Boss Server Hop", "ย้ายเซิร์ฟหาบอส"), T("Hops to servers where the boss is up or about to spawn, kills it, then moves on", "ย้ายไปเซิร์ฟที่บอสเกิดอยู่หรือใกล้เกิด ฆ่าแล้วย้ายต่อ"), function(value)
            xDTaraZ.Boss.HopFlag(value)
            if value and Options.AutoWorldBoss and not Options.AutoWorldBoss.Value then Options.AutoWorldBoss:SetValue(true) end
        end, true)

        local indexBox = tab:AddRightGroupbox(T("Index", "สมุดสะสม"))
        MultiSelect(indexBox, "IndexTypes", T("Index Types", "ประเภทที่จะเก็บ"), nil, Config.GearTypes)
        Pick(indexBox, "MissingItem", T("Missing Item", "ของที่ยังไม่มี"), T("Chance shown is per forge with the best ore", "เปอร์เซ็นต์ = โอกาสต่อการหลอมหนึ่งครั้งด้วยแร่ที่ดีที่สุด"), function()
            return { "..." }
        end, true)
        task.defer(function()
            local ok, labels = pcall(xDTaraZ.Index.Choices)
            if ok then
                Later(SetList, "MissingItem", labels, true)
            else
                warn("[LootToForge] index list:", labels)
            end
        end)
        indexBox:AddButton({ Text = T("Get Selected", "หาชิ้นนี้"), Style = "Primary", Func = LongAction("Index", function()
            local gear = State.MissingLabels[opt.MissingItem]
            return gear and xDTaraZ.Index.Hunt(gear)
        end, function(got)
            Later(SetList, "MissingItem", (Source(xDTaraZ.Index.Choices)))
            return got and "Got it!" or "Not found this time, press again"
        end) }):AddButton(RefreshButton("MissingItem", xDTaraZ.Index.Choices))
        Feature(indexBox, "AutoIndex", T("Auto Complete Index", "เก็บสมุดสะสมอัตโนมัติ"), T("Forges every missing weapon, armor and hat, then claims rewards", "หลอมอาวุธ เกราะ หมวกที่ยังไม่มีทุกชิ้น แล้วรับรางวัล"), nil, true)
        indexBox:AddButton({ Text = T("Collect All Ores", "เก็บแร่ทุกชนิด"), Func = LongAction("Ores", xDTaraZ.Index.CollectOres, function()
            local count, level = xDTaraZ.Index.Progress()
            return ("Index %d, level %d"):format(count, level)
        end) }):AddButton({ Text = T("Claim Rewards", "รับรางวัล"), Style = "Success", Func = Action(xDTaraZ.Index.ClaimAll) })
    end

    local function BuildForge(tab)
        local forgeBox = tab:AddLeftGroupbox(T("Forge", "หลอม"))
        local targetNames = {}
        for _, target in ipairs(Config.ForgeTargets) do
            targetNames[#targetNames + 1] = target.name
        end
        forgeBox:AddDropdown("ForgeTarget", {
            Text = T("Target Gear", "อุปกรณ์ที่จะหลอม"),
            Values = targetNames,
            Default = 1,
            Callback = function(value)
                opt.ForgeTarget = value or opt.ForgeTarget
            end,
        })
        Pick(forgeBox, "ForgeOre", T("Ore To Use", "แร่ที่ใช้หลอม"), T("Pick an ore and it never runs out", "เลือกแร่แล้วไม่มีวันหมด"), xDTaraZ.Ore.ForgeChoices, nil, true)
        Feature(forgeBox, "AutoForge", T("Auto Forge", "หลอมอัตโนมัติ"), T("Forges the target gear nonstop", "หลอมอุปกรณ์ที่เลือกไม่หยุด"))
        forgeBox:AddButton({ Text = T("Forge Now", "หลอมเดี๋ยวนี้"), Style = "Primary", Func = Action(xDTaraZ.Forge.Step) })
        forgeBox:AddSlider("ForgePerTick", {
            Text = T("Forges Per Round", "หลอมต่อรอบ"),
            Min = 1, Max = 50, Default = opt.ForgePerTick, Rounding = 0,
            Callback = function(value)
                opt.ForgePerTick = value
            end,
        })
        Check(forgeBox, "ForgeSellJunk", T("Sell worse gear right away", "ขายของที่แย่กว่าที่ใส่ทันที"))

        local oreUseBox = tab:AddRightGroupbox(T("Ore Usage", "การใช้แร่"))
        oreUseBox:AddLabel(T("Used when Ore To Use is Owned ores", "ใช้ตอนแร่ที่ใช้หลอม = Owned ores"))
        Toggle(oreUseBox, "BestOreFirst", T("Spend Best Ore First", "ใช้แร่ดีสุดก่อน"), T("Off = spend the weakest ore first", "ปิด = ใช้แร่ที่อ่อนที่สุดก่อน"))
        MultiSelect(oreUseBox, "ForgeRarities", T("Forge Ore Rarity", "rarity แร่ที่ใช้หลอม"), T("Only these ore rarities are used for forging", "ใช้แร่เฉพาะ rarity ที่เลือกในการหลอม"), rarityNames)
        NumberInput(oreUseBox, "KeepPerOre", T("Keep Per Ore", "เก็บแร่ไว้ชนิดละ"), T("Never forge below this amount of each ore", "ไม่หลอมจนแร่แต่ละชนิดต่ำกว่าจำนวนนี้"))
    end

    local function BuildSell(tab)
        local sellBox = tab:AddLeftGroupbox(T("Auto Sell", "ขายอัตโนมัติ"))
        Feature(sellBox, "AutoSell", T("Auto Sell", "ขายอัตโนมัติ"), T("Sells gear that matches your filters. Equipped gear is never sold", "ขายอุปกรณ์ที่ตรงตัวกรอง ของที่ใส่อยู่จะไม่ขาย"))
        sellBox:AddButton({ Text = T("Sell All Now", "ขายทั้งหมดเดี๋ยวนี้"), Style = "Primary", Func = Action(function()
            xDTaraZ.Sell.Run(xDTaraZ.Data.Get())
            Notify("Sold", "Coin")
        end) })

        local filterBox = tab:AddRightGroupbox(T("Filters", "ตัวกรอง"))
        MultiSelect(filterBox, "SellTypes", T("Sell Item Types", "ประเภทที่จะขาย"), nil, Config.GearTypes)
        MultiSelect(filterBox, "SellRarities", T("Sell Rarity Filter", "กรอง rarity ที่จะขาย"), T("Only sell these rarities", "ขายเฉพาะ rarity ที่เลือก"), rarityNames)
        NumberInput(filterBox, "KeepPerItem", T("Keep Per Item", "เก็บไว้ชิ้นละ"), T("Keeps this many of each item, highest enhance first", "เก็บแต่ละไอเทมไว้ตามจำนวนนี้ เลือกตัวตีบวกสูงสุดก่อน"))
    end

    local function BuildProgress(tab)
        local trainBox = tab:AddLeftGroupbox(T("Training", "ฝึก"))
        Feature(trainBox, "AutoTrain", T("Auto Train", "ฝึกอัตโนมัติ"), T("Trains at the best area nonstop and drinks your potions", "ฝึกโซนดีสุดไม่หยุด ใช้ยาให้เอง"), function(value)
            task.spawn(xDTaraZ.Util.Try, xDTaraZ.Level.SetTraining, value)
        end)
        local autoClick = Feature(trainBox, "AutoClick", T("Auto Click", "คลิกอัตโนมัติ"), T("Clicks to train as fast as the game allows", "คลิกฝึกเร็วสุดเท่าที่เกมยอม"), function(value)
            if value then xDTaraZ.Level.StartClicking() end
        end)
        NeedModule(autoClick, ReplicatedStorage.CTRL.TrainCTRL)
        Feature(trainBox, "AutoRebirth", T("Auto Rebirth", "รีเบิร์ธอัตโนมัติ"), T("Rebirths as soon as your level is high enough", "รีเบิร์ธทันทีเมื่อเลเวลถึง"))
        trainBox:AddButton({ Text = T("Rebirth Now", "รีเบิร์ธเดี๋ยวนี้"), Func = Action(xDTaraZ.Level.Rebirth) })

        local upgradeBox = tab:AddRightGroupbox(T("Upgrades", "อัปเกรด"))
        MultiSelect(upgradeBox, "Upgrades", T("Upgrades To Buy", "อัปเกรดที่จะซื้อ"), nil, (Source(xDTaraZ.Upgrade.Names)))
        Feature(upgradeBox, "AutoUpgrade", T("Auto Buy Upgrades", "ซื้ออัปเกรดอัตโนมัติ"), T("Buys the selected upgrades whenever possible", "ซื้ออัปเกรดที่เลือกทุกครั้งที่ซื้อได้"))
        upgradeBox:AddButton({ Text = T("Buy Upgrade Now", "ซื้ออัปเกรดเดี๋ยวนี้"), Func = Action(xDTaraZ.Upgrade.BuySelected) })
    end

    local function BuildTower(tab)
        local towerBox = tab:AddLeftGroupbox(T("Tower", "หอคอย"))
        Feature(towerBox, "AutoTower", T("Auto Farm Tower", "ฟาร์มหอคอยอัตโนมัติ"), T("Top floor loot nonstop on one ticket: rare stones and season coins", "ของชั้นบนสุดไม่หยุดด้วยตั๋วใบเดียว ได้หินหายากและเหรียญซีซั่น"), function(value)
            task.defer(function()
                if not value then return xDTaraZ.Util.Try(xDTaraZ.Tower.Exit) end
                if not xDTaraZ.Tower.Enter() then Notify("No tower ticket", "Warning") end
            end)
        end)
        towerBox:AddButton({ Text = T("Exit Tower Now", "ออกจากหอคอยเดี๋ยวนี้"), Style = "Warning", Func = function()
            Options.AutoTower:SetValue(false)
            task.spawn(xDTaraZ.Util.Try, xDTaraZ.Tower.Exit)
        end })

        local seasonBox = tab:AddRightGroupbox(T("Season", "ซีซั่น"))
        local goodLabels, goodIds = Source(xDTaraZ.Season.Goods)
        local goodDefault = {}
        for label, goodId in pairs(goodIds) do
            if opt.SeasonGoods[goodId] then table.insert(goodDefault, label) end
        end
        Feature(seasonBox, "AutoSeason", T("Auto Season", "ซีซั่นอัตโนมัติ"), T("Daily ticket, pass rewards, spins and shop", "ตั๋วรายวัน รางวัลพาส สุ่ม และร้าน"))
        seasonBox:AddButton({ Text = T("Season Now", "ซีซั่นเดี๋ยวนี้"), Func = Action(xDTaraZ.Season.Step) })
        Check(seasonBox, "SeasonSpin", T("Spin every ticket", "สุ่มตั๋วทุกใบ"))
        seasonBox:AddDropdown("SeasonGoods", {
            Text = T("Shop Items To Buy", "ของในร้านที่จะซื้อ"),
            Values = goodLabels,
            Multi = true,
            Default = goodDefault,
            Searchable = #goodLabels > 8,
            Callback = function(selected)
                local wanted = {}
                for label, on in pairs(selected) do
                    if on and goodIds[label] then wanted[goodIds[label]] = true end
                end
                opt.SeasonGoods = wanted
            end,
        })
    end

    local function BuildSpawn(tab)
        local spawnBox = tab:AddLeftGroupbox(T("Spawn Items", "เสกของ"), nil, "OP")
        Pick(spawnBox, "SpawnItem", T("Item", "ของ"), T("Ores and runes. Runes need at least one owned", "แร่และรูน รูนต้องมีอย่างน้อย 1 ชิ้น"), xDTaraZ.Spawn.Choices, true, true)
        NumberInput(spawnBox, "SpawnAmount", T("Amount", "จำนวน"), nil, 1)
        spawnBox:AddButton({ Text = T("Spawn", "เสก"), Style = "Primary", Func = function()
            local picked = State.SpawnLabels[opt.SpawnItem]
            if not picked then return Notify("Pick an item first", "Warning") end
            local label, amount = opt.SpawnItem, opt.SpawnAmount
            task.defer(function()
                local ok = xDTaraZ.Spawn.Give(picked.id, picked.kind, amount)
                Notify(ok and ("Added %s %s"):format(xDTaraZ.Util.Abbreviate(amount), label) or "You need at least one of this item first", ok and "Success" or "Warning")
            end)
        end }):AddButton(RefreshButton("SpawnItem", xDTaraZ.Spawn.Choices))
        spawnBox:AddButton({ Text = T("Dupe Whole Inventory", "ปั๊มของทั้งกระเป๋า"), Risky = true, Func = function()
            local amount = opt.SpawnAmount
            task.defer(function()
                local touched = xDTaraZ.Spawn.DupeAll(amount)
                Notify(("Added %s to %d stacks"):format(xDTaraZ.Util.Abbreviate(amount), touched), touched > 0 and "Success" or "Warning")
            end)
        end })

        local gearBox = tab:AddLeftGroupbox(T("Spawn Gear", "เสกอาวุธและชุด"), nil, "OP")
        local function LoadGearList(slot)
            task.defer(function()
                local ok, labels = pcall(xDTaraZ.Spawn.GearChoices, slot)
                if ok then
                    Later(SetList, "SpawnGear", labels, true)
                else
                    warn("[LootToForge] gear list:", labels)
                end
            end)
        end
        opt.GearSlot = Config.GearTypes[1]
        gearBox:AddDropdown("GearSlot", {
            Text = T("Type", "ประเภท"),
            Values = Config.GearTypes,
            Default = 1,
            NoSave = true,
            Callback = function(value)
                opt.GearSlot = value
                LoadGearList(value)
            end,
        })
        opt.SpawnGear = nil
        gearBox:AddDropdown("SpawnGear", {
            Text = T("Gear", "อุปกรณ์"),
            Description = T("Strongest first. Exclusive gear is shop only", "แรงสุดอยู่บน ของ Exclusive มีแค่ในร้าน"),
            Values = { "..." },
            Default = 1,
            Searchable = true,
            NoSave = true,
            Callback = function(value)
                opt.SpawnGear = value
            end,
        })
        LoadGearList(opt.GearSlot)
        NumberInput(gearBox, "GearCopies", T("Copies", "จำนวนชิ้น"), nil, 1)
        gearBox:AddButton({ Text = T("Spawn Gear", "เสกอุปกรณ์"), Style = "Primary", Func = LongAction("Index", function()
            local gear = State.GearLabels[opt.SpawnGear]
            return gear and xDTaraZ.Index.Hunt(gear, math.max(1, math.floor(opt.GearCopies)))
        end, function(got)
            return got and "Spawned!" or "Not all copies this time, press again"
        end) })
        gearBox:AddButton({ Text = T("Buy Exclusive Gear", "ซื้อของ Exclusive"), Func = LongAction("Tower", xDTaraZ.Season.BuyExclusive, function(bought)
            return (bought or 0) > 0 and ("Bought %d exclusive pieces"):format(bought) or "Already bought this refresh"
        end) })

        local potionBox = tab:AddRightGroupbox(T("Potions", "ยา"), nil, "OP")
        potionBox:AddButton({ Text = T("Max Potion Buffs", "บัฟยาเต็มทั้งปี"), Style = "Primary", Func = LongAction("Potion", xDTaraZ.Potion.MaxBuffs, function(count)
            return (count or 0) > 0 and ("%d potion buffs active for about a year"):format(count) or "Own at least one potion first"
        end) })
        potionBox:AddButton({ Text = T("Add 100K Potions", "เพิ่มยา 100K ขวด"), Func = Action(function()
            for _, potionId in ipairs(xDTaraZ.Potion.Owned()) do
                xDTaraZ.Potion.Add(potionId, Config.PotionStack)
            end
        end) })

        local coinBox = tab:AddRightGroupbox(T("Season Coins", "เหรียญซีซั่น"), nil, "OP")
        NumberInput(coinBox, "CoinTarget", T("Amount", "จำนวน"), nil, 1)
        coinBox:AddButton({ Text = T("Add Season Coins", "เพิ่มเหรียญซีซั่น"), Style = "Primary", Func = LongAction("Tower", function()
            return xDTaraZ.Tower.FarmCoins(opt.CoinTarget)
        end, function(gained) return ("+%s season coins"):format(xDTaraZ.Util.Abbreviate(gained or 0)) end) })

        local stoneBox = tab:AddRightGroupbox(T("Enhance Stones", "หินตีบวก"))
        stoneBox:AddButton({ Text = T("Farm Enhance Stones", "ฟาร์มหินตีบวก"), Style = "Primary", Func = LongAction("Stones", function()
            local before = xDTaraZ.Data.Count(xDTaraZ.Data.Get(), "EnhantStone_1")
            xDTaraZ.Stage.FarmStones(xDTaraZ.Stage.Best())
            task.wait(0.5)
            return xDTaraZ.Data.Count(xDTaraZ.Data.Get(), "EnhantStone_1") - before
        end, function(gained) return ("+%d enhance stones"):format(gained or 0) end) })
        stoneBox:AddButton({ Text = T("Farm Rare Stones", "ฟาร์มหินตีบวกหายาก"), Func = LongAction("Tower", function()
            local before = xDTaraZ.Data.Count(xDTaraZ.Data.Get(), "EnhantStone_2")
            xDTaraZ.Tower.FarmStep()
            task.wait(0.5)
            return xDTaraZ.Data.Count(xDTaraZ.Data.Get(), "EnhantStone_2") - before
        end, function(gained) return ("+%d rare stones"):format(gained or 0) end) })
    end

    local function BuildPlayer(tab)
        local raceBox = tab:AddLeftGroupbox(T("Race", "เผ่า"))
        local raceLabels, raceIds = Source(xDTaraZ.Race.Choices)
        opt.TargetRace = raceIds[raceLabels[1]]
        raceBox:AddDropdown("TargetRace", {
            Text = T("Target Race", "เผ่าที่ต้องการ"),
            Values = raceLabels,
            Default = 1,
            Searchable = #raceLabels > 8,
            Callback = function(value)
                opt.TargetRace = raceIds[value]
            end,
        })
        Feature(raceBox, "AutoRace", T("Auto Roll Race", "สุ่มเผ่าอัตโนมัติ"), T("Uses your race rolls until you get the chosen race", "สุ่มเผ่าจนกว่าจะได้เผ่าที่เลือก"), function(value)
            if not value or State.Rolling then return end
            State.Rolling = true
            task.defer(function()
                local ok, outcome = pcall(xDTaraZ.Race.RollUntil, opt.TargetRace)
                State.Rolling = false
                if ok and outcome == "got" then
                    Notify("Got the race!", "Success")
                elseif ok and outcome == "empty" then
                    Notify("No race rolls left", "Warning")
                end
                Later(TurnOff, "AutoRace")
            end)
        end)
        Feature(raceBox, "AutoBestRace", T("Use Best Race Slot", "ใช้ช่องเผ่าที่ดีสุด"), T("Switches to your rarest race", "สลับไปใช้เผ่าที่หายากที่สุด"))
        raceBox:AddButton({ Text = T("Switch Now", "สลับเดี๋ยวนี้"), Func = Action(function()
            Notify(xDTaraZ.Race.EquipBest() and "Switched race slot" or "Already on your best race")
        end) })

        local moveBox = tab:AddRightGroupbox(T("Movement", "การเคลื่อนที่"))
        HotkeyFeature(moveBox, "SpeedOn", T("Speed", "ความเร็ว"), nil, xDTaraZ.Movement.Apply)
        moveBox:AddSlider("WalkSpeed", {
            Text = T("Walk Speed", "ความเร็วเดิน"),
            Min = 16, Max = 200, Default = opt.WalkSpeed, Rounding = 0,
            Callback = function(value)
                opt.WalkSpeed = value
                xDTaraZ.Movement.Apply()
            end,
        })
        HotkeyFeature(moveBox, "InfJump", T("Infinite Jump", "กระโดดไม่จำกัด"))

        local guardBox = tab:AddRightGroupbox(T("Survival", "เอาตัวรอด"))
        local godMode = Feature(guardBox, "GodMode", T("Invincible", "อมตะ"), T("Monsters and bosses can't kill you", "มอนสเตอร์และบอสฆ่าไม่ตาย"), function(value)
            if not value then
                if State.RestoreDamage then State.RestoreDamage() end
            elseif not xDTaraZ.Guard.HookDamage() then
                Notify("Invincible is not available on this executor", "Warning")
                task.defer(TurnOff, "GodMode")
            end
        end)
        NeedModule(godMode, ReplicatedStorage.CTRL.HPCTRL)
        local keepOre = Feature(guardBox, "KeepOre", T("Keep Ore On Death", "ตายแล้วแร่ไม่หาย"), nil, function(value)
            if not value then
                xDTaraZ.Guard.UnhookOreLoss()
            elseif not xDTaraZ.Guard.HookOreLoss() then
                Notify("Keep Ore On Death is not supported on this executor", "Warning")
                task.defer(TurnOff, "KeepOre")
            end
        end)
        xDTaraZ.Compat.NeedCap(keepOre, "Namecall")
    end

    local function BuildSettings(window)
        local settingsTab = window:AddSettingsTab()
        local sessionBox = settingsTab:AddRightGroupbox(T("Session", "เซสชัน"))
        Toggle(sessionBox, "AutoRejoin", T("Auto Rejoin", "เข้าเกมใหม่อัตโนมัติ"), T("Rejoins the game by itself after a disconnect", "หลุดแล้วเข้าเกมใหม่เอง"))
        Toggle(sessionBox, "LowGraphics", T("FPS Boost", "เพิ่ม FPS"), T("Turns off 3D rendering to save CPU and GPU", "ปิดการแสดงผล 3D ประหยัด CPU/GPU"), xDTaraZ.Session.SetLowGraphics)
        sessionBox:AddButton({ Text = T("Rejoin Now", "เข้าเกมใหม่เดี๋ยวนี้"), Func = Action(xDTaraZ.Session.Rejoin) })
    end

    local noteText = {
        EnhantStone_1 = "farming enhance stones",
        EnhantStone_2 = "farming rare enhance stones",
        Coin = "farming coins",
        Enhancing = "enhancing",
        NoTicket = "need a tower ticket",
        Done = "all at target",
    }

    local function TaskText()
        if State.Lock == "Index" then return "Index " .. (State.IndexNote or "planning") end
        if State.Lock then return State.Lock end
        if opt.MaxGear then return "Max Gear, " .. (noteText[State.GearNote] or "starting") end
        return "Idle"
    end

    local function UpdateStatus()
        local ok, profile = pcall(xDTaraZ.Data.Get)
        if not (ok and profile and statusLabel) then return end
        local eco = profile.Eco
        local line = ("Level %d · Rebirth %d · Coins %s"):format(eco.level, eco.rebirth, xDTaraZ.Util.Abbreviate(eco.coin))
        if State.TowerLoot > 0 then
            line ..= ("\nTower loot x%d"):format(State.TowerLoot)
        end
        Later(statusLabel.SetText, statusLabel, line)
        Later(gearLabel.SetText, gearLabel, "Equipped: " .. xDTaraZ.Gear.EquippedNames(profile))
        Later(taskLabel.SetText, taskLabel, "Working on: " .. TaskText())
    end

    local function BuildTabs()
        local Window = Library.Window
        Window:AddTabSection(T("Farm", "ฟาร์ม"))
        local MainTab = Window:AddTab(T("Main", "หลัก"), "house", T("Status, all-in-one mode and rewards", "สถานะ โหมดทำทุกอย่าง และรางวัล"))
        local FarmTab = Window:AddTab(T("Combat & Farm", "ต่อสู้และฟาร์ม"), "swords", T("Stages, monsters, bosses and index", "ด่าน มอนสเตอร์ บอส และสมุดสะสม"))
        local ForgeTab = Window:AddTab(T("Forge", "หลอม"), "zap", T("Forge gear from any ore", "หลอมอุปกรณ์จากแร่ไหนก็ได้"))
        local SellTab = Window:AddTab(T("Sell", "ขาย"), "upload", T("Sell gear by type and rarity", "ขายอุปกรณ์ตามประเภทและ rarity"))
        Window:AddTabSection(T("Progress", "ความคืบหน้า"))
        local ProgressTab = Window:AddTab(T("Upgrade & Rebirth", "อัปเกรดและรีเบิร์ธ"), "sliders-horizontal", T("Training, rebirth and upgrades", "ฝึก รีเบิร์ธ และอัปเกรด"))
        local TowerTab = Window:AddTab(T("Tower", "หอคอย"), "shield", T("Tower loot and season pass", "ของจากหอคอย และซีซั่นพาส"))
        local SpawnTab = Window:AddTab(T("Spawn Items", "เสกของ"), "target", T("Ores, runes and enhance stones", "แร่ รูน และหินตีบวก"))
        Window:AddTabSection(T("Other", "อื่นๆ"))
        local PlayerTab = Window:AddTab(T("Player", "ผู้เล่น"), "user", T("Race, movement and survival", "เผ่า การเคลื่อนที่ และเอาตัวรอด"))

        local sections = {
            { BuildMain, MainTab },
            { BuildFarm, FarmTab },
            { BuildForge, ForgeTab },
            { BuildSell, SellTab },
            { BuildProgress, ProgressTab },
            { BuildTower, TowerTab },
            { BuildSpawn, SpawnTab },
            { BuildPlayer, PlayerTab },
            { BuildSettings, Window },
        }
        for _, section in ipairs(sections) do
            xDTaraZ.Util.Try(section[1], section[2])
        end
        xDTaraZ.Util.Try(BlockMissing)

        Library:Every(Config.PumpInterval, Pump)
        task.spawn(function()
            while State.Alive do
                UpdateStatus()
                task.wait(Config.StatusInterval)
            end
        end)
    end

    local function Unload()
        Library:Unload()
    end
    Library:OnUnload(xDTaraZ.Scheduler.Stop)
    Library:OnUnload(function()
        if getgenv().LootToForgeUnload == Unload then getgenv().LootToForgeUnload = nil end
    end)
    getgenv().LootToForgeUnload = Unload

    Library:CreateWindow({
        Title = "Nova Hub",
        SubTitle = "Loot To Forge by xDTaraZ",
        MenuKey = Enum.KeyCode.LeftControl,
        ConfigFolder = Config.SaveFolder,
        Language = "Auto",
        Theme = "Nova",
        OnUnlocked = function()
            BuildTabs()
            xDTaraZ.Util.Try(xDTaraZ.Scheduler.Boot)
            Notify("Loaded", "Success")
            xDTaraZ.Util.Try(Library.LoadAutoloadConfig, Library)
            if xDTaraZ.Boss.HopWanted() and Options.BossHop then Options.BossHop:SetValue(true) end
        end,
    })
end

if getgenv().LootToForgeUnload then
    pcall(getgenv().LootToForgeUnload)
end

pcall(NovaBanner.Step, "Systems")
BuildInterface()
pcall(NovaBanner.Step, "Interface")]==]

NOVA_HUB_MODULES[10765091041] = [==[if not game:IsLoaded() then
    game.Loaded:Wait()
end

if game.GameId ~= 10765091041 then
    game:GetService("Players").LocalPlayer:Kick("Nova Hub : this script is for Open Sea For Animals only")
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
        "   OPEN SEA FOR ANIMALS  |  by xDTaraZ  |  discord.gg/FHVfmeSceA",
        "   executor: " .. executor .. "   |   player: " .. game:GetService("Players").LocalPlayer.Name,
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
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local xDTaraZ = setmetatable({}, {
    __newindex = function(self, key, value)
        rawset(self, key, type(value) == "function" and LPH_JIT(value) or value)
    end,
})

xDTaraZ.Config = {
    Discord = "https://discord.gg/FHVfmeSceA",
    UpdateLog = {
        { "2026-10-05", "Auto Pickaxe, Auto Potion, Spin Wheel and Season Pass\nEvent pickups, Fullbright, Teleport and Server Hop\nAuto Sell Brainrots fixed, bigger status panel" },
        { "2026-10-03", "Classic Nova Hub UI is back\nBetter executor support\nAuto Loot stops when full\nAuto-detect Upgrades" },
    },
    UiSource = "NovaHub://embedded-ui",
    ServerList = "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&limit=100",
    SaveFolder = "Open Sea For Animals",
    LoadTimeout = 10,
    AlertTries = 20,
    AlertRetry = 0.5,
    JobFailLimit = 5,
    JobFailWindow = 10,
    TickDelay = 0.25,
    LootWorkers = 3,
    WaveExtension = 5,
    LootIdle = 1,
    ResumeInterval = 0.5,
    ResumeBackoff = 30,
    InventoryLimit = 200,
    PlotRecheck = 30,
    ClaimInterval = 30,
    UpgradeInterval = 3,
    SellInterval = 2,
    PotionInterval = 5,
    PickupInterval = 1,
    PickupHop = 0.15,
    PickupsPerTick = 12,
    FullbrightInterval = 1,
    SpinCost = 25,
    Codes = { "Release", "SORRYFORRESTARTGUYSTPBUG3", "MASTERY", "GHOULUPDATE" },
    PlaytimeSlots = 12,
    DailyDays = 7,
    PlaceEggTries = 3,
    FallbackUpgrades = { "Carry", "MovementSpeed", "PlotUpgrade" },
  