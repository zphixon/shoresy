
.PHONY: all clean objdump debug meta

source_dir := src
build_dir := build

binary := $(build_dir)/forth

sources := $(wildcard $(source_dir)/*.asm)
macros := $(wildcard $(source_dir)/*.mac)

objects := $(sources:$(source_dir)%.asm=$(build_dir)%.o)

nasmflags := -g -f elf64 -I$(source_dir)
ldflags := -g

all: $(binary)

meta:
	$(info sources: $(sources))
	$(info objects: $(objects))
	$(info binary: $(binary))
	$(info macros: $(macros))

$(binary): $(objects) $(macros)
	ld $(ldflags) $(objects) -o $(binary)

$(build_dir)/%.o: $(sources) $(macros)
	@mkdir $(build_dir) -p
	nasm $(nasmflags) $< -o $@

clean:
	rm $(objects)
	rm $(binary)

objdump: $(binary)
	objdump -M intel -sj .text -sj .rodata -sj .data -D --disassembler-color=on $(binary) | less -R

debug: $(binary)
	gdb $(binary)
