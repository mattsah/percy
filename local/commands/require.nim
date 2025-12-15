import
    percy,
    basecli

type
    RequireCommand = ref object of BaseGraphCommand

begin RequireCommand:
    method execute(console: Console): int =
        result = super.execute(console)

        this.settings.prepare()
        # Add requirement to the .nimble file
        # re-run dependency graph

shape RequireCommand: @[
    Command(
        name: "require",
        description: "Add a requirement to the project",
        opts: @[
            CommandFileOpt
        ]
    )
]