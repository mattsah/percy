import
    percy

const
    linksFile* = "vendor/links.json"

type
    Links* = ref object of Class
        links*: Table[string, string]

proc `[]`*(links: Links, url: string): string =
    links.links[url]

proc contains*(links: Links, url: string): bool =
    links.links.hasKey(url)

proc readLinks*(): Links =
    result = Links()
    if fileExists(linksFile):
        for k, v in json.parseFile(linksFile)["links"].pairs:
            result.links[k] = v.getStr()

proc writeLinks*(links: Links) =
    if links.links.len == 0:
        if fileExists(linksFile):
            removeFile(linksFile)
    else:
        var inner = newJObject()
        for k, v in links.links:
            inner[k] = %v
        writeFile(linksFile, pretty(%* { "links": inner }))
