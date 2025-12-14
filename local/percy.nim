import
    mininim,
    lib/nimble/parser,
    std/osproc

export
    mininim,
    osproc

const
    name* = "percy"
    target* = "vendor"
    index* = "index.json"

type
    ExecHook* = proc(): void

proc getNimbleInfo*(): NimbleFileInfo =
    for file in walkFiles("*.nimble"):
        return parser.parseFile(readFile(file))
    raise newException(ValueError, "Could not find .nimble file")

proc getLocalDir*(subdir: string = ""): string =
    when defined(linux):
        result = getHomeDir() / ".local" / "share" / percy.name / subdir
    else:
        result = getHomeDir() / ("." & percy.name) / subdir

proc getAppCacheDir*(subdir: string = ""): string =
    result = percy.getLocalDir("cache" / subdir)

proc execCmd*(parts: seq[string]): int =
    result = execCmd(parts.join(" "))

proc execCmdEx*(output: var string, parts: seq[string]): int =
    (output, result) = execCmdEx(parts.join(" "))

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
            echo fmt "Entering directory '{dir}'"
        setCurrentDir(dir)
    try:
        callback()
    finally:
        when defined debug:
            echo fmt "Leaving directory '{dir}'"
        setCurrentDir(originalDir)