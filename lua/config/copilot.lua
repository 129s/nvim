-- Copilot is opt-in: it stays off (no language-server process) until
-- `:CopilotToggle` enables it for the current Neovim instance. Toggling off
-- stops the LSP client, which terminates its node process.
local M = {
    enabled = false,
}

---Apply the default-off state after copilot.lua has run its setup.
function M.on_setup()
    if M.enabled then
        return
    end

    -- blink-copilot treats `vim.g.copilot_enabled ~= 0` as enabled, so keep the
    -- flag in sync to stop it from requesting against a stopped client.
    vim.g.copilot_enabled = 0
    require("copilot.command").disable()
end

function M.toggle()
    ---@diagnostic disable-next-line: missing-fields
    require("lazy").load({ plugins = { "copilot.lua" } })

    local client = require("copilot.client")

    if client.is_disabled() then
        require("copilot.command").enable()
        M.enabled = true
        vim.g.copilot_enabled = 1
        vim.notify("Copilot enabled")
    else
        require("copilot.command").disable()
        M.enabled = false
        vim.g.copilot_enabled = 0
        vim.notify("Copilot disabled")
    end
end

function M.setup()
    vim.api.nvim_create_user_command("CopilotToggle", M.toggle, {
        desc = "Toggle GitHub Copilot (starts/stops the language server)",
    })
end

return M
