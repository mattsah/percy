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
        repository: Repository
        antecedent: Option[seq[Requirement]]
        version: Version

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

    Solution* = Table[Repository, Version]

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
    method parseConstraint*(constraint: string, repository: Repository): Constraint {. base .}=
        let
            cleaned = constraint.replace(" ", "")

        if cleaned.startsWith("=="):
            return Constraint(check: ConstraintHook as (
                result = v == v(cleaned[2..^1])
            ))
        elif cleaned.startsWith(">="):
            return Constraint(check: ConstraintHook as (
                result = v >= v(cleaned[2..^1])
            ))
        elif cleaned.startsWith("<="):
            return Constraint(check: ConstraintHook as (
                result = v <= v(cleaned[2..^1])
            ))
        elif cleaned.startsWith("<"):
            return Constraint(check: ConstraintHook as (
                result = v < v(cleaned[1..^1])
            ))
        elif cleaned.startsWith(">"):
            return Constraint(check: ConstraintHook as (
                result = v > v(cleaned[1..^1])
            ))
        else:
            let
                now = v(cleaned[1..^1])
            if cleaned.startsWith("~"):
                let
                    next = Version(major: now.major, minor: now.minor + 1, patch: 0)
                return Constraint(check: ConstraintHook as (
                    result = v >= now and v < next
                ))
            elif cleaned.startsWith("^"):
                let
                    next = Version(major: now.major + 1, minor: 0, patch: 0)
                return Constraint(check: ConstraintHook as (
                    result = v >= now and v < next
                ))
            elif cleaned.startsWith("#"):
                return Constraint(check: ConstraintHook as (
                    block:
                        let
                            head = cleaned[1..^1].replace(re"[!@#$%^&*+_.,]", "-")
                        result = v == v("0.0.0-branch." & head)
                ))

        raise newException(ValueError, "Invalid version constraint '{constraint}'")

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
            let
                versions = commits.mapIt($(it.version)).join(", ")

            echo fmt "  {repository.url}:"
            echo fmt ""
            echo fmt "  {versions}"
            echo fmt ""

    #[
    ##
    ]#
    method resolve*(commit: Commit): void {. base .} =
        var
            nimbleInfo: NimbleFileInfo
        let
            key = (commit.repository, commit.version)

        if not this.requirements.hasKey(key):
            if not this.quiet:
                echo fmt "Graph: Resolving Nimble File"
                echo fmt "  Source: {commit.repository.url} @ {commit.version}"

            this.requirements[key] = newSeq[Requirement]()

            for file in commit.repository.list("/", commit.id):
                if file.endsWith(".nimble"):
                    when debugging(2):
                        echo repository.read(file, commit.id)
                    nimbleInfo = parser.parseFile(commit.repository.read(file, commit.id))
                    for requirement in nimbleInfo.requires:
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
            this.resolve(commit)

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
    method analyze*(solver: Solver, conflict: seq[Requirement]): seq[Requirement] {. base .} =
        var
            learned = initHashSet[Requirement]()

        for dep in conflict:
            learned.incl(dep)

        toSeq(learned)
    ]#

    #[
    ##
    ]#
    method solve*(): SolverResult {. base .} =
        var
            backtrackCount = 0

        while true:
            var
                changed = true

            while changed:
                changed = false

                for dependant, requirements in this.graph.requirements:
                    let
                        repository = dependant[0] # Tuple unpacking doesn't seem to work in loop
                        version {. used .} = dependant[1]

                    if repository in this.assignments:
                        continue

                    # If all but one dependency is satisfied, the last one is forced
                    var
                        unsatisfied: seq[Requirement] = @[]

                    for requirement in requirements:
                        if requirement.repository in this.assignments:
                            let
                                assignedVersion = this.assignments[requirement.repository].version
                            if not requirement.constraint.check(assignedVersion):
                                unsatisfied.add(requirement)
                        else:
                            unsatisfied.add(requirement)

                    if unsatisfied.len == 1:
                        # Unit clause - forced assignment
                        let
                            forcedRequirement = unsatisfied[0]
                        # We would need to choose a version that satisfies the constraint
                        # Simplified for this example
                        changed = true

            # All variables assigned?
            if this.assignments.len == this.graph.commits.len:
                var
                    solution = initTable[Repository, Version]()

                for repository, assignment in this.assignments:
                    solution[repository] = assignment.version

                return SolverResult(
                    solution: some(solution),
                    backtrackCount: backtrackCount
                )

            # Make a decision
            for repository in this.graph.commits.keys:
                if not this.assignments.hasKey(repository):
                    # Choose a version (simplified - always pick newest)
                    let
                        tags = this.graph.commits[repository]

                    for tag in tags:
                        # Check consistency
                        var
                            consistent = true
                        let
                            key = (repository, tag.version)

                        if this.graph.requirements.hasKey(key):
                            for requirement in this.graph.requirements[key]:
                                if requirement.repository in this.assignments:
                                    if not requirement.constraint.check(this.assignments[requirement.repository].version):
                                        consistent = false
                                        break

                        if consistent:
                            this.assignments[repository] = Assignment(
                                level: this.level,
                                repository: repository,
                                version: tag.version
                            )
                            break

                    if repository notin this.assignments:
                        backtrackCount += 1

                        # Simplified backtracking (full CDCL would analyze conflict)
                        if this.level == 0:
                            return SolverResult(
                                solution: none(Solution),
                                backtrackCount: backtrackCount
                            )

                        # Backtrack to previous decision level
                        var
                            toRemove = initHashSet[Repository]()
                        for repository, assignment in this.assignments:
                            if assignment.level >= this.level:
                                toRemove.incl(repository)

                        for repository in toRemove:
                            this.assignments.del(repository)

                        this.level -= 1

                    break

        # Should not reach here
        result = SolverResult(
            solution: none(Solution)
        )