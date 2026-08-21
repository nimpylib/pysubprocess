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

  SubprocessError* = object of CatchableError
    ## Base class for errors raised by this module.

  CalledProcessError* = object of SubprocessError
    ## Raised when ``check=true`` and the command fails.
    returncode*: int
    cmd*: seq[string]
    output*: string
    stdout*: string
    stderr*: string

  TimeoutExpired* = object of SubprocessError
    ## Raised when a child process exceeds a requested timeout.
    cmd*: seq[string]
    timeout*: float
    output*: string
    stdout*: string
    stderr*: string

proc `$`*(completed: CompletedProcess): string =
  "CompletedProcess(args=" & $completed.args & ", returncode=" &
    $completed.returncode & ")"
