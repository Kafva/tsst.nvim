local M = {}

-- Test modules should be imported from '.'
vim.o.runtimepath = vim.o.runtimepath .. ',.'

local COLOR_RED = string.char(27) .. '[91m'
local COLOR_GREEN = string.char(27) .. '[32m'
local COLOR_RESET = string.char(27) .. '[0m'

---@param msg string|nil
local function failed_message(msg)
    local info = debug.getinfo(3, 'Sl')
    local src = info.source
    local lnum = info.currentline
    return '\nAssertion failed: '
        .. src
        .. ':'
        .. lnum
        .. ': '
        .. (msg or '')
        .. '\n'
end


---@return boolean
function M.run_test(testfile)
    local modpath = testfile:gsub('/', '.'):gsub('.lua$', '')
    local ok, testmod = pcall(require, modpath)
    if not ok then
        io.write('Error loading test module: ' .. tostring(testmod) .. '\n')
        io.flush()
        return false
    end
    io.write('=== Module: ' .. modpath .. '\n')

    for _, tc in pairs(testmod.testcases) do
        testmod.before_each()
        local testcase_ok, errmsg = pcall(tc.fn)
        local status = testcase_ok and (COLOR_GREEN .. ' OK ' .. COLOR_RESET)
            or (COLOR_RED .. 'FAIL' .. COLOR_RESET)
        io.write(string.format("[ %s ] %s\n", status, tc.desc))
        io.flush()

        if not testcase_ok then
            io.write(errmsg .. '\n')
            io.flush()
            return false
        end
    end

    return true
end

vim.api.nvim_create_user_command('RunTests', function(opts)
    local targets = vim.split(opts.fargs[1], ' ')
    for _, target in pairs(targets) do
        if not M.run_test(target) then
            break
        end
    end
    vim.cmd [[silent qa!]]
end, { nargs = 1 })

-- Test utilities --------------------------------------------------------------
function M.rm_f(filepath)
    local _, err, errno = vim.uv.fs_unlink(filepath)
    if errno ~= nil and errno ~= 'ENOENT' then
        error(err)
    end
end

---@param got any
---@param expected any
function M.assert_eq(got, expected)
    if got == expected then
        return
    end
    local msg = failed_message()
    msg = msg .. 'Expected: ' .. tostring(expected) .. '\n'
    msg = msg .. 'Got: ' .. tostring(got) .. '\n'
    error(msg)
end

return M
