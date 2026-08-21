import ./types

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

proc commandLine*(command: string; args: openArray[string]): seq[string] =
  result = newSeqOfCap[string](args.len + 1)
  result.add command
  for arg in args:
    result.add arg
