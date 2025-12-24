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
            infoType = console.getArg("type", "nimble")
            useJson = console.getOpt("json") of true
            graph = this.getGraph()

        case infoType:
            of "nimble":
                if useJson:
                    print pretty(%this.nimbleInfo)
                    return 0
                else:
                    print "Not Implemented Yet"
            of "lock", "graph":
                let
                    locks = parseJson(readFile("percy.lock"))

                if useJson and infoType == "lock":
                    print pretty(locks)
                else:
                    let
                        lockCount = locks.len
                    var
                        dependents = initOrderedTable[Commit, OrderedSet[Commit]](lockCount)
                        dependencies = initOrderedTable[Commit, OrderedSet[Commit]](lockCount)
                        workDirs = initTable[Commit, string](lockCount)
                        commits = newSeq[Commit](lockCount)

                    for i, node in locks.getElems():
                        let
                            commit = Commit.fromLockFile(node)
                        commits[i] = commit
                        workDirs[commit] = this.settings.getWorkDir(commit.repository.url)
                        dependents[commit] = initOrderedSet[Commit]()

                    commits = commits.sortedByIt(workDirs[it])

                    if infoType == "graph":
                        proc collectRequirements(commit: Commit): void =
                            dependencies[commit] = initOrderedSet[Commit]()
                            for requirements in commit.info.requires:
                                for requirement in requirements:
                                    let
                                        requirement = graph.parseRequirement(requirement)
                                    for i, node in locks.getElems():
                                        let
                                            nodeUrl = node["repository"].getStr()
                                        if nodeUrl == requirement.repository.url:
                                            dependencies[commit].incl(commits[i])
                                            if not dependencies.hasKey(commits[i]):
                                                collectRequirements(commits[i])
                                            for subDependency in dependencies[commits[i]]:
                                                dependencies[commit].incl(subDependency)

                        for commit in commits:
                            collectRequirements(commit)

                        for commit in commits:
                            for dependent, dependencies in dependencies:
                                if dependencies.contains(commit):
                                    dependents[commit].incl(dependent)

                            dependents[commit] = dependents[commit]
                                .toSeq()
                                .sortedByIt(workDirs[it])
                                .toOrderedSet()

                            dependencies[commit] = dependencies[commit]
                                .toSeq()
                                .sortedByIt(workDirs[it])
                                .toOrderedSet()

                    if useJson:
                        var
                            results = newJObject()
                        for i, commit in commits:
                            results[workDirs[commit]] = %(
                                commit: commit.id,
                                version: $commit.version,
                                dependents: dependents[commit].mapIt(workDirs[it]),
                                dependencies: dependencies[commit].mapIt(workDirs[it])
                            )
                        print pretty(results)

                    else:
                        for i, commit in commits:
                            print fmt "{workDirs[commit]} [{fg.green}{$commit.version}{fg.stop}]"
                            print fmt "> URL: {commit.repository.url}"
                            print fmt "> Commit: {commit.id}"
                            if infoType == "graph" and dependents[commit].len:
                                print fmt "> Dependents: "
                                for dependent in dependents[commit]:
                                    print fmt "      {workDirs[dependent]}"

                            if infoType == "graph" and dependencies[commit].len:
                                print fmt "> Dependencies: "
                                for dependency in dependencies[commit]:
                                    print fmt "      {workDirs[dependency]}"


            else:
                fail fmt "Invalid type specified"

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