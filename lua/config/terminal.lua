local M = {}

-- These are all window-local options. Setting them for a terminal buffer also
-- changes the window itself, and Neovim copies them into windows created from
-- it (`:split`, `:tabnew`). A file opened in that window (via `:edit` or
-- `:drop` from the shell) would inherit "no numbers, no gutter, no wrapping".
-- Track each window's editor profile and restore it when a regular buffer
-- takes over the terminal buffer.
local managed_options = {
    "number",
    "relativenumber",
    "signcolumn",
    "statuscolumn",
    "foldcolumn",
    "wrap",
    "linebreak",
    "list",
    "cursorline",
    "cursorcolumn",
}

local terminal_options = {
    number = false,
    relativenumber = false,
    signcolumn = "no",
    statuscolumn = "",
    foldcolumn = "0",
    wrap = false,
    linebreak = false,
    list = false,
    cursorline = false,
    cursorcolumn = false,
}

-- `editor_profiles` remembers each window's last editor options; `terminal_windows`
-- marks windows currently displaying a terminal buffer. The profile is recorded
-- while a normal buffer is displayed (and on BufLeave, before Neovim switches
-- to the terminal buffer and rewrites window options itself).
local editor_profiles = {}
local terminal_windows = {}

local function is_floating(win)
    return vim.api.nvim_win_get_config(win).relative ~= ""
end

local function is_terminal_buffer(buf)
    return vim.bo[buf].buftype == "terminal"
end

local function read_options(win)
    local values = {}
    for _, name in ipairs(managed_options) do
        values[name] = vim.api.nvim_get_option_value(name, { win = win })
    end
    return values
end

local function global_editor_options()
    local values = {}
    for _, name in ipairs(managed_options) do
        values[name] = vim.o[name]
    end
    return values
end

local function apply_options(win, values)
    for name, value in pairs(values) do
        vim.api.nvim_set_option_value(name, value, { win = win })
    end
end

local function save_editor_profile(win)
    if not vim.api.nvim_win_is_valid(win) or is_floating(win) then
        return
    end

    editor_profiles[win] = read_options(win)
end

local function restore_editor_options(win, buf)
    terminal_windows[win] = nil
    apply_options(win, editor_profiles[win] or global_editor_options())
    editor_profiles[win] = read_options(win)

    -- Large-file handling runs before this autocmd; its per-window tweaks were
    -- overwritten by the restore, so reapply them.
    if buf ~= nil and vim.b[buf].user_bigfile then
        pcall(function()
            require("config.bigfile").apply(buf)
        end)
    end
end

local function update_window(win, buf)
    if not vim.api.nvim_win_is_valid(win) or is_floating(win) then
        return
    end

    if is_terminal_buffer(buf) then
        terminal_windows[win] = true
        apply_options(win, terminal_options)
    elseif terminal_windows[win] then
        restore_editor_options(win, buf)
    else
        save_editor_profile(win)
    end
end

local function code_reference(mode)
    local source_buf = vim.api.nvim_get_current_buf()
    if vim.bo[source_buf].buftype ~= "" then
        return
    end

    local start_line, end_line, lines
    if mode == "n" then
        start_line = vim.api.nvim_win_get_cursor(0)[1]
        end_line = start_line
        lines = vim.api.nvim_buf_get_lines(source_buf, start_line - 1, start_line, false)
    else
        local anchor = vim.fn.getpos("v")
        local cursor = vim.fn.getpos(".")
        local start_pos, end_pos = anchor, cursor
        if anchor[2] > cursor[2] or (anchor[2] == cursor[2] and anchor[3] > cursor[3]) then
            start_pos, end_pos = cursor, anchor
        end
        start_line = start_pos[2]
        end_line = end_pos[2]
        lines = mode == "V" and vim.api.nvim_buf_get_lines(source_buf, start_line - 1, end_line, false)
            or vim.fn.getregion(start_pos, end_pos, { type = mode })
    end

    local path = vim.api.nvim_buf_get_name(source_buf)
    path = path == "" and "[No Name]" or vim.fn.fnamemodify(path, ":p")
    local location = start_line == end_line and tostring(start_line) or (start_line .. "-" .. end_line)
    local language = vim.bo[source_buf].filetype
    local reference = string.format("@%s:%s\n```%s\n%s\n```", path, location, language, table.concat(lines, "\n"))
    reference = reference:gsub("\r", ""):gsub("\27", "^[")

    local config_home = vim.env.XDG_CONFIG_HOME
    if not config_home or config_home == "" then
        config_home = vim.fn.expand("~/.config")
    end
    local command = {
        "python3",
        vim.fs.joinpath(config_home, "niri", "omp-toggle.py"),
        "--send",
        "--cwd",
        vim.fn.getcwd(),
    }
    if vim.g.omp_continue_session == false then
        command[#command + 1] = "--no-continue"
    end

    local ok, err = pcall(vim.system, command, {
        stdin = reference .. "\n",
        text = true,
    }, function(result)
        if result.code == 0 then
            return
        end
        vim.schedule(function()
            local message = vim.trim(result.stderr or "")
            if message == "" then
                message = "Reference delivery failed (exit " .. result.code .. ")"
            end
            vim.notify("OMP: " .. message, vim.log.levels.ERROR)
        end)
    end)
    if not ok then
        vim.notify("OMP: " .. tostring(err), vim.log.levels.ERROR)
    end
end

function M.setup()
    local map = vim.keymap.set

    local group = vim.api.nvim_create_augroup("UserTerminalWindow", { clear = true })

    -- The first terminal buffer of the session is the shell. Keep it around so
    -- <leader>T can switch to it like a normal buffer instead of spawning a
    -- new shell each time.
    local shell_buf
    vim.api.nvim_create_autocmd("TermOpen", {
        group = group,
        callback = function(event)
            if not shell_buf or not vim.api.nvim_buf_is_valid(shell_buf) then
                shell_buf = event.buf
            end
        end,
    })

    -- Seed the startup window while it still has editor options: `-c terminal`
    -- reuses that window and rewrites its options before TermOpen.
    update_window(vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf())

    vim.api.nvim_create_autocmd({ "TermOpen", "BufWinEnter", "BufEnter", "TermEnter" }, {
        group = group,
        callback = function(event)
            for _, win in ipairs(vim.fn.win_findbuf(event.buf)) do
                update_window(win, event.buf)
            end
        end,
    })

    -- Record editor options while the window still shows the regular buffer;
    -- Neovim rewrites some of them before TermOpen fires.
    vim.api.nvim_create_autocmd({ "BufLeave", "BufWinLeave" }, {
        group = group,
        callback = function(event)
            if is_terminal_buffer(event.buf) then
                return
            end
            for _, win in ipairs(vim.fn.win_findbuf(event.buf)) do
                save_editor_profile(win)
            end
        end,
    })

    vim.api.nvim_create_autocmd("WinNew", {
        group = group,
        callback = function(event)
            local win = vim.api.nvim_get_current_win()
            if is_floating(win) then
                return
            end

            -- The new window inherited window-local options from the window it
            -- was split from. If that window displayed a terminal buffer, carry
            -- its editor profile over so it is restored when a file is shown.
            if editor_profiles[win] == nil then
                for _, other in ipairs(vim.fn.win_findbuf(event.buf)) do
                    if other ~= win and editor_profiles[other] ~= nil then
                        editor_profiles[win] = vim.deepcopy(editor_profiles[other])
                        break
                    end
                end
            end

            update_window(win, event.buf)
        end,
    })

    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        callback = function(event)
            local win = tonumber(event.match)
            editor_profiles[win] = nil
            terminal_windows[win] = nil
        end,
    })

    map("n", "<leader>aa", function()
        code_reference("n")
    end, { desc = "Add current line to OMP" })
    map("x", "<leader>aa", function()
        code_reference(vim.fn.mode())
    end, { desc = "Add selection to OMP" })

    -- `<C-i>` and `<Tab>` are the same byte (0x09) under the legacy key
    -- encoding. An explicit `<Tab>` mapping next to each `<C-i>` mapping makes
    -- Neovim drop the alternate `<Tab>` form of the `<C-i>` mapping (see
    -- "lhsrawalt" in |maparg()|), so the two keys stay distinct: Ctrl-I
    -- toggles the terminal, Tab keeps its native meaning.
    map("n", "<Tab>", "<Tab>", { desc = "Jump forward" })
    map("t", "<Tab>", "<Tab>", { desc = "Send Tab to terminal" })

    -- Exit terminal mode without closing the terminal.
    map("t", "<C-i>", "<C-\\><C-n>", { desc = "Exit terminal mode" })

    local function find_terminal_buf()
        local fallback
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_valid(buf) and is_terminal_buffer(buf) then
                if buf == shell_buf then
                    return buf
                end
                fallback = fallback or buf
            end
        end
        return fallback
    end

    local function show_shell()
        local buf = find_terminal_buf()
        if not buf then
            vim.cmd("terminal")
            shell_buf = vim.api.nvim_get_current_buf()
            return
        end
        shell_buf = buf
        local wins = vim.fn.win_findbuf(buf)
        if #wins > 0 then
            vim.api.nvim_set_current_win(wins[1])
        else
            vim.api.nvim_win_set_buf(0, buf)
        end
        vim.cmd("startinsert")
    end

    local function leave_shell()
        local current = vim.api.nvim_get_current_buf()
        local alt = vim.fn.bufnr("#")
        local target
        if alt ~= -1 and alt ~= current and not is_terminal_buffer(alt) then
            target = alt
        else
            local best_time = -1
            for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
                if info.bufnr ~= current and not is_terminal_buffer(info.bufnr) then
                    local used = info.lastused or 0
                    if used > best_time then
                        target = info.bufnr
                        best_time = used
                    end
                end
            end
        end
        if target then
            vim.api.nvim_win_set_buf(0, target)
        end
    end

    local function focus_shell()
        if is_terminal_buffer(vim.api.nvim_get_current_buf()) then
            vim.cmd("startinsert")
        else
            show_shell()
        end
    end

    local function toggle_shell()
        if is_terminal_buffer(vim.api.nvim_get_current_buf()) then
            leave_shell()
        else
            show_shell()
        end
    end

    map("n", "<C-i>", focus_shell, { desc = "Toggle terminal" })
    -- Same toggle from the modes that matter in practice: normal, insert,
    -- visual/select, and terminal. Operator-pending is excluded: switching
    -- there would apply the pending operator to the shell buffer.
    map({ "n", "i", "v", "t" }, "<C-Q>", toggle_shell, { desc = "Toggle shell" })
end

return M
