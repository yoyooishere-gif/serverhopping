--==[ ADVANCED SERVER HOPPER – FIX BACKUP & AVOID SAME SERVER ]==--

if not game:IsLoaded() then
    game.Loaded:Wait()
end

-- Konfigurasi umum
local CONFIG = {
    DelayBeforeStart   = 8,   -- jeda sebelum mulai hop (detik)

    -- RANGE UTAMA (server yang diinginkan)
    MinPlayers         = 3,   -- minimal pemain di server tujuan
    MaxPlayers         = 7,   -- maksimal pemain di server tujuan

    -- RANGE CADANGAN (kalau tidak ada yang masuk range utama)
    BackupMinPlayers   = 2,   -- minimal pemain untuk server cadangan (TIDAK AKAN pilih 1 pemain)

    MaxPagesToScan     = 6,   -- maksimal halaman server yang discan
    RandomStartPage    = true,-- mulai dari page acak
    UseAntiFriend      = true,-- cek teman di server sekarang
    RememberVisited    = true,-- ingat server yang sudah dikunjungi
    ResetVisitedAfter  = 150, -- kalau visited > ini, reset list
}

task.wait(CONFIG.DelayBeforeStart)

local Players         = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService     = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local placeId     = game.PlaceId
local currentJob  = game.JobId

math.randomseed(os.time())

----------------------------------------------------------------
-- 🔁 GLOBAL visited server list (supaya ingat lewat teleport)
----------------------------------------------------------------
local env = getgenv and getgenv() or _G
env.AdvServerHopVisited = env.AdvServerHopVisited or {}
local visited = env.AdvServerHopVisited

local function countVisited()
    local n = 0
    for _ in pairs(visited) do n += 1 end
    return n
end

if CONFIG.RememberVisited and countVisited() > CONFIG.ResetVisitedAfter then
    visited = {}
    env.AdvServerHopVisited = visited
    warn("[ServerHop] Reset daftar visited server (kebanyakan).")
end

----------------------------------------------------------------
-- 👥 Load daftar teman (kalau anti friend on)
----------------------------------------------------------------
local FriendIds = {}

local function loadFriends()
    local ok, pagesOrErr = pcall(function()
        return Players:GetFriendsAsync(LocalPlayer.UserId)
    end)

    if not ok then
        warn("[ServerHop] Gagal load daftar teman:", pagesOrErr)
        return
    end

    local pages = pagesOrErr
    repeat
        for _, info in ipairs(pages:GetCurrentPage()) do
            FriendIds[info.Id] = true
        end
    until pages.IsFinished or not pcall(function()
        pages:AdvanceToNextPageAsync()
    end)
end

if CONFIG.UseAntiFriend then
    loadFriends()
end

local function HasFriendInCurrentServer()
    if not CONFIG.UseAntiFriend then return false end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and FriendIds[plr.UserId] then
            return true, plr.Name
        end
    end
    return false
end

local hasFriend, friendName = HasFriendInCurrentServer()
if hasFriend then
    warn("[ServerHop] Ada teman di server ini:", friendName, "→ cari server lain.")
else
    print("[ServerHop] Tidak ada teman di server ini.")
end

----------------------------------------------------------------
-- 🌐 Cek apakah HTTP ke games.roblox.com tersedia
----------------------------------------------------------------
local HTTP_OK = true

do
    local testUrl = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=10")
        :format(placeId)

    local ok, res = pcall(function()
        return game:HttpGet(testUrl)
    end)

    if not ok then
        HTTP_OK = false
        warn("[ServerHop] HTTP ke games.roblox.com diblokir oleh executor / device.")
        warn("[ServerHop] Pindah ke mode sederhana: rejoin biasa.")
    else
        local okDecode = pcall(function()
            HttpService:JSONDecode(res)
        end)
        if not okDecode then
            HTTP_OK = false
            warn("[ServerHop] Response server list tidak valid, mode advanced dimatikan.")
        end
    end
end

----------------------------------------------------------------
-- 🪂 Mode simple (kalau HTTP tidak bisa)
----------------------------------------------------------------
local function SimpleRejoin()
    warn("[ServerHop] Mode simple aktif (tanpa server list). Rejoin place saja.")
    local okTp, err = pcall(function()
        TeleportService:Teleport(placeId, LocalPlayer)
    end)
    if not okTp then
        warn("[ServerHop] Teleport simple gagal:", err)
    end
end

if not HTTP_OK then
    SimpleRejoin()
    return
end

----------------------------------------------------------------
-- 📄 Ambil server list (Advanced mode)
----------------------------------------------------------------
local cursor = nil

local function GetServers()
    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100")
        :format(placeId)

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
        warn("[ServerHop] Gagal decode JSON server list:", errDecode)
        return nil
    end

    cursor = decoded.nextPageCursor
    return decoded.data
end

----------------------------------------------------------------
-- 🎲 Skip ke page acak dulu (RandomStartPage)
----------------------------------------------------------------
if CONFIG.RandomStartPage then
    local maxSkip = math.max(0, CONFIG.MaxPagesToScan - 1)
    local skipPages = math.random(0, maxSkip)

    for _ = 1, skipPages do
        local servers = GetServers()
        if not servers or not cursor then break end
    end

    print("[ServerHop] Mulai scan dari page acak, skip halaman:", skipPages)
end

print(("[ServerHop] Target server utama: %d–%d pemain"):format(CONFIG.MinPlayers, CONFIG.MaxPlayers))

----------------------------------------------------------------
-- 🔎 Kumpulkan kandidat server
----------------------------------------------------------------
local candidates = {}
local backups    = {}

-- helper pilih server dengan score terbaik
local function pickBest(list)
    if #list == 0 then return nil end
    local best = list[1]
    for i = 2, #list do
        if list[i].score > best.score then
            best = list[i]
        end
    end
    return best
end

for page = 1, CONFIG.MaxPagesToScan do
    local servers = GetServers()
    if not servers then break end

    for _, server in ipairs(servers) do
        local sid       = server.id
        local playing   = server.playing
        local maxPlr    = server.maxPlayers

        -- ❗️JANGAN pilih server sendiri
        if sid ~= currentJob then
            local notFull    = playing < maxPlr
            local inMain     = playing >= CONFIG.MinPlayers and playing <= CONFIG.MaxPlayers
            local inBackup   = playing >= CONFIG.BackupMinPlayers  -- minimal 2 pemain
            local notVisited = (not CONFIG.RememberVisited) or (not visited[sid])

            if notFull and notVisited then
                local info = {
                    id      = sid,
                    playing = playing,
                    max     = maxPlr,
                    score   = 0,
                }

                -- Skor: makin dekat ke tengah range utama, makin bagus
                local mid = (CONFIG.MinPlayers + CONFIG.MaxPlayers) / 2
                local dist = math.abs(playing - mid)
                info.score = -dist + math.random()

                if inMain then
                    table.insert(candidates, info)
                elseif inBackup then
                    table.insert(backups, info)
                end
            end
        end
    end

    if not cursor then
        break
    end
end

----------------------------------------------------------------
-- 🎯 Pilih server target
----------------------------------------------------------------
local target = pickBest(candidates)

if not target then
    if #backups > 0 then
        warn(("[ServerHop] Tidak ada server %d–%d pemain, pakai server cadangan (≥%d pemain).")
            :format(CONFIG.MinPlayers, CONFIG.MaxPlayers, CONFIG.BackupMinPlayers))
        target = pickBest(backups)
    else
        warn("[ServerHop] Tidak ada server lain yang bisa dimasuki (advanced). Rejoin biasa.")
        SimpleRejoin()
        return
    end
end

----------------------------------------------------------------
-- 🚀 Teleport ke server target
----------------------------------------------------------------
print(("[ServerHop] Teleport ke server %s (%d/%d pemain)")
    :format(target.id, target.playing, target.max))

if CONFIG.RememberVisited then
    visited[target.id] = true
end

local okTp, tpErr = pcall(function()
    TeleportService:TeleportToPlaceInstance(placeId, target.id, LocalPlayer)
end)

if not okTp then
    local errStr = tostring(tpErr)
    warn("[ServerHop] Teleport gagal:", errStr)

    if errStr:find("773") or errStr:lower():find("restricted") then
        warn("[ServerHop] Error 773 (tempat/server dibatasi Roblox). " ..
             "Ini batas server, bukan script. Coba lagi nanti atau ganti game.")
    end
end
