## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: command 'build': a retired spelling is listed nowhere, so it cannot stand in group 'Output'

import clispec

cliProgram(Tool, "tool"):
  subcmd "build":
    group "Output":
      flag format is string, default = "text"
      retired "--fmt", replacement = "--format"  # clispec-invalid
