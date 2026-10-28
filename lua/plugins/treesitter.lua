local languages = {
    "bash",
    "c",
    "cpp",
    "dart",
    "json",
    "lua",
    "markdown",
    "markdown_inline",
    "comment",
    "latex",
    "odin",
    "python",
    "query",
    "toml",
    "vim",
    "vimdoc",
    "yaml",
    "zig",
}

return {
    {
        "nvim-treesitter/nvim-treesitter",
        branch = "main",
        build = ":TSUpdate",
        config = function()
            local treesitter = require("nvim-treesitter")
            treesitter.setup()

            local ts_config = require("nvim-treesitter.config")
            local installed = ts_config.get_installed()
            local to_install = {}

            for _, lang in ipairs(languages) do
                if not vim.tbl_contains(installed, lang) then
                    table.insert(to_install, lang)
                end
            end

            local function start_treesitter(buf, filetype)
                if not vim.api.nvim_buf_is_valid(buf) or filetype == "" then
                    return
                end

                if require("config.bigfile").is_large(buf) then
                    pcall(vim.treesitter.stop, buf)
                    return
                end

                local lang = vim.treesitter.language.get_lang(filetype)
                if not lang or not vim.tbl_contains(ts_config.get_installed(), lang) then
                    return
                end

                pcall(vim.treesitter.start, buf, lang)
            end

            local function start_loaded_buffers()
                for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                    if vim.api.nvim_buf_is_loaded(buf) then
                        start_treesitter(buf, vim.bo[buf].filetype)
                    end
                end
            end

            local group = vim.api.nvim_create_augroup("UserTreesitter", { clear = true })
            vim.api.nvim_create_autocmd("FileType", {
                group = group,
                callback = function(args)
                    start_treesitter(args.buf, args.match)
                end,
            })
            vim.api.nvim_create_autocmd("User", {
                group = group,
                pattern = "TSUpdate",
                callback = start_loaded_buffers,
            })

            start_loaded_buffers()

            if #to_install > 0 then
                local install_task = treesitter.install(to_install)
                install_task:await(function(err)
                    if not err then
                        vim.schedule(start_loaded_buffers)
                    end
                end)
            end
        end,
    },
    {
        "nvim-treesitter/nvim-treesitter-textobjects",
        branch = "main",
        dependencies = { "nvim-treesitter/nvim-treesitter" },
        config = setup_textobjects,
    },
    {
        "HiPhish/rainbow-delimiters.nvim",
        init = function()
            vim.g.rainbow_delimiters = {
                highlight = {
                    "RainbowDelimiterViolet",
                    "RainbowDelimiterOrange",
                    "RainbowDelimiterBlue",
                    "RainbowDelimiterYellow",
                    "RainbowDelimiterGreen",
                    "RainbowDelimiterRed",
                    "RainbowDelimiterCyan",
                },
            }
        end,
    },
}
