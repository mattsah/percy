import
    percy,
    lib/repository

type
    Package* = ref object of Class
        repository: Repository

begin Package:
    proc `%`*(): JsonNode =
        result = newJString(this.repository.origin)

    proc validateName*(name: string): void {. static .} =
        discard

    method init*(repository: Repository): void {. base .} =
        this.repository = repository

    method repository*(): Repository {. base .} =
        result = this.repository
