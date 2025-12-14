# Percy
## Sick and tired of terrible package managers for Nim?

Percy (short for Perseus, _the greek hero that turned Atlas into stone_) is a different approach to package management for Nim.  Unlike others, it doesn't use package names (at least not in the traditional sense).  Instead, it relies solely on URLs for all package resolution.  In fact, you can name your packages almost whatever you like.

Don't worry though, your existing packages are safe with Percy.  In fact, Percy make it even easier for you to manage your own package sources by creating your very own package repository with no "special treatment" compared to any other.

> NOTE: Percy isn't actually completed yet.  If you want to play around you can clone this repo and install it with `atlas`
>
> ```bash
> git clone https://github.com/mattsah/percy
> cd percy
> atlas install
> nim build
> bin/percy <commands>
> ```

## Basic Usage

You can initialize Percy rather easily.  Simply execute the following in your project directory:

```bash
percy init
```

Once initialized, you'll see a new file called `percy.json` in your project root.  It should look something like this:

```json
{
  "meta": {},
  "sources": {
    "nim-lang": "gh://nim-lang/packages"
  },
  "packages": {}
}
```

#### Sources and Packages

- Sources are package repositories, by default `percy init` will create an empty file with the default Nim repository URL in the sources.  This should give you general compatibility with `nimble` and `atlas`
- Packages are individual package overloads.

_In both cases_ the URLs should always bit to a git repository.

If you're adding a new source, the git repository needs only to contain a `packages.json` file with the same structure as that found at https://github.com/nim-lang/packages/blob/master/packages.json.

Packages will need to contain a `.nimble` file.  Although the name of the file is irrelevant to Percy, if you want broader compatibility with other package managers, you'll probably want to conform to those standards.

##### Setting New URLs

To set a source URL you can use the `percy set` command, for example:

```bash
percy set source company-packages gh://organization/repository
```

Same for adding or overloading a package:

```bash
percy set package my-package gh://username/repository
```

#### Installing Dependencies

Once your sources and packages are setup as needed (for most people this will be no changes at all), you can go ahead and install your dependencies with:

```bash
percy install
```

> NOTE: For installation to work you need to have `git` installed and have it in your path.  We assume that's normal.

That will look something like the following:

```bash
[11:58] [master]!? matt@naimey:percy$ bin/percy install
Downloading https://github.com/nim-lang/packages into central caching
Cloning into bare repository '58CDF17AAB6671C59764F4A3FF6A0AF7761348FA'...
remote: Enumerating objects: 9906, done.
remote: Counting objects: 100% (189/189), done.
remote: Compressing objects: 100% (44/44), done.
remote: Total 9906 (delta 176), reused 145 (delta 145), pack-reused 9717 (from 2)
Receiving objects: 100% (9906/9906), 4.02 MiB | 15.81 MiB/s, done.
Resolving deltas: 100% (5915/5915), done.
Downloading https://github.com/primd-cooperative/mininim-core into central caching
Cloning into bare repository 'DFFAA9EEB5D21824761EC5397BC9D12298BA390A'...
remote: Enumerating objects: 17, done.
remote: Counting objects: 100% (15/15), done.
remote: Compressing objects: 100% (12/12), done.
remote: Total 17 (delta 2), reused 15 (delta 2), pack-reused 2 (from 1)
Receiving objects: 100% (17/17), 16.49 KiB | 703.00 KiB/s, done.
Resolving deltas: 100% (2/2), done.
Downloading https://github.com/primd-cooperative/mininim-cli into central caching
Cloning into bare repository '9533C07D6844B33BCF591287DED1F4F0E58AB290'...
remote: Enumerating objects: 25, done.
remote: Counting objects: 100% (14/14), done.
remote: Compressing objects: 100% (8/8), done.
remote: Total 25 (delta 5), reused 10 (delta 4), pack-reused 11 (from 1)
Receiving objects: 100% (25/25), 4.16 KiB | 4.16 MiB/s, done.
Resolving deltas: 100% (7/7), done.
```

You may have noticed in the above that the repository is also being downloaded into the cache.  Indeed, both your source and your packages are dependencies.

When the installation is complete, you should have a new `vendor` directory with an `index.json` file in it.  This file contains a list of all the available packages mapped to their URLs based on your sources and package overloads.

> NOTE: Actual dependency resolution is not complete yet, what follows is what **will** happen.

Based on your project's `.nimble` file and all the other `.nimble` files for its recursive dependencies, you'll also see a collection of folders in there representing your actual project dependencies, e.g.:

```
vendor
├── mininim-cli
├── mininim-core
└── index.json
```

This will also update your `nim.cfg` file with something similar to what other package manager do:

```nim
############# begin percy config section ##########
--noNimblePath
--path:"vendor/mininim-core/src"
--path:"vendor/mininim-cli/src"
############# end percy config section   ##########
```

##### Package Resolution and Path Rules

As we've already mentioned, Percy doesn't actually use or care about the package names (or versions) as defined by the `.nimble` files in your project's dependencies.  It does, however, still use the `.nimble` file for:

1. Downstream / recursive dependencies
2. Information about the `srcDir` for creating the paths.

Instead, the names come from reverse mapping the URL to the sources and packages you've provided.  In the case.  If you're using URLs directly, it will use the path information from the URL, for example if your `.nimble` file contained the following:

```bash
requires https://github.com/foobar/amazing-nim >= 1.0
requires https://github.com/euantorano/semver.nim >= 1.2.3
```

Then you would have the following:

```
vendor
├── euantorano
│  └── semver.nim
├── foobar
│  └── amazing-nim
└── index.json
```

And your `nim.cfg` might look something like the following:

```nim
############# begin percy config section ##########
--noNimblePath
--path:"vendor/euantorano/semver.nim/src"
--path:"vendor/foobar/amazing-nim"
############# end percy config section   ##########
```

In fact, if you add a package with a `/` in the alias or if your source repositories contain such names, it will also create this structure, e.g.:

```bash
percy set package mininim/core gh://primd-cooperative/mininim-core
```

Would result in:

```
vendor
├── mininim
│  └── core
└── index.json
```

_In short_, your package names are no longer tied to committed configs and code.  The only real restrictions are characters reserved for indicating versions, such as: `#`,  `>`,  `<`, `~`, `^`, and `=`.

###### Conflicting Names and URLs

When the same name is found in two sources and/or within your package overloads, the last to define it always wins with your package overloads being the highest.  It's important to note, however, there is no actual name to URL mapping in the traditional sense.  Let's assume the following case.

1. You have two distinct `sources` defined.
2. Both sources contain a package called `neo`
   1. One source maps `neo` to `https://github.com/andreaferretti/neo`
   2. The second maps `neo` to `https://github.com/xTrayambak/neo`

When executing `percy install` any `.nimble` files containing simply the name `neo` will use the latter URL.  If you need packages from the second to specifically overload other packages in the first, but still want the first instance of `neo`, simply do:

```bash
percy set package neo https://github.com/andreaferretti/neo
percy update
```

This is similar to Atlas's `pkgOverrides`, but because Percy actually uses URLs internally, it's far less likely to be needed.

If one of the downstream packages is using the second `neo` from by depending directly on the URL, no conflict will occur as your resulting vendor directory will look like this:

```
vendor
├── neo
├── xTrayambak
│  └── neo
└── index.json
```

Of course, this _cannot_ and will not prevent actual potential module name conflicts.  That is to say, both search paths will be included in the your `nim.cfg`, so if each of them has a `neo.nim` file at the root of their source path and you `import neo` you may still be up shit's creek.

#### Requiring Dependencies

The `percy.json` file only contains information about where to find packages by name (either through a source repository or your package overloads).  This is not the same as requiring the package itself, which need to modify the `.nimble` file and add it.  To actually require the dependency from the sources and packages you have available you would perform something like the following:

```bash
percy require semver '>=1.2.3'
```

This will modify your `.nimble` file to add or update the appropriate line such as:

```nim
requires "semver >= 1.2.3"
```

Similarly you can require URLs directly:

```bash
percy requires https://github.com/euantorano/semver.nim ">=1.2.3"
```

#### Removing Dependencies

To remove a dependency you would simply run:

```bash
percy remove semver
```

Or

```bash
percy remove https://github.com/euantorano/semver.nim
```

> Note: if you required a package based using a name, you can still remove it via the URL, and vice-versa if the URL maps to a name in your sources or package overloads.

This however, will not remove the corresponding source/package availability information from your `percy.json`, to do that you need to use `percy unset`:

```bash
percy unset package semver
```

If `semver` is part of a source repository, this will have no effect, but you can remove an entire repository:

```bash
percy unset source nim-lang
```

#### Building / Tasks / Etc

Percy does not aim to replace your build / installation system.  As a package manager, it is focused on gracefully handling packages and solving the madness therein.  In all the examples above we use `nim.cfg` based path configuration as `nim` itself also supports tasks via `config.nims`.  Flags and/or autodetection may be added to see whether or not `--path` entries should be added to `nim.cfg` or `nimble.paths`, but nothing has been decided yet.

While Percy intends to continue using `.nimble` files for the foreseeable future, it's not really intended to be mixed with other package managers.

If you're curious to see how we build with `nim build`, check out [the config.nims file](./config.nims)