# utilities that may be used by more than one language binding

import macros
from strutils import format
#-------------------------------------------------------------------------------
# support for the `~` macro ("overriding the dot"):

# I found that nimrod doesn't handle overloading very well - it often complains
# about amgiuity where I see none. I therefore have to struggle
# to make it completely clear to the compiler how I want ~a.b(c,d) to be dispatched.
# 
# The language-specific modules will define an appropriate isDynamic macro and a 
# dynamicDot proc. Python wil implement dynamicDot using getattr and lua will
# implement it using `[]`. Then, it will be something along the lines of:
#
# replaceDots(e) will substitute:
#   a.b(x1,..xn) ---> dotAndCall(isDynamic(a), a, "b", x, y)
#   a.b ---> dot(isDynamic(a), a, "b")
#
# template isDynamic(x:expr): int = 0
# template isDynamic(x:PLuaRef): int = 1
# template isDynamic(x:PPyRef): int = 1
#

proc resolveDot*(aIsDynamic: PNimrodNode, a: PNimrodNode, s:PNimrodNode): PNimrodNode {.compileTime.} = 
  assert(aIsDynamic.kind == nnkIntLit)
  if aIsDynamic.intVal==1: 
    result = newCall("dynamicDot", a, s)
  else:
    result = newDotExpr(a, newIdentNode(s.strVal))

macro dotAndCall*(aIsDynamic: int, a:expr, s:string, args: varargs[expr]): expr = 
  echo format("isDynamic($1)==$2", toStrLit(a), toStrLit(aIsDynamic))
  let func = resolveDot(aIsDynamic, a, s)
  echo format("func==$1", toStrLit(func))
  result = newCall(func)
  for i in 0..args.len-1: result.add(args[i])

macro dot*(aIsDynamic: int, a:expr, s: string): expr =
  result = resolveDot(aIsDynamic, a, s)

type
  Replacement = tuple[e: PNimrodNode, wasADotB: Bool]

# This is a temporary kludge until '.' can be overloaded. However,
# it doesn't seem like that's gonna happen until version 1 or even
# later, see the IRC logs for 2014-02-09.
proc replaceDots*(a: PNimrodNode, isDynamicTest: PNimrodNode): Replacement {.compileTime.} =
  # the default case: return a unmodified
  result.e = a
  result.wasADotB = false

  case a.kind
  of nnkDotExpr: 
    expectLen(a, 2)
    expectKind(a[1], nnkIdent)
    # defer the distinction between python member lookup and nimrod member
    # lookup to the type-checking phase.
    #echo("looking up ", repr(a[1]), " in ", repr(replaceDots(a[0]).e, isDynamicTest))
    let obj = replaceDots(a[0], isDynamicTest).e
    let field = toStrLit(a[1])
    # objIsDynamic is a way to ask the type checker whether obj is 
    # a refernece to a dynamic-language value (PLuaRef/PPyRef).
    let objIsDynamic = newCall(isDynamicTest, obj)
    result.e = newCall(bindSym"dot", objIsDynamic, obj, field)
    result.wasADotB = true
  of nnkEmpty, nnkNilLit, nnkCharLit..nnkInt64Lit: discard
  of nnkFloatLit..nnkFloat64Lit, nnkStrLit..nnkTripleStrLit: discard
  of nnkIdent, nnkSym, nnkNone: discard
  else:
    var i = 0
    var first : Replacement
    if a.len>0:
      first = replaceDots(a[0], isDynamicTest)
      i = 1
    if (a.kind==nnkCall) and first.wasADotB:
      # we cannot expand a[0] by itself, since it may be of the form obj.method,
      # in which case the compiler must not try to type-check it without 
      # the arguments a[1..]. We therefore replace the form call(obj.field, a[1], ...)
      # into the form dotAndCall(isDynamic(obj), field, a[1], ...) which will be treated
      # as a whole.
      # first is supposed to be: call("dot", call("isDynamic", obj), obj, field)
      # we replace the "dot" with "dotAndCall" and add a[1..] as arguments,
      assert(first.e.kind == nnkCall) 
      result.e = first.e
      echo "will try to resolve: ", toStrLit(a)
      echo "a[0] reduced to: ", toStrLit(first.e)
      result.e[0] = bindSym"dotAndCall"
    else:
      # a[0] can be expanded without considering a[1..]
      result.e = newNimNode(a.kind)
      if i>0: result.e.add(first.e)
    for j in i .. a.len-1:
      result.e.add(replaceDots(a[j], isDynamicTest).e)
    echo "--> ", toStrLit(result.e)

