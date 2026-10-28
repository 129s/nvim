local M = {}

local digit_keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" }
local panel = {
    buf = nil,
    win = nil,
}

local function normalize(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end

    path = vim.fn.expand(path)
    local ok, normalized = pcall(vim.fs.normalize, path)
    if ok and type(normalized) == "string" and normalized ~= "" then
        path = normalized
    end

    return path
end

local function dedupe_key(path)
    local realpath = vim.uv.fs_realpath(path) or path
    realpath = normalize(realpath) or realpath
    return realpath
end

local function add_path(paths, seen, label, path, short_label, icon)
    if #paths >= #digit_keys then
        return
    end

    path = normalize(path)
    local stat = path and vim.uv.fs_stat(path)
    if stat == nil or stat.type ~= "directory" then
        return
    end

    local key = dedupe_key(path)
    if seen[key] then
        return
    end

    seen[key] = true
    table.insert(paths, {
        label = label,
        short_label = short_label or label,
        path = path,
        icon = icon or "󰉋",
    })
end

function M.list()
    local paths = {}
    local seen = {}

    add_path(paths, seen, "Home", "~", "Home", "󰋜")
    add_path(paths, seen, "Nvim", vim.fn.stdpath("config"), "Nvim", "")
    add_path(paths, seen, "Projects", "~/Projects", "Proj", "󰉋")
    add_path(paths, seen, "Config", vim.env.XDG_CONFIG_HOME or "~/.config", "Cfg", "󰉌")
    add_path(paths, seen, "Data", vim.fn.stdpath("data"), "Data", "󰉌")
    add_path(paths, seen, "Cache", vim.fn.stdpath("cache"), "Cache", "󰉌")
    add_path(paths, seen, "Mounts", "/mnt", "Mnt", "󰋊")
    add_path(paths, seen, "Media", "/run/media/" .. vim.fn.fnamemodify(vim.uv.os_homedir(), ":t"), "Media", "󰋊")
    add_path(paths, seen, "/", "/", "/", "󰋊")

    for index, item in ipairs(paths) do
        item.index = index
        item.key = digit_keys[index]
    end

    return paths
end

function M.by_key(key)
    key = tostring(key)
    for _, item in ipairs(M.list()) do
        if item.key == key then
            return item
        end
    end
end

local function same_path(left, right)
    left = normalize(left)
    right = normalize(right)
    if left == nil or right == nil then
        return false
    end

    return left == right
end

local function focus_minifiles_path(path)
    local ok, mini_files = pcall(require, "mini.files")
    if not ok then
        return
    end

    local state = mini_files.get_explorer_state()
    if state == nil or type(state.windows) ~= "table" then
        return
    end

    for _, win in ipairs(state.windows) do
        if same_path(win.path, path) and vim.api.nvim_win_is_valid(win.win_id) then
            vim.api.nvim_set_current_win(win.win_id)
            return
        end
    end
end

function M.open_in_minifiles(path)
    path = normalize(path)
    local stat = path and vim.uv.fs_stat(path)
    if stat == nil or stat.type ~= "directory" then
        vim.notify("Quick path is not available: " .. tostring(path), vim.log.levels.WARN)
        return false
    end

    local mini_files = require("mini.files")
    if mini_files.get_explorer_state() == nil then
        mini_files.open(path, false)
    else
        mini_files.set_branch({ path }, { depth_focus = 1 })
    end

    vim.schedule(function()
        focus_minifiles_path(path)
    end)

    return true
end

function M.jump(key)
    local item = M.by_key(key)
    if item == nil then
        return false
    end

    return M.open_in_minifiles(item.path)
end

local function display_width(text)
    return vim.fn.strdisplaywidth(text)
end

local function fit_text(text, width)
    if width <= 0 then
        return ""
    end

    if display_width(text) <= width then
        return text
    end

    if width == 1 then
        return vim.fn.strcharpart(text, 0, 1)
    end

    local suffix = "…"
    local chars = vim.fn.strchars(text)
    for len = chars, 0, -1 do
        local candidate = vim.fn.strcharpart(text, 0, len) .. suffix
        if display_width(candidate) <= width then
            return candidate
        end
    end

    return ""
end

local function choose_label(item, width)
    if display_width(item.label) <= width then
        return item.label
    end

    if display_width(item.short_label) <= width then
        return item.short_label
    end

    return fit_text(item.short_label, width)
end

local function make_cell(item, width)
    local prefix = item.key .. " " .. item.icon .. " "
    local label_width = width - display_width(prefix)

    if label_width < 1 then
        prefix = item.key .. item.icon .. " "
        label_width = width - display_width(prefix)
    end

    local text = prefix .. choose_label(item, label_width)
    if display_width(text) > width then
        text = fit_text(text, width)
    end

    local padding = math.max(0, width - display_width(text))
    local left = math.floor(padding / 2)
    return string.rep(" ", left) .. text .. string.rep(" ", padding - left)
end

local function panel_content_width()
    return math.max(1, vim.o.columns - 2)
end

local function cell_layout(count)
    local width = panel_content_width()
    local separator = count > 1 and " " or ""
    local separator_width = display_width(separator) * math.max(0, count - 1)
    local available = width - separator_width

    if available < count then
        separator = ""
        separator_width = 0
        available = width
    end

    local base_width = math.max(1, math.floor(available / count))
    local extra = math.max(0, available - base_width * count)
    local widths = {}

    for index = 1, count do
        widths[index] = base_width + (index <= extra and 1 or 0)
    end

    return widths, separator, width
end

local function fit_line(line, width)
    if display_width(line) < width then
        return line .. string.rep(" ", width - display_width(line))
    end

    return fit_text(line, width)
end

local function render_line()
    local items = M.list()
    local count = math.min(#items, #digit_keys)
    if count == 0 then
        return ""
    end

    local widths, separator, width = cell_layout(count)
    local cells = {}

    for index = 1, count do
        table.insert(cells, make_cell(items[index], widths[index]))
    end

    return fit_line(table.concat(cells, separator), width)
end

local function set_panel_lines()
    if not (panel.buf and vim.api.nvim_buf_is_valid(panel.buf)) then
        return
    end

    vim.bo[panel.buf].modifiable = true
    vim.api.nvim_buf_set_lines(panel.buf, 0, -1, false, { render_line() })
    vim.bo[panel.buf].modifiable = false
end

local function panel_border()
    return vim.o.winborder ~= "" and vim.o.winborder or "single"
end

local function panel_config()
    return {
        relative = "editor",
        row = 0,
        col = 0,
        width = panel_content_width(),
        height = 1,
        style = "minimal",
        border = panel_border(),
        title = " Quick Access ",
        title_pos = "center",
        focusable = true,
        zindex = 100,
    }
end

function M.panel_height()
    return 3
end

function M.item_at_column(col)
    local items = M.list()
    local count = math.min(#items, #digit_keys)
    if count == 0 then
        return nil
    end

    local widths, separator = cell_layout(count)
    local separator_width = display_width(separator)
    local start = 0

    for index = 1, count do
        local cell_width = widths[index]
        if col >= start and col < start + cell_width then
            return items[index]
        end
        start = start + cell_width + separator_width
    end
end

local function map_panel_keys(buf)
    for _, key in ipairs(digit_keys) do
        vim.keymap.set("n", key, function()
            M.jump(key)
        end, { buffer = buf, desc = "Open quick path " .. key })
    end

    vim.keymap.set("n", "<LeftMouse>", function()
        local mouse = vim.fn.getmousepos()
        if mouse.winid ~= panel.win then
            return
        end

        local item = M.item_at_column(math.max(0, mouse.column - 1))
        if item ~= nil then
            M.open_in_minifiles(item.path)
        end
    end, { buffer = buf, desc = "Open quick path" })
end

local function ensure_panel_buf()
    if panel.buf and vim.api.nvim_buf_is_valid(panel.buf) then
        return panel.buf
    end

    panel.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[panel.buf].bufhidden = "wipe"
    vim.bo[panel.buf].buftype = "nofile"
    vim.bo[panel.buf].filetype = "quickaccess"
    vim.bo[panel.buf].swapfile = false
    vim.b[panel.buf].minifiles_preview_keep_open = true
    map_panel_keys(panel.buf)

    return panel.buf
end

function M.open_panel()
    local buf = ensure_panel_buf()
    set_panel_lines()

    if panel.win and vim.api.nvim_win_is_valid(panel.win) then
        vim.api.nvim_win_set_config(panel.win, panel_config())
    else
        panel.win = vim.api.nvim_open_win(buf, false, panel_config())
    end

    vim.wo[panel.win].number = false
    vim.wo[panel.win].relativenumber = false
    vim.wo[panel.win].signcolumn = "no"
    vim.wo[panel.win].statuscolumn = ""
    vim.wo[panel.win].foldcolumn = "0"
    vim.wo[panel.win].wrap = false
    vim.wo[panel.win].winhighlight = table.concat({
        "NormalFloat:MiniFilesNormal",
        "FloatBorder:MiniFilesBorder",
        "FloatTitle:MiniFilesTitle",
        "CursorLine:MiniFilesCursorLine",
    }, ",")
end

function M.close_panel()
    if panel.win and vim.api.nvim_win_is_valid(panel.win) then
        vim.api.nvim_win_close(panel.win, true)
    end
    panel.win = nil

    if panel.buf and vim.api.nvim_buf_is_valid(panel.buf) then
        vim.api.nvim_buf_delete(panel.buf, { force = true })
    end
    panel.buf = nil
end

function M.position_minifiles_window(win_id)
    if type(win_id) ~= "number" or not vim.api.nvim_win_is_valid(win_id) then
        return
    end

    local config = vim.api.nvim_win_get_config(win_id)
    if config.relative ~= "editor" then
        return
    end

    config.row = M.panel_height()

    if type(config.height) == "number" then
        local max_height = math.max(1, vim.o.lines - M.panel_height() - 2)
        config.height = math.min(config.height, max_height)
    end

    vim.api.nvim_win_set_config(win_id, config)
end

function M.position_minifiles_windows()
    local ok, mini_files = pcall(require, "mini.files")
    if not ok then
        return
    end

    local state = mini_files.get_explorer_state()
    if state == nil or type(state.windows) ~= "table" then
        return
    end

    for _, win in ipairs(state.windows) do
        M.position_minifiles_window(win.win_id)
    end
end

function M.update_panel()
    M.open_panel()
    M.position_minifiles_windows()
end

return M
