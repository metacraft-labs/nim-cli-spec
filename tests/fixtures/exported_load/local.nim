## A program whose description is not exported: declared and loaded (the
## ``load`` overload that takes no ``argv``) in the same module.

import clispec

cliProgram(Local, "local"):
  flag count is int, default = 1, help = "How many"

let c = try:
    Local.load()
  except CliHelpRequest as e:
    Local.printHelp(e)
    quit(0)
  except CliUsageError as e:
    Local.printError(e)
    quit(2)
echo "count=" & $c.count
