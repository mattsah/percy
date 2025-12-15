import
    percy,
    lib/settings,
    lib/repository

type
    DepGraph* = ref object of Class


    Requirement* = object of Class
        repository: Repository
        condition: string

begin DepGraph:
    proc parseRequirement*(requirement: string): void {. static .} =
        discard

    method init*(settings: Settings, nimbleInfo: NimbleFileInfo): void {. base .} =
        discard

    method addRequirement*(requirement: string): void {. base .} =
        discard
