import
    percy,
    semver,
    algorithm,
    lib/settings,
    lib/repository

type
    ConstraintHook* {. inheritable .} = proc(v: Version): bool

    Constraint* = ref object of Class
        check: ConstraintHook

    AllConstraint* = ref object of Constraint

    AnyConstraint* = ref object of Constraint

    Requirement* = object
        repository: Repository
        constraint: Constraint

    DepGraph* = ref object of Class
        settings: Settings
        nimbleInfo: NimbleFileInfo
        packages: Table[string, seq[Version]]

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
    method init*(settings: Settings, nimbleInfo: NimbleFileInfo): void {. base .} =
        this.settings = settings
        this.nimbleInfo = nimbleInfo

    method parseConstraint(constraint: string): Constraint {. base .}=
        discard

    method parseRequirement(requirement: string): Requirement {. base .} =
        # Something like:
        #   semver >=1.2.3|#head
        #   mininim-core >=2.1,<=2.5|>=2.8
        #   /path/to/file ^1.5
        #   gh://mattsah/percy ~=1.5
        #
        # The rules around splitting constraints are probably OK, but longer
        # term we might need to parse out the package differently if spaces
        # are not common dividing repository + constraints.  Problem is a
        # URL can contain a ~ and so can a constraint.
        let
            parts = requirement.strip().split(' ', 2)
        var
            package = parts[0].strip()
            constraint = Constraint(check: ConstraintHook as (
                block:
                    return true
            ))

        if parts.len > 1:
            var
                anyParts = parts[1].replace(" ", "").split('|')
                anyItems = newSeq[Constraint](anyParts.len)
            for anyConstraint in anyParts:
                var
                    allParts = anyConstraint.split(',')
                    allItems = newSeq[Constraint](allParts.len)
                for allConstraint in allParts:
                    allItems.add(this.parseConstraint(allConstraint))
                anyItems.add(AllConstraint.init(allItems))
            constraint = AnyConstraint.init(anyItems)

        result = Requirement(
            repository: this.settings.getRepository(package),
            constraint: constraint
        )

    method build*(): void {. base .} =
        #        for requirement in nimbleInfo.requires:
        #            depgraph.addRequirement(requirement)
        discard

    method addRequirement*(requirement: string): void {. base .} =
        discard
