Mercury
=======

[Mercury](http://www.mercurylang.org/) is a logic/functional programming
language which combines the clarity and the expressiveness of declarative
programming with advanced static analysis and error detection features.

More information is available on the
[website's about pages](http://www.mercurylang.org/about.html),
in other README files in the source code repository, and in the
[documentation](http://www.mercurylang.org/documentation/documentation.html).

## Cloning Mercury

The Mercury repository requires Git's core.autocrlf feature to be turned off,
in order to guarantee seamless building please use the following git settings before you
clone the Mercury repository:
```sh
git config --global core.autocrlf false # you can also use --system
```
In case you already cloned Mercury, or in case you do not want to modify the global configuration,
you can use:
```sh
git config --local core.autocrlf false
# before running this make sure you have no unsafed changes
git rm --cached -r . # remove files from Git's index
git reset --hard # Rewrite the Git index to pick up all the new line endings
```
Finally for cloning you can use:
```sh
git clone https://github.com/Mercury-Language/mercury.git
```
If you rather like to work in a Mercury fork, you have to fork the required Git sub-modules as well:
  - [bdwgc](https://github.com/Mercury-Language/bdwgc)
  - [libatomic_ops](https://github.com/Mercury-Language/libatomic_ops)

After cloning, please run `./prepare.sh` from the repository root to clone the required Git sub-modules and to run autoconf.

## README files

The Mercury compiler has a number of different
[backends](http://www.mercurylang.org/about/backends.html)
and works on different operating systems.
Specific information is contained in individual README files:

  * [Bootstrapping](README.bootstrap) discusses how to get Mercury installed.

    This is important as the Mercury compiler is written in Mercury.

  * C Low-level backend

    This backend works well with GCC but also works with:

      * [Clang](README.clang)

  * High-level backend targets

      * C
      * [C#](README.CSharp)
      * [Erlang](README.Erlang)
      * [Java](README.Java)

  * Platforms

      * [Linux](README.Linux)
        ([Alpha](README.Linux-Alpha),
        [PPC](README.Linux-PPC),
        [m68k](README.Linux-m68k))
      * [MacOS X](README.MacOS)
      * [FreeBSD](README.FreeBSD)
      * [OpenBSD](README.OpenBSD)
      * [AIX](README.AIX)
      * [HP-UX](README.HPUX)
      * [Solaris](README.Solaris)
      * [Windows](README.MS-Windows)
        ([Visual C](README.MS-VisualC),
        [MinGW](README.MinGW),
        [Cygwin](README.Cygwin))

  * Cross compilation

      * [MinGW](README.MinGW-cross)

## Other information

See the current [release notes](RELEASE_NOTES) for the latest stable release.
The [history](HISTORY) file is relevant if you want to find out more about the
past development of Mercury.
[News](NEWS) lists any current or future enhancements (but this isn't
always up-to-date).
The [limitations](LIMITATIONS) file lists a number of ways in which the
Mercury implementation does not yet meet its goals.

## Information for developers

If you are considering contributing to the Mercury project the website
contains some documents that may be helpful.  These include a document about
[contributions in general](http://www.mercurylang.org/development/contributions.html) and
[specific information](http://www.mercurylang.org/development/developer.html)
about contributing such as coding styles.

## Contact

See [our contact page](http://www.mercurylang.org/contact.html).
