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
    local modname = modpath:gsub("tests.", '')
    io.write(string.format("\x1b[3m>>> %s\x1b[0m\n", modname))

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

---@param filepath string
---@return string
local function readfile(filepath)
    local content
    local fd, err
    fd, err = vim.uv.fs_open(filepath, 'r', 438)

    if not fd then
        error(err or ('Failed to open ' .. filepath))
    end

    content, err = vim.uv.fs_read(fd, 8192)

    if not content then
        error(err or ('Failed to read ' .. filepath))
    end

    _, err = vim.uv.fs_close(fd)
    if err then
        error(err)
    end

    return content
end

function M.rm_f(filepath)
    local _, err, errno = vim.uv.fs_unlink(filepath)
    if errno ~= nil and errno ~= 'ENOENT' then
        error(err)
    end
end

---@param expected any
---@param actual any
function M.assert_eql(expected, actual)
    if actual == expected then
        return
    end
    local msg = failed_message()
    msg = msg .. string.format('Expected: %s\n', tostring(expected))
    msg = msg .. string.format('Actual: %s\n', tostring(actual))
    error(msg)
end

---@param expected any[]
---@param actual any[]
function M.assert_eql_tables(expected, actual)
    for i,_ in ipairs(expected) do
        if expected[i] ~= actual[i] then
            local msg = failed_message()
            msg = msg .. string.format('Difference at index %d\n', i)
            msg = msg .. string.format('Expected: %s\n', tostring(expected[i]))
            msg = msg .. string.format('Actual: %s\n', tostring(actual[i]))
            error(msg)
        end
    end
end

---@param expected_file string
---@param actual string[]
function M.assert_eql_file(expected_file, actual)
    local expected = vim.split(readfile(expected_file), '\n', {trimempty = true})
    for i,_ in ipairs(expected) do
        if expected[i] ~= actual[i] then
            local msg = failed_message()
            msg = msg .. string.format('Difference at %s:%d\n', expected_file, i)
            msg = msg .. string.format('Expected: %s\n', tostring(expected[i]))
            msg = msg .. string.format('Actual: %s\n', tostring(actual[i]))
            error(msg)
        end
    end
end

return M
