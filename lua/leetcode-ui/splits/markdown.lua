---Turn LeetCode article markdown into plain markdown a Neovim buffer can show.
local Markdown = {}

local PLAYGROUND = "<<playground:(%w+)>>"

---@param content string
---@return string[] lines, string[] playground_uuids
function Markdown.clean(content)
    local s = content:gsub("\r\n", "\n")

    s = s:gsub("%[TOC%]", "")
    s = s:gsub("<lcvideo>.-</lcvideo>", "")
    s = s:gsub("<iframe[^>]-player%.vimeo%.com.-</iframe>", "")
    s = s:gsub("##+ Video Solution%s*%-%-%-+", "")
    s = s:gsub('<iframe[^>]-src="https://leetcode%.com/playground/(%w+)/shared".-</iframe>', "\n<<playground:%1>>\n")
    s = s:gsub("<iframe.-</iframe>", "")
    s = s:gsub("</?div[^>]*>", "")
    s = s:gsub("&nbsp;", " ")
    s = s:gsub("%$%$(.-)%$%$", "`%1`")
    s = s:gsub("\n\n\n+", "\n\n")

    local uuids = {}
    for uuid in s:gmatch(PLAYGROUND) do
        table.insert(uuids, uuid)
    end

    return vim.split(vim.trim(s), "\n"), uuids
end

---@param a string
---@param b string
local function same_lang(a, b)
    return a == b or (a:match("^python") ~= nil and b:match("^python") ~= nil)
end

---Replace playground placeholders with fenced code in the reader's language.
---LeetCode does not have every language for every article; then the
---configured default language is used, else Python 3, else the first one,
---and the fence is marked `fallback` so the card can say so.
---@param lines string[]
---@param codes table<string, { code: string, langSlug: string }[]>
---@param lang string lang slug, for example "rust"
---@return string[]
function Markdown.fill_playgrounds(lines, codes, lang)
    local preferred = { lang, require("leetcode.config").user.lang, "python3" }
    local out = {}
    for _, line in ipairs(lines) do
        local uuid = line:match("^%s*" .. PLAYGROUND .. "%s*$")
        if not uuid then
            table.insert(out, line)
        else
            local list = codes[uuid]
            local pick
            for _, want in ipairs(preferred) do
                for _, c in ipairs(list or {}) do
                    if not pick and same_lang(c.langSlug, want) then
                        pick = c
                    end
                end
            end
            pick = pick or (list and list[1])

            if pick then
                local fallback = not same_lang(pick.langSlug, lang) and " fallback" or ""
                table.insert(out, "```" .. pick.langSlug .. fallback)
                vim.list_extend(out, vim.split((pick.code:gsub("\r\n", "\n")), "\n"))
                table.insert(out, "```")
            elseif list then
                table.insert(out, "_(code unavailable)_")
            else
                table.insert(out, "_Loading code…_")
            end
        end
    end
    return out
end

return Markdown
