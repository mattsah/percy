import
    percy,
    semver,
    lib/settings,
    lib/repository,
    mininim/cli

export
    semver

type
    AddRequirementException* = ref object of CatchableError
        requirement*: Requirement

    InvalidNimVersionException* = ref object of AddRequirementException
        current*: string

    EmptyCommitPoolException* = ref object of AddRequirementException

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
        commits: seq[string]

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

    Solution* = seq[Commit]

    SolverResults* = object
        solution*: Option[Solution]
        backtrackCount*: int
        timeTaken*: float

#[

]#
begin Constraint:
    discard

#[

]#
begin AllConstraint:
    #[

    ]#
    proc init*(items: seq[Constraint]): void =
        this.check = ConstraintHook as (
            block:
                result = true
                for i in items:
                    if i.check(v) == false:
                        return false
        )

#[

]#
begin AnyConstraint:
    #[

    ]#
    proc init*(items: seq[Constraint]): void =
        this.check = ConstraintHook as (
            block:
                result = false
                for i in items:
                    if i.check(v) == true:
                        return true
        )

#[

]#
begin Requirement:
    #[

    ]#
    proc `$`*(): string =
        if this.versions.toLower() == "any":
            result = this.package
        else:
            result = fmt "{this.package} {this.versions}"

    #[

    ]#
    method repository*(): Repository {. base .} =
        result = this.repository

#[

]#
begin DepGraph:
    method stack*(): seq[Requirement] {. base .} =
        result = this.stack

    #[

    ]#
    method addRequirement*(parent: Commit, requirement: Requirement, depth: int): void {. base .}

    #[

    ]#
    method init*(settings: Settings, quiet: bool = true): void {. base .} =
        this.quiet    = quiet
        this.settings = settings

    method checkConstraint*(requirement: Requirement, commit: Commit): bool {. base .} =
        if requirement.constraint.check(commit.version):
            result = true
        elif requirement.constraint.check(ver(commit.id)):
            result = true
        else:
            result = false

    #[

    ]#
    method parseConstraint*(constraint: string, repository: Repository): Constraint {. base .} =
        return Constraint(
            check: ConstraintHook as (
                block:
                    try:
                        if constraint == "any":
                            return true
                        elif constraint.startsWith("=="):
                            return v == ver(constraint[2..^1])
                        elif constraint.startsWith(">="):
                            return v >= ver(constraint[2..^1])
                        elif constraint.startsWith("<="):
                            return v <= ver(constraint[2..^1])
                        elif constraint.startsWith("="):
                            # TODO: Should throw some kind of warning
                            return v == ver(constraint[1..^1])
                        elif constraint.startsWith("<"):
                            return v < ver(constraint[1..^1])
                        elif constraint[0] == '>':
                            return v > ver(constraint[1..^1])
                        else:
                            if constraint[0] in {'@', '#'}:
                                let
                                    version = ver(constraint[1..^1])

                                if v.build.startsWith("commit."):
                                    if version.build.startsWith("commit.)"):
                                        return v.build.startsWith(version.build) or
                                               version.build.startsWith(v.build)

                                return v == version
                            else:
                                let
                                    now =
                                        if constraint[1] == '=':
                                            # TODO: Should throw some kind of warning
                                            ver(constraint[2..^1])
                                        else:
                                            ver(constraint[1..^1])

                                if constraint[0] == '~':
                                    let
                                        next = Version(
                                            major: now.major,
                                            minor: now.minor + 1,
                                            patch: 0
                                        )
                                    return v >= now and v < next
                                elif constraint[0] == '^':
                                    let
                                        next = Version(
                                            major: now.major + 1,
                                            minor: 0,
                                            patch: 0
                                        )
                                    return v >= now and v < next
                                else:
                                    # TODO: Should throw some kind of warning
                                    return v == ver(constraint)
                    except:
                        discard

                    raise newException(
                        ValueError,
                        fmt "Invalid version constraint '{constraint}': {getCurrentExceptionMsg()}"
                    )
            )
        )

    #[

    ]#
    method parseRequirement*(requirement: string): Requirement {. base .} =
        # Something like:
        #   semver >=1.2.3|#head
        #   mininim-core >=2.1&<=2.5|>=2.8
        #   /path/to/file ^1.5
        #   gh://mattsah/percy ~=1.5
        #
        # The rules around splitting package and versions are probably OK, but longer. Only glaring
        # issue is that a URL can contain an `~`.
        #
        var
            parts: seq[string]
            commits: seq[string]
            package: string
            versions: string
            repository: Repository
            constraint = Constraint(check: ConstraintHook as (
                block:
                    result = true
            ))

        package = requirement.strip()
        versions = "any"

        for i, sym in package:
            if sym in {'=', '>', '<', '~', '^', '#', '@', ' '}:
                parts = package.split(sym, 1)
                package = parts[0].strip()
                if parts.len > 1:
                    versions = replace(sym & parts[1].toLower(), " ", "")
                break

        repository = this.settings.getRepository(package)

        if versions != "any":
            var
                anyParts = versions.split('|')
                anyItems = newSeq[Constraint](anyParts.len)

            for i, anyConstraint in anyParts:
                var
                    allParts = anyConstraint.split('&')
                    allItems = newSeq[Constraint](allParts.len)
                for j, allConstraint in allParts:
                    allItems[j] = this.parseConstraint(allConstraint, repository)
                    #
                    # Handle specific commits by adding them to separate commit tracking
                    #
                    if allConstraint[0] in {'@', '#'}:
                        let
                            id = allConstraint[1..^1]
                        if ver(id).build.startsWith("commit."):
                            commits.add(id)
                anyItems[i] = AllConstraint.init(allItems)

            constraint = AnyConstraint.init(anyItems)

        result = Requirement(
            package: package,
            versions: versions,
            repository: repository,
            constraint: constraint,
            commits: commits
        )

    #[

    ]#
    method reportStack*(): void {. base .} =
        print fmt "Graph: Package Stack Report"
        print fmt "> Size: {$this.stack.len}"
        print fmt "> Stack:"
        for i, requirement in this.stack:
            print fmt """  {alignLeft("", (i+1), ' ')}  ↳ """, 0
            print fmt """{requirement.package} {requirement.versions}"""

    #[

    ]#
    method report*(): void {. base .} =
        print "Graph: Completed With Usable Versions"

        for repository, commits in this.tracking:
            print fmt "   {fg.cyan}{repository.url}{fg.stop}:"
            for commit in commits:
                print fmt "     {fg.green}{commit.version}{fg.stop}"

    #[

    ]#
    method resolve*(commit: Commit, depth: int): void {. base .} =
        let
            key = (commit.repository, commit.version)

        this.requirements[key] = newSeq[Requirement]()

        if not this.quiet:
            print fmt "Graph: Resolving Nimble File"
            print fmt "> Source: {commit.repository.url} @ {commit.version}"

        try:
            for file in commit.repository.listDir("/", commit.id):
                if file.endsWith(".nimble"):
                        let
                            contents = commit.repository.readFile(file, commit.id)
                        when debugging(3):
                            print fmt "Graph: Parsing nimble contents"
                            print fmt "> Repository URL: {commit.repository.url}"
                            print fmt "> Repository Hash: {commit.repository.shaHash}"
                            print fmt "> Commit: {commit.version} ({commit.id})"
                            print indent(contents, 4)

                        commit.info = parser.parse(contents)
                        break

            for requirements in commit.info.requires:
                for requirement in requirements:
                    this.addRequirement(commit, this.parseRequirement(requirement), depth + 1)

            if not this.tracking.hasKey(commit.repository):
                this.tracking[commit.repository] = initOrderedSet[Commit]()

            this.tracking[commit.repository].incl(commit)

        except Exception as e:
            this.commits[commit.repository].excl(commit)

            with e of AddRequirementException:
                discard this.stack.pop()
                with e of InvalidNimVersionException:
                    warn fmt "Graph: Excluding Commit ({e.msg})"
                    info fmt "> Requirement: Nim @ {e.requirement.versions}"
                    info fmt "> Current Version: {e.current}"
                with e of EmptyCommitPoolException:
                    warn fmt "Graph: Excluding Commit ({e.msg})"
                    info fmt "> Requirement: {e.requirement.package} @ {e.requirement.versions}"
            with e of ValueError:
                warn fmt "Graph: Excluding Commit (Failed Resolving Nimble File)"
                info fmt "> Error: {e.msg}"

            info fmt "> Commit Repository URL: {commit.repository.url}"
            info fmt "> Commit Repository Hash: {commit.repository.shaHash}"
            info fmt "> Commit Version: {commit.version}"
            info fmt "> Commit Hash: {commit.id}"

    #[

    ]#
    method expandCommits*(requirement: Requirement): void {. base .} =
        if not this.commits.hasKey(requirement.repository):
            if requirement.repository.exists:
                if not this.quiet:
                    print fmt "Graph: Adding Repository (Scanning Available Tags)"
                    print fmt "> Repository URL: {requirement.repository.url}"
                    print fmt "> Repository Hash: {requirement.repository.shaHash}"

                # TODO: Remove condition
                if not requirement.repository.cacheExists or this.newest:
                    discard requirement.repository.update(quiet = this.quiet, force = true)

                this.commits[requirement.repository] = requirement.repository.getCommits()
            else:
                warn fmt "Graph: Failed Adding Repository (Cannot Connect)"
                info fmt "> Repository URL: {requirement.repository.url}"
                info fmt "> Repository Hash: {requirement.repository.shaHash}"

                this.commits[requirement.repository] = initOrderedSet[Commit](0)

        if requirement.repository.cacheExists and requirement.commits.len > 0:
            for id in requirement.commits:
                let
                    commit = requirement.repository.getCommit(id)

                if isSome(commit):
                    this.commits[requirement.repository].incl(commit.get())

    #[

    ]#
    method addRequirement*(parent: Commit, requirement: Requirement, depth: int): void {. base .} =
        this.stack.add(requirement)

        if requirement.package.toLower() == "nim":
            if not this.checkConstraint(requirement, Commit(version: ver(NimVersion))):
                raise InvalidNimVersionException(
                    msg: fmt "Unmet Nim Version Requirement",
                    current: NimVersion,
                    requirement: requirement
                )
        else:
            let
                key = (parent.repository, parent.version)

            this.expandCommits(requirement)

            if this.commits[requirement.repository].len == 0:
                raise EmptyCommitPoolException(
                    msg: fmt "Requirement Has No Available Commits",
                    requirement: requirement
                )
            else:
                var
                    toResolve = HashSet[Commit]()
                    toRemove = Table[Commit, string]()

                for commit in this.commits[requirement.repository]:
                    let
                        key = (commit.repository, commit.version)

                    if not this.requirements.hasKey(key):
                        if depth == 0:
                            if not this.checkConstraint(requirement, commit):
                                toRemove[commit] = "Not Usable At Top-Level"
                            else:
                                toResolve.incl(commit)
                        else:
                            if this.checkConstraint(requirement, commit):
                                toResolve.incl(commit)

                for commit, reason in toRemove:
                    this.commits[commit.repository].excl(commit)
                    if not this.quiet:
                        warn fmt "Graph: Excluding Commit ({reason})"
                        info fmt "> Repository URL: {commit.repository.url}"
                        info fmt "> Repository Hash: {commit.repository.shaHash}"
                        info fmt "> Commit Version: {commit.version}"
                        info fmt "> Commit Hash: {commit.id}"

                for commit in toResolve:
                    this.resolve(commit, depth)

                if not this.quiet:
                    print fmt "Graph: Adding Requirement"
                    print fmt "> Dependent: {parent.repository.url} @ {parent.version}"
                    print fmt "> Dependency: {requirement.repository.url} @ {requirement.versions}"

                this.requirements[key].add(requirement)

        discard this.stack.pop()

    #[

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

        for repository in this.commits.keys:
            if not this.tracking.hasKey(repository):
                raise newException(
                    ValueError,
                    fmt "could not find usable version(s) for '{repository.url}'"
                )

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

]#
begin Solver:
    #[

    ]#
    method init*(): void {. base .} =
        discard

    #[

    ]#
    method solve*(graph: DepGraph): SolverResults {. base .} =
        var
            level = 0
            assignments = initTable[Repository, Assignment]()
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

                return SolverResults(
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
                    # consistent with it.
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
                        # if any of our existing assignments violate them.
                        #
                        for requirement in graph.requirements[key]:
                            if assignments.hasKey(requirement.repository):
                                let
                                    assignment = assignments[requirement.repository]

                                if not graph.checkConstraint(requirement, assignment.commit):
                                    # TODO, Save some info about the current state and/or add
                                    # specific conflict info that other solutions can check first
                                    # to avoid.
                                    consistentWithOtherAssignments = false
                                    break

                    if consistentWithOtherAssignments:
                        #
                        # We were found to be consistent with all other assignments, so let's add
                        # ourself to the assignment.
                        #
                        inc level
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
                        return SolverResults(
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
                            graph.tracking[repository].excl(assignment.commit)
                            toRemove.incl(repository)

                    for repository in toRemove:
                        assignments.del(repository)

                    dec level


                #
                # If we got here, we've either:
                # 1. Assigned a commit for the given repository
                # 2. Backtracked one level up and removed the current assignment from candidates.
                break

#[

]#
begin SolverResults:
    #[

    ]#
    method isEmpty*(): bool {. base .} =
        result = isNone(this.solution)
