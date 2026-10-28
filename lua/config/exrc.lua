-- Allow project-local .nvim.lua configs without the trust prompt.
-- Neovim sources .nvim.lua through vim.secure.read(), which otherwise asks
-- before running untrusted code. Files explicitly denied with `:trust ++deny`
-- (a "!" entry in the trust database) are still skipped.
local trust_file = vim.fn.stdpath("state") .. "/trust"

local function denied(fullpath)
    local f = io.open(trust_file, "r")
    if not f then
        return false
    end
    local db = f:read("*a") or ""
    f:close()
    for line in vim.gsplit(db, "\n") do
        local hash, file = line:match("^(%S+) (.+)$")
        if hash == "!" and file == fullpath then
            return true
        end
    end
    return false
end

local secure_read = vim.secure.read

vim.secure.read = function(path)
    local fullpath = vim.uv.fs_realpath(vim.fs.normalize(path))
    if fullpath and vim.endswith(fullpath, ".nvim.lua") and not denied(fullpath) then
        local f = io.open(fullpath, "rb")
        if f then
            local contents = f:read("*a")
            f:close()
            if contents then
                return contents
            end
        end
    end
    return secure_read(path)
end

-- Autocmds created by a file are remembered so a re-source does not stack
-- duplicates (Lua's nvim_create_autocmd without a group appends). Startup
-- loading is done by Neovim's C code, so its autocmds are not tracked; the
-- first manual reload can therefore leave one extra instance.
local sourced_autocmds = {}

local function autocmd_ids()
    local ids = {}
    for _, au in ipairs(vim.api.nvim_get_autocmds({})) do
        if au.id then
            ids[au.id] = true
        end
    end
    return ids
end

local function clear_sourced_autocmds(file)
    for _, id in ipairs(sourced_autocmds[file] or {}) do
        pcall(vim.api.nvim_del_autocmd, id)
    end
    sourced_autocmds[file] = nil
end

local function record_sourced_autocmds(file, before)
    local created = {}
    for _, au in ipairs(vim.api.nvim_get_autocmds({})) do
        if au.id and not before[au.id] then
            created[#created + 1] = au.id
        end
    end
    sourced_autocmds[file] = created
end

-- Source-like reload for project configs: `:ExrcReload` re-runs the same
-- search as startup (cwd upward, nearest first) without restarting Nvim.
-- Trust is unchanged: vim.secure.read() still gates the files.
local function source_exrc(file)
    local ok, contents = pcall(vim.secure.read, file)
    if not ok then
        return "error", contents
    end
    if type(contents) ~= "string" then
        return "untrusted"
    end

    clear_sourced_autocmds(file)
    local before = autocmd_ids()

    local ok_run, err
    if vim.endswith(file, ".lua") then
        local chunk, load_err = loadstring(contents, "@" .. file)
        if not chunk then
            record_sourced_autocmds(file, before)
            return "error", load_err
        end
        ok_run, err = pcall(chunk)
    else
        ok_run, err = pcall(vim.api.nvim_exec2, contents, {})
    end
    record_sourced_autocmds(file, before)
    if not ok_run then
        return "error", err
    end
    return "ok"
end

local function exrc_files()
    return vim.fs.find({ ".nvim.lua", ".nvimrc", ".exrc" }, {
        type = "file",
        upward = true,
        limit = math.huge,
        path = vim.fn.getcwd(),
    })
end

local reloading = false

local function do_reload_exrc()
    local cwd = vim.fn.getcwd()
    local files = exrc_files()
    if #files == 0 then
        vim.notify("exrc: no project config found under " .. cwd, vim.log.levels.WARN)
        return
    end

    local exrc_on = vim.o.exrc
    local count = 0
    for _, file in ipairs(files) do
        local full = vim.uv.fs_realpath(vim.fs.normalize(file))
        if full then
            local status, err = source_exrc(full)
            if status == "ok" then
                count = count + 1
            elseif status == "untrusted" then
                vim.notify(("exrc: %s is not trusted; run :trust then :ExrcReload"):format(full), vim.log.levels.WARN)
            else
                vim.notify(("exrc: %s: %s"):format(full, tostring(err)), vim.log.levels.ERROR)
                return
            end
        end
        -- Mirror startup semantics: an exrc can opt out of parent configs.
        -- Ignore the sentinel when 'exrc' was already off (explicit reload).
        if exrc_on and not vim.o.exrc then
            break
        end
    end
    vim.notify(("exrc: reloaded %d file(s)"):format(count), vim.log.levels.INFO)
end

local function reload_exrc()
    if reloading then
        return
    end
    reloading = true
    local ok, err = pcall(do_reload_exrc)
    reloading = false
    if not ok then
        vim.notify("exrc: reload failed: " .. tostring(err), vim.log.levels.ERROR)
    end
end

vim.api.nvim_create_user_command("ExrcReload", reload_exrc, {
    desc = "Re-source project .nvim.lua/.nvimrc/.exrc (like `source .zshrc`)",
})

-- Auto-reload `.nvim.lua` on save, but only when the saved file belongs to the
-- current exrc chain. `.nvimrc`/`.exrc` are excluded: their trust hash changes
-- on save, so reloading would trigger the trust prompt.
vim.api.nvim_create_autocmd("BufWritePost", {
    group = vim.api.nvim_create_augroup("UserExrcReload", { clear = true }),
    pattern = ".nvim.lua",
    callback = function(args)
        local saved = vim.uv.fs_realpath(vim.fs.normalize(args.file))
        if not saved then
            return
        end
        for _, file in ipairs(exrc_files()) do
            local full = vim.uv.fs_realpath(vim.fs.normalize(file))
            if full == saved then
                reload_exrc()
                return
            end
        end
    end,
})
