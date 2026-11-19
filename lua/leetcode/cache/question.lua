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

return QuestionCache
