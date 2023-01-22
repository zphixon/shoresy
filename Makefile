
.PHONY: all clean objdump debug

source_dir := src
build_dir := build

binary := $(build_dir)/forth

sources := $(wildcard $(source_dir)/*.asm)
macros := $(wildcard $(source_dir)/*.mac)

objects := $(sources:$(source_dir)%.asm=$(build_dir)%.o)

nasmflags := -g -f elf64 -I$(source_dir)
ldflags := -g

all: $(binary)

$(binary): $(objects) $(macros)
	ld $(ldflags) $(objects) -o $(binary)

$(build_dir)/%.o: $(source_dir)/%.asm $(build_dir)
	nasm $(nasmflags) $< -o $@

clean:
	rm $(objects)
	rm $(binary)

$(build_dir):
	mkdir $(build_dir)

objdump: $(binary)
	objdump -M intel -j .text -j .rodata -D --disassembler-color=on $(binary) | less -R

debug: $(binary)
	gdb $(binary)
