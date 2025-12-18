import
    percy,
    basecli

type
    HookCommand = ref object of BaseGraphCommand

begin HookCommand:
    method execute(console: Console): int =
        result = super.execute(console)

        let
            hook = "hooks" / console.getArg("name")
        var
            error: int

        this.settings.prepare()

        if fileExists(hook & ".nims"):
            error = execCmd("nim r --hints:off " & hook & ".nims")
        elif dirExists(hook):
            for file in walkDir(hook):
                if file.path.endsWith(".nims"):
                    error = execCmd("nim r " & file.path)
        else:
            echo "No hook(s) found"

shape HookCommand: @[
    Command(
        name: "hook",
        description: "Remove a package from your project's dependencies",
        opts: @[
            CommandConfigOpt,
            CommandVerboseOpt,
        ],
        args: @[
            Arg(
                name: "name",
                description: "The name of the hook in the hooks dir",
                require: true
            )
        ]
    )
]