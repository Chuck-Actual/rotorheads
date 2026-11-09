-- Test runner. Usage (from the mission/ folder): lua5.1 tests/run.lua
package.path = "./?.lua;" .. package.path

local LOGIC_MODULES = { "util", "config", "core", "logistics", "outposts", "factories", "redair", "lives", "markers", "convoy", "livemap" }

local T = { passed = 0, failed = 0, failures = {} }

function T.fresh()
  RH = nil
  RH_CONFIG_OVERRIDES = nil
  for _, m in ipairs(LOGIC_MODULES) do dofile("src/rh/" .. m .. ".lua") end
  local fake = dofile("tests/fake_dcs.lua")
  local w = fake.new()
  RH.dcs = w.dcs
  RH.util.log = function() end
  math.randomseed(42)
  return w
end

function T.eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", msg or "values differ", tostring(expected), tostring(actual)), 2)
  end
end

function T.ok(cond, msg)
  if not cond then error(msg or "assertion failed", 2) end
end

function T.test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    T.passed = T.passed + 1
    print("  ok   " .. name)
  else
    T.failed = T.failed + 1
    table.insert(T.failures, name)
    print("  FAIL " .. name .. "\n       " .. tostring(err))
  end
end

_G.T = T

local suites = { "test_util", "test_markers", "test_logistics", "test_lives", "test_outposts", "test_factories", "test_convoy", "test_livemap" }
for _, s in ipairs(suites) do
  print(s)
  dofile("tests/" .. s .. ".lua")
end

print(string.format("\n%d passed, %d failed", T.passed, T.failed))
os.exit(T.failed == 0 and 0 or 1)
