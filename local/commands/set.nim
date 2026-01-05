import
    percy,
    basecli,
    lib/package,
    lib/source,
    std/uri

type
    SetCommand = ref object of BaseGraphCommand

#[
    The `set` command is responsible for adding a source or package to the configuration file,
    triggering updates and re-indexing of existing and new sources and packages and, by default
    attempting to re-resolve the dependency graph.  Resolution can be skipped via the `-s` option
    in order to enable configuration management only.
]#
begin SetCommand:
    #[
        Execute the command
    ]#
    method execute(console: Console): int =
        result = super.execute(console)

        let
            skip = parseBool(console.getOpt("skip-resolution"))
            setUrl = console.getArg("url")
            setType = console.getArg("type")
            repository = Repository.init(setUrl)
        var
            setAlias = console.getArg("alias").toLower()

        if setAlias == "<path of url>":
            setAlias = parseUri(repository.url).path.toLower().strip(chars = {'/'})

        try:
            case setType:
                of "source":
                    Source.validateName(setAlias)
                    this.settings.data.sources[setAlias] = Source.init(repository)
                of "package":
                    Package.validateName(setAlias)
                    this.settings.data.packages[setAlias] = Package.init(repository)
        except Exception as e:
            fail fmt "Invalid {setType} alias specified"
            info fmt "> Error: {e.msg}"
            info fmt "> Alias: {setAlias}"
            return 1

        try:
            Repository.validateUrl(repository.url)

            if not repository.exists:
                raise newException(
                    ValueError,
                    fmt "could not reach repository at {setUrl}"
                )

        except Exception as e:
            fail fmt "Invalid url specified"
            info fmt "> Error: {e.msg}"
            info fmt "> URL: {setUrl}"
            return 2

        this.settings.prepare(force = true, save = false)

        if not skip:
            result = this.resolve()

        if result == 0:
            this.settings.save()
            print fmt "Successfully added {setType}"
            print fmt "> URL: {repository.url}"
            print fmt "> Alias: {setAlias}"
        else:
            fail fmt "Unable to update after setting {setType}, no files written"
            info fmt "> URL: {repository.url}"
            info fmt "> Alias: {setAlias}"
            result = 10 + result

shape SetCommand: @[
    Command(
        name: "set",
        description: "Set a source or package URL for the project in the current directory",
        opts: @[
            CommandConfigOpt,
            CommandVerbosityOpt,
            CommandSkipOpt,
        ],
        args: @[
            Arg(
                name: "type",
                values: @["source", "package"],
                description: "The type of URL to set"
            ),
            Arg(
                name: "url",
                description: "A valid git URL for the source or package repository"
            ),
            Arg(
                name: "alias",
                default: "<path of url>",
                description: "The alias for the source or package"
            )
        ]
    )
]
