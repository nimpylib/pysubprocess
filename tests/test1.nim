import std/[strtabs, strutils, unittest]

when defined(js):
  from pkg/jscompat/envvars import getEnvCompat
  from pkg/jscompat/os import getCurrentDirCompat
else:
  from std/envvars import getEnv
  from std/os import getCurrentDir

import pysubprocess

proc testCurrentDir(): string =
  when defined(js): getCurrentDirCompat()
  else: getCurrentDir()

proc testGetEnv(name: string): string =
  when defined(js): getEnvCompat(name)
  else: getEnv(name)

suite "subprocess":
  test "run captures stdout and stderr":
    let completed = run(["node", "-e",
      "process.stdout.write('out'); process.stderr.write('err')"],
      capture_output = true)
    check completed.args[0] == "node"
    check completed.returncode == 0
    check completed.stdout == "out"
    check completed.stderr == "err"

  test "input is sent to stdin":
    let output = check_output(["node", "-e",
      "process.stdin.pipe(process.stdout)"], input = "hello")
    check output == "hello"

  test "stderr can be redirected to stdout":
    let completed = run(["node", "-e",
      "process.stdout.write('out'); process.stderr.write('err')"],
      stdout = PIPE, stderr = STDOUT)
    check completed.stdout == "outerr"
    check completed.stderr == ""

  test "STDOUT is rejected as a stdout target":
    expect ValueError:
      discard run(["node"], stdout = STDOUT)

  test "cwd and environment are forwarded":
    let env = newStringTable(modeCaseSensitive)
    env["PYSUBPROCESS_TEST"] = "works"
    env["PATH"] = testGetEnv("PATH")
    let completed = run(["node", "-e",
      "const p=require('node:path'); process.stdout.write(p.basename(process.cwd()) + '\\n' + process.env.PYSUBPROCESS_TEST)"],
      cwd = testCurrentDir(), env = env, stdout = PIPE)
    let lines = completed.stdout.splitLines()
    check lines[0] == "pysubprocess"
    check lines[1] == "works"

  test "check raises CalledProcessError":
    try:
      discard run(["node", "-e",
        "process.stdout.write('bad'); process.stderr.write('worse'); process.exit(7)"],
        capture_output = true, check = true)
      fail()
    except CalledProcessError as error:
      check error.returncode == 7
      check error.output == "bad"
      check error.stderr == "worse"

  test "call and check_call":
    check call(["node", "-e", "process.exit(3)"]) == 3
    check check_call(["node", "-e", ""]) == 0

  test "single argument vectors and check_returncode":
    let completed = run(["node"], stdout = DEVNULL, stderr = DEVNULL)
    check completed.returncode == 0
    completed.check_returncode()

  test "getstatusoutput strips the final newline":
    let (status, output) = getstatusoutput(
      "node -e \"console.log('hello')\"")
    check status == 0
    check output == "hello"
