import
    mininim,
    mininim/cli,
    lib/settings

type
    InitCommand = ref object of Class

begin InitCommand:
    method execute(console: Console): int {. base .} =
        let
            fileName = console.getOpt("file", "f")
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
        opts: @[
            Opt(
                name: "file",
                default: "percy.json",
                description: "The settings filename"
            )
        ]
    )
]