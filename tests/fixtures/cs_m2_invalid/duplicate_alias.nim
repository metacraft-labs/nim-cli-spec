## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'library': spelling '-l' is already used by 'link'

import clispec

type
  Color = enum
    red, green
  Name = string
  Count = int

const model {.used.} = plainCliModel:
  call:
    flag link is string, alias = "-l"
    flag library is string, alias = "-l"  # clispec-invalid
    flag lib is string, alias = "-L"
