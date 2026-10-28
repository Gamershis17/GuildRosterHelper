-- GuildRosterHelper v2.0.4 -- Front Desk version
-- Tabs: Roster | Professions | Requests, in classic WoW panel style.
-- Slash commands: /grh  or  /guildroster
-- Roster: click a name to whisper, Shift-click to invite.
-- Professions: guildmates running the addon share their recipes when
--   they open a profession window; lists fill in from that shared data.
--   The game never exposes other players' recipes, so members without
--   the addon simply don't appear in the profession lists.
-- Requests: the Request button whispers the crafter and, if they run
--   the addon, drops the request into their Requests tab.

local ADDON_NAME = "GuildRosterHelper"
local PREFIX = "GRH1"
local ROW_HEIGHT = 20
local VISIBLE_ROWS = 15
local PROF_ROWS = 16
local REQ_ROWS = 19

local PROFESSIONS = {
    "Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering",
    "First Aid", "Fishing", "Herbalism", "Jewelcrafting", "Leatherworking",
    "Mining", "Skinning", "Tailoring",
}

-- ---------- saved data ----------

local function DB()
    GuildRosterHelperDB = GuildRosterHelperDB or {}
    local db = GuildRosterHelperDB
    db.myProfessions = db.myProfessions or {}
    db.guildData = db.guildData or {}
    db.requests = db.requests or {}
    return db
end

-- ---------- helpers ----------

local function GetClassColor(classFile)
    local c = classFile and RAID_CLASS_COLORS[classFile]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function ShortName(fullName)
    if not fullName then return "" end
    local dash = fullName:find("-")
    if dash then return fullName:sub(1, dash - 1) end
    return fullName
end

local function split(str, delim)
    local out = {}
    if not str or str == "" then return out end
    for part in string.gmatch(str, "([^" .. delim .. "]+)") do
        out[#out + 1] = part
    end
    return out
end

-- split a "D|idx|total|chunk" wrapper without breaking on "|" inside chunk
local function ParseChunk(msg)
    local a = msg:find("|", 1, true)
    if not a then return nil end
    local b = msg:find("|", a + 1, true)
    if not b then return nil end
    local c = msg:find("|", b + 1, true)
    if not c then return nil end
    return tonumber(msg:sub(a + 1, b - 1)), tonumber(msg:sub(b + 1, c - 1)),
        msg:sub(c + 1)
end

-- split a "P|prof|skill|recipes" payload
local function ParsePayload(p)
    local a = p:find("|", 1, true)
    if not a then return nil end
    local b = p:find("|", a + 1, true)
    if not b then return nil end
    local c = p:find("|", b + 1, true)
    if not c then return nil end
    return p:sub(1, a - 1), p:sub(a + 1, b - 1), p:sub(b + 1, c - 1),
        p:sub(c + 1)
end

local function SendAddon(target, msg, channel)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, channel, target)
    elseif SendAddonMessage then
        pcall(SendAddonMessage, PREFIX, msg, channel, target)
    end
end

local function SendGuild(msg)
    SendAddon(nil, msg, "GUILD")
end

-- The window frame is created below; forward-declare it so the slash
-- command can be registered up here, before any UI code runs. If the
-- window code ever fails, /grh still answers instead of going silent,
-- and any error inside the handler prints in chat.
local frame

SLASH_GUILDROSTERHELPER1 = "/grh"
SLASH_GUILDROSTERHELPER2 = "/guildroster"
SlashCmdList["GUILDROSTERHELPER"] = function()
    if not frame then
        print("Guild Roster Helper: window is not ready yet.")
        return
    end
    local ok, err = pcall(function()
        if frame:IsShown() then
            frame:Hide()
        else
            GuildRoster()
            RefreshRoster()
            frame:Show()
        end
    end)
    if not ok then
        print("Guild Roster Helper error: " .. tostring(err))
    end
end

-- ---------- main window ----------

frame = CreateFrame("Frame", "GuildRosterHelperFrame", UIParent, "BackdropTemplate")
frame:SetSize(780, 520)
frame:SetPoint("CENTER")
frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
})
frame:SetBackdropColor(0, 0, 0, 0.9)
frame:EnableMouse(true)
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local db = DB()
    local point, _, _, x, y = self:GetPoint(1)
    db.point, db.x, db.y = point, x, y
end)
frame:Hide()

local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
closeBtn:SetScript("OnClick", function() frame:Hide() end)

local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
titleText:SetPoint("TOP", frame, "TOP", 0, -10)
titleText:SetText("Guild Roster Helper")

-- ---------- tabs (real WoW tab buttons) ----------

local rosterPanel = CreateFrame("Frame", nil, frame)
local profPanel = CreateFrame("Frame", nil, frame)
local reqPanel = CreateFrame("Frame", nil, frame)

local function ShowTab(id)
    pcall(PanelTemplates_SetTab, frame, id)
    rosterPanel:SetShown(id == 1)
    profPanel:SetShown(id == 2)
    reqPanel:SetShown(id == 3)
    if id == 2 then RefreshProfList() RefreshDetail() end
    if id == 3 then RefreshReqList() end
end

local tabX = 16
for id, label in ipairs({ "Roster", "Professions", "Requests" }) do
    local tab = CreateFrame("Button", "GuildRosterHelperFrameTab" .. id, frame,
        "CharacterFrameTabButtonTemplate")
    tab:SetID(id)
    tab:SetText(label)
    tab:SetPoint("TOPLEFT", frame, "TOPLEFT", tabX, -32)
    if not pcall(PanelTemplates_TabResize, tab, 0) then tab:SetWidth(120) end
    tab:SetScript("OnClick", function(self) ShowTab(self:GetID()) end)
    tabX = tabX + 126
end
pcall(PanelTemplates_SetNumTabs, frame, 3)

-- ---------- roster tab ----------

local members = {}
local shown = {}
local sortMode = "level"
local onlineOnly = false
local searchText = ""
local RosterOnline = {}

local statsText = rosterPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
statsText:SetPoint("TOP", frame, "TOP", 0, -70)
statsText:SetText("Loading roster...")

local classText = rosterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
classText:SetPoint("TOP", frame, "TOP", 0, -88)
classText:SetJustifyH("CENTER")
classText:SetWidth(740)
classText:SetHeight(28)
classText:SetWordWrap(true)

local searchLabel = rosterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
searchLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -124)
searchLabel:SetText("Search:")

local searchBox = CreateFrame("EditBox", nil, rosterPanel, "InputBoxTemplate")
searchBox:SetSize(200, 26)
searchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 70, -120)
searchBox:SetAutoFocus(false)
searchBox:SetScript("OnTextChanged", function(self)
    searchText = self:GetText() or ""
    ApplyFilter()
end)
searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

local onlineBtn = CreateFrame("Button", nil, rosterPanel, "UIPanelButtonTemplate")
onlineBtn:SetSize(110, 26)
onlineBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -120)
onlineBtn:SetText("Online only: Off")
onlineBtn:SetScript("OnClick", function(self)
    onlineOnly = not onlineOnly
    self:SetText(onlineOnly and "Online only: On" or "Online only: Off")
    ApplyFilter()
end)

local function MakeSortButton(label, mode, x)
    local b = CreateFrame("Button", nil, rosterPanel, "UIPanelButtonTemplate")
    b:SetSize(70, 22)
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -156)
    b:SetText(label)
    b:SetScript("OnClick", function()
        sortMode = mode
        ApplyFilter()
    end)
    return b
end
MakeSortButton("Name", "name", 16)
MakeSortButton("Level", "level", 90)
MakeSortButton("Class", "class", 164)

local refreshBtn = CreateFrame("Button", nil, rosterPanel, "UIPanelButtonTemplate")
refreshBtn:SetSize(90, 22)
refreshBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -156)
refreshBtn:SetText("Refresh")
refreshBtn:SetScript("OnClick", function()
    GuildRoster()
    RefreshRoster()
end)

local hintText = rosterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hintText:SetPoint("BOTTOM", frame, "BOTTOM", 0, 14)
hintText:SetText("Click a name to whisper  |  Shift-click to invite")

local scroll = CreateFrame("ScrollFrame", "GuildRosterHelperScroll", rosterPanel,
    "FauxScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -184)
scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 34)
scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, UpdateList)
end)

local rows = {}
for i = 1, VISIBLE_ROWS do
    local row = CreateFrame("Button", nil, rosterPanel)
    row:SetSize(700, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

    row.levelText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.levelText:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.levelText:SetWidth(28)
    row.levelText:SetJustifyH("CENTER")

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.nameText:SetPoint("LEFT", row, "LEFT", 32, 0)
    row.nameText:SetWidth(150)
    row.nameText:SetJustifyH("LEFT")

    row.classText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.classText:SetPoint("LEFT", row, "LEFT", 186, 0)
    row.classText:SetWidth(95)
    row.classText:SetJustifyH("LEFT")

    row.zoneText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.zoneText:SetPoint("LEFT", row, "LEFT", 285, 0)
    row.zoneText:SetWidth(140)
    row.zoneText:SetJustifyH("LEFT")

    row.rankText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.rankText:SetPoint("LEFT", row, "LEFT", 429, 0)
    row.rankText:SetWidth(260)
    row.rankText:SetJustifyH("LEFT")

    row:SetScript("OnClick", function(self)
        local m = self.member
        if not m then return end
        if IsShiftKeyDown() then
            InviteUnit(m.short)
        else
            ChatFrame_OpenChat("/w " .. m.short .. " ", DEFAULT_CHAT_FRAME)
        end
    end)
    row:SetScript("OnEnter", function(self)
        local m = self.member
        if not m then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(m.short, 1, 1, 1)
        GameTooltip:AddLine("Level " .. m.level .. " " .. m.class, 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Rank: " .. m.rank, 0.8, 0.8, 0.8)
        if m.online then
            GameTooltip:AddLine("Zone: " .. m.zone, 0.8, 0.8, 0.8)
        else
            GameTooltip:AddLine("Offline", 0.8, 0.8, 0.8)
        end
        if m.note ~= "" then
            GameTooltip:AddLine("Note: " .. m.note, 0.6, 0.8, 1)
        end
        if m.officernote ~= "" then
            GameTooltip:AddLine("Officer note: " .. m.officernote, 1, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    rows[i] = row
end

function UpdateList()
    local total = #shown
    FauxScrollFrame_Update(scroll, total, VISIBLE_ROWS, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(scroll)
    for i = 1, VISIBLE_ROWS do
        local row = rows[i]
        local m = shown[i + offset]
        if m then
            row.member = m
            row.levelText:SetText(m.level)
            local r, g, b = GetClassColor(m.classFile)
            row.nameText:SetText(m.short)
            row.nameText:SetTextColor(r, g, b)
            row.classText:SetText(m.class)
            row.rankText:SetText(m.rank)
            if m.online then
                row.zoneText:SetText(m.zone)
                row.nameText:SetAlpha(1)
                row.classText:SetAlpha(1)
                row.zoneText:SetAlpha(1)
                row.rankText:SetAlpha(1)
            else
                row.zoneText:SetText("Offline")
                row.nameText:SetAlpha(0.55)
                row.classText:SetAlpha(0.55)
                row.zoneText:SetAlpha(0.55)
                row.rankText:SetAlpha(0.55)
            end
            row:Show()
        else
            row.member = nil
            row:Hide()
        end
    end

    local online = 0
    for _, m in ipairs(members) do
        if m.online then online = online + 1 end
    end
    local guildName = GetGuildInfo("player") or "No guild"
    statsText:SetText(guildName .. "  |  Online: " .. online .. " / " .. #members .. "  |  Showing: " .. total)

    local counts, names = {}, {}
    for _, m in ipairs(members) do
        if m.online then
            local key = m.classFile or m.class
            counts[key] = (counts[key] or 0) + 1
            names[key] = m.class
        end
    end
    local order = {}
    for key in pairs(counts) do order[#order + 1] = key end
    table.sort(order, function(a, b) return counts[a] > counts[b] end)
    local parts = {}
    for _, key in ipairs(order) do
        local r, g, b = GetClassColor(key)
        parts[#parts + 1] = string.format("|cff%02x%02x%02x%s: %d|r",
            r * 255, g * 255, b * 255, names[key], counts[key])
    end
    classText:SetText(table.concat(parts, "   "))
end

function ApplyFilter()
    wipe(shown)
    local q = searchText:lower()
    for _, m in ipairs(members) do
        if (not onlineOnly or m.online) and (q == "" or
            m.short:lower():find(q, 1, true) or
            m.class:lower():find(q, 1, true) or
            m.zone:lower():find(q, 1, true) or
            m.rank:lower():find(q, 1, true)) then
            shown[#shown + 1] = m
        end
    end
    if sortMode == "name" then
        table.sort(shown, function(a, b) return a.short < b.short end)
    elseif sortMode == "class" then
        table.sort(shown, function(a, b)
            if a.class == b.class then return a.short < b.short end
            return a.class < b.class
        end)
    else
        table.sort(shown, function(a, b)
            if a.online ~= b.online then return a.online end
            if a.level == b.level then return a.short < b.short end
            return a.level > b.level
        end)
    end
    UpdateList()
end

function RefreshRoster()
    wipe(members)
    wipe(RosterOnline)
    local rosterSet = {}
    local total = GetNumGuildMembers()
    for i = 1, total do
        local name, rank, rankIndex, level, class, zone, note, officernote, online, status, classFile =
            GetGuildRosterInfo(i)
        if name then
            local short = ShortName(name)
            members[#members + 1] = {
                name = name,
                short = short,
                rank = rank or "",
                level = level or 0,
                class = class or "",
                classFile = classFile,
                zone = zone or "",
                note = note or "",
                officernote = officernote or "",
                online = online,
            }
            rosterSet[short] = true
            RosterOnline[short] = online
        end
    end
    -- drop shared profession data for people who left the guild
    local db = DB()
    for pname in pairs(db.guildData) do
        if not rosterSet[pname] then db.guildData[pname] = nil end
    end
    ApplyFilter()
end

-- ---------- professions tab ----------

local selectedProf = "Enchanting"
local viewMode = "all" -- "all" or "players"
local profSearchText = ""
local profSortMode = "alpha" -- "alpha" or "count"
local sortCraftersBySkill = true
local profShown = {}
local selectedRecipe = nil
local selectedPlayer = nil
local selectedCrafter = nil
local lastBroadcast = 0
local lastScan = {}
local chunkBuf = {}

-- Midnight (retail) replaced the classic tradeskill API, so recipe
-- scanning is Classic-only. Roster and requests work everywhere.
local HAS_CLASSIC_TRADE = GetTradeSkillLine ~= nil and GetNumTradeSkills ~= nil

local profHeader = profPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
profHeader:SetPoint("TOP", frame, "TOP", 0, -70)
profHeader:SetText("Pick a profession below")

local profSearchLabel = profPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
profSearchLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -98)
profSearchLabel:SetText("Search:")

local profSearchBox = CreateFrame("EditBox", nil, profPanel, "InputBoxTemplate")
profSearchBox:SetSize(200, 26)
profSearchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 70, -94)
profSearchBox:SetAutoFocus(false)
profSearchBox:SetScript("OnTextChanged", function(self)
    profSearchText = self:GetText() or ""
    RefreshProfList()
end)
profSearchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
profSearchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

local azBtn = CreateFrame("Button", nil, profPanel, "UIPanelButtonTemplate")
azBtn:SetSize(50, 26)
azBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 280, -94)
azBtn:SetText("A-Z")
azBtn:SetScript("OnClick", function(self)
    if profSortMode == "alpha" then
        profSortMode = "count"
        self:SetText("Most")
    else
        profSortMode = "alpha"
        self:SetText("A-Z")
    end
    RefreshProfList()
end)

local profAllBtn = CreateFrame("Button", nil, profPanel, "UIPanelButtonTemplate")
profAllBtn:SetSize(50, 26)
profAllBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 340, -94)
profAllBtn:SetText("All")
profAllBtn:SetScript("OnClick", function()
    profSearchBox:SetText("")
    profSearchText = ""
    RefreshProfList()
end)

local modeBtn = CreateFrame("Button", nil, profPanel, "UIPanelButtonTemplate")
modeBtn:SetSize(104, 26)
modeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -94)
modeBtn:SetText("View: All")
modeBtn:SetScript("OnClick", function(self)
    if viewMode == "all" then
        viewMode = "players"
        self:SetText("View: Players")
    else
        viewMode = "all"
        self:SetText("View: All")
    end
    selectedRecipe = nil
    selectedPlayer = nil
    selectedCrafter = nil
    RefreshProfList()
    RefreshDetail()
end)

local profScroll = CreateFrame("ScrollFrame", "GuildRosterHelperProfScroll", profPanel,
    "FauxScrollFrameTemplate")
profScroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -126)
profScroll:SetSize(366, 322)
profScroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, UpdateProfList)
end)

local profRows = {}
for i = 1, PROF_ROWS do
    local row = CreateFrame("Button", nil, profPanel)
    row:SetSize(340, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", profScroll, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.nameText:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.nameText:SetWidth(300)
    row.nameText:SetJustifyH("LEFT")

    row.countText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.countText:SetPoint("LEFT", row, "LEFT", 310, 0)
    row.countText:SetWidth(30)
    row.countText:SetJustifyH("RIGHT")

    row:SetScript("OnClick", function(self)
        if viewMode == "all" then
            selectedRecipe = self.itemName
        else
            selectedPlayer = self.itemName
        end
        selectedCrafter = nil
        RefreshDetail()
    end)
    profRows[i] = row
end

-- detail pane (WoW tooltip look)
local detailPane = CreateFrame("Frame", nil, profPanel, "BackdropTemplate")
detailPane:SetPoint("TOPLEFT", frame, "TOPLEFT", 396, -126)
detailPane:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 72)
detailPane:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
detailPane:SetBackdropColor(0, 0, 0, 0.9)

local detailTitle = detailPane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
detailTitle:SetPoint("TOPLEFT", detailPane, "TOPLEFT", 16, -10)
detailTitle:SetWidth(240)
detailTitle:SetJustifyH("LEFT")
detailTitle:SetText("Select a recipe")

local sortCraftBtn = CreateFrame("Button", nil, detailPane, "UIPanelButtonTemplate")
sortCraftBtn:SetSize(96, 24)
sortCraftBtn:SetPoint("TOPRIGHT", detailPane, "TOPRIGHT", -8, -6)
sortCraftBtn:SetText("Sort: Skill")
sortCraftBtn:SetScript("OnClick", function(self)
    sortCraftersBySkill = not sortCraftersBySkill
    self:SetText(sortCraftersBySkill and "Sort: Skill" or "Sort: Name")
    RefreshDetail()
end)

local detailSub = detailPane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
detailSub:SetPoint("TOPLEFT", detailPane, "TOPLEFT", 16, -34)
detailSub:SetWidth(340)
detailSub:SetJustifyH("LEFT")
detailSub:SetText("")

local detailLines = {}
for i = 1, 6 do
    local t = detailPane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t:SetPoint("TOPLEFT", detailPane, "TOPLEFT", 16, -58 - (i - 1) * 16)
    t:SetWidth(340)
    t:SetJustifyH("LEFT")
    detailLines[i] = t
end

local crafterBtns = {}
for i = 1, 5 do
    local b = CreateFrame("Button", nil, detailPane)
    b:SetSize(340, 20)
    b:SetPoint("TOPLEFT", detailPane, "TOPLEFT", 16, -158 - (i - 1) * 22)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    b.dot = b:CreateTexture(nil, "OVERLAY")
    b.dot:SetSize(14, 14)
    b.dot:SetPoint("LEFT", b, "LEFT", 0, 0)
    b.dot:SetTexture("Interface\\FriendsFrame\\StatusIcon-Online")
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("LEFT", b, "LEFT", 20, 0)
    b.text:SetWidth(300)
    b.text:SetJustifyH("LEFT")
    b:SetScript("OnClick", function(self)
        selectedCrafter = self.crafterName
        RefreshDetail()
    end)
    crafterBtns[i] = b
end

local requestBtn = CreateFrame("Button", nil, detailPane, "UIPanelButtonTemplate")
requestBtn:SetSize(96, 24)
requestBtn:SetPoint("TOPLEFT", detailPane, "TOPLEFT", 16, -272)
requestBtn:SetText("Request")
requestBtn:SetScript("OnClick", function()
    if not selectedCrafter or not selectedRecipe then return end
    SendAddon(selectedCrafter, "R|" .. selectedRecipe .. "|" .. selectedProf, "WHISPER")
    ChatFrame_OpenChat("/w " .. selectedCrafter .. " Can you craft " .. selectedRecipe .. "? ", DEFAULT_CHAT_FRAME)
end)

local whisperBtn = CreateFrame("Button", nil, detailPane, "UIPanelButtonTemplate")
whisperBtn:SetSize(96, 24)
whisperBtn:SetPoint("TOPLEFT", detailPane, "TOPLEFT", 16, -272)
whisperBtn:SetText("Whisper")
whisperBtn:SetScript("OnClick", function()
    if not selectedPlayer then return end
    ChatFrame_OpenChat("/w " .. selectedPlayer .. " ", DEFAULT_CHAT_FRAME)
end)

local detailNote = detailPane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
detailNote:SetPoint("TOPLEFT", detailPane, "TOPLEFT", 16, -306)
detailNote:SetWidth(340)
detailNote:SetJustifyH("LEFT")
detailNote:SetText("Recipes appear as guildmates with the addon share them.")
detailNote:SetTextColor(0.55, 0.55, 0.55)

-- profession buttons, bottom rows
local function MakeProfButton(label, x, y, w)
    local b = CreateFrame("Button", nil, profPanel, "UIPanelButtonTemplate")
    b:SetSize(w, 24)
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
    b:SetText(label)
    b:SetScript("OnClick", function()
        selectedProf = label
        selectedRecipe = nil
        selectedCrafter = nil
        RefreshProfList()
        RefreshDetail()
    end)
    return b
end

local row1 = { { "Alchemy", 87, 85 }, { "Blacksmithing", 178, 115 },
    { "Cooking", 299, 85 }, { "Enchanting", 390, 100 },
    { "Engineering", 496, 100 }, { "First Aid", 602, 90 } }
for _, p in ipairs(row1) do MakeProfButton(p[1], p[2], -454, p[3]) end
local row2 = { { "Fishing", 32, 85 }, { "Herbalism", 123, 95 },
    { "Jewelcrafting", 224, 120 }, { "Leatherworking", 350, 120 },
    { "Mining", 476, 80 }, { "Skinning", 562, 90 }, { "Tailoring", 658, 90 } }
for _, p in ipairs(row2) do MakeProfButton(p[1], p[2], -482, p[3]) end

-- ---------- profession data: scan + sync ----------

local function BroadcastProf(profName)
    local db = DB()
    local mine = db.myProfessions[profName]
    if not mine then return end
    local names = {}
    for n in pairs(mine.recipes) do names[#names + 1] = n end
    table.sort(names)
    local payload = "P|" .. profName .. "|" .. (mine.skill or 0) .. "|" .. table.concat(names, ";")
    for i = 1, #payload, 200 do
        SendGuild("D|" .. math.ceil(i / 200) .. "|" .. math.ceil(#payload / 200) .. "|" .. payload:sub(i, i + 199))
    end
    lastBroadcast = GetTime()
end

local function ScanTradeSkill()
    if not GetTradeSkillLine or not GetNumTradeSkills then return end
    local profName = GetTradeSkillLine()
    if not profName then return end
    local now = GetTime()
    if lastScan[profName] and now - lastScan[profName] < 60 then return end
    lastScan[profName] = now
    local n = GetNumTradeSkills()
    if not n then return end
    local recipes = {}
    for i = 1, n do
        local name, skillType = GetTradeSkillInfo(i)
        if name and skillType ~= "header" then
            local reagents = {}
            local nr = (GetTradeSkillNumReagents and GetTradeSkillNumReagents(i)) or 0
            for j = 1, nr do
                local rName, _, rCount = GetTradeSkillReagentInfo and GetTradeSkillReagentInfo(i, j)
                if rName then reagents[#reagents + 1] = { name = rName, count = rCount or 0 } end
            end
            recipes[name] = { reagents = reagents }
        end
    end
    local skill, maxSkill = 0, 0
    local profs = { GetProfessions() }
    for _, idx in ipairs(profs) do
        if idx then
            local ok, pname, _, s, m = pcall(GetProfessionInfo, idx)
            if ok and pname == profName then
                skill, maxSkill = s or 0, m or 0
                break
            end
        end
    end
    local db = DB()
    db.myProfessions[profName] = { skill = skill, max = maxSkill, recipes = recipes }
    BroadcastProf(profName)
    if profPanel:IsShown() then RefreshProfList() RefreshDetail() end
end

-- ---------- profession list + detail ----------

local function CollectCrafters(prof)
    local db = DB()
    local map = {}
    local me = UnitName("player")
    if me then me = ShortName(me) end
    local mine = db.myProfessions[prof]
    if mine then
        for recipe in pairs(mine.recipes) do
            map[recipe] = map[recipe] or {}
            map[recipe][#map[recipe] + 1] = { name = me or "You", skill = mine.skill or 0, online = true }
        end
    end
    for pname, profs in pairs(db.guildData) do
        local entry = profs[prof]
        if entry then
            for recipe in pairs(entry.recipes) do
                map[recipe] = map[recipe] or {}
                map[recipe][#map[recipe] + 1] = { name = pname, skill = entry.skill or 0, online = RosterOnline[pname] }
            end
        end
    end
    return map
end

function RefreshProfList()
    local db = DB()
    wipe(profShown)
    if not HAS_CLASSIC_TRADE then
        profHeader:SetText("Profession sharing needs the Classic client -- roster and requests work here.")
        UpdateProfList()
        return
    end
    if viewMode == "players" then
        local counts = {}
        for pname, profs in pairs(db.guildData) do
            local total = 0
            for _, entry in pairs(profs) do
                for _ in pairs(entry.recipes) do total = total + 1 end
            end
            counts[pname] = total
        end
        local me = UnitName("player")
        if me then
            me = ShortName(me)
            local total = 0
            for _, entry in pairs(db.myProfessions) do
                for _ in pairs(entry.recipes) do total = total + 1 end
            end
            if total > 0 then counts[me] = total end
        end
        local q = profSearchText:lower()
        for pname, total in pairs(counts) do
            if q == "" or pname:lower():find(q, 1, true) then
                profShown[#profShown + 1] = { name = pname, count = total, online = RosterOnline[pname] }
            end
        end
        table.sort(profShown, function(a, b) return a.name < b.name end)
        profHeader:SetText("Guild crafters sharing: " .. #profShown)
    else
        local map = CollectCrafters(selectedProf)
        local q = profSearchText:lower()
        for recipe, crafters in pairs(map) do
            if q == "" or recipe:lower():find(q, 1, true) then
                profShown[#profShown + 1] = { name = recipe, count = #crafters, crafters = crafters }
            end
        end
        if profSortMode == "count" then
            table.sort(profShown, function(a, b)
                if a.count == b.count then return a.name < b.name end
                return a.count > b.count
            end)
        else
            table.sort(profShown, function(a, b) return a.name < b.name end)
        end
        profHeader:SetText(selectedProf .. ": " .. #profShown .. " recipes known in the guild")
    end
    UpdateProfList()
end

function UpdateProfList()
    local total = #profShown
    FauxScrollFrame_Update(profScroll, total, PROF_ROWS, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(profScroll)
    for i = 1, PROF_ROWS do
        local row = profRows[i]
        local item = profShown[i + offset]
        if item then
            row.itemName = item.name
            row.nameText:SetText(item.name)
            row.countText:SetText(item.count)
            if viewMode == "players" then
                if item.online then
                    row.nameText:SetTextColor(1, 1, 1)
                else
                    row.nameText:SetTextColor(0.6, 0.6, 0.6)
                end
            else
                if item.name == selectedRecipe then
                    row.nameText:SetTextColor(1, 0.82, 0.25)
                else
                    row.nameText:SetTextColor(0.85, 0.85, 0.85)
                end
            end
            row:Show()
        else
            row.itemName = nil
            row:Hide()
        end
    end
end

function RefreshDetail()
    for _, t in ipairs(detailLines) do t:SetText("") end
    for _, b in ipairs(crafterBtns) do
        b.crafterName = nil
        b:Hide()
    end
    requestBtn:Hide()
    whisperBtn:Hide()
    if viewMode == "players" then
        if not selectedPlayer then
            detailTitle:SetText("Select a player")
            detailSub:SetText("")
            return
        end
        detailTitle:SetText(selectedPlayer)
        local db = DB()
        local me = UnitName("player")
        if me then me = ShortName(me) end
        local profs = nil
        local total = 0
        if selectedPlayer == me then
            profs = db.myProfessions
        elseif db.guildData[selectedPlayer] then
            profs = db.guildData[selectedPlayer]
        end
        if profs then
            for pname, entry in pairs(profs) do
                for _ in pairs(entry.recipes) do total = total + 1 end
            end
        end
        detailSub:SetText(total .. " recipes shared")
        if profs then
            local i = 0
            local names = {}
            for pname in pairs(profs) do names[#names + 1] = pname end
            table.sort(names)
            for _, pname in ipairs(names) do
                i = i + 1
                if i <= 6 then
                    local entry = profs[pname]
                    detailLines[i]:SetText(pname .. "  " .. (entry.skill or 0) .. "/" .. (entry.max or 0))
                end
            end
        end
        whisperBtn:Show()
        return
    end
    -- recipe mode
    if not selectedRecipe then
        detailTitle:SetText("Select a recipe")
        detailSub:SetText("")
        return
    end
    detailTitle:SetText(selectedRecipe)
    local map = CollectCrafters(selectedProf)
    local crafters = map[selectedRecipe] or {}
    detailSub:SetText(#crafters .. " crafter(s) (green dot = online)")
    local db = DB()
    local mine = db.myProfessions[selectedProf]
    local known = mine and mine.recipes[selectedRecipe]
    if known then
        detailLines[1]:SetText("Reagents:")
        local i = 1
        for _, rg in ipairs(known.reagents) do
            i = i + 1
            if i <= 6 then
                detailLines[i]:SetText(rg.count .. " x " .. rg.name)
            end
        end
        if #known.reagents > 5 then
            detailLines[6]:SetText("+ " .. (#known.reagents - 5) .. " more reagents")
        end
    else
        detailLines[1]:SetText("Reagents: ask the crafter")
    end
    if sortCraftersBySkill then
        table.sort(crafters, function(a, b)
            if a.skill == b.skill then return a.name < b.name end
            return a.skill > b.skill
        end)
    else
        table.sort(crafters, function(a, b) return a.name < b.name end)
    end
    for i = 1, 5 do
        local c = crafters[i]
        local b = crafterBtns[i]
        if c then
            b.crafterName = c.name
            b.text:SetText(c.name .. "  " .. c.skill)
            if c.online then
                b.dot:Show()
                b.text:SetTextColor(1, 1, 1)
            else
                b.dot:Hide()
                b.text:SetTextColor(0.6, 0.6, 0.6)
            end
            if c.name == selectedCrafter then
                b.text:SetTextColor(1, 0.82, 0.25)
            end
            b:Show()
        end
    end
    if #crafters > 5 then
        detailLines[6]:SetText("+ " .. (#crafters - 5) .. " more crafters")
    end
    if not selectedCrafter and crafters[1] then
        selectedCrafter = crafters[1].name
    end
    if selectedCrafter then requestBtn:Show() end
end

-- ---------- requests tab ----------

local clearReqBtn = CreateFrame("Button", nil, reqPanel, "UIPanelButtonTemplate")
clearReqBtn:SetSize(90, 22)
clearReqBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -70)
clearReqBtn:SetText("Clear all")
clearReqBtn:SetScript("OnClick", function()
    wipe(DB().requests)
    RefreshReqList()
end)

local reqScroll = CreateFrame("ScrollFrame", "GuildRosterHelperReqScroll", reqPanel,
    "FauxScrollFrameTemplate")
reqScroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -98)
reqScroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 34)
reqScroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, UpdateReqList)
end)

local reqRows = {}
for i = 1, REQ_ROWS do
    local row = CreateFrame("Button", nil, reqPanel)
    row:SetSize(660, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", reqScroll, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.text:SetWidth(640)
    row.text:SetJustifyH("LEFT")

    row:SetScript("OnClick", function(self)
        if self.reqFrom then
            ChatFrame_OpenChat("/w " .. self.reqFrom .. " ", DEFAULT_CHAT_FRAME)
        end
    end)

    local dismiss = CreateFrame("Button", nil, reqPanel, "UIPanelButtonTemplate")
    dismiss:SetSize(40, ROW_HEIGHT)
    dismiss:SetPoint("TOPLEFT", reqScroll, "TOPLEFT", 686, -(i - 1) * ROW_HEIGHT)
    dismiss:SetText("X")
    dismiss:SetScript("OnClick", function(self)
        local db = DB()
        local idx = self.reqIndex
        if idx and db.requests[idx] then
            table.remove(db.requests, idx)
        end
        RefreshReqList()
    end)
    row.dismiss = dismiss

    reqRows[i] = row
end

function RefreshReqList()
    UpdateReqList()
end

function UpdateReqList()
    local db = DB()
    local reqs = db.requests
    local total = #reqs
    FauxScrollFrame_Update(reqScroll, total, REQ_ROWS, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(reqScroll)
    for i = 1, REQ_ROWS do
        local row = reqRows[i]
        -- newest first
        local req = reqs[total - (i + offset) + 1]
        if req then
            row.reqFrom = req.from
            row.text:SetText(req.from .. " wants: " .. req.recipe .. " (" .. req.prof .. ")  [" .. (req.time or "") .. "]")
            row.dismiss.reqIndex = total - (i + offset) + 1
            row:Show()
            row.dismiss:Show()
        else
            row.reqFrom = nil
            row:Hide()
            row.dismiss:Hide()
        end
    end
end

-- ---------- addon message handling ----------

local function OnAddonMessage(prefix, msg, channel, senderFull)
    if prefix ~= PREFIX then return end
    local sender = ShortName(senderFull)
    local me = UnitName("player")
    if me then me = ShortName(me) end
    if sender == me then return end
    if msg == "REQ" then
        if GetTime() - lastBroadcast > 300 then
            for prof in pairs(DB().myProfessions) do BroadcastProf(prof) end
        end
        return
    end
    if msg:sub(1, 2) == "D|" then
        local idx, total, chunk = ParseChunk(msg)
        if not idx or not total or not chunk then return end
        local buf = chunkBuf[sender]
        if not buf or buf.total ~= total or idx == 1 then
            buf = { total = total, parts = {}, got = 0 }
            chunkBuf[sender] = buf
        end
        if not buf.parts[idx] then
            buf.parts[idx] = chunk
            buf.got = buf.got + 1
        end
        if buf.got >= total then
            local payload = table.concat(buf.parts)
            chunkBuf[sender] = nil
            local kind, prof, skill, recipeStr = ParsePayload(payload)
            if kind == "P" and prof then
                local db = DB()
                local recs = {}
                for _, rn in ipairs(split(recipeStr, ";")) do recs[rn] = true end
                db.guildData[sender] = db.guildData[sender] or {}
                db.guildData[sender][prof] = { skill = tonumber(skill) or 0, recipes = recs }
                if profPanel:IsShown() then RefreshProfList() RefreshDetail() end
            end
        end
        return
    end
    if msg:sub(1, 2) == "R|" then
        local a = msg:find("|", 1, true)
        local b = msg:find("|", a + 1, true)
        if not a or not b then return end
        local recipe = msg:sub(a + 1, b - 1)
        local prof = msg:sub(b + 1)
        local db = DB()
        db.requests[#db.requests + 1] = { from = sender, recipe = recipe, prof = prof, time = date("%H:%M") }
        while #db.requests > 30 do table.remove(db.requests, 1) end
        if reqPanel:IsShown() then RefreshReqList() end
        print("Guild Roster Helper: crafting request from " .. sender .. ": " .. recipe .. " (" .. prof .. ")")
        return
    end
end

-- ---------- events + slash command ----------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        local db = DB()
        if db.point then
            frame:ClearAllPoints()
            frame:SetPoint(db.point, UIParent, db.point, db.x, db.y)
        end
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
        elseif RegisterAddonMessagePrefix then
            pcall(RegisterAddonMessagePrefix, PREFIX)
        end
        ShowTab(1)
        print("Guild Roster Helper v2.0.4 loaded. Type /grh to open.")
    elseif event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" then
        if frame:IsShown() then RefreshRoster() end
    elseif event == "TRADE_SKILL_SHOW" then
        ScanTradeSkill()
    elseif event == "CHAT_MSG_ADDON" then
        OnAddonMessage(arg1, arg2, arg3, arg4)
    elseif event == "PLAYER_LOGIN" then
        if C_Timer and C_Timer.After then
            C_Timer.After(30, function() SendGuild("REQ") end)
        end
    end
end)

-- (Slash command is registered near the top of this file, before the
-- window code, so /grh answers even if later UI code ever fails.)
