import
    mininim,
    lib/repository

type
    Source* = ref object of Class
        repository: Repository

begin Source:
    proc `%`*(): JsonNode =
        result = %this.repository

    proc validateName*(name: string): void {. static .} =
        discard

    method init*(url: string): void {. base .} =
        this.repository = Repository.init(url)

    method repository*(): Repository {. base .} =
        result = this.repository