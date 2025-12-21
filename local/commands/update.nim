import
    percy,
    basecli

type
    UpdateCommand = ref object of BaseGraphCommand

begin UpdateCommand:
    method execute(console: Console): int =
        result = super.execute(console)

        this.settings.prepare(true)

shape UpdateCommand: @[
    Command(
        name: "update",
        description: "Update package(s) and corresponding version constraints",
        opts: @[
            CommandConfigOpt,
            CommandVerbosityOpt,
        ]
    )
]