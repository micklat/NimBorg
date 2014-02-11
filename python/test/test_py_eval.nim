import NimBorg/python/high_level

let interpreter = init_python()
let c = init_context()
c.globals["x"] = 42
c.locals["y"] = 10
let res = $c.eval("float(x)/y**2")
echo res
assert(res=="0.42")
