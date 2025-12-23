import
    percy,
    basecli,
    lib/package,
    lib/source,
    std/uri

type
    SetCommand = ref object of BaseGraphCommand

begin SetCommand:
    method execute(console: Console): int =
        result = super.execute(console)

        let
            graph = this.getGraph()
            solver = Solver.init()
            setUrl = console.getArg("url")
            setType = console.getArg("type")
            repository = Repository.init(setUrl)
        var
            setAlias = console.getArg("alias")

        if setAlias == "<path of url>":
            setAlias = parseUri(repository.url).path.toLower().strip(chars = {'/'})

        case setType:
            of "source":
                try:
                    Source.validateName(setAlias)
                    this.settings.data.sources[setAlias] = Source.init(repository)
                except:
                    fail fmt "Invalid source alias specified"
                    info fmt "> Error: {getCurrentExceptionMsg()}"
                    info fmt "> Source Alias: {setAlias}"
                    return 1
            of "package":
                try:
                    Package.validateName(setAlias)
                    this.settings.data.packages[setAlias] = Package.init(repository)
                except:
                    fail fmt "Invalid package alias specified"
                    info fmt "> Error: {getCurrentExceptionMsg()}"
                    info fmt "> Package Alias: {setAlias}"
                    return 1

        try:
            Repository.validateUrl(repository.url)

            if not repository.exists:
                raise newException(
                    ValueError,
                    fmt "could not reach repository at {setUrl}"
                )
        except:
            fail fmt "Invalid url specified"
            info fmt ">  Error: {getCurrentExceptionMsg()}"
            return 2

        this.settings.prepare(true)

        try:
            graph.build(this.nimbleInfo)
            # TODO: Validate solution and suggest running update
            this.settings.save()
        except:
            raise getCurrentException() # replace with handling

        print fmt "Successfully added {setType}"
        print fmt "> Repository: {repository.url}"
        print fmt "> Package Alias: {setAlias}"
        result = 0

shape SetCommand: @[
    Command(
        name: "set",
        description: "Set a source or package URL",
        opts: @[
            CommandConfigOpt,
            CommandVerbosityOpt,
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