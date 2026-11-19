local log = require("leetcode.logger")
local arguments = require("leetcode.command.arguments")
local config = require("leetcode.config")
local event = require("nui.utils.autocmd").event
local api = vim.api

local t = require("leetcode.translator")

---@class lc.Commands
local cmd = {}

---@param old_name string
---@param new_name string
function cmd.deprecate(old_name, new_name)
    log.warn(("`%s` is deprecated, use `%s` instead."):format(old_name, new_name))
end

function cmd.cache_update()
    require("leetcode.utils").auth_guard()

    require("leetcode.cache").update()
end

---@param options table<string, string[]>
function cmd.problems(options)
    require("leetcode.utils").auth_guard()

    local p = require("leetcode.cache.problemlist").get()
    local picker = require("leetcode.picker")
    picker.question(p, options)
end

---Close every open problem and show the menu. Unsaved problems are listed in
---one prompt: save them, discard them, or cancel.
function cmd.home()
    local questions = vim.list_slice(_Lc_state.questions)
    local unsaved = vim.tbl_filter(function(q)
        return q.bufnr and api.nvim_buf_is_valid(q.bufnr) and vim.bo[q.bufnr].modified
    end, questions)
    if #unsaved > 0 then
        local names = table.concat(vim.tbl_map(function(q)
            return ("%s. %s"):format(q.q.frontend_id, q.q.title)
        end, unsaved), ", ")
        local choice = vim.fn.confirm(("Unsaved changes in %s."):format(names), "&Save\n&Discard\n&Cancel", 3)
        if choice == 3 or choice == 0 then
            return
        end
        for _, q in ipairs(unsaved) do
            if choice == 1 then
                api.nvim_buf_call(q.bufnr, function()
                    pcall(vim.cmd, "silent write")
                end)
            else
                vim.bo[q.bufnr].modified = false
            end
        end
    end
    for _, q in ipairs(questions) do
        if q.winid and api.nvim_win_is_valid(q.winid) then
            local tabp = api.nvim_win_get_tabpage(q.winid)
            if #api.nvim_list_tabpages() > 1 then
                pcall(vim.cmd.tabclose, api.nvim_tabpage_get_number(tabp))
            else
                q:unmount()
            end
        end
    end
    cmd.menu()
end

function cmd.recent()
    require("leetcode.utils").auth_guard()
    local questions = require("leetcode.cache.recent").questions()
    if #questions == 0 then
        return log.info("No recent problems yet")
    end
    require("leetcode.picker").question(questions, {})
end

---@param str string
---@return boolean success
local function sign_in(str)
    local err = require("leetcode.cache.cookie").set(str)

    if not err then
        log.info("Sign-in successful")
        cmd.start_user_session()
    else
        log.error("Sign-in failed: " .. err)
    end

    return not err
end

---@param cb? function
function cmd.cookie_prompt(cb)
    local popup_options = {
        relative = "editor",
        position = {
            row = "50%",
            col = "50%",
        },
        size = 40,
        border = {
            style = "rounded",
            text = {
                top = (" %s "):format(t("Enter cookie")),
                top_align = "left",
            },
        },
        win_options = {
            winhighlight = "Normal:Normal",
        },
    }

    local NuiInput = require("nui.input")
    local input = NuiInput(popup_options, {
        prompt = " 󰆘 ",
        on_submit = function(value)
            pcall(cb, sign_in(value))
        end,
    })

    input:mount()

    local keys = config.user.keys
    input:map("n", keys.toggle, function()
        input:unmount()
    end)
    input:on(event.BufLeave, function()
        input:unmount()
    end)
end

local browser_timer

---Sign in with the session of a browser signed in to leetcode. If there is none, opens the
---login page in a supported browser and waits for one; falls back to the cookie prompt.
---@param cb? function
function cmd.browser_sign_in(cb)
    local ok, browser = pcall(require, "leetcode.cache.browser") -- needs LuaJIT's ffi
    local app = ok and browser.app()
    if not app then
        return cmd.cookie_prompt(cb)
    end
    if browser_timer then
        return log.info("Still waiting for you to sign in in the browser")
    end

    -- if the session on disk is rejected it's stale: wait for a different one
    local stale = browser.get()
    if stale and sign_in(stale) then
        return pcall(cb, true)
    end

    -- not the default browser, it may be one we can't read
    browser.open(app, ("https://leetcode.%s/accounts/login/"):format(config.domain))
    -- Chromium-based browsers write new cookies to disk only every ~30s
    local spinner = require("leetcode.logger.spinner"):start(
        ("Waiting for you to sign in to leetcode in %s, this can take ~30s"):format(app),
        "points"
    )

    local tries = 0 -- 3s apart, gives up after 3min
    browser_timer = vim.loop.new_timer()
    browser_timer:start(
        3000,
        3000,
        vim.schedule_wrap(function()
            if not browser_timer then
                return
            end
            tries = tries + 1
            local str = browser.get()
            str = str ~= stale and str or nil
            if str or tries == 60 then
                browser_timer:close()
                browser_timer = nil
                if str then
                    spinner:success(("Found your leetcode session in %s"):format(app))
                    pcall(cb, sign_in(str))
                else
                    spinner:error("No leetcode session found in any browser")
                    cmd.cookie_prompt(cb)
                end
            end
        end)
    )
end

function cmd.sign_out()
    cmd.menu()

    log.warn("You're now signed out")
    cmd.delete_cookie()
    cmd.set_menu_page("signin")
end

---Sign out
function cmd.delete_cookie()
    config.auth = {}
    local cookie = require("leetcode.cache.cookie")
    cookie.delete()
end

cmd.q_close_all = function()
    local utils = require("leetcode.utils")
    local qs = utils.question_tabs()

    for _, tabp in ipairs(qs) do
        tabp.question:unmount()
    end
end

function cmd.exit()
    local leetcode = require("leetcode")
    leetcode.stop()
end

cmd.expire = vim.schedule_wrap(function()
    local tabp = api.nvim_get_current_tabpage()
    cmd.menu()

    cmd.cookie_prompt(function(success)
        if success then
            if api.nvim_tabpage_is_valid(tabp) then
                api.nvim_set_current_tabpage(tabp)
            end
            log.info("Successful re-login")
        else
            cmd.sign_out()
        end
    end)
end)

function cmd.qot()
    require("leetcode.utils").auth_guard()

    local problems = require("leetcode.api.problems")
    local Question = require("leetcode-ui.question")

    problems.question_of_today(function(qot, err)
        if err then
            return log.err(err)
        end
        local problemlist = require("leetcode.cache.problemlist")
        Question(problemlist.get_by_title_slug(qot.title_slug)):mount()
    end)
end

function cmd.random_question(opts)
    require("leetcode.utils").auth_guard()

    local problems = require("leetcode.cache.problemlist")
    local question = require("leetcode.api.question")

    if opts and opts.difficulty then
        opts.difficulty = opts.difficulty[1]:upper()
    end
    if opts and opts.status then
        opts.status = ({
            ac = "AC",
            notac = "TRIED",
            todo = "NOT_STARTED",
        })[opts.status[1]]
    end

    local q, err = question.random(opts)
    if err then
        return log.err(err)
    end

    local item = problems.get_by_title_slug(q.title_slug) or {}
    local Question = require("leetcode-ui.question")
    Question(item):mount()
end

function cmd.start_with_cmd()
    local leetcode = require("leetcode")
    if leetcode.start(false) then
        cmd.menu()
    end
end

function cmd.menu()
    local winid, bufnr = _Lc_state.menu.winid, _Lc_state.menu.bufnr
    local ok, tabp = pcall(api.nvim_win_get_tabpage, winid)
    local ui = require("leetcode-ui.utils")

    if ok then
        api.nvim_set_current_tabpage(tabp)
        ui.win_set_buf(winid, bufnr)
    else
        _Lc_state.menu:remount()
    end
end

function cmd.yank()
    local utils = require("leetcode.utils")
    local q = utils.curr_question()
    if not q then
        return
    end

    q:editor_yank_code()
end

---@param page lc-menu.page
function cmd.set_menu_page(page)
    _Lc_state.menu:set_page(page)
end

function cmd.start_user_session() --
    cmd.set_menu_page("menu")
    config.stats.update()
end

function cmd.question_tabs()
    local picker = require("leetcode.picker")
    picker.tabs()
end

function cmd.change_lang()
    local utils = require("leetcode.utils")
    local q = utils.curr_question()
    if q then
        local picker = require("leetcode.picker")
        picker.language(q)
    end
end

function cmd.desc_toggle()
    local utils = require("leetcode.utils")
    local q = utils.curr_question()
    if q then
        q.description:toggle()
    end
end

function cmd.desc_toggle_stats()
    local utils = require("leetcode.utils")
    local q = utils.curr_question()
    if q then
        q.description:toggle_stats()
    end
end

function cmd.console()
    local utils = require("leetcode.utils")
    local q = utils.curr_question()
    if q then
        q.console:toggle()
    end
end

function cmd.info()
    local utils = require("leetcode.utils")
    local q = utils.curr_question()
    if q then
        q.info:toggle()
    end
end

function cmd.hints()
    -- cmd.deprecate("Leet hints", "Leet info")
    cmd.info()
end

function cmd.q_run()
    local utils = require("leetcode.utils")
    utils.auth_guard()
    local q = utils.curr_question()
    if q then
        q.console:run()
    end
end

function cmd.q_submit()
    local utils = require("leetcode.utils")
    utils.auth_guard()
    local q = utils.curr_question()
    if q then
        q.console:run(true)
    end
end

function cmd.ui_skills()
    if config.is_cn then
        return
    end
    local skills = require("leetcode-ui.popup.skills")
    skills:show()
end

function cmd.ui_languages()
    local languages = require("leetcode-ui.popup.languages")
    languages:show()
end

function cmd.open()
    local utils = require("leetcode.utils")
    utils.auth_guard()
    local q = utils.curr_question()

    if q then
        if vim.ui.open then
            vim.ui.open(q.cache.link)
        else
            local command
            local os_name = vim.loop.os_uname().sysname

            if os_name == "Linux" then
                command = string.format("xdg-open '%s'", q.cache.link)
            elseif os_name == "Darwin" then
                command = string.format("open '%s'", q.cache.link)
            else
                -- Fallback to Windows if uname is not available or does not match Linux/Darwin.
                command = string.format("start \"\" \"%s\"", q.cache.link)
            end

            vim.fn.jobstart(command, { detach = true })
        end
    end
end

function cmd.reset()
    local utils = require("leetcode.utils")
    utils.auth_guard()
    local q = utils.curr_question()
    if not q then
        return
    end

    if vim.fn.confirm("Clear your code back to the starter code?", "&Clear\n&Cancel", 2) ~= 1 then
        return
    end
    q:editor_reset_code()
end

function cmd.last_submit()
    local utils = require("leetcode.utils")
    utils.auth_guard()
    local q = utils.curr_question()
    if not q then
        return
    end

    local question_api = require("leetcode.api.question")
    question_api.latest_submission(q.q.id, q.lang, function(res, err) --
        if err then
            if err.status == 404 then
                log.error("You haven't submitted any code!")
            else
                log.err(err)
            end

            return
        end

        if type(res) == "table" and res.code then
            ---@type string
            local lines = res.code
            q:editor_section_replace(lines, "code")
        else
            log.error("Something went wrong")
        end
    end)
end

function cmd.restore()
    local utils = require("leetcode.utils")
    local ui = require("leetcode-ui.utils")
    local q = utils.curr_question()
    if not q then
        return
    end

    if
        (q.winid and api.nvim_win_is_valid(q.winid))
        and (q.bufnr and api.nvim_buf_is_valid(q.bufnr))
    then
        ui.win_set_buf(q.winid, q.bufnr)
    end

    q.description:show()
    local winid, bufnr = q.description.winid, q.description.bufnr

    if
        (winid and api.nvim_win_is_valid(winid)) --
        and (bufnr and api.nvim_buf_is_valid(bufnr))
    then
        ui.win_set_buf(q.winid, q.bufnr)
    end
end

function cmd.inject()
    local utils = require("leetcode.utils")
    local q = utils.curr_question()
    if not q then
        return
    end

    if q.bufnr and api.nvim_buf_is_valid(q.bufnr) then
        local range = q:editor_section_range("code")

        if not range:is_valid_or_log() then
            return
        end

        local lines = table.concat(range.lines, "\n", range.start_i, range.end_i)

        q:editor_reset()
        q:editor_section_replace(lines, "code")
    end
end

function cmd.fold()
    local utils = require("leetcode.utils")
    local q = utils.curr_question()
    if not q then
        return
    end

    q:editor_fold_imports(true)
end

---@param name lc.splits.PaneName
function cmd.pane_toggle(name)
    return function()
        local q = require("leetcode.utils").curr_question()
        if not q then
            return
        end
        if not q.layout then
            return log.warn("Pane toggles need `layout = \"splits\"`")
        end
        if name == "console" then
            return q.console:toggle()
        end
        if name == "side" then
            return q.layout.side:toggle()
        end
        if name == "testcase" or name == "result" then
            if q.layout:is_visible("console") and q.console.active == name then
                return q.layout:hide("console")
            end
            return q.console:select(name)
        end
        q.layout:toggle(name)
    end
end

function cmd.testcase_reset()
    local q = require("leetcode.utils").curr_question()
    if q then
        q.console.testcase:reset()
    end
end

---@param name "side"|"tests"|"code"
function cmd.fullscreen(name)
    return function()
        local q = require("leetcode.utils").curr_question()
        if not q then
            return
        end
        if name == "code" then
            return require("leetcode-ui.controls").fullscreen_code(q)
        end
        if q.layout then
            q.layout:fullscreen(name == "tests" and "console" or "side")
        end
    end
end

function cmd.testcase_new()
    local q = require("leetcode.utils").curr_question()
    if q and q.layout then
        q.console.testcase:add_custom()
    end
end

function cmd.testcase_delete()
    local q = require("leetcode.utils").curr_question()
    if q and q.layout then
        q.console.testcase:delete_case(vim.api.nvim_win_get_cursor(0)[1])
    end
end

function cmd.testcase_add_failed()
    local q = require("leetcode.utils").curr_question()
    if q then
        q.console:use_testcase()
    end
end

function cmd.layout_cycle()
    local q = require("leetcode.utils").curr_question()
    if not q then
        return
    end
    if not q.layout then
        return log.warn("Layout presets need `layout = \"splits\"`")
    end
    q.layout:set_preset()
end

function cmd.debug()
    local q = require("leetcode.utils").curr_question()
    if q then
        require("leetcode.debug").toggle(q)
    end
end

function cmd.stealth_toggle()
    require("leetcode-ui.stealth").toggle()
end

function cmd.tags_toggle()
    local q = require("leetcode.utils").curr_question()
    if q then
        local tags = require("leetcode-ui.tags")
        tags.toggle(q.bufnr)
        if not tags.hidden(q.bufnr) and config.user.editor.fold_imports then
            q:editor_fold_imports(false)
        end
    end
end

function cmd.timings()
    require("leetcode.timings").show()
end

function cmd.get_active_session()
    local sessions = config.sessions.all
    return vim.tbl_filter(function(s)
        return s.is_active
    end, sessions)[1]
end

function cmd.get_session_by_name(name)
    local sessions = config.sessions.all

    name = name:lower()
    if name == config.sessions.default then
        name = ""
    end
    return vim.tbl_filter(function(s)
        return s.name:lower() == name
    end, sessions)[1]
end

function cmd.change_session(opts)
    require("leetcode.utils").auth_guard()

    local name = opts.name[1] or config.sessions.default

    local session = cmd.get_session_by_name(name)
    if not session then
        return log.error("Session not found")
    end

    local stats_api = require("leetcode.api.statistics")
    stats_api.change_session(session.id, function(_, err)
        if err then
            return log.err(err)
        end
        log.info(("Session changed to `%s`"):format(name))
        config.stats.update()
    end)
end

function cmd.create_session(opts)
    require("leetcode.utils").auth_guard()

    local name = opts.name[1]
    if not name then
        return log.error("Session name not provided")
    end

    local stats_api = require("leetcode.api.statistics")
    stats_api.create_session(name, function(_, err)
        if err then
            return log.err(err)
        end
        log.info(("session `%s` created"):format(name))
    end)
end

function cmd.update_sessions()
    require("leetcode.utils").auth_guard()

    config.stats.update_sessions()
end

function cmd.fix()
    require("leetcode.cache.cookie").delete()
    require("leetcode.cache.problemlist").delete()
    vim.cmd("qa!")
end

---@return string[], string[]
function cmd.parse(args)
    local parts = vim.split(vim.trim(args), "%s+")
    if args:sub(-1) == " " then
        parts[#parts + 1] = ""
    end

    local options = {}
    for _, part in ipairs(parts) do
        local opt = part:match("(.-)=.-")
        if opt then
            table.insert(options, opt)
        end
    end

    return parts, options
end

---@param tbl table
local function cmds_keys(tbl)
    return vim.tbl_filter(function(key)
        if type(key) ~= "string" then
            return false
        end
        if key:sub(1, 1) == "_" then
            return false
        end
        if tbl[key]._private then
            return false
        end

        return true
    end, vim.tbl_keys(tbl))
end

---@param _ string
---@param line string
---
---@return string[]
function cmd.complete(_, line)
    local args, options = cmd.parse(line:gsub("Leet%s", ""))
    return cmd.rec_complete(args, options, cmd.commands)
end

---@param args string[]
---@param options string[]
---@param cmds table<string,any>
---
---@return string[]
function cmd.rec_complete(args, options, cmds)
    if not cmds or vim.tbl_isempty(args) then
        return {}
    end

    if not cmds._args and cmds[args[1]] then
        return cmd.rec_complete(args, options, cmds[table.remove(args, 1)])
    end

    local txt, keys = args[#args], cmds_keys(cmds)
    if cmds._args then
        local option_keys = cmds_keys(cmds._args)
        option_keys = vim.tbl_filter(function(key)
            return not vim.tbl_contains(options, key)
        end, option_keys)
        option_keys = vim.tbl_map(function(key)
            return ("%s="):format(key)
        end, option_keys)
        keys = vim.tbl_extend("force", keys, option_keys)

        local s = vim.split(txt, "=")
        if s[2] and cmds._args[s[1]] then
            local vals = vim.split(s[2], ",")
            return vim.tbl_filter(function(key)
                return not vim.tbl_contains(vals, key) and key:find(vals[#vals], 1, true) == 1
            end, cmds._args[s[1]])
        end
    end

    return vim.tbl_filter(function(key)
        return not vim.tbl_contains(args, key) and key:find(txt, 1, true) == 1
    end, keys)
end

function cmd.exec(args)
    local cmds = cmd.commands

    local options = vim.empty_dict()
    for s in vim.gsplit(args.args:lower(), "%s+", { trimempty = true }) do
        local opt = vim.split(s, "=")

        if opt[2] then
            options[opt[1]] = vim.split(opt[2], ",", { trimempty = true })
        elseif cmds then
            cmds = cmds[s]
        else
            break
        end
    end

    if cmds and type(cmds[1]) == "function" then
        cmds[1](options) ---@diagnostic disable-line
    else
        log.error(("Invalid command: `%s %s`"):format(args.name, args.args))
    end
end

---Actions that `config.user.mappings` can bind, as `:Leet` arguments.
cmd.mapping_actions = {
    menu = { "home", "LeetCode menu (closes problems)" },
    run = { "run", "Run tests" },
    submit = { "submit", "Submit" },
    debug = { "debug", "Open in debugger" },
    side = { "pane side", "Toggle description panel" },
    console = { "pane console", "Toggle tests" },
    testcase = { "pane testcase", "Open tests" },
    result = { "pane result", "Results tab" },
    reset = { "testcase reset", "Reset test cases" },
    add_case = { "testcase add", "Add failed case" },
    new_case = { "testcase new", "Write test case" },
    delete_case = { "testcase delete", "Delete test case" },
    layout = { "layout", "Toggle layout" },
    tags = { "tags", "Toggle tags" },
    stealth = { "stealth", "Toggle stealth" },
    info = { "info", "Info" },
    list = { "list", "Pick problem" },
    recent = { "recent", "Recent problems" },
    daily = { "daily", "Daily problem" },
    random = { "random", "Random problem" },
    lang = { "lang", "Change language" },
    last_submit = { "last_submit", "Load last submission" },
    reset_code = { "reset", "Clear code" },
    yank = { "yank", "Yank code" },
    exit = { "exit", "Exit" },
    signin = { "cookie browser", "Sign in again" },
    key_hints = { "keys", "Toggle key hints" },
    side_fullscreen = { "fullscreen side", "Fullscreen description panel" },
    tests_fullscreen = { "fullscreen tests", "Fullscreen tests" },
    code_fullscreen = { "fullscreen code", "Fullscreen code" },
}

---Actions that only make sense inside a problem. They are mapped buffer-local
---in the problem's buffers, so they exist only there.
cmd.problem_actions = {
    run = true,
    submit = true,
    debug = true,
    lang = true,
    code_fullscreen = true,
    reset_code = true,
    last_submit = true,
    console = true,
    testcase = true,
    result = true,
    new_case = true,
    reset = true,
    add_case = true,
    tests_fullscreen = true,
    side = true,
    side_fullscreen = true,
    layout = true,
}

---A mapping may list several keys for one action (run is both "run tests"
---and "run" in the code group). Hints show the first.
---@param name string
---@param opts table
local function set_mapping(name, opts)
    local lhs = (config.user.mappings or {})[name]
    local action = cmd.mapping_actions[name]
    if not (lhs and action) then
        return
    end
    for _, key in ipairs(type(lhs) == "table" and lhs or { lhs }) do
        vim.keymap.set("n", key, function()
            vim.cmd("Leet " .. action[1])
        end, vim.tbl_extend("force", { desc = action[2] }, opts))
    end

    -- Give which-key the same icon the UI uses, instead of its guess.
    local icon = config.user.nerd_font and config.icons.actions[name]
    local ok, wk = pcall(require, "which-key")
    if icon and ok and wk.add then
        local spec = {}
        for _, key in ipairs(type(lhs) == "table" and lhs or { lhs }) do
            table.insert(spec, { key, icon = { icon = icon, hl = "leetcode_menu_icon" }, buffer = opts.buffer })
        end
        pcall(wk.add, spec)
    end
end

---Global mappings: the ones that make sense anywhere.
function cmd.setup_mappings()
    for name in pairs(config.user.mappings or {}) do
        if not cmd.problem_actions[name] then
            set_mapping(name, {})
        end
    end
end

---Problem mappings, buffer-local to one of a problem's buffers. which-key
---groups for them (`which_key_groups`) are registered on the same buffers, so
---they only show inside a problem.
---@param bufnr integer
function cmd.problem_mappings(bufnr)
    for name in pairs(cmd.problem_actions) do
        set_mapping(name, { buffer = bufnr })
    end
    local groups = config.user.which_key_groups or {}
    local ok, wk = pcall(require, "which-key")
    if ok and next(groups) and wk.add then
        local spec = {}
        for lhs, name in pairs(groups) do
            table.insert(spec, { lhs, group = name, buffer = bufnr })
        end
        pcall(wk.add, spec)
    end
end

function cmd.setup()
    api.nvim_create_user_command("Leet", cmd.exec, {
        bar = true,
        bang = true,
        nargs = "?",
        desc = "Leet",
        complete = cmd.complete,
    })
end

cmd.commands = {
    cmd.menu,

    menu = { cmd.menu },
    exit = { cmd.exit },
    console = { cmd.console },
    info = { cmd.info },
    hints = { cmd.hints },
    tabs = { cmd.question_tabs },
    lang = { cmd.change_lang },
    run = { cmd.q_run },
    test = { cmd.q_run },
    submit = { cmd.q_submit },
    daily = { cmd.qot },
    yank = { cmd.yank },
    open = { cmd.open },
    reset = { cmd.reset },
    last_submit = { cmd.last_submit },
    restore = { cmd.restore },
    inject = { cmd.inject },
    fold = { cmd.fold },
    timings = { cmd.timings },
    tags = { cmd.tags_toggle },
    stealth = { cmd.stealth_toggle },
    home = { cmd.home },
    fullscreen = {
        side = { cmd.fullscreen("side") },
        tests = { cmd.fullscreen("tests") },
        code = { cmd.fullscreen("code") },
    },
    keys = {
        function()
            require("leetcode-ui.controls").toggle_key_hints()
        end,
    },
    debug = { cmd.debug },
    layout = { cmd.layout_cycle },
    pane = {
        side = { cmd.pane_toggle("side") },
        console = { cmd.pane_toggle("console") },
        testcase = { cmd.pane_toggle("testcase") },
        result = { cmd.pane_toggle("result") },
    },
    testcase = {
        reset = { cmd.testcase_reset },
        add = { cmd.testcase_add_failed },
        new = { cmd.testcase_new },
        delete = { cmd.testcase_delete },
    },
    -- session = {
    --     change = {
    --         cmd.change_session,
    --         _args = arguments.session_change,
    --     },
    --     create = {
    --         cmd.create_session,
    --         _args = arguments.session_create,
    --     },
    --     update = { cmd.update_sessions },
    -- },
    recent = { cmd.recent },
    list = {
        cmd.problems,
        _args = arguments.list,
    },
    random = {
        cmd.random_question,
        _args = arguments.random,
    },
    desc = {
        cmd.desc_toggle,

        stats = { cmd.desc_toggle_stats },
        toggle = { cmd.desc_toggle },
    },
    cookie = {
        update = { cmd.cookie_prompt },
        browser = { cmd.browser_sign_in },
        delete = { cmd.sign_out },
    },
    cache = {
        update = { cmd.cache_update },
    },
    fix = {
        cmd.fix,
        _private = true,
    },
}

return cmd
