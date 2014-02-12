from low_level/lua import REGISTRYINDEX, Integer, Number
from low_level/lualib import nil
from low_level/lauxlib import NOREF, unref, reference
from macros import newCall, gensym, quote, bindSym, len, `[]`, add, `$`,
  newNimNode, newDotExpr, newIdentNode, nnkStmtListExpr, newLetStmt, 
  toStrLit, treeRepr, lispRepr
from strutils import format

# TODO: 
#
# * call functions
# * override dot
# * more error handling
# * each proc should check that its args belong to the same lua state

type
  # wrap a LuaState in an object, to facilitate future use of destructors:
  LuaState = object {.byref.}
    L*: lua.PState
  PLuaState* = ref LuaState

  # A non-borrowed (counted) reference. Avoid copying these around! Nimrod 
  # doesn't have the equivalent of an assignment constructor (yet?), so any
  # copy of a LuaRef must be counted (use dup for that).
  LuaRef = object {.byref.}
    state*: PLuaState # prevents the lua state from being GC'd while this ref is alive
    r*: cint
  PLuaRef* = ref LuaRef

  ELua* = object of E_Base
  ELuaTypeError* = object of ELua
  ELuaSyntax* = object of ELua
  #ELuaGCMM* = object of ELua # only defined in lua 5.2, the bindings are for 5.1

# forward declarations:
proc call_with_lua_refs*(f: PLuaRef, args: varargs[PLuaRef]): PLuaRef

#------------------------------------------------------------
# lifetime management

proc finalize_luaref(o: PLuaRef) =
  unref(o.state.L, REGISTRYINDEX, o.r)
  o.r = NOREF

proc pop_ref*(state: PLuaState): PLuaRef {.inline.} =
  new(result, finalize_luaref)
  result.state = state
  result.r = reference(state.L, REGISTRYINDEX)

#------------------------------------------------------------
# pushing stuff into the stack

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

proc open_libs*(s: PLuaState) : void = lualib.openlibs(s.L)

proc finalize_luastate(s: PLuaState) =
  if s.L!=nil:
    lua.close(s.L)
    s.L = nil

proc new_state*(open_std_libs=true) : PLuaState =
  let L = lauxlib.newstate()
  if L==nil:
    raise newException(EOutOfMemory, "failure in lua_newstate()")
  new(result, finalize_luastate)
  result.L = L
  if open_std_libs: result.open_libs()

proc new_table*(s: PLuaState): PLuaRef = 
  lua.newtable(s.L)
  result = s.pop_ref

proc lua_error(err_code: int, context = "lua FFI"): void =
  case err_code:
    of lua.OK: 
      discard
    of lua.ERRSYNTAX: 
      raise newException(ELuaSyntax, context)
    of lua.ERRMEM:
      raise newException(EOutOfMemory, context)
    else:
      let msg = format("lua thread state=$1, in $2", 
                       err_code, context)
      raise newException(ELua, msg)

proc nullary_func*(s: PLuaState, lua_expr: string): PLuaRef = 
  let body = "return " & lua_expr
  let err_code = lauxlib.loadString(s.L, body)
  if err_code == lua.OK: 
    return pop_ref(s)
  lua.pop(s.L, 1)
  if err_code == lua.ERRSYNTAX: 
    raise newException(ELuaSyntax, "syntax error in: " & body)
  else: 
    lua_error(err_code, lua_expr)

proc eval*(s: PLuaState, lua_expr: string): PLuaRef {.discardable.} = 
  call_with_lua_refs(s.nullary_func(lua_expr))

#------------------------------

proc to_int*(x: PLuaRef): Integer = 
  lua_push(x)
  result = lua.tointeger(x.state.L, -1)
  lua.pop(x.state.L, 1)

proc to_float*(x: PLuaRef): Number =
  lua_push(x)
  result = lua.tonumber(x.state.L, -1)
  lua.pop(x.state.L, 1)

proc to_string(x: PLuaRef): string =
  lua_push(x)
  try:
    if lua.isstring(x.state.L, -1) != 0:
      result = $lua.tostring(x.state.L, -1)
    else:
      raise newException(ELuaTypeError, "This lua object is not immediately convertible to string")
  finally: 
    lua.pop(x.state.L, 1)

#-------------------------------------------------------------------------------
# operators

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

proc `$`*(x: PLuaRef): string {.inline.} = to_string(x)

proc call_with_lua_refs(f: PLuaRef, args: varargs[PLuaRef]): PLuaRef =
  let s = f.state
  lua_push(f)
  for i in 0..args.len-1:
    lua_push(args[i])
  let err_code = lua.pcall(s.L, cint(args.len), 1, 0)
  if err_code == lua.OK:
    result = pop_ref(s)
  else:
    let err_text = pop_ref(s)
    lua_error(err_code, to_string(err_text))

# I need a macro to apply to_ref to every argument of a lua function
# converters can't work here because I need the state from the lua function 
# as a parameter for to_ref.
macro `()`*(f: PLuaRef, args: varargs[expr]): expr =
  # I want something like: 
  # (let temp_f = f; let s = temp_f.state; lua_call(temp_f, to_ref(s, arg1), to_ref(s, arg2), ...))
  # and the last expression is handled with usual operator overloading
  let temp_f = gensym(ident="func")
  let state = gensym(ident="state")
  var call_node = newCall(bindSym"call_with_lua_refs", temp_f)
  for i in 0..len(args)-1:
    call_node.add(newCall(bindSym"to_ref", state, args[i]))
  result = newNimNode(nnkStmtListExpr)
  result.add(newLetStmt(temp_f, f))
  result.add(newLetStmt(state, newDotExpr(f, newIdentNode("state"))))
  result.add(call_node)
  echo lispRepr(result)
  #echo treeRepr(result)
