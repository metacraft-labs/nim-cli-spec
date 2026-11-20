## test_cs_m7_completion_install_locations: ``clispec/completion_install``
## gives the documented file name, per-user targets and system-wide
## directories for each shell and platform family, honours the variables
## that move the per-user locations, and quotes every name and path in the
## blocks it writes.
##
## Hermetic: the module is pure, the environment is passed in as a table, and
## no file is read or written. Nothing is mocked. The expected paths are the
## shells' own documented locations, cited in the module's documentation.

import std/[strutils, tables, unittest]

import clispec

proc envOf(pairs: openArray[(string, string)]): CliInstallEnv =
  let table = pairs.toTable
  cliInstallEnv(proc (name: string): string = table.getOrDefault(name))

proc paths(targets: seq[CliCompletionTarget]): seq[string] =
  for t in targets: result.add t.path

proc sysPaths(shell: CliShell; family: CliPlatformFamily;
            prefix = ""): seq[string] =
  cliSystemCompletionTargets(shell, "tool", family, prefix).paths

suite "test_cs_m7_completion_install_locations":

  test "the file name each shell looks up":
    check cliCompletionFileName(cshBash, "tool") == "tool"
    check cliCompletionFileName(cshZsh, "tool") == "_tool"
    check cliCompletionFileName(cshFish, "tool") == "tool.fish"
    check cliCompletionFileName(cshPowerShell, "tool") == "tool.ps1"

  test "per user, with nothing but HOME set":
    let env = envOf({"HOME": "/home/u"})
    let bash = cliUserCompletionTargets(cshBash, "tool", env)
    check bash.len == 2
    check bash[0].kind == ctkFile
    check bash[0].path ==
      "/home/u/.local/share/bash-completion/completions/tool"
    check bash[1].kind == ctkProfileBlock
    check bash[1].path == "/home/u/.bashrc"
    check bash[1].script == bash[0].path
    check bash[1].onlyWithoutLoader
    let zsh = cliUserCompletionTargets(cshZsh, "tool", env)
    check zsh.paths == @["/home/u/.local/share/zsh/site-functions/_tool",
                         "/home/u/.zshrc"]
    check zsh[1].script == zsh[0].path
    check not zsh[1].onlyWithoutLoader
    check cliUserCompletionTargets(cshFish, "tool", env).paths ==
      @["/home/u/.config/fish/completions/tool.fish"]
    let pwsh = cliUserCompletionTargets(cshPowerShell, "tool", env)
    check pwsh.paths == @["/home/u/.local/share/tool/completions/tool.ps1",
                          "/home/u/.config/powershell/profile.ps1"]
    check pwsh[1].edition == cpePwsh

  test "XDG_DATA_HOME, XDG_CONFIG_HOME, ZDOTDIR and BASH_COMPLETION_USER_DIR":
    let env = envOf({"HOME": "/home/u", "XDG_DATA_HOME": "/d",
                     "XDG_CONFIG_HOME": "/c", "ZDOTDIR": "/z"})
    check cliUserCompletionTargets(cshBash, "tool", env).paths ==
      @["/d/bash-completion/completions/tool", "/home/u/.bashrc"]
    check cliUserCompletionTargets(cshZsh, "tool", env).paths ==
      @["/d/zsh/site-functions/_tool", "/z/.zshrc"]
    check cliUserCompletionTargets(cshFish, "tool", env).paths ==
      @["/c/fish/completions/tool.fish"]
    check cliUserCompletionTargets(cshPowerShell, "tool", env).paths ==
      @["/d/tool/completions/tool.ps1", "/c/powershell/profile.ps1"]
    let own = envOf({"HOME": "/home/u", "XDG_DATA_HOME": "/d",
                     "BASH_COMPLETION_USER_DIR": "/b"})
    check cliUserCompletionTargets(cshBash, "tool", own)[0].path ==
      "/b/completions/tool"
    # A relative XDG value is invalid and ignored (XDG Base Directory
    # Specification).
    let relative = envOf({"HOME": "/home/u", "XDG_DATA_HOME": "rel",
                          "XDG_CONFIG_HOME": "rel"})
    check cliUserCompletionTargets(cshFish, "tool", relative).paths ==
      @["/home/u/.config/fish/completions/tool.fish"]
    check cliUserCompletionTargets(cshZsh, "tool", relative)[0].path ==
      "/home/u/.local/share/zsh/site-functions/_tool"

  test "per user on Windows: PowerShell only, both editions, Documents as given":
    let env = cliInstallEnv(proc (name: string): string =
      case name
      of "USERPROFILE": "C:\\Users\\u"
      of "LOCALAPPDATA": "C:\\Users\\u\\AppData\\Local"
      else: "", documents = "D:\\OneDrive\\Documents")
    for shell in [cshBash, cshZsh, cshFish]:
      check cliUserCompletionTargets(shell, "tool", env, windows = true).len == 0
    let pwsh = cliUserCompletionTargets(cshPowerShell, "tool", env,
      windows = true)
    check pwsh.paths == @[
      "C:\\Users\\u\\AppData\\Local\\tool\\completions\\tool.ps1",
      "D:\\OneDrive\\Documents\\PowerShell\\Profile.ps1",
      "D:\\OneDrive\\Documents\\WindowsPowerShell\\Profile.ps1"]
    check pwsh[1].edition == cpePwsh
    check pwsh[2].edition == cpeWindows
    check pwsh[2].script == pwsh[0].path
    # Without the Documents folder: the home directory's.
    let plain = cliInstallEnv(proc (name: string): string =
      if name == "USERPROFILE": "C:\\Users\\u" else: "")
    check cliUserCompletionTargets(cshPowerShell, "tool", plain,
      windows = true).paths == @[
        "C:\\Users\\u\\AppData\\Local\\tool\\completions\\tool.ps1",
        "C:\\Users\\u\\Documents\\PowerShell\\Profile.ps1",
        "C:\\Users\\u\\Documents\\WindowsPowerShell\\Profile.ps1"]

  test "system-wide, the local administrator's area (--system)":
    check sysPaths(cshBash, cpfLocal) ==
      @["/usr/local/share/bash-completion/completions/tool"]
    check sysPaths(cshZsh, cpfLocal) ==
      @["/usr/local/share/zsh/site-functions/_tool"]
    check sysPaths(cshFish, cpfLocal) ==
      @["/usr/local/share/fish/vendor_completions.d/tool.fish"]
    check sysPaths(cshPowerShell, cpfLocal) ==
      @["/usr/local/share/tool/completions/tool.ps1"]
    let pwsh = cliSystemCompletionTargets(cshPowerShell, "tool", cpfLocal,
      psHome = "/opt/microsoft/powershell/7")
    check pwsh.paths == @["/usr/local/share/tool/completions/tool.ps1",
                          "/opt/microsoft/powershell/7/profile.ps1"]
    check pwsh[1].kind == ctkProfileBlock
    check pwsh[1].script == pwsh[0].path
    # A test root moves every path.
    check sysPaths(cshBash, cpfLocal, "/r/usr/local") ==
      @["/r/usr/local/share/bash-completion/completions/tool"]

  test "system-wide, the local administrator's area on Linux (--system)":
    # Bash, Zsh and PowerShell as on macOS and the BSDs, under /usr/local.
    check sysPaths(cshBash, cpfLinuxLocal) ==
      @["/usr/local/share/bash-completion/completions/tool"]
    check sysPaths(cshZsh, cpfLinuxLocal) ==
      @["/usr/local/share/zsh/site-functions/_tool"]
    check sysPaths(cshPowerShell, cpfLinuxLocal) ==
      @["/usr/local/share/tool/completions/tool.ps1"]
    check cliDefaultPrefix(cpfLinuxLocal) == "/usr/local"
    # Fish's goes in fish's configuration directory, which every fish
    # searches; /usr/local/share/fish/vendor_completions.d is searched only
    # when XDG_DATA_DIRS names /usr/local/share (measured on Debian 12 and
    # Fedora 45, where a console session sets none).
    check sysPaths(cshFish, cpfLinuxLocal) ==
      @["/etc/fish/completions/tool.fish"]
    # The negative control: the old location, which fish does not load.
    check "/usr/local/share/fish/vendor_completions.d/tool.fish" notin
      sysPaths(cshFish, cpfLinuxLocal)
    # A test root moves the configuration directory too, and only through
    # sysconfDir: the prefix does not carry it.
    check cliSystemCompletionTargets(cshFish, "tool", cpfLinuxLocal,
      "/r/usr/local", sysconfDir = "/r/etc").paths ==
      @["/r/etc/fish/completions/tool.fish"]
    check cliSystemCompletionTargets(cshBash, "tool", cpfLinuxLocal,
      "/r/usr/local", sysconfDir = "/r/etc").paths ==
      @["/r/usr/local/share/bash-completion/completions/tool"]
    # Every other family ignores sysconfDir.
    check cliSystemCompletionTargets(cshFish, "tool", cpfLocal,
      sysconfDir = "/r/etc").paths ==
      @["/usr/local/share/fish/vendor_completions.d/tool.fish"]

  test "system-wide, each package family":
    # Debian's zsh reads other packages' functions from vendor-completions.
    check sysPaths(cshBash, cpfDebian) ==
      @["/usr/share/bash-completion/completions/tool"]
    check sysPaths(cshZsh, cpfDebian) ==
      @["/usr/share/zsh/vendor-completions/_tool"]
    check sysPaths(cshFish, cpfDebian) ==
      @["/usr/share/fish/vendor_completions.d/tool.fish"]
    for family in [cpfRpm, cpfArch]:
      check sysPaths(cshBash, family) ==
        @["/usr/share/bash-completion/completions/tool"]
      check sysPaths(cshZsh, family) == @["/usr/share/zsh/site-functions/_tool"]
      check sysPaths(cshFish, family) ==
        @["/usr/share/fish/vendor_completions.d/tool.fish"]
    check sysPaths(cshBash, cpfFreeBsd) ==
      @["/usr/local/share/bash-completion/completions/tool"]
    check sysPaths(cshZsh, cpfFreeBsd) ==
      @["/usr/local/share/zsh/site-functions/_tool"]
    check sysPaths(cshFish, cpfFreeBsd) ==
      @["/usr/local/share/fish/completions/tool.fish"]
    check sysPaths(cshFish, cpfOpenBsd, "/usr/pkg") ==
      @["/usr/pkg/share/fish/vendor_completions.d/tool.fish"]
    check sysPaths(cshBash, cpfHomebrew, "/opt/homebrew") ==
      @["/opt/homebrew/etc/bash_completion.d/tool"]
    check sysPaths(cshZsh, cpfHomebrew, "/opt/homebrew") ==
      @["/opt/homebrew/share/zsh/site-functions/_tool"]
    check sysPaths(cshBash, cpfMacosPkg) ==
      @["/usr/local/etc/bash_completion.d/tool",
        "/usr/local/share/bash-completion/completions/tool"]
    check sysPaths(cshFish, cpfMacosPkg) ==
      @["/usr/local/share/fish/vendor_completions.d/tool.fish"]
    check sysPaths(cshZsh, cpfNix, "/nix/store/x-tool") ==
      @["/nix/store/x-tool/share/zsh/site-functions/_tool"]
    for family in [cpfDebian, cpfRpm, cpfArch, cpfFreeBsd, cpfOpenBsd,
                   cpfMacosPkg]:
      check sysPaths(cshPowerShell, family).len == 0
    for shell in [cshBash, cshZsh, cshFish]:
      check sysPaths(shell, cpfWindows, "C:\\Program Files\\Tool").len == 0
    let windows = cliSystemCompletionTargets(cshPowerShell, "tool",
      cpfWindows, "C:\\Program Files\\Tool",
      psHome = "C:\\Program Files\\PowerShell\\7")
    check windows.paths == @[
      "C:\\Program Files\\Tool\\share\\tool\\completions\\tool.ps1",
      "C:\\Program Files\\PowerShell\\7\\Profile.ps1"]

  test "a family without a fixed prefix needs one":
    for family in [cpfHomebrew, cpfNix, cpfWindows]:
      check cliDefaultPrefix(family) == ""
      expect ValueError:
        discard cliSystemCompletionDirs(cshPowerShell, "tool", family)
    check cliDefaultPrefix(cpfDebian) == "/usr"
    check cliDefaultPrefix(cpfLocal) == "/usr/local"

  test "where bash-completion is looked for":
    let loaders = cliBashCompletionLoaders()
    check "/usr/share/bash-completion/bash_completion" in loaders
    check "/usr/local/share/bash-completion/bash_completion" in loaders
    check "/etc/bash_completion" in loaders
    check "/opt/homebrew/etc/profile.d/bash_completion.sh" in loaders
    check cliBashCompletionLoaders(["/brew"])[^1] ==
      "/brew/etc/profile.d/bash_completion.sh"

  test "profile blocks load the script and quote every name and path":
    check cliProfileBlockBody(cshBash, "tool", "/h/c/tool") ==
      "if [ -r '/h/c/tool' ]; then . '/h/c/tool'; fi\n"
    check cliProfileBlockBody(cshFish, "tool", "/h/tool.fish") == ""
    let zsh = cliProfileBlockBody(cshZsh, "tool", "/h/zsh/site-functions/_tool")
    check "fpath=('/h/zsh/site-functions' ${fpath:#'/h/zsh/site-functions'})" in zsh
    check "autoload -Uz '_tool'" in zsh
    check "compdef '_tool' 'tool'" in zsh
    let pwsh = cliProfileBlockBody(cshPowerShell, "tool", "/h/tool.ps1")
    check pwsh == "if (Test-Path -LiteralPath '/h/tool.ps1') { " &
      "Invoke-Expression ([System.IO.File]::ReadAllText('/h/tool.ps1')) }\n"
    # A program name and paths holding characters the shells treat
    # specially stay single words: a quote is closed and escaped, `$`, `;`
    # and spaces are inside quotes.
    let odd = "my tool's;$x"
    let script = "/h o/it's/_" & odd
    let zshOdd = cliProfileBlockBody(cshZsh, odd, script)
    check "compdef '_my tool'\\''s;$x' 'my tool'\\''s;$x'" in zshOdd
    check "fpath=('/h o/it'\\''s'" in zshOdd
    let bashOdd = cliProfileBlockBody(cshBash, odd, "/h o/$x;'q")
    check bashOdd == "if [ -r '/h o/$x;'\\''q' ]; then . '/h o/$x;'\\''q'; fi\n"
    let pwshOdd = cliProfileBlockBody(cshPowerShell, odd, "C:\\it's $x.ps1")
    check "'C:\\it''s $x.ps1'" in pwshOdd

  test "a generated script is recognised, any other file is not":
    for shell in CliShell:
      let script = cliCompletionScript(shell, "tool")
      check cliIsGeneratedCompletionScript(script, shell, "tool")
      # Another program's script, another shell's, and a hand-written file.
      check not cliIsGeneratedCompletionScript(
        cliCompletionScript(shell, "other"), shell, "tool")
      check not cliIsGeneratedCompletionScript("complete -F _f tool\n",
        shell, "tool")
      check not cliIsGeneratedCompletionScript("", shell, "tool")
    check not cliIsGeneratedCompletionScript(
      cliCompletionScript(cshFish, "tool"), cshBash, "tool")
    # An older clispec's script for the same program: same header, other body.
    let older = cliCompletionScript(cshBash, "tool").splitLines()[0] &
      "\nold body\n"
    check cliIsGeneratedCompletionScript(older, cshBash, "tool")
    # CRLF line ends (a file edited on Windows).
    check cliIsGeneratedCompletionScript(
      cliCompletionScript(cshPowerShell, "tool").replace("\n", "\r\n"),
      cshPowerShell, "tool")
