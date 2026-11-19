-- SpellRankUp: Wird ein höherer Rang eines Zaubers gelernt, ersetzt er den alten Rang auf den Aktionsleisten.
-- Nur Plätze, auf denen gerade ein niedrigerer Rang desselben Zaubers liegt; sonst wird nichts angefasst.
local ADDON, SR = ...
_G.SpellRankUp = SR
local L = SR.L

local NUM_SLOTS = 180 -- alle Aktionsplätze inkl. Haltungs-/Gestaltleisten; leere Plätze werden übersprungen
local PREFIX = "|cff66ccffSpellRankUp|r: "

SR.known = nil   -- [spellID] = true: Zauberbuch beim letzten Prüfen
SR.pending = {}  -- [spellID] = true: neu gelernt, noch nicht auf die Leisten gebracht

function SR.Print(msg)
    (DEFAULT_CHAT_FRAME or { AddMessage = print }):AddMessage(PREFIX .. msg)
end

---------------------------------------------------------------------------------------------------
-- Zauber-Funktionen: je nach Client global (alt) oder in C_Spell/C_SpellBook (neu, z. B. Forever)
---------------------------------------------------------------------------------------------------
local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id)
        if ok and n then return n end
    end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end

-- Rang-Text („Rang 3“) und Rang-Zahl; Zauber ohne Zahl im Rang-Text (z. B. „Volksfähigkeit“) haben keinen Rang
local function SpellRank(id)
    local sub
    if C_Spell and C_Spell.GetSpellSubtext then
        local ok, s = pcall(C_Spell.GetSpellSubtext, id)
        if ok then sub = s end
    end
    if (not sub or sub == "") and GetSpellSubtext then
        local ok, s = pcall(GetSpellSubtext, id)
        if ok then sub = s end
    end
    if not sub or sub == "" then return nil end
    return tonumber(sub:match("%d+")), sub
end

local function PickupSpellAny(id)
    if C_Spell and C_Spell.PickupSpell then return C_Spell.PickupSpell(id) end
    if PickupSpell then return PickupSpell(id) end
end

-- Alle Zauber im Zauberbuch des Spielers (Begleiter-Zauber nicht)
local function ReadSpellBook()
    local set, count = {}, 0
    local function add(id)
        if type(id) == "number" and id > 0 and not set[id] then set[id] = true; count = count + 1 end
    end
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemInfo then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell or 1
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() or 0 do
            local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
            if info then
                for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
                    if item and item.itemType == spellType then add(item.spellID or item.actionID) end
                end
            end
        end
    elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemInfo then
        for tab = 1, GetNumSpellTabs() do
            local _, _, offset, num = GetSpellTabInfo(tab)
            for i = offset + 1, offset + num do
                local kind, id = GetSpellBookItemInfo(i, BOOKTYPE_SPELL or "spell")
                if kind == "SPELL" then add(id) end
            end
        end
    end
    return set, count
end

---------------------------------------------------------------------------------------------------
-- Ersetzen
---------------------------------------------------------------------------------------------------
-- Alle Plätze, auf denen ein niedrigerer Rang von newID liegt
function SR.SlotsFor(newID)
    local name = SpellName(newID)
    local rank = SpellRank(newID)
    if not name or not rank then return {} end
    local slots = {}
    for slot = 1, NUM_SLOTS do
        if HasAction(slot) then
            local kind, id = GetActionInfo(slot)
            if kind == "spell" and id ~= newID and SpellName(id) == name then
                local old = SpellRank(id)
                if not old or old < rank then slots[#slots + 1] = slot end
            end
        end
    end
    return slots
end

-- Bringt alle neu gelernten Ränge auf die Leisten. Im Kampf oder mit etwas am Mauszeiger: später.
function SR.Process()
    if not next(SR.pending) then return end
    if not SR.db.enabled then wipe(SR.pending) return end
    if InCombatLockdown() then
        if not SR.waitCombat then
            SR.waitCombat = true
            SR.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
            SR.Print(L["Im Kampf – die Aktionsleiste wird nach dem Kampf aktualisiert."])
        end
        return
    end
    if GetCursorInfo() then
        if not SR.waitCursor then
            SR.waitCursor = true
            C_Timer.After(1, function() SR.waitCursor = nil; SR.Process() end)
        end
        return
    end
    -- niedrigere Ränge zuerst, damit beim Lernen mehrerer Ränge auf einmal der höchste übrig bleibt
    local ids = {}
    for id in pairs(SR.pending) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return (SpellRank(a) or 0) < (SpellRank(b) or 0) end)
    wipe(SR.pending)
    for _, id in ipairs(ids) do
        local done = 0
        for _, slot in ipairs(SR.SlotsFor(id)) do
            ClearCursor()
            PickupSpellAny(id)
            if GetCursorInfo() then
                PlaceAction(slot)
                done = done + 1
            end
            ClearCursor()
        end
        if done > 0 then
            local _, sub = SpellRank(id)
            SR.Print(L["%s (%s) liegt jetzt auf der Aktionsleiste (%d×)."]:format(SpellName(id), sub, done))
        end
    end
end

-- Zauberbuch mit dem letzten Stand vergleichen; neue Zauber vormerken
function SR.Check()
    SR.checkQueued = nil
    local now, count = ReadSpellBook()
    if count == 0 then return end -- Zauberbuch (noch) nicht geladen
    if SR.known then
        for id in pairs(now) do
            if not SR.known[id] then SR.pending[id] = true end
        end
    end
    SR.known = now
    SR.Process()
end

local function QueueCheck()
    if SR.checkQueued then return end
    SR.checkQueued = true
    C_Timer.After(0.5, SR.Check)
end

---------------------------------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
SR.frame = frame
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        SpellRankUpDB = SpellRankUpDB or {}
        SR.db = SpellRankUpDB
        if SR.db.enabled == nil then SR.db.enabled = true end
    elseif event == "PLAYER_LOGIN" then
        -- Ausgangsstand: was beim Einloggen schon bekannt ist, gilt nicht als neu gelernt
        local now, count = ReadSpellBook()
        if count > 0 then SR.known = now end
        self:RegisterEvent("SPELLS_CHANGED")
        self:RegisterEvent("LEARNED_SPELL_IN_TAB")
        self:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE")
    elseif event == "LEARNED_SPELL_IN_TAB" or event == "LEARNED_SPELL_IN_SKILL_LINE" then
        if type(arg1) == "number" then SR.pending[arg1] = true end
        QueueCheck()
    elseif event == "SPELLS_CHANGED" then
        QueueCheck()
    elseif event == "PLAYER_REGEN_ENABLED" then
        SR.waitCombat = nil
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        SR.Process()
    end
end)

---------------------------------------------------------------------------------------------------
-- /spellrankup
---------------------------------------------------------------------------------------------------
local function Status()
    SR.Print(SR.db.enabled and L["An: Neu gelernte Ränge ersetzen den alten Rang auf der Aktionsleiste."]
        or L["Aus: Die Aktionsleiste bleibt, wie sie ist."])
end

SLASH_SPELLRANKUP1 = "/spellrankup"
SLASH_SPELLRANKUP2 = "/sru"
SlashCmdList.SPELLRANKUP = function(msg)
    msg = (msg or ""):lower():match("^%s*(%S*)")
    if msg == "on" then SR.db.enabled = true; Status()
    elseif msg == "off" then SR.db.enabled = false; wipe(SR.pending); Status()
    elseif msg == "" or msg == "status" then Status(); SR.Print(L["Befehle: /spellrankup on | off"])
    else SR.Print(L["Befehle: /spellrankup on | off"]) end
end
