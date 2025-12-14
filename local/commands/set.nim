import
    percy,
    mininim/cli,
    lib/settings,
    lib/package,
    lib/source

type
    SetCommand = ref object of Class

begin SetCommand:
    method execute(console: Console): int {. base .} =
        let
            setUrl = console.getArg("url")
            setType = console.getArg("type")
            setAlias = console.getArg("alias")
            fileName = console.getOpt("file", "f")
            settings = Settings.init()

        settings.load(fileName)

        # validate alias
        # validate url

        case setType:
            of "source":
                settings.data.sources[setAlias] = Source.init(setUrl)
            of "package":
                settings.data.packages[setAlias] = Package.init(setUrl)

        settings.save(fileName)

shape SetCommand: @[
    Command(
        name: "set",
        description: "Set a source or package URL",
        opts: @[
            Opt(
                name: "file",
                flag: "f",
                default: "percy.json",
                description: "The settings filename"
            )
        ],
        args: @[
            Arg(
                name: "type",
                require: true,
                values: @["source", "package"],
                description: "The type of URL to set"
            ),
            Arg(
                name: "alias",
                require: true,
                description: "The alias for the source or package"
            ),
            Arg(
                name: "url",
                require: true,
                description: "A valid git URL to the source or package repository"
            )
        ]
    )
]