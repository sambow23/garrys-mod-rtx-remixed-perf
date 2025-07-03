#include "gmod_interface.hpp"
#include <cstdio>

extern "C" ILuaShared *get_lua_shared(CreateInterfaceFn createInterface)
{
    return (ILuaShared *)createInterface("LUASHARED003", NULL);
}

extern "C" CLuaInterface *open_lua_interface(ILuaShared *lua, unsigned char type)
{
    return (CLuaInterface *)lua->GetLuaInterface(type);
}

extern "C" void *get_lua_state_from_interface(CLuaInterface *lua)
{
    return lua->lua;
}