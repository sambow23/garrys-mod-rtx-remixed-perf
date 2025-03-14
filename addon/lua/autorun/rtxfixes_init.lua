if SERVER then
    cleanup.Register("rtx_lights")
end

if CLIENT then
    require((BRANCH == "x86-64" or BRANCH == "chromium" ) and "RTXFixesBinary" or "RTXFixesBinary_32bit")
end