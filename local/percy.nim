import
    mininim,
    semver,
    std/re,
    std/osproc,
    nimble/parser

export
    mininim,
    semver,
    osproc,
    parser

const
    name* = "percy"
    target* = "vendor"

type
    ExecHook* = proc(): void

##
##  General Utilities (should always be used with percy.* prefix)
##

#[

]#
proc getVendorDir*(subdir: string = ""): string =
    result = getCurrentDir() / percy.target / subdir

#[
    Get the application's local dir or a subdirectory of it
]#
proc getAppLocalDir*(subdir: string = ""): string =
    when defined(linux):
        result = getHomeDir() / ".local" / "share" / percy.name / subdir
    else:
        result = getHomeDir() / ("." & percy.name) / subdir

#[
    Get the application's cache dir or a subdirectory of it
]#
proc getAppCacheDir*(subdir: string = ""): string =
    result = percy.getAppLocalDir("cache" / subdir)

#[
    Execute a sequence as a command
]#
proc execCmd*(parts: seq[string]): int =
    result = execCmd(parts.join(" "))

#[
    Execute multiple sequences as commands.
]#
proc execCmds*(commands: varargs[seq[string]]): int =
    for command in commands:
        let
            error = execCmd(command)
        if error:
            return error
    return 0

#[
    Execute a command capture its output, including STDERR
]#
proc execCmdCaptureAll*(output: var string, parts: seq[string]): int =
    when defined windows:
        (output, result) = execCmdEx(parts.join(" "))
    else:
        (output, result) = execCmdEx(parts.join(" "))

    output = output.strip()

#[
    Execute a command capture its output, excluding STDERR
]#
proc execCmdCapture*(output: var string, parts: seq[string]): int =
    when defined windows:
        (output, result) = execCmdEx(parts.join(" ") & " 2>NUL")
    else:
        (output, result) = execCmdEx(parts.join(" ") & " 2>/dev/null")

    output = output.strip()

#[
    Execute the contents of the callback within a new directory, by default Percy's, then
    change exit the directory back to the original.
]#
proc execIn*(callback: ExecHook, dir: string = percy.getAppLocalDir()): void =
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

#[
    Determine whether or not a directory contains any file (not just other directories)
]#
proc hasFile*(path: string): bool =
    if dirExists(path):
        for item in walkDir(path):
            if fileExists(item.path):
                return true
    else:
        raise newException(ValueError, fmt "{path} is not a directory")

#[
    Version overload with fixups to solve for bad semver
]#
proc ver*(version: string): Version =
    let
        lowered = version.toLower()
        cleaned = lowered.replace(re"[!@#$%^&*+_.,/]", "-")

    if lowered == "head": # explicit head
        return v("0.0.0-HEAD")
    if lowered.startsWith("head@"): # explicit branch
        return v("0.0.0-branch." & cleaned[5..^1])
    if lowered.len >= 4 and lowered.len <= 40 and lowered.match(re"^[a-f0-9]+$"): # implicit commit
        return v("0.0.0-commit." & lowered)
    if lowered.match(re"^(v?)[0-9]+\.[0-9]+.*"): # implicit version tag
        var
            verParts = lowered.split('.')
            newVersion = verParts[0].replace(re"[^0-9]", "") & "." & verParts[1]
            thirdDigit: int

        if verParts.len > 2:
            if parseInt(verParts[2], thirdDigit) == verParts[2].len:
                newVersion = newVersion & "." & $thirdDigit
                if verParts.len > 3:
                    newVersion = newVersion & "-" & cleaned.split('-')[3..^1].join("-")
            else:
                newVersion = newVersion & ".0-" & cleaned.split('-')[2..^1].join("-")
        else:
            newVersion = newVersion & ".0"

        return v(newVersion)

    return v("0.0.0-branch." & cleaned)
