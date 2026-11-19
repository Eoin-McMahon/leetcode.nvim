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
        sync_on_save = true, ---@type boolean Push the code to LeetCode's synced draft on `:w`, like Cmd-S on the website
        load_draft = true, ---@type boolean Load the website's autosaved draft (Firefox and Zen)
        controls = true, ---@type boolean Clickable Run and Submit in the winbar
    },

    ---Global keymaps, created by the plugin when it starts. Every key hint in
    ---the UI is read from here, so remapping a key here changes its hint too.
    ---`false` or nil leaves an action unmapped. Actions: menu, run, submit,
    ---debug, side, console, testcase, result, reset, add_case,
    ---layout, tags, stealth, info, list, daily, random, lang, last_submit,
    ---reset_code, yank, exit, signin.
    ---@type table<string, string|false>
    mappings = {},

    ---How a space leader is shown in key hints. nil uses the Nerd space icon
    ---(`󱁐 lh`) with `nerd_font`, else "SPC".
    ---@type string?
    leader_label = nil,

    ---"classic" keeps the floating console. "splits" opens description, code,
    ---testcase and result as real windows.
    ---@type "classic"|"splits"
    layout = "classic",

    splits = {
        preset = "website", ---@type "website"|"wide"
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

        tab_next = "]t", ---@type string|string[] next side pane tab
        tab_prev = "[t", ---@type string|string[] previous side pane tab
        back = "<BS>", ---@type string|string[] back from an opened solution
        ---Side panel tab keys, active in the panel's read-only buffers.
        side_tabs = { description = "d", editorial = "e", solutions = "s", submissions = "u" },
    },

    ---@type lc.highlights
    theme = {},

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
