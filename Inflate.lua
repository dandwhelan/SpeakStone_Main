local addonName, addon = ...

-- A DEFLATE decoder in plain Lua 5.1 (no bit operators, as the game's Lua has none),
-- for the quest text the Guide shows (QuestTexts.lua, built by tools/build_quest_texts.py).
-- The text is about 17 MB; compressed in small chunks and kept as base64 text it is a
-- third of that, and a chunk is unpacked only when a quest in it is looked at.
--
-- Modelled on zlib's "puff": one bit at a time, canonical Huffman codes from the code
-- lengths. Slower than a table-driven decoder but a chunk is about 40 KB, and the code
-- is short enough to check by eye.

local floor = math.floor
local byte, char, concat = string.byte, string.char, table.concat
local unpack = unpack or table.unpack

local POW2 = {}
for i = 0, 31 do POW2[i] = 2 ^ i end

local LEN_BASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 }
local LEN_EXTRA = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DIST_BASE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 }
local DIST_EXTRA = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local CLEN_ORDER = { 17, 18, 19, 1, 9, 8, 10, 7, 11, 6, 12, 5, 13, 4, 14, 3, 15, 2, 16 }

-- A canonical Huffman code from a list of lengths (lengths[i] is the length of symbol i - 1).
local function BuildHuffman(lengths, n)
    local count, symbol, offs = {}, {}, {}
    for len = 0, 15 do count[len] = 0 end
    for i = 1, n do
        local l = lengths[i]
        count[l] = count[l] + 1
    end
    offs[1] = 0
    for len = 1, 14 do offs[len + 1] = offs[len] + count[len] end
    for i = 1, n do
        local l = lengths[i]
        if l ~= 0 then
            symbol[offs[l]] = i - 1
            offs[l] = offs[l] + 1
        end
    end
    return { count = count, symbol = symbol }
end

local fixedLit, fixedDist
local function FixedTables()
    if not fixedLit then
        local l = {}
        for i = 1, 144 do l[i] = 8 end
        for i = 145, 256 do l[i] = 9 end
        for i = 257, 280 do l[i] = 7 end
        for i = 281, 288 do l[i] = 8 end
        fixedLit = BuildHuffman(l, 288)
        local d = {}
        for i = 1, 30 do d[i] = 5 end
        fixedDist = BuildHuffman(d, 30)
    end
    return fixedLit, fixedDist
end

-- Returns the decoded string, or nil and a reason when the data is not valid DEFLATE.
function addon.Inflate(data)
    local pos, bitbuf, bitcnt = 1, 0, 0
    local size = #data
    local out, n = {}, 0

    local function Bits(need)
        while bitcnt < need do
            local b = byte(data, pos)
            if not b then error("ran out of input") end
            pos = pos + 1
            bitbuf = bitbuf + b * POW2[bitcnt]
            bitcnt = bitcnt + 8
        end
        local value = bitbuf % POW2[need]
        bitbuf = (bitbuf - value) / POW2[need]
        bitcnt = bitcnt - need
        return value
    end

    local function Decode(h)
        local code, first, index = 0, 0, 0
        local count, symbol = h.count, h.symbol
        for len = 1, 15 do
            code = code + Bits(1)
            local c = count[len]
            if code - c < first then
                return symbol[index + (code - first)]
            end
            index = index + c
            first = (first + c) * 2
            code = code * 2
        end
        error("bad code")
    end

    local function Codes(lit, dist)
        while true do
            local sym = Decode(lit)
            if sym < 256 then
                n = n + 1
                out[n] = sym
            elseif sym == 256 then
                return
            else
                sym = sym - 256
                if sym > 29 then error("bad length symbol") end
                local len = LEN_BASE[sym] + Bits(LEN_EXTRA[sym])
                local ds = Decode(dist) + 1
                if ds > 30 then error("bad distance symbol") end
                local d = DIST_BASE[ds] + Bits(DIST_EXTRA[ds])
                if d > n then error("distance too far back") end
                for _ = 1, len do
                    n = n + 1
                    out[n] = out[n - d]
                end
            end
        end
    end

    local function Stored()
        bitbuf, bitcnt = 0, 0
        local lo, hi = byte(data, pos), byte(data, pos + 1)
        if not (lo and hi) then error("ran out of input") end
        local len = lo + hi * 256
        pos = pos + 4
        for i = 0, len - 1 do
            local b = byte(data, pos + i)
            if not b then error("ran out of input") end
            n = n + 1
            out[n] = b
        end
        pos = pos + len
    end

    local function Dynamic()
        local nlen = Bits(5) + 257
        local ndist = Bits(5) + 1
        local ncode = Bits(4) + 4
        local lengths = {}
        for i = 1, 19 do lengths[i] = 0 end
        for i = 1, ncode do lengths[CLEN_ORDER[i]] = Bits(3) end
        local lencode = BuildHuffman(lengths, 19)
        local all, idx = {}, 0
        while idx < nlen + ndist do
            local sym = Decode(lencode)
            if sym < 16 then
                idx = idx + 1
                all[idx] = sym
            else
                local prev, rep = 0, 0
                if sym == 16 then
                    if idx == 0 then error("repeat with nothing before it") end
                    prev = all[idx]
                    rep = 3 + Bits(2)
                elseif sym == 17 then
                    rep = 3 + Bits(3)
                else
                    rep = 11 + Bits(7)
                end
                for _ = 1, rep do
                    idx = idx + 1
                    all[idx] = prev
                end
            end
        end
        local lit, dl = {}, {}
        for i = 1, nlen do lit[i] = all[i] end
        for i = 1, ndist do dl[i] = all[nlen + i] end
        return BuildHuffman(lit, nlen), BuildHuffman(dl, ndist)
    end

    local ok, err = pcall(function()
        local last
        repeat
            last = Bits(1)
            local kind = Bits(2)
            if kind == 0 then
                Stored()
            elseif kind == 1 then
                local lit, dist = FixedTables()
                Codes(lit, dist)
            elseif kind == 2 then
                local lit, dist = Dynamic()
                Codes(lit, dist)
            else
                error("bad block type")
            end
        until last == 1
    end)
    if not ok then
        return nil, tostring(err)
    end
    -- bytes to a string, a slice at a time (unpack has a limit)
    local parts = {}
    for i = 1, n, 4096 do
        parts[#parts + 1] = char(unpack(out, i, math.min(i + 4095, n)))
    end
    return concat(parts)
end

-- base64 text to the bytes it stands for.
local B64 = {}
do
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i = 1, #alphabet do B64[byte(alphabet, i)] = i - 1 end
end

function addon.Base64Decode(text)
    local parts, np = {}, 0
    local len = #text
    for i = 1, len, 4 do
        local a, b, c, d = byte(text, i, i + 3)
        local va, vb = B64[a], B64[b]
        if not (va and vb) then break end
        local vc, vd = c and B64[c], d and B64[d]
        local value = va * 262144 + vb * 4096 + (vc or 0) * 64 + (vd or 0)
        local b1 = floor(value / 65536)
        local b2 = floor(value / 256) % 256
        local b3 = value % 256
        np = np + 1
        if vc and vd then
            parts[np] = char(b1, b2, b3)
        elseif vc then
            parts[np] = char(b1, b2)
        else
            parts[np] = char(b1)
        end
    end
    return concat(parts)
end
