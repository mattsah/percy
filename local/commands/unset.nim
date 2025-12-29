import
    percy,
    basecli

type
    UnsetCommand = ref object of BaseGraphCommand

begin UnsetCommand:
    method execute(console: Console): int =
        result = super.execute(console)

        let
            skip = parseBool(console.getOpt("skip-resolution"))
            unsetType = console.getArg("type")
            unsetAlias = console.getArg("alias")
        var
            repository: Repository

        case unsetType:
            of "source":
                if not this.settings.data.sources.hasKey(unsetAlias):
                    fail fmt "Invalid source alias specified"
                    info fmt "> Error: does not appear to be set."
                    info fmt "> Source Alias: {unsetAlias}"
                    return 1

                repository = this.settings.data.sources[unsetAlias].repository
                this.settings.data.sources.del(unsetAlias)

            of "package":
                if not this.settings.data.packages.hasKey(unsetAlias):
                    fail fmt "Invalid package alias specified"
                    info fmt "> Error: does not appear to be set."
                    info fmt "> Package Alias: {unsetAlias}"
                    return 1

                repository = this.settings.data.packages[unsetAlias].repository
                this.settings.data.packages.del(unsetAlias)

        this.settings.prepare(true, skip)

        if not skip:
            result = this.resolve()

        if result == 0:
            this.settings.save()
            print fmt "Successfully unset {unsetType}"
            print fmt "> Repository: {repository.url}"
            print fmt "> Package Alias: {unsetAlias}"
        else:
            case unsetType:
                of "source":
                    fail fmt "Unable to update after unsetting source, no files written"
                    info fmt "> Repository: {repository.url}"
                    info fmt "> Source Alias: {unsetAlias}"

                of "package":
                    fail fmt "Unable to update after unsetting package, no files written"
                    info fmt "> Repository: {repository.url}"
                    info fmt "> Package Alias: {unsetAlias}"

shape UnsetCommand: @[
    Command(
        name: "unset",
        description: "Unset a source or package URL",
        opts: @[
            CommandConfigOpt,
            CommandVerbosityOpt,
            CommandSkipOpt,
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
