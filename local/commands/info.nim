import
    percy,
    basecli,
    lib/lockfile

type
    InfoCommand = ref object of BaseGraphCommand

begin InfoCommand:
    method execute(console: Console): int =
        result = super.execute(console)

        let
            infoType = console.getArg("type")
            useJson = console.getOpt("json") of true
            graph = this.getGraph()

        case infoType:
            of "nimble":
                if useJson:
                    print pretty(%this.nimbleInfo)
                else:
                    print this.nimbleInfo.description
                    print fmt "> Author: {this.nimbleInfo.author}"
                    print fmt "> License: {this.nimbleInfo.license}"
                    print fmt "> Requirements:"
                    for requirements in this.nimbleInfo.requires:
                        for requirement in requirements:
                            let
                                requirement = graph.parseRequirement(requirement)
                            print fmt "      ", 0
                            print fmt "{fg.green}{requirement.package}{fg.stop} ", 0
                            print fmt "{requirement.versions}"

            of "lock":
                let
                    lockFile = LockFile.init("percy.lock")

                if useJson:
                    print pretty(%lockFile)
                else:
                    for commit in lockFile.commits:
                        let
                            workDir = this.settings.getWorkDir(commit.repository.url)
                        print fmt "{workDir} [{fg.green}{$commit.version}{fg.stop}]"
                        print fmt "> URL: {commit.repository.url}"
                        print fmt "> Hash: {commit.repository.shaHash}"
                        print fmt "> Commit: {commit.id}"

            of "graph":
                let
                    lockFile = LockFile.init("percy.lock")
                    itemGraphs = lockFile.graph(graph, this.settings)

                if useJson:
                    var
                        results = newJObject()
                    for commit, itemGraph in itemGraphs:
                        results[itemGraph.directory] = %(
                            commit: commit.id,
                            version: $commit.version,
                            dependents: itemGraph.dependents.mapIt(itemGraphs[it].directory),
                            dependencies: itemGraph.dependencies.mapIt(itemGraphs[it].directory)
                        )

                    print pretty(results)

                else:
                    for commit, itemGraph in itemGraphs:
                        print fmt "{itemGraph.directory} [{fg.green}{$commit.version}{fg.stop}]"
                        print fmt "> URL: {commit.repository.url}"
                        print fmt "> Hash: {commit.repository.shaHash}"
                        print fmt "> Commit: {commit.id}"
                        if itemGraph.dependents.len:
                            print fmt "> Dependents: "
                            for dependent in itemGraph.dependents:
                                print fmt "      {itemGraphs[dependent].directory}"
                        if itemGraph.dependencies.len:
                            print fmt "> Dependencies: "
                            for dependency in itemGraph.dependencies:
                                print fmt "      {itemGraphs[dependency].directory}"

            else:
                fail fmt "Invalid type specified"
                return 1

shape InfoCommand: @[
    Command(
        name: "info",
        description: "Get useful information about this package",
        args: @[
            Arg(
                name: "type",
                values: @["nimble", "lock", "graph"],
                default: "nimble",
                description: "The type of information to get"
            )
        ],
        opts: @[
            CommandConfigOpt,
            CommandVerbosityOpt,
            Opt(
                flag: 'j',
                name: "json",
                description: "Get the information as JSON"
            )
        ]
    )
]
