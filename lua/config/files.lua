local M = {}

local function minifiles_sync_no_confirm()
    local mini_files = require("mini.files")
    local old_confirm = vim.fn.confirm

    vim.fn.confirm = function()
        return 1
    end

    local ok, result = pcall(mini_files.synchronize)
    vim.fn.confirm = old_confirm

    if not ok then
        error(result)
    end

    return result
end

local function minifiles_close_no_confirm()
    local mini_files = require("mini.files")
    local old_confirm = vim.fn.confirm

    vim.fn.confirm = function()
        return 1
    end

    local ok, result = pcall(mini_files.close)
    vim.fn.confirm = old_confirm

    if not ok then
        error(result)
    end

    return result
end

local function minifiles_disable_preview_cursor_tracking(buf)
    if not vim.api.nvim_buf_is_valid(buf) or vim.b[buf].minifiles_preview_cursor_tracking_disabled then
        return
    end

    local ok, autocmds = pcall(vim.api.nvim_get_autocmds, { group = "MiniFiles", buffer = buf })
    if not ok then
        return
    end

    for _, autocmd in ipairs(autocmds) do
        if autocmd.desc == "Tweak cursor position" then
            pcall(vim.api.nvim_del_autocmd, autocmd.id)
        end
    end

    vim.b[buf].minifiles_preview_cursor_tracking_disabled = true
    vim.b[buf].minifiles_preview_keep_open = true
end

local function minifiles_read_preview_lines(path, max_bytes)
    local stat = vim.uv.fs_stat(path)
    if stat == nil then
        return { "-No-access" }
    end

    local fd = vim.uv.fs_open(path, "r", 438)
    if fd == nil then
        return { "-No-access" }
    end

    local data = vim.uv.fs_read(fd, math.min(stat.size, max_bytes), 0) or ""
    vim.uv.fs_close(fd)

    local lines = vim.split(data, "\n", { plain = true })
    if #lines == 0 then
        return { "" }
    end

    return lines
end

local function minifiles_patch_preview_behavior()
    local mini_files = require("mini.files")
    local _, helper = debug.getupvalue(mini_files.synchronize, 1)
    if type(helper) ~= "table" or helper._preview_behavior_patch then
        return
    end

    helper.explorer_track_lost_focus = function()
        local track = vim.schedule_wrap(function()
            if helper.vim_ui.select_active or helper.vim_ui.input_active then
                return
            end

            local buf = vim.api.nvim_get_current_buf()
            local filetype = vim.bo[buf].filetype
            if filetype == "minifiles" or filetype == "minifiles-help" or vim.b[buf].minifiles_preview_keep_open then
                return
            end

            local current_win = vim.api.nvim_get_current_win()
            minifiles_close_no_confirm()
            pcall(vim.api.nvim_set_current_win, current_win)
        end)

        helper.timers.focus:start(1000, 1000, track)
    end

    helper.buffer_update_file = function(buf, path, opts, _)
        if not vim.api.nvim_buf_is_valid(buf) then
            return
        end

        minifiles_disable_preview_cursor_tracking(buf)
        vim.bo[buf].modifiable = true
        vim.bo[buf].filetype = "minifiles"
        vim.bo[buf].swapfile = false

        local fd = vim.uv.fs_open(path, "r", 1)
        if fd == nil then
            helper.set_buflines(buf, { "-No-access" .. string.rep("-", opts.windows.width_preview) })
            return
        end

        local is_text = (vim.uv.fs_read(fd, 1024) or ""):find("\0") == nil
        vim.uv.fs_close(fd)

        local lines
        if is_text then
            local ok, read_result = pcall(vim.fn.readfile, path, "", vim.o.lines)
            lines = ok and vim.split(table.concat(read_result, "\n"), "\n") or {}
        else
            lines = minifiles_read_preview_lines(path, 1024 * 1024)
        end

        if #lines == 0 then
            lines = { "" }
        end
        helper.set_buflines(buf, lines)

        if is_text and helper.buffer_should_highlight(buf) then
            local filetype = vim.filetype.match({ buf = buf, filename = path })
            local has_lang, lang = pcall(vim.treesitter.language.get_lang, filetype)
            lang = has_lang and lang or filetype
            local has_parser, parser = pcall(vim.treesitter.get_parser, buf, lang, { error = false })
            has_parser = has_parser and parser ~= nil
            if has_parser then
                has_parser = pcall(vim.treesitter.start, buf, lang)
            end
            if not has_parser then
                vim.bo[buf].syntax = filetype
            end
        end
    end

    helper._preview_behavior_patch = true
end

local function minifiles_current_window_path(state)
    state = state or require("mini.files").get_explorer_state()
    if state == nil or type(state.windows) ~= "table" then
        return nil
    end

    local current_win = vim.api.nvim_get_current_win()
    for _, win in ipairs(state.windows) do
        if win.win_id == current_win then
            return win.path
        end
    end
end

local function minifiles_focus_path(path)
    if path == nil then
        return false
    end

    local state = require("mini.files").get_explorer_state()
    if state == nil or type(state.windows) ~= "table" then
        return false
    end

    for _, win in ipairs(state.windows) do
        if win.path == path and vim.api.nvim_win_is_valid(win.win_id) then
            vim.api.nvim_set_current_win(win.win_id)
            return true
        end
    end

    return false
end

local function minifiles_focus_navigation()
    local state = require("mini.files").get_explorer_state()
    if state == nil or type(state.branch) ~= "table" then
        return false
    end

    return minifiles_focus_path(state.branch[state.depth_focus])
end

local function minifiles_open_path(path)
    if path == nil then
        return
    end

    path = vim.fs.normalize(path)
    minifiles_close_no_confirm()
    vim.cmd.edit(vim.fn.fnameescape(path))
end

local function minifiles_is_file_preview_window()
    local state = require("mini.files").get_explorer_state()
    if state == nil or type(state.branch) ~= "table" then
        return false
    end

    local current_path = minifiles_current_window_path(state)
    if current_path ~= state.branch[state.depth_focus + 1] then
        return false
    end

    local stat = vim.uv.fs_stat(current_path)
    return stat ~= nil and stat.type == "file"
end

local function minifiles_focus_preview()
    local mini_files = require("mini.files")

    if minifiles_is_file_preview_window() then
        return
    end

    local entry = mini_files.get_fs_entry()

    if entry == nil then
        return
    end

    if entry.fs_type == "directory" then
        mini_files.go_in()
        return
    end

    if entry.fs_type ~= "file" then
        return
    end

    local state = mini_files.get_explorer_state()
    if state == nil then
        return
    end

    local branch = {}
    for i = 1, state.depth_focus do
        branch[i] = state.branch[i]
    end
    branch[state.depth_focus + 1] = entry.path

    mini_files.set_branch(branch, { depth_focus = state.depth_focus })

    vim.schedule(function()
        minifiles_focus_path(entry.path)
    end)
end

local function minifiles_enter()
    local mini_files = require("mini.files")
    local state = mini_files.get_explorer_state()
    local current_path = minifiles_current_window_path(state)
    local current_stat = current_path and vim.uv.fs_stat(current_path)

    if
        current_stat ~= nil
        and current_stat.type == "file"
        and type(state) == "table"
        and type(state.branch) == "table"
        and current_path == state.branch[state.depth_focus + 1]
    then
        minifiles_open_path(current_path)
        return
    end

    local entry = mini_files.get_fs_entry()
    if entry == nil then
        return
    end

    if entry.fs_type == "directory" then
        mini_files.go_in()
    elseif entry.fs_type == "file" then
        minifiles_open_path(entry.path)
    end
end

local function minifiles_go_back()
    local mini_files = require("mini.files")
    local state = mini_files.get_explorer_state()
    local current_path = minifiles_current_window_path(state)

    if state ~= nil and type(state.branch) == "table" and current_path == state.branch[state.depth_focus + 1] then
        minifiles_focus_navigation()
        return
    end

    mini_files.go_out()
end

local function minifiles_l()
    vim.schedule(minifiles_focus_preview)
    return "<Ignore>"
end

local function minifiles_h()
    vim.schedule(minifiles_go_back)
    return "<Ignore>"
end

local function minifiles_format_size(bytes)
    local units = { "B", "KiB", "MiB", "GiB" }
    local size = bytes or 0
    local unit = 1

    while size >= 1024 and unit < #units do
        size = size / 1024
        unit = unit + 1
    end

    if unit == 1 then
        return string.format("%d %s", size, units[unit])
    end

    return string.format("%.1f %s", size, units[unit])
end

local function minifiles_count_items(path)
    local iterator = vim.uv.fs_scandir(path)
    if iterator == nil then
        return nil
    end

    local count = 0
    while vim.uv.fs_scandir_next(iterator) ~= nil do
        count = count + 1
    end

    return count
end

local function minifiles_preview_label(path)
    local stat = path and vim.uv.fs_stat(path)
    if stat == nil then
        return "No entry"
    end

    if stat.type == "directory" then
        local count = minifiles_count_items(path)
        if count == nil then
            return "No access"
        end

        return count == 1 and "1 item" or string.format("%d items", count)
    end

    if stat.type == "file" then
        return minifiles_format_size(stat.size)
    end

    return stat.type
end

local function minifiles_update_preview_title(win_id)
    if not vim.api.nvim_win_is_valid(win_id) then
        return
    end

    local mini_files = require("mini.files")
    local state = mini_files.get_explorer_state()
    if state == nil or type(state.branch) ~= "table" or type(state.windows) ~= "table" then
        return
    end

    local preview_path = state.branch[state.depth_focus + 1]
    if preview_path == nil then
        return
    end

    for _, win in ipairs(state.windows) do
        if win.win_id == win_id and win.path == preview_path then
            local config = vim.api.nvim_win_get_config(win_id)
            config.title = " " .. minifiles_preview_label(preview_path) .. " "
            vim.api.nvim_win_set_config(win_id, config)
            return
        end
    end
end

local function minifiles_adjust_widths()
    local mini_files = require("mini.files")
    local columns = vim.o.columns
    local focus = math.min(40, math.max(28, math.floor(columns * 0.35)))
    local preview = math.max(24, columns - focus - 4)

    mini_files.config.windows.width_focus = focus
    mini_files.config.windows.width_preview = preview

    return {
        width_focus = focus,
        width_preview = preview,
    }
end

local function minifiles_update_layout(refresh)
    local mini_files = require("mini.files")
    local widths = minifiles_adjust_widths()

    if refresh and mini_files.get_explorer_state() ~= nil then
        mini_files.refresh({ windows = widths })
    end

    require("config.quick_paths").update_panel()
end

local function minifiles_schedule_layout(delay)
    vim.defer_fn(function()
        local ok, mini_files = pcall(require, "mini.files")
        if not ok or mini_files.get_explorer_state() == nil then
            return
        end

        minifiles_update_layout(true)
    end, delay or 0)
end

local function minifiles_open()
    local mini_files = require("mini.files")
    -- 如果已经打开，则聚焦到第一个窗口并返回
    if mini_files.get_explorer_state() ~= nil then
        local state = mini_files.get_explorer_state()
        if state and state.windows and #state.windows > 0 then
            vim.api.nvim_set_current_win(state.windows[1].win_id)
        end
        return
    end

    local buf = vim.api.nvim_get_current_buf()
    local path = vim.api.nvim_buf_get_name(buf)
    local is_terminal = vim.bo[buf].buftype == "terminal" or path:match("^term://") ~= nil
    if is_terminal or path == "" then
        path = vim.uv.cwd()
    else
        path = vim.fs.normalize(path)
    end

    minifiles_adjust_widths()

    if is_terminal then
        mini_files.open(path, true)
    elseif path ~= "" then
        mini_files.open(path, false)
    else
        mini_files.open(vim.uv.cwd(), true)
    end

    minifiles_update_layout(false)
    minifiles_schedule_layout(0)
    minifiles_schedule_layout(50)
end

local function minifiles_jump_quick_path(key)
    local ok, quick_paths = pcall(require, "config.quick_paths")
    if not ok then
        return
    end

    quick_paths.jump(key)
end

local function minifiles_map_quick_paths(buf)
    local ok, quick_paths = pcall(require, "config.quick_paths")
    if not ok then
        return
    end

    for _, item in ipairs(quick_paths.list()) do
        vim.keymap.set("n", item.key, function()
            minifiles_jump_quick_path(item.key)
        end, { buffer = buf, desc = "Open " .. item.label })
    end
end

local function minifiles_buffer_path(buf)
    return vim.api.nvim_buf_get_name(buf):match("^minifiles://%d+/(.*)$")
end

local function minifiles_sync_after_mode_exit()
    vim.schedule(minifiles_sync_no_confirm)
    return "<Esc>"
end

local function minifiles_enable_write_sync(buf)
    local path = minifiles_buffer_path(buf)
    local stat = path and vim.uv.fs_stat(path)
    if stat == nil or stat.type ~= "directory" then
        return
    end

    vim.bo[buf].buftype = "acwrite"

    vim.api.nvim_create_autocmd("BufWriteCmd", {
        buffer = buf,
        callback = function()
            minifiles_sync_no_confirm()
            if vim.api.nvim_buf_is_valid(buf) then
                vim.bo[buf].modified = false
            end
        end,
    })
end

local minifiles_git_ns = vim.api.nvim_create_namespace("UserMiniFilesGit")
local minifiles_git_cache = {}
local minifiles_git_ttl_ms = 2000
local minifiles_git_pending = {}

local minifiles_git_styles = {
    added = { symbol = "A", hl = "MiniFilesGitAdded" },
    modified = { symbol = "M", hl = "MiniFilesGitModified" },
    deleted = { symbol = "D", hl = "MiniFilesGitDeleted" },
    renamed = { symbol = "R", hl = "MiniFilesGitRenamed" },
    copied = { symbol = "C", hl = "MiniFilesGitRenamed" },
    untracked = { symbol = "U", hl = "MiniFilesGitUntracked" },
    unmerged = { symbol = "!", hl = "MiniFilesGitUnmerged" },
}

local minifiles_git_priority = {
    unmerged = 70,
    modified = 60,
    added = 50,
    untracked = 40,
    renamed = 30,
    copied = 20,
    deleted = 10,
}

local function minifiles_git_setup_highlights()
    local links = {
        MiniFilesGitAdded = "GitSignsAdd",
        MiniFilesGitModified = "GitSignsChange",
        MiniFilesGitDeleted = "GitSignsDelete",
        MiniFilesGitUntracked = "GitSignsAdd",
        MiniFilesGitRenamed = "DiagnosticInfo",
        MiniFilesGitUnmerged = "DiagnosticError",
    }
    for group, link in pairs(links) do
        vim.api.nvim_set_hl(0, group, { link = link, default = true })
    end
end

local function minifiles_git_normalize(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end

    return vim.fs.normalize(path)
end

local function minifiles_git_kind(xy)
    if type(xy) ~= "string" or #xy < 2 then
        return nil
    end
    if xy == "!!" then
        return nil
    end
    if xy == "??" then
        return "untracked"
    end
    if xy:find("U", 1, true) or xy == "AA" or xy == "DD" then
        return "unmerged"
    end
    if xy:find("D", 1, true) then
        return "deleted"
    end
    if xy:find("R", 1, true) then
        return "renamed"
    end
    if xy:find("C", 1, true) then
        return "copied"
    end
    if xy:find("A", 1, true) then
        return "added"
    end
    if xy:find("[MT]", 1) then
        return "modified"
    end
    return "modified"
end

local function minifiles_git_merge(a, b)
    if a == nil or a == b then
        return b
    end
    if b == nil then
        return a
    end

    local ka, kb = minifiles_git_kind(a), minifiles_git_kind(b)
    local pa = minifiles_git_priority[ka or ""] or 0
    local pb = minifiles_git_priority[kb or ""] or 0
    if pb ~= pa then
        return pb > pa and b or a
    end
    return b
end

local function minifiles_git_root(path)
    path = minifiles_git_normalize(path)
    if path == nil then
        return nil
    end

    local stat = vim.uv.fs_stat(path)
    local dir = path
    if stat and stat.type == "file" then
        dir = vim.fs.dirname(path)
    end

    local found = vim.fs.find(".git", {
        path = dir,
        upward = true,
        limit = 1,
    })
    if found[1] == nil then
        return nil
    end
    return minifiles_git_normalize(vim.fs.dirname(found[1]))
end

local function minifiles_git_style(path)
    path = minifiles_git_normalize(path)
    if path == nil then
        return nil
    end

    local best_root, cached = nil, nil
    for root, entry in pairs(minifiles_git_cache) do
        if path == root or vim.startswith(path, root .. "/") then
            if best_root == nil or #root > #best_root then
                best_root = root
                cached = entry
            end
        end
    end

    if cached == nil or cached.map == nil then
        return nil
    end

    local xy = cached.map[path]
    local kind = minifiles_git_kind(xy)
    if kind == "deleted" then
        local stat = vim.uv.fs_stat(path)
        if stat ~= nil and stat.type == "directory" then
            kind = "modified"
        end
    end
    if kind == nil then
        return nil
    end
    return minifiles_git_styles[kind]
end

local function minifiles_git_add_status(map, path, xy, root)
    path = minifiles_git_normalize(path)
    root = minifiles_git_normalize(root)
    if path == nil or root == nil or minifiles_git_kind(xy) == nil then
        return
    end

    map[path] = minifiles_git_merge(map[path], xy)

    local parent_xy = xy
    if minifiles_git_kind(xy) == "deleted" then
        parent_xy = " M"
    end

    local current = minifiles_git_normalize(vim.fs.dirname(path))
    while current ~= nil do
        map[current] = minifiles_git_merge(map[current], parent_xy)
        if current == root then
            break
        end

        local parent = minifiles_git_normalize(vim.fs.dirname(current))
        if parent == nil or parent == current then
            break
        end
        current = parent
    end
end

local function minifiles_git_parse(root, output)
    local map = {}
    if type(output) ~= "string" or output == "" then
        return map
    end

    local parts = vim.split(output, "\0", { plain = true, trimempty = true })
    local i = 1
    while i <= #parts do
        local entry = parts[i]
        i = i + 1
        if entry ~= "" and #entry >= 4 then
            local xy = entry:sub(1, 2)
            local rel = entry:sub(4)
            if xy:match("^[RC]") then
                local dest = parts[i]
                if dest ~= nil and dest ~= "" then
                    rel = dest
                    i = i + 1
                end
            end

            if rel:sub(-1) == "/" then
                rel = rel:sub(1, -2)
            end

            local abs = root .. "/" .. rel
            minifiles_git_add_status(map, abs, xy, root)
        end
    end
    return map
end

local function minifiles_git_buffers()
    local buffers = {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then
            local name = vim.api.nvim_buf_get_name(buf)
            if name:match("^minifiles://") then
                buffers[#buffers + 1] = buf
            end
        end
    end
    return buffers
end

local function minifiles_git_apply(buf)
    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end

    vim.api.nvim_buf_clear_namespace(buf, minifiles_git_ns, 0, -1)

    local mini_files = require("mini.files")
    local line_count = vim.api.nvim_buf_line_count(buf)
    for line = 1, line_count do
        local entry = mini_files.get_fs_entry(buf, line)
        local style = entry and minifiles_git_style(entry.path)
        if style ~= nil then
            local row = line - 1
            local text = vim.api.nvim_buf_get_lines(buf, row, line, false)[1] or ""
            local icon_start, name_start = text:match("^/%d+/().-()/")

            -- Override mini.files icon/name highlights (priority > 4096).
            if icon_start ~= nil and name_start ~= nil then
                vim.api.nvim_buf_set_extmark(buf, minifiles_git_ns, row, icon_start - 1, {
                    end_col = name_start - 1,
                    hl_group = style.hl,
                    priority = 5000,
                    right_gravity = false,
                })
                vim.api.nvim_buf_set_extmark(buf, minifiles_git_ns, row, name_start - 1, {
                    end_row = line,
                    end_col = 0,
                    hl_group = style.hl,
                    priority = 5000,
                    right_gravity = false,
                })
            end

            vim.api.nvim_buf_set_extmark(buf, minifiles_git_ns, row, 0, {
                virt_text = { { style.symbol, style.hl } },
                virt_text_pos = "right_align",
                hl_mode = "combine",
                priority = 50,
            })
        end
    end
end

local function minifiles_git_apply_all()
    for _, buf in ipairs(minifiles_git_buffers()) do
        minifiles_git_apply(buf)
    end
end

local function minifiles_git_highlight(fs_entry)
    local style = minifiles_git_style(fs_entry.path)
    if style ~= nil then
        return style.hl
    end
    return require("mini.files").default_highlight(fs_entry)
end

local function minifiles_git_prefix(fs_entry)
    local icon, hl = require("mini.files").default_prefix(fs_entry)
    local style = minifiles_git_style(fs_entry.path)
    if style ~= nil then
        return icon, style.hl
    end
    return icon, hl
end

local function minifiles_git_refresh_content()
    -- Prefer extmark overlays so async status still colors files without a
    -- full buffer rewrite (and without tripping pending-edit confirms).
    minifiles_git_apply_all()
end

local function minifiles_git_fetch(path, opts)
    opts = opts or {}
    local root = minifiles_git_root(path)
    if root == nil then
        return
    end

    local now = vim.uv.now()
    local cached = minifiles_git_cache[root]
    if not opts.force and cached and cached.map and (now - cached.time) < minifiles_git_ttl_ms then
        if opts.apply then
            minifiles_git_apply_all()
        end
        return
    end

    if minifiles_git_pending[root] then
        return
    end
    minifiles_git_pending[root] = true

    vim.system({
        "git",
        "-c",
        "core.quotepath=false",
        "--no-optional-locks",
        "status",
        "--porcelain=v1",
        "-z",
        "-uall",
    }, {
        cwd = root,
        text = true,
    }, function(result)
        vim.schedule(function()
            minifiles_git_pending[root] = nil
            if result.code ~= 0 then
                minifiles_git_cache[root] = { map = {}, time = vim.uv.now() }
                return
            end

            minifiles_git_cache[root] = {
                map = minifiles_git_parse(root, result.stdout or ""),
                time = vim.uv.now(),
            }
            minifiles_git_refresh_content()
        end)
    end)
end

local function minifiles_git_invalidate(path)
    if path == nil then
        minifiles_git_cache = {}
        return
    end

    local root = minifiles_git_root(path)
    if root ~= nil then
        minifiles_git_cache[root] = nil
    end
end

local function minifiles_git_on_explorer_open()
    local state = require("mini.files").get_explorer_state()
    if state == nil then
        return
    end

    local anchor = state.anchor or state.branch and state.branch[state.depth_focus]
    minifiles_git_fetch(anchor or vim.fn.getcwd(), { force = true })
end

local function minifiles_git_on_buffer_update(args)
    local buf = args.data.buf_id
    local path = minifiles_buffer_path(buf)
    if path ~= nil then
        minifiles_git_fetch(path)
    end
    minifiles_git_apply(buf)
end

local function minifiles_git_on_fs_action(args)
    local data = args.data or {}
    minifiles_git_invalidate(data.from or data.to)
    minifiles_git_invalidate(data.to)
    vim.defer_fn(function()
        local state = require("mini.files").get_explorer_state()
        if state == nil then
            return
        end
        local path = state.branch and state.branch[state.depth_focus]
        minifiles_git_fetch(path or vim.fn.getcwd(), { force = true })
    end, 50)
end

function M.setup()
    minifiles_git_setup_highlights()
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("UserMiniFilesGit", { clear = true }),
        callback = minifiles_git_setup_highlights,
    })

    require("mini.files").setup({
        content = {
            highlight = minifiles_git_highlight,
            prefix = minifiles_git_prefix,
        },
        mappings = {
            close = "",
            go_in = "",
            go_in_plus = "",
            go_out = "",
            go_out_plus = "H",
            mark_goto = "'",
            mark_set = "m",
            reset = "<BS>",
            reveal_cwd = "@",
            show_help = "g?",
            synchronize = "",
            trim_left = "<",
            trim_right = ">",
        },
        options = {
            permanent_delete = false,
        },
        windows = {
            max_number = 2,
            preview = true,
            width_focus = 34,
            width_nofocus = 18,
            width_preview = 58,
        },
    })
    minifiles_patch_preview_behavior()

    vim.keymap.set("n", "<leader>e", minifiles_open, { desc = "Files" })

    vim.api.nvim_create_autocmd("User", {
        pattern = "MiniFilesActionRename",
        callback = function(event)
            Snacks.rename.on_rename_file(event.data.from, event.data.to)
            minifiles_git_on_fs_action(event)
        end,
    })

    vim.api.nvim_create_autocmd("User", {
        pattern = {
            "MiniFilesActionCreate",
            "MiniFilesActionDelete",
            "MiniFilesActionCopy",
            "MiniFilesActionMove",
        },
        callback = minifiles_git_on_fs_action,
    })

    vim.api.nvim_create_autocmd("User", {
        pattern = "MiniFilesExplorerOpen",
        callback = minifiles_git_on_explorer_open,
    })

    vim.api.nvim_create_autocmd("User", {
        pattern = "MiniFilesBufferUpdate",
        callback = minifiles_git_on_buffer_update,
    })

    vim.api.nvim_create_autocmd("User", {
        pattern = "MiniFilesBufferCreate",
        callback = function(args)
            local buf = args.data.buf_id

            minifiles_enable_write_sync(buf)

            vim.keymap.set("n", "l", minifiles_l, { buffer = buf, expr = true, desc = "Enter" })
            vim.keymap.set("n", "<CR>", minifiles_enter, { buffer = buf, desc = "Open or enter" })
            vim.keymap.set("n", "q", minifiles_close_no_confirm, { buffer = buf, desc = "Close" })
            vim.keymap.set("n", "h", minifiles_h, { buffer = buf, expr = true, desc = "Back" })
            -- vim.keymap.set("n", "=", minifiles_sync_no_confirm, { buffer = buf, desc = "Synchronize" })
            vim.keymap.set("n", "<C-s>", minifiles_sync_no_confirm, { buffer = buf, desc = "Synchronize" })
            vim.keymap.set({ "i", "x" }, "<C-s>", minifiles_sync_after_mode_exit, {
                buffer = buf,
                expr = true,
                replace_keycodes = true,
                desc = "Synchronize",
            })
            vim.keymap.set("n", "u", function()
                vim.cmd("undo")
            end, { buffer = buf, desc = "Undo edit" })
            minifiles_map_quick_paths(buf)
        end,
    })

    vim.api.nvim_create_autocmd("User", {
        pattern = "MiniFilesWindowUpdate",
        callback = function(args)
            minifiles_update_preview_title(args.data.win_id)
            minifiles_adjust_widths()
            require("config.quick_paths").position_minifiles_window(args.data.win_id)
            require("config.quick_paths").open_panel()
        end,
    })

    vim.api.nvim_create_autocmd("User", {
        pattern = "MiniFilesExplorerClose",
        callback = function()
            require("config.quick_paths").close_panel()
        end,
    })

    vim.api.nvim_create_autocmd("VimResized", {
        group = vim.api.nvim_create_augroup("UserMiniFilesQuickAccess", { clear = true }),
        callback = function()
            local mini_files = require("mini.files")
            if mini_files.get_explorer_state() ~= nil then
                minifiles_update_layout(true)
            end
        end,
    })
end

return M
