## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: command 'build': an example needs its help

import clispec

const model {.used.} = plainCliModel:
  subcmd "build":
    example "tool build app", help = "Build the app"
    example "tool build lib"  # clispec-invalid
