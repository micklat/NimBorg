# A high-level wrapper for python 2.x (thus the name "py2.nim" rather than "py.nim")

# shrot-term TODO:
#
# * check whether the destructor gets called at all
# * support more of the API
#
# mid-range TODO:
# 
# * don't print exceptions, retrieve the exception information into nimrod
#
# long-range TODO:
# * find a better syntax for member access
#

import python except expr
import macros

type
  # A non-borrowed (counted) reference. Avoid copying these around! Nimrod doesn't have
  # the equivalent of an assignment constructor (yet?), so any copy of PyRef must be counted (use dup for that).
  PyRef = object {.inheritable, byref.} 
    p: PPyObject
  PPyRef* = ref PyRef

  EPyException = object of E_Base

proc handle_error(s : string) =
  PyErr_Print()
  raise newException(EPyException, s)

proc check(p: PPyObject) : PPyObject =
  if p == nil: handle_error("check(nil)")
  result = p

proc check(x: int) : int =
  if x == -1: handle_error("check(-1)")
  result = x

converter to_PPyRef*(p: PPyObject) : PPyRef = 
  new result
  result.p = check(p)

converter to_py*(f: float) : PPyRef = PyFloat_fromDouble(f)
converter to_py*(i: int) : PPyRef = PyInt_FromLong(int32(i))
converter to_py*(s: cstring) : PPyRef = PyString_fromString(s)
converter to_py*(s: string) : PPyRef = to_py(cstring(s))

converter to_list*(vals: openarray[PPyRef]): PPyRef =
  result = PyList_New(len(vals))
  for i in 0..len(vals)-1:
    let p = vals[i].p
    discard check(PyList_SetItem(result.p, i, p))
    Py_INCREF(p)

converter to_py*[T](vals: openarray[T]): PPyRef =
  to_list(map[T,PPyRef](vals, to_py))

converter to_py*[T](vals: seq[T]): PPyRef =
  to_list(map[T,PPyRef](vals, to_py))

converter to_tuple*(vals: openarray[PPyRef]): PPyRef = 
  new result
  result.p = check(PyTuple_New(len(vals)))
  for i in 0..len(vals)-1:
    let p = vals[i].p
    discard check(PyTuple_SetItem(result.p, i, p))
    Py_INCREF(p) # the tuple 'steals' references
  
proc `$`*(o: PPyRef) : string = 
  let s = to_PPyRef(PyObject_Str(o.p))
  $PyString_AsString(s.p)

converter from_py_int*(o: PPyRef) : int = PyInt_AsLong(o.p)

proc len*(o: PPyRef) : int =
  check(PyObject_Length(o.p))

proc `()`*(f: PPyRef, args: varargs[PPyRef]): PPyRef = 
  let args_tup = to_tuple(args)
  PyObject_CallObject(f.p, args_tup.p)

macro `->`*(a: expr, b:expr) : expr {.immediate.} =
  let name = toStrLit(b)
  result = newNimNode(nnkCall)
  result.add(newIdentNode("getattr"))
  result.add(a)
  result.add(name)

proc dup*(src: PPyRef) : PPyRef = 
  new result
  result.p = src.p
  Py_INCREF(result.p)

proc destroy(o: var PyRef) {.destructor.} =
  if o.p != nil:
    echo "decrefing"
    Py_DECREF(o.p)
    o.p = nil

proc getattr*(o: PPyRef, name: cstring) : PPyRef =
  result = to_PPyRef(PyObject_GetAttrString(o.p, name))

proc py_import*(name : cstring) : PPyRef =
  PyImport_ImportModule(name)

proc `[]`*(v: PPyRef, key: PPyRef) : PPyRef =
  to_PPyRef(PyObject_GetItem(v.p, key.p))

type
  Interpreter = object {.bycopy.} 

proc make_interpreter() : Interpreter =
  Py_Initialize()
  result = Interpreter()
  
proc destroy(interpreter : Interpreter) {.destructor.} =
  Py_Finalize()

var py_interpreter = make_interpreter()
