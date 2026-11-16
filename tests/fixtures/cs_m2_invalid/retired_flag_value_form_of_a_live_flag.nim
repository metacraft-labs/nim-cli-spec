## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: command 'build': retired '--mode=legacy' is a spelling of flag 'mode' in command 'build'

import clispec

cliProgram(Tool, "tool"):
  subcmd "build":
    flag mode is string, default = "fast"
    retired "--mode=legacy", replacement = "--compat"  # clispec-invalid
