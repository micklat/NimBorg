# A high-level wrapper for python 2.x

# short-term TODO:
#
# * support more of the API
#
# mid-range TODO:
# 
# * don't print exceptions, retrieve the exception information into nimrod
#

import nim_py/low_level except expr
import nimborg_common
import macros

type
  # A non-borrowed (counted) reference. Avoid copying these around! Nimrod 
  # doesn't have the equivalent of an assignment constructor (yet?), so any
  # copy of a PyRef must be counted (use dup for that).
  PyRef = object {.inheritable, byref.} 
    p: PPyObject
  PPyRef* = ref PyRef

  EPython = object of E_Base

  Context = object 
    globals*, locals*: PPyRef 
  PContext = ref Context

# forward declarations
proc getattr*(o: PPyRef, name: cstring) : PPyRef
proc eval*(c: PContext, src: cstring) : PPyRef
proc `[]`*(v: PPyRef, key: PPyRef) : PPyRef
proc `[]=`*(mapping, key, val: PPyRef): void
proc builtins*() : PPyRef
proc `()`*(f: PPyRef, args: varargs[PPyRef,to_py]): PPyRef {.discardable.}
proc pyDict*(): PPyRef
proc pyList*(size: int): PPyRef
proc `$`*(o: PPyRef) : string

#-------------------------------------------------------------------------------
# error handling

proc handleError(s : string) =
  PyErr_Print()
  raise newException(EPython, s)

proc check(p: PPyObject) : PPyObject =
  if p == nil: handleError("check(nil)")
  result = p

proc check(x: int) : int =
  if x == -1: handleError("check(-1)")
  result = x

#-------------------------------------------------------------------------------
# lifetime management

proc refCount*(o: PPyRef): int = o.p.ob_refcnt

proc finalizePyRef(o: PPyRef) =
  if o.p != nil:
    Py_DECREF(o.p)
    o.p = nil

converter toPPyRef*(p: PPyObject) : PPyRef = 
  new(result, finalizePyRef)
  result.p = check(p)

proc dup*(src: PPyRef) : PPyRef = 
  new(result, finalizePyRef)
  result.p = src.p
  Py_INCREF(result.p)

#-------------------------------------------------------------------------------
# conversion of nimrod values to/from python values

proc toPy*(x: PPyRef) : PPyRef = x
converter toPy*(f: float) : PPyRef{.procvar.} = PyFloat_fromDouble(f)
converter toPy*(i: int) : PPyRef {.procvar.} = 
  result = PyInt_FromLong(int32(i))
converter toPy*(s: cstring) : PPyRef {.procvar.} = PyString_fromString(s)
converter toPy*(s: string) : PPyRef {.procvar.} = toPy(cstring(s))

proc to_list*(vals: openarray[PPyRef]): PPyRef =
  result = pyList(len(vals))
  for i in 0..len(vals)-1:
    let p = vals[i].p
    Py_INCREF(p)
    discard check(PyList_SetItem(result.p, i, p))

# doesn't work as a converter, I don't know why
proc toPy*[T](vals: openarray[T]): PPyRef {.procvar.} = 
  to_list(map[T,PPyRef](vals, (proc(x:T): PPyRef = toPy(x))))

converter toPy*[T](vals: seq[T]): PPyRef {.procvar.} = 
  to_list(map[T,PPyRef](vals, (proc(x:T): PPyRef = toPy(x))))

proc toTuple*(vals: openarray[PPyRef]): PPyRef = 
  let size = vals.len
  result = PyTuple_New(size)
  for i in 0..size-1:
    let p = vals[i].p
    Py_INCREF(p) # PyTuple_SetItem steals refs
    discard check(PyTuple_SetItem(result.p, i, p))
  
proc `$`*(o: PPyRef) : string = 
  let s = toPPyRef(PyObject_Str(o.p))
  $PyString_AsString(s.p)

proc intFromPy*(o: PPyRef) : int =
  result = PyInt_AsLong(o.p)
  if result== -1:
    if PyErr_Occurred() != nil:
      handleError("failed conversion to int")

proc floatFromPy*(o: PPyRef) : float =
  result = PyFloat_AsDouble(o.p)
  if result == -1.0:
    if PyErr_Occurred() != nil:
      handleError("failed conversion to float")

#-------------------------------------------------------------------------------
# ~a.b : syntactic sugar for getattr(a,"b")

# distinguish between accesses to python objects and to nimrod objects
# based on the object's type.
macro resolveDot(obj: expr, field: string): expr = 
  result = resolveNimrodDot(obj, strVal(field))

macro resolveDot(obj: PPyRef, field: string): expr = 
  result = newCall(bindSym"getattr", obj, newStrLitNode(strVal(field)))

macro `~`*(a: expr) : expr {.immediate.} = 
  result = replaceDots(a, bindSym"resolveDot")

#-------------------------------------------------------------------------------
# common object properties

proc getattr*(o: PPyRef, name: cstring) : PPyRef =
  result = toPPyRef(PyObject_GetAttrString(o.p, name))

proc repr*(o: PPyRef): string = $(builtins()["repr"](o))

proc len*(o: PPyRef) : int =
  check(PyObject_Length(o.p))

#-------------------------------------------------------------------------------
# operator overloading

proc `()`*(f: PPyRef, args: varargs[PPyRef,toPy]): PPyRef = 
  let args_tup = toTuple(args)
  PyObject_CallObject(f.p, args_tup.p)

proc `[]`*(v: PPyRef, key: PPyRef) : PPyRef =
  toPPyRef(PyObject_GetItem(v.p, key.p))

proc `[]=`*(mapping, key, val: PPyRef): void =
  discard check(PyObject_SetItem(mapping.p, key.p, val.p))

proc `*`*(a,b:PPyRef): PPyRef = PyNumber_Multiply(a.p,b.p)
proc `+`*(a,b:PPyRef): PPyRef = PyNumber_Add(a.p,b.p)
proc `-`*(a,b:PPyRef): PPyRef = PyNumber_Subtract(a.p,b.p)
proc `/`*(a,b:PPyRef): PPyRef = PyNumber_TrueDivide(a.p,b.p)
proc `%`*(a,b:PPyRef): PPyRef = PyNumber_Remainder(a.p,b.p)
proc `-`*(a:PPyRef): PPyRef = PyNumber_Negative(a.p)
proc `+`*(a:PPyRef): PPyRef = PyNumber_Positive(a.p)
proc abs*(a:PPyRef): PPyRef = PyNumber_Absolute(a.p)

#------------------------------------------------------------------------------
# containers

proc pyDict*(): PPyRef = PyDict_New()

proc pyList*(size: int): PPyRef = 
  result = PyList_New(size)
  for i in 0..size-1:
    Py_INCREF(Py_None)
    let err = PyList_SetItem(result.p, i, Py_None)
    assert(err==0)

#-------------------------------------------------------------------------------
# importation and evaluation

proc eval*(c: PContext, src: cstring) : PPyRef =
  PyRun_String(src, eval_input, c.globals.p, c.locals.p)

proc builtins*() : PPyRef = PyEval_GetBuiltins()
  
proc pyImport*(name : cstring) : PPyRef =
  PyImport_ImportModule(name)

proc initContext*() : PContext = 
  new result
  result.locals = pyDict()
  result.globals = pyDict()
  result.globals["__builtins__"] = builtins()
  result.globals["__builtins__"] = builtins()

const 
  GC_the_python_interpreter = false

when GC_the_python_interpreter:
  type
    Interpreter = object {.bycopy.} 
    PInterpreter* = ref Interpreter

  proc finalizeInterpreter(interpreter : PInterpreter) =
    Py_Finalize()

  # init_python is not useful yet. Before I let users call this,
  # I must add and maintain a reference to the interpreter
  # in each PyRef, as is done with lua states.
  # The reason is that the python references are unsafe if
  # the interpreter is finalized, so they semantically depend
  # upon the interpreter, even though the interpreter is not
  # passed to the python/C API routines.
  proc init_python() : PInterpreter =
    new(result, finalizeInterpreter)
    Py_Initialize()
else:
  # temporary kludge, until I adopt the lua convention
  Py_Initialize()
