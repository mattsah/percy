import
    percy,
    basecli

type
    InitCommand = ref object of BaseCommand

begin InitCommand:
    #[
        Get the path inclusion content
    ]#
    method getPaths(): string {. base .} =
        result = dedent(
            fmt """
            # <{percy.name}>
            --noNimblePath
            import
                std/strutils
            when withDir(thisDir(), system.fileExists("vendor/percy.paths")):
                for path in readFile("vendor/percy.paths").split("\n"):
                    if path.strip().len > 0:
                        switch("path", path)
            # </{percy.name}>
            """
        )

    #[
        Get the test task content
    ]#
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

    #[
        Get the build task content
    ]#
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
                    build(@["--opt:speed", "--checks:on"])
                elif defined debug:
                    build(@["--debugger:native", "--stacktrace:on", "--linetrace:on", "--checks:on"])
                else:
                    build(@["--stacktrace:on", "--linetrace:on", "--checks:on"])
            # </{percy.name}>
            """
        )

    #[
        Create a working copy of the given repository URL and get the path
    ]#
    method createWorkCopy(url: string, target: string): string {. base .} =
        let
            repository = Repository.init(url)
        var
            output: string
            error: int

        if target == "<repository name>":
            result = absolutePath(repository.url[repository.url.rfind('/')+1..^1])
        else:
            result = absolutePath(target)

        if dirExists(result) or fileExists(result):
            raise newException(
                ValueError,
                fmt "'{result}' already exists"
            )

        error = percy.execCmdCaptureAll(output, @[
            fmt "git clone {repository.url} {result}"
        ])

        if error:
            if this.verbosity > 0:
                print output

            raise newException(
                ValueError,
                fmt "cloning '{url}' failed"
            )

    #[
        Update the config.nims file in the current directory
    ]#
    method updateConfig(withoutTasks: bool = false): void {. base .} =
        var
            config = ""
            nowrite = 0
            inBlock = false
            hasTests = false
            hasBuild = false
            configIn: seq[string]
            configOut: seq[string]

        if fileExists("config.nims"):
            configIn = readFile("config.nims").split('\n')

        for line in configIn:
            if line.strip().startsWith("task build,"):
                hasBuild = nowrite == 0
            if line.strip().startsWith("task test,"):
                hasTests = nowrite == 0

            if inBlock and line.len > 0 and line[0] != ' ':
                inBlock = false
                dec nowrite
            if not inBlock and line == fmt "# <{percy.name}>":
                inc nowrite
                continue
            if not inBlock and line == fmt "# </{percy.name}>":
                dec nowrite
                continue
            if nowrite:
                continue

            configOut.add(line)

        config = configOut.join("\n").strip()
        config = config & "\n\n" & this.getPaths().strip()

        if not withoutTasks:
            if not hasBuild:
                config = config & "\n\n" & this.buildTask.strip()
            if not hasTests:
                config = config & "\n\n" & this.testTask.strip()

        writeFile("config.nims", config)

    #[
        Execute the command
    ]#
    method execute(console: Console): int =
        result = super.execute(console)

        let
            skip = parseBool(console.getOpt("skip-resolution"))
            reset = parseBool(console.getOpt("reset"))
            without = parseBool(console.getOpt("without-tasks"))
            target = console.getArg("target")
            url = console.getArg("url")

        if url != "<none>":
            try:
                setCurrentDir(this.createWorkCopy(url, target))
                this.settings = Settings.open(this.config)
            except Exception as e:
                fail fmt "Cannot initialize external package"
                info fmt "> Error: {e.msg}"
                return 1

        if not fileExists(this.settings.config) or reset:
            this.settings.data.sources.clear()
            this.settings.data.packages.clear()

            this.settings.data.meta = newJObject()
            this.settings.data.sources["nim-lang"] = Source.init(
                this.settings.getRepository("gh://nim-lang/packages")
            )

        if skip:
            this.settings.prepare(true, true)
            this.settings.save()
        else:
            this.updateConfig(without)
            this.settings.prepare(true, false)
            this.settings.save()

            if url != "<none>":
                let
                    subConsole = this.app.get(Console, false)
                var
                    command = @["install"]

                if this.verbosity:
                    command.add("-v:" & $this.verbosity)

                result = subConsole.run(command)

shape InitCommand: @[
    Command(
        name: "init",
        description: "Initialize a project or package",
        args: @[
            Arg(
                name: "url",
                default: "<none>",
                description: "Initialize an external package or project via a valid Git repository"
            ),
            Arg(
                name: "target",
                default: "<repository name>",
                description: "The local directory for an externally initialized package or project"
            )
        ],
        opts: @[
            CommandConfigOpt,
            CommandVerbosityOpt,
            CommandSkipOpt,
            Opt(
                flag: 'r',
                name: "reset",
                description: "Reset the configuration to defaults (standard nim sources, no meta)"
            ),
            Opt(
                flag: 'w',
                name: "without-tasks",
                description: "Do not include nim build/test tasks"
            )
        ]
    )
]
