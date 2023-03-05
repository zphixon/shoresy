# shoresy

A 64-bit Linux intel forth in the style of Jones' forth. See src/main.asm.

Compile with `make`.

TODO:
- make nice debugging facilities
  - I imagine a bunch of variables containing values that might be interesting
    to look at as the program executes, updated by docol/interpret
  - also some type information would be nice
  - gdb commands to skip over words
  - or just a debugger written in forth
