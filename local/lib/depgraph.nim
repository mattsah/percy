import
    percy,
    lib/repository,
    semver

type
    DepGraph* = ref object of Class


    Requirement* = object of Class
        repository: Repository
        condition: string

begin DepGraph:
    proc parseRequirement*(requirement: string): void {. static .} =
        discard

    method addRequirement*(requirement: string): void {. base .} =
        discard
