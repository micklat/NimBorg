import NimBorg/lua/high_level as lua_hl

let s = lua_hl.new_state()
let d = s.new_table()
d["name"] = "fred"
d["age"] = 42
try:
  echo d # won't work, tables are not natively convertible to string
except lua_hl.ELuaTypeError:
  echo "exception duly raised"
echo d["name"], " ", d["age"]
assert(to_int(d["age"])==42)
