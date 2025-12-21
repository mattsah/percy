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
            graph = this.getGraph()
            solver = Solver.init()
            package = console.getArg("package")
            versions = console.getArg("versions")
            requireCount = this.nimbleInfo.requires.len
            requireLine = strip(fmt "{package} {versions}")

        var
            hasAddition = false
            newContent: string
            requirement: Requirement
            results: SolverResult

        try:
            requirement = graph.parseRequirement(requireLine)
        except:
            fail fmt "Invalid constraint '{versions}' specified:"
            info fmt "  Error: {getCurrentExceptionMsg()}"
            return 2

        if not requirement.repository.exists:
            fail fmt "Cannot resolve package '{package}'"
            if dirExists(requirement.repository.url):
                info fmt "  Hint: the path in question may not be a git repository"
            elif requirement.repository.url.contains("://"):
                info fmt "  Hint: check for errors in the URL and make sure it's reachable"
            else:
                info fmt "  Hint: you may need to add a source with `percy set`"
            return 1

        for i, requirements in this.nimbleInfo.requires:
            for j, existingLine in requirements:
                let
                    existingRequirement = graph.parseRequirement(existingLine)
                if requirement.repository.url == existingRequirement.repository.url:
                    this.nimbleInfo.requires[i][j] = requireLine
                else:
                    hasAddition = true

        if hasAddition:
            this.nimbleMap = this.nimbleMap & "\n" & "{%requires-" & $requireCount & "%}"
            this.nimbleInfo.requires.add(@[requireLine])

        newContent = parser.render(this.nimbleMap, this.nimbleInfo)

        try:
            graph.build(this.nimbleInfo)

            results = solver.solve(graph)

            if isSome(results.solution):
                discard this.loadSolution(results.solution.get())
                writeFile(this.nimbleFile, newContent)
            else:
                discard
        except:
            graph.reportStack()
            fail fmt "Failed updating with new requirement"
            info fmt "  Error: {getCurrentExceptionMsg()}"
            return 3

shape RequireCommand: @[
    Command(
        name: "require",
        description: "Add a requirement to the project",
        args: @[
            Arg(
                name: "package",
                description: "The package to require, a sourced alias or a URL"
            ),
            Arg(
                name: "versions",
                default: "any",
                description: "A valid versions constraint string such as 'any' or '>= 1.2'"
            )
        ],
        opts: @[
            CommandConfigOpt,
            CommandVerbosityOpt,
        ]
    )
]