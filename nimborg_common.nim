# utilities that may be used by more than one language binding

import macros

# rewrite: a.b ---> lookup(a, "b")
#
# This is a temporary kludge until '.' can be overloaded. However,
# it doesn't seem like that's gonna happen until version 1 or even
# later, see the IRC logs for 2014-02-09.
proc replaceDots*(a: expr, lookup: expr): expr {.compileTime.} =
  #echo(repr(a))
  result = a
  case a.kind
  of nnkDotExpr: 
    expectLen(a, 2)
    expectKind(a[1], nnkIdent)
    # defer the distinction between python member lookup and nimrod member
    # lookup to the type-checking phase.
    #echo("looking up ", repr(a[1]), " in ", repr(replaceDots(a[0], lookup)))
    result = newCall(lookup, replaceDots(a[0], lookup), toStrLit(a[1]))
  of nnkEmpty, nnkNilLit, nnkCharLit..nnkInt64Lit: discard
  of nnkFloatLit..nnkFloat64Lit, nnkStrLit..nnkTripleStrLit: discard
  of nnkIdent, nnkSym, nnkNone: discard
  else:
    result = newNimNode(a.kind)
    for i in 0..a.len-1:
      result.add(replaceDots(a[i], lookup))

proc resolveNimrodDot*(obj: expr, field: string): expr {.compileTime.} = 
  result = newDotExpr(obj, newIdentNode(field))
  #echo "re-created ", repr(result)
