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
        verbosity*: int
        settings*: Settings

    BaseGraphCommand* = ref object of BaseCommand
        nimbleInfo*: NimbleFileInfo
        nimbleFile*: string
        nimbleMap*: string

let
    CommandConfigOpt* = Opt(
        flag: 'c',
        name: "config",
        default: "percy.json",
        description: "The configuration settings filename"
    )

    CommandVerbosityOpt* = Opt(
        flag: 'v',
        name: "verbosity",
        default: "0",
        values: @["1", "2", "3"],
        description: "The verbosity level of the output"
    )

begin BaseCommand:
    method execute*(console: Console): int {. base .} =
        result = 0

        this.config = console.getOpt("config")
        this.verbosity = parseInt(console.getOpt("verbosity"))
        this.settings = this.app.get(Settings).open(this.config)

begin BaseGraphCommand:
    method execute*(console: Console): int =
        var
            foundNimble = false

        result = super.execute(console)

        for file in walkFiles("*.nimble"):
            this.nimbleFile = file
            this.nimbleInfo = parser.parseFile(readFile(file), this.nimbleMap)
            foundNimble = true
            break

        if not foundNimble:
            raise newException(ValueError, "Could not find .nimble file")

    method getGraph*(quiet: bool = false): DepGraph {. base .} =
        result = DepGraph.init(this.settings, this.verbosity == 0)

    method loadSolution*(solution: Solution, force: bool = false): seq[Checkout] {. base .} =
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
        # and their workDir.  Error if there appears to be changes and/or no appropriate
        # correspondance.  The logic in here will exclude from deleteDirs if the package can
        # be updated and/or parent dirs, if they are schedule for delete.
        #

        for commit in solution:
            let
                currentUrl = commit.repository.url
                workTrees = commit.repository.workTrees
                workDir = vendorDir / this.settings.getName(commit.repository.url)

            #
            # If the workDir is not in the current worktree, it either exists and is something
            # else or it doesn't and we create it.
            #
            if not workTrees.hasKey(workDir):
                if dirExists(workDir):
                    if not force:
                        info fmt "Skip '{workDir}': non-worktree of {currentUrl} (force with -f)"
                    else:
                        # Delete and recreate
                        deleteDirs.incl(workDir)
                        createDirs.incl(workDir)
                else:
                    # Just create
                    createDirs.incl(workDir)
            else:
                let
                    branch = workTrees[workDir].branch
                    head = workTrees[workDir].head

                percy.execIn(
                    ExecHook as (
                        block:
                            error = percy.execCmdCapture(output, @[
                                fmt "git status --porcelain"
                            ])
                    ),
                    workDir
                )

                #
                # If the user has any unsaved changes we want to be more careful.
                #
                if output.len > 0: #optimized
                    if not force:
                        info fmt "Skip '{workDir}': exists, but has changes (force with -f)"
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

                    #
                    # We only bother to update workdirs where the head does not match the commit
                    # id.
                    #
                    if head != commit.id:
                        #
                        # We only update the workdir if a branch is not check out as a checked
                        # out branch likely indicates the person is working on it.  If the local
                        # repository is stale, it will not have updated to the latest ref so we
                        # want to retain the branch head.
                        #
                        if not force and branch.len != 0:
                            info fmt "Skip '{workDir}': using branch `{branch}` (force with -f)"
                        else:
                            updateDirs.incl(workDir)

        #
        # Report changes
        #

        let # optimized
            hasDeleteDirs = deleteDirs.len > 0
            hasUpdateDirs = updateDirs.len > 0
            hasCreateDirs = createDirs.len > 0

        if this.verbosity > 1 and (hasDeleteDirs or hasUpdateDirs or hasCreateDirs):
            print fmt "Solution: Changes Required"
            if hasDeleteDirs:
                print fmt "  Delete:"
                for dir in deleteDirs:
                    print fmt "    {dir}"
            if hasUpdateDirs:
                print fmt "  Update:"
                for dir in updateDirs:
                    print fmt "    {dir}"
            if hasCreateDirs:
                print fmt "  Create:"
                for dir in createDirs:
                    print fmt "    {dir}"

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
                                fmt "git checkout -q --detach {commitHash}"
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

