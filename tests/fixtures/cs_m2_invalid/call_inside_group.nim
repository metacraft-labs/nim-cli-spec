## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: the anonymous `call:` command has no row in help, so it cannot stand in group 'Build Commands'

import clispec

const model {.used.} = plainCliModel:
  group "Build Commands":
    subcmd "build": discard
    call: discard  # clispec-invalid
