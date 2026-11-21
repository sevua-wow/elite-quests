local ADDON, ns = ...
local L = ns.L

local W, H       = 940, 600
local LEFT_W     = 320
local INDENT     = 18
local TREE_ROW_H = 20
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

local STATUS_COLOR = {
    done      = { 0.15, 1.00, 0.15 },
    log       = { 1.00, 0.82, 0.00 },
    available = { 1.00, 1.00, 1.00 },
    locked    = { 0.55, 0.55, 0.55 },
}
local STATUS_ICON = {
    done      = "Interface\\RaidFrame\\ReadyCheck-Ready",
    log       = "Interface\\RaidFrame\\ReadyCheck-Waiting",
    available = "Interface\\GossipFrame\\AvailableQuestIcon",
    locked    = "Interface\\Buttons\\UI-CheckBox-Up",
}
local STATUS_TEXT = {
    done = L.STATUS_DONE, log = L.STATUS_LOG, available = L.STATUS_AVAILABLE, locked = L.STATUS_LOCKED,
}
local ICON_QUEST = "Interface\\Icons\\INV_Misc_Note_01"
local ICON_ELITE = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"
local ICON_HOME = "Interface\\Icons\\INV_Misc_Book_09"
local HOME = "home" -- valeur de ns.selected quand la page d'accueil est affichée
ns.HOME = HOME

-- Version lue dans le .toc ; "dev" tant que le packager n'a pas remplacé @project-version@.
local function AddonVersion()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local v = get and get(ADDON, "Version")
    if type(v) ~= "string" or v == "" or v:find("@", 1, true) then return "dev" end
    return v
end
local ICON_LEVEL = "Interface\\Icons\\Spell_ChargePositive"

local PANEL_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local MAIN_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

local frame, listScroll, listContent, treeScroll, treeContent
local header = {}
local listRows, treeRows = {}, {}
local searchText = ""

---------------------------------------------------------------------------
-- Petits utilitaires
---------------------------------------------------------------------------
local function SetColor(tex, r, g, b, a)
    if tex.SetColorTexture then tex:SetColorTexture(r, g, b, a or 1) else tex:SetTexture(r, g, b, a or 1) end
end

local function ProgressColor(p)
    if p >= 1 then return 0.1, 0.85, 0.1 end
    if p < 0.5 then return 0.85, 0.15 + p * 1.2, 0.1 end
    return 0.85 - (p - 0.5) * 1.2, 0.8, 0.1
end

local function CreateBar(parent, height)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetHeight(height)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", -1, 1)
    bg:SetPoint("BOTTOMRIGHT", 1, -1)
    SetColor(bg, 0, 0, 0, 0.7)
    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.text:SetPoint("CENTER", 0, 0)
    return bar
end

local function SetBar(bar, done, total)
    local p = total > 0 and done / total or 0
    bar:SetValue(p)
    bar:SetStatusBarColor(ProgressColor(p))
    return p
end

-- Règles du royaume tirées de son nom : "CAMWOW EU5 Realm 3 PvE" -> "PvE".
-- Nom complet si aucune règle n'est reconnue.
local RULESETS = { "RPPvP", "RPPvE", "PvP", "PvE" } -- RP d'abord : "rppvp" contient "pvp"
local function RealmRuleset(realm)
    local flat = (realm or ""):lower():gsub("[%s%-_]", "")
    for _, rs in ipairs(RULESETS) do
        if flat:find(rs:lower(), 1, true) then return rs end
    end
    return realm or "?"
end
ns.RealmRuleset = RealmRuleset

local function ClassColorName(c)
    local col = c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
    if col then
        return ("|cff%02x%02x%02x%s|r"):format(col.r * 255, col.g * 255, col.b * 255, c.name or "?")
    end
    return c.name or "?"
end

local function FactionLabel(f)
    if f == "Alliance" then return FACTION_ALLIANCE or "Alliance" end
    if f == "Horde" then return FACTION_HORDE or "Horde" end
    return L.UNKNOWN_FACTION
end

local function QuestLink(id)
    local q = ns.GetQuests()[id]
    return ("|cffffff00|Hquest:%d:%d|h[%s]|h|r"):format(id, q and q.level or 0, ns.QuestName(id))
end

local function QuestTooltip(owner, id)
    local q = ns.GetQuests()[id] or {}
    local st = ns.Status(id)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ns.QuestName(id), unpack(STATUS_COLOR[st]))
    if q.elite then GameTooltip:AddLine(L.ELITE, 1, 0.5, 0) end
    GameTooltip:AddLine(STATUS_TEXT[st], unpack(STATUS_COLOR[st]))
    if q.level then GameTooltip:AddLine(L.LEVEL:format(q.level), 1, 1, 1) end
    if q.minLevel then GameTooltip:AddLine(L.MIN_LEVEL:format(q.minLevel), 1, 1, 1) end
    if q.zone then GameTooltip:AddLine(L.ZONE:format(ns.ZoneName(q.zone)), 1, 1, 1) end
    if q.npc then
        local where = q.npc
        if q.startZone then where = where .. " — " .. ns.ZoneName(q.startZone) end
        if q.x and q.y then where = ("%s (%.1f, %.1f)"):format(where, q.x, q.y) end
        GameTooltip:AddLine(L.STARTS_AT:format(where), 1, 1, 1)
    end
    if q.group then GameTooltip:AddLine(L.GROUP:format(q.group), 1, 1, 1) end
    if q.faction then GameTooltip:AddLine(FactionLabel(q.faction), 0.7, 0.7, 1) end
    if q.note then GameTooltip:AddLine(q.note, 0.8, 0.8, 0.8, true) end
    if id > 0 then GameTooltip:AddLine(L.QUEST_ID:format(id), 0.5, 0.5, 0.5) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.CLICK_HINT, 0.5, 0.8, 1)
    GameTooltip:Show()
end

-- Wowhead donne un ID de zone (areaId) ; la carte du jeu utilise un uiMapID.
-- On les relie une fois en jeu en comparant les noms (localisés) des zones et des cartes.
local mapCache = {}
function ns.ResolveMapId(q)
    if q.mapId then return q.mapId end
    if not q.areaId or not (C_Map and C_Map.GetMapInfo) then return nil end
    if mapCache[q.areaId] ~= nil then return mapCache[q.areaId] or nil end
    local wanted = {}
    if C_Map.GetAreaInfo then
        local n = C_Map.GetAreaInfo(q.areaId)
        if n then wanted[n:lower()] = true end
    end
    if q.zone then wanted[q.zone:lower()] = true end
    local best, bestType
    for mapId = 1, 3000 do
        local info = C_Map.GetMapInfo(mapId)
        if info and info.name and wanted[info.name:lower()] then
            -- on préfère une carte de type « zone » (3) à un donjon ou une micro-carte
            if not best or (info.mapType == 3 and bestType ~= 3) then best, bestType = mapId, info.mapType end
        end
    end
    mapCache[q.areaId] = best or false
    return best
end

-- Épingle native sur la carte du monde (repli : TomTom, puis coordonnées dans le chat)
function ns.SetMapPin(id)
    local q = ns.GetQuests()[id]
    local name = ns.QuestName(id)
    local mapId = q and q.x and q.y and ns.ResolveMapId(q)
    if not mapId then
        ns.Print(L.NO_COORDS:format(name))
        return
    end
    local canPin = C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates
    if canPin and C_Map.CanSetUserWaypointOnMap then canPin = C_Map.CanSetUserWaypointOnMap(mapId) end
    if canPin then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapId, q.x / 100, q.y / 100))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
        ns.Print(L.PIN_SET:format(name, q.x, q.y))
    elseif TomTom and TomTom.AddWaypoint then
        TomTom:AddWaypoint(mapId, q.x / 100, q.y / 100, { title = name })
        ns.Print(L.PIN_SET:format(name, q.x, q.y))
    else
        ns.Print(L.PIN_COORDS:format(name, ns.ZoneName(q.zone), q.x, q.y))
    end
end

local function QuestClick(id, mouse)
    if IsShiftKeyDown() then
        if id > 0 and ChatEdit_InsertLink then ChatEdit_InsertLink(QuestLink(id)) end
        return true
    elseif IsControlKeyDown() then
        ns.SetMapPin(id)
        return true
    end
    return false
end

ns.QuestTooltip = QuestTooltip
ns.QuestClick = QuestClick

---------------------------------------------------------------------------
-- Liste de gauche : continent > zone > quêtes élites (avec barres)
---------------------------------------------------------------------------
-- Retrait des zones (et de leurs quêtes) sous leur continent, effet « dossier ».
local ZONE_INDENT = 14

local function GetListRow(i)
    local row = listRows[i]
    if row then return row end
    row = CreateFrame("Button", nil, listContent)
    row:RegisterForClicks("LeftButtonUp")

    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row.hl:SetBlendMode("ADD")

    row.sel = row:CreateTexture(nil, "BACKGROUND")
    row.sel:SetAllPoints()
    SetColor(row.sel, 1, 0.82, 0, 0.18)

    row.expand = row:CreateTexture(nil, "ARTWORK")
    row.expand:SetSize(14, 14)
    row.expand:SetPoint("LEFT", 2, 0)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(14, 14)

    row.zoneIcon = row:CreateTexture(nil, "ARTWORK")
    row.zoneIcon:SetSize(16, 16)
    row.zoneIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.text:SetJustifyH("LEFT")
    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.right:SetJustifyH("RIGHT")

    row.bar = CreateBar(row, 10)

    row:SetScript("OnClick", function(self, mouse)
        if self.kind == "home" then
            ns.selected = HOME
            ns.Refresh()
        elseif self.kind == "zone" or self.kind == "continent" then
            ns.db.collapsed[self.key] = not ns.db.collapsed[self.key] or nil
            ns.Refresh()
        elseif self.kind == "elite" then
            if not QuestClick(self.id, mouse) then
                ns.selected = self.id
                ns.Refresh()
            end
        end
    end)
    row:SetScript("OnEnter", function(self)
        if self.kind == "elite" then QuestTooltip(self, self.id) end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    listRows[i] = row
    return row
end

local function Matches(id)
    if searchText == "" then return true end
    local q = ns.GetQuests()[id]
    local hay = (ns.QuestName(id) .. " " .. ns.ZoneName(q.zone) .. " " .. (q.continent or "")):lower()
    return hay:find(searchText, 1, true) ~= nil
end

-- Lignes de la liste : continent > zone > élites, en tenant compte des replis et de la recherche.
local function BuildListEntries()
    local Q = ns.GetQuests()
    local entries, zoneStats = { { kind = "home", text = L.HOME } }, {}
    local lastCont, lastZone, contEntry
    local firstVisible, selectedVisible
    for _, id in ipairs(ns.EliteList()) do
        if Matches(id) then
            local q = Q[id]
            local cont, zone = q.continent or "?", q.zone or "?"
            local zkey = cont .. "/" .. zone
            if cont ~= lastCont then
                contEntry = { kind = "continent", key = cont, text = ns.ZoneName(cont), done = 0, total = 0 }
                entries[#entries + 1] = contEntry
                lastCont, lastZone = cont, nil
            end
            local contOpen = searchText ~= "" or not ns.db.collapsed[cont]
            if zone ~= lastZone and contOpen then
                local z = { kind = "zone", key = zkey, zone = zone, text = ns.ZoneName(zone), done = 0, total = 0 }
                entries[#entries + 1] = z
                zoneStats[zkey] = z
                lastZone = zone
            end
            local d, t = ns.Progress(id)
            local finished = t > 0 and d >= t
            contEntry.total = contEntry.total + 1
            if finished then contEntry.done = contEntry.done + 1 end
            local zs = zoneStats[zkey]
            if zs then
                zs.total = zs.total + 1
                if finished then zs.done = zs.done + 1 end
            end
            if contOpen and (searchText ~= "" or not ns.db.collapsed[zkey]) then
                entries[#entries + 1] = { kind = "elite", id = id, done = d, total = t }
            end
            firstVisible = firstVisible or id
            if id == ns.selected then selectedVisible = true end
        end
    end
    if ns.selected ~= HOME and not selectedVisible then
        ns.selected = ns.selected and firstVisible or HOME
        if not ns.selected then ns.selected = HOME end
    end
    return entries
end
ns.BuildListEntries = BuildListEntries

local function RefreshList()
    local Q = ns.GetQuests()
    local width = listScroll:GetWidth()
    local entries = BuildListEntries()

    local y = 0
    for i, e in ipairs(entries) do
        local row = GetListRow(i)
        row.kind, row.id, row.key = e.kind, e.id, e.key
        row:ClearAllPoints()
        row.text:ClearAllPoints()
        row.right:ClearAllPoints()
        row.icon:ClearAllPoints()
        row.bar:Hide(); row.expand:Hide(); row.icon:Hide(); row.zoneIcon:Hide(); row.sel:Hide()
        row.right:SetText("")
        local h
        if e.kind == "home" then
            h = 26
            row.zoneIcon:SetTexture(ICON_HOME)
            row.zoneIcon:ClearAllPoints()
            row.zoneIcon:SetPoint("LEFT", 2, 0)
            row.zoneIcon:Show()
            row.text:SetFontObject("GameFontNormalLarge")
            row.text:SetPoint("LEFT", row.zoneIcon, "RIGHT", 6, 0)
            row.text:SetText(e.text)
            row.text:SetTextColor(1, 0.82, 0)
            if ns.selected == HOME then row.sel:Show() end
            row.hl:SetAlpha(1)
        elseif e.kind == "continent" then
            h = 24
            row.expand:Show()
            row.expand:ClearAllPoints()
            row.expand:SetPoint("LEFT", 2, 0)
            local collapsed = ns.db.collapsed[e.key] and searchText == ""
            row.expand:SetTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
            row.text:SetFontObject("GameFontNormalLarge")
            row.text:SetPoint("LEFT", row.expand, "RIGHT", 4, -1)
            row.text:SetText(e.text)
            row.right:SetPoint("RIGHT", -4, 0)
            row.right:SetText(("%d/%d"):format(e.done, e.total))
            row.hl:SetAlpha(1)
        elseif e.kind == "zone" then
            h = 20
            row.expand:Show()
            row.expand:ClearAllPoints()
            row.expand:SetPoint("LEFT", 2 + ZONE_INDENT, 0)
            local collapsed = ns.db.collapsed[e.key] and searchText == ""
            row.expand:SetTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
            row.zoneIcon:SetTexture((ns.ZoneIcon(e.zone)))
            row.zoneIcon:ClearAllPoints()
            row.zoneIcon:SetPoint("LEFT", row.expand, "RIGHT", 4, 0)
            row.zoneIcon:Show()
            row.text:SetFontObject("GameFontNormal")
            row.text:SetPoint("LEFT", row.zoneIcon, "RIGHT", 5, 0)
            row.text:SetText(e.text)
            row.right:SetPoint("RIGHT", -4, 0)
            row.right:SetText(("%d/%d"):format(e.done, e.total))
            row.hl:SetAlpha(1)
        else
            h = 34
            local st = ns.Status(e.id)
            local pct = e.total > 0 and e.done / e.total or 0
            row.icon:Show()
            row.icon:SetTexture(STATUS_ICON[st])
            row.icon:SetPoint("TOPLEFT", 20 + ZONE_INDENT, -3)
            row.text:SetFontObject("GameFontHighlight")
            row.text:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 4, 0)
            row.text:SetPoint("RIGHT", -34, 0)
            row.text:SetText(ns.QuestName(e.id))
            row.text:SetTextColor(unpack(pct >= 1 and STATUS_COLOR.done or STATUS_COLOR.available))
            row.right:SetPoint("TOPRIGHT", -4, -4)
            local lvl = Q[e.id].level
            row.right:SetText(lvl and ("[%d]"):format(lvl) or "")
            row.bar:Show()
            row.bar:SetPoint("BOTTOMLEFT", 22 + ZONE_INDENT, 5)
            row.bar:SetPoint("BOTTOMRIGHT", -6, 5)
            SetBar(row.bar, e.done, e.total)
            row.bar.text:SetText(("%d %%"):format(math.floor(pct * 100 + 0.5)))
            if e.id == ns.selected then row.sel:Show() end
            row.hl:SetAlpha(1)
        end
        if e.kind == "zone" then row.text:SetTextColor(1, 0.82, 0) end
        if e.kind == "continent" then row.text:SetTextColor(1, 0.5, 0) end
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetSize(width, h)
        row:Show()
        y = y + h
    end
    for i = #entries + 1, #listRows do listRows[i]:Hide() end
    listContent:SetSize(width, math.max(y, 1))
    frame.empty:SetShown(#entries == 0)
end

---------------------------------------------------------------------------
-- Arbre de droite : étapes de la quête élite sélectionnée
---------------------------------------------------------------------------
local function GetTreeRow(i)
    local row = treeRows[i]
    if row then return row end
    row = CreateFrame("Button", nil, treeContent)
    row:SetHeight(TREE_ROW_H)
    row:RegisterForClicks("LeftButtonUp")

    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row.hl:SetBlendMode("ADD")

    row.vline = row:CreateTexture(nil, "BORDER")
    row.vline:SetWidth(1)
    SetColor(row.vline, 0.6, 0.6, 0.6, 0.6)
    row.hline = row:CreateTexture(nil, "BORDER")
    row.hline:SetHeight(1)
    SetColor(row.hline, 0.6, 0.6, 0.6, 0.6)

    row.status = row:CreateTexture(nil, "ARTWORK")
    row.status:SetSize(14, 14)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", row.status, "RIGHT", 3, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetJustifyH("LEFT")
    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.right:SetPoint("RIGHT", -6, 0)
    row.right:SetJustifyH("RIGHT")

    row:SetScript("OnClick", function(self, mouse)
        if not self.id then return end
        if QuestClick(self.id, mouse) then return end
        local q = ns.GetQuests()[self.id]
        if q and q.elite and self.id ~= ns.selected then
            ns.selected = self.id
            ns.Refresh()
        end
    end)
    row:SetScript("OnEnter", function(self) if self.id then QuestTooltip(self, self.id) end end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    treeRows[i] = row
    return row
end

local function VisibleTreeRows(eliteId)
    local all = ns.Tree(eliteId)
    if not ns.db.hideDone then return all end
    local kept = {}
    for _, r in ipairs(all) do
        if (r.kind == "all" or r.kind == "any") or not ns.RowDone(r) or r.id == eliteId then
            kept[#kept + 1] = r
        end
    end
    -- retire les en-têtes de groupe devenus vides
    local out = {}
    for i, r in ipairs(kept) do
        if r.kind == "all" or r.kind == "any" then
            local nxt = kept[i + 1]
            if nxt and nxt.depth > r.depth then out[#out + 1] = r end
        else
            out[#out + 1] = r
        end
    end
    return out
end

local function ShowHome()
    header.icon:Show()
    header.icon:SetTexture(ICON_HOME)
    header.title:SetText(L.TITLE)
    header.sub:SetText(L.HOME_VERSION:format(AddonVersion()))
    header.bar:Hide()
    frame.viewBtn:Hide()
    treeScroll:Hide()
    frame.graph:Hide()
    frame.home:SetText(table.concat({ L.HOME_WELCOME, L.HOME_ATTUNE, L.HOME_THANKS }, "\n\n"))
    frame.home:Show()
end

local function RefreshTree()
    local id = ns.selected
    local Q = ns.GetQuests()
    for _, r in ipairs(treeRows) do r:Hide() end
    if id == HOME then return ShowHome() end
    frame.home:Hide()
    frame.viewBtn:Show()
    local q = id and Q[id]
    if not q then
        header.title:SetText(L.SELECT_QUEST)
        header.sub:SetText("")
        header.icon:Hide()
        header.bar:Hide()
        treeContent:SetSize(treeScroll:GetWidth(), 1)
        ns.TreeView.Refresh(nil)
        return
    end
    header.icon:Show()
    header.icon:SetTexture(ICON_ELITE)
    header.title:SetText(ns.QuestName(id))
    local parts = {}
    if q.level then parts[#parts + 1] = L.LEVEL:format(q.level) end
    if q.zone then parts[#parts + 1] = ns.ZoneName(q.zone) end
    if q.group then parts[#parts + 1] = L.GROUP:format(q.group) end
    parts[#parts + 1] = FactionLabel(q.faction)
    header.sub:SetText(table.concat(parts, "  •  "))
    local d, t = ns.Progress(id)
    header.bar:Show()
    local p = SetBar(header.bar, d, t)
    header.bar.text:SetText(L.PROGRESS:format(d, t) .. ("  (%d %%)"):format(math.floor(p * 100 + 0.5)))

    local graphMode = ns.db.viewMode == "tree"
    frame.viewBtn:SetText(graphMode and L.LIST_VIEW or L.TREE_VIEW)
    frame.graph:SetShown(graphMode)
    treeScroll:SetShown(not graphMode)
    if graphMode then
        ns.TreeView.Refresh(id)
        return
    end

    local width = treeScroll:GetWidth()
    local rows = VisibleTreeRows(id)
    for i, r in ipairs(rows) do
        local row = GetTreeRow(i)
        local x = 6 + r.depth * INDENT
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * TREE_ROW_H)
        row:SetWidth(width)
        row.status:ClearAllPoints()
        row.status:SetPoint("LEFT", x, 0)
        row.id = (r.kind == "quest" or r.kind == "ref") and r.id or nil

        if r.depth > 0 then
            local lx = 6 + (r.depth - 1) * INDENT + 7
            row.vline:ClearAllPoints()
            row.vline:SetPoint("TOPLEFT", lx, 0)
            row.vline:SetPoint("BOTTOMLEFT", lx, 0)
            row.hline:ClearAllPoints()
            row.hline:SetPoint("LEFT", lx, 0)
            row.hline:SetWidth(x - lx - 1)
            row.vline:Show(); row.hline:Show()
        else
            row.vline:Hide(); row.hline:Hide()
        end

        row.text:ClearAllPoints()
        row.right:SetText("")
        if r.kind == "all" or r.kind == "any" then
            local done = ns.RowDone(r)
            row.status:SetTexture(done and STATUS_ICON.done or STATUS_ICON.locked)
            row.status:Show()
            row.icon:Hide()
            row.text:SetPoint("LEFT", row.status, "RIGHT", 4, 0)
            row.text:SetText(r.kind == "all" and L.ALL_OF or L.ONE_OF)
            row.text:SetTextColor(1, 0.82, 0)
        elseif r.kind == "level" then
            local done = ns.RowDone(r)
            local st = done and "done" or "locked"
            row.status:SetTexture(STATUS_ICON[st]); row.status:Show()
            row.icon:SetTexture(ICON_LEVEL); row.icon:Show()
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
            row.text:SetText(L.REACH_LEVEL:format(r.level))
            row.text:SetTextColor(unpack(STATUS_COLOR[st]))
            row.right:SetText(L.LEVEL:format(ns.CharLevel()))
        else
            local qq = Q[r.id] or {}
            local st = ns.Status(r.id)
            row.status:SetTexture(STATUS_ICON[st]); row.status:Show()
            row.icon:SetTexture(qq.elite and ICON_ELITE or ICON_QUEST); row.icon:Show()
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
            local name = ns.QuestName(r.id)
            if r.kind == "ref" then name = name .. "  |cff888888" .. L.ALREADY_LISTED .. "|r" end
            if qq.elite then name = name .. "  |cffff8000[" .. L.ELITE .. "]|r" end
            row.text:SetText(name)
            row.text:SetTextColor(unpack(STATUS_COLOR[st]))
            local info = {}
            if qq.zone and qq.zone ~= q.zone then info[#info + 1] = ns.ZoneName(qq.zone) end
            if qq.level then info[#info + 1] = ("[%d]"):format(qq.level) end
            row.right:SetText(table.concat(info, "  "))
        end
        row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
        row:Show()
    end
    treeContent:SetSize(width, math.max(#rows * TREE_ROW_H, 1))
end

---------------------------------------------------------------------------
-- Sélecteur de personnage (liste déroulante maison, compatible tous clients)
---------------------------------------------------------------------------
local charMenu
local function UpdateCharButton()
    local c = ns.ViewChar()
    frame.charBtn:SetText(L.VIEWING .. " : " .. (c and ClassColorName(c) or "?"))
end

local function ToggleCharMenu()
    if charMenu and charMenu:IsShown() then charMenu:Hide() return end
    if not charMenu then
        charMenu = CreateFrame("Frame", nil, frame, BACKDROP_TEMPLATE)
        charMenu:SetFrameStrata("DIALOG")
        if charMenu.SetBackdrop then charMenu:SetBackdrop(PANEL_BACKDROP) end
        if charMenu.SetBackdropColor then charMenu:SetBackdropColor(0, 0, 0, 0.95) end
        charMenu.buttons = {}
    end
    local keys = {}
    for k in pairs(ns.db.chars) do keys[#keys + 1] = k end
    table.sort(keys)
    for i, k in ipairs(keys) do
        local b = charMenu.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, charMenu)
            b:SetSize(200, 18)
            b:SetPoint("TOPLEFT", 8, -8 - (i - 1) * 18)
            b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.text:SetPoint("LEFT", 4, 0)
            b:SetScript("OnClick", function(self)
                ns.viewKey = self.key
                charMenu:Hide()
                ns.Refresh()
            end)
            charMenu.buttons[i] = b
        end
        local c = ns.db.chars[k]
        b.key = k
        b.text:SetText(("%s - %s  (%d, %s)"):format(ClassColorName(c), RealmRuleset(c.realm), c.level or 0, FactionLabel(c.faction)))
        b:Show()
    end
    for i = #keys + 1, #charMenu.buttons do charMenu.buttons[i]:Hide() end
    charMenu:SetSize(216, 16 + #keys * 18)
    charMenu:ClearAllPoints()
    charMenu:SetPoint("TOPRIGHT", frame.charBtn, "BOTTOMRIGHT", 0, -2)
    charMenu:Show()
end

---------------------------------------------------------------------------
-- Construction de la fenêtre
---------------------------------------------------------------------------
local function CreateCheck(name, parent, label, getter, setter)
    local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    cb.label:SetText(label)
    cb:SetScript("OnShow", function(self) self:SetChecked(getter()) end)
    cb:SetScript("OnClick", function(self) setter(self:GetChecked() and true or false); ns.Refresh() end)
    return cb
end

local function CreatePanel(parent)
    local p = CreateFrame("Frame", nil, parent, BACKDROP_TEMPLATE)
    if p.SetBackdrop then
        p:SetBackdrop(PANEL_BACKDROP)
        p:SetBackdropColor(0, 0, 0, 0.6)
        p:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    end
    return p
end

-- Molette deux fois plus lente que le défaut du template (hauteur/2 par cran).
local function SlowWheel(sf)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local v = self:GetVerticalScroll() - delta * self:GetHeight() / 4
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), v)))
    end)
end

local function CreateMainFrame()
    frame = CreateFrame("Frame", "ForeverElitesFrame", UIParent, BACKDROP_TEMPLATE)
    frame:SetSize(W, H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        ns.db.point = { point, rel, x, y }
    end)
    if frame.SetBackdrop then frame:SetBackdrop(MAIN_BACKDROP) end
    frame:Hide()
    tinsert(UISpecialFrames, "ForeverElitesFrame")

    local hdr = frame:CreateTexture(nil, "ARTWORK")
    hdr:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    hdr:SetSize(360, 64)
    hdr:SetPoint("TOP", 0, 12)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", hdr, "TOP", 0, -14)
    title:SetText(L.TITLE)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    -- Recherche
    local search = CreateFrame("EditBox", "ForeverElitesSearch", frame, "InputBoxTemplate")
    search:SetSize(LEFT_W - 12, 20)
    search:SetPoint("TOPLEFT", 28, -34)
    search:SetAutoFocus(false)
    search.ph = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    search.ph:SetPoint("LEFT", 2, 0)
    search.ph:SetText(L.SEARCH)
    search:SetScript("OnTextChanged", function(self)
        searchText = (self:GetText() or ""):lower()
        self.ph:SetShown(searchText == "")
        ns.Refresh()
    end)
    search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- Personnage
    local charBtn = CreateFrame("Button", "ForeverElitesCharButton", frame, "UIPanelButtonTemplate")
    charBtn:SetSize(240, 22)
    charBtn:SetPoint("TOPRIGHT", -36, -32)
    charBtn:SetScript("OnClick", ToggleCharMenu)
    frame.charBtn = charBtn

    -- Panneau gauche
    local left = CreatePanel(frame)
    left:SetPoint("TOPLEFT", 18, -62)
    left:SetPoint("BOTTOMLEFT", 18, 46)
    left:SetWidth(LEFT_W)
    listScroll = CreateFrame("ScrollFrame", "ForeverElitesListScroll", left, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 6, -6)
    listScroll:SetPoint("BOTTOMRIGHT", -28, 6)
    listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetSize(LEFT_W - 34, 1)
    listScroll:SetScrollChild(listContent)
    SlowWheel(listScroll)

    frame.empty = left:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    frame.empty:SetPoint("TOPLEFT", 12, -12)
    frame.empty:SetPoint("RIGHT", -12, 0)
    frame.empty:SetJustifyH("LEFT")
    frame.empty:SetText(L.NO_DATA)

    -- Panneau droit
    local right = CreatePanel(frame)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
    right:SetPoint("BOTTOMRIGHT", -18, 46)

    header.icon = right:CreateTexture(nil, "ARTWORK")
    header.icon:SetSize(40, 40)
    header.icon:SetPoint("TOPLEFT", 10, -10)
    header.title = right:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header.title:SetPoint("TOPLEFT", header.icon, "TOPRIGHT", 10, -2)
    header.title:SetPoint("RIGHT", -130, 0)
    header.title:SetJustifyH("LEFT")
    header.sub = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    header.sub:SetPoint("TOPLEFT", header.title, "BOTTOMLEFT", 0, -4)
    header.sub:SetJustifyH("LEFT")
    header.bar = CreateBar(right, 14)
    header.bar:SetPoint("TOPLEFT", 12, -58)
    header.bar:SetPoint("TOPRIGHT", -12, -58)

    local sep = right:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", 8, -80)
    sep:SetPoint("TOPRIGHT", -8, -80)
    SetColor(sep, 0.6, 0.6, 0.6, 0.5)

    treeScroll = CreateFrame("ScrollFrame", "ForeverElitesTreeScroll", right, "UIPanelScrollFrameTemplate")
    treeScroll:SetPoint("TOPLEFT", 6, -86)
    treeScroll:SetPoint("BOTTOMRIGHT", -28, 6)
    treeContent = CreateFrame("Frame", nil, treeScroll)
    treeContent:SetSize(W - LEFT_W - 90, 1)
    treeScroll:SetScrollChild(treeContent)
    SlowWheel(treeScroll)

    -- Vue arbre (graphe façon Attune), même emplacement que la liste d'étapes
    frame.graph = ns.TreeView.Create(right)
    frame.graph:SetPoint("TOPLEFT", 4, -84)
    frame.graph:SetPoint("BOTTOMRIGHT", -4, 4)
    frame.graph:Hide()

    -- Page d'accueil : paragraphes de texte, à l'emplacement de la liste d'étapes
    frame.home = right:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.home:SetPoint("TOPLEFT", 16, -96)
    frame.home:SetPoint("RIGHT", -16, 0)
    frame.home:SetJustifyH("LEFT")
    frame.home:SetJustifyV("TOP")
    frame.home:SetSpacing(3)
    frame.home:Hide()

    local viewBtn = CreateFrame("Button", "ForeverElitesViewToggle", right, "UIPanelButtonTemplate")
    viewBtn:SetSize(110, 22)
    viewBtn:SetPoint("TOPRIGHT", -10, -12)
    viewBtn:SetScript("OnClick", function()
        ns.db.viewMode = (ns.db.viewMode == "tree") and "list" or "tree"
        ns.Refresh()
    end)
    frame.viewBtn = viewBtn

    -- Bas de fenêtre
    local expand = CreateFrame("Button", "ForeverElitesExpand", frame, "UIPanelButtonTemplate")
    expand:SetSize(110, 22)
    expand:SetPoint("BOTTOMLEFT", 22, 18)
    expand:SetText(L.EXPAND_ALL)
    expand:SetScript("OnClick", function() wipe(ns.db.collapsed); ns.Refresh() end)

    local collapse = CreateFrame("Button", "ForeverElitesCollapse", frame, "UIPanelButtonTemplate")
    collapse:SetSize(110, 22)
    collapse:SetPoint("LEFT", expand, "RIGHT", 6, 0)
    collapse:SetText(L.COLLAPSE_ALL)
    collapse:SetScript("OnClick", function()
        local Q = ns.GetQuests()
        for id, q in pairs(Q) do
            if q.elite then ns.db.collapsed[(q.continent or "?") .. "/" .. (q.zone or "?")] = true end
        end
        ns.Refresh()
    end)

    local cb1 = CreateCheck("ForeverElitesHideDone", frame, L.HIDE_DONE,
        function() return ns.db.hideDone end, function(v) ns.db.hideDone = v end)
    cb1:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 2, -30)
    local cb2 = CreateCheck("ForeverElitesAllFactions", frame, L.ALL_FACTIONS,
        function() return ns.db.allFactions end, function(v) ns.db.allFactions = v end)
    cb2:SetPoint("LEFT", cb1.label, "RIGHT", 16, -1)

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMRIGHT", -24, 24)
    hint:SetText(L.CLICK_HINT)

    frame:SetScript("OnShow", function() ns.Refresh() end)
    frame:SetScript("OnHide", function() if charMenu then charMenu:Hide() end end)
end

function ns.ResetPosition()
    if not frame then return end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER")
end

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    UpdateCharButton()
    RefreshList()
    RefreshTree()
end

function ns.Toggle(forceShow)
    if not frame then
        CreateMainFrame()
        local p = ns.db.point
        if p then
            frame:ClearAllPoints()
            frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
        end
    end
    if forceShow then
        if frame:IsShown() then ns.Refresh() else frame:Show() end
    else
        frame:SetShown(not frame:IsShown())
    end
end

---------------------------------------------------------------------------
-- Bouton de minicarte (sans bibliothèque externe)
---------------------------------------------------------------------------
local mmButton
local function PlaceMinimapButton()
    local a = math.rad(ns.db.minimap.angle or 200)
    local r = (Minimap:GetWidth() / 2) + 10
    mmButton:ClearAllPoints()
    mmButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

function ns.UpdateMinimapButton()
    if not mmButton then return end
    if ns.db.minimap.hide then mmButton:Hide() else mmButton:Show(); PlaceMinimapButton() end
end

function ns.CreateMinimapButton()
    if mmButton then return end
    local b = CreateFrame("Button", "ForeverElitesMinimapButton", Minimap)
    mmButton = b
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetTexture(ICON_ELITE)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon:SetPoint("TOPLEFT", 7, -6)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function() ns.Toggle() end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            ns.db.minimap.angle = math.deg(math.atan2(py / s - my, px / s - mx))
            PlaceMinimapButton()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(L.TITLE, 1, 0.5, 0)
        GameTooltip:AddLine(L.MINIMAP_TIP, 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ns.UpdateMinimapButton()
end
