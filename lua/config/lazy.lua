local lazier_path = vim.fn.stdpath("data") .. "/lazier/lazier.nvim"

if not vim.uv.fs_stat(lazier_path) then
    local repo = "https://github.com/jake-stewart/lazier.nvim.git"
    local out = vim.fn.system({ "git", "clone", "--branch=stable-v2", repo, lazier_path })
    if vim.v.shell_error ~= 0 then
        vim.api.nvim_echo({
            { "Failed to clone lazier.nvim:\n", "ErrorMsg" },
            { out, "WarningMsg" },
        }, true, {})
        vim.fn.getchar()
        os.exit(1)
    end
end

vim.opt.rtp:prepend(lazier_path)

require("lazier").setup("plugins", {
    spec = {
        { import = "plugins" },
    },
    defaults = {
        lazy = false,
        version = false,
    },
    performance = {
        rtp = {
            disabled_plugins = {
                "gzip",
                "tarPlugin",
                "tohtml",
                "tutor",
                "zipPlugin",
            },
        },
    },
    lazier = {
        -- Treewalker is mapped from the global keymap file. Starting lazily can
        -- leave its command unavailable during the first input events.
        start_lazily = false,
        before = function()
            require("config.bigfile").setup()
            require("config.options")
            require("config.autocmds")
        end,
        after = function()
            require("config.keymaps")
            require("config.copilot").setup()
            require("config.cleanmode").setup()
        end,
    },
})
