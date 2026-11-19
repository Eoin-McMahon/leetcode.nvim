# Splits layout design

Status: approved 2026-11-19.

Plan this design belongs to: `~/.config/nvim/docs/leetcode-nvim-plan.md`.

## Goal

Make a question tab look and behave like the LeetCode website: a side pane of
tabs, a code window, a test pane, clickable Run and Submit, fast feedback, and
the website's autosaved draft on open. Everything is a real Neovim split so
`<C-w>` and Ctrl-hjkl move between panes.

Out of scope: debugging, the menu and greeter, the CN plugin.

## How the plugin works today

- `Question:create_buffer` (`lua/leetcode-ui/question.lua:93`) opens the solution
  file in a new tabpage. That window is `q.winid`. Closing it unmounts the
  question (`WinClosed` autocmd, `:297`).
- The description is a `NuiSplit` (`lua/leetcode-ui/split/description.lua`)
  drawn by `leetcode-ui.renderer`. It is already a real split.
- The console is a floating `NuiLayout` (`lua/leetcode-ui/layout/console.lua:104`)
  holding two `NuiPopup`s: `testcase` and `result`.
- The runner reaches the console only through `q.console.testcase:content()` and
  `q.console.result:handle(item)` (`lua/leetcode/runner/init.lua:45,67`), plus
  `q.console:run(submit)` from `cmd.q_run` and `cmd.q_submit`.
- Commands that touch the UI objects: `desc_toggle`, `desc_toggle_stats`,
  `console`, `info`, `restore`, `q_run`, `q_submit` (`lua/leetcode/command/init.lua`).
- Polling (`lua/leetcode/api/interpreter.lua:53`): the interval is meant to
  switch to 900 ms once the judge reports `STARTED`, but the check reads
  `item.sate`, a typo, so it is always 450 ms. Each poll is also a full HTTP
  round trip through curl, so the wait per step is 450 ms plus request time.
- `last_submit` uses the REST endpoint `/submissions/latest/?qid=&lang=`
  (`lua/leetcode/api/urls.lua:16`), not GraphQL.
- Neovim here is 0.12, so extmarks support `conceal_lines`.

## Design

### Config

New options, all defaulted so `classic` users see no change:

```lua
layout = "classic", -- "classic" | "splits"

splits = {
    preset = "website", -- "website" | "wide"
    side = { width = 0.4, tabs = { "description", "editorial", "solutions", "submissions" } },
    console = { size = 0.35 }, -- height in "website", width in "wide"
},

editor = {
    hide_tags = true, -- conceal the @leet start/end lines
},

keys = {
    -- added; nil means unmapped
    run = nil, submit = nil, toggle_tags = nil, ...
},
```

Eoin's config sets `layout = "splits"`. The `<leader>l` keymaps and the
which-key group live in his Neovim config and call `:Leet` subcommands, so the
fork only needs the subcommands, not the leader mappings.

### Modules

All new code goes under `lua/leetcode-ui/splits/`. Existing files change only at
the few branch points listed below.

| File                     | Role                                                          |
| ------------------------ | ------------------------------------------------------------- |
| `splits/init.lua`        | `SplitsLayout`: owns the windows of one question tab          |
| `splits/presets.lua`     | `website` and `wide` presets as data                          |
| `splits/pane.lua`        | One managed window: open, close, remember size, winbar        |
| `splits/side.lua`        | Side pane: tab strip and lazy per-tab buffers                 |
| `splits/console.lua`     | Testcase and result buffers with the `q.console` interface    |
| `splits/controls.lua`    | Winbar strings and the `_G._leetcode_ctl` click handlers      |
| `splits/hints.lua`       | Restore hints for hidden panes                                |
| `api/article.lua`        | Editorial, solutions and submissions queries (unit 4)         |

### Layout engine

Copied in spirit from nvim-dap-ui (`windows/layout.lua`), but every pane opens
relative to the code window with `nvim_open_win(buf, false, { split = dir, win =
code_winid })`, not editor-wide `topleft` / `botright`. That is what puts the
console under the code window only in the website preset.

Presets are data:

```lua
website = {
    { pane = "side",     split = "left",  size = "side.width" },
    { pane = "testcase", split = "below", size = "console.size", parent = "code" },
    { pane = "result",   split = "right", size = 0.5,            parent = "testcase" },
},
wide = {
    { pane = "side",     split = "left",  size = "side.width" },
    { pane = "testcase", split = "right", size = "console.size", parent = "code" },
    { pane = "result",   split = "below", size = 0.5,            parent = "testcase" },
},
```

```
website                          wide
+--------+-------------------+   +--------+------------+--------+
|        | Run  Submit       |   |        | Run Submit | test   |
| side   | code              |   | side   | code       |        |
| tabs   |                   |   | tabs   |            +--------+
|        +---------+---------+   |        |            | result |
|        | test    | result  |   |        |            |        |
+--------+---------+---------+   +--------+------------+--------+
```

- Sizes are fractions of the tab, applied after open. Before a pane closes, its
  live size is read back and kept per preset, as dap-ui does.
- Switching preset closes every managed window except the code window and opens
  the other preset. Buffers survive, so testcase edits and results stay.
- Opening a pane whose parent is hidden falls back to the code window as parent.

### Panes, hiding and hints

- Each pane (side, testcase, result) shows and hides on its own. Hiding closes the
  window. The buffer stays.
- Closing a pane with `<C-w>c` or `:q` counts as hiding it. A `WinClosed`
  autocmd on the pane's window updates state.
- Restore hints go in the code window's winbar, right of Run and Submit:
  `side hidden: <leader>ld`. The code window is never hidden, so the hint always
  has a place to show. The key text comes from a `hint_keys` option that Eoin's
  config fills in, since the fork does not know his leader mappings.
- Pane windows get `winfixbuf` so `:e` or a picker cannot replace their buffer,
  and `winfixwidth` / `winfixheight` so `<C-w>=` leaves the layout alone.

### Side pane

- One window. Each tab has its own scratch buffer, created lazily on first view
  and swapped in with `nvim_win_set_buf` (with `winfixbuf` lifted for the swap).
- The winbar is a clickable tab strip built from `%N@v:lua._leetcode_ctl.tab@`
  handlers, active tab highlighted. Keys `]t` / `[t` cycle tabs in the pane.
- Description reuses `Description`'s population and renderer, drawn into the
  side pane's buffer instead of a `NuiSplit` window. `Description` gets a small
  change so its renderer can target a buffer and window it did not create.
- Editorial, Solutions and Submissions need new GraphQL queries. Candidate names
  are `ugcArticleOfficialSolutionArticle`, `ugcArticleSolutionArticles` and
  `questionSubmissionList`. None are verified. Unit 4 starts with a script that
  checks them against the live API with the stored cookie. Editorial is premium
  for many questions; a premium-locked tab shows a one-line message.
- Solutions shows a list (title, author, votes). `<CR>` on an entry opens that
  article in the same tab buffer, `<BS>` goes back to the list. Submissions
  shows status, runtime, memory and time; `<CR>` loads that submission's code
  into the editor's code section, reusing `editor_section_replace`.

### Console

- `splits/console.lua` exposes the same interface the runner and commands use:
  `testcase:content()`, `testcase:reset()`, `testcase:append()`,
  `result:handle(item)`, `result:focus()`, `result.last_testcase`, `run(submit)`,
  `show()`, `hide()`, `toggle()`.
- Result reuses `leetcode-ui.renderer.result` as is, pointed at the result
  pane's buffer.
- Testcase copies the buffer logic from `popup/console/testcase.lua` (about 150
  lines: populate, extmarks for parameter names, snapshot). That file depends on
  `NuiPopup` throughout, and changing it would conflict with upstream. The cost
  is that upstream fixes to testcase handling must be ported by hand.
- `run(submit)` shows the result pane if hidden, but does not move focus to it,
  so the cursor stays in the code. Unlike `classic`, which focuses the result.

### Run and Submit controls

The code window's winbar:

```
 ▶ Run <leader>lr   ⇪ Submit <leader>ls      side hidden: <leader>ld
```

Built from `%@v:lua._leetcode_ctl.run@...%X`, with `_G._leetcode_ctl` holding
`run`, `submit` and `tab` functions that resolve the current question from the
clicked window's tabpage. The key labels come from `hint_keys`. While a run is
in flight, Run shows a spinner and clicks are ignored. If Eoin has a winbar
plugin, this overrides the winbar for this window only.

### Question integration

- `Question:handle_mount` branches on `config.user.layout`. For `splits`, it
  creates `SplitsLayout` and sets `self.console` to the splits console and
  `self.description` to a thin object with `toggle`, `show`, `hide` and
  `toggle_stats` that route to the side pane. The commands listed above keep
  working without edits.
- `Question:_unmount` calls `self.layout:unmount()` when present.
- `classic` keeps today's code paths unchanged.

### Tags (unit 1)

- Tag lines get an extmark with `conceal_lines = ""` in a dedicated namespace,
  so they take no screen rows. The lines stay in the buffer, so
  `editor_section_range` still finds them. `conceallevel` is set to 2 on the code
  window.
- Extmarks are placed on open and refreshed on `TextChanged` (cheap: a scan for
  two tags). `:Leet tags` toggles them per buffer.
- Risk: deleting a concealed line by accident. `dd` on the line above or below a
  hidden tag does not touch it, but a visual-line delete across it does. The
  existing missing-tag warning covers the result, and `u` undoes it.
- `match DiagnosticHint /@leet/` (`question.lua:138`) is a window-local match
  that today leaks into other buffers shown in the same window. It moves to an
  extmark highlight in the same namespace.

### Polling (unit 1)

- Fix the `sate` typo.
- Intervals: poll at 200 ms for the first 3 seconds, then 500 ms, then 1 s
  after 15 s. Options `poll = { fast = 200, slow = 500, slowest = 1000 }`.
- Before settling on numbers, time a few real runs and log per-poll latency
  with `vim.uv.hrtime` behind a debug flag. If request latency dominates, the
  interval change will help less than hoped, and that is worth knowing before
  tuning further.
- Do not go below 150 ms. LeetCode's rate limit is unknown.

### Performance (all units)

Goal: every local action finishes inside one frame, and every network action
shows feedback inside one frame.

Budgets, checked with the timing log below:

| Action                                         | Budget                     |
| ---------------------------------------------- | -------------------------- |
| Toggle a pane, switch tab, switch preset       | under 16 ms                |
| Open a question already in the disk cache      | under 50 ms to first paint |
| Click Run or Submit                            | feedback in under 16 ms    |
| Stealth toggle, overlay refresh while typing   | under 16 ms                |

What is slow today:

- `question.by_title_slug` is a synchronous curl call, so opening a question
  freezes Neovim for a full HTTP round trip (`lua/leetcode/api/question.lua:15`,
  `utils.curl` without a callback at `lua/leetcode/api/utils.lua:91`).
- The description redraws in full on every `WinResized`, which fires repeatedly
  while dragging a split.
- Every API call spawns a new curl process with a new TLS handshake. For
  polling this is likely the biggest cost per step. Not yet measured.

Rules:

1. **Never block on the network.** All API calls take a callback. Opening a
   question opens the tab and code window at once from the local file, draws the
   side pane from the disk cache if there is one, and fills in or refreshes when
   the fetch returns (stale while revalidate). A question seen for the first time
   with no local file shows a loading line until the snippet arrives.
2. **Cache questions on disk**, keyed by slug, with a timestamp. Today only the
   problem list is cached.
3. **Prefetch** Editorial, Solutions and Submissions in the background right after
   a question opens, so switching tabs never waits on the network. Refresh
   Submissions after each submit.
4. **Render once, then swap.** Each side tab and console pane keeps its buffer.
   Show and hide only open and close windows, tab switch is `nvim_win_set_buf`.
   Nothing re-renders unless its data changed.
5. **One redraw per action.** Do all window operations of a toggle or preset
   switch in one synchronous call with no `vim.schedule` in between. Neovim
   redraws once when control returns to the event loop.
6. **Debounce reflow.** Description and article redraws on resize wait about
   50 ms after the last `WinResized`, and skip if the width did not change.
7. **Cheap winbars.** Winbar strings are plain strings, rebuilt only when state
   changes, not `%!` expressions evaluated on every redraw. The run spinner
   updates at 10 fps on a timer and redraws only that winbar
   (`nvim__redraw({ win = id, winbar = true })`).
8. **Optimistic feedback.** A Run or Submit click clears the result pane and
   shows "Running" before the request leaves.
9. **Viewport-bound overlay.** The stealth renames use a decoration provider
   (`nvim_set_decoration_provider`, ephemeral extmarks in `on_win`/`on_line`), so
   the cost scales with visible lines, not file length. The treesitter tree is
   already parsed incrementally by Neovim. The name map and decoy chunks are
   computed once per question and cached.
10. **Lazy requires.** New modules are required inside the functions that use
    them, so `:Leet` startup does not grow.

Persistent connection: measured in unit 1 and rejected. A status check takes
250 to 400 ms, of which TCP and TLS setup is about 40 ms; the rest is LeetCode's
server. A keep-alive helper would save about 40 ms per poll.

Unit 1 measurements (two-sum, Run, non-premium):

| Measure                       | Before       | After        |
| ----------------------------- | ------------ | ------------ |
| Open question, cached         | blocking     | 35 ms        |
| Open question, uncached       | blocking     | non-blocking |
| Run click to result           | 2.8 to 3.1 s | about 2.75 s |

Run time is dominated by the judge (about 2.3 s). LeetCode also rejects a third
Run in quick succession ("run code too soon"), which no client change avoids.

Timing log: `debug = { timings = true }` records `vim.uv.hrtime` spans for the
actions in the table above and for each API call, and `:Leet timings` prints
them. Each unit checks its own actions against the budget before its commit.

### Highlighting (unit 1)

- New option `theme = { leetcode_colors = false }`.
- Off: every plugin group in `lua/leetcode/theme/default.lua` links to a
  standard group from the user's colorscheme. Difficulty to
  `DiagnosticOk` / `DiagnosticWarn` / `DiagnosticError`, headers to `Title`,
  inline code to `@markup.raw`, constraints and follow-up to `Comment`, links to
  `@markup.link`. The `_alt` backgrounds blend the linked fg into `Normal` bg.
- On: today's hardcoded LeetCode colors.
- The code buffer already uses the user's treesitter and colorscheme. No change
  there.

### Stealth mode (unit 6)

One toggle, `:Leet stealth`, that makes the question tab look like ordinary work
code. A second press restores the previous state.

Chrome:

- Hide side pane and console, remembering the layout.
- Clear the code window's winbar (no Run / Submit, no restore hints).
- Force tags hidden.
- Silence plugin notifications and the spinner.
- Set `titlestring` to a neutral name and expose
  `require("leetcode").stealth_name(bufnr)` so the user's statusline can show it
  instead of `1.two-sum.py`. The buffer name is not changed, since that would
  change the file it writes to.
- Optionally turn off diagnostic virtual text in the code window.

Overlay (display only, the buffer and the file are never changed, so run,
submit, save and the tag search see the real code):

- Renames: a treesitter query finds class, method, function and parameter
  identifiers in the code section. Each occurrence gets an extmark with
  `conceal = ""` over the real name and `virt_text_pos = "inline"` with the fake
  one. The fake text takes the highlight of the original capture
  (`vim.treesitter.get_captures_at_pos`), so it looks native.
- Names come from a work-domain word list (`ShipmentAllocator`,
  `resolve_batch_ids`, `order_ids`), seeded per question slug so they are stable
  across sessions. Case style follows the original (Pascal, camel, snake).
- The cursor line shows real names (`concealcursor` left empty), so editing
  works normally.
- Decoy code: `virt_lines` above and below the solution with uncalled helpers,
  imports and a dataclass from a per-language template set. Highlighted by
  parsing the decoy text with `vim.treesitter.get_string_parser` and turning
  captures into virt_text chunks.
- Comment headers from the snippet (for example
  `# Definition for singly-linked list.`) are concealed or replaced the same way.
- Refresh on `TextChanged` / `TextChangedI`, debounced about 150 ms.

Known leaks, accepted:

- Decoy lines have no line numbers, so the number column shows gaps. Option
  `stealth.decoy = true | false`; with numbers on, renaming alone may be the
  better choice.
- The cursor skips decoy lines.
- LSP hover, completion, `/` search and yanks show real names.
- It survives a glance, not a close read.

### Autosaved draft (unit 5)

Unchanged from the plan: a throwaway script first to find where the website
keeps the editor draft. If it is not reachable, fall back to `last_submit` on
open and ask Eoin before building on that.

## Unit changes

Unit 3 in the plan is too big for one window. Split it:

| Unit | Scope                                                                     |
| ---- | ------------------------------------------------------------------------- |
| 3    | Layout engine, presets, console panes, hide and hints, preset switch      |
| 4    | Side pane tabs, Editorial / Solutions / Submissions API and rendering     |
| 5    | Autosaved draft on open                                                   |
| 6    | Stealth mode: chrome toggle and disguise overlay                          |

Unit 1 also takes the `leetcode_colors` highlight toggle.

Unit 2's winbar controls depend on the code window only, so they land before the
layout engine and work in `classic` too.

## Testing

The fork has no test suite. Each unit is checked by hand in Neovim against a
real question, with a short checklist in the commit message: open, run, submit,
toggle each pane, switch preset, `<C-w>` moves, close the code window.

## Decisions

1. Testcase buffer logic is copied into the splits module, not shared with
   `popup/console/testcase.lua`.
2. Run and Submit keep the cursor in the code window.
3. The second preset is called `wide`.
