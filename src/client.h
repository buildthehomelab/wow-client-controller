/* Addresses in Wow.exe 3.3.5a build 12340. Each was read from the disassembly of the stock exe (sha c6f92098). */
#ifndef CLIENT_H
#define CLIENT_H

#include <stdint.h>
#include <stddef.h>

typedef struct lua_State lua_State;
typedef int (*lua_CFunction)(lua_State *);

#define LUA_REGISTRYINDEX (-10000)
#define LUA_GLOBALSINDEX (-10002)
#define LUA_TNIL 0

/* Per-frame handler, registered by "push 0x495810" in the UI's constructor. We change that one immediate, so a
   hook on the function's own first bytes (AwesomeWotlk has one) keeps working whichever DLL loads first. */
#define ADDR_FRAME_PUSH_OPERAND 0x00495F49u
#define ADDR_FRAME_HANDLER 0x00495810u
typedef int (*FrameHandler)(int, int, int, int);

#define CLIENT_FN(ret, addr, ...) ((ret (*)(__VA_ARGS__))(uintptr_t)(addr))

#define GetLuaState CLIENT_FN(lua_State *, 0x00817DB0, void)

#define lua_gettop CLIENT_FN(int, 0x0084DBD0, lua_State *)
#define lua_settop CLIENT_FN(void, 0x0084DBF0, lua_State *, int)
#define lua_pushvalue CLIENT_FN(void, 0x0084DE50, lua_State *, int)
#define lua_type CLIENT_FN(int, 0x0084DEB0, lua_State *, int)
#define lua_tonumber CLIENT_FN(double, 0x0084E030, lua_State *, int)
#define lua_toboolean CLIENT_FN(int, 0x0084E0B0, lua_State *, int)
#define lua_tolstring CLIENT_FN(const char *, 0x0084E0E0, lua_State *, int, size_t *)
#define lua_pushnil CLIENT_FN(void, 0x0084E280, lua_State *)
#define lua_pushnumber CLIENT_FN(void, 0x0084E2A0, lua_State *, double)
#define lua_pushstring CLIENT_FN(void, 0x0084E350, lua_State *, const char *)
#define lua_pushcclosure CLIENT_FN(void, 0x0084E400, lua_State *, lua_CFunction, int)
#define lua_pushboolean CLIENT_FN(void, 0x0084E4D0, lua_State *, int)
#define lua_getfield CLIENT_FN(void, 0x0084E590, lua_State *, int, const char *)
#define lua_createtable CLIENT_FN(void, 0x0084E6E0, lua_State *, int, int)
#define lua_setfield CLIENT_FN(void, 0x0084E900, lua_State *, int, const char *)
#define lua_pcall CLIENT_FN(int, 0x0084EC50, lua_State *, int, int, int)
#define LUA_MULTRET (-1)
/* What FrameScript_Execute uses to compile. 0 is success. */
#define luaL_loadbuffer CLIENT_FN(int, 0x0084F860, lua_State *, const char *, size_t, const char *)

/* Stack layout, from lua_gettop at 0x84DBD0: top at +0x0C, base at +0x10, 16 bytes a value. Each value carries its own
   taint at +0x0C (lua_pushboolean at 0x84E4D0). */
#define LUA_STATE_TOP(L) (*(char **)((char *)(L) + 0x0C))
#define LUA_STATE_BASE(L) (*(char **)((char *)(L) + 0x10))
#define LUA_VALUE_SIZE 16
#define LUA_VALUE_TAINT(slot) (*(uint32_t *)((slot) + 0x0C))

/* The taint of the running Lua code. Protected functions refuse when it isn't 0 (see Script_InteractUnit). */
#define CLIENT_TAINT (*(volatile uint32_t *)(uintptr_t)0x00D4139Cu)
/* While this counter is 0 the client doesn't track taint at all: reading a tainted value, or running an addon's function,
   leaves CLIENT_TAINT alone, so addon code would run clean. The client's own entry points raise it around any Lua
   they run (FrameScript_Execute at 0x819214, the frame-script dispatcher at 0x48EC34), and so must we. */
#define CLIENT_TAINT_DEPTH (*(volatile int32_t *)(uintptr_t)0x00D413A0u)
/* Lua refuses a C function outside this address range. Widened the same way AwesomeWotlk does it. */
#define CLIENT_FUNCTION_RANGE_LOW (*(volatile uint32_t *)(uintptr_t)0x00D415B8u)
#define CLIENT_FUNCTION_RANGE_HIGH (*(volatile uint32_t *)(uintptr_t)0x00D415BCu)

/* 1 while in the world. Cleared just before PLAYER_LEAVING_WORLD fires (0x528C30), set before PLAYER_ENTERING_WORLD
   (0x528010). */
#define CLIENT_IN_WORLD (*(volatile uint8_t *)(uintptr_t)0x00BD0792u)

/* Objects */
#define TYPEMASK_ANY 0x01u
#define TYPEMASK_UNIT 0x08u
#define TYPEMASK_GAMEOBJECT 0x20u

typedef int (*EnumObjectsCallback)(uint64_t guid, void *context);
#define EnumVisibleObjects CLIENT_FN(int, 0x004D4B30, EnumObjectsCallback, void *)
#define ActivePlayerGuid CLIENT_FN(uint64_t, 0x004D3790, void)
#define GetObjectByGuid CLIENT_FN(void *, 0x004D4DB0, uint64_t, uint32_t, const char *, int)
/* Same path as Lua's InteractUnit: selects the object, then its right-click action. Units and gameobjects. */
#define InteractWithGuid CLIENT_FN(int, 0x005277B0, uint64_t)

typedef int (__attribute__((thiscall)) *UnitReactionFn)(void *self, void *other);
#define ClientUnitReaction ((UnitReactionFn)(uintptr_t)0x007251C0u)

typedef void (__attribute__((thiscall)) *GetPositionFn)(void *self, float *position);
#define VTABLE_GET_POSITION 11

/* Descriptor indices, from AzerothCore's UpdateFields.h for 3.3.5a. OBJECT_END = 6. */
#define FIELD_OBJECT_TYPE 2
#define FIELD_UNIT_HEALTH (6 + 0x12)
#define FIELD_UNIT_FLAGS (6 + 0x35)
#define FIELD_UNIT_DYNAMIC_FLAGS (6 + 0x49)
#define FIELD_UNIT_NPC_FLAGS (6 + 0x4C)
#define FIELD_GO_FLAGS (6 + 0x03)
#define FIELD_GO_BYTES_1 (6 + 0x0B)

#define UNIT_DYNFLAG_LOOTABLE 0x1u
#define UNIT_FLAG_NOT_SELECTABLE 0x02000000u
#define UNIT_FLAG_SKINNABLE 0x04000000u
#define GO_FLAG_NOT_SELECTABLE 0x10u

#endif
