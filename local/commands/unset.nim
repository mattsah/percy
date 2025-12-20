import
    percy,
    basecli

type
    UnsetCommand = ref object of BaseGraphCommand

begin UnsetCommand:
    method execute(console: Console): int =
        result = super.execute(console)

        let
            unsetType = console.getArg("type")
            unsetAlias = console.getArg("alias")
        var
            graph: DepGraph

        case unsetType:
            of "source":
                if not this.settings.data.sources.hasKey(unsetAlias):
                    stderr.writeLine(fmt "Invalid source alias '{unsetAlias}' specified")
                    stderr.writeLine(fmt "  Error: does not appear to be set.")
                    return 1
                this.settings.data.sources.del(unsetAlias)

            of "package":
                if not this.settings.data.packages.hasKey(unsetAlias):
                    stderr.writeLine(fmt "Invalid package alias '{unsetAlias}' specified")
                    stderr.writeLine(fmt "  Error: does not appear to be set.")
                    return 1
                this.settings.data.packages.del(unsetAlias)

        this.settings.prepare(true)

        try:
            graph = this.buildGraph(true)
            # TODO: Validate solution and suggest running update
            this.settings.save()
        except:
            raise getCurrentException() # replace with handling

shape UnsetCommand: @[
    Command(
        name: "unset",
        description: "Unset a source or package URL",
        opts: @[
            CommandConfigOpt,
            CommandVerboseOpt,
        ],
        args: @[
            Arg(
                name: "type",
                values: @["source", "package"],
                description: "The type of URL to unset"
            ),
            Arg(
                name: "alias",
                description: "The alias for the source or package"
            )
        ]
    )
]