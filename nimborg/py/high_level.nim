# A high-level wrapper for python 2.x

# short-term TODO:
#
# * export nimrod values (especially functions) to python (with new python type objects).   
#
# mid-range TODO:
# 
# * don't print exceptions, retrieve the exception information into nimrod
#

import nimborg/py/low_level except expr, stmt
import macros
from strutils import `%`

type
  # A non-borrowed (counted) reference. Avoid copying these around! Nimrod 
  # doesn't have the equivalent of an assignment constructor (yet?), so any
  # copy of a PyRef must be counted (use dup for that). For this reason,
  # we add a level of indirection, and represent python objects as PPyRef,
  # which can be copied freely.
  PyRef = object {.inheritable, byref.} 
    p: PPyObject
  PPyRef* = ref PyRef

  EPython = object of E_Base
  EPyNotSupported = object of EPython # operation requested not supported 
                                      # by the recepient python object
  EPyTypeError = object of EPython

  Context = object 
    globals*, locals*: PPyRef 
  PContext = ref Context

# forward declarations
proc getattr*(o: PPyRef, field: cstring): PPyRef
proc setattr*(o: PPyRef, field: cstring, val: PPyRef): void
proc eval*(c: PContext, src: cstring): PPyRef
proc `[]`*(v: PPyRef, key: PPyRef): PPyRef
proc `[]=`*(mapping, key, val: PPyRef): void
proc builtins*(): PPyRef
proc `()`*(f: PPyRef, args: varargs[PPyRef,to_py]): PPyRef {.discardable.}
proc pyDict*(): PPyRef
proc pyList*(size: int): PPyRef
proc `$`*(o: PPyRef): string

#-------------------------------------------------------------------------------
# error handling

proc handleError(s: string) =
  PyErr_Print()
  raise newException(EPython, s)

proc check(p: PPyObject): PPyObject =
  if p == nil: handleError("check(nil)")
  result = p

proc check(x: int): int {.discardable.} =
  if x == -1: handleError("check(-1)")
  result = x

#-------------------------------------------------------------------------------
# lifetime management

proc refCount*(o: PPyRef): int = o.p.ob_refcnt

proc finalizePyRef(o: PPyRef) =
  if o.p != nil:
    Py_DECREF(o.p)
    o.p = nil

proc wrapNew*(p: PPyObject): PPyRef = 
  new(result, finalizePyRef)
  result.p = check(p)

proc dup*(src: PPyRef): PPyRef = 
  new(result, finalizePyRef)
  result.p = src.p
  Py_INCREF(result.p)

#-------------------------------------------------------------------------------
# conversion of nimrod values to/from python values

converter rawPyObject(x: PPyRef): PPyObject = x.p

proc toPy*(x: PPyRef): PPyRef = x
converter toPy*(f: float): PPyRef{.procvar.} = wrapNew(PyFloat_fromDouble(f))
converter toPy*(i: int): PPyRef {.procvar.} = 
  result = wrapNew(PyInt_FromLong(int32(i)))
converter toPy*(s: cstring): PPyRef {.procvar.} = wrapNew(PyString_fromString(s))
converter toPy*(s: string): PPyRef {.procvar.} = wrapNew(toPy(cstring(s)))

proc toList*(vals: openarray[PPyRef]): PPyRef =
  result = pyList(len(vals))
  for i in 0..len(vals)-1:
    let p = vals[i].p
    Py_INCREF(p)
    discard check(PyList_SetItem(result.p, i, p))

# doesn't work as a converter, I don't know why
proc toPy*[T](vals: openarray[T]): PPyRef {.procvar.} = 
  toList(map[T,PPyRef](vals, (proc(x:T): PPyRef = toPy(x))))

converter toPy*[T](vals: seq[T]): PPyRef {.procvar.} = 
  toList(map[T,PPyRef](vals, (proc(x:T): PPyRef = toPy(x))))

proc toTuple*(vals: openarray[PPyRef]): PPyRef = 
  let size = vals.len
  result = wrapNew(PyTuple_New(size))
  for i in 0..size-1:
    let p = vals[i].p
    Py_INCREF(p) # PyTuple_SetItem steals refs
    discard check(PyTuple_SetItem(result.p, i, p))

proc mkTuple*(args: varargs[PPyRef, toPy]): PPyRef = 
  result = toTuple(args)
  
proc `$`*(o: PPyRef): string = 
  let s = wrapNew(PyObject_Str(o.p))
  $PyString_AsString(s.p)

proc toInt*(o: PPyRef): int =
  result = PyInt_AsLong(o.p)
  if result== -1:
    if PyErr_Occurred() != nil:
      handleError("failed conversion to int")

proc toFloat*(o: PPyRef): float =
  result = PyFloat_AsDouble(o.p)
  if result == -1.0:
    if PyErr_Occurred() != nil:
      handleError("failed conversion to float")

proc toBool*(o: PPyRef): bool = (PyObject_IsTrue(o)==1)

#-------------------------------------------------------------------------------
# common object properties

proc getattr*(o: PPyRef, field: cstring): PPyRef =
  wrapNew(PyObject_GetAttrString(o.p, field))

proc setattr*(o: PPyRef, field: cstring, val: PPyRef): void =
  check(PyObject_SetAttrString(o.p, field, val.p))

proc repr*(o: PPyRef): string = $(builtins()["repr"](o))

proc len*(o: PPyRef): int = check(PyObject_Length(o.p))

#-------------------------------------------------------------------------------
# operator overloading

proc `.`*(obj: PPyRef, field: string): PPyRef {.inline.} = 
  getattr(obj, field)
  
proc `.=`*[T](obj: PPyRef, field: string, value: T) {.inline.} = 
  setattr(obj, field, toPy(value))  

macro `.()`*(obj: PPyRef, field: string, args: varargs[PPyRef, toPy]): expr =
  #echo "$1.$2($3 args)" % [$toStrLit(obj), $field, $(cs.len-2)]
  let f = newCall(bindSym"getattr", obj, field)
  result = newCall(f)
  for i in 0..args.len-1:
    result.add(newCall(bindSym"toPy", args[i]))
  #echo toStrLit(result)

proc `()`*(f: PPyRef, args: varargs[PPyRef,toPy]): PPyRef = 
  let args_tup = toTuple(args)
  wrapNew(PyObject_CallObject(f.p, args_tup.p))

proc `[]`*(v: PPyRef, key: PPyRef): PPyRef =
  wrapNew(PyObject_GetItem(v.p, key.p))

proc `[]=`*(mapping, key, val: PPyRef): void =
  discard check(PyObject_SetItem(mapping.p, key.p, val.p))

proc `*`*(a,b:PPyRef): PPyRef = wrapNew(PyNumber_Multiply(a.p,b.p))
proc `+`*(a,b:PPyRef): PPyRef = wrapNew(PyNumber_Add(a.p,b.p))
proc `-`*(a,b:PPyRef): PPyRef = wrapNew(PyNumber_Subtract(a.p,b.p))
proc `/`*(a,b:PPyRef): PPyRef = wrapNew(PyNumber_TrueDivide(a.p,b.p))
proc `%`*(a,b:PPyRef): PPyRef = wrapNew(PyNumber_Remainder(a.p,b.p))
proc `-`*(a:PPyRef): PPyRef = wrapNew(PyNumber_Negative(a.p))
proc `+`*(a:PPyRef): PPyRef = wrapNew(PyNumber_Positive(a.p))
proc abs*(a:PPyRef): PPyRef = wrapNew(PyNumber_Absolute(a.p))
proc `==`*(a:PPyRef,b:PPyRef): PPyRef = wrapNew(PyObject_RichCompare(a.p, b.p, Py_EQ))

#------------------------------------------------------------------------------
# containers

proc pyDict*(): PPyRef = wrapNew(PyDict_New())

proc pyList*(size: int): PPyRef = 
  result = wrapNew(PyList_New(size))
  for i in 0..size-1:
    Py_INCREF(Py_None)
    let err = PyList_SetItem(result.p, i, Py_None)
    assert(err==0)

proc finalizeRawPyBuffer(b: ref TPy_buffer) =
  if b.obj!=nil: PyBuffer_Release(addr(b[]))

proc isPyBufferable*(obj: PPyRef): bool{.inline.} = 
  PyObject_CheckBuffer(obj)

# this is still very low-level. It will take some work to provide a friendly and general
# interface around python's buffers.
proc rawPyBuffer*(obj: PPyRef, flags: cint): ref TPy_buffer =
  new(result, finalizeRawPyBuffer)
  let err = PyObject_GetBuffer(obj, addr(result[]), flags)
  if err == -1:
    result.obj = nil # flag to skip PyBuffer_Release
    result = nil

type
  TypedPyBuffer1D*[T] = object {.byref.}
    pyBuf: TPy_buffer
    nElements*: int
  PTypedPyBuffer1D*[T] = ref TypedPyBuffer1D[T]

proc len*[T](arr: TypedPyBuffer1D[T]): int {.inline.} = arr.nElements

proc `[]`*[T](arr: TypedPyBuffer1D[T], i: int): var T =
  let d = i*sizeof(T)
  if d<arr.pyBuf.length: 
    let p = cast[ptr T](cast[int](arr.pyBuf.buf) + d)
    result = p[]
  else:
    raise newException(EInvalidIndex, 
                       "$* * $* >= $*" % [$i, $sizeof(T), $arr.pyBuf.length])

proc `[]`*[T](arr: PTypedPyBuffer1D[T], i: int): var T {.inline.} = arr[][i]

proc `[]=`*[T](arr: var TypedPyBuffer1D[T], i: int, v: T) {.inline.} =
  let p : ptr T = addr(arr[i])
  p[] = v

proc `[]=`*[T](arr: var PTypedPyBuffer1D[T], i: int, v: T) {.inline.} =
  let p : ptr T = addr(arr[i])
  p[] = v

proc finalizeTypedPyBuffer1D[T](tb: ref TypedPyBuffer1D[T]) =
  if tb.pyBuf.obj!=nil: PyBuffer_Release(addr(tb.pyBuf))

let default_buffer_flags: cint = PyBUF_WRITABLE or PyBUF_FORMAT

template defPyBufferConverter(convName: expr, T: typeDesc, fmt: string): stmt {.immediate.} =
  proc convName*(obj: PPyRef, flags = default_buffer_flags): PTypedPyBuffer1D[T] =
    new(result, finalizeTypedPyBuffer1D)
    result.pyBuf.obj = nil # flag to skip PyBuffer_Release, unless GetBuffer succeeds
    let err = PyObject_GetBuffer(obj, addr(result.pyBuf), flags)
    if err == -1:
      raise newException(EPyNotSupported, 
        "buffer interface not supported with flags " & $flags)
    if ((flags and PyBUF_FORMAT)!=0) and (fmt != $result.pyBuf.format):
      let msg = "expected buffer format $1 but got $2" % [fmt, $result.pyBuf.format]
      raise newException(EPyTypeError, msg)
    result.nElements = result.pyBuf.length div result.pyBuf.itemsize

defPyBufferConverter(float64Buffer, float64, "d")
defPyBufferConverter(float32Buffer, float32, "f")
defPyBufferConverter(uint8Buffer, uint8, "B")

#-------------------------------------------------------------------------------
# importation and evaluation

proc eval*(c: PContext, src: cstring): PPyRef =
  wrapNew(PyRun_String(src, eval_input, c.globals.p, c.locals.p))

proc builtins*(): PPyRef = wrapNew(PyEval_GetBuiltins())
  
proc pyImport*(name: cstring): PPyRef =
  wrapNew(PyImport_ImportModule(name))

proc initContext*(): PContext = 
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

  proc finalizeInterpreter(interpreter: PInterpreter) =
    finalizePython()

  # init_python is not useful yet. Before I let users call this,
  # I must add and maintain a reference to the interpreter
  # in each PyRef, as is done with lua states.
  # The reason is that the python references are unsafe if
  # the interpreter is finalized, so they semantically depend
  # upon the interpreter, even though the interpreter is not
  # passed to the python/C API routines.
  proc initPy(): PInterpreter =
    new(result, finalizeInterpreter)
    initPython()
else:
  # temporary kludge, until I adopt the lua convention
  initPython()
