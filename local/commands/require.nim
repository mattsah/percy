import
    percy,
    basecli,
    lib/depgraph,
    nimble/parser

type
    RequireCommand = ref object of BaseGraphCommand

begin RequireCommand:
    method execute(console: Console): int =
        result = super.execute(console)

        let
            package = console.getArg("package")
            versions = console.getArg("versions")
            repository = this.settings.getRepository(package)
            requireCount = this.nimbleInfo.requires.len
        var
            graph = this.getGraph()
            changed = false
            newContent: string

        if not repository.exists:
            stderr.writeLine(fmt "Cannot resolve package '{package}'")
            stderr.writeLine(fmt "  Error: {getCurrentExceptionMsg()}")
            return 1

        if package notin ["", "any"]:
            try:
                discard graph.parseConstraint(package, repository)
            except:
                stderr.writeLine(fmt "Invalid constraint '{versions}' specified:")
                stderr.writeLine(fmt "  Error: {getCurrentExceptionMsg()}")
                return 2

        for i, requirements in this.nimbleInfo.requires:
            for j, requirement in requirements:
                let
                    existingPackage = graph.parseRequirement(requirement)
                if repository.url == existingPackage.repository.url:
                    this.nimbleInfo.requires[i][j] = fmt "{package} {versions}"
                    changed = true

        if not changed:
            this.nimbleMap = this.nimbleMap & "\n" & "{%requires-" & $requireCount & "%}"
            this.nimbleInfo.requires.add(@[fmt "{package} {versions}"])

        newContent = parser.render(this.nimbleMap, this.nimbleInfo)

        try:
            graph = this.buildGraph(true)
            # TODO: Validate and run Solution
            writeFile(this.nimbleFile, newContent)
        except:
            stderr.writeLine(fmt "Failed updating with new requirement")
            stderr.writeLine(fmt "  Error: {getCurrentExceptionMsg()}")
            return 3

shape RequireCommand: @[
    Command(
        name: "require",
        description: "Add a requirement to the project",
        args: @[
            Arg(
                name: "package",
                description: "An alias in one of your configured sources/packages or a URL"
            ),
            Arg(
                name: "versions",
                description: "A valid versions constraint string such as 'any' or '>= 1.2'"
            )
        ],
        opts: @[
            CommandConfigOpt,
            CommandVerbosityOpt,
        ]
    )
]