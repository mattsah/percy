import
    percy,
    basecli

type
    FetchCommand = ref object of BaseCommand

begin FetchCommand:
    #[

    ]#
    method resolveCommit(repository: Repository, version: Version): Commit {. base .} =
        var
            candidate: Option[Commit]

        if version.build.startsWith("commit."):
            candidate = repository.getCommit(version.build[7..^1])
            if isSome(candidate):
                return candidate.get()
        else:
            for candidate in repository.getCommits():
                if version == candidate.version:
                    return candidate

        raise newException(
            ValueError,
            "cannot find version corresponding to {$verison}"
        )

    #[

    ]#
    method initializeWorkTree(): int {. base .} =
        let
            console = this.app.get(Console, false)
        var
            command = @["init"]

        if this.verbosity:
            command.add("-v:" & $this.verbosity)

        result = console.run(command)

    #[

    ]#
    method updateWorkTree(): int {. base .} =
        let
            console = this.app.get(Console, false)
        var
            command = @["update", "-n", "-p"]

        if this.verbosity:
            command.add("-v:" & $this.verbosity)

        result = console.run(command)


    #[

    ]#
    method buildWorkTree(): HashSet[string] {. base .} =
        var
            error: int
            output: string
            existingFiles: HashSet[string]
            targetConfig: JsonNode
            nimbleInfo: NimbleFileInfo
            buildNode: JsonNode
            buildCmd = "nim build"

        if fileExists(fmt "{percy.name}.json"):
            targetConfig = parseFile(fmt "{percy.name}.json")
            buildNode = targetConfig.get("meta.build")

            if buildNode.kind == JString:
                buildCmd = buildNode.getStr()

        for file in walkDir(getCurrentDir()):
            if file.path.endsWith(".nimble"):
                nimbleInfo = parser.parse(readFile(file.path))
                break

        for file in walkDir(getCurrentDIr() / nimbleInfo.binDir):
            if fileExists(file.path):
                existingFiles.incl(file.path)

        (output, error) = execCmdEx(buildCmd)

        if this.verbosity > 0:
            info output

        if error != 0:
            raise newException(
                ValueError,
                fmt "failed executing `{buildCmd}` with error ({error})"
            )

        for file in walkDir(getCurrentDIr() / nimbleInfo.binDir):
            if fileExists(file.path) and not existingFiles.contains(file.path):
                result.incl(file.path)

    #[

    ]#
    method execute(console: Console): int =
        result = super.execute(console)

        let
            binDir = percy.getAppLocalDir("bin")
            buildDir = percy.getAppLocalDir("build")
            url = console.getArg("url")
            version = console.getArg("version")
            newest = parseBool(console.getOpt("newest"))
            keep = parseBool(console.getOpt("keep"))
        var
            commit: Commit
            repository: Repository
            targetDir: string
            output: string
            error: int

        if not dirExists(binDir):
            createDir(binDir)

        if not dirExists(buildDIr):
            createDir(buildDir)

        setCurrentDir(buildDir)

        try:
            repository = Repository.init(url)

            if newest:
                discard repository.update(force = true)
            else:
                discard repository.update(force = false)

            discard repository.prune()

        except Exception as e:
            fail fmt "Could Not Fetch From Repository"
            info fmt "> Error: {e.msg}"
            return 1

        try:
            commit = this.resolveCommit(repository, ver(version))

        except Exception as e:
            fail fmt "Could Not Fetch Requested Version"
            info fmt "> Error: {e.msg}"
            info fmt "> Version: {version}"
            return 2

        targetDir = buildDir / repository.shaHash / commit.id

        if not dirExists(targetDir):
            error = repository.exec(
                @[
                    fmt "git worktree add -d {targetDir} {commit.id}",
                ],
                output
            )

            if error != 0:
                fail fmt "Could Not Create Build Worktree"
                return 3

        setCurrentDir(targetDir)

        error = this.initializeWorkTree()

        if error != 0:
            return 10 + error

        error = this.updateWorkTree()

        if error != 0:
            return 20 + error

        try:
            let
                binFiles = this.buildWorkTree()

            for file in binFiles:
                createSymlink(file, binDir / file.extractFilename())
        except Exception as e:
            fail fmt "Failed Building Worktree"
            info fmt "> Error: {e.msg}"
            return 4

shape FetchCommand: @[
    Command(
        name: "fetch",
        description: "Download, install, and build applications",
        args: @[
            Arg(
                name: "url",
                description: "A valid git URL for the repository to fetch and build"
            ),
            Arg(
                name: "version",
                default: "head",
                description: "The version to fetch and build"
            )
        ],
        opts: @[
            CommandConfigOpt,
            CommandVerbosityOpt,
            Opt(
                flag: 'n',
                name: "newest",
                description: "Force fetching of HEADs even if local cache is not stale"
            ),
            Opt(
                flag: 'k',
                name: "keep",
                description: "Keep existing versions for faster switching"
            )
        ]
    )
]
