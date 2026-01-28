-- Pastikan game sudah selesai load
if not game:IsLoaded() then
    game.Loaded:Wait()
end

-- Jeda 20 detik setelah auto-execute
task.wait(20)

local Players          = game:GetService("Players")
local TeleportService  = game:GetService("TeleportService")
local HttpService      = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local placeId     = game.PlaceId
local currentJobId = game.JobId

--------------------------------------------------------------------
-- 🔧 KONFIGURASI
--------------------------------------------------------------------
local MIN_PLAYERS = 7          -- minimal pemain di server tujuan
local MAX_PLAYERS = 15         -- maksimal pemain di server tujuan
local MAX_PAGES   = 5          -- maksimal halaman server yang dicek
--------------------------------------------------------------------

--------------------------------------------------------------------
-- 🔹 Load daftar teman (UserId)
--------------------------------------------------------------------
local FriendIds = {}

do
    local ok, pagesOrErr = pcall(function()
        return Players:GetFriendsAsync(LocalPlayer.UserId)
    end)

    if not ok then
        warn("[ServerHop] Gagal load daftar teman:", pagesOrErr)
    else
        local pages = pagesOrErr
        repeat
            for _, info in ipairs(pages:GetCurrentPage()) do
                FriendIds[info.Id] = true
            end
        until pages.IsFinished or not pcall(function()
            pages:AdvanceToNextPageAsync()
        end)
    end
end

local function HasFriendInCurrentServer()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and FriendIds[plr.UserId] then
            return true, plr.Name
        end
    end
    return false
end

local hasFriend, friendName = HasFriendInCurrentServer()
if hasFriend then
    warn("[ServerHop] Ada teman di server ini:", friendName, "→ akan hop ke server lain.")
else
    print("[ServerHop] Tidak ada teman di server ini.")
end

--------------------------------------------------------------------
-- 🔹 Ambil list server dari API Roblox
--------------------------------------------------------------------
local cursor = nil

local function GetServers()
    -- Pakai placeId dari game yang sedang kamu mainkan
    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(placeId)

    if cursor then
        url = url .. "&cursor=" .. cursor
    end

    local ok, result = pcall(function()
        return game:HttpGet(url)
    end)

    if not ok then
        warn("[ServerHop] Gagal ambil server list:", result)
        return nil
    end

    local decoded
    local okDecode, errDecode = pcall(function()
        decoded = HttpService:JSONDecode(result)
    end)

    if not okDecode then
        warn("[ServerHop] Gagal decode JSON:", errDecode)
        return nil
    end

    cursor = decoded.nextPageCursor
    return decoded.data
end

print(("[ServerHop] Mencari server lain... (min %d, max %d pemain)"):format(MIN_PLAYERS, MAX_PLAYERS))
print("[ServerHop] Server saat ini JobId:", currentJobId)

--------------------------------------------------------------------
-- 🔹 Cari server yang:
--     - tidak penuh
--     - beda JobId (bukan server yang sama)
--     - jumlah pemain antara 7–15
--------------------------------------------------------------------
local foundServer
local foundPlayerCount

for page = 1, MAX_PAGES do
    local servers = GetServers()
    if not servers then break end

    for _, server in ipairs(servers) do
        print(("[ServerHop] Cek server %s | %d/%d pemain"):format(
            server.id,
            server.playing,
            server.maxPlayers
        ))

        local notFull         = server.playing < server.maxPlayers
        local differentServer = server.id ~= currentJobId
        local enoughPlayers   = server.playing >= MIN_PLAYERS
        local notTooMany      = server.playing <= MAX_PLAYERS

        if notFull and differentServer and enoughPlayers and notTooMany then
            foundServer      = server.id
            foundPlayerCount = server.playing
            print("[ServerHop] Server cocok ditemukan:", foundServer,
                  "| pemain:", server.playing, "/", server.maxPlayers)
            break
        end
    end

    if foundServer or not cursor then
        break
    end
end

--------------------------------------------------------------------
-- 🔹 Teleport & handle error (termasuk kode 773)
--------------------------------------------------------------------
if foundServer then
    print("[ServerHop] Teleport ke server:", foundServer)
    local okTp, tpErr = pcall(function()
        TeleportService:TeleportToPlaceInstance(placeId, foundServer)
    end)

    if not okTp then
        warn("[ServerHop] Teleport gagal:", tpErr)

        -- Deteksi error 773 (tempat dibatasi)
        local errStr = tostring(tpErr)
        if errStr:find("773") or errStr:lower():find("restricted") then
            warn("[ServerHop] Error 773 (tempat dibatasi). Ini batasan dari Roblox, tidak bisa di-bypass dari script.")
        end
    end
else
    warn("[ServerHop] Tidak menemukan server lain yang cocok. Coba rejoin biasa.")
end
