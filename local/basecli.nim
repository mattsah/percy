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
        solver*: Solver

let
    CommandConfigOpt* = Opt(
        flag: "c",
        name: "config",
        default: "percy.json",
        description: "The configuration settings filename"
    )

    CommandVerboseOpt* = Opt(
        flag: "v",
        name: "verbose",
        description: "Whether or not to be verbose in output"
    )



begin BaseCommand:
    method execute*(console: Console): int {. base .} =
        result = 0

        this.config = console.getOpt("config", "c")
        this.verbose = console.getOpt("verbose", "v")
        this.settings = this.app.get(Settings).open(this.config)

begin BaseGraphCommand:
    method execute*(console: Console): int =
        result = super.execute(console)

        this.nimbleInfo = percy.getNimbleInfo()
        this.solver = Solver.init()

    method getGraph*(quiet: bool = false): DepGraph {. base .} =
        let
            quiet = quiet or not this.verbose

        result = DepGraph.init(this.settings, quiet)

        result.build(this.nimbleInfo)

        if not quiet:
            result.report()

    method loadSolution*(solution: Solution, quiet: bool = false, force: bool = false): seq[Checkout] {. base .} =
        var
            error: int
            existingDirs: seq[string]
            deleteDirs: HashSet[string]
            updateDirs: HashSet[string]
            createDirs: HashSet[string]
            workTrees: Table[string, WorkTree]
            workTreeStatus: string
        let
            vendorDir = getCurrentDir() / "vendor"
            quiet = quiet or not this.verbose

        for item in walkDir(vendorDir):
            if dirExists(item.path) and not symlinkExists(item.path):
                existingDirs.add(item.path)
                existingDirs.add(onlyDirs(item.path))

        deleteDirs = existingDirs.sortedByIt(it.len).reversed().toHashSet()

        if not quiet:
            echo fmt "Solution: Found Existing Directoories"
            for dir in existingDirs:
                echo fmt "  {dir}"

        for commit in solution:
            let
                workTrees = commit.repository.workTrees
                workDir = vendorDir / this.settings.getName(commit.repository.url)
            if workTrees.hasKey(workDir):
                percy.execIn(
                    ExecHook as (
                        block:
                            error = percy.execCmdEx(workTreeStatus, @[
                                fmt "git status --porcelain"
                            ])
                    ),
                    workDir
                )

                if workTreeStatus:
                    if not force:
                        raise newException(
                            ValueError,
                            fmt "'{workDir}' exists, but is has changes"
                        )
                    else:
                        deleteDirs.incl(workDir)
                else:
                    if workTrees[workDir].head != commit.id:
                        deleteDirs.excl(workDir)
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

        if not quiet:
            echo fmt "Solution: Changes Required"
            if deleteDirs:
                echo fmt "  Delete:"
                for dir in deleteDirs:
                    echo fmt "    {dir}"
            if updateDirs:
                echo fmt "  Update:"
                for dir in updateDirs:
                    echo fmt "    {dir}"
            if createDirs:
                echo fmt "  Create:"
                for dir in createDirs:
                    echo fmt "    {dir}"
