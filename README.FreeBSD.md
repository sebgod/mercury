Mercury on FreeBSD
==================

GCC 4.2.1 Compatibility
-----------------------

FreeBSD 9.1's default version of GCC (version 4.2.1) sometimes locks up when
compiling the C code generated by the Mercury compiler. Installing GCC 4.4.7
from ports and directing Mercury to use `gcc44` as follows can fix this problem:

```
    CC=gcc44 ./configure <your normal configure arguments>
```