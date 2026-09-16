-- Test harness for modules/CommonResource.lua, run under wasmoon (Lua 5.4).
-- The wiki repo runs Scribunto (Lua 5.1); modules are kept 5.1-compatible.
--
-- Run from the wiki repo root:
--   script -q /dev/null bunx wasmoon -l modules -l scripts scripts/common_resource/run_tests.lua
--
-- Checks:
--   1. The Lua port of the TypeScript getTotalGuaranteed (kept here,
--      test-only) matches the TS dump for every numeric totals field
--      (scripts/common_resource/common_resource_expected.lua).
--   2. Data-module totals match the TS dump verbatim.
--   3. Rendered wikitext is byte-identical to the frozen snapshots in
--      scripts/common_resource/snapshots/ (regenerate both together when
--      the guide data changes on purpose).
--   4. Smoke checks: non-empty output, balanced table braces, spot values.

-- Repo root derived from this script's own path. wasmoon's file opener only
-- accepts absolute real paths (no '..' normalization, no relative resolution),
-- so strip path segments from the string instead of relying on the FS.
local SCRIPT_DIR = debug.getinfo(1, 'S').source:match('^@(.*)/')
local BASE = SCRIPT_DIR:gsub('/[^/]+$', ''):gsub('/[^/]+$', '')

-- Scribunto stub: the module loads its data via mw.loadData; on the wiki this
-- shares one immutable copy per page parse. Under the harness, require
-- against the generated file on disk.
mw = {
    loadData = function(name)
        return require(name)
    end,
}
package.preload['Module:CommonResourceData'] = function()
    return dofile(BASE .. '/modules/CommonResourceData.lua')
end

local commonResource = dofile(BASE .. '/modules/CommonResource.lua')
local dataModule = dofile(BASE .. '/modules/CommonResourceData.lua')
local expected = dofile(BASE .. '/scripts/common_resource/common_resource_expected.lua')

local failures = 0

local function assertEqual(actual, want, label)
    if actual ~= want then
        failures = failures + 1
        print(string.format('FAIL %s: got %s, want %s', label, tostring(actual), tostring(want)))
    end
end

-- Port of the ecgc-dev getTotalGuaranteed, quirks included. Test-only: the
-- wiki module renders the totals stored in the data module verbatim.
local NUM_CHAPTERS = 15
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

local FIELDS = { 'bimonthly', 'monthly', 'weekly', 'daily', 'oneTime' }

-- 1. Totals equivalence: wherever the TS dump has a number, the Lua port of
--    getTotalGuaranteed must reproduce it from the drops data. The 9
--    type-random resources hardcode 'N/A' on the TS side, so only numeric
--    dump values are reproducible from drops.
local nameSet = {}
local computed = { infinite = {}, finite = {} }
for _, section in ipairs({ 'infinite', 'finite' }) do
    for _, resource in ipairs(dataModule[section]) do
        nameSet[resource.name] = true
        computed[section][resource.name] = getTotalGuaranteed(resource)
    end
end

local checked = 0
for _, section in ipairs({ 'infinite', 'finite' }) do
    local expectedCount = 0
    for name, totals in pairs(expected[section]) do
        expectedCount = expectedCount + 1
        local got = computed[section][name]
        if got == nil then
            failures = failures + 1
            print('FAIL missing resource: ' .. name)
        else
            for _, field in ipairs(FIELDS) do
                if type(totals[field]) == 'number' then
                    assertEqual(got[field], totals[field], string.format('%s.%s', name, field))
                end
            end
        end
        checked = checked + 1
    end
    local dataCount = #dataModule[section]
    if expectedCount ~= dataCount then
        failures = failures + 1
        print(string.format('FAIL %s count: expected %d, data %d', section, expectedCount, dataCount))
    end
end

-- 2. Data-module totals must match the dump exactly (copied verbatim), and
--    every data resource must exist in the dump.
for _, section in ipairs({ 'infinite', 'finite' }) do
    for _, resource in ipairs(dataModule[section]) do
        local want = expected[section][resource.name]
        if want == nil then
            failures = failures + 1
            print('FAIL no expected totals for: ' .. resource.name)
        else
            for _, field in ipairs(FIELDS) do
                assertEqual(
                    resource.total[field],
                    want[field],
                    string.format('data.%s.%s', resource.name, field)
                )
            end
        end
    end
end
print(string.format('totals compared: %d resources, %d failures so far', checked, failures))

-- 3. Snapshot regression: rendered output must be byte-identical.
local renewable = commonResource.renewable()
local finite = commonResource.finite()

local function readOrWriteSnapshot(filename, rendered)
    local path = BASE .. '/scripts/common_resource/snapshots/' .. filename
    local file = io.open(path, 'r')
    if file == nil then
        file = assert(io.open(path, 'w'))
        file:write(rendered)
        file:close()
        print('snapshot written (new): ' .. filename)
        return
    end
    local content = file:read('*a')
    file:close()
    if content ~= rendered then
        failures = failures + 1
        local firstDiff = math.min(#content, #rendered)
        for i = 1, math.min(#content, #rendered) do
            if content:byte(i) ~= rendered:byte(i) then
                firstDiff = i
                break
            end
        end
        print(string.format(
            'FAIL snapshot differs: %s (lens %d vs %d, first diff at %d)',
            filename, #content, #rendered, firstDiff
        ))
    end
end
readOrWriteSnapshot('renewable.wikitext', renewable)
readOrWriteSnapshot('finite.wikitext', finite)

-- 4. Smoke checks.
local _, openCount = renewable:gsub('{|', '')
local _, closeCount = renewable:gsub('|}', '')
assertEqual(openCount > 0, true, 'renewable has table starts')
assertEqual(openCount, closeCount, 'renewable balanced table braces')
assertEqual(#finite > 0, true, 'finite renders')
assertEqual(renewable:find('113,820', 1, true) ~= nil, true, 'oil monthly total rendered')
assertEqual(renewable:find('2,910', 1, true) ~= nil, true, 'core data monthly total rendered')
assertEqual(finite:find('4,700', 1, true) ~= nil, true, 'gem lifetime total rendered')

-- Emit rendered wikitext between markers so the shell can capture it (the
-- wasmoon FS sandbox discards io.open writes, so stdout is the only channel).
print('===RENEWABLE_START===')
print(renewable)
print('===RENEWABLE_END===')
print('===FINITE_START===')
print(finite)
print('===FINITE_END===')

if failures == 0 then
    print('ALL TESTS PASSED')
else
    print('TESTS FAILED: ' .. failures)
    os.exit(1)
end
