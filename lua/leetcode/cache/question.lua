local config = require("leetcode.config")
local log = require("leetcode.logger")

---On-disk cache of full question payloads, so a question opens without waiting
---on the network. Entries are refreshed in the background after each open.
---@class lc.cache.QuestionPayload
local QuestionCache = {}

---@type table<string, lc.question_res>
local memory = {}

---@param title_slug string
local function file_for(title_slug)
    local dir = config.storage.cache:joinpath("questions" .. (config.is_cn and "_cn" or ""))
    return dir, dir:joinpath(title_slug .. ".json")
end

---@param title_slug string
---@return lc.question_res?
function QuestionCache.get(title_slug)
    if memory[title_slug] then
        return memory[title_slug]
    end

    local _, file = file_for(title_slug)
    local fd = io.open(file:absolute(), "r")
    if not fd then
        return
    end
    local contents = fd:read("*a")
    fd:close()

    local ok, cached = pcall(vim.json.decode, contents)
    if not ok or type(cached) ~= "table" or cached.version ~= config.version then
        return
    end

    memory[title_slug] = cached.question
    return cached.question
end

---@param title_slug string
---@param q lc.question_res
function QuestionCache.set(title_slug, q)
    memory[title_slug] = q

    local dir, file = file_for(title_slug)
    local ok, encoded = pcall(vim.json.encode, { version = config.version, question = q })
    if not ok then
        return log.debug("question cache encode failed: " .. tostring(encoded))
    end

    vim.uv.fs_mkdir(dir:absolute(), 448, function()
        vim.uv.fs_open(file:absolute(), "w", 420, function(err, fd)
            if err or not fd then
                return
            end
            vim.uv.fs_write(fd, encoded, -1, function()
                vim.uv.fs_close(fd)
            end)
        end)
    end)
end

---@type table<string, fun(q?: lc.question_res, err?: lc.err)[]>
local inflight = {}

---Fetch a question once, however many callers ask while it is in flight, and
---cache the result.
---@param title_slug string
---@param cb? fun(q?: lc.question_res, err?: lc.err)
function QuestionCache.fetch(title_slug, cb)
    if inflight[title_slug] then
        if cb then
            table.insert(inflight[title_slug], cb)
        end
        return
    end
    inflight[title_slug] = cb and { cb } or {}

    require("leetcode.api.question").fetch(title_slug, function(q, err)
        local waiting = inflight[title_slug]
        inflight[title_slug] = nil
        if q then
            QuestionCache.set(title_slug, q)
        end
        for _, fn in ipairs(waiting) do
            fn(q, err)
        end
    end)
end

local prefetch_timer

---Warm the cache for a question the user is likely to open, for example the
---one under the picker cursor. Debounced so scrolling does not fire requests.
---@param title_slug string
function QuestionCache.prefetch(title_slug)
    prefetch_timer = prefetch_timer or vim.uv.new_timer()
    prefetch_timer:stop()
    prefetch_timer:start(150, 0, vim.schedule_wrap(function()
        if not QuestionCache.get(title_slug) then
            QuestionCache.fetch(title_slug)
        end
    end))
end

return QuestionCache
