import std/tables

type NimbleFileInfo* = object
    # Meta
    author*:string
    description*: string
    license*: string
    backend*: string

    # PM
    paths*: seq[string]
    requires*: seq[seq[string]]

    # Build
    bin*: seq[string]
    binDir*: string = "."
    srcDir*: string = "."
    namedBin*: Table[string, string]

    # TODO
    features*: Table[string, seq[string]]
