return {
    {
        "stevearc/conform.nvim",
        event = { "BufWritePre" },
        cmd = { "ConformInfo" },
        keys = {
            {
                "<leader>lf",
                function()
                    require("conform").format({ async = true, lsp_format = "fallback" })
                end,
                mode = { "n", "x" },
                desc = "Format",
            },
        },
        opts = {
            format_on_save = function(bufnr)
                -- Keep LaTeX formatting opt-in until latexindent is configured.
                if vim.tbl_contains({ "tex", "plaintex", "bib" }, vim.bo[bufnr].filetype) then
                    return
                end

                return {
                    timeout_ms = 1000,
                    lsp_format = "fallback",
                }
            end,
            formatters_by_ft = {
                dart = { "dart_format" },
                lua = { "stylua" },
                odin = { "odinfmt" },
                zig = { "zigfmt" },
            },
        },
    },
}
