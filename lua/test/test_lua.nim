import NimBorg/lua/high_level

let s = new_state()
let x = s.new_table()
x[1] = 13
echo x[1]
assert(to_int(x[1])==13)
