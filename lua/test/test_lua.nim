import NimBorg/lua/high_level

let s = new_state()
let d = s.new_table()
d["name"] = "fred"
d["age"] = 42
# It doesn't look like lua_tostring would agree to convert any input to string,
# so for now we can only print the table's values, rather than the table itself.
#echo d
echo d["name"], " ", d["age"]
assert(to_int(d["age"])==42)
