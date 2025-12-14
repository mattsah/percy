import
    percy,
    lib/repository

type
    Package* = ref object of Class
        repository: Repository

begin Package:
    proc `%`*(): JsonNode =
        result = %this.repository

    proc validateName*(name: string): void {. static .} =
        discard

    method init*(url: string): void {. base .} =
        this.repository = Repository.init(url)

    method repository*(): Repository {. base .} =
        result = this.repository