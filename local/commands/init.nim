import
    percy,
    basecli

type
    InitCommand = ref object of BaseCommand

const
    CommandSourceArg = Arg(
        name: "source",
        default: "none, init current directory",
        description: "An external git repository to be cloned for initialization"
    )

    CommandTargetArg = Arg(
        name: "target",
        default: "<source:basename>",
        description: "The directory in which the source will be "
    )

    CommandResetOpt = Opt(
        flag: 'r',
        name: "reset",
        description: "Reset the configuration to defaults (standard nim sources, no meta)"
    )

    CommandWithoutTasksOpt = Opt(
        flag: 'w',
        name: "without-tasks",
        description: "Do not include nim build/test tasks"
    )

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
            cfg = %(namedBin: (), srcDir: ".", binDir: ".")

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
                    cfg = parseJson({escape($cfg)})
                when defined(windows):
                    let
                        (info, error) = gorgeEx("percy info -j 2>NUL")
                else:
                    let
                        (info, error) = gorgeEx("percy info -j 2>/dev/null")
                if error == 0:
                    cfg = parseJson(info)

                let
                    srcDir = strip(cfg["srcDir"].getStr(), leading = false, chars = {{'/'}}) & "/"
                    binDir = strip(cfg["binDir"].getStr(), leading = false, chars = {{'/'}}) & "/"

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
            # </{percy.name}>
            """
        )

    #[
        Create a working copy of the given repository
    ]#
    method createWorkCopy(repository: Repository, workDir: string): void {. base .} =
        var
            output: string
            error: int

        if dirExists(workDir) or fileExists(workDir):
            raise newException(
                ValueError,
                fmt "'{workDir}' already exists"
            )

        error = percy.execCmdCaptureAll(output, @[
            fmt "git clone {repository.url} {workDir}"
        ])

        if error:
            if this.verbosity > 0:
                print output

            raise newException(
                ValueError,
                fmt "cloning '{repository.url}' failed"
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
            skip = parseBool(console.getOpt(CommandSkipOpt))
            reset = parseBool(console.getOpt(CommandResetOpt))
            without = parseBool(console.getOpt(CommandWithoutTasksOpt))
            target = console.getArg(CommandTargetArg)
            source = console.getArg(CommandSourceArg)
        var
            workDir: string

        if console.hasArg(CommandSourceArg):
            try:
                let
                    repository = this.settings.getRepository(source)

                if not console.hasArg(CommandTargetArg):
                    workDir = absolutePath(repository.url[repository.url.rfind('/')+1..^1])
                else:
                    workDir = absolutePath(target)

                this.createWorkCopy(repository, workDir)
                setCurrentDir(workDir)
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

        this.updateConfig(withoutTasks = without)

        if skip:
            this.settings.prepare(force = false, save = false)
            this.settings.save()
        else:
            this.settings.prepare(force = true, save = true)
            this.settings.save()

            if console.hasArg(CommandSourceArg):
                let
                    subConsole = this.app.get(Console, false)
                var
                    command = @["install"]

                if this.verbosity:
                    command.add("-v:" & $this.verbosity)

                result = subConsole.run(command)

                if result != 0:
                    result = 10 + result

shape InitCommand: @[
    Command(
        name: "init",
        description: "Initialize a project in the current directory or from an external source",
        args: @[
            CommandSourceArg,
            CommandTargetArg
        ],
        opts: @[
            CommandConfigOpt,
            CommandVerbosityOpt,
            CommandSkipOpt,
            CommandResetOpt,
            CommandWithoutTasksOpt
        ]
    )
]
