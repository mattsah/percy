import
    percy,
    semver,
    std/re,
    lib/settings,
    lib/repository

export
    semver

type
    ConstraintHook* = proc(v: Version): bool

    Constraint* = ref object of Class
        check: ConstraintHook

    AllConstraint* = ref object of Constraint

    AnyConstraint* = ref object of Constraint

    Requirement* = object
        original: string
        repository: Repository
        constraint: Constraint

    DepGraph* = ref object of Class
        quiet: bool
        commits: OrderedTable[Repository, HashSet[Commit]]
        tracking: OrderedTable[Repository, seq[Requirement]]
        requirements: Table[(Repository, Version), seq[Requirement]]
        settings: Settings

    DecisionLevel = int

    Assignment = object
        level: DecisionLevel
        commit: Commit

    Solver* = ref object of Class
        graph: DepGraph
        level: DecisionLevel
        assignments: Table[Repository, Assignment]
        learnedConstraints: seq[seq[Requirement]]
        assignmentOrder: seq[Repository]

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

begin DepGraph:

    #[
    ##
    ]#
    method addRequirement*(commit: Commit, requirement: Requirement): void {. base .}

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
                        if cleaned.startsWith("=="):
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
        var
            repository = this.settings.getRepository(parts[0].strip())
            constraint = Constraint(check: ConstraintHook as (
                block:
                    return true
            ))

        if parts.len > 1:
            var
                anyParts = parts[1].split('|')
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
            original: requirement,
            repository: repository,
            constraint: constraint
        )

    #[
    ##
    ]#
    method report*(): void {. base .} =
        echo "Graph: Graph Completed With Usable Versions"

        for repository, commits in this.commits:
            echo fmt "  {repository.url}:"
            for commit in commits:
                echo fmt "    {commit.version}"

    #[
    ##
    ]#
    method resolve*(commit: Commit): void {. base .} =
        let
            key = (commit.repository, commit.version)

        if not this.requirements.hasKey(key):
            if not this.quiet:
                echo fmt "Graph: Resolving Nimble File"
                echo fmt "  Source: {commit.repository.url} @ {commit.version}"

            this.requirements[key] = newSeq[Requirement]()

            for file in commit.repository.listDir("/", commit.id):
                if file.endsWith(".nimble"):
                    when debugging(2):
                        echo repository.read(file, commit.id)
                    commit.info = parser.parseFile(commit.repository.readFile(file, commit.id))
                    for requirement in commit.info.requires:
                        this.addRequirement(commit, this.parseRequirement(requirement))
                    break

    #[
    ##
    ]#
    method addRepository*(repository: Repository): void {. base .} =
        if not this.commits.hasKey(repository):
            if not this.quiet:
                echo fmt "Graph: Adding Repository (Scanning Available Tags)"
                echo fmt "  Repository: {repository.url}"

            this.commits[repository] = repository.commits

    #[
    ##
    ]#
    method addRequirement*(commit: Commit, requirement: Requirement): void {. base .} =
        let
            key = (commit.repository, commit.version)
        var
            toRemove = HashSet[Commit]()
            toResolve = HashSet[Commit]()

        if not this.quiet:
            echo fmt "Graph: Adding Requirement"
            echo fmt "  Dependent: {commit.repository.url} @ {commit.version}"
            echo fmt "  Dependends On: {requirement.repository.url} @ {requirement.original}"

        this.addRepository(requirement.repository)

        if not this.tracking.hasKey(requirement.repository):
            this.tracking[requirement.repository] = newSeq[Requirement]()

            for commit in this.commits[requirement.repository]:
                if not requirement.constraint.check(commit.version):
                    toRemove.incl(commit)
                else:
                    toResolve.incl(commit)
        else:
            for commit in this.commits[requirement.repository]:
                var
                    usable = false

                for requirement in this.tracking[commit.repository]:
                    if requirement.constraint.check(commit.version):
                        usable = true
                        break

                if not usable:
                    toRemove.incl(commit)
                else:
                    toResolve.incl(commit)

        this.tracking[requirement.repository].add(requirement)

        for commit in toRemove:
            if not this.quiet:
                echo fmt "Graph: Excluding Commit (Not a Usable Version)"
                echo fmt "  Repository: {commit.repository.url}"
                echo fmt "  Version: {commit.version}"
            this.commits[commit.repository].excl(commit)

        for commit in toResolve:
            if this.commits[commit.repository].contains(commit):
                this.resolve(commit)
            else:
                if not this.quiet:
                    echo fmt "Graph: Skipping Resolution (Already Removed)"
                    echo fmt "  Repository: {commit.repository.url}"
                    echo fmt "  Version: {commit.version}"

        this.requirements[key].add(requirement)

    #[
    ##
    ]#
    method build*(nimbleInfo: NimbleFileInfo): void {. base .} =
        let
            repository = this.settings.getRepository(getCurrentDir())
            commit = Commit(repository: repository)

        this.requirements[(commit.repository, commit.version)] = newSeq[Requirement]()

        for requirement in nimbleInfo.requires:
            this.addRequirement(commit, this.parseRequirement(requirement))

        #
        # Determine sorting possibly by arguments to build, for now we'll just sort by least to
        # most available commits/versions with respect to repositories.  And from highest version
        # to lowest on the commits themselves.
        #

        this.commits = this.commits.pairs.toSeq().sortedByIt(it[1].len).toOrderedTable()

        for repository, commits in this.commits:
            this.commits[repository] = commits.toSeq().sorted(cmp, Descending).toHashSet()

#[
##
]#
begin Solver:

    #[
    ##
    ]#
    method init*(graph: DepGraph): void {. base .} =
        this.assignments = initTable[Repository, Assignment]()
        this.learnedConstraints = newSeq[seq[Requirement]]()
        this.graph = graph
        this.level = 0

    #[
    ##
    ]#
    method solve*(): SolverResult {. base .} =
        var
            backtrackCount = 0
            knownConflicts = initHashSet[(Commit, Commit)]()

        while true:
            #
            # If all repositories have been assigned a version, we're done.
            #

            if this.assignments.len == this.graph.commits.len:
                var
                    solution = newSeq[Commit]()

                for repository, assignment in this.assignments:
                    solution.add(assignment.commit)

                return SolverResult(
                    solution: some(solution),
                    backtrackCount: backtrackCount
                )

            #
            # Make a decision
            #
            for repository in this.graph.commits.keys:
                if this.assignments.hasKey(repository):
                    #
                    # We've already assigned this repository, just continue.  The assigmnet may
                    # be removed later if not version of the next level down is found to be
                    # consistent iwth it.
                    #
                    continue

                for commit in this.graph.commits[repository]:
                    var
                        consistentWithOtherAssignments = true
                    let
                        key = (commit.repository, commit.version)

                    if this.graph.requirements.hasKey(key):
                        #
                        # We loop through all of the requirements for this commit and check to see
                        # if any of our existing assignments violat them.
                        #
                        for requirement in this.graph.requirements[key]:
                            if this.assignments.hasKey(requirement.repository):
                                let
                                    assignment = this.assignments[requirement.repository]

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
                        this.assignments[repository] = Assignment(
                            level: this.level,
                            commit: commit
                        )
                        break

                if repository notin this.assignments:
                    #
                    # We've run through all the commmits on this repo and found none that are
                    # consistent, thus far, so we need to go back up one level.
                    #
                    inc backtrackCount

                    if this.level == 0:
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
                    for repository, assignment in this.assignments:
                        if assignment.level >= this.level:
                            toRemove.incl(repository)

                    for repository in toRemove:
                        this.assignments.del(repository)

                    dec this.level

                #
                # If we got here, we've either:
                # 1. Assigned a commit for the given repository or...
                # 2.
                break