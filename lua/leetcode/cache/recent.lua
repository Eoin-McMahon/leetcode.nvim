local config = require("leetcode.config")

---Recently opened questions, newest first, kept on disk across sessions.
local Recent = {}

local MAX = 30

local function file()
    return config.storage.cache:joinpath("recent" .. (config.is_cn and "_cn" or "") .. ".json"):absolute()
end

---@return string[] title slugs
function Recent.slugs()
    local ok, data = pcall(function()
        return vim.json.decode(table.concat(vim.fn.readfile(file()), "\n"))
    end)
    return ok and type(data) == "table" and data or {}
end

---@param slug string
function Recent.add(slug)
    local list = vim.tbl_filter(function(s)
        return s ~= slug
    end, Recent.slugs())
    table.insert(list, 1, slug)
    list = vim.list_slice(list, 1, MAX)
    pcall(vim.fn.writefile, { vim.json.encode(list) }, file())
end

---@return lc.cache.Question[]
function Recent.questions()
    local problemlist = require("leetcode.cache.problemlist")
    local out = {}
    for _, slug in ipairs(Recent.slugs()) do
        local ok, q = pcall(problemlist.get_by_title_slug, slug)
        if ok and q then
            table.insert(out, q)
        end
    end
    return out
end

return Recent
