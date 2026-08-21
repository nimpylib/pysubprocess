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

  test "missing commands raise OSError":
    expect OSError:
      discard run(["pysubprocess-command-that-does-not-exist"],
        capture_output = true)

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

  test "timeout raises the public exception with captured fields":
    try:
      discard run(["node", "-e",
        "process.stdout.write('partial'); setTimeout(() => {}, 1000)"],
        stdout = PIPE, stderr = PIPE, timeout = 0.05)
      fail()
    except TimeoutExpired as error:
      check error.cmd[0] == "node"
      check error.timeout == 0.05
      check error.stdout == error.output

  test "Popen communicate and attributes":
    let child = Popen(["node", "-e",
      "process.stdin.on('data', d => process.stdout.write(d)); process.stdin.on('end', () => process.stderr.write('done'))"],
      stdin = PIPE, stdout = PIPE, stderr = PIPE)
    check child.args[0] == "node"
    check child.returncode.isNone
    let (childOut, childErr) = child.communicate("hello")
    check childOut == "hello"
    check childErr == "done"
    check child.returncode.get == 0
    check child.poll().get == 0

  test "Popen wait returns the exit status":
    let child = Popen(["node", "-e", "process.exit(4)"],
      stdout = DEVNULL, stderr = DEVNULL)
    check child.wait() == 4
    check child.returncode.get == 4

  when not defined(js):
    test "Popen wait timeout leaves child available for termination":
      let child = Popen(["node", "-e", "setTimeout(() => {}, 1000)"],
        stdout = DEVNULL, stderr = DEVNULL)
      expect TimeoutExpired:
        discard child.wait(0.02)
      child.kill()
      check child.wait() != 0

  test "encoding compatibility parameters are accepted":
    check check_output(["node", "-e", "process.stdout.write('ok')"],
      encoding = "utf-8", errors = "strict", text = true,
      universal_newlines = true) == "ok"
    check getoutput("node -e \"process.stdout.write('ok')\"",
      encoding = "utf-8", errors = "strict") == "ok"

  test "generated string overloads match argv overloads":
    check call("node", stdin = DEVNULL, stdout = DEVNULL, stderr = DEVNULL) == 0
    check check_output("node -e \"process.stdout.write('ok')\"",
      shell = true) == "ok"
    let child = Popen("node", stdin = DEVNULL, stdout = DEVNULL,
      stderr = DEVNULL)
    check child.wait() == 0
