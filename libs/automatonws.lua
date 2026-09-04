--[[
automatonws.lua -- presentation-neutral Horizon-era automaton WS projection

The normal automaton AI chooses among weapon skills unlocked by the equipped
frame and current combat skill. It prefers the greatest number of matching
maneuvers, then the highest skill requirement, then the highest ability id.

Inhibitor can replace that normal choice with a skillchain-aware choice. The
client does not expose all server-side skillchain state used by that decision,
so callers should present an Inhibitor result as conditional.
]]

local lib = {}
lib.VERSION = '1.0'

lib.FRAME = {
    HARLEQUIN = 0x20,
    VALOREDGE = 0x21,
    SHARPSHOT = 0x22,
    STORMWAKER = 0x23,
}

local harlequin_skills = {
    { id = 1943, name = 'Slapstick',    element = 'Thunder', skill = 0 },
    { id = 2067, name = 'Knockout',     element = 'Wind',    skill = 145 },
    { id = 2301, name = 'Magic Mortar', element = 'Light',   skill = 225 },
}

lib.SKILLS = {
    [lib.FRAME.HARLEQUIN] = harlequin_skills,
    [lib.FRAME.VALOREDGE] = {
        { id = 1940, name = 'Chimera Ripper', element = 'Fire',    skill = 0 },
        { id = 1941, name = 'String Clipper', element = 'Thunder', skill = 0 },
        { id = 2065, name = 'Cannibal Blade', element = 'Dark',    skill = 150 },
        { id = 2299, name = 'Bone Crusher',   element = 'Light',   skill = 245 },
    },
    [lib.FRAME.SHARPSHOT] = {
        { id = 1942, name = 'Arcuballista',  element = 'Fire',    skill = 0 },
        { id = 2066, name = 'Daze',          element = 'Thunder', skill = 150 },
        { id = 2300, name = 'Armor Piercer', element = 'Dark',    skill = 245 },
    },
    [lib.FRAME.STORMWAKER] = harlequin_skills,
}

local function maneuver_count(counts, element)
    if counts == nil then return 0 end
    local direct = tonumber(counts[element])
    if direct ~= nil then return math.max(0, direct) end
    local wanted = string.lower(element)
    for name, count in pairs(counts) do
        if string.lower(tostring(name)) == wanted then
            return math.max(0, tonumber(count) or 0)
        end
    end
    return 0
end

local function higher_priority(candidate, current)
    if current == nil then return true end
    if candidate.maneuvers ~= current.maneuvers then
        return candidate.maneuvers > current.maneuvers
    end
    if candidate.required_skill ~= current.required_skill then
        return candidate.required_skill > current.required_skill
    end
    return candidate.id > current.id
end

function lib.combat_skill_kind(frame)
    return frame == lib.FRAME.SHARPSHOT and 'ranged' or 'melee'
end

function lib.predict(options)
    options = options or {}
    local frame = tonumber(options.frame)
    local skill = tonumber(options.skill)
    local available = lib.SKILLS[frame]
    if available == nil then
        return nil, 'unknown_frame'
    end
    if skill == nil then
        return nil, 'unknown_skill'
    end

    local selected = nil
    for _, ws in ipairs(available) do
        if skill >= ws.skill then
            local candidate = {
                id = ws.id,
                name = ws.name,
                element = ws.element,
                required_skill = ws.skill,
                skill = skill,
                skill_kind = lib.combat_skill_kind(frame),
                maneuvers = maneuver_count(options.maneuvers, ws.element),
                inhibitor = options.inhibitor == true,
                tp = tonumber(options.tp),
            }
            candidate.ready = candidate.tp ~= nil and candidate.tp >= 1000
            candidate.conditional = candidate.inhibitor
            if higher_priority(candidate, selected) then
                selected = candidate
            end
        end
    end

    if selected == nil then
        return nil, 'no_unlocked_skill'
    end
    return selected
end

return lib
