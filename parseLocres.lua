
-- set to false to not check magic number
local MATCH_MAGIC = true

-- file to read from current directory
local LOCRES_FILE = "Game.locres"



local Buffer = require "buffer".Buffer
local fs = require "fs"

local function toUtf16LE(s)
    local o = {}
    for i = 1, #s do
        o[#o+1] = s:sub(i,i)
        o[#o+1] = '\x00'
    end
    return table.concat(o)
end


local buf = Buffer:new(assert(fs.readFileSync(LOCRES_FILE)))
local tag = os.date("%Y-%m-%d", fs.statSync(LOCRES_FILE).mtime.sec)   -- YYYY-mm-dd

-- check header if file is a proper locres file
local MAGIC = "\x0E\x14\x74\x75\x67\x4A\x03\xFC"
assert((not MATCH_MAGIC) or buf:toString(1,8) == MAGIC, "ERROR: Hader magic doesn't match! Probably wrong locres ver.")



----- Strings -----

-- { str = "string", isUtf16 = true/false }[], 0 index C table
local strings = {}

local pos = buf:readUInt32LE(0x11 + 1) + 1
local size = buf:readUInt32LE(pos); pos = pos + 4;

for i = 0, size-1 do
    local str
    local isUtf16 = false
    local strLen = buf:readInt32LE(pos); pos = pos + 4;

    -- negative length: utf-16 --
    if strLen < 0 then
        strLen = -strLen * 2
        str = buf:toString(pos, pos + strLen-1 - 2); pos = pos + strLen;
        isUtf16 = true
    else
        str = buf:toString(pos, pos + strLen-1 - 1); pos = pos + strLen;
    end

    local users = buf:readUInt32LE(pos); pos = pos + 4;

    strings[i] = { str = str, isUtf16 = isUtf16 }
end



----- Keys -----

-- { namespace = "namespaceName", key = "key", isUtf16 = true/false, valueId = 3 }[], 1 index normal Lua table
local keys = {}

local namespaceCount = buf:readUInt32LE(0x1D + 1)
pos = 0x21 + 1

for _ = 1, namespaceCount do
    local nsHash = buf:readUInt32LE(pos); pos = pos + 4;
    local nsNameLen = buf:readInt32LE(pos); pos = pos + 4;
    local nsName
    if nsNameLen <= 1 then
        nsName = "_internal_"
        pos = pos + (nsNameLen == 0 and 0 or 1);
    else
        nsName = buf:toString(pos, pos + nsNameLen-1 - 1); pos = pos + nsNameLen;
    end
    local nsItems = buf:readUInt32LE(pos); pos = pos + 4;

    for _ = 1, nsItems do
        local key
        local isUtf16 = false
        local keyHash1 = buf:readUInt32LE(pos); pos = pos + 4;
        local keyLen = buf:readInt32LE(pos); pos = pos + 4;

        if keyLen < 0 then  -- utf16 --
            keyLen = -keyLen * 2
            key = buf:toString(pos, pos + keyLen-1 - 2); pos = pos + keyLen;
            isUtf16 = true
        else
            key = buf:toString(pos, pos + keyLen-1 - 1); pos = pos + keyLen;
        end

        local keyHash2 = buf:readUInt32LE(pos); pos = pos + 4;
        local valueId = buf:readUInt32LE(pos); pos = pos + 4;

        table.insert(keys, {
            namespace = nsName,
            key = key,
            isUtf16 = isUtf16,
            valueId = valueId
        })
    end
end



----- Output -----

-- use io.open for writing in chunks
local out = assert(io.open(LOCRES_FILE .. "_" .. tag .. ".txt", 'wb'))

for _, key in ipairs(keys) do
    local left
    if key.isUtf16 then
        if key.key:find('[="\\]\0') then
            left = '"\0'..toUtf16LE(key.namespace..'.')..key.key:gsub('\\\0','\\\0\\\0'):gsub('"\0','\\\0"\0')..'"\0'
        else
            left = toUtf16LE(key.namespace..'.')..key.key
        end
    else
        if key.key:find('[="\\]') then
            left = toUtf16LE('"'..key.namespace..'.'..key.key:gsub('\\','\\\\'):gsub('"','\\"')..'"')
        else
            left = toUtf16LE(key.namespace..'.'..key.key)
        end
    end

    local val = strings[key.valueId]
    local right
    if val.isUtf16 then
        if val.str:find('\n\0') then
            val.str = toUtf16LE('"""\n')..val.str..toUtf16LE('\n"""')
        end
        right = val.str
    else
        if val.str:find('\n') then
            val.str = '"""\n'..val.str..'\n"""'
        end
        right = toUtf16LE(val.str)
    end

    out:write(left..'=\0'..right..'\n\0')
end

out:close()


print("Done.")
