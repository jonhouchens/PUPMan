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

print('pupcooldowns: all assertions passed')
