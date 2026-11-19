---Deterministic work-sounding names for the stealth overlay. The same question
---and symbol always get the same fake name, across sessions.
local Names = {}

local NOUNS = {
    "shipment", "inventory", "order", "batch", "route", "slot", "ledger", "stock",
    "demand", "supplier", "warehouse", "carrier", "invoice", "tenant", "billing",
    "pallet", "dock", "picker", "manifest", "forecast", "quota", "region", "catalog",
    "account", "payment", "schedule", "capacity", "sku", "delivery", "fleet",
}
local VERBS = {
    "resolve", "allocate", "reconcile", "compute", "merge", "validate", "normalize",
    "aggregate", "dispatch", "rebalance", "collect", "index", "schedule", "assign",
    "prune", "sync", "build", "load", "project", "partition",
}
local SUFFIXES = {
    "allocator", "resolver", "planner", "ledger", "balancer", "registry", "service",
    "builder", "tracker", "index", "router", "scheduler", "cache", "store",
}
local PARAM_SUFFIXES = { "ids", "codes", "limit", "count", "map", "items", "window", "keys", "rows", "batch" }

---FNV-1a, so names do not depend on Lua's string hashing.
---@param s string
---@return integer
local function hash(s)
    local h = 2166136261
    for i = 1, #s do
        h = bit.bxor(h, s:byte(i))
        h = bit.band(h * 16777619, 0xffffffff)
    end
    return h
end

---@param list string[]
---@param h integer
---@param salt integer
local function pick(list, h, salt)
    return list[(bit.rshift(h, salt) % #list) + 1]
end

---@param original string
---@return "pascal"|"camel"|"snake"|"upper"
local function style_of(original)
    if original:match("^[A-Z][A-Z0-9_]*$") and #original > 1 then
        return "upper"
    elseif original:match("^[A-Z]") then
        return "pascal"
    elseif original:match("%l%u") then
        return "camel"
    end
    return "snake"
end

---@param words string[]
---@param style string
local function format(words, style)
    if style == "snake" then
        return table.concat(words, "_")
    elseif style == "upper" then
        return table.concat(words, "_"):upper()
    end
    local out = {}
    for i, w in ipairs(words) do
        out[i] = (style == "camel" and i == 1) and w or (w:sub(1, 1):upper() .. w:sub(2))
    end
    return table.concat(out)
end

---@param kind "type"|"function"|"parameter"
---@param seed string
---@param original string
---@param attempt integer
---@return string
local function make(kind, seed, original, attempt)
    local h = hash(seed .. ":" .. original .. ":" .. attempt)
    local words
    if kind == "type" then
        words = { pick(NOUNS, h, 0), pick(SUFFIXES, h, 8) }
    elseif kind == "function" then
        words = { pick(VERBS, h, 0), pick(NOUNS, h, 8) }
        if bit.band(h, 1) == 1 then
            table.insert(words, pick(PARAM_SUFFIXES, h, 16))
        end
    else
        words = { pick(NOUNS, h, 0), pick(PARAM_SUFFIXES, h, 8) }
    end
    return format(words, style_of(original))
end

---@param seed string usually the question slug
---@param symbols { name: string, kind: "type"|"function"|"parameter" }[]
---@return table<string, string>
function Names.map(seed, symbols)
    local map, used = {}, {}
    for _, sym in ipairs(symbols) do
        if not map[sym.name] then
            local attempt, fake = 0, nil
            repeat
                fake = make(sym.kind, seed, sym.name, attempt)
                attempt = attempt + 1
            until not used[fake] or attempt > 20
            map[sym.name] = fake
            used[fake] = true
        end
    end
    return map
end

---@param seed string
---@param ext string
function Names.filename(seed, ext)
    local h = hash(seed)
    return ("%s_%s.%s"):format(pick(NOUNS, h, 0), pick(SUFFIXES, h, 8), ext)
end

return Names
