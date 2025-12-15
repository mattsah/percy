import
    percy,
    basecli

type
    UnsetCommand = ref object of BaseGraphCommand

begin UnsetCommand:
    method execute(console: Console): int =
        result = super.execute(console)

        let
            setType = console.getArg("type")
            setAlias = console.getArg("alias")

        # validate alias
        # validate url

        case setType:
            of "source":
                this.settings.data.sources.del(setAlias)
            of "package":
                this.settings.data.packages.del(setAlias)

        this.settings.prepare()
        # Check if dependency graph still works with these settings
        # warn if not that packages should be removed or fixed up
        this.settings.save()

shape UnsetCommand: @[
    Command(
        name: "unset",
        description: "Unset a source or package URL",
        opts: @[
            CommandFileOpt
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