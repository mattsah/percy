import
    percy,
    mininim/cli,
    lib/repository,
    lib/settings,
    lib/depgraph

export
    cli,
    parser,
    settings,
    depgraph

type
    BaseCommand* = ref object of Class
        config*: string
        verbose*: string
        settings*: Settings

    BaseGraphCommand* = ref object of BaseCommand
        nimbleInfo*: NimbleFileInfo
        nimbleFile*: string
        nimbleMap*: string
        solver*: Solver

let
    CommandConfigOpt* = Opt(
        flag: 'c',
        name: "config",
        default: "percy.json",
        description: "The configuration settings filename"
    )

    CommandVerboseOpt* = Opt(
        flag: 'v',
        name: "verbose",
        description: "Whether or not to be verbose in output"
    )

begin BaseCommand:
    method execute*(console: Console): int {. base .} =
        result = 0

        this.config = console.getOpt("config")
        this.verbose = console.getOpt("verbose")
        this.settings = this.app.get(Settings).open(this.config)

begin BaseGraphCommand:
    method execute*(console: Console): int =
        var
            foundNimble = false

        result = super.execute(console)
        this.solver = Solver.init()

        for file in walkFiles("*.nimble"):
            this.nimbleFile = file
            this.nimbleInfo = parser.parseFile(readFile(file), this.nimbleMap)
            foundNimble = true
            break

        if not foundNimble:
            raise newException(ValueError, "Could not find .nimble file")

    method getGraph*(quiet: bool = false): DepGraph {. base .} =
        result = DepGraph.init(this.settings, quiet or not this.verbose)

    method buildGraph*(quiet: bool = false): DepGraph {. base .} =
        result = this.getGraph(quiet)

        result.build(this.nimbleInfo)

        if not quiet:
            result.report()

    method loadSolution*(solution: Solution, quiet: bool = false, force: bool = false): seq[Checkout] {. base .} =
        var
            error: int
            output: string
            pathList: seq[string]
            deleteDirs: OrderedSet[string]
            updateDirs: OrderedSet[string]
            createDirs: OrderedSet[string]
            workTrees: Table[string, WorkTree]
        let
            vendorDir = getCurrentDir() / percy.target
            quiet = quiet or not this.verbose

        #
        # Find all folders which we should, provisionally, delete -- based on the fact that they:
        # 1. Are actually a directory
        # 2. Are not a symlink (we don't want to eff with those)
        # 3. Contain files (not just other directories)
        #

        proc scanDeletes(dir: string): HashSet[string] =
            var
                delCount = 0
                subCount = 0
            for item in walkDir(dir):
                inc subCount
                if not dirExists(item.path):
                    continue
                if symLinkExists(item.path):
                    continue
                if percy.hasFile(item.path):
                    result.incl(item.path)
                    inc delCount
                else:
                    result.incl(scanDeletes(item.path))
            if subCount == delCount:
                result.incl(dir)

        deleteDirs = scanDeletes(vendorDir).toSeq().sortedByIt(it.len).reversed().toOrderedSet()

        #
        # Loop through all the commits in our solution and build out their existing workTrees
        # and their workDir.  Error if there appears to be cahnges and/or no appropriate
        # correspondance.  The logic in here will exclude from deleteDirs if the package can
        # be updated and/or parent dirs, if they are schedule for delete.
        #

        for commit in solution:
            let
                workTrees = commit.repository.workTrees
                workDir = vendorDir / this.settings.getName(commit.repository.url)
            if workTrees.hasKey(workDir):
                percy.execIn(
                    ExecHook as (
                        block:
                            error = percy.execCmdCapture(output, @[
                                fmt "git status --porcelain"
                            ])
                    ),
                    workDir
                )

                if output.len > 0: #optimized
                    if not force:
                        raise newException(
                            ValueError,
                            fmt "'{workDir}' exists, but is has changes"
                        )
                    else:
                        deleteDirs.incl(workDir)
                else:
                    var
                        safeDirs = initHashSet[string]()
                    deleteDirs.excl(workDir)

                    for dir in deleteDirs:
                        if workDir.startsWith(dir & "/"):
                            safeDirs.incl(dir)
                    for dir in safeDirs:
                        deleteDirs.excl(dir)

                    if workTrees[workDir].head != commit.id:
                        updateDirs.incl(workDir)
            else:
                if dirExists(workDir):
                    if not force:
                        raise newException(
                            ValueError,
                            fmt "'{workDir}' exists, but is not a workTree of {commit.repository.url}"
                        )
                    else:
                        deleteDirs.incl(workDir)
                else:
                    createDirs.incl(workDir)

        #
        # Report changes
        #

        let # optimized
            hasDeleteDirs = deleteDirs.len > 0
            hasUpdateDirs = updateDirs.len > 0
            hasCreateDirs = createDirs.len > 0

        if not quiet and (hasDeleteDirs or hasUpdateDirs or hasCreateDirs):
            echo fmt "Solution: Changes Required"
            if hasDeleteDirs:
                echo fmt "  Delete:"
                for dir in deleteDirs:
                    echo fmt "    {dir}"
            if hasUpdateDirs:
                echo fmt "  Update:"
                for dir in updateDirs:
                    echo fmt "    {dir}"
            if hasCreateDirs:
                echo fmt "  Create:"
                for dir in createDirs:
                    echo fmt "    {dir}"

        #
        # Perform loading
        #

        pathList.add("--noNimblePath")

        for dir in deleteDirs:
            removeDir(dir)
        for commit in solution:
            let
                relDir = this.settings.getName(commit.repository.url)
                workDir = vendorDir / relDir
                commitHash = commit.id

            if updateDirs.contains(workDir):
                percy.execIn(
                    ExecHook as (
                        block:
                            error = percy.execCmd(@[
                                fmt "git checkout {commitHash}"
                            ])
                    ),
                    workDir
                )
            elif createDirs.contains(workDir):
                error = commit.repository.exec(@[
                    fmt "git worktree add -d {workDir} {commitHash}"
                ], output)

            if commit.info.srcDir.len > 0: # optimized
                pathList.add(fmt """--path:"{percy.target / relDir / commit.info.srcDir}"""")
            else:
                pathList.add(fmt """--path:"{percy.target / relDir}"""")

        writeFile(fmt "vendor/{percy.name}.paths", pathList.join("\n"))

