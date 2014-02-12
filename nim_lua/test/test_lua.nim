import nim_lua/high_level as luaHL
from math import pi

let s = luaHL.newLuaState()
let d = s.luaTable
d["name"] = "fred"
d["age"] = 42
try:
  echo d # won't work, tables are not natively convertible to string
except luaHL.ELuaTypeError:
  echo "exception duly raised and caught"
echo d["name"], " ", d["age"]
assert(toInt(d["age"])==42)

s.eval("print('99 bottles of beer on the wall')")

assert(toInt(s.eval("4+3"))==7)
let lua_math = s.eval("math")
let lua_cos = luaMath["cos"]
let lua_sin = s.eval("math.sin")
assert(abs(math.cos(pi/3)-to_float(lua_cos(pi/3))) < 0.000001)
assert(abs(math.sin(pi/6)-to_float(lua_sin(pi/6))) < 0.000001)


