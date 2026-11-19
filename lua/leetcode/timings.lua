local config = require("leetcode.config")

---@class lc.Timings
local Timings = {}

local MAX_ENTRIES = 200

---@type { name: string, ms: number, at: integer }[]
local entries = {}

local function enabled()
    return config.user.debug_timings == true
end

---Start a span. Returns a function that ends it, so callbacks can close spans
---they did not open.
---@param name string
---@return fun(suffix?: string)
function Timings.start(name)
    if not enabled() then
        return function() end
    end

    local started = vim.uv.hrtime()
    return function(suffix)
        local ms = (vim.uv.hrtime() - started) / 1e6
        table.insert(entries, { name = suffix and (name .. " " .. suffix) or name, ms = ms, at = os.time() })
        if #entries > MAX_ENTRIES then
            table.remove(entries, 1)
        end
    end
end

---@param name string
---@param fn function
function Timings.wrap(name, fn)
    return function(...)
        local stop = Timings.start(name)
        local results = { fn(...) }
        stop()
        return unpack(results)
    end
end

function Timings.entries()
    return entries
end

function Timings.show()
    if not enabled() then
        return require("leetcode.logger").warn("Set `debug_timings = true` to record timings")
    end

    local lines = {}
    for i = #entries, 1, -1 do
        local e = entries[i]
        table.insert(lines, ("%s  %8.1f ms  %s"):format(os.date("%H:%M:%S", e.at), e.ms, e.name))
    end
    if #lines == 0 then
        lines = { "No timings recorded yet" }
    end

    vim.cmd("botright new")
    local bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].buftype = "nofile"
    vim.bo[bufnr].bufhidden = "wipe"
    vim.bo[bufnr].modifiable = false
    vim.api.nvim_buf_set_name(bufnr, "leetcode://timings")
end

return Timings
