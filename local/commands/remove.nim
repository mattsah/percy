import
    percy,
    basecli

type
    RemoveCommand = ref object of BaseGraphCommand

begin RemoveCommand:
    method execute(console: Console): int =
        result = super.execute(console)

        let
            skip = parseBool(console.getOpt("skip-resolution"))
            package = console.getArg("package")
            repository = this.settings.getRepository(package)
            graph = this.getGraph()
        var
            isRemoved = false
            newContent: string

        for i, requirements in this.nimbleInfo.requires:
            for j, existingLine in requirements:
                let
                    existingRequirement = graph.parseRequirement(existingLine)
                if repository.url == existingRequirement.repository.url:
                    this.nimbleInfo.requires[i].delete(j..j)

                    if this.nimbleInfo.requires[i].len == 0:
                        var
                            mapLines = this.nimbleMap.split('\n')
                            lineNums = mapLines.high

                        for line in 0..lineNums:
                            if mapLines[line].endsWith("{%requires-" & $i & "%}"):
                                let
                                    indent = alignLeft("", mapLines[line].find('{'), ' ')
                                var
                                    revLine = line
                                    forLine = line
                                    isAlone = true

                                while revLine > 0:
                                    dec revLine
                                    #
                                    # If we find whitespace, just continue
                                    #
                                    if mapLines[revLine].strip() == "":
                                        continue
                                    #
                                    # If we find a line before with same indentation we can't
                                    # delete the block
                                    #
                                    if mapLines[revLine].startsWith(indent):
                                        revLine = line
                                        isAlone = false
                                    break

                                while forLine < lineNums:
                                    inc forLine
                                    if mapLines[forLine].strip() == "":
                                        continue
                                    if mapLines[forLine].startsWith(indent):
                                        forLine = line
                                        isAlone = false
                                    break

                                #
                                # If we're not alone in our block, we reset our revLine
                                # so we don't delete the block start.
                                #
                                if not isAlone:
                                    revLine = line

                                #
                                # Account for deleted lines on next iteration of loop and
                                # delete the lines
                                #
                                isRemoved = true
                                lineNums = forLine - revLine + 1
                                mapLines.delete(revLine..forLine)
                            else:
                                discard

                        this.nimbleMap = mapLines.join('\n')

        if not isRemoved:
            fail fmt "Package '{package}' does not seem to be currently required"
            if not repository.url.contains("://"):
                info fmt "  Hint: you may have added it as a URL instead of a package alias"

            return 1

        newContent = parser.render(this.nimbleMap, this.nimbleInfo)

        if not skip:
            result = this.resolve()

        if result == 0:
            writeFile(this.nimbleFile, newContent)
        else:
            fail fmt "Unable to update after removing requirement, no files written"
            info fmt "> Package: {package}"

shape RemoveCommand: @[
    Command(
        name: "remove",
        description: "Remove a package from your project's dependencies",
        args: @[
            Arg(
                name: "package",
                description: "The package to remove, an alias or a URL"
            )
        ],
        opts: @[
            CommandConfigOpt,
            CommandVerbosityOpt,
            CommandSkipOpt,
        ]
    )
]
