-- Test harness for modules/CommonResource.lua, run under wasmoon (Lua 5.4).
-- The wiki repo runs Scribunto (Lua 5.1); modules are kept 5.1-compatible.
--
-- Run from the wiki repo root:
--   script -q /dev/null bunx wasmoon -l modules -l scripts scripts/common_resource/run_tests.lua
--
-- Checks:
--   1. Lua-computed totals match the TypeScript getTotalGuaranteed dump for
--      every resource (scripts/common_resource/common_resource_expected.lua).
--   2. Rendering both sections produces non-empty wikitext with balanced
--      table braces.

-- Repo root derived from this script's own path. wasmoon's file opener only
-- accepts absolute real paths (no '..' normalization, no relative resolution),
-- so strip path segments from the string instead of relying on the FS.
local SCRIPT_DIR = debug.getinfo(1, 'S').source:match('^@(.*)/')
local BASE = SCRIPT_DIR:gsub('/[^/]+$', ''):gsub('/[^/]+$', '')

-- Resolve Module:CommonResourceData the MediaWiki way (require 'Module:...')
-- against the generated file on disk.
package.preload['Module:CommonResourceData'] = function()
    return dofile(BASE .. '/modules/CommonResourceData.lua')
end

local commonResource = dofile(BASE .. '/modules/CommonResource.lua')
local expected = dofile(BASE .. '/scripts/common_resource/common_resource_expected.lua')

local failures = 0

local function assertEqual(actual, want, label)
    if actual ~= want then
        failures = failures + 1
        print(string.format('FAIL %s: got %s, want %s', label, tostring(actual), tostring(want)))
    end
end

-- 1. Totals equivalence: the data module must carry the TS dump totals
--    verbatim, and wherever the dump has a number, the Lua port of
--    getTotalGuaranteed must reproduce it from the drops data.
local computed = commonResource.totals()
local checked = 0
for _, section in ipairs({ 'infinite', 'finite' }) do
    for name, totals in pairs(expected[section]) do
        local got = computed[section][name]
        if got == nil then
            failures = failures + 1
            print('FAIL missing resource: ' .. name)
        else
            for _, field in ipairs({ 'bimonthly', 'monthly', 'weekly', 'daily', 'oneTime' }) do
                -- The 9 type-random resources hardcode 'N/A' on the TS side,
                -- so only numeric dump values are reproducible from drops.
                if type(totals[field]) == 'number' then
                    assertEqual(got[field], totals[field], string.format('%s.%s', name, field))
                end
            end
        end
        checked = checked + 1
    end
end

-- Data-module totals must match the dump exactly (they are copied verbatim).
local dataModule = dofile(BASE .. '/modules/CommonResourceData.lua')
for _, section in ipairs({ 'infinite', 'finite' }) do
    for _, resource in ipairs(dataModule[section]) do
        local want = expected[section][resource.name]
        if want == nil then
            failures = failures + 1
            print('FAIL no expected totals for: ' .. resource.name)
        else
            for _, field in ipairs({ 'bimonthly', 'monthly', 'weekly', 'daily', 'oneTime' }) do
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

-- 2. Render smoke checks.
local renewable = commonResource.renewable()
local finite = commonResource.finite()

local _, openCount = renewable:gsub('{|', '')
local _, closeCount = renewable:gsub('|}', '')
assertEqual(openCount > 0, true, 'renewable has table starts')
assertEqual(openCount, closeCount, 'renewable balanced table braces')
assertEqual(#finite > 0, true, 'finite renders')

-- Sample number spot-checks against known TS dump values.
assertEqual(renewable:find('113,820', 1, true) ~= nil, true, 'oil monthly total rendered')
assertEqual(renewable:find('2,910', 1, true) ~= nil, true, 'core data monthly total rendered')
assertEqual(finite:find('4,700', 1, true) ~= nil, true, 'gem lifetime total rendered')

-- Emit rendered wikitext between markers for shell capture.
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
