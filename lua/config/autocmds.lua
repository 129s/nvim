local group = vim.api.nvim_create_augroup("UserConfig", { clear = true })

vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
    group = group,
    callback = function(event)
        local name = vim.api.nvim_buf_get_name(event.buf)
        if name == "" or vim.bo[event.buf].buftype ~= "" then
            return
        end
        local dir = vim.fs.dirname(name)
        if vim.fn.isdirectory(dir) == 1 then
            vim.api.nvim_set_current_dir(dir)
        end
    end,
})

-- Niri launches external terminals in the active window's cwd, including :lcd/:tcd.
if vim.env.XDG_RUNTIME_DIR and vim.env.XDG_RUNTIME_DIR ~= "" then
    local pid = vim.fn.getpid()
    local directory = vim.fs.joinpath(vim.env.XDG_RUNTIME_DIR, "nvim-cwd")
    local state_path = vim.fs.joinpath(directory, tostring(pid))
    local stat = table.concat(vim.fn.readfile("/proc/" .. pid .. "/stat"), "\n")
    local start_time = vim.split(stat:match(".*%) (.*)"), " ")[20]
    vim.fn.mkdir(directory, "p", 448)
    local function publish_cwd()
        local temporary = state_path .. ".tmp"
        vim.fn.writefile({ vim.json.encode({ cwd = vim.fn.getcwd(), start_time = start_time }) }, temporary)
        assert(vim.uv.fs_rename(temporary, state_path))
    end
    vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged", "WinEnter", "TabEnter", "BufEnter", "FocusLost" }, {
        group = group,
        callback = publish_cwd,
    })
    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = group,
        callback = function()
            vim.fn.delete(state_path)
        end,
    })
    publish_cwd()
end

vim.api.nvim_create_autocmd("TextYankPost", {
    group = group,
    callback = function()
        vim.hl.on_yank()
    end,
})

vim.api.nvim_create_autocmd("BufReadPost", {
    group = group,
    callback = function(event)
        if vim.o.diff or vim.bo[event.buf].buftype ~= "" then
            return
        end
        local mark = vim.api.nvim_buf_get_mark(event.buf, '"')
        if mark[1] > 0 and mark[1] <= vim.api.nvim_buf_line_count(event.buf) then
            pcall(vim.api.nvim_win_set_cursor, 0, mark)
        end
    end,
})
