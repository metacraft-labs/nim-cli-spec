## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'mode': acceptsNextWord applies to a flag with an optionalValue (one whose value may be left out)

import clispec

const model {.used.} = plainCliModel:
  flag mode is string, acceptsNextWord = true  # clispec-invalid
  flag level is string, optionalValue = "on", acceptsNextWord = true
