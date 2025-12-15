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
        repository: Repository
        constraint: Constraint

    DepGraph* = ref object of Class
        repositories: Table[Repository, seq[Commit]]
        requirements: Table[(Repository, Commit), seq[Requirement]]
        conflicts: Table[(Repository, Commit), HashSet[string]]
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
                    if not i.check(v):
                        result = false
                discard
        )

begin AnyConstraint:
    proc init*(items: seq[Constraint]): void =
        this.check = ConstraintHook as (
            block:
                result = false
                for i in items:
                    if i.check(v):
                        result = true
                        break
                discard
        )

begin DepGraph:
    method addRequirement*(commit: Commit, repository: Repository, requirement: Requirement): void {. base .}

    method init*(settings: Settings): void {. base .} =
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
            cleaned = Constraint(check: ConstraintHook as (
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

            cleaned = AnyConstraint.init(anyItems)

        result = Requirement(
            repository: repository,
            constraint: cleaned
        )

    method resolve*(commit: Commit, repository: Repository): void {. base .} =
        let
            nimbleInfo = parser.parseFile(repository.read("*.nimble", commit.id))
        for requirement in nimbleInfo.requires:
            this.addRequirement(commit, repository, this.parseRequirement(requirement))

    method addRepository*(repository: Repository): void {. base .} =
        if not this.repositories.hasKey(repository):
            this.repositories[repository] = repository.tags

    method addRequirement*(commit: Commit, repository: Repository, requirement: Requirement): void {. base .} =
        let
            key = (repository, commit)

        if not this.requirements.hasKey(key):
            this.requirements[key] = newSeq[Requirement]()

        this.requirements[key].add(requirement)
        this.addRepository(requirement.repository)

        for commit in this.repositories[requirement.repository]:
            if requirement.constraint.check(commit.version):
                this.resolve(commit, requirement.repository)

begin Solver:
    discard