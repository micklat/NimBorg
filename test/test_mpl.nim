import NimBorg/py2
from python import PyList_New

let mpl = py_import("matplotlib")
discard (mpl->plot)(to_py(@[1,2,3,4]), to_py(@[10,11,10,12]))
discard (mpl->title)("plotting example")
discard (mpl->show)()
