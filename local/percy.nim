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
    Get the current directory relative vendor dir or a subdirectory of it
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
    Execute a command capture its output, excluding STDERR
]#
proc execCmdCapture*(output: var string, parts: seq[string]): int =
    when defined windows:
        (output, result) = execCmdEx(parts.join(" ") & " 2>NUL")
    else:
        (output, result) = execCmdEx(parts.join(" ") & " 2>/dev/null")

    output = output.strip()

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
    Execute the contents of the callback within a new directory, by default Percy's, then
    change the directory back to the original before return.
]#
proc execIn*(callback: ExecHook, dir: string = percy.getAppLocalDir()): void =
    let
        originalDir = getCurrentDir()

    if dir != originalDir:
        when defined debug:
            info fmt "Entering directory '{dir}'"
        setCurrentDir(dir)

    callback()

    if dir != originalDir:
        when defined debug:
            info fmt "Leaving directory '{dir}'"
        setCurrentDir(originalDir)

#[
    Version overload with fixups to solve for bad semver
]#
proc ver*(version: string): Version =
    let
        lowered = version.toLower()
        cleaned = lowered.replace(re"[!@#$%^&*+_.,/]", "-")

    if lowered in ["any", "head"]: # any or explit HEAD
        return v("0.0.0-HEAD")
    if lowered.startsWith("head@"): # explicit branch
        return v("0.0.0-branch." & cleaned[5..^1])
    if lowered.len >= 4 and lowered.len <= 40 and lowered.match(re"^[a-f0-9]+$"): # implicit commit
        return v("0.0.0-commit." & lowered)
    if lowered.match(re"^v?[0-9]+\.[0-9]+(\.[0-9]+)?.*"): # implicit version tag
        var
            dotCount = 0
            versionTail: string
            versionClean: string
            versionParts: seq[string]

        for i in lowered:
            if i == '.':
                inc dotCount
            if i in {'0'..'9', 'v', '.'} and dotCount < 3:
                versionClean.add(i)
            else:
                break

        versionParts = versionClean.strip(chars = {'v', '.'}).split('.', 2)

        if versionParts.len < 3:
            versionParts.add("0")
        if cleaned.len > versionClean.len:
            versionTail = "-" & cleaned[versionClean.len..^1].strip("-")

        return v(versionParts.mapIt($parseInt(it)).join('.') & versionTail)

    return v("0.0.0-branch." & cleaned)
