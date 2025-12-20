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
            file: string
            error: int

        this.settings.prepare()

        if not hook.endsWith(".nims"):
            file = hook & ".nims"

        if fileExists(file):
            error = execCmd(fmt "nim r --hints:off {file}")
        elif dirExists(hook):
            for file in walkDir(hook):
                if file.path.endsWith(".nims"):
                    error = execCmd(fmt "nim r {file.path}")
        else:
            echo "No hook(s) found"

shape HookCommand: @[
    Command(
        name: "hook",
        description: "Execute a hook from the `hooks` folder",
        opts: @[
            CommandConfigOpt,
            CommandVerboseOpt,
        ],
        args: @[
            Arg(
                name: "name",
                description: "The name of the hook in the `hooks` folder (just a relative path)"
            )
        ]
    )
]