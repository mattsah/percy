import
    percy,
    semver,
    lib/repository


begin Commit:
    proc fromLockFile*(node: JsonNode): Commit {. static .} =
        result = Commit(
            id: node["id"].getStr(),
            version: node["version"].to(Version),
            repository: Repository.init(node["repository"].getStr()),
            info: node["info"].to(NimbleFileInfo)
        )

    method toLockFile*(): JsonNode {. base .} =
        result = newJObject()
        result["id"] = %(this.id)
        result["info"] = %(this.info)
        result["version"] = %(this.version)
        result["repository"] = %(this.repository.url)
