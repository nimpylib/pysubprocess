## A small, synchronous subset of Python's ``subprocess`` API.
##
## Commands are passed as an argument vector by default.  Set ``shell=true``
## only when shell syntax is deliberately required.

import std/strtabs

when defined(js):
  import std/jsffi
  from pkg/jscompat/utils/denoAttrs import importByNodeOrDeno

  when defined(nodejs):
    {.emit: """/*INCLUDESECTION*/
    import { spawnSync as pysubprocessNodeSpawnSyncNative } from 'node:child_process';
    """.}

  {.emit: """/*INCLUDESECTION*/
  function pysubprocessEnvironment(envPairs) {
    if (envPairs === null) return undefined;
    const env = {};
    for (let i = 0; i < envPairs.length; i += 2)
      env[envPairs[i]] = envPairs[i + 1];
    return env;
  }

  function pysubprocessNodeSpawnSync(command, args, input, cwd, shell, envPairs) {
    const options = {
      encoding: 'utf8',
      input: input,
      maxBuffer: 64 * 1024 * 1024,
      shell: shell
    };
    if (cwd.length !== 0) options.cwd = cwd;
    const env = pysubprocessEnvironment(envPairs);
    if (env !== undefined) options.env = env;
    const child = pysubprocessNodeSpawnSyncNative(command, args, options);
    return {
      status: child.status === null ? -1 : child.status,
      stdout: child.stdout === null ? '' : child.stdout,
      stderr: child.stderr === null ? '' : child.stderr,
      error: child.error === undefined ? '' : child.error.message
    };
  }

  const pysubprocessTextDecoder = new TextDecoder();
  function pysubprocessDenoResult(child) {
    return {
      status: child.code,
      stdout: pysubprocessTextDecoder.decode(child.stdout),
      stderr: pysubprocessTextDecoder.decode(child.stderr),
      error: ''
    };
  }

  function pysubprocessDenoCommand(command, args, cwd, shell, envPairs) {
    let executable = command;
    let commandArgs = args;
    if (shell) {
      if (Deno.build.os === 'windows') {
        executable = 'cmd.exe';
        commandArgs = ['/d', '/s', '/c', command];
      } else {
        executable = '/bin/sh';
        commandArgs = ['-c', command];
      }
    }
    const options = {
      args: commandArgs,
      stdin: 'null',
      stdout: 'piped',
      stderr: 'piped'
    };
    if (cwd.length !== 0) options.cwd = cwd;
    const env = pysubprocessEnvironment(envPairs);
    if (env !== undefined) {
      options.env = env;
      options.clearEnv = true;
    }
    return { executable, options };
  }

  async function pysubprocessDenoInputBridgeMain() {
    const spec = JSON.parse(Deno.readTextFileSync(Deno.args[0]));
    spec.options.stdin = 'piped';
    const child = new Deno.Command(spec.executable, spec.options).spawn();
    const writer = child.stdin.getWriter();
    await writer.write(new TextEncoder().encode(spec.input));
    await writer.close();
    const output = await child.output();
    Deno.stdout.writeSync(output.stdout);
    Deno.stderr.writeSync(output.stderr);
    Deno.exit(output.code);
  }
  const pysubprocessDenoInputBridge =
    '(' + pysubprocessDenoInputBridgeMain.toString() + ')()';

  function pysubprocessDenoSpawnSync(command, args, input, cwd, shell, envPairs) {
    try {
      const spec = pysubprocessDenoCommand(
        command, args, cwd, shell, envPairs);
      if (input.length === 0)
        return pysubprocessDenoResult(
          new Deno.Command(spec.executable, spec.options).outputSync());

      // outputSync rejects piped stdin, so a synchronous Deno.Command runs a
      // small bridge that uses Deno.Command.spawn() to feed the input.
      const specPath = Deno.makeTempFileSync({
        prefix: 'pysubprocess-', suffix: '.json'
      });
      try {
        Deno.writeTextFileSync(specPath, JSON.stringify({
          executable: spec.executable,
          options: spec.options,
          input: input
        }));
        const bridge = new Deno.Command(Deno.execPath(), {
          args: ['eval', pysubprocessDenoInputBridge, specPath],
          stdin: 'null',
          stdout: 'piped',
          stderr: 'piped'
        }).outputSync();
        return pysubprocessDenoResult(bridge);
      } finally {
        Deno.removeSync(specPath);
      }
    } catch (error) {
      return {
        status: -1,
        stdout: '',
        stderr: '',
        error: String(error.message || error)
      };
    }
  }

  const pysubprocessTextEncoder = new TextEncoder();
  function pysubprocessDenoWriteStdout(value) {
    Deno.stdout.writeSync(pysubprocessTextEncoder.encode(value));
  }
  function pysubprocessDenoWriteStderr(value) {
    Deno.stderr.writeSync(pysubprocessTextEncoder.encode(value));
  }
  """.}

  type JsRunResult = JsObject

  proc spawnSync(command: cstring; args: seq[cstring]; input, cwd: cstring;
      shell: bool; envPairs: JsObject): JsRunResult
      {.importByNodeOrDeno(
        "pysubprocessNodeSpawnSync", "pysubprocessDenoSpawnSync").}

  proc status(res: JsRunResult): int {.importjs: "#.status".}
  proc stdout(res: JsRunResult): cstring {.importjs: "#.stdout".}
  proc stderr(res: JsRunResult): cstring {.importjs: "#.stderr".}
  proc error(res: JsRunResult): cstring {.importjs: "#.error".}
  proc jsNull(ignored: int): JsObject {.importjs: "(#, null)".}
  proc asJsObject(values: seq[cstring]): JsObject {.importjs: "#".}
  proc writeParentStdout(value: cstring)
      {.importByNodeOrDeno("process.stdout.write", "pysubprocessDenoWriteStdout").}
  proc writeParentStderr(value: cstring)
      {.importByNodeOrDeno("process.stderr.write", "pysubprocessDenoWriteStderr").}
else:
  import std/[osproc, streams]

  proc writeParentStdout(value: string) = stdout.write value
  proc writeParentStderr(value: string) = stderr.write value

type
  Stdio* = enum
    ## Redirection choices accepted by `run`.
    INHERIT, PIPE, STDOUT, DEVNULL

  CompletedProcess* = object
    ## Result returned by `run`.
    args*: seq[string]
    returncode*: int
    stdout*: string
    stderr*: string

  CalledProcessError* = object of CatchableError
    ## Raised when ``check=true`` and the command fails.
    returncode*: int
    cmd*: seq[string]
    output*: string
    stdout*: string
    stderr*: string

proc `$`*(completed: CompletedProcess): string =
  "CompletedProcess(args=" & $completed.args & ", returncode=" &
    $completed.returncode & ")"

proc newCalledProcessError(completed: CompletedProcess): ref CalledProcessError =
  let message = "Command " & $completed.args & " returned non-zero exit status " &
    $completed.returncode & "."
  result = newException(CalledProcessError, message)
  result.returncode = completed.returncode
  result.cmd = completed.args
  result.output = completed.stdout
  result.stdout = completed.stdout
  result.stderr = completed.stderr

when defined(js):
  proc environmentPairs(env: StringTableRef): seq[cstring] =
    if env != nil:
      for key, value in env:
        result.add cstring(key)
        result.add cstring(value)

proc commandLine(command: string; args: openArray[string]): seq[string] =
  result = newSeqOfCap[string](args.len + 1)
  result.add command
  for arg in args:
    result.add arg

proc runImpl(command: string; commandArgs: openArray[string]; input: string;
    captureOutput, check, shell: bool; cwd: string; env: StringTableRef;
    stdoutMode, stderrMode: Stdio): CompletedProcess =
  if command.len == 0:
    raise newException(ValueError, "args must not be empty")
  if captureOutput and (stdoutMode != INHERIT or stderrMode != INHERIT):
    raise newException(ValueError,
      "stdout and stderr arguments may not be used with capture_output")

  let
    effectiveStdout = if captureOutput: PIPE else: stdoutMode
    effectiveStderr = if captureOutput: PIPE else: stderrMode
  if effectiveStdout == STDOUT:
    raise newException(ValueError, "STDOUT is only valid for stderr")
  result.args = commandLine(command, commandArgs)

  when defined(js):
    var jsArgs = newSeqOfCap[cstring](commandArgs.len)
    for arg in commandArgs:
      jsArgs.add cstring(arg)
    let pairs = environmentPairs(env)
    let jsEnv = if env == nil: jsNull(0) else: asJsObject(pairs)
    let child = spawnSync(cstring(command), jsArgs, cstring(input), cstring(cwd),
      shell, jsEnv)
    if child.error.len != 0:
      raise newException(OSError, $child.error)
    result.returncode = child.status
    let childStdout = $child.stdout
    let childStderr = $child.stderr
    case effectiveStdout
    of PIPE: result.stdout = childStdout
    of DEVNULL: discard
    of INHERIT:
      if childStdout.len != 0: writeParentStdout cstring(childStdout)
    of STDOUT: discard # validated above
    case effectiveStderr
    of PIPE: result.stderr = childStderr
    of STDOUT:
      if effectiveStdout == PIPE:
        result.stdout.add childStderr
      elif effectiveStdout == INHERIT and childStderr.len != 0:
        writeParentStdout cstring(childStderr)
    of DEVNULL: discard
    of INHERIT:
      if childStderr.len != 0: writeParentStderr cstring(childStderr)
  else:
    var options = {poUsePath}
    if shell:
      options.incl poEvalCommand
    if effectiveStderr == STDOUT:
      options.incl poStdErrToStdOut

    let useParentStreams = input.len == 0 and effectiveStdout == INHERIT and
      effectiveStderr == INHERIT
    if useParentStreams:
      options.incl poParentStreams

    var process = startProcess(command, workingDir = cwd, args = commandArgs,
      env = env, options = options)
    try:
      if useParentStreams:
        result.returncode = process.waitForExit()
      else:
        let childInput = process.inputStream()
        if input.len != 0:
          childInput.write input
        childInput.close()

        let childStdout = process.outputStream().readAll()
        let childStderr = if effectiveStderr == STDOUT: ""
                          else: process.errorStream().readAll()
        result.returncode = process.waitForExit()

        case effectiveStdout
        of PIPE: result.stdout = childStdout
        of DEVNULL: discard
        of INHERIT:
          if childStdout.len != 0: writeParentStdout childStdout
        of STDOUT: discard # validated above
        case effectiveStderr
        of PIPE: result.stderr = childStderr
        of STDOUT: discard # already merged and routed as stdout
        of DEVNULL: discard
        of INHERIT:
          if childStderr.len != 0: writeParentStderr childStderr
    finally:
      process.close()

  if check and result.returncode != 0:
    raise newCalledProcessError(result)

proc run*(args: openArray[string]; input = ""; captureOutput = false;
    check = false; shell = false; cwd = ""; env: StringTableRef = nil;
    stdout = INHERIT; stderr = INHERIT): CompletedProcess =
  ## Run a command and wait for it to finish.
  ##
  ## ``args`` is an executable followed by its arguments. Captured output is
  ## UTF-8 text on the JavaScript/Node.js backend and a Nim string natively.
  if args.len == 0:
    raise newException(ValueError, "args must not be empty")
  if args.len == 1:
    runImpl(args[0], [], input, captureOutput, check, shell, cwd, env, stdout,
      stderr)
  else:
    runImpl(args[0], args.toOpenArray(1, args.high), input, captureOutput,
      check, shell, cwd, env, stdout, stderr)

proc run*(command: string; input = ""; captureOutput = false; check = false;
    shell = false; cwd = ""; env: StringTableRef = nil; stdout = INHERIT;
    stderr = INHERIT): CompletedProcess =
  ## String form of `run`. Without ``shell=true`` the whole string is treated
  ## as the executable name, matching Python's subprocess behavior.
  runImpl(command, [], input, captureOutput, check, shell, cwd, env, stdout,
    stderr)

proc call*(args: openArray[string]; shell = false; cwd = "";
    env: StringTableRef = nil): int {.discardable.} =
  ## Run a command and return its exit status.
  run(args, shell = shell, cwd = cwd, env = env).returncode

proc call*(command: string; shell = false; cwd = "";
    env: StringTableRef = nil): int {.discardable.} =
  ## String form of `call`.
  run(command, shell = shell, cwd = cwd, env = env).returncode

proc checkCall*(args: openArray[string]; shell = false; cwd = "";
    env: StringTableRef = nil): int {.discardable.} =
  ## Run a command, raising `CalledProcessError` on failure.
  run(args, check = true, shell = shell, cwd = cwd, env = env).returncode

proc checkCall*(command: string; shell = false; cwd = "";
    env: StringTableRef = nil): int {.discardable.} =
  ## String form of `checkCall`.
  run(command, check = true, shell = shell, cwd = cwd, env = env).returncode

proc checkOutput*(args: openArray[string]; input = ""; shell = false;
    cwd = ""; env: StringTableRef = nil; stderr = INHERIT): string =
  ## Run a command and return stdout, raising on failure.
  run(args, input = input, check = true, shell = shell, cwd = cwd, env = env,
    stdout = PIPE, stderr = stderr).stdout

proc checkOutput*(command: string; input = ""; shell = false; cwd = "";
    env: StringTableRef = nil; stderr = INHERIT): string =
  ## String form of `checkOutput`.
  run(command, input = input, check = true, shell = shell, cwd = cwd,
    env = env, stdout = PIPE, stderr = stderr).stdout

proc checkReturncode*(completed: CompletedProcess) =
  ## Raise `CalledProcessError` if this process did not exit successfully.
  if completed.returncode != 0:
    raise newCalledProcessError(completed)

proc getstatusoutput*(command: string): tuple[status: int, output: string] =
  ## Run a shell command with stderr redirected to stdout.
  let completed = run(command, shell = true, stdout = PIPE, stderr = STDOUT)
  result = (completed.returncode, completed.stdout)
  while result.output.len != 0 and result.output[^1] in {'\r', '\n'}:
    result.output.setLen(result.output.len - 1)

proc getoutput*(command: string): string =
  ## Return combined output from a shell command.
  getstatusoutput(command).output
