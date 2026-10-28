local M = {}

-- Show named marks in the sign column.
local mark_sign_ns = vim.api.nvim_create_namespace("user-mark-signs")

local function refresh_mark_signs(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
        return
    end

    vim.api.nvim_buf_clear_namespace(buf, mark_sign_ns, 0, -1)
    local marks = vim.fn.getmarklist(buf)
    vim.list_extend(marks, vim.fn.getmarklist())

    for _, item in ipairs(marks) do
        local name = item.mark:sub(2)
        local mark_buf, line = item.pos[1], item.pos[2]
        if name:match("^[a-zA-Z]$") and mark_buf == buf and line > 0 then
            vim.api.nvim_buf_set_extmark(buf, mark_sign_ns, line - 1, 0, {
                sign_text = name,
                sign_hl_group = "DiagnosticInfo",
                priority = 20,
            })
        end
    end
end

function M.setup()
    local map = vim.keymap.set

    map("n", "m", function()
        local name = vim.fn.getcharstr()
        if not name:match("^[a-zA-Z]$") then
            return
        end

        local cursor = vim.api.nvim_win_get_cursor(0)
        vim.api.nvim_buf_set_mark(0, name, cursor[1], cursor[2], {})
        refresh_mark_signs()
    end, { desc = "Set visible mark" })

    map("n", "<leader>md", function()
        vim.cmd("delmarks!")
        vim.cmd("delmarks A-Z0-9")
        refresh_mark_signs()
    end, { desc = "Delete all marks" })

    vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
        group = vim.api.nvim_create_augroup("UserMarkSigns", { clear = true }),
        callback = function(event)
            refresh_mark_signs(event.buf)
        end,
    })
end

return M
