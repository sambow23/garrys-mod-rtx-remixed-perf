if not CLIENT then return end
-- Store the original functions
local _G_old = {
    ErrorNoHalt = ErrorNoHalt,
    Error = Error,
    Msg = Msg,
    MsgC = MsgC,
    print = print
}

local suppressPattern = "CMaterial::DrawElements: No bound shader for engine/occlusionproxy"

local function shouldSuppress(...)
    local args = {...}
    for i, v in ipairs(args) do
        if type(v) == "string" and v:find(suppressPattern, 1, true) then
            return true
        end
    end
    return false
end

-- Override all possible output functions
function ErrorNoHalt(...)
    if not shouldSuppress(...) then
        _G_old.ErrorNoHalt(...)
    end
end

function Error(...)
    if not shouldSuppress(...) then
        _G_old.Error(...)
    end
end

function Msg(...)
    if not shouldSuppress(...) then
        _G_old.Msg(...)
    end
end

function MsgC(...)
    if not shouldSuppress(...) then
        _G_old.MsgC(...)
    end
end

function print(...)
    if not shouldSuppress(...) then
        _G_old.print(...)
    end
end

-- Also try to override the registry error function
if debug and debug.getregistry then
    local registry = debug.getregistry()
    if registry.ErrorNoHalt then
        local old = registry.ErrorNoHalt
        registry.ErrorNoHalt = function(...)
            if not shouldSuppress(...) then
                old(...)
            end
        end
    end
end
