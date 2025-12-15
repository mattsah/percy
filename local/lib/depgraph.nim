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
    proc init*(check: ConstraintHook): void =
        this.check = check
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

    method parseRequirement*(requirement: string): Requirement =
        # Something like:
        #   semver >=1.2.3|#head
        #   mininim-core >=2.1,<=2.5|>=2.8
        #   /path/to/file ^1.5
        #   gh://mattsah/percy ~=1.5
        let
            parts = requirement.split(' ', 2)
        var
            items = newSeq[Constraint]()
            package = parts[0].strip()
            constrain = "any"

        result.repository = this.settings.getRepository(package)

        if parts.len > 1:
            constrain = parts[1].replace(" ", "")

        discard

    method build*(): void {. base .} =
        #        for requirement in nimbleInfo.requires:
        #            depgraph.addRequirement(requirement)
        discard

    method addRequirement*(requirement: string): void {. base .} =
        discard
