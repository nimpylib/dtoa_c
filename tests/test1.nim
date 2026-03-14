#[ NIM-BUG: when `nimble test`, `-D` flags will be missing?
import std/unittest

import dtoa_c
var ndigits = 3
proc `==`(dd: float, res: cstring): bool =
  const MyBufLen = 100
  var
    mybuflen = MyBufLen
    buf, buf_end: cstring
    shortbuf: array[MyBufLen, cchar]
    mybuf: cstring = cast[cstring](addr shortbuf[0])
    decpt: c_int
    sign: bool

  # round to a decimal string

  buf = dtoa(dd.cdouble, DTOA_SIGNIFICANT, ndigits.cint, decpt, sign, buf_end)
  defer: freedtoa buf
  echo buf
  buf == res

test "dtoa":
  check 1.23 == cstring"1.23"
]#

