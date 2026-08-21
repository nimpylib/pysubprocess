import ./types

type CommandSpec* = object
  command*: string
  args*: seq[string]
  argv*: seq[string]

when defined(js):
  from pkg/jscompat/utils/denoAttrs import importByNodeOrDeno

  {.emit: """/*INCLUDESECTION*/
  const pysubprocessTextEncoder = new TextEncoder();
  function pysubprocessDenoWriteStdout(value) {
    Deno.stdout.writeSync(pysubprocessTextEncoder.encode(value));
  }
  function pysubprocessDenoWriteStderr(value) {
    Deno.stderr.writeSync(pysubprocessTextEncoder.encode(value));
  }
  """.}

  proc writeParentStdout*(value: string)
      {.importByNodeOrDeno("process.stdout.write", "pysubprocessDenoWriteStdout").}
  proc writeParentStderr*(value: string)
      {.importByNodeOrDeno("process.stderr.write", "pysubprocessDenoWriteStderr").}
else:
  proc writeParentStdout*(value: string) = stdout.write value
  proc writeParentStderr*(value: string) = stderr.write value

proc newCalledProcessError*(
    completed: CompletedProcess): ref CalledProcessError =
  let message = "Command " & $completed.args & " returned non-zero exit status " &
    $completed.returncode & "."
  result = newException(CalledProcessError, message)
  result.returncode = completed.returncode
  result.cmd = completed.args
  result.output = completed.stdout
  result.stdout = completed.stdout
  result.stderr = completed.stderr

proc newTimeoutExpired*(cmd: seq[string]; timeout: float; output = "";
    stderr = ""): ref TimeoutExpired =
  let message = "Command " & $cmd & " timed out after " & $timeout &
    " seconds"
  result = newException(TimeoutExpired, message)
  result.cmd = cmd
  result.timeout = timeout
  result.output = output
  result.stdout = output
  result.stderr = stderr

proc commandLine*(command: string; args: openArray[string]): seq[string] =
  result = newSeqOfCap[string](args.len + 1)
  result.add command
  for arg in args:
    result.add arg

proc commandSpec*(args: openArray[string]): CommandSpec =
  if args.len == 0:
    raise newException(ValueError, "args must not be empty")
  result.command = args[0]
  if args.len > 1:
    result.args = @args[1 .. ^1]
  result.argv = @args

proc commandSpec*(command: string): CommandSpec =
  if command.len == 0:
    raise newException(ValueError, "args must not be empty")
  result.command = command
  result.argv = @[command]

proc validateStdio*(stdinMode, stdoutMode: Stdio) =
  if stdinMode == STDOUT:
    raise newException(ValueError, "STDOUT is not valid for stdin")
  if stdoutMode == STDOUT:
    raise newException(ValueError, "STDOUT is only valid for stderr")

proc routeOutput*(stdoutMode, stderrMode: Stdio; rawStdout,
    rawStderr: string): tuple[stdout: string, stderr: string] =
  case stdoutMode
  of PIPE: result.stdout = rawStdout
  of INHERIT:
    if rawStdout.len != 0: writeParentStdout rawStdout
  of DEVNULL, STDOUT: discard
  case stderrMode
  of PIPE: result.stderr = rawStderr
  of STDOUT:
    if stdoutMode == PIPE:
      result.stdout.add rawStderr
    elif stdoutMode == INHERIT and rawStderr.len != 0:
      writeParentStdout rawStderr
  of INHERIT:
    if rawStderr.len != 0: writeParentStderr rawStderr
  of DEVNULL: discard
