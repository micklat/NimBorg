import NimBorg/py2

echo "the current working directory is:"
#let getcwd = py_import("os")->getcwd
echo(~py_import("os").getcwd())

echo ""

echo "the current python path is:"
let path = ~py_import("sys").path
for i in 0..len(path)-1:
  echo i, " ", path[i]
