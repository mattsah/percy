import
    percy,
    semver,
    std/re,
    lib/settings,
    lib/repository,
    mininim/cli

export
    semver

type
    MissingRepositoryException* = ref object of CatchableError
        repository*: Repository

    ConstraintHook* = proc(v: Version): bool

    Constraint* = ref object of Class
        check: ConstraintHook

    AllConstraint* = ref object of Constraint

    AnyConstraint* = ref object of Constraint

    Requirement* = object
        package*: string
        versions*: string
        repository*: Repository
        constraint: Constraint

    DepGraph* = ref object of Class
        quiet: bool
        newest: bool
        stack: seq[Requirement]
        commits: OrderedTable[Repository, OrderedSet[Commit]]
        tracking: OrderedTable[Repository, OrderedSet[Commit]]
        requirements: Table[(Repository, Version), seq[Requirement]]
        settings: Settings

    DecisionLevel = int

    Assignment = object
        level: DecisionLevel
        commit: Commit

    Solver* = ref object of Class

    SolverResult* = object
        solution*: Option[Solution]
        backtrackCount*: int
        timeTaken*: float

    Solution* = seq[Commit]

begin Constraint:
    discard

begin AllConstraint:
    proc init*(items: seq[Constraint]): void =
        this.check = ConstraintHook as (
            block:
                result = true
                for i in items:
                    if i.check(v) == false:
                        return false
        )

begin AnyConstraint:
    proc init*(items: seq[Constraint]): void =
        this.check = ConstraintHook as (
            block:
                result = false
                for i in items:
                    if i.check(v) == true:
                        return true
        )

begin Requirement:
    method repository*(): Repository {. base .} =
        result = this.repository

begin DepGraph:
    method stack*(): seq[Requirement] {. base .} =
        result = this.stack

    #[
    ##
    ]#
    method addRequirement*(commit: Commit, requirement: Requirement, depth: int): void {. base .}

    #[
    ##
    ]#
    method init*(settings: Settings, quiet: bool = true): void {. base .} =
        this.quiet    = quiet
        this.settings = settings

    #[
    ##
    ]#
    method parseConstraint*(constraint: string, repository: Repository): Constraint {. base .} =
        let
            cleaned = constraint.replace(" ", "")
            fix = proc(numericV: string): string =
                result = numericV
                for i in numericV.split('.').len..2:
                    result = result & ".0"

        return Constraint(
            check: ConstraintHook as (
                block:
                    try:
                        if cleaned == "any":
                            return true
                        elif cleaned.startsWith("=="):
                            return v == v(fix(cleaned[2..^1]))
                        elif cleaned.startsWith(">="):
                            return v >= v(fix(cleaned[2..^1]))
                        elif cleaned.startsWith("<="):
                            return v <= v(fix(cleaned[2..^1]))
                        elif cleaned.startsWith("<"):
                            return v < v(fix(cleaned[1..^1]))
                        elif cleaned.startsWith(">"):
                            return v > v(fix(cleaned[1..^1]))
                        else:
                            if cleaned.startsWith("#"):
                                let
                                    head = cleaned[1..^1].replace(re"[!@#$%^&*+_.,]", "-")
                                return v == v("0.0.0-branch." & head)
                            else:
                                let
                                    now = v(fix(cleaned[1..^1]))
                                if cleaned.startsWith("~"):
                                    let
                                        next = Version(
                                            major: now.major,
                                            minor: now.minor + 1,
                                            patch: 0
                                        )
                                    return v >= now and v < next
                                elif cleaned.startsWith("^"):
                                    let
                                        next = Version(
                                            major: now.major + 1,
                                            minor: 0,
                                            patch: 0
                                        )
                                    return v >= now and v < next
                                else:
                                    discard
                    except:
                        discard

                    raise newException(
                        ValueError,
                        fmt "Invalid version constraint '{constraint}': {getCurrentExceptionMsg()}"
                    )
            )
        )


    #[
    ##
    ]#
    method parseRequirement*(requirement: string): Requirement {. base .} =
        # Something like:
        #   semver >=1.2.3|#head
        #   mininim-core >=2.1,<=2.5|>=2.8
        #   /path/to/file ^1.5
        #   gh://mattsah/percy ~=1.5
        #
        # The rules around splitting cleaneds are probably OK, but longer
        # term we might need to parse out the package differently if spaces
        # are not common dividing repository + cleaneds.  Problem is a
        # URL can contain a ~ and so can a cleaned.
        let
            parts = requirement.strip().split(' ', 1)
            package = parts[0]
        var
            versions: string
            repository = this.settings.getRepository(package)
            constraint = Constraint(check: ConstraintHook as (
                block:
                    result = true
            ))

        if parts.len > 1:
            versions = parts[1]
        else:
            versions = "any"

        if parts.len > 1:
            var
                anyParts = versions.split('|')
                anyItems = newSeq[Constraint](anyParts.len)

            for i, anyConstraint in anyParts:
                var
                    allParts = anyConstraint.split(',')
                    allItems = newSeq[Constraint](allParts.len)
                for j, allConstraint in allParts:
                    allItems[j] = this.parseConstraint(allConstraint, repository)
                anyItems[i] = AllConstraint.init(allItems)

            constraint = AnyConstraint.init(anyItems)

        result = Requirement(
            package: package,
            versions: versions,
            repository: repository,
            constraint: constraint
        )

    #[
    ##
    ]#
    method reportStack*(): void {. base .} =
        print fmt "Graph: Package Stack Report"
        print fmt "> Size: {$this.stack.len}"
        print fmt "> Stack:"
        for i, requirement in this.stack:
            print fmt """    {alignLeft("", (i+1), ' ')}""", 0
            if i != 0:
                print " ↳ ", 0
            print fmt """{requirement.package} {requirement.versions}"""

    #[
    ##
    ]#
    method report*(): void {. base .} =
        print "Graph: Completed With Usable Versions"

        for repository, commits in this.tracking:
            print fmt "  {fg.cyan}{repository.url}{fg.stop}:"
            for commit in commits:
                print fmt "    {fg.green}{commit.version}{fg.stop}"

    #[
    ##
    ]#
    method resolve*(commit: Commit, depth: int): void {. base .} =
        let
            key = (commit.repository, commit.version)

        if not this.tracking.hasKey(commit.repository):
            this.tracking[commit.repository] = initOrderedSet[Commit]()

        if not this.requirements.hasKey(key):
            if not this.quiet:
                print fmt "Graph: Resolving Nimble File"
                print fmt "> Source: {commit.repository.url} @ {commit.version}"

            this.tracking[commit.repository].incl(commit)

            this.requirements[key] = newSeq[Requirement]()

            for file in commit.repository.listDir("/", commit.id):
                if file.endsWith(".nimble"):
                    try:
                        let
                            contents = commit.repository.readFile(file, commit.id)
                        when debugging(3):
                            print fmt "Graph: Parsing nimble contents"
                            print fmt "> Repository: {commit.repository.url}"
                            print fmt "> Commit: {commit.version} ({commit.id})"
                            print indent(contents, 4)
                        commit.info = parser.parseFile(contents)
                    except:
                        print fmt "Graph: Failed parsing nimble file {file}"
                        print fmt "> Repository: {commit.repository.url}"
                        print fmt "> Commit: {commit.version} ({commit.id})"
                        print fmt "> Error: {getCurrentExceptionMsg()}"
                        quit(1)

                    for requirements in commit.info.requires:
                        for requirement in requirements:
                            this.addRequirement(commit, this.parseRequirement(requirement), depth + 1)
                    break

    #[
    ##
    ]#
    method addRepository*(repository: Repository): void {. base .} =
        if not this.commits.hasKey(repository):
            if not repository.exists:
                raise MissingRepositoryException(
                    msg: fmt "required repository '{repository.original}' does not seem to exist",
                    repository: repository
                )

            if not this.quiet:
                print fmt "Graph: Adding Repository (Scanning Available Tags)"
                print fmt "> Repository: {repository.url}"

            this.commits[repository] = repository.commits(this.newest)

    #[
    ##
    ]#
    method addRequirement*(commit: Commit, requirement: Requirement, depth: int): void {. base .} =
        let
            key = (commit.repository, commit.version)

        this.stack.add(requirement)

        if not this.quiet:
            print fmt "Graph: Adding Requirement"
            print fmt "> Dependent: {commit.repository.url} @ {commit.version}"
            print fmt "> Dependends On: {requirement.repository.url} @ {requirement.versions}"

        this.addRepository(requirement.repository)

        var
            toResolve = HashSet[Commit]()

        if depth == 0:
            var
                toRemove = HashSet[Commit]()

            for commit in this.commits[requirement.repository]:
                if not requirement.constraint.check(commit.version):
                    toRemove.incl(commit)
                else:
                    toResolve.incl(commit)

            for commit in toRemove:
                if not this.quiet:
                    print fmt "Graph: Excluding Commit (Not Usable At Top-Level)"
                    print fmt "> Repository: {commit.repository.url}"
                    print fmt "> Version: {commit.version}"
                this.commits[commit.repository].excl(commit)
        else:
            for commit in this.commits[requirement.repository]:
                if requirement.constraint.check(commit.version):
                    toResolve.incl(commit)

        this.requirements[key].add(requirement)

        for commit in toResolve:
            if this.commits[commit.repository].contains(commit):
                this.resolve(commit, depth)
            else:
                if not this.quiet:
                    print fmt "Graph: Skipping Resolution (Already Removed)"
                    print fmt "> Repository: {commit.repository.url}"
                    print fmt "> Version: {commit.version}"

        discard this.stack.pop()


    #[
    ##
    ]#
    method build*(nimbleInfo: NimbleFileInfo, newest: bool = false): void {. base .} =
        let
            repository = this.settings.getRepository(getCurrentDir())
            commit = Commit(repository: repository)

        this.newest = newest
        this.requirements[(commit.repository, commit.version)] = newSeq[Requirement]()

        for requirements in nimbleInfo.requires:
            for requirement in requirements:
                this.addRequirement(commit, this.parseRequirement(requirement), 0)

        #
        # Determine sorting possibly by arguments to build, for now we'll just sort by least to
        # most available commits/versions with respect to repositories.  And from highest version
        # to lowest on the commits themselves.
        #

        this.tracking = this.tracking.pairs.toSeq()
            .sortedByIt(it[1].len)
            .toOrderedTable()

        for repository, commits in this.tracking:
            this.tracking[repository] = commits.toSeq()
                .sorted(
                    proc (x, y: Commit): int {. closure .} =
                        let
                            xIsBranch = x.version.build.startsWith("branch.")
                            yIsbranch = y.version.build.startsWith("branch.")
                        if x.version.build == "HEAD":
                            result = 1
                        elif y.version.build == "HEAD":
                            result = -1
                        elif xIsBranch and yIsBranch:
                            result = cmp(x.version.build, y.version.build)
                        elif xIsBranch:
                            result = 1
                        elif yIsBranch:
                            result = -1
                        else:
                            result = cmp(x.version, y.version)
                    ,
                    Descending
                )
                .toOrderedSet()

#[
##
]#
begin Solver:

    #[
    ##
    ]#
    method init*(): void {. base .} =
        discard

    #[
    ##
    ]#
    method solve*(graph: DepGraph): SolverResult {. base .} =
        var
            level = 0
            assignments = initTable[Repository, Assignment]()
            knownConflicts = initHashSet[(Commit, Commit)]()
            backtrackCount = 0

        while true:
            #
            # If all repositories have been assigned a version, we're done.
            #

            if assignments.len == graph.tracking.len:
                var
                    solution = newSeq[Commit]()

                for repository, assignment in assignments:
                    solution.add(assignment.commit)

                return SolverResult(
                    solution: some(solution),
                    backtrackCount: backtrackCount
                )

            #
            # Make a decision
            #
            for repository in graph.tracking.keys:
                if assignments.hasKey(repository):
                    #
                    # We've already assigned this repository, just continue.  The assigmnet may
                    # be removed later if not version of the next level down is found to be
                    # consistent iwth it.
                    #
                    continue

                for commit in graph.tracking[repository]:
                    var
                        consistentWithOtherAssignments = true
                    let
                        key = (commit.repository, commit.version)

                    if graph.requirements.hasKey(key):
                        #
                        # We loop through all of the requirements for this commit and check to see
                        # if any of our existing assignments violat them.
                        #
                        for requirement in graph.requirements[key]:
                            if assignments.hasKey(requirement.repository):
                                let
                                    assignment = assignments[requirement.repository]

                                if not requirement.constraint.check(assignment.commit.version):
                                    knownConflicts.incl((assignment.commit, commit))
                                    knownConflicts.incl((commit, assignment.commit))
                                    consistentWithOtherAssignments = false
                                    break

                    if consistentWithOtherAssignments:
                        #
                        # We were found to be consistent with all other assignments, so let's add
                        # ourself to the assignment.
                        #
                        assignments[repository] = Assignment(
                            level: level,
                            commit: commit
                        )
                        break

                if repository notin assignments:
                    #
                    # We've run through all the commmits on this repo and found none that are
                    # consistent, thus far, so we need to go back up one level.
                    #
                    inc backtrackCount

                    if level == 0:
                        return SolverResult(
                            solution: none(Solution),
                            backtrackCount: backtrackCount
                        )

                    #
                    # Backtrack to previous decision level by removing any at higher or current
                    # levels.
                    #
                    var
                        toRemove = initHashSet[Repository]()
                    for repository, assignment in assignments:
                        if assignment.level >= level:
                            toRemove.incl(repository)

                    for repository in toRemove:
                        assignments.del(repository)

                    dec level

                #
                # If we got here, we've either:
                # 1. Assigned a commit for the given repository or...
                # 2.
                break