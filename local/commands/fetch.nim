import
    percy,
    basecli,
    pkg/checksums/sha1

type
    FetchCommand = ref object of BaseCommand

#[

]#
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

        if buildDo:
            error = percy.execCmdCaptureAll(output, @[
                buildCmd
            ])

            if this.verbosity > 0:
                info fmt "Building:"
                for line in output.split('\n'):
                    info indent(line, 3)

            if error != 0:
                raise newException(
                    ValueError,
                    fmt "failed executing `{buildCmd}` with error ({error})"
                )

    method linkBinFiles(binFiles: HashSet[string], binDir: string): void =
        for file in binFiles:
            let
                linkPath = binDir / file.extractFilename()

            if symlinkExists(linkPath):
                let
                    current = expandSymLink(linkPath)
                if current == file and secureHashFile(current) == secureHashFile(file):
                    warn fmt "Existing Binary Link Is Latest"
                    info fmt "> Link: {linkPath}"
                    info fmt "> Current Target: {current}"
                    continue
                else:
                    warn fmt "Replacing Existing Binary Link"
                    info fmt "> Path: {linkPath}"
                    info fmt "> Current Target: {current}"
                    info fmt "> New Target: {file}"
                    removeFile(linkPath)
            else:
                event fmt "Creating Binary Link"
                print fmt "> Link: {linkPath}"
                print fmt "> Binary: {file}"

            createSymlink(file, linkPath)


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
            delete = parseBool(console.getOpt("delete"))
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

        repository = Repository.init(url)
        workDir = buildDir / repository.shaHash

        try:
            discard repository.clone()
        except Exception as e:
            fail fmt "Could not fetch from repository"
            info fmt "> Error: {e.msg}"
            return 1

        if newest:
            discard repository.update(force = true)

        try:
            commit = this.resolveCommit(repository, ver(version))
        except Exception as e:
            fail fmt "Could Resolve Version"
            info fmt "> Error: {e.msg}"
            info fmt "> Version: {version}"
            return 2

        targetDir = workDir / commit.id

        discard repository.prune()

        if delete:
            if not dirExists(targetDir):
                fail fmt "Unable To Remove Requested Binaries"
                info fmt "> Error: no versions of the requested repository exist"
                return 3
            else:
                if version == "any":
                    print fmt "Removing All Versions of Request Repository"
                    print fmt "> Path: {workDir}"
                    removeDir(workDir)
                else:
                    var
                        alts: seq[(string, Time)]

                    print fmt "Removing Requested Version of Repository"
                    print fmt "> Version: {version}"
                    print fmt "> Path: {targetDir}"
                    removeDir(targetDir)

                    print fmt "Searching Usable Versions"

                    for dir in walkDir(workDir):
                        if dirExists(dir.path):
                            alts.add((dir.path, getCreationTime(dir.path)))

                    for (targetDir, created) in alts.sortedByIt(it[1]).reversed():
                        setCurrentDir(targetDir)
                        try:
                            this.linkBinFiles(this.buildWorkTree(), binDir)
                        except:
                            discard

            warn fmt "Removing Stale Links"
            for file in walkDir(binDir):
                if not symLinkExists(file.path):
                    continue
                let
                    source = expandSymLink(file.path)
                if source.startsWith(buildDir) and not fileExists(file.path):
                    if this.verbosity > 0:
                        info fmt "> Link: {file.path}"
                    removeFile(file.path)
        else:
            if not dirExists(targetDir):
                error = repository.exec(
                    @[
                        fmt "git worktree add -d {targetDir} {commit.id}",
                    ],
                    output
                )

                if error != 0:
                    fail fmt "Could Not Create Build Worktree"
                    info fmt "> Error: {output}"
                    return 3

                setCurrentDir(targetDir)
            else:
                setCurrentDir(targetDir)

                error = percy.execCmdCaptureAll(output, @[
                    fmt "git checkout -d {commit.id}",
                ])

                if error != 0:
                    fail fmt "Could Not Update Build Worktree"
                    info fmt "> Error: {output}"
                    return 3

            error = this.initializeWorkTree()

            if error != 0:
                return 10 + error

            error = this.updateWorkTree(newest)

            if error != 0:
                return 20 + error

            try:
                this.linkBinFiles(this.buildWorkTree(newest), binDir)
            except Exception as e:
                fail fmt "Failed Building Worktree"
                info fmt "> Error: {e.msg}"
                return 4

            #
            # Remove other versions
            #
            if not keep:
                for dir in walkDir(workDir):
                    if dir.path != targetDir:
                        removeDir(dir.path)

        discard repository.prune()


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
                default: "any",
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
