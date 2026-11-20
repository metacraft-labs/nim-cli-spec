## The ``relay`` program: it loads the description ``relay_cli.nim``
## exports, from its own command line (the ``load`` overload that takes no
## ``argv``), and prints what it parsed.

import clispec

import ./relay_cli

proc main() =
  let c = try:
      Relay.load()
    except CliHelpRequest as e:
      Relay.printHelp(e)
      quit(0)
    except CliUsageError as e:
      Relay.printError(e)
      quit(2)
  var line = "port=" & $c.port & " quiet=" & $c.quiet & " command=" &
    $c.command
  if c.command == RelayCommand.send:
    line.add(" message=" & c.send.message)
  echo line

main()
