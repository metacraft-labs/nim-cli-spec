## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: the root command: retired word 'help' asks for the help under parsing helpWord

import clispec

cliProgram(Tool, "tool"):
  parsing helpWord
  subcmd "switch":
    pos name is string
  retired "help", replacement = "tool --help"  # clispec-invalid
