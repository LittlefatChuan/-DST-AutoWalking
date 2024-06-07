-- 125 --> {1,1,1,1,1,0,1}
function DecToBinTable(num, reverse)
    if type(num) ~= "number" then
        if type(num) == "string" then
            num = tonumber(num, 10)
        elseif type(num) == "table" then
            num = tonumber(table.concat(num), 10)
        end
    end

    if num == nil then return end

    local t = {}
    local n = num
    local i = 1
    repeat
        t[i] = n%2
        i = i+1
        n = math.floor(n/2)
    until(n == 0)
    if not reverse then
        t = table.reverse(t)  -- klei has write table.reverse in the util.lua
    end
    return t
end

--"1111101" --> 125
function BinToDecNum(bin)
    local bin_str
    if type(bin) == "table" then
        bin_str = table.concat(bin)
    elseif type(bin) == "number" then
        bin_str = tostring(bin)
    elseif type(bin) == "string" then
        bin_str = bin
    end
    if bin_str == nil then return end

    return tonumber(bin_str, 2)
end

-- 1 --> true   0--> false
function BitToBoolean(bit)
    if bit == nil then  -- equals 0
        return false
    end
    return (bit > 0)
end

-- support "and","or","xor"
-- eg: print(BitOperate(128,192,"and"))
-- $$:  128	10000000
function BitOperate(num1, num2, oper)

    if not (oper and type(oper) == "string") then return end

    local oper_lower = string.lower(oper)

    if not (oper_lower == "and" or oper_lower == "or" or oper_lower == "xor") then return end

    local bin_rev_table1 = DecToBinTable(num1,true)
    local bin_rev_table2 = DecToBinTable(num2,true)
    local result_rev_table = {}

    local max_len = math.max(#(bin_rev_table1),#(bin_rev_table2))
    for i=1, max_len, 1 do
        if oper_lower == "and" then
            result_rev_table[i] = (BitToBoolean(bin_rev_table1[i]) and BitToBoolean(bin_rev_table2[i])) and 1 or 0
        elseif  oper_lower == "or" then
            result_rev_table[i] = (BitToBoolean(bin_rev_table1[i]) or BitToBoolean(bin_rev_table2[i])) and 1 or 0
        elseif  oper_lower == "xor" then
            result_rev_table[i] = (BitToBoolean(bin_rev_table1[i]) ~= BitToBoolean(bin_rev_table2[i])) and 1 or 0
        end
    end

    local result_str = table.concat(table.reverse(result_rev_table))
    return BinToDecNum(result_str), result_str
end

-- by lw
function BitAND(a, b)
    local p, c = 1, 0
    while a > 0 and b > 0 do
        local ra, rb = a % 2, b % 2
        if ra + rb > 1 then
            c = c + p
        end
        a, b, p = (a - ra) / 2, (b - rb) / 2, p * 2
    end
    return c
end

