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

    %ifndef link
    %define link 0
    %endif

    ; Forth word - %1=name %2=namestr %3=flags
%macro defword 2-3 0
    section .rodata
    align 8
    global name_%1
name_%1:                   ; header
    dq link                ; link
    %define link name_%1
    db %3                  ; flags
    %strlen name_%1_len %2
    db name_%1_len         ; name length
    db %2                  ; name
    align 8                ; padding
    global %1
%1:
    dq docol               ; codeword
%endmacro

    ; assembly word
    ; %1=name %2=namestr %3=flags
%macro defcode 2-3 0
    section .rodata
    align 8
    global name_%1
name_%1:                   ; header
    dq link                ; link
    %define link name_%1
    db %3                  ; flags
    %strlen name_%1_len %2
    db name_%1_len         ; name length
    db %2                  ; name
    align 8                ; padding
    global %1
%1:
    dq code_%1             ; codeword
    section .text
    align 8
    global code_%1
code_%1:                   ; actual assembly code
%endmacro

    ; variable stored in .data segment
    ; %1=name %2=namestr %3=initial %4=flags
%macro defvar 2-4 0, 0
    defcode %1, %2, %4
    push var_%1
    next
    section .data
    align 8
var_%1:
    dq %3
%endmacro

    ; builtin word to push a constant to the stack
    ; %1=name %2=namestr %3=value %4=flags
%macro defconst 3-4 0
    defcode %1, %2, %4
    push %3
    next
%endmacro


    section .text
    align 8
    global _start
_start:
    cld
    ; todo xd

    defcode drop, 'drop', 0
        pop rax
    next

    defcode swap, 'swap'
        pop rax
        pop rbx
        push rax
        push rbx
    next

    defcode dup, 'dup'
        mov rax, [rsp]
        push rax
    next

    defcode over, 'over'
        mov rax, [esp + 8]
        push rax
    next

    defcode rot, 'rot'
        pop rax
        pop rbx
        pop rcx
        push rbx
        push rax
        push rcx
    next

    defcode nrot, '-rot'
        pop rax
        pop rbx
        pop rcx
        push rax
        push rcx
        push rbx
    next

    defcode lit, 'lit'
        lodsq
        push rax
    next

    defcode store, '!'
        pop rbx
        pop rax
        mov [rbx], rax
    next

    defcode fetch, '@'
        pop rbx
        mov [rbx], rax
        push rax
    next

    defvar state, 'state'
    defvar here, 'here'
    defvar latest, 'latest', 0 ;todo add syscall0
    defvar s0, 's0'
    defvar base, 'base', 10

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
;%include "syscall.mac"
;%include "error_help.mac"
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
