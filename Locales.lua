-- SpellRankUp: Sprachen. Schlüssel ist der deutsche Text; fehlt eine Übersetzung, gilt Englisch, sonst der Schlüssel.
local _, SR = ...

local locale = GetLocale and GetLocale() or "enUS"
if locale == "enGB" then locale = "enUS" end
SR.LOCALE = locale

SR.TRANSLATIONS = SR.TRANSLATIONS or {}
local T = SR.TRANSLATIONS

SR.L = setmetatable({}, {
    __index = function(_, key)
        if locale == "deDE" then return key end
        local own = T[locale] or (locale == "esMX" and T.esES)
        return (own and own[key]) or (T.enUS and T.enUS[key]) or key
    end,
})
