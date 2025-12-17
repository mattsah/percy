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
            echo fmt "Entering directory '{dir}'"
        setCurrentDir(dir)
    try:
        callback()
    finally:
        when defined debug:
            echo fmt "Leaving directory '{dir}'"
        setCurrentDir(originalDir)

proc onlyDirs*(path: string): seq[string] =
    var
        directories = newSeq[string]()
        hasFiles = false
    for item in walkDir(path):
        if dirExists(item.path):
            if not symlinkExists(item.path):
                directories.add(item.path)
        else:
            hasFiles = true
    if not hasFiles:
        for subDirectory in directories:
            result.add(percy.onlyDirs(subDirectory))

    result.add(directories)