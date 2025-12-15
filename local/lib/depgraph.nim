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
        packages =  initTable[string, seq[Version]]

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
    proc parseRequirement*(requirement: string): void {. static .} =
        # Something like:
        #   semver>=1.2.3
        #   mininim-core>=2.1,<=2.5|>=2.8
        #   gh://mattsah/percy~=1.5
        discard

    method init*(settings: Settings, nimbleInfo: NimbleFileInfo): void {. base .} =
        discard

    method build*(): void {. base .} =
        #        for requirement in nimbleInfo.requires:
        #            depgraph.addRequirement(requirement)
        discard

    method addRequirement*(requirement: string): void {. base .} =
        discard
