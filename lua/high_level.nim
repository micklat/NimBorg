from low_level/lua import REGISTRYINDEX, Integer, Number
from low_level/lauxlib import NOREF, unref, reference

# TODO: 
#
# * each proc should check that its args belong to the same lua state

type
  # wrap a LuaState in an object, to facilitate future use of destructors:
  LuaState = object {.byref.}
    L*: lua.PState
  PLuaState = ref LuaState

  # A non-borrowed (counted) reference. Avoid copying these around! Nimrod 
  # doesn't have the equivalent of an assignment constructor (yet?), so any
  # copy of a LuaRef must be counted (use dup for that).
  LuaRef = object {.byref.}
    state: PLuaState # prevents the lua state from being GC'd while this ref is alive
    r*: cint
  PLuaRef = ref LuaRef

#-------------------------------------------------------------------------------
# lifetime management

proc finalize_luaref(o: PLuaRef) =
  unref(o.state.L, REGISTRYINDEX, o.r)
  o.r = NOREF

proc pop_ref*(state: PLuaState): PLuaRef {.inline.} =
  new(result, finalize_luaref)
  result.state = state
  result.r = reference(state.L, REGISTRYINDEX)

{.push inline.}
proc lua_push*(s: PLuaState, x:int) = lua.pushinteger(s.L, Integer(x))
proc lua_push*(s: PLuaState, x:string) = lua.pushstring(s.L, x)
proc lua_push*(s: PLuaState, x:cstring) = lua.pushstring(s.L, x)
proc lua_push*(s: PLuaState, x:float) = lua.pushnumber(s.L, x)
proc lua_push*(s: PLuaState, x:bool) = lua.pushboolean(s.L, ord(x))
proc lua_push*(x: PLuaRef): void = 
  lua.rawgeti(x.state.L, REGISTRYINDEX, x.r)

proc len*(x: PLuaRef): cint = lua.objlen(x.state.L, x.r) 

{.pop.}

proc to_ref*[T](state: PLuaState, x:T) : PLuaRef = 
  state.lua_push(x)
  result = pop_ref(state)

proc finalize_luastate(s: PLuaState) =
  if s.L!=nil:
    lua.close(s.L)
    s.L = nil

proc new_state*() : PLuaState =
  let L = lauxlib.newstate()
  if L!=nil:
    new(result, finalize_luastate)
    result.L = L
  else:
    raise newException(EOutOfMemory, "failure in lua_newstate()")

proc new_table*(s: PLuaState): PLuaRef = 
  lua.newtable(s.L)
  result = s.pop_ref

proc `[]=`*[K,V](table: PLuaRef, key: K, val: V): void =
  lua_push(table)
  lua_push(table.state, key)
  lua_push(table.state, val)
  lua.settable(table.state.L, -3)
  lua.pop(table.state.L, 1)
  
proc `[]`*[K](table: PLuaRef, key:K): PLuaRef = 
  let s = table.state
  lua_push(table)
  lua_push(s, key)
  lua.gettable(s.L, -2)
  result = pop_ref(s)
  lua.pop(table.state.L, 1)

#------------------------------

proc to_int*(x: PLuaRef): int = 
  lua_push(x)
  result = lua.tointeger(x.state.L, -1)
  lua.pop(x.state.L, 1)

proc to_float*(x: PLuaRef): lua.Number =
  lua_push(x)
  result = lua.tonumber(x.state.L, -1)
  lua.pop(x.state.L, 1)

proc to_string(x: PLuaRef): string =
  lua_push(x)
  result = $lua.tostring(x.state.L, -1)
  lua.pop(x.state.L, 1)

proc `$`*(x: PLuaRef): string {.inline.} = to_string(x)
