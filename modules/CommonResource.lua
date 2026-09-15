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
-- Total math mirrors ecgc-dev getTotalGuaranteed exactly: month = 30 days,
-- 4 weeks per month; Monthly and Bimonthly are summed separately, and
-- Weekly/Daily derive from the Monthly sum (before the bimonthly fallback).

local p = {}

local data = require('Module:CommonResourceData')

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

local NUM_CHAPTERS = 15

-- Formats 1234567 -> "1,234,567"; keeps up to 2 decimals, trailing zeros trimmed.
local function formatNumber(value)
    if type(value) == 'string' then
        return value
    end
    local body
    if math.floor(value) == value then
        body = string.format('%d', value)
    else
        body = string.format('%.2f', value)
        body = body:gsub('0+$', ''):gsub('%.$', '')
    end
    local withCommas = body:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    withCommas = withCommas:gsub('^,', '')
    return withCommas
end

-- Port of the ecgc-dev getTotalGuaranteed, quirks included.
local function getTotalGuaranteed(resource)
    local monthlyTotal = 0
    local bimonthlyTotal = 0
    local oneTimeTotal = 0

    for _, group in ipairs(resource.drops) do
        for _, loc in ipairs(group.locations) do
            local amount = loc.amount
            if type(amount) == 'number' then
                local tf = loc.timeFrame
                if tf == 'daily' then
                    monthlyTotal = monthlyTotal + amount * 30
                    bimonthlyTotal = bimonthlyTotal + amount * 60
                elseif tf == 'weekly' then
                    monthlyTotal = monthlyTotal + amount * 4
                    bimonthlyTotal = bimonthlyTotal + amount * 8
                elseif tf == 'monthly' then
                    monthlyTotal = monthlyTotal + amount
                    bimonthlyTotal = bimonthlyTotal + amount * 2
                elseif tf == 'bimonthly' then
                    bimonthlyTotal = bimonthlyTotal + amount
                elseif tf == 'one-time' then
                    oneTimeTotal = oneTimeTotal + amount
                elseif tf == 'chapter' then
                    oneTimeTotal = oneTimeTotal + amount * NUM_CHAPTERS
                end
            end
        end
    end

    local monthly = monthlyTotal
    if monthly == 0 then
        monthly = math.floor(bimonthlyTotal / 2)
    end
    return {
        bimonthly = bimonthlyTotal,
        monthly = monthly,
        weekly = math.floor(monthlyTotal / 4),
        daily = math.floor(monthlyTotal / 30),
        oneTime = oneTimeTotal ~= 0 and oneTimeTotal or 'N/A',
    }
end

local function markWikitext(group)
    local glyph = group.optimal and '&#8277;' or (group.mark == 'check' and '&#10003;' or '&#10007;')
    local color = MARK_COLORS[group.color] or group.color
    return string.format('<span style="color:%s">%s</span>', color, glyph)
end

local function linkWikitext(loc)
    if loc.link and loc.link ~= '' then
        return string.format('[[%s|%s]]', loc.link, loc.name)
    end
    return loc.name
end

-- One line per source group: "✓ '''Academy:''' Canteen, Commissions".
local function locationCell(resource)
    local lines = {}
    for _, group in ipairs(resource.drops) do
        local names = {}
        for _, loc in ipairs(group.locations) do
            table.insert(names, linkWikitext(loc))
        end
        local label = GROUP_LABELS[group.group] or group.group
        table.insert(
            lines,
            string.format("%s '''%s:''' %s", markWikitext(group), label, table.concat(names, ', '))
        )
    end
    return table.concat(lines, '<br />')
end

-- One line per source group listing guaranteed (and RNG) amounts per source.
local function quantityCell(resource)
    local lines = {}
    for _, group in ipairs(resource.drops) do
        local terms = {}
        for _, loc in ipairs(group.locations) do
            local term
            if type(loc.amount) == 'number' then
                local tf = loc.timeFrame or ''
                term = formatNumber(loc.amount) .. (TIMEFRAME_LABELS[tf] or '')
                if tf == 'one-time' then
                    term = term .. ' (one-time)'
                end
            else
                term = 'RNG'
            end
            term = term .. ' (' .. loc.name .. ')'
            if loc.notes then
                term = term .. ', ' .. loc.notes
            end
            table.insert(terms, term)
        end
        table.insert(lines, table.concat(terms, ' + '))
    end
    return table.concat(lines, '<br />')
end

local function totalCell(resource, isFinite)
    -- Totals come from the data module verbatim (mirroring the ecgc-dev
    -- source, where 21 resources use getTotalGuaranteed and the 9 type-random
    -- ones report 'N/A').
    local total = resource.total
    -- A field renders only when it is a non-zero number ('N/A' and 0 are skipped).
    local function show(field)
        return type(field) == 'number' and field ~= 0
    end
    local parts = {}
    if isFinite then
        if show(total.oneTime) then
            table.insert(parts, string.format("'''%s''' lifetime", formatNumber(total.oneTime)))
        end
    else
        if show(total.daily) then
            table.insert(parts, string.format("'''%s/Day'''", formatNumber(total.daily)))
        end
        if show(total.weekly) then
            table.insert(parts, string.format("'''%s/Week'''", formatNumber(total.weekly)))
        end
        if show(total.monthly) then
            table.insert(parts, string.format("'''%s/Month'''", formatNumber(total.monthly)))
        end
        if show(total.bimonthly) then
            table.insert(parts, string.format("'''%s/2 Months'''", formatNumber(total.bimonthly)))
        end
        if show(total.oneTime) then
            table.insert(
                parts,
                string.format("'''%s''' one-time", formatNumber(total.oneTime))
            )
        end
    end
    local cell = table.concat(parts, '<br />')
    if resource.notes then
        if cell ~= '' then
            cell = cell .. '<br />'
        end
        cell = cell .. resource.notes
    end
    if cell == '' then
        cell = "-"
    end
    return cell
end

local function resourceRow(resource, isFinite)
    local itemCell = string.format("%s<br />[[%s|%s]]", resource.icon, resource.link, resource.name)
    return table.concat({
        '|-',
        '| ' .. itemCell,
        '| ' .. locationCell(resource),
        '| ' .. quantityCell(resource),
        "| style='white-space:nowrap' | " .. totalCell(resource, isFinite),
        '',
    }, '\n')
end

local function categoryTable(resources, caption, totalHeader, isFinite)
    local rows = {}
    for _, resource in ipairs(resources) do
        table.insert(rows, resourceRow(resource, isFinite))
    end
    return table.concat({
        '{|class="azltable mw-collapsible" style="width:100%; text-align:center"',
        '|+ ' .. caption,
        "! style='width:175px' | Item",
        "! style='width:400px' | Location",
        '! Guaranteed quantities (if applicable)',
        '! ' .. totalHeader,
        table.concat(rows, '\n'),
        '|}',
        '',
    }, '\n')
end

-- Keeps only resources of one category, preserving data order.
local function filterByCategory(resources, category)
    local filtered = {}
    for _, resource in ipairs(resources) do
        if resource.category == category then
            table.insert(filtered, resource)
        end
    end
    return filtered
end

function p.renewable()
    local seen = {}
    local categories = {}
    for _, resource in ipairs(data.infinite) do
        if not seen[resource.category] then
            seen[resource.category] = true
            table.insert(categories, resource.category)
        end
    end

    local output = {}
    for _, category in ipairs(categories) do
        local heading = CATEGORY_HEADINGS[category] or category
        table.insert(output, '===' .. heading .. '===')
        local seeAlso = CATEGORY_SEE_ALSO[category]
        if seeAlso then
            table.insert(output, seeAlso)
        end
        table.insert(output, '')
        local label = CATEGORY_HEADINGS[category] or category
        table.insert(output, categoryTable(filterByCategory(data.infinite, category), label, 'Total quantity', false))
        table.insert(output, '')
    end
    return table.concat(output, '\n')
end

function p.finite()
    return categoryTable(data.finite, 'Finite resources', 'Lifetime amount', true)
end

-- Exposed for tests: totals keyed by resource name.
function p.totals()
    local result = { infinite = {}, finite = {} }
    for _, resource in ipairs(data.infinite) do
        result.infinite[resource.name] = getTotalGuaranteed(resource)
    end
    for _, resource in ipairs(data.finite) do
        result.finite[resource.name] = getTotalGuaranteed(resource)
    end
    return result
end

return p
