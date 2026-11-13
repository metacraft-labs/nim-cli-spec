## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'schemaName': configuration key 'schema' is reserved

import clispec

cliProgram(Tool, "tool"):
  configSchema "tool.config.v1"
  flag schemaName is string, key = "schema"  # clispec-invalid
  flag extras is string, key = "extra.things"
