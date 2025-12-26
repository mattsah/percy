import
    percy,
    basecli

type
    RequireCommand = ref object of BaseGraphCommand

begin RequireCommand:
    method execute(console: Console): int =
        result = super.execute(console)

        let
            graph = this.getGraph()
            package = console.getArg("package")
            versions = console.getArg("versions")
            requireCount = this.nimbleInfo.requires.len
        var
            hasAddition = true
            newContent: string
            requireLine: string
            requirement: Requirement

        if versions.toLower() == "any":
            requireLine = strip(fmt "{package}")
        else:
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
                    hasAddition = false

        if hasAddition:
            this.nimbleMap = this.nimbleMap & "\n" & "{%requires-" & $requireCount & "%}"
            this.nimbleInfo.requires.add(@[requireLine])

        newContent = parser.render(this.nimbleMap, this.nimbleInfo)

        result = this.resolve()

        if result == 0:
            writeFile(this.nimbleFile, newContent)
        else:
            fail fmt "Unable to update after adding new requirement, no files written"
            info fmt "> Package: {package}"

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