-- Client side of the shared language servers managed by `lspmux.service`.
-- Keep host/port in sync with ~/.config/lspmux/config.toml.
local M = {
    host = "127.0.0.1",
    port = 27631,
}

--- LSP `init_options.lspMux` for a server spawned by lspmux.
---@param server string Absolute path or name resolved in the service's PATH.
---@param args string[]|nil
function M.options(server, args)
    return {
        version = "1",
        method = "connect",
        server = server,
        args = args or {},
        -- Only used when the client sends no workspace folder.
        cwd = vim.uv.cwd(),
    }
end

M.connect = vim.lsp.rpc.connect(M.host, M.port)

return M
