addon.name      = 'pupman';
addon.author    = 'Koruru';
addon.version   = '3.9.0';
addon.desc      = 'A compact maneuver planner, automaton control, and overload helper for Puppetmaster.';

require 'common';

local actionpacket = require 'actionpacket';
local burden       = require 'burdenmodel';
local forecast     = require 'burdenforecast';
local pupcooldowns = require 'pupcooldowns';
local pupstats     = require 'pupstats';
local chat         = require 'chat';
local imgui        = require 'imgui';
local petstatus    = require 'petstatus';
local settings     = require 'settings';

local PUP_JOB_ID = 18;
local ACTIVATE_ABILITY_ID = 136;
local OVERLOAD_BUFF_ID = 299;
local MANEUVER_DURATION = 60;
local MANEUVER_MIN_ID = 141;
local MANEUVER_MAX_ID = 148;
local MANEUVER_RESOURCE_OFFSET = 512;
local MANEUVER_RECAST_SECONDS = 10;
local MANEUVER_ATTEMPT_GUARD_SECONDS = 0.75;
local RANGED_EQUIPMENT_SLOT = 2;
local MANEUVER_BUFF_GRACE_SECONDS = 1.0;
local MANEUVER_CONFIRM_TIMEOUT = 2.5;
local MANEUVER_REQUEST_TIMEOUT = 5.0;
local HUD_FONT_PATH = 'C:\\Windows\\Fonts\\tahomabd.ttf';
local HUD_FONT_SIZE = 14.0;
local HUD_VITALS_FONT_SIZE = 16.0;
local HUD_WIDTH = 382;
local SYSTEMS_WIDTH = 230;
local SYSTEMS_GAP = 8;
local MP_WARNING_THRESHOLD = 30;
local MP_DANGER_THRESHOLD = 20;
local MP_CRITICAL_THRESHOLD = 10;
local OIL_ITEM_IDS = T{ 18731, 18732, 18733, 19185 };
local oil_item_set = {};
for _, item_id in ipairs(OIL_ITEM_IDS) do
    oil_item_set[item_id] = true;
end

-- Mirrors the town list used by the installed LuAshitacast profile. Airships
-- are included because that profile treats them as non-field hubs as well.
local town_zones = {
    [26]=true, [48]=true, [50]=true, [53]=true,
    [80]=true, [87]=true, [94]=true,
    [223]=true, [224]=true, [225]=true, [226]=true,
    [230]=true, [231]=true, [232]=true, [233]=true,
    [234]=true, [235]=true, [236]=true, [237]=true,
    [238]=true, [239]=true, [240]=true, [241]=true, [242]=true,
    [243]=true, [244]=true, [245]=true, [246]=true,
    [247]=true, [248]=true, [249]=true, [250]=true, [252]=true,
    [256]=true, [257]=true, [280]=true, [284]=true,
};

local event_system_pointer = ashita.memory.find(
    'FFXiMain.dll', 0,
    'A0????????84C0741AA1????????85C0741166A1????????663B05????????0F94C0C3', 0, 0);
local interface_hidden_pointer = ashita.memory.find(
    'FFXiMain.dll', 0,
    '8B4424046A016A0050B9????????E8????????F6D81BC040C3', 0, 0);

local pup_recasts = T{
    { key = 'activate',   short = 'ACT', name = 'Activate',   id = 205 },
    { key = 'repair',     short = 'REP', name = 'Repair',     id = 206 },
    { key = 'deploy',     short = 'DEP', name = 'Deploy',     id = 207 },
    { key = 'deactivate', short = 'DEA', name = 'Deactivate', id = 208 },
    { key = 'retrieve',   short = 'RET', name = 'Retrieve',   id = 209 },
};

local automaton_heads = T{
    [1] = 'Harlequin', [2] = 'Valoredge', [3] = 'Sharpshot',
    [4] = 'Stormwaker', [5] = 'Soulsoother', [6] = 'Spiritreaver',
};

local automaton_frames = T{
    [20] = 'Harlequin', [21] = 'Valoredge', [22] = 'Sharpshot', [23] = 'Stormwaker',
};

local elements = T{
    [141] = { name = 'Fire',    buff = 300, color = { 0.90, 0.25, 0.15, 1.00 } },
    [142] = { name = 'Ice',     buff = 301, color = { 0.35, 0.70, 1.00, 1.00 } },
    [143] = { name = 'Wind',    buff = 302, color = { 0.35, 0.85, 0.55, 1.00 } },
    [144] = { name = 'Earth',   buff = 303, color = { 0.72, 0.52, 0.25, 1.00 } },
    [145] = { name = 'Thunder', buff = 304, color = { 0.75, 0.45, 1.00, 1.00 } },
    [146] = { name = 'Water',   buff = 305, color = { 0.20, 0.55, 0.95, 1.00 } },
    [147] = { name = 'Light',   buff = 306, color = { 1.00, 0.90, 0.35, 1.00 } },
    [148] = { name = 'Dark',    buff = 307, color = { 0.55, 0.40, 0.70, 1.00 } },
};

-- Okabe-Ito-inspired colors, extended with a muted violet for Dark. The
-- element glyph shapes remain distinct even when two hues appear similar.
local colorblind_colors = {
    Fire    = { 0.90, 0.62, 0.00, 1.00 },
    Ice     = { 0.34, 0.71, 0.91, 1.00 },
    Wind    = { 0.00, 0.62, 0.45, 1.00 },
    Earth   = { 0.94, 0.89, 0.26, 1.00 },
    Thunder = { 0.80, 0.48, 0.66, 1.00 },
    Water   = { 0.00, 0.45, 0.70, 1.00 },
    Light   = { 0.96, 0.90, 0.65, 1.00 },
    Dark    = { 0.48, 0.40, 0.64, 1.00 },
};

local by_name = {};
local by_buff = {};
for ability_id, element in pairs(elements) do
    element.ability = ability_id;
    element.burden_index = ability_id - MANEUVER_MIN_ID;
    by_name[string.lower(element.name)] = element;
    by_buff[element.buff] = element;
end

-- A compact ToAU-inspired palette: imperial blue-green, aged brass, and parchment.
local toau_theme = {
    brass = { 0.776, 0.631, 0.357, 1.00 },
    brass_dim = { 0.565, 0.455, 0.267, 1.00 },
    teal = { 0.231, 0.651, 0.627, 1.00 },
    bg_dark = { 0.024, 0.082, 0.102, 0.96 },
    bg_medium = { 0.039, 0.137, 0.157, 1.00 },
    bg_light = { 0.059, 0.196, 0.208, 1.00 },
    bg_lighter = { 0.082, 0.247, 0.251, 1.00 },
    text = { 0.910, 0.875, 0.776, 1.00 },
    border = { 0.310, 0.290, 0.216, 1.00 },
};

-- These are convenient starting points, not attachment-specific prescriptions.
local presets = {
    balanced = { 'Fire', 'Wind', 'Light' },
    melee    = { 'Fire', 'Fire', 'Thunder' },
    ranged   = { 'Wind', 'Wind', 'Fire' },
    tank     = { 'Earth', 'Light', 'Fire' },
    healer   = { 'Light', 'Light', 'Dark' },
    nuker    = { 'Ice', 'Ice', 'Dark' },
};

local default_profiles = {
    ['1:20'] = 'balanced',
    ['2:21'] = 'melee',
    ['3:22'] = 'ranged',
    ['4:23'] = 'nuker',
    ['5:23'] = 'healer',
    ['6:23'] = 'nuker',
};

local defaults = T{
    visible = true,
    position_x = 420,
    position_y = 260,
    refresh_at = 12,
    repair_warn_at = 40,
    burden_threshold = 0,
    burden_heatsink = false,
    burden_heatsink_mode = 'auto',
    burden_guard = -1,
    colorblind = false,
    systems_visible = false,
    systems_side = 'right',
    hide_town = true,
    hide_cutscene = true,
    layout = 'micro',
    mode = 'profile',
    plan = T{ 'Fire', 'Fire', 'Thunder' },
    mode_plans = T{
        balanced = T{ 'Fire', 'Wind', 'Light' },
        melee = T{ 'Fire', 'Fire', 'Thunder' },
        ranged = T{ 'Wind', 'Wind', 'Fire' },
        tank = T{ 'Earth', 'Light', 'Fire' },
        healer = T{ 'Light', 'Light', 'Dark' },
        nuker = T{ 'Ice', 'Ice', 'Dark' },
    },
    profiles = T{
        ['1:20'] = 'balanced',
        ['2:21'] = 'melee',
        ['3:22'] = 'ranged',
        ['4:23'] = 'nuker',
        ['5:23'] = 'healer',
        ['6:23'] = 'nuker',
    },
};

local state = T{
    settings = settings.load(defaults),
    open = { true },
    systems_open = { true },
    slots = T{},
    last_action = -10,
    maneuver_request = nil,
    pending_maneuver = nil,
    overload_skip = nil,
    last_sync = 0,
    first_draw = true,
    pet_hp_current = nil,
    pet_hp_max = nil,
    pet_hp_valid = false,
    pet_hp_server_id = 0,
    pet_hp_updated = 0,
    pet_mp_current = nil,
    pet_mp_max = nil,
    automaton_head = 0,
    automaton_frame = 0,
    active_mode = 'custom',
    pet_status_server_id = 0,
    pet_status_hpp = nil,
    pet_status_mpp = nil,
    pet_status_tp = nil,
    pet_status_target = nil,
    oil_count = 0,
    oil_last_sync = -10,
    hud_font = nil,
    hud_vitals_font = nil,
    systems_pet_initialized = false,
    systems_pet_server_id = 0,
};

local function copy_plan(plan)
    return T{ plan[1], plan[2], plan[3] };
end

local function ensure_settings_shape()
    state.settings.layout = state.settings.layout == 'micro' and 'micro' or 'compact';
    -- Migrate settings written by releases that called profile selection
    -- "auto".
    if (state.settings.mode == nil or state.settings.mode == 'auto') then
        state.settings.mode = 'profile';
    end
    state.settings.auto_combat = nil;
    state.settings.repair_warn_at = math.max(0, math.min(99,
        tonumber(state.settings.repair_warn_at) or 40));
    state.settings.burden_threshold =
        tonumber(state.settings.burden_threshold) == 5 and 5 or 0;
    state.settings.burden_heatsink = state.settings.burden_heatsink == true;
    local heatsink_mode = string.lower(tostring(
        state.settings.burden_heatsink_mode or 'auto'));
    if (heatsink_mode ~= 'auto' and heatsink_mode ~= 'on'
        and heatsink_mode ~= 'off') then
        heatsink_mode = 'auto';
    end
    state.settings.burden_heatsink_mode = heatsink_mode;
    local burden_guard = tonumber(state.settings.burden_guard);
    state.settings.burden_guard = burden_guard ~= nil
        and math.max(-1, math.min(100, math.floor(burden_guard))) or -1;
    state.settings.colorblind = state.settings.colorblind == true;
    state.settings.systems_visible = state.settings.systems_visible == true;
    state.settings.systems_side = state.settings.systems_side == 'left'
        and 'left' or 'right';
    state.settings.hide_town = state.settings.hide_town ~= false;
    state.settings.hide_cutscene = state.settings.hide_cutscene ~= false;
    state.settings.mode_plans = state.settings.mode_plans or T{};
    for name, plan in pairs(presets) do
        if (state.settings.mode_plans[name] == nil) then
            state.settings.mode_plans[name] = copy_plan(plan);
        end
    end
    state.settings.profiles = state.settings.profiles or T{};
    for key, mode in pairs(default_profiles) do
        if (state.settings.profiles[key] == nil) then
            state.settings.profiles[key] = mode;
        end
    end
end

ensure_settings_shape();

local burden_stats = pupstats.attach({
    alias = 'pupman_burden_stats',
    now = os.clock,
});

local systems_tracker = pupcooldowns.new({ now = os.clock });

local function configure_systems_tracker()
    systems_tracker:configure(
        burden_stats:attachments(), state.automaton_frame);
end

local function heatsink_detected()
    return burden_stats:has_attachment('Heatsink');
end

local function effective_heatsink()
    if (state.settings.burden_heatsink_mode == 'on') then
        return true;
    elseif (state.settings.burden_heatsink_mode == 'off') then
        return false;
    end
    return heatsink_detected();
end

local burden_model = burden.attach({
    alias = 'pupman_burden',
    thresh_gear = state.settings.burden_threshold,
    heatsink = effective_heatsink(),
    frame_half_dark = false,
    stat_diff = function(element, phase)
        return burden_stats:stat_diff(element, phase);
    end,
    now = os.clock,
});

local function configure_burden_model()
    local heatsink = effective_heatsink();
    -- Keep the legacy boolean synchronized for settings readers from older
    -- releases; mode is the authoritative user choice in this release.
    state.settings.burden_heatsink = heatsink;
    burden_model:configure({
        thresh_gear = state.settings.burden_threshold,
        heatsink = heatsink,
        -- PupMan learns the equipped frame from packet 0x44. Valoredge and
        -- Sharpshot use LSB's reduced Dark burden path.
        frame_half_dark = state.automaton_frame == 21
            or state.automaton_frame == 22,
    });
end

local function element_display_color(element)
    if (state.settings.colorblind) then
        return colorblind_colors[element.name] or element.color;
    end
    return element.color;
end

local function draw_element_icon(draw, name, center_x, center_y, size, color)
    if (draw == nil or name == nil) then
        return;
    end
    local half = size / 2;
    local glyph = imgui.GetColorU32(color);
    local plate = imgui.GetColorU32({ 0.02, 0.07, 0.09, 0.72 });
    draw:AddCircleFilled({ center_x, center_y }, half + 2, plate, 12);

    if (name == 'Fire') then
        draw:AddTriangleFilled(
            { center_x, center_y - half },
            { center_x - half * 0.8, center_y + half },
            { center_x + half * 0.8, center_y + half }, glyph);
    elseif (name == 'Ice') then
        draw:AddQuadFilled(
            { center_x, center_y - half }, { center_x + half, center_y },
            { center_x, center_y + half }, { center_x - half, center_y }, glyph);
    elseif (name == 'Wind') then
        draw:AddLine({ center_x - half, center_y - 2 }, { center_x + half, center_y - 2 }, glyph, 1.5);
        draw:AddLine({ center_x - half * 0.6, center_y + 1 }, { center_x + half, center_y + 1 }, glyph, 1.5);
        draw:AddLine({ center_x, center_y + 4 }, { center_x + half * 0.7, center_y + 4 }, glyph, 1.5);
    elseif (name == 'Earth') then
        draw:AddRectFilled(
            { center_x - half * 0.8, center_y - half * 0.8 },
            { center_x + half * 0.8, center_y + half * 0.8 }, glyph, 1.0);
    elseif (name == 'Thunder') then
        draw:AddLine({ center_x + 1, center_y - half }, { center_x - 2, center_y }, glyph, 2.0);
        draw:AddLine({ center_x - 2, center_y }, { center_x + 2, center_y }, glyph, 2.0);
        draw:AddLine({ center_x + 2, center_y }, { center_x - 1, center_y + half }, glyph, 2.0);
    elseif (name == 'Water') then
        draw:AddTriangleFilled(
            { center_x, center_y - half },
            { center_x - half * 0.75, center_y + 1 },
            { center_x + half * 0.75, center_y + 1 }, glyph);
        draw:AddCircleFilled({ center_x, center_y + 2 }, half * 0.7, glyph, 10);
    elseif (name == 'Light') then
        draw:AddCircleFilled({ center_x, center_y }, half * 0.55, glyph, 10);
        draw:AddLine({ center_x - half, center_y }, { center_x + half, center_y }, glyph, 1.2);
        draw:AddLine({ center_x, center_y - half }, { center_x, center_y + half }, glyph, 1.2);
    else -- Dark
        draw:AddCircle({ center_x, center_y }, half * 0.85, glyph, 12, 1.7);
        draw:AddLine(
            { center_x - half * 0.65, center_y + half * 0.65 },
            { center_x + half * 0.65, center_y - half * 0.65 }, glyph, 1.5);
    end
end

local function load_hud_font()
    local ok, font = pcall(function()
        return imgui.AddFontFromFileTTF(HUD_FONT_PATH, HUD_FONT_SIZE);
    end);
    if (ok and font ~= nil) then
        state.hud_font = font;
    else
        state.hud_font = nil;
    end

    local vitals_ok, vitals_font = pcall(function()
        return imgui.AddFontFromFileTTF(HUD_FONT_PATH, HUD_VITALS_FONT_SIZE);
    end);
    if (vitals_ok and vitals_font ~= nil) then
        state.hud_vitals_font = vitals_font;
    else
        state.hud_vitals_font = nil;
    end
end

local function push_vitals_font()
    if (state.hud_vitals_font == nil) then
        return false;
    end
    return pcall(imgui.PushFont, state.hud_vitals_font);
end

local function message(text)
    print(chat.header(addon.name):append(chat.message(text)));
end

local function error_message(text)
    print(chat.header(addon.name):append(chat.error(text)));
end

-- Logs has no public addon-to-addon writer; use its chatlogs directory and
-- character/day naming for a structured sidecar that can be analyzed without
-- mixing CSV rows into the normal chat transcript.
local burden_log_path = nil;

local function burden_log_sink(event)
    if (burden_log_path == nil) then
        error('burden telemetry path is not set');
    end
    event.wall_time = os.date('%Y-%m-%dT%H:%M:%S');
    local file, err = io.open(burden_log_path, 'a');
    if (file == nil) then
        error('could not append burden telemetry: ' .. tostring(err));
    end
    file:write(burden.telemetry_csv_row(event) .. '\n');
    file:close();
end

local function burden_log_header_matches(path, expected)
    local file = io.open(path, 'r');
    if (file == nil) then
        return true;
    end
    local first_line = file:read('*l');
    file:close();
    return first_line == nil or first_line == expected;
end

local function start_burden_log()
    if (burden_model:telemetry_enabled()) then
        message('Burden telemetry is already running: ' .. burden_log_path);
        return;
    end

    local name = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0);
    name = tostring(name or 'Unknown'):gsub('[^%w_%-]', '_');
    if (name == '') then name = 'Unknown'; end
    local date = os.date('*t');
    local directory = ('%s/%s/'):fmt(AshitaCore:GetInstallPath(), 'chatlogs');
    if (not ashita.fs.exists(directory)) then
        ashita.fs.create_dir(directory);
    end
    burden_log_path = ('%s%s_%.4u.%.2u.%.2u.burden.csv'):fmt(
        directory, name, date.year, date.month, date.day);
    local expected_header = burden.telemetry_csv_header();
    if (not burden_log_header_matches(burden_log_path, expected_header)) then
        -- Never append a new column layout under an older header. This matters
        -- during same-day upgrades while a controlled test series is active.
        local schema = tostring(burden.VERSION or 'new'):gsub('[^%w%-]', '_');
        burden_log_path = ('%s%s_%.4u.%.2u.%.2u.burden.v%s.csv'):fmt(
            directory, name, date.year, date.month, date.day, schema);
    end

    local file, err = io.open(burden_log_path, 'a+');
    if (file == nil) then
        burden_log_path = nil;
        error_message('Could not start burden telemetry: ' .. tostring(err));
        return;
    end
    local size = file:seek('end') or 0;
    if (size == 0) then
        file:write(expected_header .. '\n');
    end
    file:close();

    burden_model:set_telemetry_sink(burden_log_sink);
    if (not burden_model:telemetry_enabled()) then
        local telemetry_error = burden_model:telemetry_error();
        burden_log_path = nil;
        error_message('Could not start burden telemetry: '
            .. tostring(telemetry_error or 'unknown writer error'));
        return;
    end
    burden_model:telemetry_note(
        'PupMan ' .. tostring(addon.version) .. ' Logs-compatible sidecar');
    message('Burden telemetry started: ' .. burden_log_path);
end

local function stop_burden_log()
    if (not burden_model:telemetry_enabled()) then
        local telemetry_error = burden_model:telemetry_error();
        if (telemetry_error ~= nil) then
            error_message('Burden telemetry stopped after an error: '
                .. telemetry_error);
        else
            message('Burden telemetry is not running.');
        end
        return;
    end
    local path = burden_log_path;
    burden_model:set_telemetry_sink(nil);
    burden_log_path = nil;
    local telemetry_error = burden_model:telemetry_error();
    if (telemetry_error ~= nil) then
        error_message('Burden telemetry stopped after an error: '
            .. telemetry_error);
    else
        message('Burden telemetry saved: ' .. tostring(path));
    end
end

local function print_burden_log_status()
    if (burden_model:telemetry_enabled()) then
        message('Burden telemetry running: ' .. burden_log_path);
    elseif (burden_model:telemetry_error() ~= nil) then
        error_message('Burden telemetry error: ' .. burden_model:telemetry_error());
    else
        message('Burden telemetry is off.');
    end
end

local function is_pup()
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    return player ~= nil and player:GetMainJob() == PUP_JOB_ID;
end

local function is_town_zone()
    local party = AshitaCore:GetMemoryManager():GetParty();
    if (party == nil) then
        return false;
    end
    return town_zones[tonumber(party:GetMemberZone(0)) or 0] == true;
end

local function is_event_system_active()
    if (event_system_pointer == nil or event_system_pointer == 0) then
        return false;
    end
    local ok, active = pcall(function()
        local pointer = ashita.memory.read_uint32(event_system_pointer + 1);
        return pointer ~= nil and pointer ~= 0
            and ashita.memory.read_uint8(pointer) == 1;
    end);
    return ok and active == true;
end

local function is_interface_hidden()
    if (interface_hidden_pointer == nil or interface_hidden_pointer == 0) then
        return false;
    end
    local ok, hidden = pcall(function()
        local pointer = ashita.memory.read_uint32(interface_hidden_pointer + 10);
        return pointer ~= nil and pointer ~= 0
            and ashita.memory.read_uint8(pointer + 0xB4) == 1;
    end);
    return ok and hidden == true;
end

local function is_cutscene_active()
    local player = GetPlayerEntity();
    return (player ~= nil and player.StatusServer == 4)
        or is_event_system_active()
        or is_interface_hidden();
end

local function should_auto_hide_hud()
    return (state.settings.hide_town and is_town_zone())
        or (state.settings.hide_cutscene and is_cutscene_active());
end

local function get_pet()
    local player = GetPlayerEntity();
    if (player == nil or player.PetTargetIndex == 0) then
        return nil;
    end
    return GetEntity(player.PetTargetIndex);
end

local function has_pet()
    return get_pet() ~= nil;
end

local function animator_equipped()
    local inventory = AshitaCore:GetMemoryManager():GetInventory();
    if (inventory == nil) then
        return false;
    end

    local equipped = inventory:GetEquippedItem(RANGED_EQUIPMENT_SLOT);
    if (equipped == nil or equipped.Index == 0) then
        return false;
    end

    local container = bit.band(equipped.Index, 0xFF00) / 0x0100;
    local index = equipped.Index % 0x0100;
    local item = inventory:GetContainerItem(container, index);
    if (item == nil or item.Id == nil or item.Id == 0) then
        return false;
    end

    local resource = AshitaCore:GetResourceManager():GetItemById(item.Id);
    local name = resource ~= nil and resource.Name ~= nil and resource.Name[1] or nil;
    return type(name) == 'string'
        and string.find(string.lower(name), 'animator', 1, true) ~= nil;
end

local function invalidate_pet_hp()
    state.pet_hp_valid = false;
end

local function exact_pet_hp()
    local pet = get_pet();
    if (pet == nil or not state.pet_hp_valid or state.pet_hp_server_id ~= pet.ServerId) then
        return nil, nil;
    end
    return state.pet_hp_current, state.pet_hp_max;
end

local function print_exact_pet_hp()
    local current_hp, max_hp = exact_pet_hp();
    if (current_hp == nil or max_hp == nil) then
        error_message('Exact automaton HP is not synchronized.');
        return;
    end
    message(('Exact automaton HP: %d/%d%s'):fmt(
        current_hp, max_hp, current_hp == max_hp and ' (FULL)' or ''));
end

local function is_engaged()
    local player = GetPlayerEntity();
    return player ~= nil and player.Status == 1;
end

local function ability_recast(timer_id)
    local recasts = AshitaCore:GetMemoryManager():GetRecast();
    if (recasts == nil) then
        return 0;
    end
    for index = 0, 31 do
        if (recasts:GetAbilityTimerId(index) == timer_id) then
            return math.max(0, recasts:GetAbilityTimer(index) / 60);
        end
    end
    return 0;
end

local function format_recast(seconds)
    if (seconds <= 0.1) then
        return '--';
    end
    if (seconds >= 60) then
        return ('%d:%02d'):fmt(math.floor(seconds / 60), math.floor(seconds % 60));
    end
    return ('%.0f'):fmt(math.ceil(seconds));
end

local function count_automaton_oil()
    local now = os.clock();
    if (now - state.oil_last_sync < 1.0) then
        return state.oil_count;
    end
    state.oil_last_sync = now;
    state.oil_count = 0;

    local inventory = AshitaCore:GetMemoryManager():GetInventory();
    if (inventory == nil) then
        return 0;
    end
    local max_slots = inventory:GetContainerCountMax(0) or 0;
    for index = 1, max_slots do
        local item = inventory:GetContainerItem(0, index);
        if (item ~= nil and oil_item_set[item.Id] == true) then
            state.oil_count = state.oil_count + (item.Count or 0);
        end
    end
    return state.oil_count;
end

local function pet_vitals()
    local pet = get_pet();
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if (pet == nil or player == nil) then
        return nil;
    end
    local current_hp, max_hp = exact_pet_hp();
    local mp_exact = current_hp ~= nil and state.pet_mp_current ~= nil
        and state.pet_mp_max ~= nil and state.pet_mp_max > 0;
    -- Use the live memory percentage for warning responsiveness. The raw 0x44
    -- integers remain useful for the label, but can arrive less frequently.
    local mpp = player:GetPetMPPercent() or 0;
    return {
        hp = current_hp,
        max_hp = max_hp,
        hp_exact = current_hp ~= nil and max_hp ~= nil,
        hpp = pet.HPPercent or 0,
        mp = mp_exact and state.pet_mp_current or nil,
        max_mp = mp_exact and state.pet_mp_max or nil,
        mp_exact = mp_exact,
        has_mp = current_hp ~= nil and state.pet_mp_max ~= nil
            and state.pet_mp_max > 0,
        mpp = mpp,
        tp = math.max(0, math.min(3000, player:GetPetTP() or 0)),
    };
end

local function current_buff_counts()
    local counts = {};
    local overloaded = false;
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if (player == nil) then
        return counts, overloaded;
    end

    for _, buff_id in pairs(player:GetBuffs()) do
        if (buff_id == OVERLOAD_BUFF_ID) then
            overloaded = true;
        elseif (by_buff[buff_id] ~= nil) then
            local name = by_buff[buff_id].name;
            counts[name] = (counts[name] or 0) + 1;
        end
    end
    return counts, overloaded;
end

-- A pet that already exists on the first observation is a cold attach: its
-- spawn time and prior system uses are unknowable. A later zero->pet or
-- pet-id change is a fresh spawn and can use LSB's spawn-recast baseline.
local function synchronize_systems_pet()
    local pet = get_pet();
    local server_id = pet ~= nil and pet.ServerId or 0;
    if (not state.systems_pet_initialized) then
        state.systems_pet_initialized = true;
        state.systems_pet_server_id = server_id;
        if (server_id ~= 0) then
            systems_tracker:cold_attach();
        else
            systems_tracker:on_pet_lost();
        end
        return;
    end
    if (server_id == state.systems_pet_server_id) then
        return;
    end
    state.systems_pet_server_id = server_id;
    if (server_id ~= 0) then
        systems_tracker:on_spawn();
    else
        systems_tracker:on_pet_lost();
    end
end

local function remove_expired(now)
    for index = #state.slots, 1, -1 do
        if (state.slots[index].expires <= now) then
            table.remove(state.slots, index);
        end
    end
end

local function count_slots()
    local counts = {};
    for _, slot in ipairs(state.slots) do
        counts[slot.name] = (counts[slot.name] or 0) + 1;
    end
    return counts;
end

local function total_count(counts)
    local total = 0;
    for _, count in pairs(counts) do
        total = total + count;
    end
    return total;
end

local function record_maneuver(name, approximate, started)
    local now = os.clock();
    local activation_time = started or now;
    remove_expired(now);
    while (#state.slots >= 3) do
        table.remove(state.slots, 1);
    end
    state.slots:append({
        name = name,
        started = activation_time,
        expires = activation_time + MANEUVER_DURATION,
        approximate = approximate == true,
    });
end

local function reconcile_slots()
    local now = os.clock();
    if (now - state.last_sync < 0.25) then
        return;
    end
    state.last_sync = now;
    remove_expired(now);

    if (state.maneuver_request ~= nil
        and now - state.maneuver_request.sent >= MANEUVER_REQUEST_TIMEOUT) then
        state.maneuver_request = nil;
    end

    -- Give the client a moment to apply a buff after its action packet arrives.
    if (now - state.last_action < MANEUVER_BUFF_GRACE_SECONDS) then
        return;
    end

    local actual = current_buff_counts();
    local pending = state.pending_maneuver;
    if (pending ~= nil) then
        local actual_count = actual[pending.name] or 0;
        local actual_total = total_count(actual);
        local count_increased = actual_count > pending.before_count;
        local full_replacement = pending.before_total >= 3 and actual_total >= 3;
        if (count_increased or full_replacement) then
            record_maneuver(pending.name, false, pending.seen);
            state.pending_maneuver = nil;
        elseif (now - pending.seen < MANEUVER_CONFIRM_TIMEOUT) then
            return;
        else
            -- If the live buff count did not confirm the action, discard the
            -- provisional packet result. Generic reconciliation below preserves
            -- the real buffs and leaves the missing maneuver eligible after recast.
            state.pending_maneuver = nil;
        end
    end
    local tracked = count_slots();

    for name, count in pairs(tracked) do
        local excess = count - (actual[name] or 0);
        while (excess > 0) do
            for index, slot in ipairs(state.slots) do
                if (slot.name == name) then
                    table.remove(state.slots, index);
                    break;
                end
            end
            excess = excess - 1;
        end
    end

    tracked = count_slots();
    for name, count in pairs(actual) do
        local missing = count - (tracked[name] or 0);
        while (missing > 0) do
            record_maneuver(name, true);
            missing = missing - 1;
        end
    end
end

local function game_maneuver_recast()
    local game_recast = 0;
    local resource = AshitaCore:GetResourceManager():GetAbilityById(
        MANEUVER_MIN_ID + MANEUVER_RESOURCE_OFFSET);
    if (resource ~= nil) then
        local recast_id = resource.RecastTimerId;
        local recasts = AshitaCore:GetMemoryManager():GetRecast();
        if (recasts ~= nil) then
            for index = 0, 31 do
                if (recasts:GetAbilityTimerId(index) == recast_id) then
                    game_recast = math.max(0, recasts:GetAbilityTimer(index) / 60);
                    break;
                end
            end
        end
    end

    return game_recast;
end

local function maneuver_recast()
    -- Start the local 10-second fallback only after a server action packet.
    -- Queueing a command is not proof that it fired; FFXI can reject it while
    -- resting, standing up, animation-locked, or otherwise unable to act.
    local local_recast = math.max(0,
        MANEUVER_RECAST_SECONDS - (os.clock() - state.last_action));
    return math.max(game_maneuver_recast(), local_recast);
end

local function maneuver_risk(name, overloaded)
    local risk = {
        name = name,
        label = 'UNKNOWN',
        color = toau_theme.brass_dim,
        score = nil,
        score_upper = nil,
        quality = nil,
        safe_seconds = nil,
        safe_seconds_upper = nil,
        gain = nil,
    };
    if (name == nil) then
        if (overloaded) then
            risk.label = 'OVERLOAD';
            risk.color = { 1.00, 0.20, 0.15, 1.00 };
            risk.score = 100;
        end
        return risk;
    end

    local element = by_name[string.lower(tostring(name))];
    if (element == nil) then
        risk.quality = 'unknown';
        return risk;
    end
    local projected = forecast.predict(
        burden_model, element.burden_index, overloaded);
    risk.label = projected.label;
    risk.score = projected.score ~= nil
        and math.floor(projected.score + 0.5) or nil;
    risk.score_upper = projected.score_upper ~= nil
        and math.floor(projected.score_upper + 0.5) or nil;
    risk.quality = projected.quality;
    risk.safe_seconds = projected.safe_seconds;
    risk.safe_seconds_upper = projected.safe_seconds_upper;
    risk.gain = projected.gain;

    if (risk.label == forecast.RISK.OVERLOAD) then
        risk.color = { 1.00, 0.20, 0.15, 1.00 };
    elseif (risk.label == forecast.RISK.DANGER) then
        risk.color = { 1.00, 0.25, 0.20, 1.00 };
    elseif (risk.label == forecast.RISK.WARM) then
        risk.color = { 1.00, 0.75, 0.20, 1.00 };
    elseif (risk.label == forecast.RISK.LOW) then
        risk.color = { 0.35, 0.90, 0.45, 1.00 };
    elseif (risk.label == forecast.RISK.SAFE) then
        risk.color = { 0.30, 0.78, 0.72, 1.00 };
    end
    return risk;
end

local function missing_plan_maneuvers(active)
    local remaining = {};
    for name, count in pairs(active) do
        remaining[name] = count;
    end

    local missing = T{};
    for _, name in ipairs(state.settings.plan) do
        if ((remaining[name] or 0) > 0) then
            remaining[name] = remaining[name] - 1;
        else
            missing:append(name);
        end
    end
    return missing;
end

local function planned_maneuver(active, now)
    -- The live buff list decides whether the plan is complete. Tracked slots
    -- provide activation order and refresh timing, but never prove that a
    -- maneuver landed.
    local missing = missing_plan_maneuvers(active);
    if (#missing > 0) then
        local name = missing[1];
        return name, 'Fill missing ' .. name, 'MISSING', true, missing;
    end

    local oldest = state.slots[1];
    if (oldest ~= nil) then
        local remaining = oldest.expires - now;
        if (remaining <= state.settings.refresh_at) then
            return oldest.name,
                ('Refresh oldest (%.0fs left)'):fmt(math.max(0, remaining)),
                ('REFRESH %.0fs'):fmt(math.max(0, remaining)), true, missing;
        end
        local until_refresh = math.max(0,
            remaining - state.settings.refresh_at);
        return oldest.name,
            ('Plan stable - refresh in %.0fs'):fmt(until_refresh),
            ('STABLE %.0fs'):fmt(until_refresh), false, missing;
    end

    return state.settings.plan[1], 'Start plan', 'START', true, missing;
end

local function overload_skip_limit()
    local guard = tonumber(state.settings.burden_guard) or -1;
    return guard >= 0 and guard or 0;
end

local function overload_skip_ready(risk)
    local score = risk.score_upper or risk.score;
    return score ~= nil and score <= overload_skip_limit();
end

-- One evaluation supplies execution and every HUD component. action_name is
-- non-nil only when /pm n may act now; planned_name remains populated while
-- waiting so burden always refers to the actual eventual plan element.
local function decision_snapshot()
    local now = os.clock();
    if (burden_model.heatsink ~= effective_heatsink()) then
        configure_burden_model();
    end
    local decision = {
        evaluated_at = now,
        action_name = nil,
        planned_name = nil,
        reason = 'Hold',
        status = 'HOLD',
        recast = maneuver_recast(),
        active_counts = {},
        overloaded = false,
        risk = maneuver_risk(nil, false),
        vitals = pet_vitals(),
    };
    if (not has_pet()) then
        decision.reason = 'No automaton';
        decision.status = 'NO PET';
        return decision;
    end

    local active, observed_overload = current_buff_counts();
    decision.active_counts = active;
    decision.overloaded = observed_overload or burden_model:is_overloaded();
    local planning_counts = {};
    for name, count in pairs(active) do planning_counts[name] = count; end
    local planned, reason, status, due, missing = planned_maneuver(
        planning_counts, now);
    decision.planned_name = planned;
    decision.reason = reason;
    decision.status = status;
    decision.risk = maneuver_risk(planned, decision.overloaded);

    if (decision.overloaded) then
        decision.reason = 'OVERLOADED - let burden cool';
        decision.status = 'OVERLOAD';
        return decision;
    end

    local skip = state.overload_skip;
    if (skip ~= nil) then
        local skip_risk = maneuver_risk(skip.name, false);
        if (overload_skip_ready(skip_risk)) then
            state.overload_skip = nil;
        elseif (due and missing ~= nil and #missing > 0
            and planned == skip.name) then
            local alternative = nil;
            for _, candidate in ipairs(missing) do
                if (candidate ~= skip.name) then
                    alternative = candidate;
                    break;
                end
            end

            if (alternative ~= nil) then
                planned = alternative;
                decision.planned_name = alternative;
                decision.reason = ('Skip %s after overload; fill missing %s'):fmt(
                    skip.name, alternative);
                decision.status = 'SKIP ' .. string.upper(skip.name);
                decision.risk = maneuver_risk(alternative, false);
            else
                local safe = skip_risk.safe_seconds_upper
                    or skip_risk.safe_seconds;
                decision.planned_name = skip.name;
                decision.risk = skip_risk;
                decision.reason = safe ~= nil
                    and ('Cooling %s after overload; safe in ~%.0fs'):fmt(
                        skip.name, safe)
                    or ('Cooling %s after overload'):fmt(skip.name);
                decision.status = safe ~= nil
                    and ('COOL %.0fs'):fmt(safe)
                    or ('COOL ' .. string.upper(skip.name));
                return decision;
            end
        end
    end

    if (not animator_equipped()) then
        decision.reason = 'No Animator equipped';
        decision.status = 'NO ANIMATOR';
        return decision;
    elseif (decision.recast > 0.1) then
        decision.reason = ('Maneuver ready in %.1fs'):fmt(decision.recast);
        decision.status = 'RECAST';
        return decision;
    elseif (not due) then
        return decision;
    end

    local guard = state.settings.burden_guard or -1;
    if (guard >= 0) then
        if (decision.risk.score == nil) then
            decision.reason = 'Burden guard: risk unknown; use a direct maneuver to override';
            decision.status = 'BURDEN UNKNOWN';
            return decision;
        end
        local guard_score = decision.risk.score_upper
            or decision.risk.score;
        if (guard_score > guard) then
            local safe = decision.risk.safe_seconds_upper
                or decision.risk.safe_seconds;
            decision.reason = safe ~= nil
                and ('Burden guard: up to %d%%; safe in ~%.0fs'):fmt(
                    guard_score, safe)
                or ('Burden guard: up to %d%%'):fmt(guard_score);
            decision.status = safe ~= nil
                and ('COOL %.0fs'):fmt(safe) or 'BURDEN GUARD';
            return decision;
        end
    end

    decision.action_name = planned;
    return decision;
end

local function use_maneuver(name, user_initiated)
    -- Maneuvers may only be queued from a direct player command. No packet,
    -- render, timer, or status event is allowed to invoke an action.
    if (user_initiated ~= true) then
        error_message('Blocked a maneuver from an unknown action source.');
        return;
    end

    local element = by_name[string.lower(name or '')];
    if (element == nil) then
        error_message('Unknown element: ' .. tostring(name));
        return;
    end
    if (not is_pup()) then
        error_message('Your main job is not Puppetmaster.');
        return;
    end
    if (not has_pet()) then
        error_message('You do not have an active automaton.');
        return;
    end
    if (not animator_equipped()) then
        error_message('Equip an Animator before using a maneuver.');
        return false;
    end
    local recast = maneuver_recast();
    if (recast > 0.1) then
        message(('Maneuver ready in %.1fs.'):fmt(recast));
        return false;
    end
    local now = os.clock();
    if (state.maneuver_request ~= nil
        and now - state.maneuver_request.sent < MANEUVER_ATTEMPT_GUARD_SECONDS) then
        return false;
    end
    local actual = current_buff_counts();
    state.maneuver_request = {
        name = element.name,
        sent = now,
        before_count = actual[element.name] or 0,
        before_total = total_count(actual),
    };
    AshitaCore:GetChatManager():QueueCommand(-1, ('/ja "%s Maneuver" <me>'):fmt(element.name));
    return true;
end

local function use_next(user_initiated)
    local decision = decision_snapshot();
    if (decision.action_name == nil) then
        message(decision.reason);
        return;
    end
    use_maneuver(decision.action_name, user_initiated);
end

local function use_repair(user_initiated)
    if (user_initiated ~= true) then
        error_message('Blocked Repair from an unknown action source.');
        return;
    end
    if (not is_pup()) then
        error_message('Repair requires Puppetmaster as your main job.');
        return;
    end
    if (not has_pet()) then
        error_message('You do not have an active automaton.');
        return;
    end
    local oils = count_automaton_oil();
    if (oils <= 0) then
        error_message('No automaton oil was found in your inventory.');
        return;
    end
    local recast = ability_recast(206);
    if (recast > 0.1) then
        error_message(('Repair ready in %.1fs.'):fmt(recast));
        return;
    end
    AshitaCore:GetChatManager():QueueCommand(-1, '/ja "Repair" <me>');
    message(('Repair queued (%d oil remaining before use).'):fmt(oils));
end

local function use_deactivate(user_initiated)
    if (user_initiated ~= true) then
        error_message('Blocked Deactivate from an unknown action source.');
        return;
    end
    if (not is_pup()) then
        error_message('Deactivate requires Puppetmaster as your main job.');
        return;
    end
    local pet = get_pet();
    if (pet == nil) then
        error_message('You do not have an active automaton.');
        return;
    end

    local current_hp, max_hp = exact_pet_hp();
    if (current_hp == nil or max_hp == nil) then
        error_message('Exact automaton HP is not synchronized yet; no action was taken.');
        return;
    end
    if (max_hp <= 0 or current_hp ~= max_hp) then
        error_message(('Automaton is not exactly full HP (%d/%d); no action was taken.'):fmt(
            current_hp, max_hp));
        return;
    end
    local deactivate_recast = ability_recast(208);
    if (deactivate_recast > 0.1) then
        error_message(('Deactivate ready in %.1fs; no action was taken.'):fmt(deactivate_recast));
        return;
    end

    AshitaCore:GetChatManager():QueueCommand(-1, '/ja "Deactivate" <me>');
    message(('Exact HP confirmed (%d/%d). Deactivate queued.'):fmt(
        current_hp, max_hp));
end

local function deactivate_readiness()
    if (not has_pet()) then
        return 'DA: NO PET', { 0.95, 0.35, 0.30, 1.00 };
    end
    local current_hp, max_hp = exact_pet_hp();
    if (current_hp == nil or max_hp == nil) then
        return 'DA: HP STALE', { 1.00, 0.72, 0.20, 1.00 };
    end
    if (current_hp ~= max_hp) then
        return ('DA: HP %d/%d'):fmt(current_hp, max_hp), { 1.00, 0.72, 0.20, 1.00 };
    end
    local recast = ability_recast(208);
    if (recast > 0.1) then
        return ('DA: %.0fs'):fmt(math.ceil(recast)), { 1.00, 0.72, 0.20, 1.00 };
    end
    return 'DA READY', { 0.35, 0.90, 0.45, 1.00 };
end

local function normalize_plan(names)
    if (#names ~= 3) then
        error_message('A plan needs exactly three elements.');
        return nil;
    end
    local plan = T{};
    for _, name in ipairs(names) do
        local element = by_name[string.lower(name)];
        if (element == nil) then
            error_message('Unknown element: ' .. tostring(name));
            return nil;
        end
        plan:append(element.name);
    end
    return plan;
end

local function apply_plan(plan, announce)
    state.settings.plan = plan;
    if (announce ~= false) then
        message(('Plan: %s / %s / %s'):fmt(plan[1], plan[2], plan[3]));
    end
end

local function set_plan(names)
    local plan = normalize_plan(names);
    if (plan == nil) then
        return false;
    end
    state.settings.mode = 'custom';
    state.settings.mode_plans.custom = copy_plan(plan);
    state.active_mode = 'custom';
    apply_plan(plan, true);
    settings.save();
    return true;
end

local function profile_key()
    return ('%d:%d'):fmt(state.automaton_head or 0, state.automaton_frame or 0);
end

local function resolve_profile_mode()
    local configured = state.settings.profiles[profile_key()];
    if (configured ~= nil and state.settings.mode_plans[configured] ~= nil) then
        return configured;
    end
    local by_head = {
        [1] = 'balanced', [2] = 'melee', [3] = 'ranged',
        [4] = 'nuker', [5] = 'healer', [6] = 'nuker',
    };
    if (by_head[state.automaton_head] ~= nil) then
        return by_head[state.automaton_head];
    end
    local by_frame = { [20] = 'balanced', [21] = 'melee', [22] = 'ranged', [23] = 'nuker' };
    return by_frame[state.automaton_frame] or 'balanced';
end

local function apply_selected_mode(announce)
    local selected = state.settings.mode;
    local active = selected == 'profile' and resolve_profile_mode() or selected;
    local plan = state.settings.mode_plans[active];
    if (plan == nil) then
        active = 'balanced';
        plan = state.settings.mode_plans.balanced;
    end
    state.active_mode = active;
    apply_plan(copy_plan(plan), false);
    if (announce ~= false) then
        local prefix = selected == 'profile' and 'Profile' or 'Mode';
        message(('%s: %s (%s / %s / %s)'):fmt(
            prefix, active, plan[1], plan[2], plan[3]));
    end
end

local function set_mode(name)
    name = string.lower(name or '');
    if (name ~= 'profile' and state.settings.mode_plans[name] == nil) then
        error_message('Unknown mode. Use: profile, balanced, melee, ranged, tank, healer, or nuker.');
        return false;
    end
    state.settings.mode = name;
    apply_selected_mode(true);
    settings.save();
    return true;
end

local function set_mode_plan(mode, names)
    mode = string.lower(mode or '');
    if (mode == '' or mode == 'profile') then
        error_message('Choose a named mode to configure.');
        return false;
    end
    local plan = normalize_plan(names);
    if (plan == nil) then
        return false;
    end
    state.settings.mode_plans[mode] = copy_plan(plan);
    if (state.settings.mode == mode or (state.settings.mode == 'profile' and resolve_profile_mode() == mode)) then
        apply_selected_mode(false);
    end
    settings.save();
    message(('Mode %s saved: %s / %s / %s'):fmt(mode, plan[1], plan[2], plan[3]));
    return true;
end

local function set_current_profile(mode)
    mode = string.lower(mode or '');
    if (state.automaton_head == 0 or state.automaton_frame == 0) then
        error_message('Head/frame data is not synchronized yet.');
        return;
    end
    if (state.settings.mode_plans[mode] == nil) then
        error_message('Unknown mode for this profile.');
        return;
    end
    state.settings.profiles[profile_key()] = mode;
    if (state.settings.mode == 'profile') then
        apply_selected_mode(false);
    end
    settings.save();
    message(('Profile %s/%s -> %s'):fmt(
        automaton_heads[state.automaton_head] or state.automaton_head,
        automaton_frames[state.automaton_frame] or state.automaton_frame, mode));
end

local function set_preset(name)
    set_mode(name);
end

local function print_recast_status()
    local parts = {};
    for _, ability in ipairs(pup_recasts) do
        parts[#parts + 1] = ('%s %s'):fmt(ability.short, format_recast(ability_recast(ability.id)));
    end
    message('Recasts: ' .. table.concat(parts, ' | '));
end

local function print_burden_status()
    configure_burden_model();
    burden_model:tick();
    local half_dark = state.automaton_frame == 21
        or state.automaton_frame == 22;
    local heatsink = effective_heatsink();
    local heatsink_mode = state.settings.burden_heatsink_mode;
    local guard = state.settings.burden_guard >= 0
        and (tostring(state.settings.burden_guard) .. '%') or 'off';
    message(('Burden model: threshold +%d | Heatsink %s (%s) | guard %s | Water %d | decay %d/tick | half-dark %s (auto).'):fmt(
        state.settings.burden_threshold,
        heatsink and 'on' or 'off', heatsink_mode,
        guard,
        burden_model.water_maneuvers or 0,
        burden_model:decay_per_tick(),
        half_dark and 'on' or 'off'));
    local parts = {};
    for ability_id = MANEUVER_MIN_ID, MANEUVER_MAX_ID do
        local element = elements[ability_id];
        local projected = forecast.predict(
            burden_model, element.burden_index, false);
        parts[#parts + 1] = projected.score == nil
            and (element.name .. '=?/' .. projected.quality)
            or (('%s=%d%%/%s'):fmt(
                element.name, math.floor(projected.score + 0.5),
                projected.quality));
        if (#parts == 4) then
            message('Next-maneuver chances: ' .. table.concat(parts, ' | '));
            parts = {};
        end
    end
    if (#parts > 0) then
        message('Next-maneuver chances: ' .. table.concat(parts, ' | '));
    end
    for _, group in ipairs(burden_stats:summary_groups(4)) do
        message('Burden stats (master-pet): ' .. group);
    end
end

local function print_systems_status()
    configure_systems_tracker();
    message(('Puppet Systems panel: %s, %s side.'):fmt(
        state.settings.systems_visible and 'on' or 'off',
        state.settings.systems_side));
    if (not has_pet()) then
        message('Puppet Systems: no active automaton.');
        return;
    end
    local counts = current_buff_counts();
    local vitals = pet_vitals();
    local rows = systems_tracker:rows({
        maneuvers = counts,
        hpp = vitals ~= nil and vitals.hpp or nil,
        mpp = vitals ~= nil and vitals.mpp or nil,
    });
    if (#rows == 0) then
        message(state.automaton_frame == 0
            and 'Puppet Systems: waiting for PUP attachment data.'
            or 'Puppet Systems: no timed systems equipped.');
        return;
    end
    for _, row in ipairs(rows) do
        local value = row.status;
        if (row.known and row.remaining > 0) then
            local seconds = math.ceil(row.remaining);
            value = seconds >= 60
                and ('~%d:%02d'):fmt(math.floor(seconds / 60), seconds % 60)
                or ('~%ds'):fmt(seconds);
        elseif (row.known and row.eligible) then
            value = 'READY';
        end
        message(('System %s: %s%s | LSB %.0fs'):fmt(
            row.name, value,
            row.element ~= nil and (' | ' .. row.element) or '',
            row.cooldown));
    end
end

local function print_help()
    local lines = T{
        '/pm - show or hide the HUD',
        '/pm n - use the recommended maneuver once',
        '/pm f|i|w|e|t|wa|l|d - use an element',
        '/pm 1|2|3 - use that slot from your plan',
        '/pm da - use Deactivate once at exact full HP',
        '/pm hp - print the synchronized raw HP values',
        '/pm repair - use Repair once when ready and oil is available',
        '/pm repairwarn <0-99> - set the HUD HP warning threshold',
        '/pm mode <profile|balanced|melee|ranged|tank|healer|nuker>',
        '/pm mode set <name> <element> <element> <element>',
        '/pm profile <mode> - bind the current head/frame profile',
        '/pm layout <compact|micro>',
        '/pm systems <on|off|toggle|status|side left|right>',
        '/pm autohide | townhide | cshide [on|off]',
        '/pm colorblind [on|off] - toggle the alternate element palette',
        '/pm burden [status|reset] - inspect or reset the burden model',
        '/pm burden threshold <0|5> | heatsink <auto|on|off>',
        '/pm burden guard <off|0-100> - optional /pm n safety hold',
        '/pm burden log <on|off|status> | note <text>',
        '/pm recasts - print all PUP ability recasts',
        '/pm plan <element> <element> <element> - set the plan',
        '/pm p <preset> - balanced, melee, ranged, tank, healer, or nuker',
        '/pm keys - print example keyboard binds',
        '/pm pos <x> <y> | /pm nudge <direction> [pixels]',
        '/pm show | hide | reset | help',
    };
    message('Commands:');
    for _, line in ipairs(lines) do
        print(chat.header(addon.name):append(chat.color1(6, line)));
    end
end

settings.register('settings', 'settings_update', function(s)
    if (s ~= nil) then
        state.settings = s;
    end
    ensure_settings_shape();
    configure_burden_model();
    configure_systems_tracker();
    apply_selected_mode(false);
    state.maneuver_request = nil;
    state.pending_maneuver = nil;
    petstatus.clear();
    invalidate_pet_hp();
    state.first_draw = true;
    settings.save();
end);

ashita.events.register('load', 'load_cb', function()
    load_hud_font();
    state.maneuver_request = nil;
    state.pending_maneuver = nil;
    petstatus.clear();
    invalidate_pet_hp();
    ensure_settings_shape();
    configure_burden_model();
    configure_systems_tracker();
    state.systems_pet_initialized = false;
    state.systems_pet_server_id = 0;
    apply_selected_mode(false);
    settings.save();
    state.open[1] = state.settings.visible;
    reconcile_slots();
    message('Loaded. Type /pm help for commands.');
end);

ashita.events.register('unload', 'unload_cb', function()
    burden_model:detach();
    burden_stats:detach();
    state.maneuver_request = nil;
    state.pending_maneuver = nil;
    petstatus.clear();
    settings.save();
end);

ashita.events.register('packet_in', 'packet_in_cb', function(e)
    if (e.id == 0x000A or e.id == 0x000B) then
        petstatus.clear();
        systems_tracker:on_pet_lost();
        state.overload_skip = nil;
        state.systems_pet_initialized = false;
        state.systems_pet_server_id = 0;
        return;
    end

    -- PUP job-stat packet. These are raw integer HP values, not the rounded
    -- percentage exposed by the entity table.
    if (e.id == 0x0044) then
        local data = e.data_modified or e.data_raw;
        if (data == nil or #data < 0x70) then
            return;
        end
        local job = data:byte(0x04 + 1);
        local is_subjob = data:byte(0x05 + 1);
        if (job ~= PUP_JOB_ID or is_subjob ~= 0) then
            return;
        end

        -- The shared provider also subscribes to 0x44 itself. Re-accepting the
        -- packet here is idempotent and guarantees attachment-derived config
        -- is current before this handler reconfigures the burden model,
        -- regardless of event callback ordering.
        burden_stats:on_job_info(data);
        local head = data:byte(0x08 + 1);
        local frame = data:byte(0x09 + 1);
        local current_hp = struct.unpack('H', data, 0x68 + 1);
        local max_hp = struct.unpack('H', data, 0x6A + 1);
        local current_mp = struct.unpack('H', data, 0x6C + 1);
        local max_mp = struct.unpack('H', data, 0x6E + 1);
        local pet = get_pet();
        local profile_changed = head ~= state.automaton_head or frame ~= state.automaton_frame;
        state.automaton_head = head;
        state.automaton_frame = frame;
        configure_burden_model();
        configure_systems_tracker();
        state.pet_hp_current = current_hp;
        state.pet_hp_max = max_hp;
        state.pet_mp_current = current_mp;
        state.pet_mp_max = max_mp;
        state.pet_hp_updated = os.clock();
        state.pet_hp_server_id = pet ~= nil and pet.ServerId or 0;
        state.pet_hp_valid = pet ~= nil and max_hp > 0 and current_hp <= max_hp;
        if (profile_changed and state.settings.mode == 'profile') then
            apply_selected_mode(true);
            settings.save();
        end
        return;
    end

    -- Pet-status packets do not expose raw HP, but they are useful for
    -- invalidating a previously exact snapshot. A percentage is never used
    -- to authorize Deactivate.
    if (e.id == 0x0068) then
        local data = e.data_modified or e.data_raw;
        local player = GetPlayerEntity();
        local pet = get_pet();
        if (data == nil or #data < 0x18 or player == nil or pet == nil) then
            return;
        end
        local owner_id = struct.unpack('I', data, 0x08 + 1);
        if (owner_id ~= player.ServerId) then
            return;
        end

        local hpp = data:byte(0x0E + 1);
        local mpp = data:byte(0x0F + 1);
        local tp = struct.unpack('I', data, 0x10 + 1);
        local target_id = struct.unpack('I', data, 0x14 + 1);
        if (state.pet_status_server_id ~= pet.ServerId) then
            if (state.pet_hp_valid) then
                invalidate_pet_hp();
            end
        elseif (state.pet_status_hpp ~= nil) then
            local hp_percent_changed = hpp ~= state.pet_status_hpp;
            local otherwise_unchanged = mpp == state.pet_status_mpp
                and tp == state.pet_status_tp and target_id == state.pet_status_target;
            if (hp_percent_changed or otherwise_unchanged) then
                invalidate_pet_hp();
            end
        elseif (state.pet_hp_valid) then
            invalidate_pet_hp();
        end

        state.pet_status_server_id = pet.ServerId;
        state.pet_status_hpp = hpp;
        state.pet_status_mpp = mpp;
        state.pet_status_tp = tp;
        state.pet_status_target = target_id;
        return;
    end

    -- A direct action message targeting the automaton may have changed HP.
    -- Invalidate the exact snapshot until the next raw PUP stat packet.
    if (e.id == 0x0029) then
        local data = e.data_modified or e.data_raw;
        local pet = get_pet();
        if (data ~= nil and pet ~= nil) then
            petstatus.handle_message(data, pet.ServerId);
        end
        if (data ~= nil and #data >= 0x0C and pet ~= nil) then
            local target_id = struct.unpack('I', data, 0x08 + 1);
            if (target_id == pet.ServerId) then
                invalidate_pet_hp();
            end
        end
        return;
    end

    if (e.id ~= 0x0028) then
        return;
    end

    local ok, packet = pcall(actionpacket.parse, e);
    if (not ok or packet == nil) then
        return;
    end

    local player = GetPlayerEntity();
    if (player ~= nil and packet.UserId == player.ServerId
        and packet.Id == ACTIVATE_ABILITY_ID) then
        -- A fresh automaton has fresh elemental burden. Overload itself lives
        -- on the master and is still enforced separately by the live buff.
        state.overload_skip = nil;
    end

    local pet = get_pet();
    if (pet ~= nil) then
        petstatus.handle_action(packet, pet.ServerId);
        if (packet.UserId == pet.ServerId) then
            systems_tracker:on_action(packet.Id);
        end
        for _, target in ipairs(packet.Targets) do
            if (target.Id == pet.ServerId) then
                invalidate_pet_hp();
                break;
            end
        end
    end

    if (packet.Id < MANEUVER_MIN_ID or packet.Id > MANEUVER_MAX_ID) then
        return;
    end

    if (player == nil or packet.UserId ~= player.ServerId) then
        return;
    end

    local element = elements[packet.Id];
    for _, target in ipairs(packet.Targets) do
        for _, action in ipairs(target.Actions) do
            if (action.Message == 798 or action.Message == 799) then
                local now = os.clock();
                state.last_action = now;

                if (action.Message == 798) then
                    local request = state.maneuver_request;
                    if (request ~= nil and request.name == element.name
                        and now - request.sent <= MANEUVER_REQUEST_TIMEOUT) then
                        state.pending_maneuver = {
                            name = element.name,
                            seen = now,
                            before_count = request.before_count,
                            before_total = request.before_total,
                        };
                    else
                        local tracked = count_slots();
                        state.pending_maneuver = {
                            name = element.name,
                            seen = now,
                            before_count = tracked[element.name] or 0,
                            before_total = total_count(tracked),
                        };
                    end
                else
                    state.pending_maneuver = nil;
                    state.overload_skip = {
                        name = element.name,
                        seen = now,
                    };
                end
                state.maneuver_request = nil;
                return;
            end
        end
    end
end);

ashita.events.register('command', 'command_cb', function(e)
    local args = e.command:args();
    if (#args == 0) then
        return;
    end
    local root = string.lower(args[1]);
    if (root ~= '/pupman' and root ~= '/pm') then
        return;
    end
    e.blocked = true;

    local command = string.lower(args[2] or 'toggle');
    if (command == 'toggle') then
        state.settings.visible = not state.settings.visible;
        state.open[1] = state.settings.visible;
    elseif (command == 'show') then
        state.settings.visible = true;
        state.open[1] = true;
    elseif (command == 'hide') then
        state.settings.visible = false;
        state.open[1] = false;
    elseif (command == 'lock' or command == 'unlock' or command == 'controls') then
        message('The HUD is always click-through. Use /pm pos or /pm nudge to move it.');
    elseif (command == 'next' or command == 'go' or command == 'n') then
        use_next(true);
    elseif (command == 'da' or command == 'deactivate') then
        use_deactivate(true);
    elseif (command == 'hp') then
        print_exact_pet_hp();
    elseif (command == 'repair' or command == 'rep') then
        use_repair(true);
    elseif (command == 'repairwarn' and tonumber(args[3]) ~= nil) then
        state.settings.repair_warn_at = math.max(0, math.min(99, math.floor(tonumber(args[3]))));
        message(('Repair warning: %d%% HP.'):fmt(state.settings.repair_warn_at));
    elseif (command == 'mode') then
        local option = string.lower(args[3] or 'status');
        if (option == 'status') then
            message(('Mode: %s%s'):fmt(state.settings.mode,
                state.settings.mode == 'profile' and (' -> ' .. state.active_mode) or ''));
        elseif (option == 'set') then
            set_mode_plan(args[4], T{ args[5], args[6], args[7] });
        else
            set_mode(option);
        end
    elseif (command == 'profile' and args[3] ~= nil) then
        set_current_profile(args[3]);
    elseif (command == 'colorblind' or command == 'cb') then
        local option = string.lower(args[3] or 'toggle');
        if (option == 'on') then
            state.settings.colorblind = true;
        elseif (option == 'off') then
            state.settings.colorblind = false;
        elseif (option == 'toggle') then
            state.settings.colorblind = not state.settings.colorblind;
        else
            error_message('Use /pm colorblind, /pm colorblind on, or /pm colorblind off.');
            return;
        end
        message('Colorblind element palette: ' .. (state.settings.colorblind and 'on.' or 'off.'));
    elseif (command == 'burden') then
        local option = string.lower(args[3] or 'status');
        if (option == 'reset') then
            if (has_pet()) then
                burden_model:on_cold_attach();
            else
                burden_model:on_deactivate();
            end
            state.overload_skip = nil;
            message('Burden projections reset; elements are unknown until anchored.');
        elseif (option == 'status') then
            print_burden_status();
        elseif (option == 'threshold') then
            local threshold = tonumber(args[4]);
            if (threshold ~= 0 and threshold ~= 5) then
                error_message('Use /pm burden threshold 0 or 5.');
                return;
            end
            state.settings.burden_threshold = threshold;
            configure_burden_model();
            message(('Burden threshold gear: +%d.'):fmt(threshold));
        elseif (option == 'heatsink') then
            local value = string.lower(args[4] or '');
            if (value ~= 'auto' and value ~= 'on' and value ~= 'off') then
                error_message('Use /pm burden heatsink auto, on, or off.');
                return;
            end
            state.settings.burden_heatsink_mode = value;
            configure_burden_model();
            message(('Burden Heatsink: %s (effective %s).'):fmt(
                value, effective_heatsink() and 'on' or 'off'));
        elseif (option == 'guard') then
            local value = string.lower(args[4] or 'status');
            if (value == 'status') then
                message(state.settings.burden_guard >= 0
                    and ('Burden guard: allow up to %d%% for /pm n.'):fmt(
                        state.settings.burden_guard)
                    or 'Burden guard: off.');
            elseif (value == 'off') then
                state.settings.burden_guard = -1;
                message('Burden guard: off.');
            else
                local limit = tonumber(value);
                if (limit == nil or limit < 0 or limit > 100) then
                    error_message('Use /pm burden guard off or a percent from 0 to 100.');
                    return;
                end
                state.settings.burden_guard = math.floor(limit);
                message(('Burden guard: /pm n will hold above %d%%.'):fmt(
                    state.settings.burden_guard));
            end
        elseif (option == 'log') then
            local value = string.lower(args[4] or 'status');
            if (value == 'on') then
                start_burden_log();
            elseif (value == 'off') then
                stop_burden_log();
            elseif (value == 'status') then
                print_burden_log_status();
            else
                error_message('Use /pm burden log on, off, or status.');
                return;
            end
        elseif (option == 'note') then
            if (not burden_model:telemetry_enabled()) then
                error_message('Start telemetry with /pm burden log on first.');
                return;
            end
            local words = {};
            for index = 4, #args do words[#words + 1] = args[index]; end
            local note = table.concat(words, ' ');
            if (note == '') then
                error_message('Use /pm burden note <text>.');
                return;
            end
            burden_model:telemetry_note(note);
            message('Burden telemetry note recorded.');
        else
            error_message('Use /pm burden status, reset, threshold, heatsink, guard, log, or note.');
        end
    elseif (command == 'layout') then
        local layout = string.lower(args[3] or '');
        if (layout ~= 'compact' and layout ~= 'micro') then
            error_message('Use /pm layout compact or /pm layout micro.');
        else
            state.settings.layout = layout;
            state.first_draw = true;
            message('HUD layout: ' .. layout .. '.');
        end
    elseif (command == 'systems' or command == 'system') then
        local option = string.lower(args[3] or 'toggle');
        if (option == 'on') then
            state.settings.systems_visible = true;
            message('Puppet Systems panel: on.');
        elseif (option == 'off') then
            state.settings.systems_visible = false;
            message('Puppet Systems panel: off.');
        elseif (option == 'toggle') then
            state.settings.systems_visible = not state.settings.systems_visible;
            message('Puppet Systems panel: '
                .. (state.settings.systems_visible and 'on.' or 'off.'));
        elseif (option == 'status') then
            print_systems_status();
        elseif (option == 'side' or option == 'left' or option == 'right') then
            local side = option == 'side' and string.lower(args[4] or '') or option;
            if (side ~= 'left' and side ~= 'right') then
                error_message('Use /pm systems side left or right.');
                return;
            end
            state.settings.systems_side = side;
            message('Puppet Systems panel side: ' .. side .. '.');
        else
            error_message('Use /pm systems on, off, status, or side left/right.');
            return;
        end
    elseif (command == 'autohide' or command == 'townhide'
        or command == 'cshide') then
        local option = string.lower(args[3] or 'toggle');
        local current = command == 'townhide' and state.settings.hide_town
            or command == 'cshide' and state.settings.hide_cutscene
            or (state.settings.hide_town and state.settings.hide_cutscene);
        local value = nil;
        if (option == 'on') then
            value = true;
        elseif (option == 'off') then
            value = false;
        elseif (option == 'toggle') then
            value = not current;
        end
        if (value == nil) then
            error_message('Use /pm ' .. command .. ' on or /pm '
                .. command .. ' off.');
            return;
        end
        if (command == 'autohide') then
            state.settings.hide_town = value;
            state.settings.hide_cutscene = value;
            message('Town and cutscene auto-hide: '
                .. (value and 'on.' or 'off.'));
        elseif (command == 'townhide') then
            state.settings.hide_town = value;
            message('Town auto-hide: ' .. (value and 'on.' or 'off.'));
        else
            state.settings.hide_cutscene = value;
            message('Cutscene auto-hide: ' .. (value and 'on.' or 'off.'));
        end
    elseif (command == 'recasts') then
        print_recast_status();
    elseif (command == '1' or command == '2' or command == '3') then
        use_maneuver(state.settings.plan[tonumber(command)], true);
    elseif (command == 'use' and args[3] ~= nil) then
        use_maneuver(args[3], true);
    elseif (by_name[command] ~= nil) then
        use_maneuver(command, true);
    elseif (command == 'f' or command == 'i' or command == 'w' or command == 'e'
        or command == 't' or command == 'wa' or command == 'l' or command == 'd') then
        local quick_elements = {
            f = 'Fire', i = 'Ice', w = 'Wind', e = 'Earth',
            t = 'Thunder', wa = 'Water', l = 'Light', d = 'Dark',
        };
        use_maneuver(quick_elements[command], true);
    elseif (command == 'plan') then
        set_plan(T{ args[3], args[4], args[5] });
    elseif ((command == 'preset' or command == 'p') and args[3] ~= nil) then
        set_preset(args[3]);
    elseif (command == 'keys' or command == 'binds') then
        message('Example: /bind ^F8 /pm n');
    elseif (command == 'pos' and tonumber(args[3]) ~= nil and tonumber(args[4]) ~= nil) then
        state.settings.position_x = math.floor(tonumber(args[3]));
        state.settings.position_y = math.floor(tonumber(args[4]));
        state.first_draw = true;
        message(('HUD position: %d, %d'):fmt(state.settings.position_x, state.settings.position_y));
    elseif (command == 'nudge') then
        local direction = string.lower(args[3] or '');
        local distance = math.max(1, math.min(100, math.floor(tonumber(args[4]) or 10)));
        if (direction == 'left') then
            state.settings.position_x = state.settings.position_x - distance;
        elseif (direction == 'right') then
            state.settings.position_x = state.settings.position_x + distance;
        elseif (direction == 'up') then
            state.settings.position_y = state.settings.position_y - distance;
        elseif (direction == 'down') then
            state.settings.position_y = state.settings.position_y + distance;
        else
            error_message('Use /pm nudge <left|right|up|down> [pixels].');
            return;
        end
        state.first_draw = true;
        message(('HUD position: %d, %d'):fmt(state.settings.position_x, state.settings.position_y));
    elseif (command == 'reset') then
        settings.reset();
        ensure_settings_shape();
        configure_burden_model();
        configure_systems_tracker();
        state.slots = T{};
        state.maneuver_request = nil;
        state.pending_maneuver = nil;
        state.overload_skip = nil;
        petstatus.clear();
        state.systems_pet_initialized = false;
        state.systems_pet_server_id = 0;
        state.first_draw = true;
        message('Settings and tracked timers reset.');
    elseif (command == 'help') then
        print_help();
    else
        print_help();
    end
    settings.save();
end);

local function render_plan()
    imgui.TextDisabled('PLAN');
    imgui.SameLine();
    for index, name in ipairs(state.settings.plan) do
        local element = by_name[string.lower(name)];
        imgui.PushStyleColor(ImGuiCol_Text, element_display_color(element));
        imgui.Text(name);
        imgui.PopStyleColor();
        if (index < #state.settings.plan) then
            imgui.SameLine();
            imgui.TextDisabled('>');
            imgui.SameLine();
        end
    end
end

local function render_section_header(label)
    imgui.Separator();
    imgui.PushStyleColor(ImGuiCol_Text, toau_theme.brass_dim);
    imgui.Text('// ' .. label);
    imgui.PopStyleColor();
end

local function render_compact_header()
    local pet = get_pet();
    local pet_name = pet ~= nil and (pet.Name or 'Active') or 'Inactive';

    if (imgui.BeginTable('##pupman_compact_header', 2, ImGuiTableFlags_SizingStretchSame)) then
        imgui.TableSetupColumn('##status_left', ImGuiTableColumnFlags_WidthStretch, 0, 0);
        imgui.TableSetupColumn('##status_right', ImGuiTableColumnFlags_WidthStretch, 0, 1);

        imgui.TableNextColumn();
        imgui.PushStyleColor(ImGuiCol_Text, toau_theme.brass);
        imgui.Text('PUP //');
        imgui.PopStyleColor();
        imgui.SameLine();
        imgui.PushStyleColor(ImGuiCol_Text, pet ~= nil
            and { 0.40, 0.90, 0.52, 1.00 } or { 0.95, 0.35, 0.30, 1.00 });
        imgui.Text(pet_name);
        imgui.PopStyleColor();

        imgui.TableNextColumn();
        imgui.TextDisabled('MODE  ' .. string.upper(state.active_mode or '---'));

        imgui.TableNextColumn();
        imgui.TextDisabled('HEAD  ' .. (automaton_heads[state.automaton_head] or '--'));
        imgui.TableNextColumn();
        imgui.TextDisabled('FRAME  ' .. (automaton_frames[state.automaton_frame] or '--'));
        imgui.EndTable();
    end
end

local function hp_vitals_color(hpp)
    if hpp <= 25 then
        return { 0.86, 0.12, 0.08, 1.00 };
    elseif hpp <= 50 then
        return { 0.74, 0.18, 0.11, 1.00 };
    end
    return { 0.58, 0.20, 0.18, 1.00 };
end

local function mp_vitals_color(mpp)
    if mpp < MP_CRITICAL_THRESHOLD then
        return { 1.00, 0.08, 0.04, 1.00 };
    elseif mpp < MP_DANGER_THRESHOLD then
        return { 1.00, 0.30, 0.06, 1.00 };
    elseif mpp < MP_WARNING_THRESHOLD then
        return { 0.96, 0.66, 0.08, 1.00 };
    elseif mpp <= 50 then
        return { 0.66, 0.49, 0.08, 1.00 };
    end
    return { 0.45, 0.60, 0.10, 1.00 };
end

local function mp_warning(mpp)
    if mpp == nil then return nil; end
    if (mpp < MP_CRITICAL_THRESHOLD) then
        return {
            level = 3,
            color = { 1.00, 0.08, 0.04, 1.00 },
        };
    elseif (mpp < MP_DANGER_THRESHOLD) then
        return {
            level = 2,
            color = { 1.00, 0.30, 0.06, 1.00 },
        };
    elseif (mpp < MP_WARNING_THRESHOLD) then
        return {
            level = 1,
            color = { 1.00, 0.72, 0.10, 1.00 },
        };
    end
    return nil;
end

local function tp_vitals_color(tp)
    if tp >= 2000 then
        return { 0.34, 0.94, 1.00, 1.00 };
    elseif tp >= 1000 then
        return { 0.14, 0.84, 1.00, 1.00 };
    elseif tp >= 800 then
        return { 0.12, 0.54, 0.70, 1.00 };
    end
    return { 0.18, 0.25, 0.25, 1.00 };
end

local function render_vital_card(
    label, fraction, fill_color, label_color, accent_color, alert_level)
    local fraction_clamped = math.clamp(fraction, 0, 1);
    local card_x, card_y = imgui.GetCursorScreenPos();
    local card_width = imgui.GetContentRegionAvail();
    local cursor_x = imgui.GetCursorPosX();
    local text_width = imgui.CalcTextSize(label);
    local draw = imgui.GetWindowDrawList();
    local card_background = toau_theme.bg_medium;
    if (accent_color ~= nil) then
        card_background = { 0.035, 0.155, 0.180, 1.00 };
    end
    local alert_pulse = 0;
    if (alert_level ~= nil and accent_color ~= nil) then
        local speed = alert_level == 3 and 8.0
            or alert_level == 2 and 6.0 or 4.2;
        alert_pulse = 0.5 + 0.5 * math.sin(os.clock() * speed);
        local tint = 0.10 + alert_level * 0.035 + alert_pulse * 0.045;
        card_background = {
            accent_color[1] * tint,
            accent_color[2] * tint,
            accent_color[3] * tint,
            1.00,
        };
        draw:AddRectFilled(
            { card_x - 6, card_y - 5 },
            { card_x + card_width + 6, card_y + 33 },
            imgui.GetColorU32({
                accent_color[1], accent_color[2], accent_color[3],
                0.08 + alert_pulse * (0.07 + alert_level * 0.025),
            }), 5.0);
    end

    draw:AddRectFilled(
        { card_x - 3, card_y - 2 }, { card_x + card_width + 3, card_y + 29 },
        imgui.GetColorU32(card_background), 3.0);
    imgui.SetCursorPosX(cursor_x + math.max(0, (card_width - text_width) / 2));
    imgui.PushStyleColor(ImGuiCol_Text, label_color or toau_theme.text);
    imgui.Text(label);
    imgui.PopStyleColor();
    imgui.SetCursorPosX(cursor_x);

    -- Size the meter explicitly and retain those exact screen-space bounds.
    -- The endpoint marker must use the ProgressBar rectangle, not the wider
    -- card rectangle or a hard-coded vertical offset.
    local meter_x, meter_y = imgui.GetCursorScreenPos();
    local meter_width = math.max(1, imgui.GetContentRegionAvail() - 1);
    local meter_height = 6;
    imgui.PushStyleColor(ImGuiCol_PlotHistogram, fill_color);
    imgui.PushStyleColor(ImGuiCol_FrameBg, toau_theme.bg_dark);
    imgui.ProgressBar(fraction_clamped, { meter_width, meter_height }, '');
    imgui.PopStyleColor(2);

    local border_color = {
        toau_theme.brass_dim[1], toau_theme.brass_dim[2], toau_theme.brass_dim[3], 0.72 };
    local border_thickness = 1.0;
    if (accent_color ~= nil) then
        local pulse = alert_level ~= nil
            and (0.62 + alert_pulse * 0.34)
            or (0.62 + ((math.sin(os.clock() * 3.5) + 1) * 0.12));
        border_color = { accent_color[1], accent_color[2], accent_color[3], pulse };
        border_thickness = alert_level ~= nil
            and (1.7 + alert_level * 0.35) or 1.6;
        draw:AddRect(
            { card_x - 4, card_y - 3 }, { card_x + card_width + 4, card_y + 30 },
            imgui.GetColorU32({ accent_color[1], accent_color[2], accent_color[3],
                pulse * (alert_level ~= nil and 0.42 or 0.24) }),
            4.0, ImDrawCornerFlags_All,
            alert_level ~= nil and (1.2 + alert_level * 0.25) or 1.0);
    end
    draw:AddRect(
        { card_x - 3, card_y - 2 }, { card_x + card_width + 3, card_y + 29 },
        imgui.GetColorU32(border_color), 3.0, ImDrawCornerFlags_All, border_thickness);
    if (fraction_clamped > 0.01 and fraction_clamped < 0.995) then
        local edge_x = meter_x
            + math.floor(meter_width * fraction_clamped + 0.5);
        draw:AddRectFilled(
            { edge_x - 1, meter_y },
            { edge_x + 1, meter_y + meter_height },
            imgui.GetColorU32({ 0.96, 0.91, 0.74, 0.72 }), 1.0);
    end
end

local function render_vital_bars(vitals, table_id)
    local font_pushed = push_vitals_font();
    imgui.PushStyleVar(ImGuiStyleVar_CellPadding, { 7, 3 });
    if (imgui.BeginTable(table_id, 3, ImGuiTableFlags_SizingStretchSame)) then
        imgui.TableNextColumn();
        if (vitals == nil) then
            render_vital_card('HP  --', 0, toau_theme.bg_lighter, toau_theme.brass_dim);
        else
            local hp_label = nil;
            if (vitals.hp_exact) then
                hp_label = ('HP  %d/%d'):fmt(vitals.hp, vitals.max_hp);
            elseif (state.pet_hp_current ~= nil and state.pet_hp_max ~= nil) then
                hp_label = ('HP  ~%d/%d'):fmt(state.pet_hp_current, state.pet_hp_max);
            else
                hp_label = ('HP  ~%d%%'):fmt(vitals.hpp);
            end
            render_vital_card(hp_label, vitals.hpp / 100, hp_vitals_color(vitals.hpp));
        end

        imgui.TableNextColumn();
        if (vitals == nil or not vitals.has_mp) then
            render_vital_card('MP  --', 0, toau_theme.bg_lighter, toau_theme.brass_dim);
        else
            local warning = mp_warning(vitals.mpp);
            local mp_prefix = warning ~= nil
                and ('MP' .. string.rep('!', warning.level)) or 'MP';
            local mp_label = nil;
            if (vitals.mp_exact) then
                mp_label = ('%s  %d/%d'):fmt(
                    mp_prefix, vitals.mp, vitals.max_mp);
            else
                mp_label = ('%s  %d%%'):fmt(mp_prefix, vitals.mpp);
            end
            render_vital_card(
                mp_label, vitals.mpp / 100, mp_vitals_color(vitals.mpp),
                warning ~= nil and { 1.00, 0.96, 0.82, 1.00 } or nil,
                warning ~= nil and warning.color or nil,
                warning ~= nil and warning.level or nil);
        end

        imgui.TableNextColumn();
        if (vitals == nil) then
            render_vital_card('TP  --', 0, toau_theme.bg_lighter, toau_theme.brass_dim);
        elseif (vitals.tp >= 1000) then
            local tp_color = tp_vitals_color(vitals.tp);
            render_vital_card(('TP  %d'):fmt(vitals.tp), vitals.tp / 3000,
                tp_color, { 0.92, 0.99, 1.00, 1.00 }, tp_color);
        elseif (vitals.tp >= 800) then
            render_vital_card(('TP  %d'):fmt(vitals.tp), vitals.tp / 3000,
                tp_vitals_color(vitals.tp), { 0.70, 0.90, 0.94, 1.00 });
        else
            render_vital_card(('TP  %d'):fmt(vitals.tp), vitals.tp / 3000,
                tp_vitals_color(vitals.tp), toau_theme.brass_dim);
        end
        imgui.EndTable();
    end
    imgui.PopStyleVar();
    if (font_pushed) then
        imgui.PopFont();
    end
end

local function render_pet_vitals(vitals)
    render_vital_bars(vitals or pet_vitals(), '##pupman_pet_vitals');
end

local function render_pet_effects(micro)
    local pet = get_pet();
    local effects = petstatus.get_effects(pet ~= nil and pet.ServerId or 0);
    if (#effects == 0) then
        return;
    end

    local shown = math.min(#effects, micro and 3 or 4);
    imgui.TextDisabled('PET FX');
    for index = 1, shown do
        local effect = effects[index];
        imgui.SameLine();
        imgui.PushStyleColor(ImGuiCol_Text, effect.is_buff
            and { 0.35, 0.82, 0.72, 1.00 }
            or { 1.00, 0.39, 0.23, 1.00 });
        imgui.Text((effect.is_buff and '+' or '-') .. effect.name);
        imgui.PopStyleColor();
    end
    if (#effects > shown) then
        imgui.SameLine();
        imgui.TextDisabled((' +%d'):fmt(#effects - shown));
    end
end

local function render_ability_recast_entry(ability)
    local recast = ability_recast(ability.id);
    local value = recast <= 0.1 and 'READY' or format_recast(recast);
    local dot_color = recast <= 0.1 and { 0.35, 0.90, 0.45, 1.00 }
        or { 0.95, 0.63, 0.20, 1.00 };
    local text_x, text_y = imgui.GetCursorScreenPos();
    if (recast <= 0.1) then
        imgui.PushStyleColor(ImGuiCol_Text, toau_theme.text);
    else
        imgui.PushStyleColor(ImGuiCol_Text, toau_theme.brass_dim);
    end
    imgui.Text(('   %s: %s'):fmt(string.upper(ability.name), value));
    imgui.PopStyleColor();
    imgui.GetWindowDrawList():AddCircleFilled(
        { text_x + 5, text_y + 7 }, 2.7, imgui.GetColorU32(dot_color), 10);
end

local function render_ability_recasts()
    imgui.TextDisabled('ABILITY RECASTS');
    if (imgui.BeginTable('##pupman_ability_recasts', 2, ImGuiTableFlags_SizingStretchSame)) then
        imgui.TableSetupColumn('##ability_left', ImGuiTableColumnFlags_WidthStretch, 0, 0);
        imgui.TableSetupColumn('##ability_right', ImGuiTableColumnFlags_WidthStretch, 0, 1);
        for _, ability in ipairs(pup_recasts) do
            -- The protected Deactivate row already provides its actionable
            -- status, so repeating it here adds noise to the compact layout.
            if (ability.key ~= 'deactivate') then
                imgui.TableNextColumn();
                render_ability_recast_entry(ability);
            end
        end
        imgui.EndTable();
    end
end

local function render_deactivate_and_repair()
    local status_text, status_color = deactivate_readiness();
    local status_label = status_text:gsub('^DA:%s*', ''):gsub('^DA%s+', '');
    imgui.TextDisabled('DEACTIVATE');
    imgui.SameLine();
    imgui.PushStyleColor(ImGuiCol_Text, status_color);
    imgui.Text(status_label);
    imgui.PopStyleColor();
    imgui.SameLine();

    local oils = count_automaton_oil();
    imgui.TextDisabled(('|  OIL %d'):fmt(oils));
end

local function render_overload_risk(decision)
    local risk = decision.risk;
    imgui.TextDisabled('NEXT RISK');
    imgui.SameLine();
    imgui.PushStyleColor(ImGuiCol_Text, risk.color);
    imgui.Text(risk.score ~= nil
        and ('%s %d%%'):fmt(risk.label, risk.score) or risk.label);
    imgui.PopStyleColor();
    if (risk.name ~= nil) then
        imgui.SameLine();
        imgui.TextDisabled('| ' .. risk.name);
    end
    if (risk.score ~= nil and risk.safe_seconds ~= nil
        and risk.safe_seconds > 0) then
        imgui.SameLine();
        imgui.TextDisabled(('| safe ~%.0fs'):fmt(risk.safe_seconds));
    end
    if (risk.label ~= 'UNKNOWN' and risk.quality ~= nil) then
        imgui.SameLine();
        imgui.TextDisabled('| ' .. risk.quality);
    end
end

local function render_next_card(decision)
    local name = decision.planned_name;
    local status = decision.status;
    local label = 'NEXT  HOLD';
    local background = toau_theme.bg_light;
    if (decision.action_name ~= nil) then
        local element = by_name[string.lower(name)];
        local element_color = element_display_color(element);
        label = ('NEXT  %s  |  %s'):fmt(string.upper(name), status);
        background = {
            element_color[1] * 0.28,
            element_color[2] * 0.28,
            element_color[3] * 0.28,
            1.00,
        };
    elseif (status == 'NO PET' or status == 'NO ANIMATOR'
        or status == 'OVERLOAD') then
        label = 'NEXT  HOLD  |  ' .. status;
    elseif (status == 'RECAST') then
        label = name ~= nil
            and ('NEXT  %s  |  WAIT %.1fs'):fmt(
                string.upper(name), decision.recast)
            or ('NEXT  WAIT  |  %.1fs'):fmt(decision.recast);
    elseif (status:find('STABLE', 1, true) == 1) then
        label = name ~= nil
            and ('NEXT  %s  |  %s'):fmt(string.upper(name), status)
            or ('PLAN  ' .. status);
    elseif (name ~= nil) then
        label = ('NEXT  %s  |  %s'):fmt(string.upper(name), status);
    else
        label = 'NEXT  HOLD  |  ' .. status;
    end

    if (name ~= nil and decision.action_name == nil) then
        local element = by_name[string.lower(name)];
        local element_color = element_display_color(element);
        background = {
            element_color[1] * 0.18,
            element_color[2] * 0.18,
            element_color[3] * 0.18,
            1.00,
        };
    end

    imgui.PushStyleColor(ImGuiCol_PlotHistogram, background);
    imgui.PushStyleColor(ImGuiCol_FrameBg, background);
    imgui.PushStyleColor(ImGuiCol_Text, toau_theme.text);
    local card_x, card_y = imgui.GetCursorScreenPos();
    imgui.ProgressBar(1, { -1, 20 }, label);
    imgui.PopStyleColor(3);
    if (name ~= nil) then
        local element = by_name[string.lower(name)];
        draw_element_icon(imgui.GetWindowDrawList(), element.name,
            card_x + 13, card_y + 10, 8, element_display_color(element));
    end
end

-- A compact three-node circuit for micro mode. The rail preserves plan order,
-- filled nodes show currently active maneuver copies, and the pulsing outer
-- ring marks the element PupMan would recommend next.
local function render_micro_plan(next_name, active_counts)
    imgui.TextDisabled('PLAN');
    imgui.SameLine();

    local x, y = imgui.GetCursorScreenPos();
    local width = imgui.GetContentRegionAvail();
    local height = 36;
    imgui.Dummy({ width, height });
    if (width < 90) then
        return;
    end

    local draw = imgui.GetWindowDrawList();
    local rail_y = y + 11;
    local rail_start = x + 18;
    local rail_end = x + width - 18;
    local rail_span = rail_end - rail_start;
    local panel = imgui.GetColorU32({
        toau_theme.bg_medium[1], toau_theme.bg_medium[2],
        toau_theme.bg_medium[3], 0.58 });
    local border = imgui.GetColorU32({
        toau_theme.brass_dim[1], toau_theme.brass_dim[2],
        toau_theme.brass_dim[3], 0.34 });
    local trace_dark = imgui.GetColorU32({ 0.02, 0.08, 0.09, 0.92 });
    local trace_lit = imgui.GetColorU32({
        toau_theme.teal[1], toau_theme.teal[2], toau_theme.teal[3], 0.42 });

    draw:AddRectFilled({ x, y }, { x + width, y + height - 1 }, panel, 4.0);
    draw:AddRect({ x, y }, { x + width, y + height - 1 }, border,
        4.0, ImDrawCornerFlags_All, 1.0);
    draw:AddLine({ rail_start, rail_y }, { rail_end, rail_y }, trace_dark, 3.0);
    draw:AddLine({ rail_start, rail_y }, { rail_end, rail_y }, trace_lit, 1.0);

    local node_x = {};
    for index = 1, 3 do
        node_x[index] = rail_start + rail_span * ((index - 1) / 2);
    end
    for index = 1, 2 do
        local arrow_x = (node_x[index] + node_x[index + 1]) / 2;
        draw:AddTriangleFilled(
            { arrow_x + 3, rail_y },
            { arrow_x - 2, rail_y - 3 },
            { arrow_x - 2, rail_y + 3 }, trace_lit);
    end

    local active = {};
    for name, count in pairs(active_counts or {}) do
        active[name] = count;
    end
    local slot_active = {};
    for index = 1, 3 do
        local name = state.settings.plan[index];
        local active_count = active[name] or 0;
        slot_active[index] = active_count > 0;
        if (slot_active[index]) then
            active[name] = active_count - 1;
        end
    end
    local next_index = nil;
    for index = 1, 3 do
        if (state.settings.plan[index] == next_name and not slot_active[index]) then
            next_index = index;
            break;
        end
    end
    if (next_index == nil) then
        for index = 1, 3 do
            if (state.settings.plan[index] == next_name) then
                next_index = index;
                break;
            end
        end
    end

    for index = 1, 3 do
        local name = state.settings.plan[index];
        local element = by_name[string.lower(name or '')];
        if (element ~= nil) then
            local color = element_display_color(element);
            local is_active = slot_active[index];
            local is_next = index == next_index;

            if (is_active) then
                draw:AddCircleFilled({ node_x[index], rail_y }, 9.0,
                    imgui.GetColorU32({ color[1], color[2], color[3], 0.20 }), 18);
                draw:AddCircle({ node_x[index], rail_y }, 9.0,
                    imgui.GetColorU32({ color[1], color[2], color[3], 0.88 }),
                    18, 1.4);
            else
                draw:AddCircle({ node_x[index], rail_y }, 9.0, border, 18, 1.0);
            end
            if (is_next) then
                local pulse = 0.64 + 0.24 * (0.5 + 0.5 * math.sin(os.clock() * 4.2));
                draw:AddCircle({ node_x[index], rail_y }, 11.5,
                    imgui.GetColorU32({ color[1], color[2], color[3], pulse }),
                    20, 1.6);
            end

            draw_element_icon(draw, element.name,
                node_x[index], rail_y, 8, color);
            local abbreviation = string.upper(string.sub(element.name, 1, 3));
            local text_width = imgui.CalcTextSize(abbreviation);
            draw:AddText(
                { node_x[index] - text_width / 2, y + 21 },
                imgui.GetColorU32({ color[1], color[2], color[3],
                    is_active and 0.96 or 0.62 }), abbreviation);
        end
    end
end

local function render_micro(decision)
    local vitals = decision.vitals;
    local deactivate_text, deactivate_color = deactivate_readiness();
    local deactivate_label = deactivate_text:gsub('^DA:%s*', ''):gsub('^DA%s+', '');
    local risk = decision.risk;

    if (imgui.BeginTable('##pupman_micro_status', 2, ImGuiTableFlags_SizingStretchSame)) then
        imgui.TableNextColumn();
        imgui.PushStyleColor(ImGuiCol_Text, toau_theme.brass);
        imgui.Text(('PUP  %s'):fmt(string.upper(state.active_mode or '---')));
        imgui.PopStyleColor();

        imgui.TableNextColumn();
        imgui.TextDisabled(is_engaged() and 'COMBAT  ENGAGED' or 'COMBAT  IDLE');

        imgui.TableNextColumn();
        imgui.PushStyleColor(ImGuiCol_Text, deactivate_color);
        imgui.Text('DEACT  ' .. deactivate_label);
        imgui.PopStyleColor();

        imgui.TableNextColumn();
        imgui.PushStyleColor(ImGuiCol_Text, risk.color);
        local safe = risk.safe_seconds ~= nil and risk.safe_seconds > 0
            and ('  S~%.0fs'):fmt(risk.safe_seconds) or '';
        imgui.Text(risk.score ~= nil
            and ('RISK  %s %d%%%s'):fmt(risk.label, risk.score, safe)
            or ('RISK  %s'):fmt(risk.label));
        imgui.PopStyleColor();
        imgui.EndTable();
    end

    render_vital_bars(vitals, '##pupman_micro_vitals');
    render_micro_plan(decision.planned_name, decision.active_counts);
    render_pet_effects(true);

    if (imgui.BeginTable('##pupman_micro_decision', 2, ImGuiTableFlags_SizingStretchSame)) then
        imgui.TableNextColumn();
        if (decision.action_name ~= nil) then
            local element = by_name[string.lower(decision.action_name)];
            imgui.PushStyleColor(ImGuiCol_Text, element_display_color(element));
            imgui.Text(('NEXT  %s  READY'):fmt(
                string.upper(decision.action_name)));
            imgui.PopStyleColor();
        elseif (decision.planned_name ~= nil) then
            imgui.TextDisabled(('NEXT  %s'):fmt(
                string.upper(decision.planned_name)));
        else
            imgui.TextDisabled('NEXT  HOLD');
        end

        imgui.TableNextColumn();
        imgui.TextDisabled(decision.status);
        imgui.EndTable();
    end
end

local function push_toau_theme()
    imgui.PushStyleColor(ImGuiCol_WindowBg, toau_theme.bg_dark);
    imgui.PushStyleColor(ImGuiCol_TitleBg, toau_theme.bg_medium);
    imgui.PushStyleColor(ImGuiCol_TitleBgActive, toau_theme.bg_light);
    imgui.PushStyleColor(ImGuiCol_TitleBgCollapsed, toau_theme.bg_dark);
    imgui.PushStyleColor(ImGuiCol_FrameBg, toau_theme.bg_medium);
    imgui.PushStyleColor(ImGuiCol_FrameBgHovered, toau_theme.bg_light);
    imgui.PushStyleColor(ImGuiCol_FrameBgActive, toau_theme.bg_lighter);
    imgui.PushStyleColor(ImGuiCol_Header, toau_theme.bg_light);
    imgui.PushStyleColor(ImGuiCol_HeaderHovered, toau_theme.bg_lighter);
    imgui.PushStyleColor(ImGuiCol_HeaderActive, toau_theme.teal);
    imgui.PushStyleColor(ImGuiCol_Border, toau_theme.border);
    imgui.PushStyleColor(ImGuiCol_Text, toau_theme.text);
    imgui.PushStyleColor(ImGuiCol_TextDisabled, toau_theme.brass_dim);
    imgui.PushStyleColor(ImGuiCol_Button, toau_theme.bg_medium);
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, toau_theme.bg_light);
    imgui.PushStyleColor(ImGuiCol_ButtonActive, toau_theme.bg_lighter);
    imgui.PushStyleColor(ImGuiCol_Separator, toau_theme.border);
end

local function render_toau_motif(decision)
    local x, y = imgui.GetWindowPos();
    local width, height = imgui.GetWindowSize();
    local draw = imgui.GetWindowDrawList();
    local brass = imgui.GetColorU32({ toau_theme.brass[1], toau_theme.brass[2], toau_theme.brass[3], 0.68 });
    local teal = imgui.GetColorU32({ toau_theme.teal[1], toau_theme.teal[2], toau_theme.teal[3], 0.65 });
    local trace = imgui.GetColorU32({ toau_theme.teal[1], toau_theme.teal[2], toau_theme.teal[3], 0.13 });
    local watermark = imgui.GetColorU32({ toau_theme.teal[1], toau_theme.teal[2], toau_theme.teal[3], 0.075 });

    local rail_color = toau_theme.brass;
    local vitals = decision ~= nil and decision.vitals or pet_vitals();
    local mp_alert = vitals ~= nil and vitals.has_mp
        and mp_warning(vitals.mpp) or nil;
    if (decision ~= nil and decision.overloaded) then
        rail_color = { 1.00, 0.20, 0.15, 1.00 };
    elseif (vitals ~= nil and state.settings.repair_warn_at > 0
        and vitals.hpp <= state.settings.repair_warn_at) then
        rail_color = { 1.00, 0.48, 0.16, 1.00 };
    elseif (mp_alert ~= nil) then
        rail_color = mp_alert.color;
    end

    draw:AddRectFilled({ x + 1, y + 1 }, { x + width - 1, y + 3 }, teal, 3.0);
    draw:AddRectFilled({ x + 1, y + 4 }, { x + 4, y + height - 4 },
        imgui.GetColorU32(rail_color), 2.0);
    draw:AddCircleFilled({ x + 8, y + 9 }, 1.8, brass, 8);
    draw:AddCircleFilled({ x + width - 8, y + 9 }, 1.8, brass, 8);
    draw:AddLine({ x + width - 48, y + 12 }, { x + width - 18, y + 12 }, trace, 1.0);
    draw:AddLine({ x + width - 30, y + 12 }, { x + width - 30, y + 29 }, trace, 1.0);
    draw:AddCircleFilled({ x + width - 30, y + 29 }, 2.0, trace, 8);

    -- Low-opacity gear and circuit watermark; drawn before content so text and
    -- bars remain the strongest visual layer.
    local gear_x = x + width - 42;
    local gear_y = y + height - 34;
    draw:AddCircle({ gear_x, gear_y }, 18, watermark, 24, 1.5);
    draw:AddCircle({ gear_x, gear_y }, 7, watermark, 16, 1.5);
    for tooth = 0, 7 do
        local angle = tooth * math.pi / 4;
        draw:AddLine(
            { gear_x + math.cos(angle) * 18, gear_y + math.sin(angle) * 18 },
            { gear_x + math.cos(angle) * 23, gear_y + math.sin(angle) * 23 },
            watermark, 2.0);
    end
    draw:AddLine({ gear_x - 30, gear_y }, { gear_x - 18, gear_y }, watermark, 1.5);
    draw:AddCircleFilled({ gear_x - 32, gear_y }, 2.0, watermark, 8);
end

local function format_system_cooldown(seconds)
    local total = math.max(0, math.ceil(seconds or 0));
    if (total >= 60) then
        return ('~%d:%02d'):fmt(math.floor(total / 60), total % 60);
    end
    return ('~%ds'):fmt(total);
end

local function system_row_status(row)
    if (not row.known) then
        return row.status, { 0.58, 0.56, 0.49, 1.00 };
    elseif (row.remaining > 0) then
        return format_system_cooldown(row.remaining),
            { 0.94, 0.64, 0.22, 1.00 };
    elseif (row.eligible) then
        return 'READY', { 0.35, 0.90, 0.55, 1.00 };
    end
    return row.status, { 0.82, 0.68, 0.38, 1.00 };
end

local function render_systems_panel(flags)
    local side = state.settings.systems_side;
    local panel_x = side == 'left'
        and (state.settings.position_x - SYSTEMS_WIDTH - SYSTEMS_GAP)
        or (state.settings.position_x + HUD_WIDTH + SYSTEMS_GAP);
    imgui.SetNextWindowPos(
        { panel_x, state.settings.position_y }, ImGuiCond_Always);
    imgui.SetNextWindowSizeConstraints(
        { SYSTEMS_WIDTH, -1 }, { SYSTEMS_WIDTH, FLT_MAX });
    imgui.SetNextWindowBgAlpha(0.96);
    state.systems_open[1] = true;
    if (imgui.Begin('Puppet Systems##pupman_systems',
        state.systems_open, flags)) then
        local panel_x_screen, panel_y_screen = imgui.GetWindowPos();
        local panel_width, panel_height = imgui.GetWindowSize();
        local draw = imgui.GetWindowDrawList();
        draw:AddRectFilled(
            { panel_x_screen + 1, panel_y_screen + 1 },
            { panel_x_screen + panel_width - 1, panel_y_screen + 3 },
            imgui.GetColorU32({
                toau_theme.teal[1], toau_theme.teal[2],
                toau_theme.teal[3], 0.70 }), 3.0);
        draw:AddRectFilled(
            { panel_x_screen + 1, panel_y_screen + 4 },
            { panel_x_screen + 4, panel_y_screen + panel_height - 4 },
            imgui.GetColorU32({
                toau_theme.brass[1], toau_theme.brass[2],
                toau_theme.brass[3], 0.74 }), 2.0);

        imgui.PushStyleColor(ImGuiCol_Text, toau_theme.brass);
        imgui.Text('PUPPET SYSTEMS');
        imgui.PopStyleColor();
        imgui.SameLine();
        imgui.TextDisabled('LSB PRIOR');
        imgui.Separator();

        local pet = get_pet();
        if (pet == nil) then
            imgui.TextDisabled('NO PET');
        else
            local counts = current_buff_counts();
            local vitals = pet_vitals();
            local rows = systems_tracker:rows({
                maneuvers = counts,
                hpp = vitals ~= nil and vitals.hpp or nil,
                mpp = vitals ~= nil and vitals.mpp or nil,
            });
            if (#rows == 0) then
                imgui.TextDisabled(state.automaton_frame == 0
                    and 'WAITING FOR PUP DATA' or 'NO TIMED SYSTEMS');
            elseif (imgui.BeginTable('##pupman_system_rows', 2,
                ImGuiTableFlags_SizingStretchProp)) then
                imgui.TableSetupColumn('##system_name',
                    ImGuiTableColumnFlags_WidthStretch, 0, 0);
                imgui.TableSetupColumn('##system_state',
                    ImGuiTableColumnFlags_WidthFixed, 72, 1);
                for _, row in ipairs(rows) do
                    local status, status_color = system_row_status(row);
                    imgui.TableNextColumn();
                    local dot_x, dot_y = imgui.GetCursorScreenPos();
                    local name = row.name;
                    if (row.element ~= nil) then
                        name = name .. '  ' .. string.upper(
                            string.sub(row.element, 1, 1));
                    end
                    imgui.Text('   ' .. name);
                    draw:AddCircleFilled(
                        { dot_x + 5, dot_y + 7 }, 2.7,
                        imgui.GetColorU32(status_color), 10);

                    imgui.TableNextColumn();
                    imgui.PushStyleColor(ImGuiCol_Text, status_color);
                    imgui.Text(status);
                    imgui.PopStyleColor();
                end
                imgui.EndTable();
            end
        end
        imgui.Separator();
        imgui.TextDisabled('~ modeled  //  packet anchored');
    end
    imgui.End();
end

ashita.events.register('d3d_present', 'present_cb', function()
    local pup_active = is_pup();
    if (pup_active) then
        synchronize_systems_pet();
        reconcile_slots();
    end
    if (not state.settings.visible or not pup_active or should_auto_hide_hud()) then
        return;
    end
    state.open[1] = true;
    if (state.first_draw) then
        imgui.SetNextWindowPos({ state.settings.position_x, state.settings.position_y }, ImGuiCond_Always);
        state.first_draw = false;
    end

    local flags = bit.bor(
        ImGuiWindowFlags_AlwaysAutoResize,
        ImGuiWindowFlags_NoDecoration,
        ImGuiWindowFlags_NoInputs,
        ImGuiWindowFlags_NoMove,
        ImGuiWindowFlags_NoSavedSettings,
        ImGuiWindowFlags_NoFocusOnAppearing
    );

    local font_pushed = false;
    if (state.hud_font ~= nil) then
        font_pushed = pcall(imgui.PushFont, state.hud_font);
    end
    push_toau_theme();
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 5.0);
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 3.0);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 11, 8 });
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { 4, 2 });
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 4, 2 });
    imgui.SetNextWindowBgAlpha(0.96);
    local micro = state.settings.layout == 'micro';
    -- Keep both layouts the same width so switching modes does not shift the
    -- right edge or reflow labels differently.
    imgui.SetNextWindowSizeConstraints({ HUD_WIDTH, -1 }, { HUD_WIDTH, FLT_MAX });
    if (imgui.Begin('PUPMan##pupman', state.open, flags)) then
        local decision = decision_snapshot();
        render_toau_motif(decision);

        if (micro) then
            render_micro(decision);
        else

            render_compact_header();
            render_pet_vitals(decision.vitals);
            render_pet_effects(false);
            render_section_header('MANEUVER CONTROL');
            render_plan();

            render_next_card(decision);
            render_overload_risk(decision);

            render_section_header('AUTOMATON');
            render_deactivate_and_repair();
            render_ability_recasts();

        end
    end
    imgui.End();
    if (state.settings.systems_visible) then
        render_systems_panel(flags);
    end
    imgui.PopStyleVar(5);
    imgui.PopStyleColor(17);
    if (font_pushed) then
        imgui.PopFont();
    end
end);
