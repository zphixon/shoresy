; vim: ft=nasm et sw=4 ts=4

; The way Forth works is... quite different from a typical language. In fact,
; it's hardly fair to call Forth a language; it's more like an entire system
; unto itself. You may know that it's stack-based, but that's only scratching
; the surface of how crazy this thing is.
;
; The average language (rust, for example) is made up of regular function
; calls, like so:
;
; fn main() {
;     foo();
;     bar();
;     another_twee_name();
; }
;
; which compiles to a series of call instructions, like
;
;     call foo
;     call bar
;     call another_twee_name
;
; and so on. In the olden days, when computer memory was worth its weight in
; gold, these repeated call instructions might have taken up a lot of memory.
; One way of saving on memory would have been to omit the call instruction,
; and just listing a series of addresses to jump to.
;
; Since that's not valid machine code, you would need some way to actually
; interpret those addresses:
;
; next:
;     mov rax, [rsi]     ; read next addr
;     add rsi, 8         ; point to next next addr
;     jmp rax            ; jump to the addr
;
; If rsi is pointing to a list of addresses, we would read the address and jump
; to it (after incrementing rsi to point at the next one in the list). The
; function would "return" by jumping back to next.
;
; This doesn't really help us though, because our address list function can
; only call normal functions, not functions that are also address lists. What
; we want is another layer of indirection: The address in the list should
; actually point to another address, telling us where to go next:

%macro next 0
    lodsq             ; put the next instruction in rax
    ; mov rax, [rsi]  ; equivalent to these two insns
    ; add rsi, 8
    jmp [rax]         ; go there
%endmacro

; So, when we hit a next, pull the next address, and that will tell us where to
; go to find where to go next. Got all that? More concretely:
;
; Words in Forth start with a codeword. That codeword is effectively an address
; which points to some location where execution should continue.
;
; The codeword for a word written in assembly just points to the very next
; instruction. That way, when `next` happens, rsi is pointing to the codeword,
; rax is set to that codeword, rsi increments, and we jump to where the
; codeword points to.
;
; When a word in assembly is finished, it simply executes a `next`. Since rsi
; is still set to the next codeword, rax is set to that codeword, then that
; address is jumped to.
;
; Where the magic happens is when a word is written in Forth proper: The codeword
; for a Forth word is called docol. It is jumped to as part of next, so rax
; points to it. The rsi is saved, then rax is incremented, so it points to the
; codeword of the next word, and rsi is updated to the new value of rax.
;
; If a word in Forth calls another word in Forth, and so on, you end up
; executing a chain of docols further and further down, pushing the rsp's on
; the return stack as you go along, until you hit the bottom with a word
; written in assembly.
;
; Then, when you hit a next, the next codeword gets executed, and things keep
; going.
;
; When a Forth word is finished, it executes an `exit`. This one's simple, it
; pops the rsp off the return stack and does a next. The effect is just like a
; return in a normal programming language - rsp is updated with its value when
; it was pushed, and the codeword it now points to is executed.

    ; %1=reg
%macro pushrsp 1
    lea rbp, [rbp-8]    ; decrement return stack pointer
    mov [rbp], %1       ; put reg on stack
%endmacro

    ; %1=reg
%macro poprsp 1
    mov %1, [rbp]       ; get reg from stack
    lea rbp, [rbp+8]    ; increment return stack pointer
%endmacro

    section .text
    align 8
docol:
    pushrsp rsi         ; store where we came from

    add rax, 8
    mov rsi, rax        ; start pointing to next codeword ptr

    next                ; now go there

;
; Next some more macros to make things nice. Ignore the header: for the moment,
; but do take note of the codeword.
;

%include "syscall.mac"
%include "error_help.mac"

%define FLAG_IMMEDIATE 1
%define FLAG_HIDDEN 2

%define link 0

    ; Forth word - %1=namestr %2=label %3=flags
%macro defword 2-3 0
    section .rodata
    align 8
    global name_%2
name_%2:                   ; header
    dq link                ; link
    %define link name_%2
    db %3                  ; flags
    %strlen name_%2_len %1
    db name_%2_len         ; name length
    db %1                  ; name
    align 8                ; padding
    global %2
%2:
    dq docol               ; codeword
%endmacro

    ; assembly word
    ; %1=namestr %2=label %3=flags
%macro defcode 2-3 0
    section .rodata
    align 8
    global name_%2
name_%2:                   ; header
    dq link                ; link
    %define link name_%2
    db %3                  ; flags
    %strlen name_%2_len %1
    db name_%2_len         ; name length
    db %1                  ; name
    align 8                ; padding
    global %2
%2:
    dq code_%2             ; codeword
    section .text
    align 8
    global code_%2
code_%2:                   ; actual assembly code
%endmacro

    ; variable stored in .data segment
    ; %1=namestr %2=label %3=initial %4=flags
%macro defvar 2-4 0, 0
    defcode %1, %2, %4
    push var_%2
    next
    section .data
    align 8
var_%2:
    dq %3
%endmacro

    ; builtin word to push a constant to the stack
    ; %1=namestr %2=label %3=value %4=flags
%macro defconst 3-4 0
    defcode %1, %2, %4
    push %3
    next
%endmacro


    section .text
    align 8
    global _start
    extern huh
_start:
    call huh
    cld
    ; todo xd

    defcode 'drop', drop
        pop rax
    next

    defcode 'swap', swap
        pop rax
        pop rbx
        push rax
        push rbx
    next

    defcode 'dup', dup
        mov rax, [rsp]
        push rax
    next

    defcode 'over', over
        mov rax, [esp + 8]
        push rax
    next

    defcode 'rot', rot
        pop rax
        pop rbx
        pop rcx
        push rbx
        push rax
        push rcx
    next

    defcode '-rot', nrot
        pop rax
        pop rbx
        pop rcx
        push rax
        push rcx
        push rbx
    next

    defcode '2drop', twodrop
        pop rax
        pop rax
    next

    defcode '2dup', twodup
        mov rax, [rsp]
        mov rbx, [rsp+8]
        push rbx
        push rax
    next

    defcode '2swap', twoswap
        pop rax
        pop rbx
        pop rcx
        pop rdx
        push rbx
        push rax
        push rdx
        push rcx
    next

    defcode '?dup', qdup
        mov rax, [rsp]
        test rax, rax
        jz .end
        push rax
    .end:
    next

    defcode '1+', increment
        inc qword [rsp]
    next

    defcode '1-', decrement
        dec qword [rsp]
    next

    defcode '4+', inc4
        add qword [rsp], 4
    next

    defcode '4-', dec4
        sub qword [rsp], 4
    next

    defcode '+', add_
        pop rax
        add [rsp], rax
    next

    defcode '-', sub_
        pop rax
        sub [rsp], rax
    next

    defcode '*', mul_
        pop rax
        pop rbx
        imul rax, rbx
        push rax
    next

    defcode '/mod', divmod
        pop rbx
        pop rax
        xor rdx, rdx
        idiv rbx
        push rdx
        push rax
    next

    ; %1=comparator
%macro compare 1
    pop rax
    pop rbx
    cmp rax, rbx  ; compare stack elements
    %1 al         ; get flag bit as byte
    movsx rcx, al ; sign extend copy
    neg rcx       ; 2s complement negate
    push rcx      ; forth convention is that true is all 1s
%endmacro

    defcode '=', equals
        compare sete
    next

    defcode '<>', nequals
        compare setne
    next

    defcode '<', lessthan
        compare setl
    next

    defcode '>', greaterthan
        compare setg
    next

    defcode '<=', lesseq
        compare setle
    next

    defcode '>=', greq
        compare setge
    next

    ; %1=comparator
%macro compare_zero 1
    pop rax
    test rax, rax
    %1 al
    movsx rbx, al
    neg rbx
%endmacro

    defcode '0=', eqzero
        compare_zero setz
    next

    defcode '0<>', neqzero
        compare_zero setnz
    next

    defcode '0<', ltzero
        compare_zero setl
    next

    defcode '0>', gtzero
        compare_zero setg
    next

    defcode '0<=', lezero
        compare_zero setle
    next

    defcode '0>=', gezero
        compare_zero setge
    next

    defcode 'and', bitand
        pop rax
        and [rsp], rax
    next

    defcode 'or', bitor
        pop rax
        or [rsp], rax
    next

    defcode 'xor', bitxor
        pop rax
        xor [rsp], rax
    next

    defcode 'and', invert
        not qword [rsp]
    next









    defcode 'lit', lit
        lodsq
        push rax
    next

    defcode '!', store
        pop rbx
        pop rax
        mov [rbx], rax
    next

    defcode '@', fetch
        pop rbx
        mov [rbx], rax
        push rax
    next

    defvar 'state', state
    defvar 'here', here
    defvar 'latest', latest, 0 ; todo add syscall0
    defvar 's0', s0
    defvar 'base', base, 10

    defconst 'version', version, 1
    defconst 'r0', rz, return_stack_top
    defconst 'docol', _docol, docol
    defconst 'flag_immediate', flag_immediate, FLAG_IMMEDIATE
    defconst 'flag_hidden', flag_hidden, FLAG_HIDDEN

    defconst 'sys_exit', sys_exit, syscall_exit
    defconst 'sys_open', sys_open, syscall_open
    defconst 'sys_close', sys_close, syscall_close
    defconst 'sys_read', sys_read, syscall_read
    defconst 'sys_write', sys_write, syscall_write
    defconst 'sys_creat', SYS_CREAT, syscall_creat
    defconst 'sys_brk', sys_brk, syscall_brk

    defconst 'open_readonly', open_readonly, 0
    defconst 'open_writeonly', open_writeonly, 1
    defconst 'open_readwrite', open_readwrite, 2

    defcode '>r', to_r
        pop rax
        pushrsp rax
    next

    defcode 'r>', from_r
        poprsp rax
        push rax
    next

    ;defcode 'rsp@'

return_stack_top:

;; dictionary entry:
;;
;; 8 bytes - link to previous entry
;; 1 byte - flags
;; 1 byte - name length
;; n bytes - name and padding
;; 8 bytes - the codeword
;; ? bytes - the code
;; 8 bytes - next, or addr of exit
;
;
;    section .text
;    align 8
;    global _start
;_start:
;    cld                       ; reset direction flag, which affects lods
;
;    mov var_s0, rsp           ; save initial data stack pointer in s0
;    mov rbp, return_stack_top ; initialize return stack
;
;    xor rbx, rbx
;    mov rax, syscall_brk
;    syscall                   ; brk(0), get location of program break
;
;    mov [var_here], rax       ; set up here to beginning of data segment
;
;    add rax, 65536
;    mov rdi, rax
;    mov rax, syscall_brk
;    syscall                   ; brk(inital data segment size + 65536)
;
;    cmp rax, [var_here]       ; check if it worked
;    jne .ok
;    set_error brk_failed
;    call error_exit
;.ok:
;
;quit:
;    mov rdi, 0
;    mov rax, syscall_exit
;    syscall
;
;
;    defword abc
;    defword abc1
;    defword abc2
;    defword abc3
;    defword abc4
;    defword abc5
;
;    section .bss
;
;    alignb 4096
;return_stack:
;    resb 8192
;return_stack_top:
;
;    alignb 4096
;buffer: resb 4096
;
;    alignb 4096
;var_s0: resq 1
;var_here: resq 1
;
