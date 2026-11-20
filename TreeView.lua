local _, ns = ...
local L = ns.L

-- Vue « arbre » façon Attune : chaque quête est une boîte, rangée par étage
-- (profondeur dans la chaîne de prérequis), reliée à ses suites par des traits.

local NODE_W, NODE_H = 180, 44
local HGAP, VGAP     = 14, 36
local LINE           = 2
local ZOOM_MIN, ZOOM_MAX = 0.4, 1.2
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

local NODE_BACKDROP = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local STYLE = {
    done      = { bg = { 0.05, 0.22, 0.05 }, border = { 0.20, 1.00, 0.20 }, text = { 0.6, 1, 0.6 } },
    log       = { bg = { 0.25, 0.20, 0.00 }, border = { 1.00, 0.82, 0.00 }, text = { 1, 0.9, 0.4 } },
    available = { bg = { 0.12, 0.12, 0.12 }, border = { 0.90, 0.90, 0.90 }, text = { 1, 1, 1 } },
    locked    = { bg = { 0.06, 0.06, 0.06 }, border = { 0.40, 0.40, 0.40 }, text = { 0.6, 0.6, 0.6 } },
}
local ICON_QUEST = "Interface\\Icons\\INV_Misc_Note_01"
local ICON_ELITE = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"
local ICON_LEVEL = "Interface\\Icons\\Spell_ChargePositive"
local STATUS_ICON = {
    done      = "Interface\\RaidFrame\\ReadyCheck-Ready",
    log       = "Interface\\RaidFrame\\ReadyCheck-Waiting",
    available = "Interface\\GossipFrame\\AvailableQuestIcon",
    locked    = "Interface\\RaidFrame\\ReadyCheck-NotReady",
}

local TV = {}
ns.TreeView = TV

local viewport, root
local nodes, lines, labels = {}, {}, {}
local zoom, panX, panY = 1, 0, 0
local currentId

local function SetColor(tex, r, g, b, a)
    if tex.SetColorTexture then tex:SetColorTexture(r, g, b, a or 1) else tex:SetTexture(r, g, b, a or 1) end
end

---------------------------------------------------------------------------
-- Calcul du graphe
---------------------------------------------------------------------------
local function Prereqs(id)
    local q = ns.GetQuests()[id]
    local list = {}
    if q then
        for _, p in ipairs(q.pre or {}) do list[#list + 1] = { id = p } end
        local any = ns.AnyPrereqs(q) or {}
        for _, p in ipairs(any) do list[#list + 1] = { id = p, any = #any > 1 } end
    end
    return list
end

-- Renvoie : liste ordonnée des nœuds, étage de chaque nœud, arêtes {from, to, any}
local function BuildGraph(eliteId)
    local order, layer, edges, visiting = {}, {}, {}, {}
    local function Visit(id)
        if layer[id] then return layer[id] end
        if visiting[id] then return 0 end -- protection contre une boucle dans les données
        visiting[id] = true
        local depth = 0
        for _, p in ipairs(Prereqs(id)) do
            local d = Visit(p.id) + 1
            if d > depth then depth = d end
            edges[#edges + 1] = { from = p.id, to = id, any = p.any }
        end
        visiting[id] = nil
        layer[id] = depth
        order[#order + 1] = id
        return depth
    end
    Visit(eliteId)

    local q = ns.GetQuests()[eliteId]
    local levelNode = q and q.minLevel and "level"
    if levelNode then
        for _, id in ipairs(order) do layer[id] = layer[id] + 1 end
        for _, id in ipairs(order) do
            if layer[id] == 1 then edges[#edges + 1] = { from = "level", to = id } end
        end
        layer.level = 0
        table.insert(order, 1, "level")
    end
    return order, layer, edges, q and q.minLevel
end

-- Positionne les nœuds : un rang par étage, ordonné par barycentre des suites
local function Layout(order, layer, edges)
    local rows, maxLayer = {}, 0
    local dfsIndex = {}
    for i, id in ipairs(order) do
        dfsIndex[id] = i
        local l = layer[id]
        rows[l] = rows[l] or {}
        table.insert(rows[l], id)
        if l > maxLayer then maxLayer = l end
    end
    local children = {}
    for _, e in ipairs(edges) do
        children[e.from] = children[e.from] or {}
        table.insert(children[e.from], e.to)
    end
    local pos = {}
    local function PlaceRow(l)
        local row = rows[l] or {}
        local width = #row * NODE_W + math.max(0, #row - 1) * HGAP
        for i, id in ipairs(row) do
            pos[id] = { x = -width / 2 + (i - 1) * (NODE_W + HGAP) + NODE_W / 2, y = l * (NODE_H + VGAP) }
        end
    end
    PlaceRow(maxLayer)
    for l = maxLayer - 1, 0, -1 do
        local row = rows[l] or {}
        local key = {}
        for _, id in ipairs(row) do
            local sum, n = 0, 0
            for _, c in ipairs(children[id] or {}) do
                if pos[c] then sum = sum + pos[c].x; n = n + 1 end
            end
            key[id] = n > 0 and sum / n or 0
        end
        table.sort(row, function(a, b)
            if key[a] ~= key[b] then return key[a] < key[b] end
            return dfsIndex[a] < dfsIndex[b]
        end)
        PlaceRow(l)
    end
    return pos, rows, maxLayer
end

---------------------------------------------------------------------------
-- Objets graphiques (réutilisés)
---------------------------------------------------------------------------
local function GetLine(i)
    local t = lines[i]
    if not t then
        t = root:CreateTexture(nil, "BORDER")
        lines[i] = t
    end
    t:ClearAllPoints()
    t:Show()
    return t
end

local function GetLabel(i)
    local f = labels[i]
    if not f then
        f = root:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        labels[i] = f
    end
    f:Show()
    return f
end

local function NodeTooltip(self)
    if self.id == "level" then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L.REACH_LEVEL:format(self.level), 1, 1, 1)
        GameTooltip:AddLine(L.LEVEL:format(ns.CharLevel()), 0.7, 0.7, 0.7)
        GameTooltip:Show()
    elseif self.id then
        ns.QuestTooltip(self, self.id)
    end
end

local function GetNode(i)
    local n = nodes[i]
    if n then return n end
    n = CreateFrame("Button", nil, root, BACKDROP_TEMPLATE)
    n:SetSize(NODE_W, NODE_H)
    n:SetFrameLevel(root:GetFrameLevel() + 5)
    if n.SetBackdrop then n:SetBackdrop(NODE_BACKDROP) end
    n:RegisterForClicks("LeftButtonUp")

    n.icon = n:CreateTexture(nil, "ARTWORK")
    n.icon:SetSize(30, 30)
    n.icon:SetPoint("LEFT", 7, 0)
    n.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    n.status = n:CreateTexture(nil, "OVERLAY")
    n.status:SetSize(14, 14)
    n.status:SetPoint("BOTTOMRIGHT", n.icon, "BOTTOMRIGHT", 4, -4)

    n.name = n:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    n.name:SetPoint("TOPLEFT", n.icon, "TOPRIGHT", 6, 1)
    n.name:SetPoint("RIGHT", -6, 0)
    n.name:SetJustifyH("LEFT")
    n.name:SetJustifyV("TOP")
    n.name:SetHeight(22)
    if n.name.SetMaxLines then n.name:SetMaxLines(2) end
    n.sub = n:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    n.sub:SetPoint("BOTTOMLEFT", n.icon, "BOTTOMRIGHT", 6, -1)
    n.sub:SetPoint("RIGHT", -6, 0)
    n.sub:SetJustifyH("LEFT")

    n:SetScript("OnEnter", NodeTooltip)
    n:SetScript("OnLeave", function() GameTooltip:Hide() end)
    n:SetScript("OnClick", function(self, mouse)
        if self.id == "level" or not self.id then return end
        if ns.QuestClick(self.id, mouse) then return end
        local q = ns.GetQuests()[self.id]
        if q and q.elite and self.id ~= ns.selected then
            ns.selected = self.id
            ns.Refresh()
        end
    end)
    nodes[i] = n
    return n
end

local function StyleNode(n, st, highlight)
    local s = STYLE[st]
    if n.SetBackdropColor then
        n:SetBackdropColor(s.bg[1], s.bg[2], s.bg[3], 0.95)
        if highlight then
            n:SetBackdropBorderColor(1, 0.5, 0, 1)
        else
            n:SetBackdropBorderColor(s.border[1], s.border[2], s.border[3], 1)
        end
    end
    n.name:SetTextColor(s.text[1], s.text[2], s.text[3])
    n.status:SetTexture(STATUS_ICON[st])
end

-- Trait coudé : du bas du prérequis jusqu'au haut de la suite
local function DrawEdge(idx, a, b, r, g, bl)
    local x1, y1 = a.x, a.y + NODE_H
    local x2, y2 = b.x, b.y
    local midY = y2 - VGAP / 2
    local t = GetLine(idx)
    SetColor(t, r, g, bl, 0.9)
    t:SetPoint("TOP", root, "TOP", x1, -y1)
    t:SetSize(LINE, math.max(1, midY - y1))
    idx = idx + 1
    if math.abs(x2 - x1) > 0.5 then
        t = GetLine(idx)
        SetColor(t, r, g, bl, 0.9)
        t:SetPoint("TOPLEFT", root, "TOP", math.min(x1, x2) - LINE / 2, -(midY - LINE / 2))
        t:SetSize(math.abs(x2 - x1) + LINE, LINE)
        idx = idx + 1
    end
    t = GetLine(idx)
    SetColor(t, r, g, bl, 0.9)
    t:SetPoint("TOP", root, "TOP", x2, -midY)
    t:SetSize(LINE, math.max(1, y2 - midY))
    return idx + 1
end

---------------------------------------------------------------------------
-- Déplacement et zoom
---------------------------------------------------------------------------
local function ApplyTransform()
    root:SetScale(zoom)
    root:ClearAllPoints()
    root:SetPoint("TOP", viewport, "TOP", panX / zoom, (-12 + panY) / zoom)
end

function TV.ResetView()
    zoom, panX, panY = 1, 0, 0
    if root then ApplyTransform() end
end

function TV.Create(parent)
    viewport = CreateFrame("Frame", nil, parent)
    if viewport.SetClipsChildren then viewport:SetClipsChildren(true) end
    viewport:EnableMouse(true)
    viewport:EnableMouseWheel(true)
    root = CreateFrame("Frame", nil, viewport)
    root:SetSize(1, 1)

    viewport:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local s = self:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        self.dragX, self.dragY = cx / s, cy / s
        self:SetScript("OnUpdate", function(f)
            local nx, ny = GetCursorPosition()
            nx, ny = nx / s, ny / s
            panX = panX + (nx - f.dragX)
            panY = panY + (ny - f.dragY)
            f.dragX, f.dragY = nx, ny
            ApplyTransform()
        end)
    end)
    viewport:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
    viewport:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
    viewport:SetScript("OnMouseWheel", function(_, delta)
        if IsControlKeyDown() then
            zoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, zoom + delta * 0.1))
        else
            panY = panY - delta * 20
        end
        ApplyTransform()
    end)

    local hint = viewport:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 6, 4)
    hint:SetText(L.TREE_HINT)

    ApplyTransform()
    return viewport
end

function TV.Refresh(eliteId)
    if not viewport then return end
    if eliteId ~= currentId then
        currentId = eliteId
        TV.ResetView()
    end
    for _, n in ipairs(nodes) do n:Hide() end
    for _, t in ipairs(lines) do t:Hide() end
    for _, f in ipairs(labels) do f:Hide() end
    if not eliteId or not ns.GetQuests()[eliteId] then return end

    local order, layer, edges, minLevel = BuildGraph(eliteId)
    local pos, rows, maxLayer = Layout(order, layer, edges)

    -- Traits (sous les boîtes)
    local li = 1
    for _, e in ipairs(edges) do
        local a, b = pos[e.from], pos[e.to]
        if a and b then
            local fromDone = (e.from == "level") and ns.CharLevel() >= minLevel or (e.from ~= "level" and ns.IsDone(e.from))
            local r, g, bl = 0.5, 0.5, 0.5
            if fromDone then r, g, bl = 0.2, 0.9, 0.2 elseif e.any then r, g, bl = 1, 0.6, 0.1 end
            li = DrawEdge(li, a, b, r, g, bl)
        end
    end

    -- Boîtes
    for i, id in ipairs(order) do
        local n = GetNode(i)
        local p = pos[id]
        n:ClearAllPoints()
        n:SetPoint("TOP", root, "TOP", p.x, -p.y)
        n.id = id
        if id == "level" then
            n.level = minLevel
            local st = ns.CharLevel() >= minLevel and "done" or "locked"
            n.icon:SetTexture(ICON_LEVEL)
            n.name:SetText(L.REACH_LEVEL:format(minLevel))
            n.sub:SetText(L.LEVEL:format(ns.CharLevel()))
            StyleNode(n, st)
        else
            local q = ns.GetQuests()[id] or {}
            n.icon:SetTexture(q.elite and ICON_ELITE or ICON_QUEST)
            n.name:SetText(ns.QuestName(id))
            local sub = q.level and ("[" .. q.level .. "]") or ""
            if q.elite then sub = sub .. " |cffff8000" .. L.ELITE .. "|r" end
            if q.zone and q.zone ~= (ns.GetQuests()[eliteId].zone) then sub = sub .. " " .. ns.ZoneName(q.zone) end
            n.sub:SetText(sub)
            StyleNode(n, ns.Status(id), id == eliteId)
        end
        n:Show()
    end

    -- « OU » entre deux alternatives voisines d'un même groupe
    local anyOf = {}
    for _, e in ipairs(edges) do
        if e.any then anyOf[e.from] = anyOf[e.from] or {}; anyOf[e.from][e.to] = true end
    end
    local lab = 1
    for l = 0, maxLayer do
        local row = rows[l] or {}
        for i = 1, #row - 1 do
            local a, b = row[i], row[i + 1]
            if anyOf[a] and anyOf[b] then
                for child in pairs(anyOf[a]) do
                    if anyOf[b][child] then
                        local f = GetLabel(lab); lab = lab + 1
                        f:ClearAllPoints()
                        f:SetPoint("CENTER", root, "TOP", (pos[a].x + pos[b].x) / 2, -(pos[a].y + NODE_H / 2))
                        f:SetText(L.OR)
                        f:SetTextColor(1, 0.6, 0.1)
                        break
                    end
                end
            end
        end
    end
end

-- exposés pour les tests hors jeu
TV._BuildGraph, TV._Layout = BuildGraph, Layout
