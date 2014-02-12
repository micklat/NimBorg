import NimBorg/lua/high_level as lua_hl
from math import pi

let s = lua_hl.new_state()
let d = s.new_table
d["name"] = "fred"
d["age"] = 42
try:
  echo d # won't work, tables are not natively convertible to string
except lua_hl.ELuaTypeError:
  echo "exception duly raised"
echo d["name"], " ", d["age"]
assert(to_int(d["age"])==42)

s.eval("print('99 bottles of beer on the wall')")

assert(to_int(s.eval("4+3"))==7)
let lua_math = s.eval("math")
let lua_cos = lua_math["cos"]
let lua_sin = s.eval("math.sin")
echo call_with_lua_refs(lua_cos, to_ref(lua_cos.state, pi/3))
echo call_with_lua_refs(lua_sin, to_ref(lua_cos.state, pi/6))

when false:
  # this currently fails due to https://github.com/Araq/Nimrod/issues/904
  echo lua_cos(pi/3), lua_sin(pi/6)


