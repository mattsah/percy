import
    percy,
    basecli

type
    RequireCommand = ref object of BaseGraphCommand

begin RequireCommand:
    #[
        Add or update related nimble info for the given requirement
    ]#
    method updateNimbleInfo(graph: DepGraph, requirement: Requirement): bool {. base .} =
        let
            requireNext = this.nimbleInfo.requires.len
        var
            existingRequirement: Requirement

        result = true

        for i, requirements in this.nimbleInfo.requires:
            for j, existingLine in requirements:
                existingRequirement = graph.parseRequirement(existingLine)

                if requirement.repository.url == existingRequirement.repository.url:
                    this.nimbleInfo.requires[i][j] = $requirement
                    result = false

        if result:
            this.nimbleMap = this.nimbleMap & "\n" & "{%requires-" & $requireNext & "%}"
            this.nimbleInfo.requires.add(@[$requirement])

    #[
        Execute the command
    ]#
    method execute(console: Console): int =
        result = super.execute(console)

        let
            skip = parseBool(console.getOpt("skip-resolution"))
            package = console.getArg("package")
            versions = console.getArg("versions")
            graph = this.getGraph()
        var
            isAdded: bool
            newContent: string
            requirement: Requirement

        try:
            requirement = graph.parseRequirement(strip(fmt "{package} {versions}"))
        except Exception as e:
            fail fmt "Invalid version constraints specified:"
            info fmt "> Error: {e.msg}"
            info fmt "> Versions: {versions}"
            return 1

        try:
            Repository.validateUrl(requirement.repository.url)
        except Exception as e:
            fail fmt "Invalid package specified"
            info fmt "> Error: {e.msg}"
            info fmt "> Package: {package}"
            info fmt "> URL: {requirement.repository.url}"
            return 2

        if not requirement.repository.exists:
            fail fmt "Cannot resolve package '{package}'"
            if dirExists(requirement.repository.url):
                info fmt "> Hint: the path in question may not be a git repository"
            elif requirement.repository.url.contains("://"):
                info fmt "> Hint: check for errors in the URL and make sure it's reachable"
            else:
                info fmt "> Hint: you may need to add a source with `percy set`"
            return 3

        isAdded = this.updateNimbleInfo(graph, requirement)
        newContent = parser.render(this.nimbleMap, this.nimbleInfo)

        discard requirement.repository.update(quiet = this.verbosity < 1, force = true)

        if not skip:
            result = this.resolve()

        if result == 0:
            writeFile(this.nimbleFile, newContent)
        else:
            fail fmt "Unable to update after adding new requirement, no files written"
            info fmt "> Package: {package}"
            return 10 + result

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
            CommandSkipOpt,
        ]
    )
]
