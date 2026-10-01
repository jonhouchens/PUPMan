package.path = './?.lua;' .. package.path

local cooldowns = require('pupcooldowns')
local now = 100
local tracker = cooldowns.new({ now = function() return now end })

local function equal(actual, expected, label)
    assert(actual == expected, ('%s: expected %s, got %s'):format(
        label, tostring(expected), tostring(actual)))
end

-- PUP frame resource IDs are hexadecimal: Valoredge is 0x21 (decimal 33).
tracker:configure({}, 0x21)
tracker:cold_attach()
local rows = tracker:rows({})
equal(#rows, 1, 'Valoredge frame system count')
equal(rows[1].name, 'Shield Bash', 'Valoredge frame ability')
equal(rows[1].status, 'UNKNOWN', 'cold Valoredge state')

tracker:on_spawn()
rows = tracker:rows({})
equal(rows[1].ready, true, 'Shield Bash ready on spawn')

tracker:on_action(1944)
rows = tracker:rows({})
equal(rows[1].remaining, 180, 'Shield Bash cooldown starts on action')

now = 220
rows = tracker:rows({})
equal(rows[1].remaining, 60, 'Shield Bash cooldown decays')

-- Decimal 21 was the former, incorrect interpretation of resource ID 0x21.
tracker:configure({}, 21)
rows = tracker:rows({})
equal(#rows, 0, 'invalid decimal frame ID is not Valoredge')

-- Sharpshot ranged attacks are frame systems whose base delay depends on the
-- equipped head. A fresh spawn begins ready; an observed action is the anchor.
now = 300
tracker:configure({}, 0x22, 0x03)
tracker:on_spawn()
rows = tracker:rows({})
equal(#rows, 1, 'Sharpshot frame system count')
equal(rows[1].name, 'Ranged Attack', 'Sharpshot ranged system')
equal(rows[1].ready, true, 'ranged attack ready on spawn')

tracker:on_action(1949)
rows = tracker:rows({})
equal(rows[1].remaining, 20, 'Sharpshot head base ranged delay')

now = 305
rows = tracker:rows({})
equal(rows[1].remaining, 15, 'ranged attack cooldown decays')

-- Drum Magazine's era values reduce delay by 2/4/6/8 seconds for 0-3 Wind.
now = 400
tracker:configure({ 'Drum Magazine' }, 0x22, 0x03)
tracker:cold_attach()
rows = tracker:rows({ maneuvers = { Wind = 2 } })
equal(rows[1].status, 'UNKNOWN', 'cold ranged attack state')
tracker:on_action(1949)
rows = tracker:rows({ maneuvers = { Wind = 2 } })
equal(rows[1].cooldown, 14, 'Drum Magazine two-Wind delay')
equal(rows[1].remaining, 14, 'Drum Magazine countdown anchor')

now = 500
tracker:configure({ 'Drum Magazine' }, 0x22, 0x01)
tracker:on_spawn()
tracker:on_action(1949)
rows = tracker:rows({ maneuvers = { Wind = 3 } })
equal(rows[1].cooldown, 17, 'Harlequin head ranged delay')

local function row(key)
    for _, value in ipairs(tracker:rows({})) do
        if value.key == key then return value end
    end
    error('missing row: ' .. key)
end
local function cast(id, header, kind)
    return tracker:on_packet({ Type = kind or 8, Id = header or 0x6163,
        Targets = { { Actions = { { Param = id } } } } })
end

now = 1000
tracker:configure({ 'Flashbulb' }, 0x23, 5)
tracker:cold_attach()
equal(#tracker:rows({}), 6, 'Soulsoother magic plus Flashbulb')
equal(row('magic_magic').status, 'UNKNOWN', 'cold magic unknown')
equal(cast(4), true, 'Cure IV cast detected')
equal(row('magic_magic').remaining, 6.4, 'Soulsoother global delay')
equal(row('magic_heal').remaining, 10, 'Cure advances healing')
equal(row('magic_status').status, 'UNKNOWN', 'unobserved category stays unknown')
now = 1002
cast(4, 0x7073)
cast(4, 4, 4)
equal(row('magic_heal').remaining, 8, 'interrupt and completion do not restart')
equal(row('magic_magic').remaining, 4.4, 'global countdown')
cast(999)
equal(row('magic_magic').remaining, 6.4, 'unknown spell still advances global')
equal(row('magic_heal').remaining, 8, 'unknown spell leaves category alone')
equal(tracker:on_packet({ Type = 8, Id = 0x6163 }), false, 'missing result ignored')
equal(tracker:on_packet({ Type = 4, Id = 1947 }), false, 'wrong type cannot fire Flashbulb')
equal(row('flashbulb').status, 'UNKNOWN', 'no false ability timestamp')
tracker:on_packet({ Type = 11, Id = 1947 })
equal(row('flashbulb').remaining, 45, 'mob ability packet tracked')
cast(143)
equal(row('magic_status').remaining, 10, 'Erase status category')
cast(57)
equal(row('magic_enhance').remaining, 15, 'Haste enhancing category')
tracker:configure({ 'Flashbulb' }, 0x23, 5)
equal(row('magic_status').remaining, 10, 'equipment refresh preserves timestamps')
tracker:on_pet_lost()
equal(row('magic_heal').status, 'NO PET', 'pet loss clears magic')
tracker:on_spawn()
equal(row('magic_heal').status, 'READY', 'fresh spawn magic ready')

tracker:configure({}, 0x23, 6)
equal(#tracker:rows({}), 4, 'Spiritreaver has no healing or status row')
cast(144)
equal(row('magic_elemental').remaining, 35, 'Spiritreaver elemental delay')
cast(247)
equal(row('magic_enfeeble').remaining, 5, 'Aspir uses enfeebling category')
tracker:configure({}, 0x23, 4)
cast(173)
equal(row('magic_elemental').remaining, 25, 'Stormwaker elemental delay')
equal(row('magic_magic').remaining, 12.8, 'Stormwaker global delay')
now = 1100
equal(row('magic_magic').status, 'READY', 'expired timer ready')
tracker:configure({}, 0x22, 5)
equal(#tracker:rows({}), 1, 'caster head on Sharpshot frame has only ranged row')
equal(cast(4), false, 'nonmagic frame ignores cast')
tracker:configure({}, 0x20, 1)
equal(#tracker:rows({}), 3, 'Harlequin magic rows')

print('pupcooldowns: all assertions passed')
