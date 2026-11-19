---@alias lc.lang
---| "cpp"
---| "java"
---| "python"
---| "python3"
---| "c"
---| "csharp"
---| "javascript"
---| "typescript"
---| "php"
---| "swift"
---| "kotlin"
---| "dart"
---| "golang"
---| "ruby"
---| "scala"
---| "rust"
---| "racket"
---| "erlang"
---| "elixir"
---| "bash"

---@alias lc.hook
---| "enter"
---| "question_enter"
---| "leave"

---@alias lc.size
---| string
---| number
---| { width: string | number, height: string | number }

---@alias lc.position "top" | "right" | "bottom" | "left"

---@alias lc.direction "col" | "row"

---@alias lc.inject { gap?: number, imports?: (fun(default_imports: string[]): string[])|string|string[], before?: string|string[], after?: string|string[] }

---@alias lc.storage table<"cache"|"home", string>

---@alias lc.picker { provider?: "fzf-lua" | "telescope" | "snacks-picker" }

---@class lc.UserConfig
local M = {
    ---@type string
    arg = "leetcode.nvim",

    ---@type lc.lang
    lang = "cpp",

    cn = { -- leetcode.cn
        enabled = false, ---@type boolean
        translator = true, ---@type boolean
        translate_problems = true, ---@type boolean
    },

    ---@type lc.storage
    storage = {
        home = vim.fn.stdpath("data") .. "/leetcode",
        cache = vim.fn.stdpath("cache") .. "/leetcode",
    },

    ---@type table<string, boolean>
    plugins = {
        non_standalone = false,
    },

    ---@type boolean
    logging = true,

    injector = {}, ---@type table<lc.lang, lc.inject>

    cache = {
        update_interval = 60 * 60 * 24 * 7, ---@type integer 7 days
    },

    editor = {
        reset_previous_code = true, ---@type boolean
        fold_imports = true, ---@type boolean
        hide_tags = true, ---@type boolean
        ---Language servers, diagnostics, Copilot and completion in the code
        ---buffer. Off matches the website: errors show only after a run.
        assist = false, ---@type boolean
        sync_on_save = true, ---@type boolean Push the code to LeetCode's synced draft on `:w`, like Cmd-S on the website
        load_draft = true, ---@type boolean Load the website's autosaved draft (Firefox and Zen)
        controls = true, ---@type boolean Clickable Run and Submit in the winbar
    },

    ---Every LeetCode key starts with this. `<prefix>` in `mappings` and
    ---`which_key_groups` expands to it, so changing it moves all keys.
    ---@type string
    prefix = "<leader>l",

    ---Keymaps the plugin creates; every key hint in the UI reads from here, so
    ---remapping a key changes its hint too. `false` unmaps an action. Keys for
    ---the code, tests and side panels exist only in a problem's buffers.
    ---@type table<string, string|string[]|false>
    mappings = {
        -- anywhere
        menu = "<prefix>l", -- closes problems (asks if unsaved)
        list = "<prefix>pf",
        recent = "<prefix>pr",
        random = "<prefix>pR",
        daily = "<prefix>pd",
        stealth = "<prefix>z",
        key_hints = "<prefix>?",
        auth_status = "<prefix>As",
        login_cookie = "<prefix>Alc",
        login_browser = "<prefix>Alb",
        logout = "<prefix>AL",
        exit = "<prefix>q",
        -- code
        run = "<prefix>cr",
        submit = "<prefix>cs",
        debug = "<prefix>cd",
        last_submit = "<prefix>cS",
        reset_code = "<prefix>cX",
        assist = "<prefix>ca",
        -- tests
        console = "<prefix>t",
        new_case = "<prefix>Tw",
        testcase = "<prefix>To",
        reset = "<prefix>TR",
        -- side panel tabs: open, switch, or collapse when already showing
        tab_description = "<prefix>d",
        tab_editorial = "<prefix>e",
        tab_solutions = "<prefix>s",
        tab_submissions = "<prefix>u",
        -- problem-wide
        fullscreen = "<prefix>f",
        layout = "<prefix>w",
        lang = "<prefix>L",
    },

    ---which-key groups. `global` ones show everywhere, `problem` ones only in a
    ---problem's buffers, like their keys.
    which_key_groups = {
        global = {
            -- A neutral name while stealth mode is on.
            ["<prefix>"] = function()
                return vim.g.leetcode_stealth and "Lab" or "LeetCode"
            end,
            ["<prefix>p"] = "Problems",
            ["<prefix>A"] = "Account",
            ["<prefix>Al"] = "Sign in",
        },
        problem = {
            ["<prefix>c"] = "Code",
            ["<prefix>T"] = "Tests",
        },
    },

    ---Show key hints next to bar buttons. Off by default; which-key lists them.
    ---Toggle at runtime with `:Leet keys` or the `key_hints` mapping. Side panel tab letters are always shown.
    ---@type boolean
    key_hints = false,

    ---How a space leader is shown in key hints. nil uses the Nerd space icon
    ---(`󱁐 lh`) with `nerd_font`, else "SPC".
    ---@type string?
    leader_label = nil,

    ---Remember the last language chosen in a problem and open the next
    ---problem in it, across sessions. Off: always start with `lang`.
    ---@type boolean
    sticky_lang = true,

    ---Close the open question when another one is opened. Unsaved code is
    ---saved first; reopening restores it from the file or the website draft.
    ---@type boolean
    single_question = true,

    ---"classic" keeps the floating console. "splits" opens description, code,
    ---testcase and result as real windows.
    ---@type "classic"|"splits"
    layout = "classic",

    splits = {
        preset = "website", ---@type "website"|"wide"
        ---Start with the test panel collapsed to one row; running code expands it.
        collapsed = true, ---@type boolean
        ---Default sizes as fractions of the tab. website: side width and test
        ---panel height. wide: side and test panel widths. Dragged sizes are
        ---kept while the question is open.
        presets = {
            website = { side = 0.35, console = 0.35 },
            wide = { side = 0.30, console = 0.25 },
        },
    },

    console = {
        open_on_runcode = true, ---@type boolean

        dir = "row", ---@type lc.direction

        size = { ---@type lc.size
            width = "90%",
            height = "75%",
        },

        result = {
            size = "60%", ---@type lc.size
        },

        testcase = {
            virt_text = true, ---@type boolean

            size = "40%", ---@type lc.size
        },
    },

    description = {
        position = "left", ---@type lc.position

        width = "40%", ---@type lc.size

        show_stats = true, ---@type boolean
    },

    ---@type lc.picker
    picker = { provider = nil },

    hooks = {
        ---@type fun()[]
        ["enter"] = {},

        ---@type fun(question: lc.ui.Question)[]
        ["question_enter"] = {},

        ---@type fun()[]
        ["leave"] = {},
    },

    keys = {
        toggle = { "q" }, ---@type string|string[]
        confirm = { "<CR>" }, ---@type string|string[]

        reset_testcases = "r", ---@type string
        use_testcase = "U", ---@type string
        focus_testcases = "H", ---@type string
        focus_result = "L", ---@type string

        tab_next = { "<Tab>", "]t" }, ---@type string|string[] next tab in the side and test panels
        tab_prev = { "<S-Tab>", "[t" }, ---@type string|string[] previous tab in the side and test panels
        back = "<BS>", ---@type string|string[] back from an opened solution
        ---Side panel tab keys, active in the panel's read-only buffers.
        side_tabs = { description = "d", editorial = "e", solutions = "s", submissions = "u" },
    },

    ---@type lc.highlights
    theme = {},

    ---User-Agent for requests. nil uses the one of the browser the cookies come
    ---from, so Cloudflare accepts its clearance cookie.
    ---@type string?
    user_agent = nil,

    ---Use Nerd Font glyphs. `nil` follows `vim.g.have_nerd_font` and defaults to
    ---true; false switches every icon to plain Unicode.
    ---@type boolean?
    nerd_font = nil,

    ---Use LeetCode's own difficulty and calendar colors instead of colors
    ---derived from the active colorscheme.
    ---@type boolean
    leetcode_colors = false,

    ---@type boolean
    image_support = false,

    debugger = {
        ---Python with debugpy. nil tries Mason's debugpy, then `python3`.
        python = nil, ---@type string?
    },

    stealth = {
        ---Show uncalled work-style code around the solution. Virtual lines have
        ---no line numbers, so turn this off if the gaps give it away.
        decoy = true, ---@type boolean
    },

    ---Result polling after Run and Submit, in milliseconds. LeetCode's rate
    ---limit is unknown, so keep `fast` at 150 or above.
    poll = {
        fast = 200, ---@type integer
        fast_for = 3000, ---@type integer
        slow = 500, ---@type integer
        slow_for = 15000, ---@type integer
        slowest = 1000, ---@type integer
    },

    ---Record how long UI actions and API calls take. `:Leet timings` shows them.
    ---@type boolean
    debug_timings = false,
}

return M
