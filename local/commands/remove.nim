import
    percy,
    basecli

type
    RemoveCommand = ref object of BaseGraphCommand

begin RemoveCommand:
    method execute(console: Console): int =
        result = super.execute(console)

        this.settings.prepare()
        # remove requirement from the nimble file
        # re-run dependency graph

shape RemoveCommand: @[
    Command(
        name: "remove",
        description: "Remove a package from your project's dependencies",
        opts: @[
            CommandFileOpt
        ]
    )
]