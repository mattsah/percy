import std/tables

type NimbleFileInfo* = object
    # Meta
    name*: string
    version*: string
    author*:string
    description*: string
    license*: string
    backend*: string

    # PM
    requires*: seq[string]
    paths*: seq[string]

    # Build
    bin*: seq[string]
    binDir*: string
    srcDir*: string
    namedBin*: Table[string, string]

    # TODO
    features*: Table[string, seq[string]]
    beforeHooks*: seq[string]
    afterHooks*: seq[string]