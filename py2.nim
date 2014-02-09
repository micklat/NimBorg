# A high-level wrapper for python 2.x (thus the name "py2.nim" rather than "py.nim")

# short-term TODO:
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

  Context = object 
    globals*, locals*: PPyRef 
  PContext = ref Context

# forward declarations
proc getattr*(o: PPyRef, name: cstring) : PPyRef

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

proc init_dict*(): PPyRef = PyDict_New()
proc init_list*(size: int): PPyRef = PyList_New(size)
proc init_tuple*(size: int): PPyRef = PyTuple_New(size)

converter to_py*(f: float) : PPyRef = PyFloat_fromDouble(f)
converter to_py*(i: int) : PPyRef = PyInt_FromLong(int32(i))
converter to_py*(s: cstring) : PPyRef = PyString_fromString(s)
converter to_py*(s: string) : PPyRef = to_py(cstring(s))

proc to_list*(vals: openarray[PPyRef]): PPyRef =
  result = init_list(len(vals))
  for i in 0..len(vals)-1:
    let p = vals[i].p
    discard check(PyList_SetItem(result.p, i, p))
    Py_INCREF(p)

proc to_py*[T](vals: openarray[T]): PPyRef =
  to_list(map[T,PPyRef](vals, to_py))

converter to_py*[T](vals: seq[T]): PPyRef =
  to_list(map[T,PPyRef](vals, to_py))

proc to_tuple*(vals: openarray[PPyRef]): PPyRef = 
  result = init_tuple(len(vals))
  for i in 0..len(vals)-1:
    let p = vals[i].p
    discard check(PyTuple_SetItem(result.p, i, p))
    Py_INCREF(p) # PyTuple_SetItem steals refs, I don't want that
  
proc `$`*(o: PPyRef) : string = 
  let s = to_PPyRef(PyObject_Str(o.p))
  $PyString_AsString(s.p)

converter from_py_int*(o: PPyRef) : int =
  result = PyInt_AsLong(o.p)
  if result== -1:
    if PyErr_Occurred() != nil:
      handle_error("failed conversion to int")

proc len*(o: PPyRef) : int =
  check(PyObject_Length(o.p))

proc `()`*(f: PPyRef, args: varargs[PPyRef]): PPyRef {.discardable.} = 
  let args_tup = to_tuple(args)
  PyObject_CallObject(f.p, args_tup.p)

# proc `()`*(field: string, obj: PPyRef): PPyRef {.delegator.} =
#   result = getattr(obj, field)

# proc `()`*(field: string, obj: PPyRef, args: varargs[PPyRef]): PPyRef =
#   echo field, " in argful delegator"
#   let args_tup = to_tuple(args)
#   PyObject_CallObject(getattr(obj.p, field).p, args_tup.p)

# This is a temporary kludge until '.' can be overloaded. However,
# it doesn't seem like that's gonna happen until version 1 or even
# later, see the IRC logs for 2014-02-09.
proc replace_dots(a: expr): expr {.compileTime.} =
  #echo(repr(a))
  result = a
  case a.kind
  of nnkDotExpr: 
    expectLen(a, 2)
    expectKind(a[1], nnkIdent)
    result = newCall(!"getattr", replace_dots(a[0]), toStrLit(a[1]))
  of nnkEmpty, nnkNilLit, nnkCharLit..nnkInt64Lit: discard
  of nnkFloatLit..nnkFloat64Lit, nnkStrLit..nnkTripleStrLit: discard
  of nnkIdent, nnkSym, nnkNone: discard
  else:
    result = newNimNode(a.kind)
    for i in 0..a.len-1:
      result.add(replace_dots(a[i]))

macro `~`*(a: expr) : expr {.immediate.} = 
  result = replace_dots(a)
  #echo(repr(result))

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

proc `[]=`*(mapping, key, val: PPyRef): void =
  discard check(PyObject_SetItem(mapping.p, key.p, val.p))

proc eval*(c: PContext, src: cstring) : PPyRef =
  PyRun_String(src, eval_input, c.globals.p, c.locals.p)

proc builtins*() : PPyRef = PyEval_GetBuiltins()
  
proc init_context*() : PContext = 
  new result
  result.locals = init_dict()
  result.globals = init_dict()
  result.globals["__builtins__"] = builtins()
  result.globals["__builtins__"] = builtins()

type
  Interpreter = object {.bycopy.} 

proc make_interpreter() : Interpreter =
  Py_Initialize()
  result = Interpreter()
  
proc destroy(interpreter : Interpreter) {.destructor.} =
  Py_Finalize()

var py_interpreter = make_interpreter()
