import
    mininim,
    mininim/cli,
    lib/settings

type
    InitCommand = ref object of Class

begin InitCommand:
    method execute(console: Console): int {. base .} =
        let
            fileName = console.getArg("file", "percy.json")
            settings = Settings.init()

        settings.load(fileName)

        #
        # Ask Questions
        #

        settings.save(fileName)

shape InitCommand: @[
    Command(
        name: "init",
        description: "Initialize as a percy package",
        args: @[
            Arg(
                name: "file",
                require: false,
                description: "The settings filename"
            )
        ]
    )
]