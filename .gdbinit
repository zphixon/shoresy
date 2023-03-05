set disassembly-flavor intel
set disassemble-next-line on
set debuginfod enabled off

break _start
catch syscall read

# this shits broke
define Vars
  set print address off
  echo latest=
  output/x (unsigned long long)var_latest

  # name
  printf " "
  set print elements *(unsigned char*) ((unsigned long long)var_latest + 9)
  output (char*) ((unsigned long long)var_latest + 10)

  # flags
  if *(unsigned char*) ((unsigned long long)var_latest + 8) == 1
    printf " (immediate)"
  end
  if *(unsigned char*) ((unsigned long long)var_latest + 8) == 2
    printf " (hidden)"
  end
  if *(unsigned char*) ((unsigned long long)var_latest + 8) == 3
    printf " (immediate, hidden)"
  end

  # link
  printf " -> "
  output/x *(unsigned long long*)var_latest

  # link name
  printf " "
  set print elements *(unsigned char*) ((*(unsigned long long*)var_latest) + 9)
  output (char*) ((*(unsigned long long*)var_latest) + 10)
  set print elements 200

  # link flags
  if *(unsigned char*) ((*(unsigned long long*)var_latest) + 8) == 1
    printf " (immediate)"
  end
  if *(unsigned char*) ((*(unsigned long long*)var_latest) + 8) == 2
    printf " (hidden)"
  end
  if *(unsigned char*) ((*(unsigned long long*)var_latest) + 8) == 3
    printf " (immediate, hidden)"
  end
  echo \n

  # other vars
  echo here=
  output/x (unsigned long long) var_here
  echo \n

  echo state=
  if (unsigned long long)var_state == 0
    printf "immediate"
  end
  if (unsigned long long)var_state != 0
    printf "compile"
  end
  echo \n

  echo word_buffer="
  printf "%s", (char*) &word_buffer
  echo "\n

  echo base=
  printf "%d", (int) var_base
  echo \n
  set print address on
end
