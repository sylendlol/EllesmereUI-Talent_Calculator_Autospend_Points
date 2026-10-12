if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUITalentCalc_Core.lua
--  Dworak > Talent Calculator: the data side.
--
--  * Reads talent trees from the client's trait API (C_Traits), the same
--    tree the WoW Forever talent window (Apply Changes) shows.
--      - your own class: the live tree, read fresh every time;
--      - other classes: the client's view loadout when it gives one, else
--        the copy saved the last time a character of that class logged in.
--  * A build is an ORDERED list of picks: the order you click the talents
--    in the calculator is the order they are learned, one per talent point.
--  * Learn on level up: after every level-up (and at login) the next
--    planned talents are bought with the points you have, then applied.
--
--  Saved data:
--    EllesmereUITalentCalcDB      (account)  trees[class], plans[class], firstLevel
--    EllesmereUITalentCalcCharDB  (character) autoLearn, viewClass
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local DW = EllesmereUIDworak
if not DW then return end -- the Dworak core is off: nothing to register into

ns.FOLDER = ADDON_NAME
local TC = {}
ns.TC = TC

local EMPTY = {}
local DATA_VERSION = 1

-------------------------------------------------------------------------------
--  Saved variables (read lazily: they load after this file runs)
-------------------------------------------------------------------------------
function TC.DB()
    local d = EllesmereUITalentCalcDB
    if type(d) ~= "table" then d = {}; EllesmereUITalentCalcDB = d end
    if d.version ~= DATA_VERSION then
        d.version = DATA_VERSION
        d.trees = {}            -- tree layout format changed: re-read on next login
    end
    d.trees = d.trees or {}
    d.plans = d.plans or {}
    d.builds = d.builds or {}   -- builds[class][name] = { steps, time }
    return d
end

function TC.CDB()
    local c = EllesmereUITalentCalcCharDB
    if type(c) ~= "table" then c = {}; EllesmereUITalentCalcCharDB = c end
    if c.autoLearn == nil then c.autoLearn = true end
    return c
end

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
    return nil
end
TC.Call = Call

function TC.Accent()
    local c = EllesmereUI.ELLESMERE_GREEN
    if c and c.r then return c.r, c.g, c.b end
    return 0.05, 0.82, 0.62
end

function TC.AccentHex()
    return EllesmereUI.HexColor(TC.Accent())
end

function TC.Print(msg)
    EllesmereUI.Print(TC.AccentHex() .. "Talent Calculator:|r " .. msg)
end

function TC.PlayerClass()
    return select(2, UnitClass("player"))
end

local function SpellNameIcon(spellID)
    if not spellID then return nil, nil end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = Call(C_Spell.GetSpellInfo, spellID)
        if type(info) == "table" then return info.name, info.iconID end
    end
    if GetSpellInfo then
        local ok, name, _, icon = pcall(GetSpellInfo, spellID)
        if ok then return name, icon end
    end
end

-------------------------------------------------------------------------------
--  Classes (WoW Forever: the nine original classes)
-------------------------------------------------------------------------------
local FOREVER_CLASSES = {
    WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true,
    SHAMAN = true, MAGE = true, WARLOCK = true, DRUID = true,
}

local classList
function TC.Classes()
    if classList then return classList end
    classList = {}
    local n = (GetNumClasses and Call(GetNumClasses)) or 13
    for i = 1, math.max(n, 13) do
        local ok, name, file, id = pcall(GetClassInfo, i)
        if ok and name and file and (not EllesmereUI.IS_FOREVER or FOREVER_CLASSES[file]) then
            classList[#classList + 1] = { name = name, file = file, id = id or i }
        end
    end
    table.sort(classList, function(a, b) return a.name < b.name end)
    return classList
end

function TC.ClassInfo(file)
    for _, c in ipairs(TC.Classes()) do
        if c.file == file then return c end
    end
end

function TC.ClassColored(file)
    local c = TC.ClassInfo(file)
    local name = c and c.name or file
    local col = RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
    if col and col.colorStr then return "|c" .. col.colorStr .. name .. "|r" end
    return name
end

-- Talent tree names, left to right: the client's specializations when it has
-- one per tree, else the original names.
local TREE_NAMES = {
    WARRIOR = { "Arms", "Fury", "Protection" },
    PALADIN = { "Holy", "Protection", "Retribution" },
    HUNTER  = { "Beast Mastery", "Marksmanship", "Survival" },
    ROGUE   = { "Assassination", "Combat", "Subtlety" },
    PRIEST  = { "Discipline", "Holy", "Shadow" },
    SHAMAN  = { "Elemental", "Enhancement", "Restoration" },
    MAGE    = { "Arcane", "Fire", "Frost" },
    WARLOCK = { "Affliction", "Demonology", "Destruction" },
    DRUID   = { "Balance", "Feral Combat", "Restoration" },
}

-- { { name, icon }, ... } for count trees, or nil.
function TC.TreeNames(file, count)
    local out = {}
    local c = TC.ClassInfo(file)
    local getNum = (C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID)
        or GetNumSpecializationsForClassID
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfoForClassID)
        or GetSpecializationInfoForClassID
    if c and getNum and getSpec and Call(getNum, c.id) == count then
        for i = 1, count do
            local ok, _, name, _, icon = pcall(getSpec, c.id, i)
            if ok and type(name) == "string" and name ~= "" then out[i] = { name = name, icon = icon } end
        end
        if #out == count then return out end
    end
    out = {}
    local names = TREE_NAMES[file]
    if names and #names == count then
        for i = 1, count do out[i] = { name = names[i] } end
        -- Icons from the talent tabs of your own class, when the client has them.
        if file == TC.PlayerClass() and GetTalentTabInfo then
            for i = 1, count do
                local r = { pcall(GetTalentTabInfo, i) }
                -- Classic: name, icon, ...; later clients: id, name, description, icon.
                local icon
                if r[1] then
                    if type(r[2]) == "string" then icon = r[3] else icon = r[5] end
                end
                if type(icon) == "number" or type(icon) == "string" then out[i].icon = icon end
            end
        end
        return out
    end
    return nil
end

-------------------------------------------------------------------------------
--  Levels and points
-------------------------------------------------------------------------------
function TC.MaxLevel()
    local m = GetMaxLevelForPlayerExpansion and Call(GetMaxLevelForPlayerExpansion)
    if type(m) == "number" and m > 1 then return m end
    return MAX_PLAYER_LEVEL or 60
end

-- The level the first talent point comes at. Read from the live tree
-- (level - points earned + 1); 10 until a character has been read.
-- WoW Forever: never more than 51 talent points, whatever the level.
TC.MAX_TALENT_POINTS = 51
-- Progress Legacy > Adventure passive: each rank moves the first talent
-- point one level earlier (rank 5: level 5 instead of 10).
TC.LEGACY_TALENT_SPELL = 1225474

-- The first talent level the Legacy passive gives, read from its text
-- ("... starting at level 5 instead of ..."); nil when not learned/unknown.
function TC.LegacyFirstLevel()
    local id = TC.LEGACY_TALENT_SPELL
    local known = (IsPlayerSpell and Call(IsPlayerSpell, id)) or (IsSpellKnown and Call(IsSpellKnown, id))
    if not known then return nil end
    local desc = C_Spell and C_Spell.GetSpellDescription and Call(C_Spell.GetSpellDescription, id)
    if type(desc) ~= "string" then return nil end
    local lv = tonumber(desc:match("starting at level (%d+)"))
    if lv and lv >= 1 and lv <= 10 then return lv end
    return nil
end

-- The level your first talent point comes at (this character): read from the
-- live tree (level - points earned + 1), else the Legacy passive, else 10.
function TC.FirstLevel()
    local c = EllesmereUITalentCalcCharDB
    local f = type(c) == "table" and c.firstLevel
    if type(f) == "number" and f >= 1 then return f end
    return TC.LegacyFirstLevel() or 10
end

function TC.MaxPoints()
    local byLevel = math.max(1, TC.MaxLevel() - TC.FirstLevel() + 1)
    if EllesmereUI.IS_FOREVER then return math.min(TC.MAX_TALENT_POINTS, byLevel) end
    return byLevel
end

-------------------------------------------------------------------------------
--  Reading a tree
--  T = { trees = { treeID, ... }, order = { nodeID, ... } (top-down),
--        nodes = { [nodeID] = { id, tree, x, y, maxRanks, choice, free,
--                  entries = { { id, spell, name, icon, ranks } },
--                  cost = { { cur, amount } },
--                  parents = { { node, req, gating } },
--                  gates = { { cur, amount } } } } }
--  live = { [nodeID] = { rank, entry } }   (the active config only)
-------------------------------------------------------------------------------
local function EdgeTypes()
    local E = Enum and Enum.TraitEdgeType
    return (E and E.RequiredForAvailability) or 3, (E and E.SufficientForAvailability) or 2
end

local function Scan(configID, treeIDs)
    if not (C_Traits and C_Traits.GetTreeNodes and C_Traits.GetNodeInfo) then return nil end
    local T = { trees = {}, nodes = {}, order = {} }
    local live = {}
    local gateByCond = {}
    local SUBTREE = Enum and Enum.TraitNodeType and Enum.TraitNodeType.SubTreeSelection

    local function Gate(condID)
        local g = gateByCond[condID]
        if g ~= nil then return g end
        g = false
        local ci = Call(C_Traits.GetConditionInfo, configID, condID)
        if type(ci) == "table" and type(ci.spentAmountRequired) == "number" and ci.spentAmountRequired > 0 then
            g = { cur = ci.traitCurrencyID, amount = ci.spentAmountRequired }
        end
        gateByCond[condID] = g
        return g
    end

    local outgoing = {}
    for ti, treeID in ipairs(treeIDs) do
        T.trees[ti] = treeID
        -- The tree's own gates ("spend N points to unlock this row").
        local tinfo = Call(C_Traits.GetTreeInfo, configID, treeID)
        if type(tinfo) == "table" and type(tinfo.gates) == "table" then
            for _, g in ipairs(tinfo.gates) do
                if g.conditionID and (g.spentAmountRequired or 0) > 0 then
                    gateByCond[g.conditionID] = { cur = g.traitCurrencyID, amount = g.spentAmountRequired }
                end
            end
        end
        for _, nodeID in ipairs(Call(C_Traits.GetTreeNodes, treeID) or EMPTY) do
            local info = Call(C_Traits.GetNodeInfo, configID, nodeID)
            if type(info) == "table" and info.ID and info.ID ~= 0 and info.isVisible ~= false
               and not info.subTreeID and not (SUBTREE and info.type == SUBTREE) then
                local node = {
                    id = nodeID, tree = ti, x = info.posX or 0, y = info.posY or 0,
                    entries = {}, cost = {}, parents = {}, gates = {},
                }
                for _, entryID in ipairs(info.entryIDs or EMPTY) do
                    local e = Call(C_Traits.GetEntryInfo, configID, entryID)
                    local def = type(e) == "table" and e.definitionID and Call(C_Traits.GetDefinitionInfo, e.definitionID)
                    if type(def) == "table" then
                        local spellID = def.spellID or def.overriddenSpellID
                        local name, icon = SpellNameIcon(spellID)
                        name = def.overrideName or name
                        if name or spellID then
                            node.entries[#node.entries + 1] = {
                                id = entryID, spell = spellID,
                                name = name or ("Spell " .. tostring(spellID)),
                                icon = def.overrideIcon or icon or 134400,
                                ranks = e.maxRanks or info.maxRanks or 1,
                            }
                        end
                    end
                end
                if #node.entries > 0 then
                    node.maxRanks = info.maxRanks or node.entries[1].ranks or 1
                    node.choice = #node.entries > 1
                    for _, c in ipairs(Call(C_Traits.GetNodeCost, configID, nodeID) or EMPTY) do
                        if (c.amount or 0) > 0 then
                            node.cost[#node.cost + 1] = { cur = c.ID, amount = c.amount }
                        end
                    end
                    for _, condID in ipairs(info.conditionIDs or EMPTY) do
                        local g = Gate(condID)
                        if g then node.gates[#node.gates + 1] = g end
                    end
                    outgoing[nodeID] = info.visibleEdges
                    live[nodeID] = {
                        rank  = info.ranksPurchased or 0,
                        entry = info.activeEntry and info.activeEntry.entryID or nil,
                    }
                    T.nodes[nodeID] = node
                    T.order[#T.order + 1] = nodeID
                end
            end
        end
    end
    if #T.order == 0 then return nil end

    -- Arrows: stored on the child as its parents.
    local REQ, SUF = EdgeTypes()
    for src, edges in pairs(outgoing) do
        for _, e in ipairs(edges or EMPTY) do
            local child = e.targetNode and T.nodes[e.targetNode]
            if child then
                child.parents[#child.parents + 1] = {
                    node = src, req = (e.type == REQ), gating = (e.type == REQ or e.type == SUF),
                }
            end
        end
    end

    -- Nodes that cost nothing are given for free (starting talents). If the
    -- client reports no cost anywhere, every rank costs one point instead.
    local anyCost = false
    for _, n in pairs(T.nodes) do
        if #n.cost > 0 then anyCost = true; break end
    end
    for _, n in pairs(T.nodes) do
        if #n.cost == 0 then
            if anyCost then n.free = true else n.cost = { { amount = 1 } } end
        end
    end

    table.sort(T.order, function(a, b)
        local A, B = T.nodes[a], T.nodes[b]
        if A.tree ~= B.tree then return A.tree < B.tree end
        if A.y ~= B.y then return A.y < B.y end
        if A.x ~= B.x then return A.x < B.x end
        return a < b
    end)
    return T, live
end

-- The active config and its trees, or nil.
function TC.LiveConfig()
    if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits) then return nil end
    local configID = Call(C_ClassTalents.GetActiveConfigID)
    if not configID then return nil end
    local trees = {}
    local cfg = Call(C_Traits.GetConfigInfo, configID)
    if type(cfg) == "table" and type(cfg.treeIDs) == "table" then
        for _, t in ipairs(cfg.treeIDs) do trees[#trees + 1] = t end
    end
    if #trees == 0 and C_SpecializationInfo and C_ClassTalents.GetTraitTreeForSpec then
        local specIndex = Call(C_SpecializationInfo.GetSpecialization)
        local specID = specIndex and specIndex > 0 and Call(C_SpecializationInfo.GetSpecializationInfo, specIndex)
        local t = specID and Call(C_ClassTalents.GetTraitTreeForSpec, specID)
        if t then trees[1] = t end
    end
    if #trees == 0 then return nil end
    return configID, trees
end

-- Unspent points per currency (staged changes included), plus .all.
local function Currencies(configID, trees)
    local q, seen = { all = 0 }, {}
    for _, treeID in ipairs(trees) do
        for _, cur in ipairs(Call(C_Traits.GetTreeCurrencyInfo, configID, treeID, false) or EMPTY) do
            local id = cur.traitCurrencyID
            if id and not seen[id] then
                seen[id] = true
                q[id] = cur.quantity or 0
                q.all = q.all + (cur.quantity or 0)
                q.earned = (q.earned or 0) + (cur.quantity or 0) + (cur.spent or 0)
            end
        end
    end
    return q
end

-- Your unspent talent points right now (0 when the tree cannot be read).
function TC.UnspentPoints()
    local configID, trees = TC.LiveConfig()
    if not configID then return 0 end
    return Currencies(configID, trees).all or 0
end

-- Your own class, live. Saves a copy for the other characters of the account.
-- Returns T, live, configID, trees.
function TC.ScanLive()
    local configID, trees = TC.LiveConfig()
    if not configID then return nil end
    local T, live = Scan(configID, trees)
    if not T then return nil end
    T.source, T.time = "live", time()
    local db = TC.DB()
    db.trees[TC.PlayerClass()] = T
    -- First talent level: level - points earned so far + 1.
    local earned = Currencies(configID, trees).earned or 0
    local level = UnitLevel("player") or 0
    -- Only while points still come with levels (below the 51 cap).
    local cdb = TC.CDB()
    if earned > 0 and earned < TC.MAX_TALENT_POINTS and level >= earned then
        cdb.firstLevel = math.max(1, math.min(10, level - earned + 1))
    elseif earned == 0 or not cdb.firstLevel then
        cdb.firstLevel = TC.LegacyFirstLevel()   -- nil: back to 10
    end
    return T, live, configID, trees
end

-- Another class: the client's view loadout (the way the talent window shows
-- a spec you are not playing), else the saved copy.
local function ScanView(file)
    local VIEW = Constants and Constants.TraitConsts and Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID
    if not (VIEW and C_ClassTalents and C_ClassTalents.InitializeViewLoadout and C_ClassTalents.GetTraitTreeForSpec) then
        return nil
    end
    local c = TC.ClassInfo(file)
    if not c then return nil end
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfoForClassID)
        or GetSpecializationInfoForClassID
    local specID = getSpec and Call(getSpec, c.id, 1)
    if not specID then return nil end
    local treeID = Call(C_ClassTalents.GetTraitTreeForSpec, specID)
    if not treeID then return nil end
    if not Call(C_ClassTalents.InitializeViewLoadout, specID, TC.MaxLevel()) then
        -- Some clients return nothing on success: carry on and let the scan decide.
    end
    local T = Scan(VIEW, { treeID })
    if not T then return nil end
    T.source, T.time = "view", time()
    return T
end

-- T (and live, for your own class) for the given class, or nil.
-------------------------------------------------------------------------------
--  Classic tiers (WoW Forever): one trait tree holds the class's three
--  talent trees side by side. Each gets n.sub (1..3) and every talent n.row
--  (0 = top row); a talent in row r needs r * 5 points spent in its own tree.
--  The client has no condition for this, so the calculator applies it.
-------------------------------------------------------------------------------
TC.TIER_POINTS = 5

local function MinGap(sorted)
    local best
    for i = 2, #sorted do
        local d = sorted[i] - sorted[i - 1]
        if d > 0.01 and (not best or d < best) then best = d end
    end
    return best
end

local function Distinct(values)
    table.sort(values)
    local u = {}
    for _, v in ipairs(values) do
        if #u == 0 or v - u[#u] > 0.01 then u[#u + 1] = v end
    end
    return u
end

-- Removes the nodes in drop (set of nodeIDs) from T.
function TC.DropNodes(T, drop)
    if not next(drop) then return end
    local order = {}
    for _, id in ipairs(T.order) do
        if drop[id] then T.nodes[id] = nil else order[#order + 1] = id end
    end
    T.order = order
    for _, n in pairs(T.nodes) do
        for i = #n.parents, 1, -1 do
            if drop[n.parents[i].node] then table.remove(n.parents, i) end
        end
    end
end

-- The client lists some talents twice (same spell, the copy at a position off
-- the grid). Keep the copy that sits in the grid: the one sharing its column
-- and row with the most other talents; a copy you have ranks in always wins.
local function Dedupe(T, live)
    local colCount, rowCount = {}, {}
    for _, n in pairs(T.nodes) do
        colCount[n.x] = (colCount[n.x] or 0) + 1
        rowCount[n.y] = (rowCount[n.y] or 0) + 1
    end
    local function Key(n)
        local parts = {}
        for _, e in ipairs(n.entries) do parts[#parts + 1] = tostring(e.spell or e.name) end
        table.sort(parts)
        return n.tree .. ":" .. table.concat(parts, ",")
    end
    local function Score(n)
        local L = live and live[n.id]
        local ranked = L and (L.rank or 0) > 0 and 1000 or 0
        return ranked + (colCount[n.x] - 1) + (rowCount[n.y] - 1) + #n.parents
    end
    local keep, drop = {}, {}
    for _, id in ipairs(T.order) do
        local n = T.nodes[id]
        local k = Key(n)
        local other = keep[k]
        if not other then
            keep[k] = n
        elseif Score(n) > Score(other) then
            drop[other.id] = true
            keep[k] = n
        else
            drop[n.id] = true
        end
    end
    TC.DropNodes(T, drop)
end

local function AssignTiers(T, live)
    T.tiered, T.subCount = false, nil
    if not EllesmereUI.IS_FOREVER then return end
    local subCount = 0
    for ti = 1, #T.trees do
        local nodes, xs = {}, {}
        for _, id in ipairs(T.order) do
            local n = T.nodes[id]
            if n.tree == ti then nodes[#nodes + 1] = n; xs[#xs + 1] = n.x end
        end
        local u = Distinct(xs)
        -- The trees are split at the widest column gaps (up to 2 splits =
        -- 3 trees), each clearly wider than a normal column step.
        local gaps = {}
        for i = 2, #u do gaps[#gaps + 1] = { d = u[i] - u[i - 1], at = u[i] } end
        local sortedD = {}
        for i, g in ipairs(gaps) do sortedD[i] = g.d end
        table.sort(sortedD)
        local median = sortedD[math.ceil(#sortedD / 2)] or 0
        table.sort(gaps, function(a, b) return a.d > b.d end)
        local cuts = {}
        for i = 1, math.min(2, #gaps) do
            if gaps[i].d > median * 1.5 then cuts[#cuts + 1] = gaps[i].at end
        end
        table.sort(cuts)
        local base = subCount
        for _, n in ipairs(nodes) do
            local k = 1
            for _, c in ipairs(cuts) do if n.x >= c - 0.01 then k = k + 1 end end
            n.sub = base + k
        end
        subCount = base + #cuts + 1
    end
    -- Talents the client lists off the grid (far below the last row or beside
    -- the last column, no arrow, no rank) are not in the talent window: out.
    local linked = {}
    for _, n in pairs(T.nodes) do
        if #n.parents > 0 then linked[n.id] = true end
        for _, p in ipairs(n.parents) do linked[p.node] = true end
    end
    local drop = {}
    for sub = 1, subCount do
        local members, xs, ys = {}, {}, {}
        for _, n in pairs(T.nodes) do
            if n.sub == sub then members[#members + 1] = n; xs[#xs + 1] = n.x; ys[#ys + 1] = n.y end
        end
        local stepX, stepY = MinGap(Distinct(xs)), MinGap(Distinct(ys))
        if #members > 3 then
            for _, n in ipairs(members) do
                local L = live and live[n.id]
                if not linked[n.id] and not (L and (L.rank or 0) > 0) then
                    local dx, dy
                    for _, o in ipairs(members) do
                        if o ~= n then
                            local ax, ay = math.abs(o.x - n.x), math.abs(o.y - n.y)
                            if not dx or ax < dx then dx = ax end
                            if not dy or ay < dy then dy = ay end
                        end
                    end
                    if (stepY and dy and dy > stepY * 1.5) or (stepX and dx and dx > stepX * 2.5) then
                        drop[n.id] = true
                    end
                end
            end
        end
    end
    T.offGrid = 0
    for _ in pairs(drop) do T.offGrid = T.offGrid + 1 end
    TC.DropNodes(T, drop)

    -- Rows inside each tree.
    for sub = 1, subCount do
        local ys = {}
        for _, n in pairs(T.nodes) do if n.sub == sub then ys[#ys + 1] = n.y end end
        local u = Distinct(ys)
        local step = MinGap(u)
        for _, n in pairs(T.nodes) do
            if n.sub == sub then
                n.row = step and math.floor((n.y - u[1]) / step + 0.5) or 0
            end
        end
    end
    T.subCount = subCount
    T.tiered = true
end
TC.AssignTiers = AssignTiers

-- T (and live, for your own class) for the given class, or nil.
local function GetTreeRaw(file)
    if file == TC.PlayerClass() then
        local T, live = TC.ScanLive()
        if T then return T, live end
        return TC.DB().trees[file]
    end
    local saved = TC.DB().trees[file]
    if saved and saved.source == "live" then return saved end
    local T = ScanView(file)
    if T then
        TC.DB().trees[file] = T
        return T
    end
    return saved
end

function TC.GetTree(file)
    local T, live = GetTreeRaw(file)
    if T then Dedupe(T, live); AssignTiers(T, live) end
    return T, live
end

-------------------------------------------------------------------------------
--  Builds: rules
-------------------------------------------------------------------------------
function TC.Plan(file)
    local plans = TC.DB().plans
    local p = plans[file]
    if type(p) ~= "table" then p = { steps = {} }; plans[file] = p end
    p.steps = p.steps or {}
    return p
end

function TC.NodeMax(n, entryID)
    if n.choice and entryID then
        for _, e in ipairs(n.entries) do
            if e.id == entryID then return e.ranks or n.maxRanks or 1 end
        end
    end
    return n.maxRanks or 1
end

function TC.EntryOf(n, entryID)
    if entryID then
        for _, e in ipairs(n.entries) do
            if e.id == entryID then return e end
        end
    end
    return n.entries[1]
end

local function CostOf(n)
    local c = 0
    for _, x in ipairs(n.cost) do c = c + x.amount end
    return c
end

function TC.Maxed(T, st, id)
    local n = T.nodes[id]
    if not n or n.free then return true end
    return (st.ranks[id] or 0) >= TC.NodeMax(n, st.entry[id])
end

local function NewState()
    return { ranks = {}, entry = {}, spent = {}, subSpent = {}, total = 0, steps = {}, levels = {} }
end

-- Can one more rank of node id be added to the build st? false, reason if not.
function TC.CanAdd(T, st, id, entryID)
    local n = T.nodes[id]
    if not n then return false, "Not in this tree." end
    if n.free then return false, "You get this talent for free." end
    local chosen = st.entry[id]
    if n.choice and chosen and entryID and chosen ~= entryID then
        return false, "The other choice of this talent is in the build."
    end
    if (st.ranks[id] or 0) >= TC.NodeMax(n, chosen or entryID) then return false, "Maxed." end
    if st.total + CostOf(n) > TC.MaxPoints() then return false, "No talent points left." end
    local hasSuf, sufOK
    for _, p in ipairs(n.parents) do
        if p.gating then
            local pn = T.nodes[p.node]
            local pname = pn and TC.EntryOf(pn, st.entry[p.node]).name or "?"
            if p.req and not TC.Maxed(T, st, p.node) then
                return false, "Requires " .. pname .. " at max rank."
            elseif not p.req then
                hasSuf = hasSuf or pname
                if TC.Maxed(T, st, p.node) then sufOK = true end
            end
        end
    end
    if hasSuf and not sufOK then return false, "Requires " .. hasSuf .. " at max rank." end
    if T.tiered and n.sub and (n.row or 0) > 0 then
        local need, have = n.row * TC.TIER_POINTS, st.subSpent[n.sub] or 0
        if have < need then
            return false, string.format("Requires %d points spent in this tree (%d more).", need, need - have)
        end
    end
    for _, g in ipairs(n.gates) do
        local have = g.cur and (st.spent[g.cur] or 0) or st.total
        if have < g.amount then
            return false, string.format("Requires %d points spent in the tree (%d more).", g.amount, g.amount - have)
        end
    end
    return true
end

local function Push(T, st, id, entryID)
    local n = T.nodes[id]
    st.ranks[id] = (st.ranks[id] or 0) + 1
    if n.choice then st.entry[id] = st.entry[id] or entryID or n.entries[1].id end
    for _, c in ipairs(n.cost) do
        if c.cur then st.spent[c.cur] = (st.spent[c.cur] or 0) + c.amount end
    end
    st.total = st.total + CostOf(n)
    if n.sub then st.subSpent[n.sub] = (st.subSpent[n.sub] or 0) + CostOf(n) end
    st.steps[#st.steps + 1] = { n = id, e = n.choice and st.entry[id] or nil }
    st.levels[#st.steps] = TC.FirstLevel() + st.total - 1
end

-- Replays a build in order; a pick the rules no longer allow is left out.
function TC.Evaluate(T, steps)
    local st = NewState()
    for _, s in ipairs(steps or EMPTY) do
        if T.nodes[s.n] and TC.CanAdd(T, st, s.n, s.e) then Push(T, st, s.n, s.e) end
    end
    return st
end

function TC.AddRank(file, T, id, entryID)
    local plan = TC.Plan(file)
    local st = TC.Evaluate(T, plan.steps)
    local ok, why = TC.CanAdd(T, st, id, entryID)
    if not ok then return false, why end
    Push(T, st, id, entryID)
    plan.steps = st.steps
    return true
end

-- Takes out the last rank of node id (all of them with all = true); picks
-- that needed it drop out too.
function TC.RemoveRank(file, T, id, all)
    local plan = TC.Plan(file)
    local steps = TC.Evaluate(T, plan.steps).steps
    for i = #steps, 1, -1 do
        if steps[i].n == id then
            table.remove(steps, i)
            if not all then break end
        end
    end
    plan.steps = TC.Evaluate(T, steps).steps
end

function TC.ClearPlan(file)
    local p = TC.Plan(file)
    p.steps = {}
    p.name = nil
end

-------------------------------------------------------------------------------
--  Saved builds (per class) and sharing strings
-------------------------------------------------------------------------------
local function CopySteps(steps)
    local out = {}
    for i, s in ipairs(steps or EMPTY) do out[i] = { n = s.n, e = s.e } end
    return out
end

local function Builds(file)
    local all = TC.DB().builds
    all[file] = all[file] or {}
    return all[file]
end

function TC.CleanName(name)
    name = tostring(name or ""):gsub("|", ""):gsub(":", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return name
end

-- Sorted names of a class's saved builds.
function TC.BuildNames(file)
    local names = {}
    for name in pairs(Builds(file)) do names[#names + 1] = name end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

function TC.HasBuild(file, name)
    return name ~= nil and Builds(file)[name] ~= nil
end

-- The build that is open now (its name), or nil.
function TC.OpenBuild(file)
    local p = TC.Plan(file)
    if p.name and Builds(file)[p.name] then return p.name end
    return nil
end

function TC.SaveBuild(file, name)
    name = TC.CleanName(name)
    if name == "" then return false end
    local p = TC.Plan(file)
    Builds(file)[name] = { steps = CopySteps(p.steps), time = time() }
    p.name = name
    return true
end

function TC.LoadBuild(file, name)
    local b = Builds(file)[name]
    if not b then return false end
    local p = TC.Plan(file)
    p.steps = CopySteps(b.steps)
    p.name = name
    return true
end

function TC.DeleteBuild(file, name)
    Builds(file)[name] = nil
    local p = TC.Plan(file)
    if p.name == name then p.name = nil end
end

-- A free name: name, name (2), name (3) ...
function TC.FreeName(file, name)
    name = TC.CleanName(name)
    if name == "" then name = "Imported" end
    if not Builds(file)[name] then return name end
    local i = 2
    while Builds(file)[name .. " (" .. i .. ")"] do i = i + 1 end
    return name .. " (" .. i .. ")"
end

-- Sharing string: EUITC1:CLASS:Name:steps. Steps in learning order, runs of
-- the same talent folded: nodeID[~entryID][xCount], joined by dots.
local EXPORT_PREFIX = "EUITC1"

function TC.Export(file)
    local p = TC.Plan(file)
    local parts, i, steps = {}, 1, p.steps or EMPTY
    while i <= #steps do
        local s, count = steps[i], 1
        while steps[i + count] and steps[i + count].n == s.n and steps[i + count].e == s.e do count = count + 1 end
        local tok = tostring(s.n)
        if s.e then tok = tok .. "~" .. s.e end
        if count > 1 then tok = tok .. "x" .. count end
        parts[#parts + 1] = tok
        i = i + count
    end
    return string.format("%s:%s:%s:%s", EXPORT_PREFIX, file, TC.CleanName(TC.OpenBuild(file) or ""), table.concat(parts, "."))
end

-- Returns class, name, steps; or nil, reason.
function TC.Import(text)
    text = tostring(text or ""):gsub("[\r\n]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    local prefix, file, name, body = text:match("^(%w+):(%u+):([^:]*):([%d%.~x]*)$")
    if prefix ~= EXPORT_PREFIX then return nil, "This is not a Talent Calculator build string." end
    if not TC.ClassInfo(file) then return nil, "Unknown class in the build string: " .. tostring(file) .. "." end
    local steps = {}
    for tok in body:gmatch("[^%.]+") do
        local n, e, c = tok:match("^(%d+)~?(%d*)x?(%d*)$")
        if not n then return nil, "The build string is damaged." end
        n, e, c = tonumber(n), tonumber(e), tonumber(c) or 1
        if c < 1 or c > 100 or #steps + c > 200 then return nil, "The build string is damaged." end
        for _ = 1, c do steps[#steps + 1] = { n = n, e = e } end
    end
    return file, name, steps
end

-- Imports text: opens the build for its class and saves it under its name.
-- Returns class, saved name; or nil, reason.
function TC.ImportBuild(text)
    local file, name, steps = TC.Import(text)
    if not file then return nil, name end
    local p = TC.Plan(file)
    p.steps = steps
    local saveAs = TC.FreeName(file, name)
    TC.SaveBuild(file, saveAs)
    return file, saveAs
end

-- The build starts with the talents you have now, top of the tree first.
function TC.CopyCurrent(T, live)
    local st = NewState()
    for _, id in ipairs(T.order) do
        local L = live and live[id]
        local n = T.nodes[id]
        if L and n and not n.free then
            for _ = 1, L.rank or 0 do
                if TC.CanAdd(T, st, id, L.entry) then Push(T, st, id, L.entry) end
            end
        end
    end
    TC.Plan(TC.PlayerClass()).steps = st.steps
    return #st.steps
end

-- How many picks of the build st your live talents already cover, step by step.
-- done[i] = true when step i is learned; returns done, index of the next step.
function TC.Progress(st, live)
    local done, count, nextIndex = {}, {}, nil
    for i, s in ipairs(st.steps) do
        count[s.n] = (count[s.n] or 0) + 1
        local L = live and live[s.n]
        done[i] = L and (L.rank or 0) >= count[s.n] or false
        if not done[i] and not nextIndex then nextIndex = i end
    end
    return done, nextIndex
end

-------------------------------------------------------------------------------
--  Learning the build
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")
local waitingCombat = false
local onLearned -- the page repaints through this

function TC.SetOnLearned(fn) onLearned = fn end

local function Commit(configID)
    local ok
    if C_ClassTalents and C_ClassTalents.CommitConfig then
        local saved
        if C_ClassTalents.GetLastSelectedSavedConfigID and C_SpecializationInfo then
            local specIndex = Call(C_SpecializationInfo.GetSpecialization)
            local specID = specIndex and specIndex > 0 and Call(C_SpecializationInfo.GetSpecializationInfo, specIndex)
            saved = specID and Call(C_ClassTalents.GetLastSelectedSavedConfigID, specID)
        end
        ok = Call(C_ClassTalents.CommitConfig, saved)
    end
    if not ok and C_Traits.CommitConfig then ok = Call(C_Traits.CommitConfig, configID) end
    return ok
end

-- Buys the next planned ranks with the points you have, then applies them.
-- manual: from the button or /talentcalc learn (reports more).
function TC.LearnPlanned(manual)
    if InCombatLockdown() then
        waitingCombat = true
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        if manual then TC.Print("your talents will be learned after combat.") end
        return
    end
    local file = TC.PlayerClass()
    local plan = TC.DB().plans[file]
    if not plan or #(plan.steps or EMPTY) == 0 then
        if manual then TC.Print("there is no build for " .. TC.ClassColored(file) .. " yet.") end
        return
    end
    local T, live, configID, trees = TC.ScanLive()
    if T then Dedupe(T, live); AssignTiers(T, live) end
    if not T then
        if manual then TC.Print("the talent tree cannot be read right now.") end
        return
    end
    if C_Traits.ConfigHasStagedChanges and Call(C_Traits.ConfigHasStagedChanges, configID) then
        TC.Print("the talent window has changes that are not applied yet. Apply or undo them, then press Learn Now.")
        return
    end

    local st = TC.Evaluate(T, plan.steps)
    local need, learned, blocked = {}, {}, nil
    for _, s in ipairs(st.steps) do
        need[s.n] = (need[s.n] or 0) + 1
        local L = live[s.n] or { rank = 0 }
        live[s.n] = L
        if (L.rank or 0) < need[s.n] then
            local n = T.nodes[s.n]
            -- Enough points for it?
            local q = Currencies(configID, trees)
            local afford = true
            for _, c in ipairs(n.cost) do
                local have = c.cur and q[c.cur] or q.all
                if (have or 0) < c.amount then afford = false end
            end
            if not afford then break end
            local ok
            if n.choice and (L.rank or 0) == 0 and C_Traits.SetSelection then
                ok = Call(C_Traits.SetSelection, configID, s.n, s.e)
            else
                ok = Call(C_Traits.PurchaseRank, configID, s.n)
            end
            if not ok then blocked = n; break end
            L.rank = (L.rank or 0) + 1
            local e = TC.EntryOf(n, s.e)
            learned[#learned + 1] = string.format("%s (%d/%d)", e.name, L.rank, TC.NodeMax(n, s.e))
        end
    end

    if #learned > 0 then
        if Commit(configID) then
            TC.Print("learned " .. table.concat(learned, ", ") .. ".")
        else
            TC.Print("the talents are picked but could not be applied. Open the talent window and press Apply Changes.")
        end
    elseif manual and not blocked then
        TC.Print("nothing to learn now: no free talent points, or the build is already learned.")
    end
    if blocked then
        local e = TC.EntryOf(blocked, nil)
        TC.Print("the next talent of the build, " .. e.name .. ", cannot be learned yet: the game says its "
            .. "requirements are not met. Check the order of the build.")
    end
    if onLearned then onLearned() end
end

local function AutoLearn()
    if TC.CDB().autoLearn then TC.LearnPlanned(false) end
end

events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        TC.DB(); TC.CDB()
        C_Timer.After(3, function() TC.ScanLive(); AutoLearn() end)
    elseif event == "PLAYER_LEVEL_UP" then
        -- The new point arrives a moment after the event.
        C_Timer.After(1, AutoLearn)
        C_Timer.After(3, AutoLearn)
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if waitingCombat then
            waitingCombat = false
            C_Timer.After(0.5, function() TC.LearnPlanned(false) end)
        end
    end
end)
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LEVEL_UP")

-------------------------------------------------------------------------------
--  /talentcalc debug: what the client gives (for fixing the calculator)
-------------------------------------------------------------------------------
function TC.Debug()
    local P = TC.Print
    local configID, trees = TC.LiveConfig()
    P("configID = " .. tostring(configID) .. ", trees = " .. (trees and table.concat(trees, ",") or "none"))
    if configID then
        local q = Currencies(configID, trees)
        P("unspent = " .. tostring(q.all) .. ", earned = " .. tostring(q.earned)
            .. ", level = " .. tostring(UnitLevel("player")) .. ", first talent level = " .. TC.FirstLevel()
            .. " (legacy " .. tostring(TC.LegacyFirstLevel()) .. "), max points = " .. TC.MaxPoints()
            .. ", max level = " .. TC.MaxLevel())
        local T = Scan(configID, trees)
        if T then
            local edges, gates, free, choice = 0, 0, 0, 0
            local types = {}
            for _, n in pairs(T.nodes) do
                for _, p in ipairs(n.parents) do
                    edges = edges + 1
                    local k = p.req and "required" or (p.gating and "sufficient" or "visual")
                    types[k] = (types[k] or 0) + 1
                end
                gates = gates + #n.gates
                if n.free then free = free + 1 end
                if n.choice then choice = choice + 1 end
            end
            local tl = {}
            for k, v in pairs(types) do tl[#tl + 1] = k .. " " .. v end
            P(string.format("nodes = %d, arrows = %d (%s), gated nodes = %d, free = %d, choice = %d",
                #T.order, edges, table.concat(tl, ", "), gates, free, choice))
            -- Distinct positions, for the layout.
            local xs, ys, sx, sy = {}, {}, {}, {}
            for _, n in pairs(T.nodes) do
                if not sx[n.x] then sx[n.x] = true; xs[#xs + 1] = n.x end
                if not sy[n.y] then sy[n.y] = true; ys[#ys + 1] = n.y end
            end
            table.sort(xs); table.sort(ys)
            P("x = " .. table.concat(xs, " "))
            P("y = " .. table.concat(ys, " "))
        else
            P("the live tree has no readable nodes.")
        end
    end
    local db = TC.DB()
    local saved = {}
    for file, T in pairs(db.trees) do saved[#saved + 1] = file .. " (" .. tostring(T.source) .. ")" end
    P("saved trees: " .. (#saved > 0 and table.concat(saved, ", ") or "none"))
    P("auto-learn = " .. tostring(TC.CDB().autoLearn))
end
