-- SpellRankUp: Flug-Animation wie beim Lernen neuer Zauber in Retail. Das Zaubersymbol erscheint am Lehrer
-- (sonst in der Bildschirmmitte), fliegt zum Knopf auf der Aktionsleiste und lässt ihn kurz aufleuchten.
-- Rein optisch: läuft über eigene, nicht geschützte Frames und funktioniert deshalb auch im Kampf.
local _, SR = ...

local POP, HOLD, FLY, FLASH = 0.15, 0.35, 0.55, 0.6 -- Sekunden: Auftauchen, Stehen, Flug, Aufleuchten
local STAGGER = 0.12                                -- Abstand zwischen mehreren Flügen
local START_SIZE, END_SIZE = 52, 36

local function SpellTexture(id)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, id)
        if ok and tex then return tex end
    end
    if GetSpellTexture then return GetSpellTexture(id) end
end

-- Mittelpunkt eines Frames in UIParent-Koordinaten
local function CenterOf(frame)
    local x, y = frame:GetCenter()
    if not x then return nil end
    local k = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return x * k, y * k
end

---------------------------------------------------------------------------------------------------
-- Knopf zu einem Aktionsplatz finden: erst die Standardleisten, sonst alle Frames (Leisten-Addons speichern
-- den Platz in .action, ._state_action oder im Attribut "action")
---------------------------------------------------------------------------------------------------
local BAR_BUTTONS = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }

local function SlotOf(b)
    local slot = rawget(b, "action") or rawget(b, "_state_action")
    if type(slot) ~= "number" and b.GetAttribute then
        local ok, a = pcall(b.GetAttribute, b, "action")
        if ok then slot = tonumber(a) end
    end
    if b.GetName and (b:GetName() or ""):match("^ActionButton%d+$") and ActionButton_GetPagedID then
        local ok, paged = pcall(ActionButton_GetPagedID, b)
        if ok and type(paged) == "number" then slot = paged end
    end
    return type(slot) == "number" and slot or nil
end

local function Usable(b) return b.IsVisible and b:IsVisible() and b.GetCenter and b:GetCenter() end

function SR.ButtonFor(slot)
    for _, prefix in ipairs(BAR_BUTTONS) do
        for i = 1, 12 do
            local b = _G[prefix .. i]
            if b and SlotOf(b) == slot and Usable(b) then return b end
        end
    end
    if EnumerateFrames then
        local f = EnumerateFrames()
        while f do
            if type(f) == "table" and (rawget(f, "action") or rawget(f, "_state_action")) and SlotOf(f) == slot and Usable(f) then
                return f
            end
            f = EnumerateFrames(f)
        end
    end
end

-- Startpunkt: Symbol der gewählten Fähigkeit im Lehrerfenster, sonst das Lehrerfenster, sonst Bildschirmmitte
local function StartPoint()
    for _, name in ipairs({ "ClassTrainerSkillIcon", "ClassTrainerFrame" }) do
        local f = _G[name]
        if f and f.IsVisible and f:IsVisible() then
            local x, y = CenterOf(f)
            if x then return x, y end
        end
    end
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    return w / 2, h * 0.6
end

---------------------------------------------------------------------------------------------------
-- Flieger und Aufleuchten (wiederverwendbar)
---------------------------------------------------------------------------------------------------
local flyers, flashes = {}, {}

local function GetFlyer()
    for _, f in ipairs(flyers) do if not f.busy then return f end end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("TOOLTIP")
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.glow = f:CreateTexture(nil, "OVERLAY")
    f.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    f.glow:SetBlendMode("ADD")
    f.glow:SetPoint("CENTER")
    flyers[#flyers + 1] = f
    return f
end

local function Flash(button)
    local fl = flashes[button]
    if not fl then
        fl = CreateFrame("Frame", nil, button)
        fl:SetAllPoints()
        fl:SetFrameLevel((button.GetFrameLevel and button:GetFrameLevel() or 1) + 5)
        fl.tex = fl:CreateTexture(nil, "OVERLAY")
        fl.tex:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        fl.tex:SetBlendMode("ADD")
        fl.tex:SetAllPoints()
        flashes[button] = fl
    end
    fl.t = 0
    fl:SetAlpha(1)
    fl:Show()
    fl:SetScript("OnUpdate", function(self, elapsed)
        self.t = self.t + elapsed
        local p = self.t / FLASH
        if p >= 1 then self:Hide(); self:SetScript("OnUpdate", nil) return end
        self:SetAlpha(1 - p)
    end)
end

local function Ease(p) return p < 0.5 and 2 * p * p or 1 - (-2 * p + 2) ^ 2 / 2 end

local function Fly(spellID, button, delay)
    local tex = SpellTexture(spellID)
    local x0, y0 = StartPoint()
    local x1, y1 = CenterOf(button)
    if not tex or not x0 or not x1 then return end
    local endSize = math.max(20, math.min(64, (button:GetWidth() or END_SIZE) * button:GetEffectiveScale() / UIParent:GetEffectiveScale()))
    local f = GetFlyer()
    f.busy = true
    f.icon:SetTexture(tex)
    f.t = -(delay or 0)
    f:SetAlpha(0)
    f:Show()
    local function Place(x, y, size)
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        f:SetSize(size, size)
        f.glow:SetSize(size * 1.8, size * 1.8)
    end
    Place(x0, y0, START_SIZE * 0.4)
    f:SetScript("OnUpdate", function(self, elapsed)
        self.t = self.t + elapsed
        local t = self.t
        if t < 0 then return end
        if t < POP then -- auftauchen und aufploppen
            local p = t / POP
            self:SetAlpha(p)
            Place(x0, y0, START_SIZE * (0.4 + 0.75 * p))
        elseif t < POP + HOLD then -- kurz stehen
            self:SetAlpha(1)
            Place(x0, y0, START_SIZE * (1.15 - 0.15 * math.min(1, (t - POP) / 0.1)))
        elseif t < POP + HOLD + FLY then -- zum Knopf fliegen, dabei auf Knopfgröße schrumpfen
            local p = Ease((t - POP - HOLD) / FLY)
            Place(x0 + (x1 - x0) * p, y0 + (y1 - y0) * p, START_SIZE + (endSize - START_SIZE) * p)
        else
            Place(x1, y1, endSize)
            self:Hide()
            self:SetScript("OnUpdate", nil)
            self.busy = false
            Flash(button)
        end
    end)
end

-- placed = { [Platz] = Zauber-ID }; je sichtbarem Knopf ein Flug, leicht versetzt
function SR.Animate(placed)
    local slots = {}
    for slot in pairs(placed) do slots[#slots + 1] = slot end
    table.sort(slots)
    local n = 0
    for _, slot in ipairs(slots) do
        local button = SR.ButtonFor(slot)
        if button then
            Fly(placed[slot], button, n * STAGGER)
            n = n + 1
        end
    end
    return n
end
