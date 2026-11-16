## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'more': command 'exec' has two afterSeparator positionals ('command' and 'more'); the words after -- fill one

import clispec

cliProgram(Tool, "tool"):
  subcmd "exec":
    pos command is seq[string], required = false, afterSeparator = true
    pos more is seq[string], required = false, afterSeparator = true  # clispec-invalid
