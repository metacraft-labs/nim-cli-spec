## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: group 'Build' lists both command 'build' and parameter 'jobs'; a group lists subcommands or parameters, not both

import clispec

const model {.used.} = plainCliModel:
  group "Build":
    subcmd "build": discard
  subcmd "test":
    group "Build":
      discard
      flag jobs is int  # clispec-invalid
    flag seed is int
