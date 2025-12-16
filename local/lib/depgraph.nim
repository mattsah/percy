import
    percy,
    semver,
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
        commits: Table[Repository, seq[Commit]]
        requirements: Table[Commit, seq[Requirement]]
        excludes: HashSet[Commit]
        settings: Settings

    Solver* = ref object of Class
        settings: Settings
        nimbleInfo: NimbleFileInfo

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
    method addRequirement*(commit: Commit, requirement: Requirement): void {. base .}

    method init*(settings: Settings, quiet: bool = true): void {. base .} =
        this.quiet    = quiet
        this.settings = settings

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
                        result = true
                        # get the hash to match the version from the repository
                        # and check whether or not that hash is in the history of
                        # the corresponding branch/reference
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
    method resolve*(tag: Commit, repository: Repository): void {. base .} =
        var
            usable = true
            nimbleInfo: NimbleFileInfo

        block checkUsability:
            for _, requirements in this.requirements:
                for requirement in requirements:
                    if tag.repository == requirement.repository:
                        usable = false
                        if requirement.constraint.check(tag.version):
                            usable = true
                            break checkUsability
        if usable:
            if not this.quiet:
                echo fmt "Graph: Resolving Nimble File"
                echo fmt "  Source: {repository.url} @ {tag.version}"

            for file in repository.list("/", tag.id):
                if file.endsWith(".nimble"):
                    when debugging(2):
                        echo repository.read(file, tag.id)
                    nimbleInfo = parser.parseFile(repository.read(file, tag.id))
                    for requirement in nimbleInfo.requires:
                        this.addRequirement(tag, this.parseRequirement(requirement))
                    break
        else:
            if not this.quiet:
                echo fmt "Graph: Excluding Commit (Not a Usable Version)"
                echo fmt "  Repository: {tag.repository.url}"
                echo fmt "  Version: {tag.version}"

            this.excludes.incl(tag)

    #[
    ##
    ]#
    method addRepository*(repository: Repository): void {. base .} =
        if not this.commits.hasKey(repository):
            if not this.quiet:
                echo fmt "Graph: Adding Repository (Scanning Available Tags)"
                echo fmt "  Repository: {repository.url}"

            this.commits[repository] = repository.tags

    #[
    ##
    ]#
    method addRequirement*(commit: Commit, requirement: Requirement): void {. base .} =
        if not this.quiet:
            echo fmt "Graph: Adding Requirement"
            echo fmt "  Dependent: {commit.repository.url} @ {commit.version}"
            echo fmt "  Dependends On: {requirement.repository.url} @ {requirement.original}"

        if not this.requirements.hasKey(commit):
            this.requirements[commit] = newSeq[Requirement]()

        this.addRepository(requirement.repository)

        for tag in this.commits[requirement.repository]:
            if this.excludes.contains(tag):
                continue
            if not requirement.constraint.check(tag.version):
                continue

            this.resolve(tag, requirement.repository)

        this.requirements[commit].add(requirement)

begin Solver:
    discard