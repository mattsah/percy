#
# Common arguments
#

--mm:atomicArc
--deepcopy:on
--verbosity:1
--path:"./local"
--path:"./vendor"

# <percy>

when withDir(thisDir(), system.fileExists("vendor/percy.paths")):
    include "vendor/percy.paths"

# </percy>
# <percy>

import
    std/os,
    std/strutils

#
# Internal commands
#

proc build(args: seq[string]): void =
    for path in listFiles("./"):
        if path.endsWith(".nim"):
            exec @[
                "nim -o:bin/" & splitFile(path).name,
                commandLineParams()[1..^1].join(" "),
                args.join(" "),
                "c " & path
            ].join(" ")

# Tasks

task test, "Run testament tests":
    exec "testament --megatest:off --directory:testing " & commandLineParams()[1..^1].join(" ")

task build, "Build the application (whatever it's called)":
    when defined release:
        build(@["--opt:speed", "--linetrace:on", "--checks:on"])
    elif defined debug:
        build(@["--debugger:native", "--stacktrace:on", "--linetrace:on", "--checks:on"])
    else:
        build(@["--stacktrace:on", "--linetrace:on", "--checks:on"])

# </percy>