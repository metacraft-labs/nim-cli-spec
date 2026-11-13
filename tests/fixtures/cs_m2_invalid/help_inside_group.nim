## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: help inside group 'Output' would describe command 'build'

import clispec

const model {.used.} = plainCliModel:
  subcmd "build":
    help "Build things"
    group "Output", help = "Where results go":
      help "Where results go"  # clispec-invalid
      flag output is string
