local config = require("leetcode.config")
local log = require("leetcode.logger")

---Read the website editor's autosaved draft from Firefox-family browsers.
---
---LeetCode keeps drafts in IndexedDB (`LeetCode-problems`, store
---`problem_code`) under `<questionId>_<sessionId>_<lang>`, with the save time in
---`<key>-updated-time`. Firefox stores IndexedDB values as snappy-compressed
---structured clones, so both are decoded here. Chromium keeps IndexedDB in
---LevelDB, which is not supported.
local Draft = {}

local dir = vim.uv.os_homedir() .. "/Library/Application Support/"
local GLOBS = {
    "zen/Profiles/*/storage/default/https+++leetcode.%s*/idb/*.sqlite",
    "Firefox/Profiles/*/storage/default/https+++leetcode.%s*/idb/*.sqlite",
}
local SQL = "select hex(d.key), hex(d.data) from object_data d join object_store s"
    .. " on s.id = d.object_store_id where s.name = 'problem_code'"

local SCTAG_STRING = 0xFFFF0004

---@param hex string
local function unhex(hex)
    return (hex:gsub("..", function(h)
        return string.char(tonumber(h, 16))
    end))
end

---@param data string
---@return string?
function Draft.snappy(data)
    local pos, len, shift = 1, 0, 0
    repeat
        local b = data:byte(pos)
        if not b then
            return
        end
        len = len + bit.lshift(bit.band(b, 0x7f), shift)
        shift = shift + 7
        pos = pos + 1
    until b < 0x80

    local out = {}
    local function le(n)
        local v = 0
        for i = 0, n - 1 do
            v = v + bit.lshift(data:byte(pos + i), 8 * i)
        end
        pos = pos + n
        return v
    end

    while pos <= #data do
        local tag = data:byte(pos)
        pos = pos + 1
        local kind = bit.band(tag, 3)

        if kind == 0 then
            local n = bit.rshift(tag, 2)
            if n >= 60 then
                n = le(n - 59)
            end
            n = n + 1
            for i = 0, n - 1 do
                out[#out + 1] = data:byte(pos + i)
            end
            pos = pos + n
        else
            local n, offset
            if kind == 1 then
                n = bit.band(bit.rshift(tag, 2), 7) + 4
                offset = bit.lshift(bit.rshift(tag, 5), 8) + data:byte(pos)
                pos = pos + 1
            else
                n = bit.rshift(tag, 2) + 1
                offset = le(kind == 2 and 2 or 4)
            end
            local start = #out - offset
            if offset == 0 or start < 0 then
                return
            end
            for i = 1, n do
                out[#out + 1] = out[start + i]
            end
        end
    end

    if #out ~= len then
        return
    end
    local chunks = {}
    for i = 1, #out, 4096 do
        chunks[#chunks + 1] = string.char(unpack(out, i, math.min(i + 4095, #out)))
    end
    return table.concat(chunks)
end

---@param s string
---@param i integer 1-based
local function u32(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    return a + b * 0x100 + c * 0x10000 + d * 0x1000000
end

---@param cp integer code point
local function utf8(cp)
    if cp < 0x80 then
        return string.char(cp)
    elseif cp < 0x800 then
        return string.char(0xC0 + bit.rshift(cp, 6), 0x80 + bit.band(cp, 0x3F))
    elseif cp < 0x10000 then
        return string.char(
            0xE0 + bit.rshift(cp, 12),
            0x80 + bit.band(bit.rshift(cp, 6), 0x3F),
            0x80 + bit.band(cp, 0x3F)
        )
    end
    return string.char(
        0xF0 + bit.rshift(cp, 18),
        0x80 + bit.band(bit.rshift(cp, 12), 0x3F),
        0x80 + bit.band(bit.rshift(cp, 6), 0x3F),
        0x80 + bit.band(cp, 0x3F)
    )
end

---First string in a structured clone, as UTF-8.
---@param data string
---@return string?
function Draft.clone_string(data)
    for i = 1, #data - 7, 8 do
        if u32(data, i + 4) == SCTAG_STRING then
            local word = u32(data, i)
            local latin1 = word >= 0x80000000
            local n = latin1 and word - 0x80000000 or word
            local body = i + 8

            if latin1 then
                local chars = {}
                for j = 0, n - 1 do
                    chars[#chars + 1] = utf8(data:byte(body + j))
                end
                return table.concat(chars)
            end

            local chars, j = {}, 0
            while j < n do
                local lo, hi = data:byte(body + 2 * j, body + 2 * j + 1)
                local unit = lo + hi * 256
                if unit >= 0xD800 and unit <= 0xDBFF and j + 1 < n then
                    local lo2, hi2 = data:byte(body + 2 * j + 2, body + 2 * j + 3)
                    local low = lo2 + hi2 * 256
                    unit = 0x10000 + (unit - 0xD800) * 0x400 + (low - 0xDC00)
                    j = j + 1
                end
                chars[#chars + 1] = utf8(unit)
                j = j + 1
            end
            return table.concat(chars)
        end
    end
end

---IndexedDB string keys are a 0x30 type byte, then each ASCII char plus one.
---@param key string
---@return string?
function Draft.key(key)
    if key:byte(1) ~= 0x30 then
        return
    end
    local chars = {}
    for i = 2, #key do
        local b = key:byte(i)
        if b >= 0x80 then
            return
        end
        chars[#chars + 1] = string.char(b - 1)
    end
    return table.concat(chars)
end

---@return string[]
local function databases()
    local list = {}
    for _, glob in ipairs(GLOBS) do
        vim.list_extend(list, vim.fn.glob(dir .. glob:format(config.domain), false, true))
    end
    return list
end

---@param db string
---@param cb fun(rows: string[][])
local function query(db, cb)
    -- Browsers lock the store and keep recent writes in the WAL: query a copy.
    local tmp = vim.fn.tempname()
    vim.uv.fs_copyfile(db, tmp)
    vim.uv.fs_copyfile(db .. "-wal", tmp .. "-wal")
    vim.system({ "sqlite3", "-separator", "\t", tmp, SQL }, { text = true }, function(out)
        vim.uv.fs_unlink(tmp)
        vim.uv.fs_unlink(tmp .. "-wal")
        local rows = {}
        if out.code == 0 then
            for line in out.stdout:gmatch("[^\n]+") do
                rows[#rows + 1] = vim.split(line, "\t")
            end
        end
        cb(rows)
    end)
end

---@param bytes string
local function decode_value(bytes)
    local raw = Draft.snappy(bytes)
    return raw and Draft.clone_string(raw)
end

---Find the newest draft for a question across all browser stores and all
---sessions. Keys carry the session id, which changes on every sign-in, so
---matching only the current one misses drafts saved in an earlier session.
---@param question_id string|integer
---@param lang string
---@param cb fun(draft?: { code: string, time: integer })
function Draft.find(question_id, lang, cb)
    local dbs = databases()
    if #dbs == 0 then
        return cb()
    end

    local pattern = ("^%s_(%%d+)_%s(.*)$"):format(question_id, vim.pesc(lang))
    local best, pending = nil, #dbs

    for _, db in ipairs(dbs) do
        query(db, function(rows)
            local codes, times = {}, {}
            for _, row in ipairs(rows) do
                local key = Draft.key(unhex(row[1]))
                local session, rest = (key or ""):match(pattern)
                if session and rest == "" then
                    codes[session] = decode_value(unhex(row[2]))
                elseif session and rest == "-updated-time" then
                    times[session] = tonumber(decode_value(unhex(row[2])) or "")
                end
            end
            for session, code in pairs(codes) do
                local time = times[session] or 0
                if code and (not best or time > best.time) then
                    best = { code = code, time = time }
                end
            end

            pending = pending - 1
            if pending == 0 then
                vim.schedule(function()
                    cb(best)
                end)
            end
        end)
    end
end

---Load the website draft into the code section when the local file is new,
---still the untouched starter code, or older than the draft. The change is a normal
---edit, so `u` undoes it.
---@param q lc.ui.Question
function Draft.apply(q)
    if not config.user.editor.load_draft then
        return
    end
    local stop_timing = require("leetcode.timings").start("draft lookup")

    Draft.find(q.q.id, q.lang, function(draft)
        stop_timing(draft and "(found)" or "(none)")
        if not (draft and q.bufnr and vim.api.nvim_buf_is_valid(q.bufnr)) then
            return
        end

        local range = q:editor_section_range("code")
        if not range.complete then
            return
        end
        local current = table.concat(range.lines, "\n", range.start_i, range.end_i)

        -- An untouched starter file always takes the draft; otherwise the newer
        -- of the two wins.
        local untouched = vim.trim(current) == vim.trim(q:snippet(true) or "")
        if q.file_existed and not untouched and draft.time / 1000 <= vim.fn.getftime(q.file:absolute()) then
            return
        end
        if vim.trim(current) == vim.trim(draft.code) then
            return
        end

        q:editor_section_replace(draft.code, "code")
        log.info(("Loaded the website draft from %s. `u` to undo"):format(os.date("%Y-%m-%d %H:%M", draft.time / 1000)))
    end)
end

return Draft
