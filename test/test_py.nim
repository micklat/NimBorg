import NimBorg/py2

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
let py_math = py_import("math")
let p = (x: 1, y: 1)
let my_pi = 4 * ~py_math.atan(p.y/p.x)
echo("pi=", my_pi)

