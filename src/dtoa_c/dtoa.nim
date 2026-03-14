##[
  We use origin dtoa.c over Python's
]##

import pkg/autoconf_sugars/short_float_repr
import pkg/autoconf_sugars/floats

const threads = compileOption("threads")
when threads:
  import std/locks
  var dtoa_locks: array[2, Lock]
  for l in dtoa_locks.mitems:
    l.initLock

  proc ACQUIRE_DTOA_LOCK*(n: c_int){.exportc.} = dtoa_locks[n].acquire()
  proc FREE_DTOA_LOCK*(n: c_int){.exportc.} = dtoa_locks[n].release()
  const threadnoInC = "dtoa_get_threadno"
  proc getThreadId*: c_int{.exportc: threadnoInC.} = c_int system.getThreadId()

const Cflags = block:
  var cflags = ""
  const Dpre = # TODO: use `#define` to C code, maybe there's compiler rejects /D,-D
    when defined(vcc): " /D"
    else: " -D"

  template addD(sym) =
      cflags.add Dpre
      cflags.add astToStr sym
  template define(sym, cond) =
    when cond:
      addD sym

  template defineVal(sym, val) =
    addD sym
    cflags.add "="
    cflags.add val
  template defineVal(sym) = defineVal(sym, astToStr sym)
  
  define MULTIPLE_THREADS, threads
  when threads:
    # need to define ACQUIRE_DTOA_LOCK(n) and FREE_DTOA_LOCK(n) where n is 0 or 1
    defineVal ACQUIRE_DTOA_LOCK
    defineVal FREE_DTOA_LOCK
    defineVal dtoa_get_threadno, threadnoInC

  #[ This code should also work for ARM mixed-endian format on little-endian
    machines, where doubles have byte order 45670123 (in increasing address
    order, 0 being the least significant byte). ]#
  define IEEE_8087, DOUBLE_IS_LITTLE_ENDIAN_IEEE754
  define IEEE_MC68k,  DOUBLE_IS_BIG_ENDIAN_IEEE754 or DOUBLE_IS_ARM_MIXED_ENDIAN_IEEE754
  cflags

{.compile("dtoa-nim.c", Cflags).}

type
  DtoaMode* = enum
    ##[
        - 0 ==> shortest string that yields d when read in
          and rounded to nearest.
        - 1 ==> like 0, but with Steele & White stopping rule;
          e.g. with IEEE P754 arithmetic , mode 0 gives
          1e23 whereas mode 1 gives 9.999999999999999e22.
        - 2 ==> max(1,ndigits) significant digits.  This gives a
          return value similar to that of ecvt, except
          that trailing zeros are suppressed.
        - 3 ==> through ndigits past the decimal point.  This
          gives a return value similar to that from fcvt,
          except that trailing zeros are suppressed, and
          ndigits can be negative.
        - 4,5 ==> similar to 2 and 3, respectively, but (in
          round-nearest mode) with the tests of mode 0 to
          possibly return a shorter string that rounds to d.
          With IEEE arithmetic and compilation with
          -DHonor_FLT_ROUNDS, modes 4 and 5 behave the same
          as modes 2 and 3 when FLT_ROUNDS != 1.
        - 6-9 ==> Debugging modes similar to mode - 4:  don't try
          fast floating-point estimate (if applicable).
    ]##
    DTOA_SHORTEST = 0.cint  ## ignores `ndigits` parameter
    DTOA_SHORTEST_STICKY

    DTOA_SIGNIFICANT  ## `ndigits` means significant digits
    DTOA_DECIMAL      ## `ndigits` means digits after decimal point

    DTOA_SHORTEST_OR_SIGNIFICANT
    DTOA_SHORTEST_OR_DECIMAL

    DTOA_DEBUG_SHORTEST
    DTOA_DEBUG_SIGNIFICANT
    DTOA_DEBUG_DECIMAL
    DTOA_DEBUG_SHORTEST_OR_SIGNIFICANT

proc dtoa_r*(
    dd: cdouble,
    mode: DtoaMode, ndigits: cint,
    decpt, sign: var cint, rve: var cstring,
    buf: cstring; blen: csize_t
): cstring {.importc: "dtoa_r", cdecl, discardable.} ##[ ```c
char* dtoa_r(double dd, int mode, int ndigits, int *decpt, int *sign, char **rve, char *buf, size_t blen)
```]##


proc dtoaImpl(
    d: cdouble,
    mode: DtoaMode, ndigits: cint,
    decpt, sign: var cint, rve: var cstring
  ): cstring{.importc: "dtoa", cdecl.} ##[ ```c
char* dtoa(double d, int mode, int ndigits, int *decpt, int *sign, char **rve)
```]##

template dtoa*(
    d: cdouble,
    mode: DtoaMode, ndigits: cint,
    decpt: var cint, sign: var bool, rve: var cstring
): cstring =
  bind dtoaImpl
  bind Py_SET_53BIT_PRECISION_HEADER, Py_SET_53BIT_PRECISION_START, Py_SET_53BIT_PRECISION_END
  block:
    Py_SET_53BIT_PRECISION_HEADER

    Py_SET_53BIT_PRECISION_START
    var signc: cint
    let buf = dtoaImpl(d, mode, ndigits, decpt, signc, rve)
    sign = bool signc
    Py_SET_53BIT_PRECISION_END
    buf

proc strtodImpl(
  s00: cstring, se: var cstring # for `strtod(s, nil)`
): cdouble{.importc: "nimpylib_dtoa_strtod", cdecl.} ##[ ```c
double strtod(const char *s00, char **se)
```]##

template strtod*(
  s00: cstring, se: var cstring # for `strtod(s, nil)`
): cdouble =
  bind strtodImpl
  bind Py_SET_53BIT_PRECISION_HEADER, Py_SET_53BIT_PRECISION_START, Py_SET_53BIT_PRECISION_END
  block:
    Py_SET_53BIT_PRECISION_HEADER

    Py_SET_53BIT_PRECISION_START
    let result = strtodImpl(s00, se)
    Py_SET_53BIT_PRECISION_END
    result

template strtod*(
  s00: cstring
): cdouble =
  var tmp: cstring
  strtod(s00, tmp)

proc freedtoa*(s: cstring){.importc, cdecl.}

