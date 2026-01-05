import
    percy,
    basecli

type
    UnsetCommand = ref object of BaseGraphCommand

#[
    The `unset` command is responsible for removing a source or package from the configuration
    file, triggering updates and re-indexing of remaining sources and packages and, by default
    attempting to re-resolve the dependency graph.  Resolution can be skipped via the `-s` option
    in order to enable configuration management only.
]#
begin UnsetCommand:
    #[
        Execute the command
    ]#
    method execute(console: Console): int =
        result = super.execute(console)

        let
            skip = parseBool(console.getOpt("skip-resolution"))
            unsetAlias = console.getArg("alias").toLower()
            unsetType = console.getArg("type")
        var
            repository: Repository

        try:
            case unsetType:
                of "source":
                    if not this.settings.data.sources.hasKey(unsetAlias):
                        raise newException(ValueError, "does not appear to be set")

                    repository = this.settings.data.sources[unsetAlias].repository
                    this.settings.data.sources.del(unsetAlias)

                of "package":
                    if not this.settings.data.packages.hasKey(unsetAlias):
                        raise newException(ValueError, "does not appear to be set")

                    repository = this.settings.data.packages[unsetAlias].repository
                    this.settings.data.packages.del(unsetAlias)

        except Exception as e:
            fail fmt "Invalid {unsetType} specified"
            info fmt "> Error: {e.msg}"
            info fmt "> Alias: {unsetAlias}"
            return 1

        this.settings.prepare(force = true, save = false)

        if not skip:
            result = this.resolve()

        if result == 0:
            this.settings.save()
            print fmt "Successfully unset {unsetType}"
            print fmt "> URL: {repository.url}"
            print fmt "> Alias: {unsetAlias}"
        else:
            fail fmt "Unable to update after unsetting {unsetType}, no files written"
            info fmt "> Repository: {repository.url}"
            info fmt "> Alias: {unsetAlias}"
            result = 10 + result

shape UnsetCommand: @[
    Command(
        name: "unset",
        description: "Unset a source or package for the project in the current directory",
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
