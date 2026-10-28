-- `w`/`b` (backed by nvim-spider) settle on the line boundary instead of
-- jumping across the newline: `w` stops on the last non-blank character of the
-- current line, `b` on the first one. Only the press that would cross the line
-- is consumed this way; the following press crosses as usual.
local M = {}

local spider = require("spider")

local function first_nonblank_col(line)
    local col = line:find("%S")
    return col and col - 1
end

--- Byte column of the last non-blank character.
local function last_nonblank_col(line)
    local trimmed = line:gsub("%s+$", "")
    if trimmed == "" then
        return nil
    end
    return vim.fn.byteidx(trimmed, vim.fn.strchars(trimmed) - 1)
end

local function motion(key)
    local start = vim.api.nvim_win_get_cursor(0)
    local start_row, start_col = start[1], start[2]
    local line = vim.api.nvim_buf_get_lines(0, start_row - 1, start_row, true)[1] or ""
    local op_pending = vim.api.nvim_get_mode().mode == "no"

    spider.motion(key)

    local row = vim.api.nvim_win_get_cursor(0)[1]
    if key == "w" then
        if row <= start_row then
            return
        end
        local col = last_nonblank_col(line)
        if not col or col <= start_col then
            return
        end
        if op_pending then
            -- operator-pending ranges stop before the endpoint; let spider build
            -- an inclusive one so the last character is covered
            require("spider.extras.operator-pending").setEndpoints(start, { start_row, col }, { inclusive = true })
        else
            vim.api.nvim_win_set_cursor(0, { start_row, col })
        end
    else
        if row >= start_row then
            return
        end
        local col = first_nonblank_col(line)
        if not col or col >= start_col then
            return
        end
        vim.api.nvim_win_set_cursor(0, { start_row, col })
    end
end

function M.w()
    motion("w")
end

function M.b()
    motion("b")
end

return M
