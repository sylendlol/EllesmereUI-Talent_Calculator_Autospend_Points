if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUITalentCalc_Page.lua
--  Dworak > Talent Calculator: the page. Pick a class, click talents in the
--  order you want to learn them (left-click adds a rank, right-click takes
--  one off, shift-right-click clears the talent). Every pick shows the level
--  it is learned at; the Learning Order list under the tree shows the whole
--  build. Colors follow the UI Accent Color (Global Settings) live.
-------------------------------------------------------------------------------
local _, ns = ...
local TC = ns.TC
local DW = EllesmereUIDworak
if not (TC and DW) then return end

local CONTENT_PAD = EllesmereUI.CONTENT_PAD or 45
local BTN = 38            -- talent button size at full scale
local GAP_X, GAP_Y = 26, 22
local TREE_GAP = 60       -- between trees when the class has several
local TREE_PAD = 18
local SUMMARY_H = 86
local UNSPENT_FONT = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway Bold.ttf"
local ORDER_COLS, ORDER_ROW_H = 3, 20

local state = { class = nil, T = nil, live = nil, st = nil }
local legacyFS   -- the Legacy Talent Points value on the page

-- Progress Legacy > Adventure: points in the talent passive (0..5), from the
-- level your first talent point comes at (10 - points).
local LEGACY_MAX = 5
local function UpdateLegacy()
    if not legacyFS then return end
    local first = TC.FirstLevel()
    local pts = math.max(0, math.min(LEGACY_MAX, 10 - first))
    local hex = TC.AccentHex()
    legacyFS:SetText(string.format("%s%d|r / %d   |cff888888first talent point at level|r %s%d|r   |cff888888max|r %s%d|r |cff888888points|r",
        hex, pts, LEGACY_MAX, hex, first, hex, TC.MaxPoints()))
end
local canvas
local Repaint

local function PP() return EllesmereUI.PanelPP end

local function ViewClass()
    local c = TC.CDB().viewClass
    if not (c and TC.ClassInfo(c)) then c = TC.PlayerClass() end
    return c
end

local function IsOwnClass() return state.class == TC.PlayerClass() end

local function LoadClass(file)
    state.class = file
    state.T, state.live = TC.GetTree(file)
    if not IsOwnClass() then state.live = nil end
end

-------------------------------------------------------------------------------
--  Canvas
-------------------------------------------------------------------------------
local function Dim() local d = EllesmereUI.TEXT_DIM or { r = 0.6, g = 0.6, b = 0.6 }; return d.r, d.g, d.b end

local function EnsureCanvas()
    if canvas then return canvas end
    local EUI = EllesmereUI
    canvas = CreateFrame("Frame", nil, UIParent)
    -- Big line on top: your unspent talent points (Expressway Bold, number green).
    canvas.unspent = canvas:CreateFontString(nil, "OVERLAY")
    if not canvas.unspent:SetFont(UNSPENT_FONT, 22, "") then
        canvas.unspent:SetFont(EUI.EXPRESSWAY, 22, "")
    end
    canvas.unspent:SetTextColor(1, 1, 1, 1)
    canvas.unspent:SetShadowOffset(1, -1)
    canvas.unspent:SetShadowColor(0, 0, 0, 1)
    canvas.unspent:SetPoint("TOPLEFT", canvas, "TOPLEFT", 4, -4)
    canvas.unspent:SetJustifyH("LEFT")

    canvas.summary = EUI.MakeFont(canvas, 14, nil, 1, 1, 1, 1)
    canvas.summary:SetPoint("TOPLEFT", canvas, "TOPLEFT", 4, -40)
    canvas.summary:SetPoint("RIGHT", canvas, "RIGHT", -4, 0)
    canvas.summary:SetWordWrap(false)
    canvas.summary:SetJustifyH("LEFT")
    canvas.hint = EUI.MakeFont(canvas, 11, nil, Dim())
    canvas.hint:SetPoint("TOPLEFT", canvas, "TOPLEFT", 4, -62)
    canvas.hint:SetJustifyH("LEFT")
    canvas.hint:SetText("Left-click: add a rank   Right-click: remove one   Shift-right-click: remove all")

    local tree = CreateFrame("Frame", nil, canvas)
    tree:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -SUMMARY_H)
    tree:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", 0, -SUMMARY_H)
    EUI.SolidTex(tree, "BACKGROUND", 0, 0, 0, 0.25):SetAllPoints()
    EUI.MakeBorder(tree, 1, 1, 1, 0.08, PP())
    tree.msg = EUI.MakeFont(tree, 13, nil, Dim())
    tree.msg:SetPoint("CENTER")
    tree.msg:SetWidth(600)
    canvas.tree = tree

    canvas.orderTitle = EUI.MakeFont(canvas, 13, nil, 1, 1, 1, 1)
    canvas.buttons, canvas.lines, canvas.labels, canvas.rows, canvas.dividers = {}, {}, {}, {}, {}
    return canvas
end

local function ShowTip(b)
    local n, st, T = b.node, state.st, state.T
    if not (n and st and T) then return end
    local ar, ag, ab = TC.Accent()
    local chosen = st.entry[n.id]
    local e = TC.EntryOf(n, chosen)
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    if e.spell and not pcall(GameTooltip.SetSpellByID, GameTooltip, e.spell) then
        GameTooltip:SetText(e.name, 1, 1, 1)
    elseif not e.spell then
        GameTooltip:SetText(e.name, 1, 1, 1)
    end
    if n.choice then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Choice of:", ar, ag, ab)
        for _, x in ipairs(n.entries) do
            local on = chosen == x.id
            GameTooltip:AddLine("  " .. x.name, on and ar or 1, on and ag or 1, on and ab or 1)
        end
    end
    GameTooltip:AddLine(" ")
    if n.free then
        GameTooltip:AddLine("You get this talent for free.", ar, ag, ab)
    else
        local r = st.ranks[n.id] or 0
        GameTooltip:AddLine(string.format("Rank %d/%d in the build", r, TC.NodeMax(n, chosen)), ar, ag, ab)
        local lv = {}
        for i, s in ipairs(st.steps) do
            if s.n == n.id then lv[#lv + 1] = tostring(st.levels[i]) end
        end
        if #lv > 0 then
            GameTooltip:AddLine("Learned at level " .. table.concat(lv, ", "), 1, 1, 1)
        end
        if state.live and state.live[n.id] then
            GameTooltip:AddLine(string.format("You have %d/%d now", state.live[n.id].rank or 0, TC.NodeMax(n, chosen)), Dim())
        end
        if r < TC.NodeMax(n, chosen) then
            local ok, why = TC.CanAdd(T, st, n.id, chosen)
            if not ok and why then GameTooltip:AddLine(why, 1, 0.35, 0.35, true) end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click: add a rank. Right-click: remove one. Shift-right-click: remove all.",
            0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

local function Changed(b)
    Repaint()
    if b and GameTooltip:IsOwned(b) then ShowTip(b) end
end

local function ChoiceMenu(b, n)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(b, function(_, root)
            root:CreateTitle("Choose a talent")
            for _, e in ipairs(n.entries) do
                root:CreateButton(string.format("|T%s:16:16:0:0|t %s", tostring(e.icon), e.name), function()
                    TC.AddRank(state.class, state.T, n.id, e.id)
                    Changed(b)
                end)
            end
        end)
    else
        -- No menu on this client: click picks the first, shift-click the second.
        local e = (IsShiftKeyDown() and n.entries[2]) or n.entries[1]
        TC.AddRank(state.class, state.T, n.id, e.id)
        Changed(b)
    end
end

local function OnClick(b, button)
    local n = b.node
    if not (n and state.T) then return end
    if button == "RightButton" then
        TC.RemoveRank(state.class, state.T, n.id, IsShiftKeyDown())
        Changed(b)
        return
    end
    local chosen = state.st and state.st.entry[n.id]
    if n.choice and not chosen then
        ChoiceMenu(b, n)
        return
    end
    TC.AddRank(state.class, state.T, n.id, chosen)
    Changed(b)
end

local function GetButton(i)
    local b = canvas.buttons[i]
    if b then return b end
    local EUI = EllesmereUI
    b = CreateFrame("Button", nil, canvas.tree)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    EUI.SolidTex(b, "BACKGROUND", 0, 0, 0, 0.7):SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.brd = EUI.MakeBorder(b, 1, 1, 1, 0.2, PP())
    local top = CreateFrame("Frame", nil, b)
    top:SetAllPoints()
    top:SetFrameLevel(b:GetFrameLevel() + 4)
    b.rankBg = top:CreateTexture(nil, "BACKGROUND")
    b.rankBg:SetColorTexture(0, 0, 0, 0.85)
    b.rank = EUI.MakeFont(top, 11, "OUTLINE", 1, 1, 1, 1)
    b.rank:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 4, -4)
    b.rankBg:SetPoint("TOPLEFT", b.rank, "TOPLEFT", -2, 1)
    b.rankBg:SetPoint("BOTTOMRIGHT", b.rank, "BOTTOMRIGHT", 2, -1)
    b.choice = EUI.MakeFont(top, 10, "OUTLINE", 1, 1, 1, 0.9)
    b.choice:SetPoint("TOPLEFT", b, "TOPLEFT", -3, 3)
    b:SetScript("OnClick", OnClick)
    b:SetScript("OnEnter", ShowTip)
    b:SetScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
    canvas.buttons[i] = b
    return b
end

local function GetLine(i)
    local l = canvas.lines[i]
    if l then return l end
    l = canvas.tree:CreateLine(nil, "BORDER")
    l:SetThickness(2)
    canvas.lines[i] = l
    return l
end

local function GetLabel(pool, i, parent, size)
    local f = pool[i]
    if f then return f end
    f = EllesmereUI.MakeFont(parent, size, nil, 1, 1, 1, 1)
    f:SetJustifyH("LEFT")
    f:SetWordWrap(false)
    pool[i] = f
    return f
end

-- Grid positions for one axis. Each distinct coordinate gets a slot; the
-- step between neighbours is measured against the usual (median) step, so a
-- far-away node does not squash the rest of the tree: a gap counts as at
-- most 2 slots, a small offset as at least a third of one.
local function Axis(values)
    local u = {}
    table.sort(values)
    for _, v in ipairs(values) do
        if #u == 0 or v - u[#u] > 0.01 then u[#u + 1] = v end
    end
    local map = { [u[1]] = 0 }
    if #u == 1 then return map, 0 end
    local gaps = {}
    for i = 2, #u do gaps[#gaps + 1] = u[i] - u[i - 1] end
    table.sort(gaps)
    local base = gaps[math.ceil(#gaps / 2)]
    local pos = 0
    for i = 2, #u do
        pos = pos + math.max(1 / 3, math.min(2, (u[i] - u[i - 1]) / base))
        map[u[i]] = pos
    end
    return map, pos
end

-- The slot of coordinate v on an axis map (nearest known value).
local function Slot(map, v)
    if map[v] then return map[v] end
    local best, bd
    for k, p in pairs(map) do
        local d = math.abs(k - v)
        if not bd or d < bd then best, bd = p, d end
    end
    return best or 0
end

-- Places everything for state.T into width; returns the canvas height.
local function Layout(width)
    EnsureCanvas()
    canvas:SetWidth(width)
    for _, b in ipairs(canvas.buttons) do b:Hide(); b.node = nil end
    for _, l in ipairs(canvas.lines) do l:Hide() end
    for _, f in ipairs(canvas.labels) do f:Hide() end
    for _, d in ipairs(canvas.dividers) do d:Hide() end
    for _, f in ipairs(canvas.rows) do f:Hide() end
    canvas.lineMap = {}

    local T = state.T
    local treeH
    if not T then
        canvas.tree.msg:SetText("No talent data for " .. TC.ClassColored(state.class) .. " yet.\n\n"
            .. "Log in with a " .. TC.ClassColored(state.class) .. " character once: the calculator saves its tree "
            .. "for every character of your account.")
        canvas.tree.msg:Show()
        treeH = 140
        canvas.tree:SetHeight(treeH)
        canvas.orderTitle:Hide()
        canvas.hint:Hide()
        return SUMMARY_H + treeH + 10
    end
    canvas.tree.msg:Hide()
    canvas.hint:Show()

    -- Group by tree; each tree gets its own grid from its positions.
    local groups = {}
    for _, id in ipairs(T.order) do
        local n = T.nodes[id]
        local key = n.sub or n.tree
        local g = groups[key]
        if not g then g = { nodes = {}, xs = {}, ys = {} }; groups[key] = g end
        g.nodes[#g.nodes + 1] = n
        g.xs[#g.xs + 1] = n.x
        g.ys[#g.ys + 1] = n.y
    end
    local list = {}
    for k = 1, math.max(#T.trees, T.subCount or 0) do if groups[k] then list[#list + 1] = groups[k] end end
    local ng = #list
    for _, g in ipairs(list) do
        g.xmap, g.cols = Axis(g.xs)
        g.ymap, g.rows = Axis(g.ys)
    end

    local cellX, cellY = BTN + GAP_X, BTN + GAP_Y
    local needed = TREE_PAD * 2 + TREE_GAP * (ng - 1)
    for _, g in ipairs(list) do needed = needed + g.cols * cellX + BTN end
    local f = math.min(1, width / needed)
    local btn = math.max(22, math.floor(BTN * f))
    cellX, cellY = cellX * f, cellY * f
    local treeGap = TREE_GAP * f
    local labelH = ng > 1 and 34 or 0
    local names = ng > 1 and TC.TreeNames(state.class, ng) or nil

    local total = treeGap * (ng - 1)
    for _, g in ipairs(list) do
        g.w = g.cols * cellX + btn
        g.h = g.rows * cellY + btn
        total = total + g.w
    end
    local x0 = math.floor((width - total) / 2)
    local maxH = 0
    local bi, li = 0, 0
    local byNode = {}
    for gi, g in ipairs(list) do
        if ng > 1 then
            local lab = GetLabel(canvas.labels, gi, canvas.tree, 14)
            lab:ClearAllPoints()
            lab:SetPoint("TOP", canvas.tree, "TOPLEFT", x0 + g.w / 2, -12)
            lab:SetJustifyH("CENTER")
            lab:SetWidth(0)
            lab:Show()
            g.label = lab
            g.name = names and names[gi] or nil
            -- Vertical divider between this tree and the previous one.
            if gi > 1 then
                local d = canvas.dividers[gi - 1]
                if not d then
                    d = canvas.tree:CreateTexture(nil, "BORDER")
                    d:SetColorTexture(1, 1, 1, 0.10)
                    if d.SetSnapToPixelGrid then d:SetSnapToPixelGrid(false); d:SetTexelSnappingBias(0) end
                    canvas.dividers[gi - 1] = d
                end
                d:ClearAllPoints()
                d:SetWidth(1)
                d:SetPoint("TOP", canvas.tree, "TOPLEFT", math.floor(x0 - treeGap / 2), -8)
                d:SetPoint("BOTTOM", canvas.tree, "BOTTOMLEFT", math.floor(x0 - treeGap / 2), 8)
                d:Show()
            end
        end
        for _, n in ipairs(g.nodes) do
            bi = bi + 1
            local b = GetButton(bi)
            b:SetSize(btn, btn)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", canvas.tree, "TOPLEFT",
                math.floor(x0 + Slot(g.xmap, n.x) * cellX + 0.5),
                -math.floor(TREE_PAD + labelH + Slot(g.ymap, n.y) * cellY + 0.5))
            b.node = n
            b:Show()
            byNode[n.id] = b
        end
        maxH = math.max(maxH, g.h)
        x0 = x0 + g.w + treeGap
    end
    canvas.byNode = byNode
    for _, n in pairs(T.nodes) do
        for _, p in ipairs(n.parents) do
            local a, c = byNode[p.node], byNode[n.id]
            if a and c then
                li = li + 1
                local l = GetLine(li)
                l:SetStartPoint("CENTER", a)
                l:SetEndPoint("CENTER", c)
                l:Show()
                canvas.lineMap[li] = { from = p.node, to = n.id }
            end
        end
    end
    canvas.groups = list
    treeH = math.floor(maxH + TREE_PAD * 2 + labelH + 0.5)
    canvas.tree:SetHeight(treeH)

    -- Learning order: room for every point of the build.
    local y = -(SUMMARY_H + treeH + 18)
    canvas.orderTitle:ClearAllPoints()
    canvas.orderTitle:SetPoint("TOPLEFT", canvas, "TOPLEFT", 4, y)
    canvas.orderTitle:SetText("LEARNING ORDER")
    canvas.orderTitle:Show()
    y = y - 24
    local slots = math.max(TC.MaxPoints(), #TC.Plan(state.class).steps)
    local rows = math.ceil(slots / ORDER_COLS)
    local colW = math.floor(width / ORDER_COLS)
    canvas.orderSlots, canvas.orderRows, canvas.colW = slots, rows, colW
    for i = 1, slots do
        local col = math.floor((i - 1) / rows)
        local row = (i - 1) % rows
        local fs = GetLabel(canvas.rows, i, canvas, 12)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", canvas, "TOPLEFT", 4 + col * colW, y - row * ORDER_ROW_H)
        fs:SetWidth(colW - 12)
    end
    return SUMMARY_H + treeH + 18 + 24 + rows * ORDER_ROW_H + 10
end

Repaint = function()
    UpdateLegacy()
    if canvas and canvas.unspent then
        canvas.unspent:SetText("Unspent talent points: |cff33ff33" .. TC.UnspentPoints() .. "|r")
    end
    if not canvas or not state.T then
        if canvas then
            canvas.summary:SetText(TC.ClassColored(state.class or TC.PlayerClass()))
        end
        return
    end
    local T = state.T
    local ar, ag, ab = TC.Accent()
    local hex = TC.AccentHex()
    local st = TC.Evaluate(T, TC.Plan(state.class).steps)
    state.st = st
    local done, nextIndex
    if state.live then done, nextIndex = TC.Progress(st, state.live) end

    for _, b in ipairs(canvas.buttons) do
        local n = b.node
        if n and b:IsShown() then
            local chosen = st.entry[n.id]
            local e = TC.EntryOf(n, chosen)
            local r, max = st.ranks[n.id] or 0, TC.NodeMax(n, chosen)
            b.icon:SetTexture(e.icon)
            b.choice:SetText(n.choice and not chosen and "?" or "")
            if n.free then
                b.icon:SetDesaturated(false); b.icon:SetAlpha(1)
                b.brd:SetColor(1, 1, 1, 0.35)
                b.rank:SetText(""); b.rankBg:Hide()
            else
                b.rankBg:Show()
                b.rank:SetText(r .. "/" .. max)
                if r >= max then
                    b.icon:SetDesaturated(false); b.icon:SetAlpha(1)
                    b.brd:SetColor(ar, ag, ab, 1)
                    b.rank:SetTextColor(ar, ag, ab, 1)
                elseif r > 0 then
                    b.icon:SetDesaturated(false); b.icon:SetAlpha(1)
                    b.brd:SetColor(ar, ag, ab, 0.6)
                    b.rank:SetTextColor(1, 1, 1, 1)
                elseif TC.CanAdd(T, st, n.id, chosen) then
                    b.icon:SetDesaturated(false); b.icon:SetAlpha(0.85)
                    b.brd:SetColor(1, 1, 1, 0.45)
                    b.rank:SetTextColor(1, 1, 1, 0.8)
                else
                    b.icon:SetDesaturated(true); b.icon:SetAlpha(0.4)
                    b.brd:SetColor(1, 1, 1, 0.12)
                    b.rank:SetTextColor(0.6, 0.6, 0.6, 0.8)
                end
            end
        end
    end
    for i, m in pairs(canvas.lineMap or {}) do
        local l = canvas.lines[i]
        if TC.Maxed(T, st, m.from) and (st.ranks[m.to] or 0) > 0 then
            l:SetColorTexture(ar, ag, ab, 0.9)
        elseif TC.Maxed(T, st, m.from) then
            l:SetColorTexture(ar, ag, ab, 0.45)
        else
            l:SetColorTexture(1, 1, 1, 0.12)
        end
    end

    -- Points per tree (several trees only).
    if canvas.groups and #canvas.groups > 1 then
        for _, g in ipairs(canvas.groups) do
            local c = 0
            for _, n in ipairs(g.nodes) do c = c + (st.ranks[n.id] or 0) end
            if g.label then
                local nm = g.name
                local icon = nm and nm.icon and string.format("|T%s:18:18:0:0:64:64:5:59:5:59|t ", tostring(nm.icon)) or ""
                g.label:SetText(icon .. "|cffffffff" .. (nm and nm.name or "Tree") .. "|r  " .. hex .. c .. "|r")
            end
        end
    end

    -- Summary line.
    local parts = { TC.ClassColored(state.class),
        string.format("Points: %s%d|r / %d", hex, st.total, TC.MaxPoints()) }
    if st.total > 0 then parts[#parts + 1] = "Build complete at level " .. hex .. st.levels[#st.steps] .. "|r" end
    if done then
        local learned = 0
        for i = 1, #st.steps do if done[i] then learned = learned + 1 end end
        parts[#parts + 1] = string.format("Learned: %d/%d", learned, #st.steps)
        if nextIndex then
            local s = st.steps[nextIndex]
            parts[#parts + 1] = "Next: " .. TC.EntryOf(T.nodes[s.n], s.e).name .. " (level " .. st.levels[nextIndex] .. ")"
        end
    end
    canvas.summary:SetText(table.concat(parts, "   |cff666666·|r   "))

    -- Learning order list.
    local count = {}
    for i = 1, canvas.orderSlots or 0 do
        local fs = canvas.rows[i]
        local s = st.steps[i]
        if fs and s then
            fs:SetWidth((canvas.colW or 300) - 12)
            count[s.n] = (count[s.n] or 0) + 1
            local n = T.nodes[s.n]
            local e = TC.EntryOf(n, s.e)
            local col = (done and done[i]) and hex or "|cffffffff"
            fs:SetText(string.format("|cff888888lvl %d|r  |T%s:14:14:0:0:64:64:5:59:5:59|t %s%s|r %d/%d",
                st.levels[i], tostring(e.icon), col, e.name, count[s.n], TC.NodeMax(n, s.e)))
            fs:Show()
        elseif fs then
            fs:Hide()
        end
    end
    if #st.steps == 0 and canvas.rows[1] then
        canvas.rows[1]:SetText("|cff888888Click the talents above in the order you want to learn them.|r")
        canvas.rows[1]:SetWidth(600)
        canvas.rows[1]:Show()
    end
end

-- After the build changed and the number of order rows may not fit any more.
local function RefreshAll()
    if not canvas then return end
    local slots = math.max(TC.MaxPoints(), #TC.Plan(state.class).steps)
    if slots ~= canvas.orderSlots then EllesmereUI:RefreshPage(true) else Repaint() end
end

TC.SetOnLearned(function()
    if canvas and canvas:IsVisible() and IsOwnClass() then
        LoadClass(state.class)
        Repaint()
    end
end)

-------------------------------------------------------------------------------
--  Export popup: the build text, selected and read-only, one Close button.
-------------------------------------------------------------------------------
local exportDimmer, exportPopup, exportEdit
local function ShowExport(str)
    local EUI = EllesmereUI
    if not exportPopup then
        local function Close() exportDimmer:Hide() end
        exportDimmer, exportPopup = EUI.BuildPopupShell("EUITalentCalcExport", {
            w = 390, h = 194, dimAlpha = 0.25,
            onEscape = Close,
            onDimmerDown = function() if not exportPopup:IsMouseOver() then Close() end end,
        })
        exportDimmer:Hide()
        local title = EUI.MakeFont(exportPopup, 16, "", 1, 1, 1)
        title:SetPoint("TOP", exportPopup, "TOP", 0, -20)
        title:SetText("Export Build")
        local msg = EUI.MakeFont(exportPopup, 12, nil, Dim())
        msg:SetPoint("TOP", title, "BOTTOM", 0, -8)
        msg:SetWidth(330)
        msg:SetJustifyH("CENTER")
        msg:SetSpacing(4)
        msg:SetText("Copy the text with Ctrl+C and share it.\nOthers paste it with Import.")

        local input = CreateFrame("Frame", nil, exportPopup)
        input:SetSize(270, 28)
        input:SetPoint("TOP", msg, "BOTTOM", 0, -12)
        input:SetFrameLevel(exportPopup:GetFrameLevel() + 2)
        EUI.SolidTex(input, "BACKGROUND", 0, 0, 0, 0.5):SetAllPoints()
        EUI.MakeBorder(input, 1, 1, 1, 0.2)

        exportEdit = CreateFrame("EditBox", nil, input)
        exportEdit:SetPoint("TOPLEFT", 10, -1)
        exportEdit:SetPoint("BOTTOMRIGHT", -10, 1)
        exportEdit:SetFont(EUI.EXPRESSWAY, 11, "")
        exportEdit:SetTextColor(1, 1, 1, 0.9)
        exportEdit:SetAutoFocus(false)
        exportEdit:SetMaxLetters(0)
        -- Read-only: typing puts the build text back, selected.
        exportEdit:SetScript("OnTextChanged", function(self, userInput)
            if userInput then
                self:SetText(exportPopup._str or "")
                self:HighlightText()
            end
        end)
        exportEdit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        exportEdit:SetScript("OnMouseUp", function(self) self:HighlightText() end)
        exportEdit:SetScript("OnEscapePressed", Close)
        exportEdit:SetScript("OnEnterPressed", Close)

        -- The same button as Cancel in EllesmereUI's input popup (Import).
        local btn = EUI.MakePopupButton(exportPopup, "BOTTOM", exportPopup, "BOTTOM", 0, 18,
            1, 1, 1, 0.7,   1, 1, 1, 0.9,
            1, 1, 1, 0.5,   1, 1, 1, 0.6)
        btn._lbl:SetText("Close")
        btn:SetScript("OnClick", Close)
    end
    -- Same size and place as EllesmereUI's input popup (Import): unscaled,
    -- centred 60 above the middle of the screen.
    exportDimmer:SetScale(1)
    exportPopup:SetScale(1)
    exportPopup:ClearAllPoints()
    exportPopup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    exportPopup._str = str
    exportEdit:SetText(str)
    exportEdit:SetCursorPosition(0)
    exportDimmer:Show()
    exportEdit:SetFocus()
    exportEdit:HighlightText()
end

-------------------------------------------------------------------------------
--  Page
-------------------------------------------------------------------------------
local function ClassDropdown()
    local values, order = {}, {}
    for _, c in ipairs(TC.Classes()) do
        values[c.file] = TC.ClassColored(c.file)
        order[#order + 1] = c.file
    end
    return values, order
end

local function BuildPage(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h
    parent._showRowDivider = true
    local prebuild = EllesmereUI.IsSearchPrebuild()
    local function notOwn() return ViewClass() ~= TC.PlayerClass() end

    _, h = W:SectionHeader(parent, "TALENT CALCULATOR", y);  y = y - h

    local values, order = ClassDropdown()
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Class", values = values, order = order, dropdownWidth = 200,
          tooltip = "The class whose talents are shown below. Each class keeps its own build.",
          getValue = function() return ViewClass() end,
          setValue = function(v)
              TC.CDB().viewClass = v
              EllesmereUI:RefreshPage(true)
          end },
        { type = "toggle", text = "Learn Automatically on Level Up",
          tooltip = "When you level up, the next talents of your class's build are learned with the new "
              .. "points and applied, in the order of the build. Out of combat only; in combat it waits.",
          getValue = function() return TC.CDB().autoLearn end,
          setValue = function(v)
              TC.CDB().autoLearn = v
              if v then TC.LearnPlanned(false) end
          end }
    );  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "labeledButton", text = "Start From My Talents", buttonText = "Copy Current",
          tooltip = "Replaces the build with the talents you have now, top of the tree first. Add the rest after them.",
          disabled = notOwn, disabledTooltip = "Your own class",
          onClick = function()
              if notOwn() then return end
              LoadClass(ViewClass())
              if not (state.T and state.live) then return end
              local n = TC.CopyCurrent(state.T, state.live)
              TC.Print("the build starts with your " .. n .. " current talent points.")
              RefreshAll()
          end },
        { type = "labeledButton", text = "Clear Build", buttonText = "Clear",
          tooltip = "Removes every talent from this class's build.",
          onClick = function()
              local file = ViewClass()
              local function doClear()
                  TC.ClearPlan(file)
                  RefreshAll()
              end
              if EllesmereUI.ShowConfirmPopup then
                  EllesmereUI:ShowConfirmPopup({
                      title = "Clear Build",
                      message = "Remove every talent from the " .. TC.ClassColored(file) .. " build?",
                      confirmText = "Clear", cancelText = "Cancel",
                      onConfirm = doClear,
                  })
              else
                  doClear()
              end
          end }
    );  y = y - h

    -- Saved builds of this class: open, save, delete; share with export/import.
    local NONE = "__none"
    local buildValues, buildOrder = {}, {}
    local names = TC.BuildNames(ViewClass())
    if #names == 0 then
        buildValues[NONE] = "No saved builds"
        buildOrder[1] = NONE
    else
        -- Shown on the button while no saved build is open; not in the list.
        buildValues[NONE] = "Select a build..."
        for _, n in ipairs(names) do buildValues[n] = n; buildOrder[#buildOrder + 1] = n end
    end
    local function noOpen() return TC.OpenBuild(ViewClass()) == nil end

    _, h = W:TripleRow(parent, y,
        { type = "dropdown", text = "Saved Build", values = buildValues, order = buildOrder,
          tooltip = "Opens a saved build of this class; it becomes the build you edit and learn. "
              .. "Each class has its own saved builds.",
          getValue = function() return TC.OpenBuild(ViewClass()) or NONE end,
          setValue = function(v)
              if v == NONE then return end
              TC.LoadBuild(ViewClass(), v)
              RefreshAll()
          end },
        { type = "button", text = "Save Build",
          tooltip = "Saves the build under a name. Saving under an existing name overwrites it.",
          onClick = function()
              local file = ViewClass()
              EllesmereUI:ShowInputPopup({
                  title = "Save Build",
                  message = "Name of this " .. TC.ClassColored(file) .. " build.\nAn existing build with the same name is overwritten.",
                  placeholder = "Build name...",
                  initialText = TC.OpenBuild(file) or "",
                  maxLetters = 30,
                  confirmText = "Save", cancelText = "Cancel",
                  onConfirm = function(txt)
                      if TC.SaveBuild(file, txt) then
                          TC.Print("saved the " .. TC.ClassColored(file) .. " build \"" .. TC.CleanName(txt) .. "\".")
                          EllesmereUI:RefreshPage(true)
                      end
                  end,
              })
          end },
        { type = "button", text = "Delete Build",
          tooltip = "Deletes the saved build selected on the left. Select it first, then press Delete Build.",
          disabled = noOpen, disabledTooltip = "A saved build selected on the left",
          onClick = function()
              local file = ViewClass()
              local name = TC.OpenBuild(file)
              if not name then return end
              EllesmereUI:ShowConfirmPopup({
                  title = "Delete Build",
                  message = "Delete the saved " .. TC.ClassColored(file) .. " build \"" .. name .. "\"?",
                  confirmText = "Delete", cancelText = "Cancel",
                  onConfirm = function()
                      TC.DeleteBuild(file, name)
                      EllesmereUI:RefreshPage(true)
                  end,
              })
          end }
    );  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "labeledButton", text = "Share This Build", buttonText = "Export",
          tooltip = "Makes a text of the build you can copy (Ctrl+C) and send to others.",
          onClick = function()
              ShowExport(TC.Export(ViewClass()))
          end },
        { type = "labeledButton", text = "Load a Shared Build", buttonText = "Import",
          tooltip = "Paste a build text someone shared. The calculator switches to its class, opens it and saves it.",
          onClick = function()
              EllesmereUI:ShowInputPopup({
                  title = "Import Build",
                  message = "Paste the build text with Ctrl+V.",
                  placeholder = "EUITC1:...",
                  maxLetters = 4000,
                  confirmText = "Import", cancelText = "Cancel",
                  onConfirm = function(txt)
                      local file, nameOrWhy = TC.ImportBuild(txt)
                      if not file then
                          TC.Print(nameOrWhy)
                          return
                      end
                      TC.CDB().viewClass = file
                      TC.Print("imported the " .. TC.ClassColored(file) .. " build \"" .. nameOrWhy .. "\".")
                      EllesmereUI:RefreshPage(true)
                  end,
              })
          end }
    );  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "labeledButton", text = "Learn the Build Now", buttonText = "Learn Now",
          tooltip = "Spends your free talent points on the next talents of the build right away, and applies them.",
          disabled = notOwn, disabledTooltip = "Your own class",
          onClick = function() TC.LearnPlanned(true) end },
        EllesmereUI.BlankRowCfg()
    );  y = y - h

    local legacyRow
    legacyRow, h = W:DualRow(parent, y,
        { type = "label", text = "Legacy Talent Points",
          tooltip = "Points in the Progress Legacy > Adventure talent passive. Each point moves your first "
              .. "talent point one level earlier (5 points: level 5 instead of 10). You never get more than "
              .. TC.MAX_TALENT_POINTS .. " talent points." }
    );  y = y - h
    if not prebuild and legacyRow and legacyRow._leftRegion then
        legacyFS = EllesmereUI.MakeFont(legacyRow, 13, nil, 1, 1, 1, 1)
        legacyFS:SetPoint("RIGHT", legacyRow, "RIGHT", -20, 0)
        legacyFS:SetJustifyH("RIGHT")
        UpdateLegacy()
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    if not prebuild then
        LoadClass(ViewClass())
        EnsureCanvas()
        local width = math.max(400, parent:GetWidth() - CONTENT_PAD * 2)
        canvas:SetParent(parent)
        canvas:SetFrameLevel(parent:GetFrameLevel() + 2)
        canvas:ClearAllPoints()
        canvas:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, y)
        local ch = Layout(width)
        canvas:SetHeight(ch)
        canvas:Show()
        Repaint()
        y = y - ch
    end

    return math.abs(y) + 10
end

DW.AddModule({
    key         = "TalentCalc",
    title       = "Talent Calculator",
    order       = 30,
    description = "Plan a talent build for any class. Your class's build is learned automatically as you level up.",
    pages       = { "Calculator" },
    buildPage   = BuildPage,
    onPageCacheRestore = function()
        if not canvas then return end
        local hadTree = state.T ~= nil
        LoadClass(ViewClass())
        if hadTree ~= (state.T ~= nil) then EllesmereUI:RefreshPage(true) else Repaint() end
    end,
})

-- Live: the talents you learn turn the build's picks to "learned".
local live = CreateFrame("Frame")
for _, ev in ipairs({ "TRAIT_CONFIG_UPDATED", "PLAYER_LEVEL_UP", "PLAYER_TALENT_UPDATE",
                      "TRAIT_TREE_CURRENCY_INFO_UPDATED" }) do
    pcall(live.RegisterEvent, live, ev)
end
local livePending = false
live:SetScript("OnEvent", function()
    if not (canvas and canvas:IsVisible()) or livePending then return end
    livePending = true
    C_Timer.After(0.3, function()
        livePending = false
        if not canvas:IsVisible() then return end
        if IsOwnClass() then LoadClass(state.class) end
        Repaint()
    end)
end)

-- The UI Accent Color (Global Settings) repaints the calculator live.
if EllesmereUI.RegAccent then
    EllesmereUI.RegAccent({ type = "callback", fn = function()
        if canvas and canvas:IsVisible() then Repaint() end
    end })
end

-- /talentcalc (or /tcalc) opens the page; "learn" learns the build now;
-- "debug" prints what the client's talent API gives.
SLASH_EUITALENTCALC1 = "/talentcalc"
SLASH_EUITALENTCALC2 = "/tcalc"
SlashCmdList.EUITALENTCALC = function(msg)
    msg = (msg or ""):lower()
    if msg:match("debug") then TC.Debug(); return end
    if msg:match("learn") then TC.LearnPlanned(true); return end
    DW.Open("TalentCalc")
end
