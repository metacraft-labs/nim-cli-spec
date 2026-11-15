## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: command 'startBackend': the word 'startBackend' matches 'start_backend' of command 'start_backend' under commandMatching ignoreStyle

import clispec

const model {.used.} = plainCliModel:
  commandMatching ignoreStyle
  subcmd "start_backend":
    pos kind is string
  subcmd "startBackend": pos other is string  # clispec-invalid
  subcmd "start-backend":
    pos third is string
