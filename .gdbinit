set disassembly-flavor intel
set disassemble-next-line on
set debuginfod enabled off

break _start
catch syscall read

# this shits broke
define Vars
  # latest
  echo latest=
  # pointer
  output/x ((unsigned long long) var_latest)

  # name
  printf " "
  set print elements *((int*)var_latest+9)
  output (char*) var_latest+10

  # flags
  if *((int*)var_latest+8) == 1
    printf " (immediate)"
  end
  if *((int*)var_latest+8) == 2
    printf " (hidden)"
  end
  if *((int*)var_latest+8) == 2
    printf " (immediate, hidden)"
  end

  # link
  printf " -> "
  output/x *(unsigned long long*) var_latest

  # link name
  set print elements (int)(*(unsigned long long*)var_latest+9)
  printf " %s", (char*) (*(unsigned long long*)var_latest)+10
  echo \n
  set print elements 200

  echo here=
  output/x (unsigned long long) var_here
  echo \n

  echo word_buffer="
  output (char*) word_buffer
  echo "\n
end
