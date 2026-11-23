local ADDON, ns = ...
local L = ns.L

ns.demo = false
ns.viewKey = nil       -- personnage affiché (clé "Nom-Royaume")
ns.selected = nil      -- ID de la quête élite sélectionnée, ou "home" (page d'accueil)

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8000" .. L.TITLE .. "|r : " .. tostring(msg))
end
ns.Print = Print

---------------------------------------------------------------------------
-- Accès API compatible Classic / moderne
---------------------------------------------------------------------------
local IsFlaggedCompleted = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted

local function QuestLogHas(id)
    if id <= 0 then return false end
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        local idx = C_QuestLog.GetLogIndexForQuestID(id)
        return idx ~= nil and idx > 0
    end
    if GetQuestLogIndexByID then
        local idx = GetQuestLogIndexByID(id)
        return idx ~= nil and idx > 0
    end
    if GetNumQuestLogEntries and GetQuestLogTitle then
        for i = 1, GetNumQuestLogEntries() do
            local qid = select(8, GetQuestLogTitle(i))
            if qid == id then return true end
        end
    end
    return false
end

local function CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end
ns.CharKey = CharKey

---------------------------------------------------------------------------
-- Données
---------------------------------------------------------------------------
function ns.GetQuests()
    return ns.demo and ns.DemoQuests or ns.Quests
end

local ENGLISH = { enUS = true, enGB = true }

function ns.QuestName(id)
    local q = ns.GetQuests()[id]
    if not q then return ("#%d"):format(id) end
    local n = q.name
    if type(n) == "table" then
        n = n[GetLocale()] or n.enUS or select(2, next(n))
    end
    -- Hors anglais : titre localisé du client. Absent de son cache, il est demandé au serveur
    -- et la liste se rafraîchit quand il arrive ; l'anglais s'affiche en attendant.
    if not ns.demo and not ENGLISH[GetLocale()] and id > 0 and C_QuestLog and C_QuestLog.GetQuestInfo then
        local t = C_QuestLog.GetQuestInfo(id)
        if type(t) == "string" and t ~= "" then return t end
        ns.RequestQuestData(id)
    end
    return n or ("#%d"):format(id)
end

---------------------------------------------------------------------------
-- Noms localisés demandés au client via une infobulle cachée
---------------------------------------------------------------------------
local scanTip
local function TipTitle(link)
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "EliteQuestsScanTip", nil, "GameTooltipTemplate")
    end
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:ClearLines()
    if not pcall(scanTip.SetHyperlink, scanTip, link) then return end
    local line = _G.EliteQuestsScanTipTextLeft1
    local t = line and line:GetText()
    if t and t ~= "" then return t end
end

-- File de demandes de titres au serveur, à petit débit (des centaines de quêtes d'un coup
-- risquent de faire refuser les requêtes). ponytail: débit fixe, adapter si le serveur bride.
local QUEST_REQUESTS_PER_TICK = 10
local requested, queue, ticker = {}, {}, nil
function ns.RequestQuestData(id)
    if requested[id] then return end
    requested[id] = true
    queue[#queue + 1] = id
    if ticker then return end
    ticker = C_Timer.NewTicker(0.5, function()
        for _ = 1, QUEST_REQUESTS_PER_TICK do
            local qid = table.remove(queue, 1)
            if not qid then break end
            if C_QuestLog.RequestLoadQuestByID then
                C_QuestLog.RequestLoadQuestByID(qid)
            else
                TipTitle("quest:" .. qid)
            end
        end
        if #queue == 0 then
            ticker:Cancel(); ticker = nil
            C_Timer.After(1, function() if ns.RequestRefresh then ns.RequestRefresh() end end)
        end
    end)
end

-- Nom du PNJ qui donne la quête, dans la langue du client si elle le connaît.
local npcNames = {}
function ns.NpcName(q)
    if not q.npcId or ns.demo or ENGLISH[GetLocale()] then return q.npc end
    if not npcNames[q.npcId] then
        npcNames[q.npcId] = TipTitle(("unit:Creature-0-0-0-0-%d-0000000000"):format(q.npcId))
    end
    return npcNames[q.npcId] or q.npc
end

-- Nom de zone dans la langue du client : catégorie traduite, sinon nom de zone du client
-- (AreaTable), sinon nom de classe localisé, sinon le nom anglais de Data.lua.
local zoneNameCache = {}
function ns.ZoneName(z)
    if not z then return "?" end
    local n = zoneNameCache[z]
    if n then return n end
    n = L.CAT[z]
    local area = ns.ZoneAreas and ns.ZoneAreas[z]
    if not n and area and C_Map and C_Map.GetAreaInfo then
        n = C_Map.GetAreaInfo(area)
        if n == "" then n = nil end
    end
    if not n and LOCALIZED_CLASS_NAMES_MALE then n = LOCALIZED_CLASS_NAMES_MALE[z:upper()] end
    n = n or z
    zoneNameCache[z] = n
    return n
end

-- Icônes devant les zones. Chaque zone liste des textures candidates (sans dossier =
-- Interface\Icons\) ; la première présente dans le client gagne, sinon une carte générique.
-- ponytail: noms devinés d'après les icônes officielles ; /eqs icons liste celles absentes du client.
local DEFAULT_ZONE_ICON = "Interface\\Icons\\INV_Misc_Map_01"
local ZONE_ICONS = {
    -- Royaumes de l'Est
    ["Alterac Mountains"] = { "Achievement_Zone_AlteracMountains_01" },
    ["Arathi Highlands"] = { "Achievement_Zone_ArathiHighlands_01" },
    ["Badlands"] = { "Achievement_Zone_Badlands_01" },
    ["Blasted Lands"] = { "Achievement_Zone_BlastedLands_01" },
    ["Burning Steppes"] = { "Achievement_Zone_BurningSteppes_01" },
    ["Dun Morogh"] = { "Achievement_Zone_DunMorogh" },
    ["Duskwood"] = { "Achievement_Zone_Duskwood" },
    ["Eastern Plaguelands"] = { "Achievement_Zone_EasternPlaguelands" },
    ["Elwynn Forest"] = { "Achievement_Zone_ElwynnForest" },
    ["Hillsbrad Foothills"] = { "Achievement_Zone_HillsbradFoothills" },
    ["Ironforge"] = { "Spell_Arcane_TeleportIronForge" },
    ["Loch Modan"] = { "Achievement_Zone_LochModan" },
    ["Redridge Mountains"] = { "Achievement_Zone_RedridgeMountains" },
    ["Searing Gorge"] = { "Achievement_Zone_SearingGorge_01" },
    ["Silverpine Forest"] = { "Achievement_Zone_Silverpine_01" },
    ["Stormwind City"] = { "Spell_Arcane_TeleportStormWind" },
    ["Stranglethorn Vale"] = { "Achievement_Zone_Stranglethorn_01" },
    ["Swamp of Sorrows"] = { "Achievement_Zone_SwampSorrows_01" },
    ["The Hinterlands"] = { "Achievement_Zone_Hinterlands_01" },
    ["Tirisfal Glades"] = { "Achievement_Zone_TirisfalGlades_01" },
    ["Undercity"] = { "Spell_Arcane_TeleportUnderCity" },
    ["Western Plaguelands"] = { "Achievement_Zone_WesternPlaguelands_01" },
    ["Wetlands"] = { "Achievement_Zone_Wetlands_01" },
    ["Riverglades"] = { "Spell_Nature_ProtectionformNature" },
    -- Kalimdor
    ["Ashenvale"] = { "Achievement_Zone_Ashenvale_01" },
    ["Azshara"] = { "Achievement_Zone_Azshara_01" },
    ["Darkshore"] = { "Achievement_Zone_Darkshore_01" },
    ["Desolace"] = { "Achievement_Zone_Desolace" },
    ["Durotar"] = { "Achievement_Zone_Durotar" },
    ["Dustwallow Marsh"] = { "Achievement_Zone_DustwallowMarsh" },
    ["Felwood"] = { "Achievement_Zone_Felwood" },
    ["Feralas"] = { "Achievement_Zone_Feralas" },
    ["Mount Hyjal"] = { "Achievement_Zone_Mount Hyjal", "INV_Misc_Herb_19" },
    ["Mulgore"] = { "Achievement_Zone_Mulgore_01" },
    ["Silithus"] = { "Achievement_Zone_Silithus_01" },
    ["Stonetalon Mountains"] = { "Achievement_Zone_Stonetalon_01" },
    ["Tanaris"] = { "Achievement_Zone_Tanaris_01" },
    ["Teldrassil"] = { "Achievement_Zone_Teldrassil_01", "Spell_Arcane_TeleportDarnassus" },
    ["The Barrens"] = { "Achievement_Zone_Barrens_01" },
    ["Thousand Needles"] = { "Achievement_Zone_ThousandNeedles_01" },
    ["Thunder Bluff"] = { "Spell_Arcane_TeleportThunderBluff" },
    ["Un'Goro Crater"] = { "Achievement_Zone_UnGoroCrater_01" },
    ["Winterspring"] = { "Achievement_Zone_Winterspring" },
    ["South Seas"] = { "INV_Misc_Fish_14" },
    ["Blackmaw Hold"] = { "Ability_Racial_BearForm", "Ability_Druid_Maul" },
    ["Shen'dralas"] = { "Spell_Arcane_StarFire", "Spell_Holy_MagicalSentry" },
    ["Zephras Isle"] = { "INV_Misc_Shell_01", "Spell_Frost_SummonWaterElemental" },
    -- Quêtes de classe, métiers, événements, divers
    ["Druid"] = { "ClassIcon_Druid", "Ability_Druid_Maul" },
    ["Hunter"] = { "ClassIcon_Hunter", "INV_Weapon_Bow_07" },
    ["Mage"] = { "ClassIcon_Mage", "INV_Staff_13" },
    ["Paladin"] = { "ClassIcon_Paladin", "Spell_Holy_HolyBolt" },
    ["Rogue"] = { "ClassIcon_Rogue", "INV_ThrowingKnife_04" },
    ["Shaman"] = { "ClassIcon_Shaman", "Spell_Nature_BloodLust" },
    ["Warlock"] = { "ClassIcon_Warlock", "Spell_Nature_FaerieFire" },
    ["Warrior"] = { "ClassIcon_Warrior", "INV_Sword_27" },
    ["Tailoring"] = { "Trade_Tailoring" },
    ["Winter Veil"] = { "INV_Holiday_Christmas_Present_01" },
    ["Nightmare Incursions"] = { "INV_Misc_Head_Dragon_Green" },
}

local function IconPath(p) return p:find("\\", 1, true) and p or ("Interface\\Icons\\" .. p) end
-- Sans GetFileIDFromPath, on ne peut pas vérifier : on prend le premier candidat.
local function IconExists(p) return not GetFileIDFromPath or GetFileIDFromPath(p) ~= nil end

local zoneIconCache = {}
-- Renvoie la texture de la zone, et false si on a dû se rabattre sur l'icône générique.
function ns.ZoneIcon(zone)
    if zoneIconCache[zone] == nil then
        zoneIconCache[zone] = false
        for _, c in ipairs(ZONE_ICONS[zone] or {}) do
            local p = IconPath(c)
            if IconExists(p) then zoneIconCache[zone] = p; break end
        end
    end
    return zoneIconCache[zone] or DEFAULT_ZONE_ICON, zoneIconCache[zone] ~= false
end

-- /eqs icons : zones de la liste sans icône trouvée dans le client.
local function ReportMissingIcons()
    local missing, seen = {}, {}
    for _, q in pairs(ns.Quests) do
        if q.elite and q.zone and not seen[q.zone] then
            seen[q.zone] = true
            local _, found = ns.ZoneIcon(q.zone)
            if not found then missing[#missing + 1] = q.zone end
        end
    end
    table.sort(missing)
    ns.Print(#missing == 0 and L.ICONS_OK
        or L.ICONS_MISSING:format(#missing, table.concat(missing, ", ")))
end

function ns.CurrentChar()
    return ns.db.chars[CharKey()]
end

function ns.ViewChar()
    return ns.db.chars[ns.viewKey or CharKey()] or ns.CurrentChar()
end

local function IsViewingSelf()
    return (ns.viewKey or CharKey()) == CharKey()
end

-- Quête terminée pour le personnage affiché ?
function ns.IsDone(id)
    if ns.demo then return ns.DemoStatus[id] == "done" end
    if IsViewingSelf() then
        return IsFlaggedCompleted(id) and true or false
    end
    local c = ns.ViewChar()
    return c and c.done[id] or false
end

function ns.CharLevel()
    if ns.demo then return ns.DemoLevel end
    if IsViewingSelf() then return UnitLevel("player") end
    local c = ns.ViewChar()
    return c and c.level or 1
end

function ns.FactionOK(q, faction)
    return not q.faction or not faction or q.faction == faction
end

-- Alternatives (preAny) jouables par le personnage affiché : on retire celles de l'autre faction
function ns.AnyPrereqs(q)
    if not q.preAny then return nil end
    local c = ns.ViewChar()
    local faction = (not ns.db.allFactions and not ns.demo and c) and c.faction or nil
    local out = {}
    for _, p in ipairs(q.preAny) do
        local pq = ns.GetQuests()[p]
        if not pq or ns.FactionOK(pq, faction) then out[#out + 1] = p end
    end
    return out
end

function ns.PrereqsMet(id)
    local q = ns.GetQuests()[id]
    if not q then return true end
    if q.pre then
        for _, p in ipairs(q.pre) do
            if not ns.IsDone(p) then return false end
        end
    end
    local any = ns.AnyPrereqs(q)
    if any and #any > 0 then
        local ok = false
        for _, p in ipairs(any) do
            if ns.IsDone(p) then ok = true break end
        end
        if not ok then return false end
    end
    return true
end

-- "done" | "log" | "available" | "locked"
function ns.Status(id)
    if ns.IsDone(id) then return "done" end
    if ns.demo then
        if ns.DemoStatus[id] then return ns.DemoStatus[id] end
    elseif IsViewingSelf() and QuestLogHas(id) then
        return "log"
    end
    local q = ns.GetQuests()[id]
    local c = ns.ViewChar()
    if q and q.minLevel and ns.CharLevel() < q.minLevel then return "locked" end
    if q and c and not ns.FactionOK(q, c.faction) then return "locked" end
    if ns.PrereqsMet(id) then return "available" end
    return "locked"
end

---------------------------------------------------------------------------
-- Arbre des prérequis (ordre chronologique, comme Attune)
-- Lignes : { kind = "level"|"quest"|"all"|"any"|"ref", id, depth, counts, ids, level }
---------------------------------------------------------------------------
local function Build(id, depth, rows, seen, underAny)
    local Q = ns.GetQuests()
    if seen[id] then
        rows[#rows + 1] = { kind = "ref", id = id, depth = depth, counts = false }
        return
    end
    seen[id] = true
    local q = Q[id] or {}
    local pre, any = q.pre, ns.AnyPrereqs(q)

    if pre and #pre == 1 then
        Build(pre[1], depth, rows, seen, underAny)
    elseif pre and #pre > 1 then
        rows[#rows + 1] = { kind = "all", depth = depth, counts = false }
        for _, p in ipairs(pre) do Build(p, depth + 1, rows, seen, underAny) end
    end

    if any and #any == 1 then
        Build(any[1], depth, rows, seen, underAny)
    elseif any and #any > 1 then
        rows[#rows + 1] = { kind = "any", depth = depth, ids = any, counts = not underAny }
        for _, p in ipairs(any) do Build(p, depth + 1, rows, seen, true) end
    end

    rows[#rows + 1] = { kind = "quest", id = id, depth = depth, counts = not underAny }
end

local treeCache = {}
function ns.Tree(eliteId)
    local c = ns.ViewChar()
    local key = (ns.demo and "d" or "r") .. (ns.db.allFactions and "*" or (c and c.faction or "")) .. eliteId
    if treeCache[key] then return treeCache[key] end
    local rows = {}
    local q = ns.GetQuests()[eliteId]
    if q and q.minLevel then
        rows[1] = { kind = "level", level = q.minLevel, depth = 0, counts = true }
    end
    Build(eliteId, 0, rows, {}, false)
    treeCache[key] = rows
    return rows
end

function ns.RowDone(row)
    if row.kind == "level" then return ns.CharLevel() >= row.level end
    if row.kind == "quest" or row.kind == "ref" then return ns.IsDone(row.id) end
    if row.kind == "any" then
        for _, p in ipairs(row.ids) do if ns.IsDone(p) then return true end end
        return false
    end
    return false
end

function ns.Progress(eliteId)
    local done, total = 0, 0
    for _, row in ipairs(ns.Tree(eliteId)) do
        if row.counts then
            total = total + 1
            if ns.RowDone(row) then done = done + 1 end
        end
    end
    return done, total
end

-- Liste des quêtes élites visibles, triées continent > zone > niveau > nom
function ns.EliteList()
    local Q = ns.GetQuests()
    local c = ns.ViewChar()
    local faction = (not ns.db.allFactions and not ns.demo and c) and c.faction or nil
    local list = {}
    for id, q in pairs(Q) do
        if q.elite and ns.FactionOK(q, faction) then list[#list + 1] = id end
    end
    table.sort(list, function(a, b)
        local qa, qb = Q[a], Q[b]
        local ca, cb = qa.continent or "~", qb.continent or "~"
        if ca ~= cb then return ca < cb end
        local za, zb = qa.zone or "~", qb.zone or "~"
        if za ~= zb then return za < zb end
        if (qa.level or 0) ~= (qb.level or 0) then return (qa.level or 0) < (qb.level or 0) end
        return ns.QuestName(a) < ns.QuestName(b)
    end)
    return list
end

---------------------------------------------------------------------------
-- Sauvegarde de la progression (consultation des rerolls)
---------------------------------------------------------------------------
function ns.Snapshot()
    local key = CharKey()
    local c = ns.db.chars[key] or {}
    ns.db.chars[key] = c
    local _, class = UnitClass("player")
    c.name = UnitName("player")
    c.realm = GetRealmName()
    c.class = class
    c.faction = UnitFactionGroup("player")
    c.level = UnitLevel("player")
    c.done = {}
    for id in pairs(ns.Quests) do
        if IsFlaggedCompleted(id) then c.done[id] = true end
    end
end

local function AvailableElites()
    local set = {}
    for id, q in pairs(ns.Quests) do
        if q.elite and ns.Status(id) == "available" then set[id] = true end
    end
    return set
end

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
ns.eventFrame = f
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("QUEST_TURNED_IN")
f:RegisterEvent("QUEST_LOG_UPDATE")
f:RegisterEvent("PLAYER_LEVEL_UP")

local pendingRefresh = false
local function RequestRefresh()
    if pendingRefresh then return end
    pendingRefresh = true
    C_Timer.After(0.5, function()
        pendingRefresh = false
        if ns.Refresh then ns.Refresh() end
    end)
end
ns.RequestRefresh = RequestRefresh

f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        ForeverElitesDB = ForeverElitesDB or {}
        local db = ForeverElitesDB
        db.chars = db.chars or {}
        db.collapsed = db.collapsed or {}
        db.minimap = db.minimap or { angle = 200, hide = false }
        if db.hideDone == nil then db.hideDone = false end
        if db.allFactions == nil then db.allFactions = false end
        if db.viewMode == nil then db.viewMode = "tree" end
        ns.db = db
    elseif event == "PLAYER_LOGIN" then
        ns.Snapshot()
        ns.viewKey = CharKey()
        if ns.CreateMinimapButton then ns.CreateMinimapButton() end
    elseif event == "QUEST_TURNED_IN" then
        local qid = arg1
        local q = ns.Quests[qid]
        local before = q and AvailableElites()
        C_Timer.After(1, function()
            ns.Snapshot()
            if q then
                local saved = ns.viewKey
                ns.viewKey = CharKey()
                Print((q.elite and L.ELITE_DONE_MSG or L.STEP_DONE_MSG):format("|cffffff00" .. ns.QuestName(qid) .. "|r"))
                for id in pairs(AvailableElites()) do
                    if not before[id] then
                        Print(L.NOW_AVAILABLE:format("|cffff8000" .. ns.QuestName(id) .. "|r"))
                    end
                end
                ns.viewKey = saved
            end
            RequestRefresh()
        end)
    elseif event == "PLAYER_LEVEL_UP" then
        C_Timer.After(1, function() ns.Snapshot(); RequestRefresh() end)
    elseif event == "QUEST_LOG_UPDATE" then
        RequestRefresh()
    end
end)

---------------------------------------------------------------------------
-- Commandes
---------------------------------------------------------------------------
SLASH_FOREVERELITES1 = "/eqs"
SLASH_FOREVERELITES2 = "/elitequests"
SlashCmdList.FOREVERELITES = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "demo" then
        ns.demo = not ns.demo
        ns.selected = nil
        Print(ns.demo and L.DEMO_ON or L.DEMO_OFF)
        ns.Toggle(true)
    elseif msg == "minimap" then
        ns.db.minimap.hide = not ns.db.minimap.hide
        if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
    elseif msg == "reset" then
        ns.db.point = nil
        if ns.ResetPosition then ns.ResetPosition() end
    elseif msg == "icons" then
        ReportMissingIcons()
    elseif msg == "help" or msg == "?" then
        Print(L.HELP)
    else
        ns.Toggle()
    end
end
