## Converting command-line text to typed values.
##
## ``parseCliValue(text, value)`` converts one word into a value of the
## parameter's type, or raises ``CliValueError`` saying what was expected.
## The generic version handles ``string``, ``bool``, ``char``, every integer
## and float type (range types included, with their bounds checked), enums,
## distinct types over any of these (``std/paths.Path``, for one) and
## ``Option[T]``. A program teaches clispec another type by declaring a
## non-generic overload in the scope of its description; overload resolution
## prefers it to the generic one:
##
## .. code-block:: nim
##   proc parseCliValue(text: string; value: var Version) =
##     value = parseVersion(text) # raise CliValueError on bad input
##
## ``cliChoiceTexts`` lists the texts an enum accepts, for help, validation
## messages and completion.

import std/[options, strutils, typetraits]

import ./model

type
  CliValueError* = object of ValueError
    ## A word that is not a value of the expected type.
    expected*: string
      ## What would have been accepted (``an integer``, ``one of: a, b``).

proc raiseCliValueError*(expected: string) {.noreturn.} =
  ## Raises a ``CliValueError`` saying what was expected.
  raise (ref CliValueError)(msg: "expected " & expected, expected: expected)

func cliChoiceTexts*[T: enum](t: typedesc[T]): seq[string] =
  ## The text of every value of the enum ``T`` (its ``$``), in order.
  for v in T:
    result.add($v)

func cliValueText*[T](v: T): string =
  ## How a value is shown in help, messages and the closed value sets: its
  ## ``$``, or for a distinct type the ``$`` of its base.
  when T is distinct:
    $distinctBase(T)(v)
  else:
    $v

template cliIsEnum*(T: typedesc): bool =
  ## Whether ``T`` is an enum (for generated code, which cannot spell the
  ## type class ``enum`` as an identifier).
  T is enum

func cliChoiceTextsOf*[E](values: openArray[E]): seq[string] =
  ## The texts of a closed value set's entries (``cliValueText``).
  for v in values:
    result.add(cliValueText(v))

func cliTypeDescription*[T](t: typedesc[T]): string =
  ## What a value of ``T`` is called in an "expected ..." message.
  when T is Option:
    cliTypeDescription(typeof(default(T).get()))
  elif T is distinct:
    cliTypeDescription(distinctBase(T))
  elif T is bool:
    "true or false"
  elif T is enum:
    "one of: " & cliChoiceTexts(T).join(", ")
  elif T is char:
    "a single character"
  elif T is SomeFloat:
    "a number"
  elif T is SomeInteger or T is range:
    when T is SomeUnsignedInt:
      "a non-negative integer"
    else:
      if low(T).BiggestInt == low(BiggestInt) and
          high(T).BiggestInt == high(BiggestInt):
        "an integer"
      else:
        "an integer from " & $low(T) & " to " & $high(T)
  elif T is string:
    "a string"
  else:
    $T

func cliConfigTypeOf*[T](t: typedesc[T]): CliConfigType =
  ## The type a configuration-file value of a parameter of type ``T`` must
  ## have (of each element, for a ``seq``): integers are integers, floats
  ## floats, ``bool`` a bool, and everything else, which is written as text
  ## on the command line, a string.
  when T is seq:
    cliConfigTypeOf(typeof(default(T)[0]))
  elif T is Option:
    cliConfigTypeOf(typeof(default(T).get()))
  elif T is distinct:
    cliConfigTypeOf(distinctBase(T))
  elif T is bool:
    cctBool
  elif T is SomeFloat:
    cctFloat
  elif T is SomeInteger or T is range:
    cctInteger
  else:
    cctString

proc parseCliValue*[T](text: string; value: var T) =
  ## Converts ``text`` to a ``T`` (see the module documentation), raising
  ## ``CliValueError`` when it is not one.
  mixin parseCliValue
  when T is Option:
    var inner: typeof(default(T).get())
    parseCliValue(text, inner)
    value = some(inner)
  elif T is distinct:
    var base: distinctBase(T)
    parseCliValue(text, base)
    value = T(base)
  elif T is string:
    value = text
  elif T is bool:
    case text.toLowerAscii()
    of "true", "yes", "on", "1": value = true
    of "false", "no", "off", "0": value = false
    else: raiseCliValueError(cliTypeDescription(T))
  elif T is enum:
    for v in T:
      if $v == text:
        value = v
        return
    # A style-insensitive match (``--color=Green`` for ``green``), as Nim
    # compares identifiers, but only when it picks one value.
    var found = 0
    for v in T:
      if cmpIgnoreStyle($v, text) == 0:
        value = v
        inc found
    if found != 1:
      raiseCliValueError(cliTypeDescription(T))
  elif T is char:
    if text.len != 1:
      raiseCliValueError(cliTypeDescription(T))
    value = text[0]
  elif T is SomeFloat:
    try:
      value = T(parseFloat(text))
    except ValueError:
      raiseCliValueError(cliTypeDescription(T))
  elif T is SomeUnsignedInt:
    var parsed: BiggestUInt
    try:
      parsed = parseBiggestUInt(text)
    except ValueError:
      raiseCliValueError(cliTypeDescription(T))
    if parsed > BiggestUInt(high(T)):
      raiseCliValueError(cliTypeDescription(T))
    value = T(parsed)
  elif T is SomeInteger or T is range:
    var parsed: BiggestInt
    try:
      parsed = parseBiggestInt(text)
    except ValueError:
      raiseCliValueError(cliTypeDescription(T))
    if parsed < BiggestInt(low(T)) or parsed > BiggestInt(high(T)):
      raiseCliValueError(cliTypeDescription(T))
    value = T(parsed)
  else:
    {.error: "clispec: no parseCliValue for " & $T & "; declare " &
      "`proc parseCliValue(text: string; value: var " & $T & ")`".}
