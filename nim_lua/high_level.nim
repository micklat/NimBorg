from low_level/lua import REGISTRYINDEX, Integer, Number
from low_level/lualib import nil
from low_level/lauxlib import NOREF, unref, reference
import macros
from strutils import format, `%`
import nimborg_common

# TODO: 
#
# * override dot
# * more error handling
# * each proc should check that its args belong to the same lua state

type
  # wrap a LuaState in an object, to facilitate future use of destructors:
  LuaState = object {.byref.}
    L: lua.PState
  PLuaState* = ref LuaState

  # A non-borrowed (counted) reference. Avoid copying these around! Nimrod 
  # doesn't have the equivalent of an assignment constructor (yet?), so any
  # copy of a LuaRef must be counted (use dup for that).
  LuaRef = object {.byref.}
    state: PLuaState # prevents the lua state from being GC'd while this ref is alive
    r: cint
  PLuaRef* = ref LuaRef

  ELua* = object of E_Base
  ELuaTypeError* = object of ELua
  ELuaSyntax* = object of ELua
  #ELuaGCMM* = object of ELua # only defined in lua 5.2, the bindings are for 5.1

# forward declarations:
proc call_with_lua_refs*(f: PLuaRef, args: varargs[PLuaRef]): PLuaRef

#------------------------------------------------------------
# lifetime management

proc finalizeLuaRef(o: PLuaRef) =
  unref(o.state.L, REGISTRYINDEX, o.r)
  o.r = NOREF

proc popRef*(state: PLuaState): PLuaRef {.inline.} =
  new(result, finalizeLuaRef)
  result.state = state
  #echo "gettop=", lua.gettop(state.L)
  assert(lua.gettop(state.L)>0)
  result.r = reference(state.L, REGISTRYINDEX)

#------------------------------------------------------------
# pushing stuff into the stack

{.push inline.}

proc luaPush*(s: PLuaState, x:int) = lua.pushinteger(s.L, Integer(x))
proc luaPush*(s: PLuaState, x:string) = lua.pushstring(s.L, x)
proc luaPush*(s: PLuaState, x:cstring) = lua.pushstring(s.L, x)
proc luaPush*(s: PLuaState, x:float) = lua.pushnumber(s.L, x)
proc luaPush*(s: PLuaState, x:bool) = lua.pushboolean(s.L, ord(x))

proc luaPush*(x: PLuaRef): void = 
  assert(x!=nil)
  #echo "calling rawgeti(L, REGISTRYINDEX, $1)" % $x.r
  lua.rawgeti(x.state.L, REGISTRYINDEX, x.r)
  #echo "lua type of returned value is ", lua.luatype(x.state.L, -1)

proc len*(x: PLuaRef): cint = lua.objlen(x.state.L, x.r) 

{.pop.}

proc toRef*[T](state: PLuaState, x:T) : PLuaRef = 
  state.luaPush(x)
  result = popRef(state)

proc openLibs*(s: PLuaState) : void = lualib.openlibs(s.L)

proc finalizeLuaState(s: PLuaState) =
  if s.L!=nil:
    lua.close(s.L)
    s.L = nil

proc newLuaState*(open_std_libs=true) : PLuaState =
  let L = lauxlib.newstate()
  if L==nil:
    raise newException(EOutOfMemory, "failure in lua_newstate()")
  new(result, finalizeLuaState)
  result.L = L
  if open_std_libs: result.openLibs()

proc luaTable*(s: PLuaState): PLuaRef = 
  lua.newtable(s.L)
  result = s.popRef

proc luaError(err_code: int, context = "lua FFI"): void =
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

proc nullaryFunc*(s: PLuaState, lua_expr: string): PLuaRef = 
  let body = "return " & lua_expr
  let err_code = lauxlib.loadstring(s.L, body)
  if err_code == lua.OK: 
    return popRef(s)
  lua.pop(s.L, 1)
  if err_code == lua.ERRSYNTAX: 
    raise newException(ELuaSyntax, "syntax error in: " & body)
  else: 
    luaError(err_code, lua_expr)

proc eval*(s: PLuaState, lua_expr: string): PLuaRef {.discardable.} = 
  call_with_lua_refs(s.nullaryFunc(lua_expr))

#------------------------------

proc toInt*(x: PLuaRef): Integer = 
  luaPush(x)
  result = lua.tointeger(x.state.L, -1)
  lua.pop(x.state.L, 1)

proc toFloat*(x: PLuaRef): Number =
  luaPush(x)
  result = lua.tonumber(x.state.L, -1)
  lua.pop(x.state.L, 1)

proc toString(x: PLuaRef): string =
  luaPush(x)
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
  luaPush(table)
  luaPush(table.state, key)
  luaPush(table.state, val)
  lua.settable(table.state.L, -3)
  lua.pop(table.state.L, 1)
  
proc lookupKey[K](table: PLuaRef, key: K): PLuaRef =
  let s = table.state
  luaPush(table)
  luaPush(s, key)
  lua.gettable(s.L, -2)
  result = popRef(s)
  lua.pop(table.state.L, 1)

proc lookupName(table: PLuaRef, key: cstring): PLuaRef = lookupKey[cstring](table, key)

proc `[]`*[K](table: PLuaRef, key:K): PLuaRef = lookupKey[K](table, key)

proc `$`*(x: PLuaRef): string {.inline.} = toString(x)

proc peek*(s: PLuaState): string =
  if lua.gettop(s.L)==0:
    return "NA"
  let t = lua.luatype(s.L, -1)
  if lua.isstring(s.L, -1) != 0:
    return format("$1{$2}", $lua.tostring(s.L, -1), t)
  return "non-stringable{$1}" % $t
  
proc callWithLuaRefs(f: PLuaRef, args: varargs[PLuaRef]): PLuaRef =
  let s = f.state
  luaPush(f)
  for i in 0..args.len-1:
    luaPush(args[i])
  let err_code = lua.pcall(s.L, cint(args.len), 1, 0)
  if err_code == lua.OK:
    #echo "call result is: ", peek(s)
    result = popRef(s)
  else:
    #echo "call failed ($1)" % $err_code
    let err_text = popRef(s)
    luaError(err_code, toString(err_text))
  assert(result!=nil)

# I need a macro to apply toRef to every argument of a lua function
# converters can't work here because I need the state from the lua function 
# as a parameter for toRef.
macro mkRefsAndCall(f: PLuaRef, args: varargs[expr]): PLuaRef =
  # I avoid a "let" here because of https://github.com/Araq/Nimrod/issues/904
  # instead, there's a "let" in `()`.
  # 
  # this macro produces:
  #   callWithLuaRefs(f, toRef(f.state, arg1), toRef(f.state, arg2), ...))
  #
  result = newCall(bindSym"callWithLuaRefs", f)
  for i in 0..len(args)-1:
    let state = newDotExpr(f, newIdentNode("state"))
    result.add(newCall(bindSym"to_ref", state, args[i]))
  #echo "mkRefsAndCall produced: ", toStrLit(result)
  #echo treeRepr(result)

template workAroundBug904(f: PLuaRef, args: varargs[expr]): PLuaRef = 
  bind mkRefsAndCall
  # I would have preferred to write:
  #   let f_val = f
  #   mkRefsAndCall(f_val, args)
  # but I must avoid 'let' at all costs:
  (proc(f_val: PLuaRef): PLuaRef = mkRefsAndCall(f_val, args))(f)

# Dear reader: I apologize for this. These gymnastics will be removed once 
# https://github.com/Araq/Nimrod/issues/904 is fixed.
template `()`*(f: PLuaRef, args: varargs[expr]): PLuaRef = 
  bind workAroundBug904
  workAroundBug904(f, args)

#-------------------------------------------------------------------------------
# ~a.b : syntactic sugar for a["b"]

# distinguish between accesses to lua objects and to nimrod objects
# based on the object's type.
macro resolveDot(obj: expr, field: string): expr = 
  result = resolveNimrodDot(obj, strVal(field))

macro resolveDot(obj: PLuaRef, field: string): expr = 
  result = newCall(bindSym"lookupName", obj, newStrLitNode(strVal(field)))

macro `~`*(a: expr) : expr {.immediate.} = 
  result = replaceDots(a, bindSym"resolveDot")

