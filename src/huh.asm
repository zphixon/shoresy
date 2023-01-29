; vim: ft=nasm et sw=4 ts=4

    global huh
huh:
    mov rcx, 0x8998b9ac6cfb5a6f
    mov rax, 0xfffffaffffffffff ; pop rax
    mov rbx, 0xffffffffffffffff ; pop rbx
    cmp rax, rbx
    sete al
    movsx rcx, al
    neg rcx
    ret
