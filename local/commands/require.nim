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

        var
            graph = this.getGraph()
            changed = false
            package = console.getArg("package")
            versions = console.getArg("versions")
            newContent: string
            requirement: Requirement

        if versions == "any":
            versions = ""

        let
            requireCount = this.nimbleInfo.requires.len
            requireLine = strip(fmt "{package} {versions}")

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
                    changed = true

        if not changed:
            this.nimbleMap = this.nimbleMap & "\n" & "{%requires-" & $requireCount & "%}"
            this.nimbleInfo.requires.add(@[requireLine])

        newContent = parser.render(this.nimbleMap, this.nimbleInfo)

        try:
            graph.build(this.nimbleInfo)
            # TODO: Validate and run Solution
            writeFile(this.nimbleFile, newContent)
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