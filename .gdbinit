set disassembly-flavor intel
set disassemble-next-line on
set debuginfod enabled off

break _start
catch syscall read
