import
    percy,
    basecli

type
    InitCommand = ref object of BaseCommand

begin InitCommand:
    method getPaths(): string {. base .} =
        result = dedent(
            fmt """
            # <{percy.name}>
            when withDir(thisDir(), system.fileExists("vendor/{percy.name}.paths")):
                include "vendor/{percy.name}.paths"
            # </{percy.name}>
            """
        )

    method testTask(): string {. base .} =
        result = dedent(
            fmt """
            # <{percy.name}>
            #
            # Test Task
            #

            task test, "Run testament tests":
                exec "testament --megatest:off --directory:testing " & commandLineParams()[1..^1].join(" ")

            # </{percy.name}>
            """
        )

    method buildTask(): string {. base .} =
        let
            cfg = "\"\"\"{\"bin\": \"\", \"srcDir\": \"\", \"binDir\": \"\"}\"\"\""

        result = dedent(
            fmt """
            # <{percy.name}>
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
                    cfg: JsonNode
                when defined(windows):
                    let
                        (info, error) = gorgeEx("percy info -j 2>NUL")
                else:
                    let
                        (info, error) = gorgeEx("percy info -j 2>/dev/null")
                if error > 0:
                    cfg = parseJson({cfg})
                else:
                    cfg = parseJson(info)

                let
                    bins = cfg["bin"].getElems()
                    srcDir = cfg["srcDir"].getStr()
                    binDir = cfg["binDir"].getStr()
                    output = if binDir.len > 0: binDir & "/" else: "./"

                for path in listFiles(if srcDir.len > 1: srcDir else: "./"):
                    if path.endsWith(".nim"):
                        let
                            target = path[path.find('/')+1..^5]
                        if bins.len == 0 or bins.contains(%target):
                            let
                                cmd = @[
                                    "nim -o:" & output,
                                    commandLineParams()[1..^1].join(" "),
                                    args.join(" "),
                                    "c " & path
                                ].join(" ")
                            echo "Executing: " & cmd
                            exec cmd

            task build, "Build the application (whatever it's called)":
                when defined release:
                    build(@["--opt:speed", "--linetrace:on", "--checks:on"])
                elif defined debug:
                    build(@["--debugger:native", "--stacktrace:on", "--linetrace:on", "--checks:on"])
                else:
                    build(@["--stacktrace:on", "--linetrace:on", "--checks:on"])
            # </{percy.name}>
            """
        )

    method execute(console: Console): int =
        result = super.execute(console)

        var
            nowrite = 0
            inBlock = false
            hasTests = false
            configIn: seq[string]
            configOut: seq[string]
            directory: string
            output: string
            error: int
        let
            target = console.getArg("target")
            reset = console.getOpt("reset")
            repo = console.getArg("repo")

        if repo:
            let
                repository = Repository.init(repo)

            if target.len == 0:
                directory = repository.url[repository.url.rfind('/')+1..^1]
            else:
                directory = target

            if dirExists(directory) or fileExists(directory):
                fail fmt "Cannot initialize repository in {target}, already exists"
                return 1

            error = percy.execCmdCaptureAll(output, @[
                fmt "git clone {repository.url} {target}"
            ])

            if error:
                fail fmt "Cannot initialize repository in {target}, clone failed"
                info indent(output, 2)
                return 2

            setCurrentDir(directory)

            this.settings = Settings.open(this.config)

        if not fileExists(this.settings.config) or reset of true:
            this.settings.data.sources.clear()
            this.settings.data.packages.clear()

            this.settings.data.meta = newJObject()
            this.settings.data.sources["nim-lang"] = Source.init(
                this.settings.getRepository("gh://nim-lang/packages")
            )

        if fileExists("config.nims"):
            configIn = readFile("config.nims").split('\n')

        for line in configIn:
            if inBlock and line.len > 0 and line[0] != ' ':
                inBlock = false
                dec nowrite
            if not inBlock and reset:
                if line.startsWith("task build,"):
                    inBlock = true
                    inc nowrite
                    continue
                if line.startsWith("task test,"):
                    hasTests = nowrite == 0
            if not inBlock and line == fmt "# <{percy.name}>":
                inc nowrite
                continue
            if not inBlock and line == fmt "# </{percy.name}>":
                dec nowrite
                continue
            if nowrite:
                continue

            configOut.add(line)

        var
            config = ""

        config = configOut.join("\n").strip()
        config = config & "\n\n" & this.getPaths().strip()

        if console.getOpt("writeTasks") of true:
            config = config & "\n\n" & this.buildTask.strip()

            if not hasTests:
                config = config & "\n\n" & this.testTask.strip()

        writeFile("config.nims", config)

        this.settings.prepare(true)
        this.settings.save()

        if repo:
            error = percy.execCmdCaptureAll(output, @[
                fmt "{getAppFilename()} install"
            ])

            if error:
                fail fmt "Could not complete installation"
                info indent(output, 2)
                return 3

        return 0

shape InitCommand: @[
    Command(
        name: "init",
        description: "Initialize as a percy package",
        args: @[
            Arg(
                name: "repo",
                description: "A repository to clone, if empty current directory is intialized"
            ),
            Arg(
                name: "target",
                description: "The directory to clone to, if empty named after repository"
            )
        ],
        opts: @[
            CommandConfigOpt,
            CommandVerbosityOpt,
            Opt(
                flag: 'w',
                name: "writeTasks",
                description: "Include nim build/test tasks"
            ),
            Opt(
                flag: 'r',
                name: "reset",
                description: "Reset the sources to standard nim and clear existing tasks"
            )
        ]
    )
]