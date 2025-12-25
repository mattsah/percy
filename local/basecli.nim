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
        this.settings = Settings.open(this.config)
        this.verbosity = parseInt(console.getOpt("verbosity"))

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
            retainDirs: HashSet[string]
            deleteDirs: OrderedSet[string]
            updateDirs: OrderedSet[string]
            createDirs: OrderedSet[string]
            workTrees: Table[string, WorkTree]
        let
            vendorDir = getCurrentDir() / percy.target

        if this.verbosity > 0:
            print "Loading Solution"

        #
        # Loop through all of our workDirs based commits in the solution and the corresponding
        # work tree.  Mark directories depending on their state, we can either:
        # - retain
        # - create
        # - update
        #
        # Deletes are handled after this as we want to cleanup directories no longer being used.
        #
        for commit in solution:
            let
                targetDir = vendorDir / this.settings.getWorkDir(commit.repository.url)
                workTrees = commit.repository.workTrees
                currentUrl = commit.repository.url

            if not workTrees.hasKey(targetDir):
                if dirExists(targetDir) and not force:
                    info fmt "> Skip: '{targetDir}': non-worktree of {currentUrl} (force with -f)"
                    retainDirs.incl(targetDir)
                else:
                    createDirs.incl(targetDir)
            else:
                let
                    branch = workTrees[targetDir].branch
                    head = workTrees[targetDir].head

                if head == commit.id: # We can just retain the current state if it matches
                    retainDirs.incl(targetDir)
                else: # If it doesn't match we want to check if there's a branch checked out
                    if branch.len != 0 and not force: # Someone may be working on something
                        info fmt "> Skip: '{targetDir}': using branch `{branch}` (force with -f)"
                        retainDirs.incl(targetDir)
                    else:
                        updateDirs.incl(targetDir)

        proc scanDeletes(dir: string): void =
            var
                delCount = 0
                subCount = 0
            for item in walkDir(dir):
                inc subCount
                if not dirExists(item.path): # We're only looking for directories
                    continue
                if symLinkExists(item.path): # Enable people to link to work on things
                    continue
                if retainDirs.contains(item.path):
                    continue
                if percy.hasFile(item.path):
                    if dirExists(item.path / ".git"): # Check if this is a git directory
                        percy.execIn(
                            ExecHook as (
                                block:
                                    error = percy.execCmdCapture(output, @[
                                        fmt "git status --porcelain"
                                    ])
                            ),
                            item.path
                        )

                        if not error and output.len > 0 and not force:
                            info fmt "> Skip: '{item.path}': has unsaved changes (force with -f)"
                            if updateDirs.contains(item.path):
                                updateDirs.excl(item.path)

                    if not updateDirs.contains(item.path):
                        deleteDirs.incl(item.path)
                        inc delCount
                else:
                    scanDeletes(item.path)
            if subCount == delCount:
                deleteDirs.incl(dir)

        scanDeletes(vendorDir)

        #
        # Report changes
        #

        deleteDirs = deleteDirs.toSeq().sortedByIt(it.len).reversed().toOrderedSet()
        updateDirs = updateDirs.toSeq().sortedByIt(it.len).reversed().toOrderedSet()
        createDirs = createDirs.toSeq().sortedByIt(it.len).reversed().toOrderedSet()

        let # optimized
            hasDeleteDirs = deleteDirs.len > 0
            hasUpdateDirs = updateDirs.len > 0
            hasCreateDirs = createDirs.len > 0

        if this.verbosity > 0:
            if hasDeleteDirs or hasUpdateDirs or hasCreateDirs:
                print fmt "> Solution: Changes Required"
                if hasDeleteDirs:
                    print fmt "> Delete:"
                    for dir in deleteDirs:
                        print fmt ">    {dir}"
                if hasUpdateDirs:
                    print fmt ">  Update:"
                    for dir in updateDirs:
                        print fmt ">    {dir}"
                if hasCreateDirs:
                    print fmt ">  Create:"
                    for dir in createDirs:
                        print fmt ">    {dir}"
            else:
                print fmt "> Solution: There Are No Applicable Changes"

        #
        # Perform loading
        #
        for dir in deleteDirs:
            removeDir(dir)

        for commit in solution:
            let
                workDir = this.settings.getWorkDir(commit.repository.url)
                targetDir = vendorDir / workDir
                commitHash = commit.id

            if updateDirs.contains(targetDir):
                percy.execIn(
                    ExecHook as (
                        block:
                            error = percy.execCmd(@[
                                fmt "git checkout -q --detach {commitHash}"
                            ])
                    ),
                    workDir
                )
            elif createDirs.contains(targetDir):
                error = commit.repository.exec(@[
                    fmt "git worktree add -d {targetDir} {commitHash}"
                ], output)

            if commit.info.srcDir.len > 0: # optimized
                pathList.add(fmt "{percy.target / workDir / commit.info.srcDir}")
            else:
                pathList.add(fmt "{percy.target / workDir}")

        writeFile(fmt "vendor/{percy.name}.paths", pathList.join("\n"))
