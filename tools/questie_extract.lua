-- Extrait de la base QuestieDB (WoW Forever) les champs utiles à Forever Elites, en JSON.
-- Données : https://github.com/Questie/QuestieDB (data/Forever), licence GPLv3.
-- Usage : lua5.1 questie_extract.lua foreverQuestDB.lua foreverNpcDB.lua foreverObjectDB.lua foreverItemDB.lua > questie.json

local questFile, npcFile, objectFile, itemFile = arg[1], arg[2], arg[3], arg[4]

-- Bouchons minimaux pour charger les fichiers de Questie hors du jeu
QuestieDB = {}
QuestieLoader = { ImportModule = function() return QuestieDB end }

assert(loadfile(questFile))()
assert(loadfile(npcFile))()
local quests = assert(loadstring(QuestieDB.questData))()
local npcs = assert(loadstring(QuestieDB.npcData))()
local objects = {}
if objectFile then
    assert(loadfile(objectFile))()
    objects = assert(loadstring(QuestieDB.objectData))()
end

local items = {}
if itemFile then
    assert(loadfile(itemFile))()
    items = assert(loadstring(QuestieDB.itemData))()
end

local qk, nk, ok, ik = QuestieDB.questKeys, QuestieDB.npcKeys, QuestieDB.objectKeys, QuestieDB.itemKeys

-- Zone où se déroule l'objectif : chaque objectif (monstre, objet, butin, lieu) vote pour
-- les zones où il apparaît, au prorata de ses points d'apparition.
local function AddSpawns(votes, spawnLists)
    local total, perZone = 0, {}
    for _, spawns in ipairs(spawnLists) do
        if type(spawns) == "table" then
            for zone, coords in pairs(spawns) do
                if type(coords) == "table" and #coords > 0 then
                    perZone[zone] = (perZone[zone] or 0) + #coords
                    total = total + #coords
                end
            end
        end
    end
    for zone, n in pairs(perZone) do votes[zone] = (votes[zone] or 0) + n / total end
end

local function NpcSpawns(id) local n = npcs[id]; return n and n[nk.spawns] end
local function ObjectSpawns(id) local o = objects[id]; return o and o[ok.spawns] end

local function ObjectiveZone(q)
    local votes = {}
    local obj = q[qk.objectives]
    if type(obj) == "table" then
        for _, c in ipairs(obj[1] or {}) do AddSpawns(votes, { NpcSpawns(c[1]) }) end
        for _, o in ipairs(obj[2] or {}) do AddSpawns(votes, { ObjectSpawns(o[1]) }) end
        for _, it in ipairs(obj[3] or {}) do
            local item = items[it[1]]
            if item then
                local lists = {}
                for _, n in ipairs(item[ik.npcDrops] or {}) do lists[#lists + 1] = NpcSpawns(n) end
                for _, o in ipairs(item[ik.objectDrops] or {}) do lists[#lists + 1] = ObjectSpawns(o) end
                AddSpawns(votes, lists)
            end
        end
        for _, kc in ipairs(obj[5] or {}) do
            local lists = {}
            for _, n in ipairs(type(kc[1]) == "table" and kc[1] or {}) do lists[#lists + 1] = NpcSpawns(n) end
            AddSpawns(votes, lists)
        end
    end
    local trigger = q[qk.triggerEnd]
    if type(trigger) == "table" and type(trigger[2]) == "table" then AddSpawns(votes, { trigger[2] }) end
    local best, bestVote, total = nil, 0, 0
    for zone, v in pairs(votes) do
        total = total + v
        if v > bestVote then best, bestVote = zone, v end
    end
    return best, total > 0 and bestVote / total or 0, votes
end

local function jsonStr(s)
    return '"' .. tostring(s):gsub('[%c"\\]', function(c)
        if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" end
        return string.format("\\u%04x", c:byte())
    end) .. '"'
end

local function jsonList(t)
    if type(t) ~= "table" then return "null" end
    local out = {}
    for _, v in ipairs(t) do out[#out + 1] = tostring(v) end
    return "[" .. table.concat(out, ",") .. "]"
end

-- Première position connue d'un PNJ ou d'un objet : nom, zone (AreaTable ID), coordonnées
local function Spot(name, spawns, preferred)
    if type(spawns) ~= "table" then return name end
    if preferred and spawns[preferred] and spawns[preferred][1] then
        local c = spawns[preferred][1]
        return name, preferred, c[1], c[2]
    end
    for zone, coords in pairs(spawns) do
        if type(coords) == "table" and coords[1] then return name, zone, coords[1][1], coords[1][2] end
    end
    return name
end

local function NpcSpot(id)
    local n = npcs[id]
    if n then return Spot(n[nk.name], n[nk.spawns], n[nk.zoneID]) end
end

local function ObjectSpot(id)
    local o = objects[id]
    if o then return Spot(o[ok.name], o[ok.spawns], o[ok.zoneID]) end
end

io.write("{\n")
local first = true
for id, q in pairs(quests) do
    local fields = {
        '"name":' .. jsonStr(q[qk.name] or ("#" .. id)),
        '"reqlevel":' .. tostring(q[qk.requiredLevel] or "null"),
        '"level":' .. tostring(q[qk.questLevel] or "null"),
        '"races":' .. string.format("%.0f", q[qk.requiredRaces] or 0),
        '"zone":' .. tostring(q[qk.zoneOrSort] or "null"),
        '"group":' .. jsonList(q[qk.preQuestGroup]),
        '"single":' .. jsonList(q[qk.preQuestSingle]),
    }
    local objZone, objShare, votes = ObjectiveZone(q)
    if objZone then
        local v = {}
        for z, n in pairs(votes) do v[#v + 1] = string.format('"%d":%.2f', z, n) end
        fields[#fields + 1] = string.format('"objZone":%d,"objShare":%.2f,"objVotes":{%s}', objZone, objShare, table.concat(v, ","))
    end
    local starts = q[qk.startedBy]
    local creature = type(starts) == "table" and type(starts[1]) == "table" and starts[1][1]
    local object = type(starts) == "table" and type(starts[2]) == "table" and starts[2][1]
    if creature or object then
        local npcName, zone, x, y
        if creature then npcName, zone, x, y = NpcSpot(creature) end
        if not x and object then npcName, zone, x, y = ObjectSpot(object) end
        if npcName then fields[#fields + 1] = '"npc":' .. jsonStr(npcName) end
        if zone and x then
            fields[#fields + 1] = string.format('"areaId":%d,"x":%.1f,"y":%.1f', zone, x, y)
        end
    end
    io.write(first and "" or ",\n", '"', id, '":{', table.concat(fields, ","), "}")
    first = false
end
io.write("\n}\n")
