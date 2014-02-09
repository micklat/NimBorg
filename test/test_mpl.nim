import NimBorg/py2
from python import PyList_New

let n = 100
let lx = new_list(n)
let ly = new_list(n)
let sin = ~py_import("math").sin
for i in 1..n:
  ~lx.append(float(i)*0.1)
  ~ly.append(sin(lx[-1]))
let mpl = py_import("matplotlib")
~mpl.plot(lx, ly)
#~mpl.plot(to_py(@[1,2,3,4]), to_py(@[10,11,10,12]))
~mpl.title("plotting example")
~mpl.show()
