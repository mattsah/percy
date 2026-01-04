#
# Common arguments
#

--mm:atomicArc
--deepcopy:on
--verbosity:1
--path:"local"

# begin Nimble config (version 2)
--noNimblePath
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config

# <percy>
--noNimblePath
import
    std/strutils
when withDir(thisDir(), system.fileExists("vendor/percy.paths")):
    for path in readFile("vendor/percy.paths").split("\n"):
        if path.strip().len > 0:
            switch("path", path)
# </percy>

# <percy>
#
# Build Task
#

import
    std/os,
    std/json,
    std/strutils

#
# Internal commands
#

proc build(args: seq[string]): void =
    var
        cfg = parseJson("{\"namedbin\":{},\"srcDir\":\".\",\"binDir\":\".\"}")
    when defined(windows):
        let
            (info, error) = gorgeEx("percy info -j 2>NUL")
    else:
        let
            (info, error) = gorgeEx("percy info -j 2>/dev/null")
    if error == 0:
        cfg = parseJson(info)

    let
        srcDir = strip(cfg["srcDir"].getStr(), leading = false, chars = {'/'}) & "/"
        binDir = strip(cfg["binDir"].getStr(), leading = false, chars = {'/'}) & "/"

    for srcName, binName in cfg["namedBin"]:
        let
            cmd = @[
                "nim -o:" & binDir & binName.getStr(),
                commandLineParams()[1..^1].join(" "),
                args.join(" "),
                "c " & srcDir & srcName
            ].join(" ")
        echo "Executing: " & cmd
        exec cmd

task build, "Build the application (whatever it's called)":
    when defined release:
        build(@["--opt:speed", "--checks:on"])
    elif defined debug:
        build(@["--debugger:native", "--stacktrace:on", "--linetrace:on", "--checks:on"])
    else:
        build(@["--stacktrace:on", "--linetrace:on", "--checks:on"])
# </percy>

# <percy>
#
# Test Task
#

task test, "Run testament tests":
    exec "testament --megatest:off --directory:testing " & commandLineParams()[1..^1].join(" ")

# </percy>