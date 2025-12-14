import
    mininim,
    mininim/cli,
    lib/settings

type
    RequireCommand = ref object of Class

begin RequireCommand:
    method execute(console: Console): int {. base .} =
        discard

shape RequireCommand: @[
    Command(
        name: "require",
        description: "Add a requirement to the project",
        args: @[
            Arg(
                name: "file",
                require: false,
                description: "The settings filename"
            )
        ]
    )
]