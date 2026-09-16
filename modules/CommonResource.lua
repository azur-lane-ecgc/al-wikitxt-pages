-- CommonResource: renders the Common Resource guide tables on the wiki from
-- Module:CommonResourceData (generated from the ecgc-dev guide).
-- Usage on a wiki page:
--   {{#invoke:CommonResource|renewable}}
--   {{#invoke:CommonResource|finite}}
-- Mark legend (mirrors the ecgc-dev glossary):
--   green check  = guaranteed drop, green star = optimal farming location,
--   sand check   = source spawning / item dropping is random,
--   sand cross   = one-time drop only,
--   red check    = not recommended, red cross = cannot drop from this source.
-- Server-load notes: mw.loadData shares one immutable copy of the data per
-- page parse (canonical loader for pure-data Scribunto modules); rendering
-- is single-pass over the data; every repeated string is built once.

local p = {}

local data = mw.loadData('Module:CommonResourceData')

-- Upvalues: these library functions run hundreds of times per render.
local concat = table.concat
local insert = table.insert
local format = string.format
local floor = math.floor

-- Section headings and See-also links per category, in display order.
local CATEGORY_HEADINGS = {
    Currency = 'Currency',
    Consumable = 'Consumables',
    ['Cognitive Awakening'] = 'Cognitive Awakening',
    Bulin = 'Bulins',
    ['Gear Enhance'] = 'Gear Upgrade Parts',
    Augmentation = 'Augmentation Materials',
    Retrofit = 'Retrofit Blueprints',
    ['Skill Book'] = 'Skill Books',
}

local CATEGORY_SEE_ALSO = {
    ['Cognitive Awakening'] = "{{See also|[[Dockyard#Cognitive_Awakening|Cognitive Awakening]]}}",
    Bulin = "{{See also|[[Dockyard#Limit_Break|Limit Break]]}}",
    ['Gear Enhance'] = "{{See also|[[Equipment#Upgrade_(Enhance)|Equipment Upgrade (Enhance)]]}}",
    Augmentation = '{{See also|[[Augmentation]]}}',
    ['Skill Book'] = "{{See also|[[Living_Area#Tactical_Class|Tactical Class]]}}",
    Retrofit = '{{See also|[[Retrofit]]}}',
}

-- Labels for the source groups defined in the guide Terminology section.
local GROUP_LABELS = {
    academy = 'Academy',
    missions = 'Missions',
    dailyRaid = 'Daily Raid',
    cruisePass = 'Cruise Pass',
    campaignDrop = 'Campaign',
    hardModeDrop = 'Hard Mode',
    eventDrop = 'Event',
    opsi = 'OPSI',
    generalShop = 'General Shop',
    coreDataShop = 'Core Data Shop',
    guildShop = 'Guild Shop',
    meritShop = 'Merit Shop',
    medalShop = 'Medal Shop',
    prototypeShop = 'Prototype Shop',
    eventShop = 'Event Shop',
    metaShop = 'META Shop',
}

local TIMEFRAME_LABELS = {
    daily = '/Day',
    weekly = '/Week',
    monthly = '/Month',
    bimonthly = '/2 Months',
    ['one-time'] = '',
    chapter = '/Chapter',
    cycle = '/Event Cycle',
}

local MARK_COLORS = {
    green = '#2e8b57',
    sand = '#b8860b',
    red = '#cd5c5c',
}

-- Fixed table skeleton; only caption, total header, and rows vary.
local TABLE_OPEN = '{|class="azltable mw-collapsible" style="width:100%; text-align:center"'
local TABLE_HEADERS = concat({
    "! style='width:175px' | Item",
    "! style='width:400px' | Location",
    '! Guaranteed quantities (if applicable)',
}, '\n')

-- Formats 1234567 -> "1,234,567"; keeps up to 2 decimals, trailing zeros trimmed.
local function formatNumber(value)
    if type(value) == 'string' then
        return value
    end
    local body
    if floor(value) == value then
        body = format('%d', value)
    else
        body = format('%.2f', value):gsub('0+$', ''):gsub('%.$', '')
    end
    local withCommas = body:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    return (withCommas:gsub('^,', ''))
end

-- Mark spans: at most 12 distinct (color, mark, optimal) combos exist in the
-- data, so build each once and reuse across all ~120 groups per render.
local markCache = {}
local function markWikitext(group)
    local key = group.color .. '/' .. group.mark .. '/' .. (group.optimal and '1' or '0')
    local span = markCache[key]
    if not span then
        local glyph = group.optimal and '&#8277;' or (group.mark == 'check' and '&#10003;' or '&#10007;')
        local color = MARK_COLORS[group.color] or group.color
        span = '<span style="color:' .. color .. '">' .. glyph .. '</span>'
        markCache[key] = span
    end
    return span
end

-- One line per source group: "✓ '''Academy:''' Canteen, Commissions".
local function locationCell(drops)
    local lines = {}
    for i = 1, #drops do
        local group = drops[i]
        local locations = group.locations
        local names = {}
        for j = 1, #locations do
            local loc = locations[j]
            local name = loc.name
            if loc.link and loc.link ~= '' then
                name = '[[' .. loc.link .. '|' .. name .. ']]'
            end
            names[j] = name
        end
        local label = GROUP_LABELS[group.group] or group.group
        lines[i] = markWikitext(group) .. " '''" .. label .. ":''' " .. concat(names, ', ')
    end
    return concat(lines, '<br />')
end

-- One line per source group listing guaranteed (and RNG) amounts per source.
local function quantityCell(drops)
    local lines = {}
    for i = 1, #drops do
        local locations = drops[i].locations
        local terms = {}
        for j = 1, #locations do
            local loc = locations[j]
            local term
            if type(loc.amount) == 'number' then
                term = formatNumber(loc.amount) .. (TIMEFRAME_LABELS[loc.timeFrame] or '')
                if loc.timeFrame == 'one-time' then
                    term = term .. ' (one-time)'
                end
            else
                term = 'RNG'
            end
            term = term .. ' (' .. loc.name .. ')'
            if loc.notes then
                term = term .. ', ' .. loc.notes
            end
            terms[j] = term
        end
        lines[i] = concat(terms, ' + ')
    end
    return concat(lines, '<br />')
end

-- Totals come from the data module verbatim (mirroring the ecgc-dev source,
-- where 21 resources use getTotalGuaranteed and the 9 type-random ones
-- report 'N/A'). A field renders only when it is a non-zero number.
local function isVisibleNumber(field)
    return type(field) == 'number' and field ~= 0
end

local function totalCell(resource, isFinite)
    local total = resource.total
    local parts = {}
    local n = 0
    if isFinite then
        if isVisibleNumber(total.oneTime) then
            n = n + 1
            parts[n] = "'''" .. formatNumber(total.oneTime) .. "''' lifetime"
        end
    else
        if isVisibleNumber(total.daily) then
            n = n + 1
            parts[n] = "'''" .. formatNumber(total.daily) .. "/Day'''"
        end
        if isVisibleNumber(total.weekly) then
            n = n + 1
            parts[n] = "'''" .. formatNumber(total.weekly) .. "/Week'''"
        end
        if isVisibleNumber(total.monthly) then
            n = n + 1
            parts[n] = "'''" .. formatNumber(total.monthly) .. "/Month'''"
        end
        if isVisibleNumber(total.bimonthly) then
            n = n + 1
            parts[n] = "'''" .. formatNumber(total.bimonthly) .. "/2 Months'''"
        end
        if isVisibleNumber(total.oneTime) then
            n = n + 1
            parts[n] = "'''" .. formatNumber(total.oneTime) .. "''' one-time"
        end
    end
    local cell = concat(parts, '<br />')
    if resource.notes then
        if cell ~= '' then
            cell = cell .. '<br />'
        end
        cell = cell .. resource.notes
    end
    if cell == '' then
        return '-'
    end
    return cell
end

local function resourceRow(resource, isFinite)
    return concat({
        '|-',
        '| ' .. resource.icon .. '<br />[[' .. resource.link .. '|' .. resource.name .. ']]',
        '| ' .. locationCell(resource.drops),
        '| ' .. quantityCell(resource.drops),
        "| style='white-space:nowrap' | " .. totalCell(resource, isFinite),
        '',
    }, '\n')
end

local function categoryTable(rows, caption, totalHeader)
    return TABLE_OPEN
        .. '\n|+ '
        .. caption
        .. '\n'
        .. TABLE_HEADERS
        .. '\n! '
        .. totalHeader
        .. '\n'
        .. concat(rows, '\n')
        .. '\n|}\n'
end

function p.renewable()
    -- Single pass over the data: bucket rendered rows by category and keep
    -- first-seen category order.
    local categories = {}
    local rowsByCategory = {}
    local infinite = data.infinite
    for i = 1, #infinite do
        local resource = infinite[i]
        local category = resource.category
        local rows = rowsByCategory[category]
        if not rows then
            rows = {}
            rowsByCategory[category] = rows
            insert(categories, category)
        end
        insert(rows, resourceRow(resource, false))
    end

    local output = {}
    for i = 1, #categories do
        local category = categories[i]
        local heading = CATEGORY_HEADINGS[category] or category
        local block = '===' .. heading .. '===\n'
        local seeAlso = CATEGORY_SEE_ALSO[category]
        if seeAlso then
            block = block .. seeAlso .. '\n'
        end
        output[i * 3 - 2] = block
        output[i * 3 - 1] = categoryTable(rowsByCategory[category], heading, 'Total quantity')
        output[i * 3] = ''
    end
    return concat(output, '\n')
end

function p.finite()
    local finite = data.finite
    local rows = {}
    for i = 1, #finite do
        rows[i] = resourceRow(finite[i], true)
    end
    return categoryTable(rows, 'Finite resources', 'Lifetime amount')
end

return p
