import std/[options, streams, strtabs]

import ../[types, utils]
import ../macros

type
  PopenBase* = ref object of RootObj
    ## State shared by native and JavaScript Popen handles.
    args*: seq[string]
    stdin*: Stream
    stdout*: Stream
    stderr*: Stream
    pid*: int
    returncode*: Option[int]
    command*, cwd*, executable*: string
    commandArgs*: seq[string]
    env*: StringTableRef
    stdinMode*, stdoutMode*, stderrMode*: Stdio
    shell*: bool
    streamsConsumed*, stdinClosed*: bool

proc validateExtendedOptions*(bufsize: int; closeFds, restoreSignals,
    startNewSession: bool; passFds: openArray[int]; group: int;
    extraGroups: openArray[int]; user, umask, pipesize, processGroup,
    creationflags: int) =
  if bufsize != -1 or not closeFds or not restoreSignals or startNewSession or
      passFds.len != 0 or group != -1 or extraGroups.len != 0 or user != -1 or
      umask != -1 or pipesize != -1 or processGroup != -1 or
      creationflags != 0:
    raise newException(ValueError,
      "this Popen process-creation option is not supported by this backend")

proc initPopenBase*(child: PopenBase; spec: CommandSpec; shell: bool;
    cwd: string; env: StringTableRef; executable: string; stdin, stdout,
    stderr: Stdio; stringStreams = false) =
  validateStdio(stdin, stdout)
  child.args = spec.argv
  child.command = spec.command
  child.commandArgs = spec.args
  child.shell = shell
  child.cwd = cwd
  child.env = env
  child.executable = executable
  child.stdinMode = stdin
  child.stdoutMode = stdout
  child.stderrMode = stderr
  child.pid = -1
  child.returncode = none(int)
  if stringStreams:
    if stdin == PIPE: child.stdin = newStringStream()
    if stdout == PIPE: child.stdout = newStringStream()
    if stderr == PIPE: child.stderr = newStringStream()

proc effectiveProgram*(child: PopenBase): string =
  if child.executable.len == 0: child.command else: child.executable

proc commandSpec*(child: PopenBase): CommandSpec =
  CommandSpec(command: child.effectiveProgram, args: child.commandArgs,
    argv: child.args)

proc validateCommunicateInput*(child: PopenBase; input: string) =
  if input.len != 0 and child.stdinMode != PIPE:
    raise newException(ValueError,
      "stdin argument must be PIPE when communicate input is supplied")

template definePopenConstructors*(ProcessType: typedesc;
    startPopen: untyped) =
  defineCommandOverloads:
    proc Popen*(args: openArray[string]; stdin = INHERIT; stdout = INHERIT;
        stderr = INHERIT; shell = false; cwd = ""; env: StringTableRef = nil;
        executable = ""; bufsize = -1; closeFds = true; restoreSignals = true;
        startNewSession = false; passFds: seq[int] = @[]; group = -1;
        extraGroups: seq[int] = @[]; user = -1; umask = -1; encoding = "";
        errors = ""; text = false; universalNewlines = false; pipesize = -1;
        processGroup = -1; creationflags = 0): ProcessType =
      validateExtendedOptions(bufsize, closeFds, restoreSignals,
        startNewSession, passFds, group, extraGroups, user, umask, pipesize,
        processGroup, creationflags)
      startPopen(commandSpec(args), shell, cwd, env, executable, stdin, stdout,
        stderr)
