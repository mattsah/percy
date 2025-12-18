import
    percy,
    basecli

type
    InfoCommand = ref object of BaseGraphCommand

begin InfoCommand:
    method execute(console: Console): int =
        result = super.execute(console)

        if console.getOpt("json", "j") of true:
            echo %this.nimbleInfo
        else:
            echo "shove it"
        discard

shape InfoCommand: @[
    Command(
        name: "info",
        description: "Remove a package from your project's dependencies",
        opts: @[
            Opt(
                flag: "j",
                name: "json",
                description: "Get the output as JSON"
            )
        ]
    )
]