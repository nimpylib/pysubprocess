import std/[options, streams, strtabs]

import ./[types, utils]
import ./execution
import ./popen/common

type PopenProcess* = ref object of PopenBase
  ## JavaScript's synchronous Popen-compatible process handle.
  completed: CompletedProcess

proc startPopen(spec: CommandSpec; shell: bool;
    cwd: string; env: StringTableRef; executable: string; stdin, stdout,
    stderr: Stdio): PopenProcess =
  new result
  result.initPopenBase(spec, shell, cwd, env, executable, stdin, stdout, stderr,
    stringStreams = true)

definePopenConstructors(PopenProcess, startPopen)

proc execute(child: PopenProcess; input: string; timeout: float) =
  if child.returncode.isSome: return
  child.completed = executeSync(child.commandSpec, input, child.shell,
    child.cwd, child.env, child.stdinMode, child.stdoutMode,
    child.stderrMode, timeout)
  child.returncode = some(child.completed.returncode)
  if child.stdout != nil: child.stdout.write child.completed.stdout
  if child.stderr != nil: child.stderr.write child.completed.stderr

proc poll*(child: PopenProcess): Option[int] = child.returncode

proc wait*(child: PopenProcess; timeout = -1.0): int =
  child.execute("", timeout)
  child.returncode.get

proc communicate*(child: PopenProcess; input = "";
    timeout = -1.0): tuple[stdout: string, stderr: string] =
  child.validateCommunicateInput(input)
  child.execute(input, timeout)
  (child.completed.stdout, child.completed.stderr)

proc sendSignal*(child: PopenProcess; signal: int) =
  ## A completed synchronous JS child needs no signal handling.
  discard signal
  if child.returncode.isNone:
    raise newException(OSError,
      "send_signal is unavailable before synchronous JS execution")

proc terminate*(child: PopenProcess) =
  if child.returncode.isNone:
    raise newException(OSError,
      "terminate is unavailable before synchronous JS execution")

proc kill*(child: PopenProcess) =
  if child.returncode.isNone:
    raise newException(OSError,
      "kill is unavailable before synchronous JS execution")
