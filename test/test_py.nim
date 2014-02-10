import NimBorg/py2
import math

echo "the current working directory is:"
#let getcwd = py_import("os")->getcwd
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


