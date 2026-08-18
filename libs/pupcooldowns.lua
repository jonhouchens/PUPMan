--[[
pupcooldowns.lua (v1.0) -- shared Puppetmaster automaton-system tracker

Tracks discrete automaton abilities from incoming action packets. Equipped
attachments and the active frame decide which rows exist; the caller supplies
those values from the PUP 0x44 packet (pupstats.lua already exposes both).

The default action IDs, cooldowns, and spawn behavior follow LandSandBoat's
base branch as of 2026-08-15. Horizon is a private fork, so every duration is a
model value. An observed pet action is authoritative for when a cooldown began.

Fresh-spawn behavior mirrors LSB: attachment recasts are applied when the pet
spawns, while Valoredge Shield Bash is initially ready. A pet already present
when an addon loads must use cold_attach(); its rows remain unknown until each
ability is observed rather than claiming a false READY state.
]]

local lib = {}
lib.VERSION = '1.0'

local function normalized(value)
    return string.lower(tostring(value or '')):gsub('[^%w]', '')
end

-- action_id is the 0x28 action header ID emitted when the automaton uses the
-- system. attachment_names sharing an action are intentionally one row.
lib.DEFINITIONS = {
    {
        key = 'shield_bash', name = 'Shield Bash', action_id = 1944,
        cooldown = 180, frame = 21, spawn_delay = false,
    },
    {
        key = 'strobe', name = 'Strobe', action_id = 1945,
        cooldown = 30, element = 'Fire',
        attachment_names = { 'Strobe', 'Strobe II' },
    },
    {
        key = 'shock_absorber', name = 'Shock Absorber', action_id = 1946,
        cooldown = 180, element = 'Earth',
        attachment_names = {
            'Shock Absorber', 'Shock Absorber II', 'Shock Absorber III',
        },
    },
    {
        key = 'flashbulb', name = 'Flashbulb', action_id = 1947,
        cooldown = 45, element = 'Light',
        attachment_names = { 'Flashbulb' },
    },
    {
        key = 'mana_converter', name = 'Mana Converter', action_id = 1948,
        cooldown = 180, element = 'Dark', condition = 'mana_converter',
        attachment_names = { 'Mana Converter' },
    },
    {
        key = 'eraser', name = 'Eraser', action_id = 2021,
        cooldown = 30, element = 'Light', condition = 'status_target',
        attachment_names = { 'Eraser' },
    },
    {
        key = 'reactive_shield', name = 'Reactive Shield', action_id = 2031,
        cooldown = 60, element = 'Fire',
        attachment_names = { 'Reactive Shield' },
    },
    {
        key = 'economizer', name = 'Economizer', action_id = 2068,
        cooldown = 60, condition = 'economizer',
        attachment_names = { 'Economizer' },
    },
    {
        key = 'replicator', name = 'Replicator', action_id = 2132,
        cooldown = 60, element = 'Wind', condition = 'replicator',
        attachment_names = { 'Replicator' },
    },
    {
        key = 'heat_capacitor', name = 'Heat Capacitor', action_id = 2745,
        cooldown = 90, element = 'Fire',
        attachment_names = { 'Heat Capacitor', 'Heat Capacitor II' },
    },
    {
        key = 'barrage_turbine', name = 'Barrage Turbine', action_id = 2746,
        cooldown = 180, element = 'Wind',
        attachment_names = { 'Barrage Turbine' },
    },
    {
        key = 'disruptor', name = 'Disruptor', action_id = 2747,
        cooldown = 60, element = 'Dark', condition = 'target_buff',
        attachment_names = { 'Disruptor' },
    },
    {
        key = 'regulator', name = 'Regulator', action_id = 3485,
        cooldown = 60, element = 'Dark', condition = 'target_buff',
        attachment_names = { 'Regulator' },
    },
}

local definitions_by_action = {}
for _, definition in ipairs(lib.DEFINITIONS) do
    definitions_by_action[definition.action_id] = definition
end

local Tracker = {}
Tracker.__index = Tracker

function lib.new(cfg)
    cfg = cfg or {}
    local self = setmetatable({}, Tracker)
    self.now = cfg.now or os.clock
    self.frame = 0
    self.attachments = {}
    self.active_definitions = {}
    self.used_at = {}
    self.pet_active = false
    self.spawned_at = nil
    self.cold = false
    return self
end

function Tracker:configure(attachments, frame)
    self.frame = tonumber(frame) or 0
    self.attachments = {}
    for _, attachment in ipairs(attachments or {}) do
        local name = type(attachment) == 'table' and attachment.name or attachment
        if name ~= nil then
            self.attachments[normalized(name)] = true
        end
    end

    self.active_definitions = {}
    for _, definition in ipairs(lib.DEFINITIONS) do
        local active = definition.frame ~= nil and definition.frame == self.frame
        if not active then
            for _, name in ipairs(definition.attachment_names or {}) do
                if self.attachments[normalized(name)] then
                    active = true
                    break
                end
            end
        end
        if active then
            self.active_definitions[#self.active_definitions + 1] = definition
        end
    end
end

function Tracker:on_spawn()
    self.pet_active = true
    self.spawned_at = self.now()
    self.cold = false
    self.used_at = {}
end

function Tracker:cold_attach()
    self.pet_active = true
    self.spawned_at = nil
    self.cold = true
    self.used_at = {}
end

function Tracker:on_pet_lost()
    self.pet_active = false
    self.spawned_at = nil
    self.cold = false
    self.used_at = {}
end

function Tracker:on_action(action_id)
    local definition = definitions_by_action[tonumber(action_id)]
    if definition == nil then return false end
    self.pet_active = true
    self.used_at[definition.key] = self.now()
    return true
end

local function maneuver_count(context, element)
    local maneuvers = context.maneuvers or {}
    return math.max(0, math.floor(tonumber(
        maneuvers[element] or maneuvers[string.lower(element or '')]) or 0))
end

function Tracker:_cooldown(definition, context)
    local cooldown = definition.cooldown
    if definition.key == 'shield_bash' then
        local barrier_count = 0
        if self.attachments[normalized('Barrier Module')] then
            barrier_count = barrier_count + 1
        end
        if self.attachments[normalized('Barrier Module II')] then
            barrier_count = barrier_count + 1
        end
        cooldown = cooldown - math.min(3, maneuver_count(context, 'Earth'))
            * 5 * barrier_count
    end
    return math.max(0, cooldown)
end

function Tracker:_known_reference(definition)
    if self.used_at[definition.key] ~= nil then
        return self.used_at[definition.key], true
    end
    if self.spawned_at ~= nil then
        if definition.spawn_delay == false then return nil, true end
        return self.spawned_at, true
    end
    return nil, false
end

function Tracker:_eligibility(definition, context)
    if definition.element ~= nil
        and maneuver_count(context, definition.element) == 0 then
        return false, 'WAIT ' .. string.upper(string.sub(definition.element, 1, 1))
    end

    local mpp = tonumber(context.mpp)
    local hpp = tonumber(context.hpp)
    if definition.condition == 'mana_converter' then
        local dark = maneuver_count(context, 'Dark')
        local thresholds = { [1] = 40, [2] = 60, [3] = 70 }
        local threshold = thresholds[dark]
        if threshold == nil then return false, 'WAIT D' end
        if mpp ~= nil and mpp > threshold then return false, 'WAIT MP' end
    elseif definition.condition == 'economizer' then
        local threshold = 30 + math.min(3, maneuver_count(context, 'Dark')) * 10
        if mpp ~= nil and mpp > threshold then return false, 'WAIT MP' end
    elseif definition.condition == 'replicator' then
        local threshold = (self.attachments[normalized('Damage Gauge')]
            or self.attachments[normalized('Damage Gauge II')]) and 75 or 50
        if hpp ~= nil and hpp > threshold then return false, 'WAIT HP' end
    end
    return true, 'READY'
end

function Tracker:rows(context)
    context = context or {}
    local rows = {}
    local now = self.now()
    for _, definition in ipairs(self.active_definitions) do
        local reference, known = self:_known_reference(definition)
        local cooldown = self:_cooldown(definition, context)
        local remaining = reference ~= nil
            and math.max(0, cooldown - (now - reference)) or 0
        local eligible, status = self:_eligibility(definition, context)
        if not self.pet_active then
            known = false
            status = 'NO PET'
        elseif not known then
            status = 'UNKNOWN'
        elseif remaining > 0 then
            status = 'COOLDOWN'
        end
        rows[#rows + 1] = {
            key = definition.key,
            name = definition.name,
            action_id = definition.action_id,
            cooldown = cooldown,
            element = definition.element,
            known = known,
            remaining = remaining,
            ready = known and remaining <= 0,
            eligible = known and remaining <= 0 and eligible,
            status = status,
            modeled = true,
        }
    end
    return rows
end

return lib
