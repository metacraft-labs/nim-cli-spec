## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'target': `default` and `required = true` are mutually exclusive

import clispec

const model {.used.} = plainCliModel:
  call:
    pos target is string, default = "all", required = true  # clispec-invalid
    pos source is string, required = true
    pos extra is string, default = "none"
