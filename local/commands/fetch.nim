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

        discard repository.update(quiet = this.verbosity < 1, force = true)
        result = this.resolveCommit(repository, version)

        raise newException(
            ValueError,
            fmt "cannot find version corresponding to {$verison}"
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

        (output, error) = execCmdEx(buildCmd)

        if this.verbosity > 0:
            info output

        if error != 0:
            raise newException(
                ValueError,
                fmt "failed executing `{buildCmd}` with error ({error})"
            )

        for file in nimbleInfo.bin:
            let
                filePath = absolutePath(nimbleInfo.binDir) / file
            if fileExists(filePath):
                result.incl(filePath)

    #[

    ]#
    method execute(console: Console): int =
        result = super.execute(console)

        const
            buildDir = percy.getAppLocalDir("build")
        let
            url = console.getArg("url")
            version = console.getArg("version")
            binDir = absolutePath(console.getOpt("bin-directory").expandTilde())
            keep = parseBool(console.getOpt("keep"))
        var
            commit: Commit
            repository: Repository
            targetDir: string
            workDir: string
            output: string
            error: int

        if not dirExists(binDir):
            createDir(binDir)

        if not dirExists(buildDIr):
            createDir(buildDir)

        setCurrentDir(buildDir)

        try:
            repository = Repository.init(url)
            discard repository.clone()
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

        workDir = buildDir / repository.shaHash
        targetDir = workDir / commit.id

        if not keep:
            for dir in walkDir(workDir):
                if dir.path != targetDir:
                    removeDir(dir.path)

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

        discard repository.prune()
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
                let
                    linkPath = binDir / file.extractFilename()
                if symlinkExists(linkPath):
                    removeFile(linkPath)
                createSymlink(file, linkPath)

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
                flag: 'k',
                name: "keep",
                description: "Keep existing versions for faster switching"
            ),
            Opt(
                flag: 'b',
                name: "bin-directory",
                default: "~/.local/bin",
                description: "Change where the binary links are stored"
            )
        ]
    )
]
