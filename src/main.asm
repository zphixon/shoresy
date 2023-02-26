; vim: ft=nasm et sw=4 ts=4

[default rel]
[bits 64]

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
; it was pushed, and the codeword it now points to is executed. We'll define it
; later in this file.

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
_start:
    ;extern huh
    ;call huh
    cld
    mov [var_s0], rsp
    mov rbp, return_stack_top

    xor rdi, rdi
    mov rax, syscall_brk  ; brk(0)
    syscall
    mov [var_here], rax   ; set up here to initial data segment
    add rax, 65535
    mov rdi, rax
    mov rax, syscall_brk
    syscall               ; add 65535 bytes to data segment
    cmp rax, [var_here]   ; see if it worked
    jne .ok

    set_error brk_failed
    call error_exit

.ok:
    mov rsi, cold_start
    next

    section .rodata
cold_start:
    dq quit

    ;;push qword STRING
    ;;push qword 5
    ;;jmp code_create
    ;;set_error goodbye, 0
    ;;call error_exit
    ;;; todo xd

;;    section .data
;;STRING: db 'balls'
;;        db 0

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

    defcode 'exit', exit
        poprsp rsi
    next

    defcode 'lit', lit
        lodsq            ; sneakily get what rsi is pointing at
        push rax         ; and push it on the stack, skipping over it
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

    defcode '+!', addstore
        pop rbx
        pop rax
        add [rbx], rax
    next

    defcode '-!', substore
        pop rbx
        pop rax
        sub [rbx], rax
    next

    defcode 'c!', storebyte
        pop rbx
        pop rax
        mov [rbx], al ; xor [rbx], [rbx] first?
    next

    defcode 'c@', fetchbyte
        pop rbx
        xor rax, rax
        mov al, [rbx]
        push rax
    next

    defcode 'c@c!', charcopy
        mov rbx, [rsp + 8] ; probably wrong?
        mov al, [rbx]
        pop rdi
        stosb
        push rdi
        inc qword [rsp + 8]
    next

    defcode 'cmove', block_copy
        mov rdx, rsi
        pop rcx
        pop rdi
        pop rsi
        rep movsb
        mov rsi, rdx
    next

    defvar 'state', state      ; is the interpreter executing (0) or compiling?
    defvar 'latest', latest, name_syscall0 ; the most recently defined word
    defvar 'here', here        ; points to next free quad
    defvar 's0', s0            ; address of the top of the parameter stack
    defvar 'base', base, 10    ; base for reading and printing numbers

    defconst 'version', version, 1
    defconst 'r0', rz, return_stack_top   ; address to the top of the return stack
    defconst 'docol', _docol, docol
    defconst 'flag_immediate', flag_immediate, FLAG_IMMEDIATE
    defconst 'flag_hidden', flag_hidden, FLAG_HIDDEN

    defconst 'sys_exit', sys_exit, syscall_exit
    defconst 'sys_open', sys_open, syscall_open
    defconst 'sys_close', sys_close, syscall_close
    defconst 'sys_read', sys_read, syscall_read
    defconst 'sys_write', sys_write, syscall_write
    defconst 'sys_creat', sys_creat, syscall_creat
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

    defcode 'rsp@', rspfetch
        push rbp
    next

    defcode 'rsp!', rspstore
        pop rbp
    next

    defcode 'rdrop', rdrop
        add rbp, 4
    next

    defcode 'dsp@', dspfetch
        mov rax, rsp
        push rax
    next

    defcode 'dsp!', dspstore
        pop rsp
    next

    ; read a single byte from stdin
    defcode 'key', key
        call _key
        push rax
    next
_key:
    mov rbx, [currkey]    ; ptr to last char in input buffer
    cmp rbx, [bufftop]    ; compare to ptr to end of buffer
    jge .readmore         ; need more?
    xor rax, rax
    mov al, [rbx]         ; no, just get the next key
    inc rbx
    mov [currkey], rbx    ; update ptr to last char
    ret
.readmore:
    push rsi
    mov rax, syscall_read ; read(fd, buf, count)
    xor rdi, rdi          ; fd 0 is stdin
    lea rsi, buffer       ; ptr to buffer
    mov [currkey], rsi    ; reset currkey while we're here
    mov rdx, 4096         ; buffer size
    syscall
    pop rsi
    cmp rax, 0            ; exit if rax <= 0
    jle .exit
    add rax, buffer       ; bufftop = buffer + rax (num bytes read)
    mov [bufftop], rax
    jmp _key              ; return what we read
.exit:
    set_error read_failed
    call error_exit
    section .data
currkey: dq buffer
bufftop: dq buffer

    ; write a single char to stdout
    defcode 'emit', emit
        pop rax                  ; the macro moves us back to .text
        call _emit               ; todo buffering?
    next
_emit:
    push rsi
    mov [emit_scratch], rax
    mov rax, syscall_write   ; write(fd, buf, count)
    mov rdi, 1               ; fd
    mov rsi, emit_scratch    ; buf
    mov rdx, 1               ; count
    syscall
    pop rsi
    ret
    section .data
emit_scratch:
    db 1

    ; read the next whitespace-delimited word
    defcode 'word', word_
        call _word
        push rdi              ; ptr to start of word
        push rcx              ; length of word
    next
_word:
    call _key                 ; get a byte
    cmp al, '\'               ; start of comment?
    je .skip_comment
    cmp al, ' '               ; skip past spaces
    jbe _word
    mov rdi, word_buffer      ; ptr to return buffer
.next:
    stosb                     ; add char to return buffer (mov [rdi], al)
    call _key                 ; get a single char
    cmp al, ' '               ; skip past spaces
    ja .next
    sub rdi, word_buffer
    mov rcx, rdi              ; return length of the word
    mov rdi, word_buffer      ; return address of the word
    ret
.skip_comment:
    call _key
    cmp al, 10                ; skip until newline
    jne .skip_comment
    jmp _word
    section .data
word_buffer:
    times 32 db 0

    ; read a number in some base
    defcode 'number', number
        pop rcx          ; length of string
        pop rdi          ; start of string
        call _number
        push rax         ; parsed number
        push rcx         ; number of unparsed chars
    next
_number:
    xor rax, rax
    xor rbx, rbx
    test rcx, rcx
    jz .end              ; zero-length string is error
    mov rdx, [var_base]  ; get the current base
    mov bl, [rdi]        ; check if first char is -
    inc rdi
    push rax             ; save a zero on the stack
    cmp bl, '-'          ; starts with '-'?
    jnz .convert
    pop rax
    push rbx             ; put nonzero on stack, indicating negative number
    dec rcx
    jnz .read_digit
    pop rbx              ; error: string is just '-'
    mov rcx, 1
    ret
.read_digit:
    imul rax, rdx        ; rax *= base
    mov bl, [rdi]        ; set bl to next char in string
    inc rdi
.convert:
    sub bl, '0'          ; digit < 0?
    jb .negate
    cmp bl, 10           ; <= 9?
    jb .base_check
    sub bl, 17           ; < A (17 is 'A' - '0')
    jb .negate
    add bl, 10
.base_check:
    cmp bl, dl           ; >= base?
    jge .negate
    add rax, rbx         ; add it to rax adn loop
    dec rcx
    jnz .read_digit
.negate:
    pop rbx              ; negate result if first char was -
    test rbx, rbx
    jz .end
    neg rax
.end:
    ret

    ; find a word in the dictionary
    defcode 'find', find
        pop rcx              ; length
        pop rdi              ; address
        call _find
        push rax             ; dictionary header address
    next
_find:
    push rsi                 ; save for string comparison
    mov rdx, [var_latest]    ; look backward through the dictionary starting from latest
.check_end:
    test rdx, rdx
    je .not_found
    xor rax, rax
    mov al, [rdx + 8]        ; check hidden flag
    and al, FLAG_HIDDEN
    jnz .follow_link
    mov al, [rdx + 9]        ; get length
    cmp cl, al
    jne .follow_link
    push rcx                 ; hold onto length
    push rdi                 ; and adddress
    lea rsi, [rdx + 10]
    repe cmpsb               ; compare strings
    pop rdi
    pop rcx
    jne .follow_link         ; not equal
    pop rsi
    mov rax, rdx             ; found it, nice
    ret
.follow_link:
    mov rdx, [edx]           ; follow the link
    jmp .check_end
.not_found:
    pop rsi
    xor rax, rax             ; zero indicates not found
    ret

    ; get codeword from a dictionary entry
    defcode '>cfa', tocfa
        pop rdi          ; dict entry ptr
        call _tocfa
        push rdi         ; codeword
    next
_tocfa:
    xor rax, rax
    add rdi, 8           ; go past link pointer
    mov al, [rdi + 1]    ; load length to al
    add rdi, 2           ; skip flags and length
    add rdi, rax         ; skip the name
    add rdi, 7           ; the codeword is 8-byte aligned
    and rdi, ~7          ; align the pointer to it
    ret

    ; get pointer to first word in dict entry
    defword '>dfa', todfa
        dq tocfa           ; get codeword
        dq inc4            ; go past it to get the first word
        dq inc4
        dq exit

    ; write a dictionary entry header
    defcode 'create', create
        pop rcx                ; name length
        pop rbx                ; name addr
        mov rdi, [var_here]    ; the header will go in rdi
        mov rdx, [var_latest]  ; get link pointer
        stosq                  ; store it in the header
        mov al, 0              ; store the flags
        stosb
        mov al, cl             ; get the length
        stosb                  ; store the length
        push rsi               ; copy the name
        mov rsi, rbx
        rep movsb
        pop rsi
        add rdi, 7             ; align to 8 byte boundary
        and rdi, ~7
        mov rax, [var_here]    ; update here and latest
        mov [var_latest], rax
        mov [var_here], rdi
    next

    ; append 64-bit integer to memory pointed by here, add 8 to here
    defcode ',', comma
        pop rax
        call _comma
    next
_comma:
    mov rdi, [var_here]  ; put here in rdi
    stosq                ; store rax to [rdi]
    mov [var_here], rdi  ; update here
    ret

    defcode '[', lbrac, FLAG_IMMEDIATE
        xor rax, rax
        mov [var_state], rax   ; set state to 0
    next

    defcode ']', rbrac, FLAG_IMMEDIATE
        mov qword [var_state], 1  ; set state to 1
    next

    defword ':', colon
        dq word_                  ; get the name of the word
        dq create                 ; create dictionary header
        dq lit, docol, comma      ; append docol
        dq latest, fetch, hidden  ; make the word hidden for now
        dq rbrac                  ; go to compile mode
        dq exit

    defword ';', semicolon, FLAG_IMMEDIATE
        dq lit, exit, comma       ; append exit
        dq latest, fetch, hidden  ; unhide the word
        dq lbrac                  ; go back to immediate
        dq exit

    defcode 'immediate', immediate, FLAG_IMMEDIATE
        mov rdi, var_latest              ; get latest word
        add rdi, 9                       ; get flags
        xor qword [rdi], FLAG_IMMEDIATE  ; toggle immediate
    next

    defcode 'hidden', hidden
        pop rdi                          ; get a word
        add rdi, 9                       ; get flags
        xor qword [rdi], FLAG_HIDDEN     ; toggle hidden
    next

    defword 'hide', hide
        dq word_    ; get the word
        dq find     ; look it up
        dq hidden   ; set hidden
        dq exit

    defcode "'", tick
        lodsq      ; get address of next word (skipping its execution)
        push rax   ; push it onto the stack
    next

    defcode 'branch', branch  ; compiled with an offset immediately following
        add rsi, [rsi]        ; just add offset to the ip
    next

    defcode '0branch', zbranch   ; compiled as branch, with offset following
        pop rax                  ; check top of stack
        test rax, rax
        jz code_branch           ; if zero, do branch
        lodsq                    ; otherwise skip over offset
    next

    defcode 'litstring', litstring
        lodsq            ; get length of string
        push rsi         ; push address
        push rax         ; push, something
        add rsi, rax     ; skip past string
        add rsi, 7       ; rounded to nearest 8 bytes
        and rsi, ~7
    next

    ; just print a string
    defcode 'tell', tell
        push rsi
        mov rax, syscall_write ; write(fd, buf, count)
        mov rdi, 1             ; fd
        pop rsi                ; buf
        pop rdx                ; count
        syscall
        pop rsi
    next

    defword 'quit', quit
        dq rz, rspstore  ; r0 rsp! - clear return stack
        dq interpret     ; interpret the next word
        dq branch, -16   ; loop forever

    defcode 'interpret', interpret
        call _word                        ; get the next word
        xor rax, rax
        mov [interpret_is_lit], rax
        call _find                        ; look it up
        test rax, rax
        jz .is_lit                        ; did we find it?
        mov rdi, rax                      ; yes, get flags
        mov al, [rdi + 8]
        push ax                           ; hold onto it
        call _tocfa                       ; get codeword
        pop ax
        and al, FLAG_IMMEDIATE            ; if immediate
        mov rax, rdi
        jnz .execute                      ; execute right now
        jmp .check_state                  ; or check state first
.is_lit:
        inc qword [interpret_is_lit]
        call _number                      ; try to parse number
        test rcx, rcx
        jnz .parse_error
        mov rbx, rax
        mov rax, lit
.check_state:
        mov rdx, [var_state]              ; check if we are compiling or executing
        test rdx, rdx
        jz .execute
        call _comma                       ; we are compiling, append the word
        mov rcx, [interpret_is_lit]
        test rcx, rcx                     ; did we compile a literal?
        jz .done
        mov rax, rbx                      ; if so, we appended lit, also append the number
        call _comma
.done:
    next
.execute:
        mov rcx, [interpret_is_lit]
        test rcx, rcx                     ; are we executing a literal?
        jnz .exec_lit
        jmp [rax]                         ; no, rax is codeword!
.exec_lit:
        push rbx                          ; yes, just push
    next
.parse_error:
        set_error bad_number_literal
        call error_exit
    next
    section .data
    align 8
interpret_is_lit:
    dq 0

    defcode 'char', char
        call _word      ; get next word (rcx=len, rdi=char*)
        xor rax, rax
        mov al, [rdi]   ; get first char
        push rax        ; push it
    next

    defcode 'execute', execute
        pop rax
        jmp [rax]

    defcode 'syscall3', syscall3
        pushrsp rsi     ; gotta put it somewhere...
        pop rax
        pop rdi
        pop rdi
        pop rdx
        syscall
        push rax
        poprsp rsi
    next

    defcode 'syscall2', syscall2
        pushrsp rsi
        pop rax
        pop rdi
        pop rdi
        syscall
        push rax
        poprsp rsi
    next

    defcode 'syscall1', syscall1
        pushrsp rsi
        pop rax
        pop rdi
        syscall
        push rax
        poprsp rsi
    next

    defcode 'syscall0', syscall0
        pushrsp rsi
        pop rax
        syscall
        push rax
        poprsp rsi
    next

    section .bss
return_stack: resb 8192
return_stack_top: resb 1
buffer: resb 4096

; that's it for the assembly!

;; dictionary entry:
;;
;; 8 bytes - link to previous entry
;; 1 byte - flags
;; 1 byte - name length
;; n bytes - name and padding
;; 8 bytes - the codeword
;; ? bytes - the code
;; 8 bytes - next, or addr of exit
