import
    percy,
    basecli,
    pkg/checksums/sha1

type
    FetchCommand = ref object of BaseCommand

begin FetchCommand:
    #[

    ]#
    method resolveCommit(repository: Repository, version: Version, update: bool = true): Commit {. base .} =
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

        if update:
            discard repository.update(quiet = this.verbosity < 1, force = true)
            return this.resolveCommit(repository, version, false)

        raise newException(
            ValueError,
            fmt "cannot find corresponding version"
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
    method updateWorkTree(newest: bool = false): int {. base .} =
        let
            console = this.app.get(Console, false)
        var
            command = @["update", "-p"]

        if newest:
            command.add("-n")

        if this.verbosity:
            command.add("-v:" & $this.verbosity)

        result = console.run(command)


    #[

    ]#
    method buildWorkTree(newest: bool = false): HashSet[string] {. base .} =
        var
            error: int
            output: string
            targetConfig: JsonNode
            nimbleInfo: NimbleFileInfo
            buildNode: JsonNode
            buildCmd = "nim build"
            buildDo = newest

        if fileExists(fmt "{percy.name}.json"):
            targetConfig = parseFile(fmt "{percy.name}.json")
            buildNode = targetConfig.get("meta.build")

            if buildNode.kind == JString:
                buildCmd = buildNode.getStr()

        for file in walkDir(getCurrentDir()):
            if file.path.endsWith(".nimble"):
                nimbleInfo = parser.parse(readFile(file.path))
                break

        for file in nimbleInfo.bin:
            let
                filePath = absolutePath(getCurrentDir() / nimbleInfo.binDir) / file

            result.incl(filePath)

            if not fileExists(filePath):
                buildDo = true

        (output, error) = execCmdEx(buildCmd)

        if this.verbosity > 0:
            info output

        if error != 0:
            raise newException(
                ValueError,
                fmt "failed executing `{buildCmd}` with error ({error})"
            )

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
            newest = parseBool(console.getOpt("newest"))
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
            fail fmt "Could not fetch from repository"
            info fmt "> Error: {e.msg}"
            return 1

        try:
            commit = this.resolveCommit(repository, ver(version))
        except Exception as e:
            fail fmt "Could not fetch request version"
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
        else:
            # Check if actual commit has changed and re-checkout if needed
            discard

        discard repository.prune()
        setCurrentDir(targetDir)

        error = this.initializeWorkTree()

        if error != 0:
            return 10 + error

        error = this.updateWorkTree(newest)

        if error != 0:
            return 20 + error

        try:
            let
                binFiles = this.buildWorkTree(newest)

            for file in binFiles:
                let
                    linkPath = binDir / file.extractFilename()

                if symlinkExists(linkPath):
                    let
                        current = expandSymLink(linkPath)
                    if current == file and secureHashFile(current) == secureHashFile(file):
                        warn fmt "Existing Binary Link Is Latest"
                        info fmt "> Path: {linkPath}"
                        continue
                    else:
                        warn fmt "Replacing Existing Binary Link"
                        info fmt "> Path: {linkPath}"
                        info fmt "> Current: {current}"
                        info fmt "> Updated: {file}"
                        removeFile(linkPath)
                else:
                    event fmt "Creating Binary Link"
                    print fmt "> Path: {linkPath}"
                    print fmt "> Linked: {file}"

                createSymlink(file, linkPath)

        except Exception as e:
            fail fmt "Failed Building Worktree"
            info fmt "> Error: {e.msg}"
            return 4

shape FetchCommand: @[
    Command(
        name: "fetch",
        description: "Download and build applications from a remote repository URL",
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
                flag: 'b',
                name: "bin-directory",
                default: "~/.local/bin",
                description: "Change where the binary links are stored"
            ),
            Opt(
                flag: 'n',
                name: "newest",
                description: "Ensure the version being fetched is fully up-to-date"
            ),
            Opt(
                flag: 'k',
                name: "keep",
                description: "Keep other versions for faster switching"
            ),
            Opt(
                flag: 'd',
                name: "delete",
                description: "Delete all builds or a specific version of a build"
            )
        ]
    )
]
