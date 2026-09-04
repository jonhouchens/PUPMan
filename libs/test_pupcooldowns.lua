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

print('pupcooldowns: all assertions passed')
