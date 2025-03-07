local M = {}

-- Test modules should be imported from '.'
vim.o.runtimepath = vim.o.runtimepath .. ',.'

local ANSI_RED = string.char(27) .. '[91m'
local ANSI_RED_BG = string.char(27) .. '[101m'
local ANSI_GREEN = string.char(27) .. '[32m'
local ANSI_ITALICS = string.char(27) .. '[3m'
local ANSI_RESET = string.char(27) .. '[0m'

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
    io.write(string.format(ANSI_ITALICS .. ">>> %s" .. ANSI_RESET .. "\n", modname))

    for _, tc in pairs(testmod.testcases) do
        testmod.before_each()
        local testcase_ok, errmsg = pcall(tc.fn)
        local status = testcase_ok and (ANSI_GREEN .. ' OK ' .. ANSI_RESET)
            or (ANSI_RED .. 'FAIL' .. ANSI_RESET)
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

---@param expected any
---@param actual any
---@return string
local function colordiff(expected, actual)
    local expected_s = tostring(expected)
    local actual_s = tostring(actual)
    msg = "Expected:\n  " .. expected_s .. "\n"
    msg = msg .. "Actual:\n  "
    for i = 1, #expected_s do
        if i > #actual_s then
            msg = msg .. ANSI_RED_BG .. " " .. ANSI_RESET
        elseif expected_s:sub(i, i) ~= actual_s:sub(i, i) then
            msg = msg .. ANSI_RED .. actual_s:sub(i,i) .. ANSI_RESET
        else
            msg = msg .. actual_s:sub(i, i)
        end
    end
    return msg .. "\n"
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
    if expected == actual then
        return
    end
    local msg = failed_message()
    msg = msg .. colordiff(expected, actual)
    error(msg)
end

---@param expected any[]
---@param actual any[]
function M.assert_eql_tables(expected, actual)
    for i,_ in ipairs(expected) do
        if expected[i] ~= actual[i] then
            local msg = failed_message()
            msg = msg .. string.format('Difference at index %d\n', i)
            msg = msg .. colordiff(expected[i], actual[i])
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
            msg = msg .. colordiff(expected[i], actual[i])
            error(msg)
        end
    end
end

return M
