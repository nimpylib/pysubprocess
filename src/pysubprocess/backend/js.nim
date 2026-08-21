import std/[jsffi, strtabs]

from pkg/jscompat/utils/denoAttrs import importByNodeOrDeno

import ../[types, utils]

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
  const child = require('node:child_process').spawnSync(command, args, options);
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

proc environmentPairs(env: StringTableRef): seq[cstring] =
  if env != nil:
    for key, value in env:
      result.add cstring(key)
      result.add cstring(value)

proc runBackend*(completed: var CompletedProcess; command: string;
    commandArgs: openArray[string]; input: string; shell: bool; cwd: string;
    env: StringTableRef; stdoutMode, stderrMode: Stdio) =
  var jsArgs = newSeqOfCap[cstring](commandArgs.len)
  for arg in commandArgs:
    jsArgs.add cstring(arg)
  let pairs = environmentPairs(env)
  let jsEnv = if env == nil: jsNull(0) else: asJsObject(pairs)
  let child = spawnSync(cstring(command), jsArgs, cstring(input), cstring(cwd),
    shell, jsEnv)
  if child.error.len != 0:
    raise newException(OSError, $child.error)
  completed.returncode = child.status
  let childStdout = $child.stdout
  let childStderr = $child.stderr
  case stdoutMode
  of PIPE: completed.stdout = childStdout
  of DEVNULL: discard
  of INHERIT:
    if childStdout.len != 0: writeParentStdout childStdout
  of STDOUT: discard # validated by the public API
  case stderrMode
  of PIPE: completed.stderr = childStderr
  of STDOUT:
    if stdoutMode == PIPE:
      completed.stdout.add childStderr
    elif stdoutMode == INHERIT and childStderr.len != 0:
      writeParentStdout childStderr
  of DEVNULL: discard
  of INHERIT:
    if childStderr.len != 0: writeParentStderr childStderr
