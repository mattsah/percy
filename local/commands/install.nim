import
    percy,
    basecli,
    lib/lockfile

type
    InstallCommand = ref object of BaseGraphCommand

begin InstallCommand:
    #[
        Execute the command
    ]#
    method execute(console: Console): int =
        result = super.execute(console)

        let
            force = parseBool(console.getOpt("force"))
            loader = this.getLoader()
        var
            lockFile: LockFile

        try:
            lockFile = LockFile.init("percy.lock")
        except Exception as e:
            fail fmt "Unable to install from lockfile"
            info fmt "> Error: {e.msg}"
            return 1

        if lockFile.exists:
            discard loader.loadSolution(lockFile.solution, force)
        else:
            let
                subConsole = this.app.get(Console, false)
            var
                command = @["update", "-n", "-p"]

            if this.verbosity:
                command.add("-v:" & $this.verbosity)
            if force:
                command.add("-f")

            result = subConsole.run(command)

            if result != 0:
                result = 10 + result

shape InstallCommand: @[
    Command(
        name: "install",
        description: "Install locked dependencies for the project in the current directory",
        opts: @[
            CommandConfigOpt,
            CommandVerbosityOpt,
            Opt(
                flag: 'f',
                name: "force",
                description: "Force checkouts which may otherwise destroy unsaved work in vendor"
            )
        ]
    )
]
