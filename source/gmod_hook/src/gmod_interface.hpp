#pragma once

// Forward declarations for Garry's Mod interfaces
typedef void *(*CreateInterfaceFn)(const char *name, int *returnCode);

// Basic interface structure
struct ILuaShared
{
    virtual ~ILuaShared() = default;
    virtual void Init() = 0;
    virtual void Shutdown() = 0;
    virtual void DumpStats() = 0;
    virtual void *CreateLuaInterface(unsigned char, bool) = 0;
    virtual void CloseLuaInterface(void *) = 0;
    virtual void *GetLuaInterface(unsigned char) = 0;
    virtual void *FindLuaInterface(void *) = 0;
    virtual void LoadFile(const char *, const char *, bool, bool) = 0;
    virtual void *GetCache(const char *) = 0;
    virtual void SetCache(const char *, void *) = 0;
    virtual void InvalidateCache(const char *) = 0;
    virtual void EmptyCache() = 0;
};

struct CLuaInterface
{
    void *lua;
    // ... other members we don't need to access directly
};

// External C interface functions
extern "C"
{
    ILuaShared *get_lua_shared(CreateInterfaceFn createInterface);
    CLuaInterface *open_lua_interface(ILuaShared *lua, unsigned char type);
    void *get_lua_state_from_interface(CLuaInterface *lua);
}