import
    mininim,
    mininim/cli,
    lib/settings

type
    UnsetCommand = ref object of Class

begin UnsetCommand:
    method execute(console: Console): int {. base .} =
        let
            setType = console.getArg("type")
            setAlias = console.getArg("alias")
            fileName = console.getOpt("file", "f")
            settings = Settings.init()

        settings.load(fileName)

        # validate alias
        # validate url

        case setType:
            of "source":
                settings.data.sources.del(setAlias)
            of "package":
                settings.data.packages.del(setAlias)

        settings.save(fileName)

shape UnsetCommand: @[
    Command(
        name: "unset",
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
                description: "The type of URL to unset"
            ),
            Arg(
                name: "alias",
                require: true,
                description: "The alias for the source or package"
            )
        ]
    )
]