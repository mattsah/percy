import
    mininim,
    std/osproc,
    nimble/parser

export
    mininim,
    osproc,
    parser

const
    name* = "percy"
    target* = "vendor"

type
    ExecHook* = proc(): void

#[
    General Utilities (should always be used with percy.* prefix)
]#

proc getLocalDir*(subdir: string = ""): string =
    when defined(linux):
        result = getHomeDir() / ".local" / "share" / percy.name / subdir
    else:
        result = getHomeDir() / ("." & percy.name) / subdir

proc getAppCacheDir*(subdir: string = ""): string =
    result = percy.getLocalDir("cache" / subdir)

proc execCmd*(parts: seq[string]): int =
    result = execCmd(parts.join(" "))

proc execCmdCaptureAll*(output: var string, parts: seq[string]): int =
    when defined windows:
        (output, result) = execCmdEx(parts.join(" "))
    else:
        (output, result) = execCmdEx(parts.join(" "))

    output = output.strip()

proc execCmdCapture*(output: var string, parts: seq[string]): int =
    when defined windows:
        (output, result) = execCmdEx(parts.join(" ") & " 2>NUL")
    else:
        (output, result) = execCmdEx(parts.join(" ") & " 2>/dev/null")

    output = output.strip()

proc execCmds*(commands: varargs[seq[string]]): int =
    for command in commands:
        let
            error = execCmd(command)
        if error:
            return error
    return 0

proc execIn*(callback: ExecHook, dir: string = percy.getLocalDir()): void =
    let
        originalDir = getCurrentDir()
    if dir != "":
        when defined debug:
            print fmt "Entering directory '{dir}'"
        setCurrentDir(dir)
    try:
        callback()
    finally:
        when defined debug:
            print fmt "Leaving directory '{dir}'"
        setCurrentDir(originalDir)

proc hasFile*(path: string): bool =
    if dirExists(path):
        for item in walkDir(path):
            if fileExists(item.path):
                return true
    else:
        raise newException(ValueError, fmt "{path} is not a directory")