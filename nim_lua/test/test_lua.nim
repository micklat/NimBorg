import nim_lua/high_level as lua_hl
from math import pi

let s = lua_hl.new_lua_state()
let d = s.lua_table
d["name"] = "fred"
d["age"] = 42
try:
  echo d # won't work, tables are not natively convertible to string
except lua_hl.ELuaTypeError:
  echo "exception duly raised and caught"
echo d["name"], " ", d["age"]
assert(to_int(d["age"])==42)

s.eval("print('99 bottles of beer on the wall')")

assert(to_int(s.eval("4+3"))==7)
let lua_math = s.eval("math")
let lua_cos = lua_math["cos"]
let lua_sin = s.eval("math.sin")
assert(abs(math.cos(pi/3)-to_float(lua_cos(pi/3))) < 0.000001)
assert(abs(math.sin(pi/6)-to_float(lua_sin(pi/6))) < 0.000001)


