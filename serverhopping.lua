-- ✅ Pastikan game sudah selesai load
if not game:IsLoaded() then
    game.Loaded:Wait()
end

-- ⏳ Delay 20 detik setelah di-execute
task.wait(20)

local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

local placeId = game.PlaceId
local currentJobId = game.JobId

local cursor = nil
local foundServer = nil

-- 🔁 Ambil list server pakai game:HttpGet (BUKAN HttpService:GetAsync)
local function GetServers()
    local url = "https://games.roblox.com/v1/games/121864768012064/servers/Public?sortOrder=Asc&limit=100"
    if cursor then
        url = url .. "&cursor=" .. cursor
    end

    -- ⛔ HttpService:GetAsync diblok, jadi kita pakai game:HttpGet
    local ok, result = pcall(function()
        return game:HttpGet(url)
    end)

    if not ok then
        warn("Gagal ambil server list via game:HttpGet:", result)
        return nil
    end

    local data
    local okDecode, decodeErr = pcall(function()
        data = HttpService:JSONDecode(result)
    end)

    if not okDecode then
        warn("Gagal decode JSON:", decodeErr)
        return nil
    end

    cursor = data.nextPageCursor
    return data.data
end

print("[ServerHop] Mencari server lain...")

-- 🔎 Cari server yang:
--     - tidak penuh
--     - jobId beda dengan server sekarang
for _ = 1, 5 do -- maksimal 5 page
    local servers = GetServers()
    if not servers then break end

    for _, server in ipairs(servers) do
        local canJoin = server.playing < server.maxPlayers
        local differentServer = server.id ~= currentJobId

        if canJoin and differentServer then
            foundServer = server.id
            break
        end
    end

    if foundServer then
        break
    end

    if not cursor then
        break -- tidak ada page lanjutan
    end
end

-- 🚀 Teleport kalau ketemu server
if foundServer then
    print("[ServerHop] Server ketemu! Teleport ke:", foundServer)
    local okTp, tpErr = pcall(function()
        TeleportService:TeleportToPlaceInstance(placeId, foundServer)
    end)

    if not okTp then
        warn("[ServerHop] Teleport gagal:", tpErr)
    end
else
    warn("[ServerHop] Tidak menemukan server lain yang bisa dimasuki. Coba rejoin biasa.")
    -- Fallback: rejoin game (kadang dapat server baru)
    -- pcall(function()
    --     TeleportService:Teleport(placeId)
    -- end)
end
