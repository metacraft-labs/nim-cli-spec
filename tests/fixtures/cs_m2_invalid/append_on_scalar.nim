## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'jobs': merge = append concatenates lists; int is not a seq

import clispec

const model {.used.} = plainCliModel:
  call:
    flag jobs is int, merge = append  # clispec-invalid
    flag paths is seq[string], merge = append
    flag quiet is int, counted = true, merge = append
