-- json.lua — minimal JSON encode/decode (MIT License, based on rxi/json.lua)

local json = {}

-- ============================================================================
-- ENCODING
-- ============================================================================

local encode

local escape_map = {
    ["\\"] = "\\\\", ['"'] = '\\"',
    ["\b"] = "\\b",  ["\f"] = "\\f",
    ["\n"] = "\\n",  ["\r"] = "\\r",
    ["\t"] = "\\t",
}
local escape_map_inv = {}
for k, v in pairs(escape_map) do escape_map_inv[v] = k end
local function escape_char(c)
    return escape_map[c] or string.format("\\u%04x", c:byte())
end

local function enc_string(v)
    return '"' .. v:gsub('[%z\1-\31\\"]', escape_char) .. '"'
end

local function enc_number(v)
    if v ~= v        then error("cannot encode NaN")      end
    if v ==  math.huge or v == -math.huge then
                          error("cannot encode Infinity")  end
    return string.format("%.14g", v)
end

local function enc_table(v, stack)
    stack = stack or {}
    if stack[v] then error("circular reference in table") end
    stack[v] = true
    local res = {}
    -- Decide array vs object: array iff all keys are consecutive integers from 1
    local n = #v
    local isArr = true
    local count = 0
    for _ in pairs(v) do count = count + 1 end
    if count ~= n then isArr = false end
    if isArr then
        for i = 1, n do res[i] = encode(v[i], stack) end
        stack[v] = nil
        return "[" .. table.concat(res, ",") .. "]"
    else
        local i = 0
        for k, val in pairs(v) do
            if type(k) ~= "string" then
                error("non-string key: " .. tostring(k))
            end
            i = i + 1
            res[i] = enc_string(k) .. ":" .. encode(val, stack)
        end
        stack[v] = nil
        return "{" .. table.concat(res, ",") .. "}"
    end
end

local type_enc = {
    ["nil"]     = function() return "null" end,
    ["boolean"] = tostring,
    ["number"]  = enc_number,
    ["string"]  = enc_string,
    ["table"]   = enc_table,
}

encode = function(v, stack)
    local f = type_enc[type(v)]
    if not f then error("cannot encode type: " .. type(v)) end
    return f(v, stack)
end

function json.encode(v) return encode(v) end

-- ============================================================================
-- DECODING
-- ============================================================================

local parse

local SPACE = { [" "]=true, ["\t"]=true, ["\r"]=true, ["\n"]=true }
local DELIM = { [" "]=true, ["\t"]=true, ["\r"]=true, ["\n"]=true,
                ["]"]=true, ["}"]=true,  [","]=true }

local function skip(s, i)
    while SPACE[s:sub(i,i)] do i = i + 1 end
    return i
end

local function next_delim(s, i)
    while not DELIM[s:sub(i,i)] and i <= #s do i = i + 1 end
    return i
end

local function err(s, i, msg)
    local line, col = 1, 1
    for j = 1, i-1 do
        col = col + 1
        if s:sub(j,j) == "\n" then line = line+1; col = 1 end
    end
    error(string.format("%s at line %d col %d", msg, line, col))
end

local function parse_string(s, i)
    local res, j = {}, i + 1
    local k = j
    while j <= #s do
        local b = s:byte(j)
        if b < 32 then err(s, j, "control char in string")
        elseif b == 92 then -- backslash
            res[#res+1] = s:sub(k, j-1)
            j = j + 1
            local c = s:sub(j, j)
            if c == "u" then
                local hex = s:sub(j+1, j+4)
                if #hex < 4 then err(s, j, "bad unicode escape") end
                local n = tonumber(hex, 16)
                -- surrogate pair
                if n >= 0xD800 and n <= 0xDBFF then
                    local hex2 = s:sub(j+7, j+10)
                    local n2   = tonumber(hex2, 16) or 0
                    n = (n - 0xD800) * 0x400 + (n2 - 0xDC00) + 0x10000
                    j = j + 6
                end
                -- codepoint to UTF-8
                local u
                local f = math.floor
                if     n <= 0x7F   then u = string.char(n)
                elseif n <= 0x7FF  then u = string.char(f(n/64)+192, n%64+128)
                elseif n <= 0xFFFF then u = string.char(f(n/4096)+224, f(n%4096/64)+128, n%64+128)
                else                    u = string.char(f(n/262144)+240, f(n%262144/4096)+128, f(n%4096/64)+128, n%64+128)
                end
                res[#res+1] = u
                j = j + 4
            else
                local esc = escape_map_inv["\\" .. c]
                if not esc then err(s, j-1, "invalid escape '\\" .. c .. "'") end
                res[#res+1] = esc
            end
            k = j + 1
        elseif b == 34 then -- quote
            res[#res+1] = s:sub(k, j-1)
            return table.concat(res), j + 1
        end
        j = j + 1
    end
    err(s, i, "unclosed string")
end

local function parse_number(s, i)
    local j = next_delim(s, i)
    local n = tonumber(s:sub(i, j-1))
    if not n then err(s, i, "invalid number") end
    return n, j
end

local LITERALS = { ["true"]=true, ["false"]=false, ["null"]=nil }
local LIT_KEYS = { ["true"]=true, ["false"]=true, ["null"]=true }

local function parse_literal(s, i)
    local j    = next_delim(s, i)
    local word = s:sub(i, j-1)
    if not LIT_KEYS[word] then err(s, i, "unknown literal '" .. word .. "'") end
    return LITERALS[word], j
end

local function parse_array(s, i)
    local res, n = {}, 1
    i = skip(s, i + 1)
    if s:sub(i,i) == "]" then return res, i+1 end
    while true do
        local v
        v, i = parse(s, i)
        res[n] = v; n = n + 1
        i = skip(s, i)
        local c = s:sub(i,i)
        i = i + 1
        if c == "]" then return res, i end
        if c ~= "," then err(s, i-1, "expected ',' or ']'") end
        i = skip(s, i)
    end
end

local function parse_object(s, i)
    local res = {}
    i = skip(s, i + 1)
    if s:sub(i,i) == "}" then return res, i+1 end
    while true do
        if s:sub(i,i) ~= '"' then err(s, i, "expected string key") end
        local k, v
        k, i = parse_string(s, i)
        i = skip(s, i)
        if s:sub(i,i) ~= ":" then err(s, i, "expected ':'") end
        i = skip(s, i + 1)
        v, i = parse(s, i)
        res[k] = v
        i = skip(s, i)
        local c = s:sub(i,i)
        i = i + 1
        if c == "}" then return res, i end
        if c ~= "," then err(s, i-1, "expected ',' or '}'") end
        i = skip(s, i)
    end
end

local DISPATCH = {
    ['"'] = parse_string,
    ["["] = parse_array,
    ["{"] = parse_object,
    ["t"] = parse_literal, ["f"] = parse_literal, ["n"] = parse_literal,
    ["-"] = parse_number,
}
for d = string.byte("0"), string.byte("9") do
    DISPATCH[string.char(d)] = parse_number
end

parse = function(s, i)
    local c = s:sub(i,i)
    local f = DISPATCH[c]
    if not f then err(s, i, "unexpected character '" .. c .. "'") end
    return f(s, i)
end

function json.decode(s)
    if type(s) ~= "string" then
        error("json.decode expects a string, got " .. type(s))
    end
    local v, i = parse(s, skip(s, 1))
    i = skip(s, i)
    if i <= #s then err(s, i, "trailing garbage") end
    return v
end

return json
