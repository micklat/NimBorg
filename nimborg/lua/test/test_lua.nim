import nimborg/lua/high_level as luaHL
from math import pi

let s = luaHL.newLuaState()
let d = s.luaTable
d["name"] = "fred"
d["age"] = 42
try:
  echo d # won't work, tables are not natively convertible to string
except luaHL.ELuaTypeError:
  echo "exception duly raised and caught"
echo(~d.name, " ", d["age"])
assert(toInt(~d.age)==42)

s.eval("print('99 bottles of beer on the wall')")

assert(toInt(s.eval("4+3"))==7)
let luaMath = s.eval("math")
let luaCos = luaMath["cos"]
let luaSin = s.eval("math.sin")
assert(abs(math.cos(pi/3)-to_float(luaCos(pi/3))) < 0.000001)
assert(abs(math.sin(pi/6)-to_float(luaSin(pi/6))) < 0.000001)

s.exec("t={foo=1, bar=2}")
echo "~q.foo=", (let q = s.eval("t"); ~q.foo)
assert(to_int(~s.eval("t").bar)==2)
