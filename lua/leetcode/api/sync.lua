local utils = require("leetcode.api.utils")
local log = require("leetcode.logger")

---Push the code section to LeetCode's synced draft, as Cmd-S does on the
---website. Only works with "sync code" turned on in LeetCode's settings.
local Sync = {}

---LeetCode's editor language ids, as used by `syncedCode`/`updateSyncedCode`.
local LANG_IDS = {
    cpp = 0,
    java = 1,
    python = 2,
    c = 3,
    csharp = 4,
    javascript = 5,
    ruby = 6,
    swift = 7,
    golang = 8,
    python3 = 11,
    scala = 12,
    kotlin = 13,
    rust = 15,
    php = 19,
    typescript = 20,
    racket = 21,
    erlang = 22,
    elixir = 23,
    dart = 24,
}

local told_disabled = false

---@param q lc.ui.Question
function Sync.push(q)
    local lang = LANG_IDS[q.lang]
    if not lang then
        return
    end
    local range = q:editor_section_range("code")
    if not range.complete then
        return
    end
    local code = table.concat(range.lines, "\n", range.start_i, range.end_i)

    local query = [[
        mutation ($questionId: Int!, $lang: Int!, $code: String!) {
            updateSyncedCode(questionId: $questionId, lang: $lang, code: $code) { ok }
        }
    ]]
    utils.query(query, { questionId = tonumber(q.q.id), lang = lang, code = code }, {
        callback = function(res)
            local ok = type(res) == "table"
                and type(res.data) == "table"
                and type(res.data.updateSyncedCode) == "table"
                and res.data.updateSyncedCode.ok
            if not ok and not told_disabled then
                told_disabled = true
                log.info("Saved locally. To sync drafts with leetcode.com, turn on code sync in LeetCode's settings")
            end
        end,
    })
end

return Sync
