local M = {}

local active = false
local saved = { windows = {}, defaults = nil, laststatus = nil, completion = nil }
local group = vim.api.nvim_create_augroup("UserCleanMode", { clear = true })

local function completion_enabled()
    return vim.g.user_completion_enabled ~= false
end

local function hide_completion()
    if not package.loaded["blink.cmp.config"] then
        return
    end

    pcall(function()
        local cmp = require("blink.cmp")
        cmp.hide()
        cmp.hide_documentation()
        cmp.hide_signature()
    end)
end

local function toggle_completion()
    vim.g.user_completion_enabled = not completion_enabled()

    if not completion_enabled() then
        hide_completion()
    end

    vim.notify("Completion " .. (completion_enabled() and "enabled" or "disabled"))
end

local function apply(win)
    vim.api.nvim_set_option_value("number", false, { win = win })
    vim.api.nvim_set_option_value("relativenumber", false, { win = win })
end

local function save(win, number, relativenumber)
    if saved.windows[win] ~= nil then
        return
    end

    saved.windows[win] = { number = number, relativenumber = relativenumber }
end

local function enable()
    local win = vim.api.nvim_get_current_win()
    saved.laststatus = vim.o.laststatus
    saved.completion = completion_enabled()
    saved.windows = {}
    saved.defaults = { number = vim.wo.number, relativenumber = vim.wo.relativenumber }

    -- New windows inherit these values while clean mode is active; restore from
    -- the pre-clean defaults instead of the inherited state.
    save(win, saved.defaults.number, saved.defaults.relativenumber)
    apply(win)

    vim.o.laststatus = 0
    vim.g.user_completion_enabled = false
    hide_completion()
end

local function disable()
    for win, opts in pairs(saved.windows) do
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_set_option_value("number", opts.number, { win = win })
            vim.api.nvim_set_option_value("relativenumber", opts.relativenumber, { win = win })
        end
    end

    if saved.laststatus ~= nil then
        vim.o.laststatus = saved.laststatus
    end
    if saved.completion ~= nil then
        vim.g.user_completion_enabled = saved.completion
    end

    saved = { windows = {}, defaults = nil, laststatus = nil, completion = nil }
end

function M.setup()
    vim.api.nvim_create_autocmd("WinNew", {
        group = group,
        callback = function()
            if not active then
                return
            end

            local win = vim.api.nvim_get_current_win()
            save(win, saved.defaults.number, saved.defaults.relativenumber)
            apply(win)
        end,
    })

    vim.api.nvim_create_user_command("ToggleCompletion", toggle_completion, {
        desc = "Toggle completion",
    })

    vim.api.nvim_create_user_command("CleanMode", function()
        active = not active
        if active then
            enable()
        else
            disable()
        end
        vim.notify("Clean mode " .. (active and "enabled" or "disabled"))
    end, {
        desc = "Toggle clean mode for live coding",
    })
end

return M
