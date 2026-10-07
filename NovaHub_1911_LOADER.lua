--// NOVA HUB 1911 - Universal GitHub Loader

local BASE = "https://raw.githubusercontent.com/phnj9dgrdc-cell/shiny-parakeet/main/"

local PARTS = {
    "NovaHub_1911_part1.lua",
    "NovaHub_1911_part2.lua",
    "NovaHub_1911_part3.lua",
    "NovaHub_1911_part4.lua",
    "NovaHub_1911_part5.lua",
    "NovaHub_1911_part6.lua",
    "NovaHub_1911_part7.lua",
    "NovaHub_1911_part8.lua",
}

local function fetch(url)
    local ok, body = pcall(function()
        return game:HttpGet(url)
    end)

    if ok and type(body) == "string" and #body > 0 then
        return body
    end

    error("Failed to download:\n" .. url .. "\n" .. tostring(body))
end

local source = {}

for i, file in ipairs(PARTS) do
    print("[Nova Hub] Loading part " .. i .. "/8: " .. file)

    local body = fetch(BASE .. file)

    if body:find("<!DOCTYPE html", 1, true)
        or body:find("<html", 1, true)
        or body:find("404: Not Found", 1, true) then

        error("[Nova Hub] GitHub returned invalid data for " .. file)
    end

    source[#source + 1] = body
end

print("[Nova Hub] All 8 parts downloaded.")
print("[Nova Hub] Compiling...")

local completeSource = table.concat(source, "\n")

local chunk, compileError = loadstring(completeSource)

if not chunk then
    error("[Nova Hub] Compilation failed:\n" .. tostring(compileError))
end

print("[Nova Hub] Starting UI...")

local success, result = pcall(chunk)

if not success then
    error("[Nova Hub] Runtime error:\n" .. tostring(result))
end

print("[Nova Hub] Loaded successfully!")
