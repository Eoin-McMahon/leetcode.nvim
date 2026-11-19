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

---Replace playground placeholders with fenced code in the preferred language.
---@param lines string[]
---@param codes table<string, { code: string, langSlug: string }[]>
---@param lang string lang slug, for example "python3"
---@param ft string fence language, for example "python"
---@return string[]
function Markdown.fill_playgrounds(lines, codes, lang, ft)
    local out = {}
    for _, line in ipairs(lines) do
        local uuid = line:match("^%s*" .. PLAYGROUND .. "%s*$")
        if not uuid then
            table.insert(out, line)
        else
            local list = codes[uuid]
            local pick
            for _, c in ipairs(list or {}) do
                if c.langSlug == lang then
                    pick = c
                end
            end
            if not pick and list and list[1] then
                pick = list[1]
            end

            if pick then
                table.insert(out, "```" .. (pick == list[1] and pick.langSlug ~= lang and pick.langSlug or ft))
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
