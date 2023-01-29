# shoresy

A 64-bit Linux intel forth in the style of Jones' forth. See src/main.asm.

Compile with `make`.

TODO:
- 64-bit syscalls use rsi as the first argument: refactor
  - next macro
  - lit
  - tick
  - branch and 0branch
  - litstring
  - docol
  - cold_start?
  - exit
  - cmove
  - key
  - find
  - create
