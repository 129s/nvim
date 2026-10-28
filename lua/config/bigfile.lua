local M = {
    -- Keep this low enough to catch parser-hostile generated Lua/JSON files
    -- before FileType and Treesitter callbacks get a chance to run.
    size = 400 * 1024,
    line_count = 20000,
    line_length = 500,
}

local function file_size(buf)
    local name = vim.api.nvim_buf_get_name(buf)
    if name == "" then
        return 0
    end

    local stat = vim.uv.fs_stat(name)
    return stat and stat.size or 0
end

function M.is_large(buf)
    buf = buf or 0
    buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
    if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
        return false
    end

    if vim.b[buf].user_bigfile then
        return true
    end

    local size = file_size(buf)
    if size >= M.size then
        return true
    end

    local lines = vim.api.nvim_buf_line_count(buf)
    return lines >= M.line_count or (lines > 0 and size / lines >= M.line_length)
end

function M.apply(buf)
    buf = buf or 0
    buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end

    vim.b[buf].user_bigfile = true
    vim.b[buf].completion = false
    vim.b[buf].snacks_indent = false
    vim.b[buf].snacks_scope = false
    vim.b[buf].snacks_words = false
    vim.b[buf].miniindentscope_disable = true
    vim.b[buf].minianimate_disable = true
    vim.b[buf].minihipatterns_disable = true

    vim.bo[buf].syntax = ""
    vim.bo[buf].undofile = false

    pcall(vim.treesitter.stop, buf)

    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        vim.wo[win].cursorline = false
        vim.wo[win].foldenable = false
        vim.wo[win].foldmethod = "manual"
        vim.wo[win].list = false
        vim.wo[win].relativenumber = false
        vim.wo[win].spell = false
        vim.wo[win].wrap = false
    end

    if vim.fn.exists(":NoMatchParen") == 2 then
        pcall(vim.cmd, "NoMatchParen")
    end
end

function M.setup()
    local group = vim.api.nvim_create_augroup("UserBigFile", { clear = true })

    vim.api.nvim_create_autocmd("BufReadPre", {
        group = group,
        callback = function(args)
            if file_size(args.buf) >= M.size then
                M.apply(args.buf)
            end
        end,
    })

    vim.api.nvim_create_autocmd({ "BufReadPost", "FileType", "BufWinEnter" }, {
        group = group,
        callback = function(args)
            if M.is_large(args.buf) then
                M.apply(args.buf)
            end
        end,
    })
end

return M
