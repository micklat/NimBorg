import NimBorg/python/high_level
import math

let interpreter = init_python()

echo "the current working directory is:"
echo(~py_import("os").getcwd())

echo ""

echo "the current python path is:"
let path = ~py_import("sys").path
for i in 0..len(path)-1:
  echo i, " ", path[i]

echo ""

# mix nimrod member access and python member access in the same expression:
let p = (x: 1, y: 1)
var py_pi = ~py_import("math").atan(p.y/p.x)
let nim_pi = float_from_py(4 * py_pi)
let nim_pi2 = 4 * float_from_py(py_pi)
assert(nim_pi==nim_pi2)
assert(nim_pi==math.pi)

# check implicit conversion
assert(float_from_py(4.2)==4.2)

# for some reason, the compiler refuses to apply a converter that
# takes either an array or an openarray as input, so I can only auto-convert
# seqs to PPyRef. Thus, the RHS of assignment can contain seqs, but not 
# arrays.
let d = init_dict()
d["name"] = "fred"
d["age"] = 42
d["coordinates"] = @[10.2, -13.2]
d["phones"] = @["0552-1234567", "1122-7009162"]
echo d
