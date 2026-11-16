## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: the anonymous `call:` command has no row in its holder's help, so it has no tier

import clispec

const model {.used.} = plainCliModel:
  subcmd "build", tier = secondary:
    call(tier = secondary): discard  # clispec-invalid
    subcmd "all": discard
