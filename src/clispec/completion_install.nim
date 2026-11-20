## Where each shell loads completion from: the file name and location of a
## program's completion script per shell, per user and system-wide and per
## platform family, and the text of a block for an rc or profile file that
## loads an installed script.
##
## This module is data and pure functions. It reads no environment variable
## and touches no file: the caller passes the environment in
## (``CliInstallEnv``, which ``cliInstallEnv`` fills from any lookup) and does
## every write itself. So a program's own installer (a ``completion install``
## style command, a package build, an install script) and its tests compute
## exactly the same locations, and every program on clispec installs to the
## same places.
##
## The locations, and where each comes from:
##
## * **Bash**, per user: ``${BASH_COMPLETION_USER_DIR:-${XDG_DATA_HOME:-~/.local/share}/bash-completion}/completions/<program>``,
##   which bash-completion 2 loads on demand the first time ``<program>`` is
##   completed. Where bash-completion is not installed (no
##   ``bash_completion`` script in the locations ``cliBashCompletionLoaders``
##   lists) nothing loads that directory, so a block in ``~/.bashrc`` sources
##   the file instead. System-wide: ``completions/`` under each of
##   ``XDG_DATA_DIRS``, ``/usr/local/share:/usr/share`` by default. The file
##   name is the unsuffixed ``<program>``: every bash-completion 2.x loads it,
##   while ``<program>.bash`` needs a recent one (bash-completion's README,
##   Q2, Q4 and Q10, https://github.com/scop/bash-completion/blob/main/README.md).
## * **Zsh**: a file ``_<program>`` whose first line is ``#compdef
##   <program>``, in a directory that is on ``$fpath`` when ``compinit``
##   runs (the zsh manual, Completion System, "Use of compinit",
##   https://zsh.sourceforge.io/Doc/Release/Completion-System.html#Use-of-compinit).
##   zsh searches no per-user directory by default, so the per-user file goes
##   in ``${XDG_DATA_HOME:-~/.local/share}/zsh/site-functions`` and a block in
##   ``${ZDOTDIR:-~}/.zshrc`` puts that directory on ``$fpath`` (and, when
##   ``compinit`` has already run, registers the function at once).
##   ``/usr/local/share/zsh/site-functions`` is the local administrator's
##   directory; Debian's own packages use ``/usr/share/zsh/vendor-completions``
##   (Debian's zsh ``README.Debian``,
##   https://salsa.debian.org/debian/zsh/-/raw/debian/debian/README.Debian),
##   other distributions ``/usr/share/zsh/site-functions``.
## * **Fish**: ``${XDG_CONFIG_HOME:-~/.config}/fish/completions/<program>.fish``
##   per user, and ``vendor_completions.d`` under the data directories
##   system-wide (fish's documentation, "Where to put completions",
##   https://fishshell.com/docs/current/completions.html#where-to-put-completions).
##   fish takes those data directories from ``XDG_DATA_DIRS``; with it unset
##   (a console or SSH session on Debian 12 and Fedora 45) only fish's own
##   ``/usr/share/fish/vendor_completions.d`` is searched, never
##   ``/usr/local/share``. So the local administrator's Linux script goes in
##   fish's configuration directory instead, ``/etc/fish/completions``
##   (``$__fish_sysconf_dir/completions``), which comes second in
##   ``$fish_complete_path`` whatever the environment. The same page lists
##   that directory as the one for completions the system administrator
##   installs for every user; ``fish_complete_path`` is described in
##   https://fishshell.com/docs/current/language.html#special-variables.
##   FreeBSD's ports use ``share/fish/completions`` (the Porter's Handbook,
##   "Shell Completion Files",
##   https://docs.freebsd.org/en/books/porters-handbook/special/#shell-completion).
## * **PowerShell** loads no completion file on its own: a block in a profile
##   evaluates the saved script with ``Invoke-Expression`` (which no execution
##   policy governs, see ``clispec/completion_scripts``). Per user the block
##   goes in ``$PROFILE.CurrentUserAllHosts``, which every host (the console,
##   VS Code) runs: ``~/.config/powershell/profile.ps1`` (under
##   ``XDG_CONFIG_HOME``) outside Windows, and on Windows
##   ``Documents\PowerShell\Profile.ps1`` for PowerShell 7 and
##   ``Documents\WindowsPowerShell\Profile.ps1`` for Windows PowerShell 5.1,
##   where Documents is the folder
##   ``[Environment]::GetFolderPath('MyDocuments')`` names, which can be
##   redirected (to OneDrive, say) away from ``%USERPROFILE%\Documents``.
##   System-wide it goes in ``$PROFILE.AllUsersAllHosts``,
##   ``$PSHOME/profile.ps1`` (about_Profiles,
##   https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_profiles).
##
## The package rows (Debian, the rpm distributions, Arch, the BSDs, Homebrew,
## a macOS installer package, Nix, Windows) are the directories each
## platform's shells read without any setup, so a package that puts the
## script there needs to change no rc file.

import std/strutils

import ./[completion, completion_scripts]

type
  CliInstallScope* = enum
    ## Who an installed script serves.
    cisUser = "user"      ## the current user: their home directory
    cisSystem = "system"  ## every user of the machine

  CliPlatformFamily* = enum
    ## Where a system-wide script goes: the local administrator's area or
    ## one kind of package.
    cpfLocal = "local"
      ## Installed by the local administrator on macOS or a BSD, outside any
      ## package manager: under ``/usr/local`` by default.
    cpfLinuxLocal = "linux-local"
      ## Installed by the local administrator on Linux, outside any package
      ## manager: under ``/usr/local`` by default, except Fish's script,
      ## which goes in fish's configuration directory
      ## (``<sysconfDir>/fish/completions``, ``/etc/fish/completions``) because
      ## fish does not search ``/usr/local/share`` unless ``XDG_DATA_DIRS``
      ## names it.
    cpfDebian = "debian"      ## a Debian or Ubuntu package (``/usr``)
    cpfRpm = "rpm"            ## a Fedora, RHEL or openSUSE package (``/usr``)
    cpfArch = "arch"          ## an Arch Linux package (``/usr``)
    cpfFreeBsd = "freebsd"    ## a FreeBSD port or package (``/usr/local``)
    cpfOpenBsd = "openbsd"
      ## An OpenBSD port or a NetBSD pkgsrc package (``${PREFIX}``,
      ## ``/usr/local`` by default); these follow the shells' upstream
      ## defaults.
    cpfHomebrew = "homebrew"  ## a Homebrew formula (``$(brew --prefix)``)
    cpfMacosPkg = "macos-pkg" ## a macOS installer package (``/usr/local``)
    cpfNix = "nix"            ## a Nix package (its ``$out``)
    cpfWindows = "windows"    ## a Windows installer (its install directory)

  CliPowerShellEdition* = enum
    ## Which PowerShell a profile belongs to: each has its own profiles.
    cpePwsh = "pwsh"              ## PowerShell 7 and later (``pwsh``)
    cpeWindows = "powershell"     ## Windows PowerShell 5.1 (``powershell``)

  CliTargetKind* = enum
    ctkFile = "file"
      ## The script itself, saved where the shell (or a block) loads it.
    ctkProfileBlock = "profile-block"
      ## A block in an rc or profile file that loads the script; its text is
      ## ``cliProfileBlockBody``.

  CliCompletionTarget* = object
    ## One thing to write for one shell.
    shell*: CliShell
    kind*: CliTargetKind
    path*: string
      ## The script's path (``ctkFile``), or the rc or profile file the
      ## block goes in (``ctkProfileBlock``).
    script*: string
      ## ``ctkProfileBlock``: the script file the block loads.
    edition*: CliPowerShellEdition
      ## ``ctkProfileBlock`` of PowerShell: which PowerShell's profile it is.
    onlyWithoutLoader*: bool
      ## Write this target only when the shell's own completion loader is
      ## missing: the ``~/.bashrc`` block for a Bash without bash-completion.

  CliInstallEnv* = object
    ## The environment the per-user locations depend on. An empty field is
    ## unset. Fill it with ``cliInstallEnv``.
    home*: string                   ## ``HOME`` (on Windows ``USERPROFILE``)
    xdgDataHome*: string            ## ``XDG_DATA_HOME``
    xdgConfigHome*: string          ## ``XDG_CONFIG_HOME``
    zdotdir*: string                ## ``ZDOTDIR``
    bashCompletionUserDir*: string  ## ``BASH_COMPLETION_USER_DIR``
    localAppData*: string           ## ``LOCALAPPDATA`` (Windows)
    documents*: string
      ## Windows: the user's Documents folder, as
      ## ``[Environment]::GetFolderPath('MyDocuments')`` reports it. It is
      ## not an environment variable, so the caller asks the system for it
      ## (``SHGetKnownFolderPath(FOLDERID_Documents)``). Empty: the
      ## ``Documents`` directory of ``home``.

  CliEnvLookup* = proc (name: string): string {.closure.}
    ## Reads one environment variable: its value, or "" when unset.

proc cliInstallEnv*(lookup: CliEnvLookup; documents = ""): CliInstallEnv =
  ## ``CliInstallEnv`` from ``lookup`` (``proc (n: string): string =
  ## getEnv(n)``, or a table in a test). ``home`` is ``HOME``, else
  ## ``USERPROFILE``. ``documents`` is passed through.
  result.home = lookup("HOME")
  if result.home.len == 0:
    result.home = lookup("USERPROFILE")
  result.xdgDataHome = lookup("XDG_DATA_HOME")
  result.xdgConfigHome = lookup("XDG_CONFIG_HOME")
  result.zdotdir = lookup("ZDOTDIR")
  result.bashCompletionUserDir = lookup("BASH_COMPLETION_USER_DIR")
  result.localAppData = lookup("LOCALAPPDATA")
  result.documents = documents

func joinPosix(parts: varargs[string]): string =
  ## ``parts`` joined with ``/``, without doubling a separator at a join.
  for part in parts:
    if part.len == 0:
      continue
    if result.len == 0:
      result = part
    elif result.endsWith('/'):
      result.add(if part.startsWith('/'): part[1 .. ^1] else: part)
    else:
      result.add(if part.startsWith('/'): part else: "/" & part)

func joinWindows(parts: varargs[string]): string =
  ## ``parts`` joined with ``\``, without doubling a separator at a join.
  for part in parts:
    if part.len == 0:
      continue
    if result.len == 0:
      result = part
    elif result.endsWith('\\') or result.endsWith('/'):
      result.add(part.strip(trailing = false, chars = {'\\', '/'}))
    else:
      result.add("\\" & part.strip(trailing = false, chars = {'\\', '/'}))

func xdgDir(value, home, fallback: string): string =
  ## An XDG base directory: ``value`` when it is an absolute path, else
  ## ``home``/``fallback``. The XDG Base Directory Specification says a
  ## relative value is invalid and must be ignored
  ## (https://specifications.freedesktop.org/basedir-spec/latest/).
  if value.startsWith('/'): value else: joinPosix(home, fallback)

func cliCompletionFileName*(shell: CliShell; program: string): string =
  ## The name the script of ``program`` for ``shell`` is saved under: the
  ## name each shell looks up (``<program>`` for Bash, ``_<program>`` for
  ## Zsh, ``<program>.fish`` for Fish) and ``<program>.ps1`` for
  ## PowerShell.
  case shell
  of cshBash: program
  of cshZsh: "_" & program
  of cshFish: program & ".fish"
  of cshPowerShell: program & ".ps1"

func cliUserCompletionTargets*(shell: CliShell; program: string;
                               env: CliInstallEnv;
                               windows = false): seq[CliCompletionTarget] =
  ## What a per-user install of ``program``'s completion for ``shell``
  ## writes, in order: the script file, then the blocks that load it. On
  ## Windows (``windows``) only PowerShell applies, with a profile block for
  ## each edition; elsewhere PowerShell 7's.
  let name = cliCompletionFileName(shell, program)
  if windows:
    if shell != cshPowerShell:
      return @[]
    let script = joinWindows(
      (if env.localAppData.len > 0: env.localAppData
       else: joinWindows(env.home, "AppData", "Local")),
      program, "completions", name)
    let documents =
      if env.documents.len > 0: env.documents
      else: joinWindows(env.home, "Documents")
    result.add CliCompletionTarget(shell: shell, kind: ctkFile, path: script)
    result.add CliCompletionTarget(shell: shell, kind: ctkProfileBlock,
      path: joinWindows(documents, "PowerShell", "Profile.ps1"),
      script: script, edition: cpePwsh)
    result.add CliCompletionTarget(shell: shell, kind: ctkProfileBlock,
      path: joinWindows(documents, "WindowsPowerShell", "Profile.ps1"),
      script: script, edition: cpeWindows)
    return
  let dataHome = xdgDir(env.xdgDataHome, env.home, ".local/share")
  let configHome = xdgDir(env.xdgConfigHome, env.home, ".config")
  case shell
  of cshBash:
    let dir =
      if env.bashCompletionUserDir.len > 0: env.bashCompletionUserDir
      else: joinPosix(dataHome, "bash-completion")
    let script = joinPosix(dir, "completions", name)
    result.add CliCompletionTarget(shell: shell, kind: ctkFile, path: script)
    result.add CliCompletionTarget(shell: shell, kind: ctkProfileBlock,
      path: joinPosix(env.home, ".bashrc"), script: script,
      onlyWithoutLoader: true)
  of cshZsh:
    let script = joinPosix(dataHome, "zsh", "site-functions", name)
    let zdot = if env.zdotdir.len > 0: env.zdotdir else: env.home
    result.add CliCompletionTarget(shell: shell, kind: ctkFile, path: script)
    result.add CliCompletionTarget(shell: shell, kind: ctkProfileBlock,
      path: joinPosix(zdot, ".zshrc"), script: script)
  of cshFish:
    result.add CliCompletionTarget(shell: shell, kind: ctkFile,
      path: joinPosix(configHome, "fish", "completions", name))
  of cshPowerShell:
    let script = joinPosix(dataHome, program, "completions", name)
    result.add CliCompletionTarget(shell: shell, kind: ctkFile, path: script)
    result.add CliCompletionTarget(shell: shell, kind: ctkProfileBlock,
      path: joinPosix(configHome, "powershell", "profile.ps1"),
      script: script, edition: cpePwsh)

func cliDefaultPrefix*(family: CliPlatformFamily): string =
  ## The installation prefix of ``family`` when it has a fixed one, else ""
  ## (Homebrew's ``$(brew --prefix)``, a Nix package's ``$out`` and a
  ## Windows install directory are known only to the caller).
  case family
  of cpfLocal, cpfLinuxLocal, cpfFreeBsd, cpfOpenBsd, cpfMacosPkg: "/usr/local"
  of cpfDebian, cpfRpm, cpfArch: "/usr"
  of cpfHomebrew, cpfNix, cpfWindows: ""

func cliSystemCompletionDirs*(shell: CliShell; program: string;
                              family: CliPlatformFamily;
                              prefix = ""; sysconfDir = "/etc"): seq[string] =
  ## The directories a system-wide script of ``shell`` goes in for
  ## ``family``, under ``prefix`` (``cliDefaultPrefix`` when empty), for the
  ## program ``program`` (whose name only PowerShell's directory holds): one,
  ## or two where a platform's shells look in two places (a macOS installer
  ## package serves Homebrew's Bash and bash-completion 2 alike), or none
  ## where the shell does not apply (PowerShell outside ``cpfLocal``,
  ## ``cpfLinuxLocal`` and ``cpfWindows``; only PowerShell on Windows). For
  ## PowerShell the directory holds the script a profile block loads.
  ## ``sysconfDir`` is the system configuration directory, which only
  ## ``cpfLinuxLocal``'s Fish directory is under (a test passes a re-rooted
  ## one). Raises ``ValueError`` for a family without a fixed prefix when
  ## ``prefix`` is empty.
  let p = if prefix.len > 0: prefix else: cliDefaultPrefix(family)
  if p.len == 0:
    raise newException(ValueError, "the " & $family &
      " family has no fixed installation prefix; pass one")
  let completionsDir = "completions"
  case family
  of cpfWindows:
    if shell == cshPowerShell:
      result.add joinWindows(p, "share", program, completionsDir)
  of cpfLocal, cpfLinuxLocal, cpfDebian, cpfRpm, cpfArch, cpfFreeBsd,
     cpfOpenBsd, cpfHomebrew, cpfMacosPkg, cpfNix:
    case shell
    of cshBash:
      case family
      of cpfHomebrew:
        result.add joinPosix(p, "etc", "bash_completion.d")
      of cpfMacosPkg:
        result.add joinPosix(p, "etc", "bash_completion.d")
        result.add joinPosix(p, "share", "bash-completion", completionsDir)
      else:
        result.add joinPosix(p, "share", "bash-completion", completionsDir)
    of cshZsh:
      if family == cpfDebian:
        result.add joinPosix(p, "share", "zsh", "vendor-completions")
      else:
        result.add joinPosix(p, "share", "zsh", "site-functions")
    of cshFish:
      case family
      of cpfFreeBsd:
        result.add joinPosix(p, "share", "fish", "completions")
      of cpfLinuxLocal:
        result.add joinPosix(sysconfDir, "fish", completionsDir)
      else:
        result.add joinPosix(p, "share", "fish", "vendor_completions.d")
    of cshPowerShell:
      if family in {cpfLocal, cpfLinuxLocal}:
        result.add joinPosix(p, "share", program, completionsDir)

func cliPowerShellAllUsersProfile*(psHome: string; windows = false): string =
  ## ``$PROFILE.AllUsersAllHosts`` of the PowerShell installed at
  ## ``psHome`` (its ``$PSHOME``): ``profile.ps1`` there, spelled
  ## ``Profile.ps1`` on Windows (about_Profiles).
  if windows: joinWindows(psHome, "Profile.ps1")
  else: joinPosix(psHome, "profile.ps1")

func cliSystemCompletionTargets*(shell: CliShell; program: string;
                                 family: CliPlatformFamily; prefix = "";
                                 psHome = ""; sysconfDir = "/etc"):
                                 seq[CliCompletionTarget] =
  ## What a system-wide install of ``program``'s completion for ``shell``
  ## writes for ``family``: the script file in each of
  ## ``cliSystemCompletionDirs`` and, for PowerShell, a block in the
  ## all-users profile of the PowerShell at ``psHome`` (none when
  ## ``psHome`` is empty: the caller must say which PowerShell). For
  ## PowerShell the script is in ``<prefix>/share/<program>/completions``.
  let windows = family == cpfWindows
  let name = cliCompletionFileName(shell, program)
  for dir in cliSystemCompletionDirs(shell, program, family, prefix,
                                     sysconfDir):
    let script =
      if windows: joinWindows(dir, name) else: joinPosix(dir, name)
    result.add CliCompletionTarget(shell: shell, kind: ctkFile, path: script)
  if shell == cshPowerShell and result.len > 0 and psHome.len > 0:
    result.add CliCompletionTarget(shell: shell, kind: ctkProfileBlock,
      path: cliPowerShellAllUsersProfile(psHome, windows),
      script: result[0].path, edition: cpePwsh)

func cliBashCompletionLoaders*(brewPrefixes: openArray[string] =
                                 ["/opt/homebrew", "/usr/local"]):
                                 seq[string] =
  ## The files whose presence means bash-completion is installed, so that it
  ## loads the per-user completion directory on its own: its
  ## ``bash_completion`` script in the usual places, and Homebrew's
  ## ``etc/profile.d/bash_completion.sh`` under each of ``brewPrefixes``.
  result = @["/usr/share/bash-completion/bash_completion",
             "/usr/local/share/bash-completion/bash_completion",
             "/etc/bash_completion"]
  for prefix in brewPrefixes:
    result.add joinPosix(prefix, "etc", "profile.d", "bash_completion.sh")

func shellQuote(s: string): string =
  ## ``s`` as one single-quoted word for Bash and Zsh.
  "'" & s.replace("'", "'\\''") & "'"

func parentPath(path: string): string =
  ## ``path`` up to its last ``/`` or ``\`` (``path`` itself when it has
  ## none).
  for i in countdown(path.high, 0):
    if path[i] in {'/', '\\'}:
      return (if i == 0: path[0 .. 0] else: path[0 ..< i])
  path

func cliProfileBlockBody*(shell: CliShell; program, script: string): string =
  ## The text of the rc or profile block that loads ``program``'s installed
  ## completion ``script`` for ``shell`` (the body only: the caller adds its
  ## own markers around it). Every name and path is quoted for the shell.
  ##
  ## * Bash: sources the script when it is readable.
  ## * Zsh: puts the script's directory first on ``$fpath`` (once), so
  ##   ``compinit`` finds it, and, when ``compinit`` has already run
  ##   (``compdef`` exists), autoloads the function and registers it at once.
  ## * PowerShell: evaluates the script's text with ``Invoke-Expression``
  ##   when the file exists, so no execution policy applies to it.
  ## * Fish: "" (Fish loads its completion directories without a block).
  case shell
  of cshBash:
    let q = shellQuote(script)
    "if [ -r " & q & " ]; then . " & q & "; fi\n"
  of cshZsh:
    let dir = shellQuote(parentPath(script))
    let fn = shellQuote(cliCompletionFileName(cshZsh, program))
    "fpath=(" & dir & " ${fpath:#" & dir & "})\n" &
      "if (( ${+functions[compdef]} )); then\n" &
      "  autoload -Uz " & fn & "\n" &
      "  compdef " & fn & " " & shellQuote(program) & "\n" &
      "fi\n"
  of cshFish:
    ""
  of cshPowerShell:
    let q = cliPowerShellSingleQuote(script)
    "if (Test-Path -LiteralPath " & q & ") { Invoke-Expression " &
      "([System.IO.File]::ReadAllText(" & q & ")) }\n"

func generatedHeader(shell: CliShell; program: string): string =
  ## The comment line that marks the script clispec generates for
  ## ``program`` and ``shell``: taken from the script itself, so the two can
  ## never disagree.
  for line in cliCompletionScript(shell, program).splitLines():
    if line.startsWith("#") and line.endsWith(", generated by clispec."):
      return line
  ""

func cliIsGeneratedCompletionScript*(content: string; shell: CliShell;
                                     program: string): bool =
  ## Whether ``content`` is a completion script clispec generated for
  ## ``program`` and ``shell`` (of any clispec version): one of its first
  ## three lines is the generated header. An installer replaces such a file
  ## and leaves any other alone.
  let header = generatedHeader(shell, program)
  if header.len == 0:
    return false
  var n = 0
  for line in content.splitLines():
    if line.strip(leading = false, chars = {'\r'}) == header:
      return true
    inc n
    if n >= 3:
      break
  false
