if not CLIENT then return end

print("\n[Matrix Debug] Testing GMod Matrix type...")

local m = Matrix()
m:Translate(Vector(10, 20, 30))

print("\n[Matrix Debug] Matrix object:")
PrintTable(getmetatable(m))

print("\n[Matrix Debug] Trying to access matrix values...")

-- Try direct indexing
print("Direct index m[1]:", m[1])

-- Try GetField
if m.GetField then
    print("Has GetField method")
    for row = 1, 4 do
        for col = 1, 4 do
            local val = m:GetField(row, col)
            print(string.format("  GetField(%d, %d) = %s", row, col, tostring(val)))
        end
    end
end

-- Try ToTable
if m.ToTable then
    print("\nHas ToTable method:")
    local t = m:ToTable()
    PrintTable(t)
end

-- Try direct table-like access
print("\nTrying table-like access:")
for i = 1, 4 do
    print(string.format("m[%d] = %s (type: %s)", i, tostring(m[i]), type(m[i])))
    if type(m[i]) == "table" then
        for j = 1, 4 do
            print(string.format("  m[%d][%d] = %s", i, j, tostring(m[i][j])))
        end
    end
end

-- Check what methods exist
print("\nAvailable methods:")
for k, v in pairs(getmetatable(m).__index or {}) do
    if type(v) == "function" then
        print("  " .. k)
    end
end
