if not game:IsLoaded() then
    game.Loaded:Wait()
end

task.wait(20)

local Players         = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService     = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local placeId     = game.PlaceId         -- ⬅ pakai place yang sedang dimainkan
local currentJobId = game.JobId

--------------------------------------------------------------------
-- 🔧 KONFIGURASI
--------------------------------------------------------------------
local MIN_PLAYERS = 7          -- minimal pemain di server tujuan
local MAX_PLAYERS = 15         -- maksimal pemain di server tujuan
local MAX_PAGES   = 5          -- maksimal halaman server yang dicek
local MAX_TRIES   = 3          -- maksimal percobaan teleport ke server berbeda
--------------------------------------------------------------------

--------------------------------------------------------------------
-- 📜 LOAD DAFTAR TEMAN
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
    warn("[ServerHop] Ada teman di server ini:", friendName, "→ akan cari server lain.")
else
    print("[ServerHop] Tidak ada teman di server ini.")
end

--------------------------------------------------------------------
-- 🌐 AMBIL LIST SERVER DARI API ROBLOX
--------------------------------------------------------------------
local cursor = nil

local function GetServers()
    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100")
        :format(placeId)      -- ⬅ TIDAK lagi hardcode

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

print(("[ServerHop] Cari server lain... (min %d, max %d pemain)")
    :format(MIN_PLAYERS, MAX_PLAYERS))
print("[ServerHop] Server sekarang JobId:", currentJobId)

--------------------------------------------------------------------
-- 🔎 KUMPULKAN KANDIDAT SERVER YANG COCOK
--------------------------------------------------------------------
local candidateServers = {}

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
            table.insert(candidateServers, {
                id      = server.id,
                playing = server.playing,
                max     = server.maxPlayers,
            })
        end
    end

    if not cursor then
        break
    end
end

if #candidateServers == 0 then
    warn("[ServerHop] Tidak ada server yang memenuhi syarat (7–15 pemain & beda JobId).")
    return
end

--------------------------------------------------------------------
-- 🚀 COBA TELEPORT KE BEBERAPA KANDIDAT, HANDLE ERROR 773
--------------------------------------------------------------------
local tries = 0

for _, server in ipairs(candidateServers) do
    if tries >= MAX_TRIES then
        warn("[ServerHop] Sudah mencapai batas percobaan teleport.")
        break
    end

    tries = tries + 1

    print(("[ServerHop] Percobaan %d: teleport ke %s (%d/%d pemain)")
        :format(tries, server.id, server.playing, server.max))

    local okTp, tpErr = pcall(function()
        TeleportService:TeleportToPlaceInstance(placeId, server.id)
    end)

    if not okTp then
        local errStr = tostring(tpErr)
        warn("[ServerHop] Teleport gagal:", errStr)

        if errStr:find("773") or errStr:lower():find("restricted") then
            warn("[ServerHop] Error 773 (tempat / server dibatasi oleh Roblox). " ..
                 "Script tidak bisa memaksa masuk. Coba server lain.")
            -- lanjut ke server kandidat berikutnya
        else
            -- error lain (misal disconnect), kita juga lanjut ke kandidat lain
            warn("[ServerHop] Bukan 773, lanjut coba server lain.")
        end
    else
        print("[ServerHop] Teleport berhasil dipanggil, menunggu pindah server...")
        break -- biasanya setelah ini script berhenti karena pindah place
    end
end
