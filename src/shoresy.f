\ vim: ft=forth et sw=4 ts=4

: / /mod swap drop ;

: mod /mod drop ;

: '\n' 10 ;
: bl 32 ;
: cr '\n' emit ;
: space bl emit ;

: negate 0 swap - ;

: true [ 16 base ! ] FFFFFFFFFFFFFFFF [ 10 base ! ] ;
: false 0 ;
: not 0= ;

: literal immediate
    ' lit , \ compile a lit
    ,       \ compile the literal from the stack
    ;

\ you may recall [ and ] which switch into and out of immediate mode
\ whatever's inside will be executed at compile time

: ':' [ char : ] literal ;
: ';' [ char ; ] literal ;
: '(' [ char ( ] literal ;
: ')' [ char ) ] literal ;
: '"' [ char " ] literal ;
: 'A' [ char A ] literal ;
: '0' [ char 0 ] literal ;
: '-' [ char - ] literal ;
: '.' [ char . ] literal ; \ syntax highlighting xd "

\ '[compile] X' compiles X, even if X is immediate
: [compile] immediate
    word \ get the word
    find \ find it
    >cfa \ get the codeword
    ,    \ compile it
;

\ insert a recursive call to a word currently being compiled
\ a word is hidden while defining it, so it wouldn't be found by find
: recurse immediate
    latest @ \ thankfully latest points at it
    >cfa ,   \ get and compile its codeword
;

\ these don't work in immediate mode unfortunately :/

\ ( -- start-addr )
: if immediate
    ' 0branch , \ compile a 0branch
    here @      \ push the location of that 0branch
    0 ,         \ compile a dummy offset for now
;

\ ( start-addr -- )
: then immediate
    dup
    here @ swap -   \ now figure out how far back we have to go
    swap !          \ and write it at the dummy offset
;

: else immediate
    ' branch ,      \ unconditional branch over the false part
    here @          \ save current location
    0 ,             \ dummy offset
    swap            \ swap out for the if offset
    dup
    here @ swap -
    swap !          \ write the current location at the if dummy
;

: begin immediate
    here @
;

: until immediate
    ' 0branch ,
    here @ -
    ,
;

: again immediate
    ' branch ,
    here @ -
    ,
;

: while immediate
    ' 0branch ,
    here @
    0 ,
;

: repeat immediate
    ' branch ,
    swap
    here @ - ,
    dup
    here @ swap -
    swap !
;

: unless immediate
    ' not ,
    [compile] if
;

: ( immediate
    1
    begin
        key
        dup '(' = if
            drop 1+
        else
            ')' = if
                1-
            then
        then
    dup 0= until
    drop
;

breakpoint
: nip ( x y -- y ) swap drop ;

\ : tuck ( x y -- y x y ) swap over ;
\ : pick ( xu ... x1 x0 u -- xu ... x1 x0 xu )
\     1+
\     4 *
\     dsp@ +
\     @
\ ;

\ : spaces ( n -- )
\     begin
\         dup 0>
\     while
\         space
\         1-
\     repeat
\     drop
\ ;
\ 
\ : decimal ( -- ) 10 base ! ;
\ : hex ( -- ) 16 base ! ;
\ 
\ : u. ( u -- )
\     base @ /mod
\     ?dup if
\         recurse
\     then
\ 
\     dup 10 < if
\         '0'
\     else
\         10 - 'a'
\     then
\ 
\     + emit
\ ;
\ 
\ : .s ( -- )
\     dsp@
\     begin
\         dup s0 @ <
\     while
\         dup @ u.
\         space
\         8 +
\     repeat
\     drop
\ ;
\ 
\ : uwidth ( u -- width )
\     base @ /        ( rem quot )
\     ?dup if         ( if quotient != 0 )
\         recurse 1+  ( return 1 + uwidth u )
\     else
\         1           ( return 1 )
\     then
\ ;
\ 
\ : u.r ( u width -- )
\     swap      ( width u )
\     dup       ( width u u )
\     uwidth    ( width u uwidth )
\     rot       ( u width width )
\     swap -    ( u width-uwidth )
\     spaces
\     u.
\ ;
\ 
\ : .r ( n width -- )
\     swap                ( width n )
\     dup 0< if
\         negate          ( width -u neg? )
\         1
\         swap            ( width neg? -u )
\         rot             ( neg? u width )
\         1-              ( neg? u width-1 )
\     else
\         0
\         swap
\         rot             ( neg? u width )
\     then
\     swap                ( neg? width u )
\     dup                 ( neg? width u u )
\     uwidth              ( neg? width u uwidth )
\     rot                 ( neg? u uwidth width )
\     swap -              ( neg? u width-uwidth )
\     spaces              ( neg? u )
\     swap                ( u neg? )
\     if '-' emit then    ( u )
\     u.
\ ;
\ 
\ : . 0 .r space ;
\ : u. u. space ;
\ : ? ( addr -- ) @ . ;
\ 
\ : id.
\     8+ 1+
\     dup c@
\     begin
\         dup 0>
\     while
\         swap 1+
\         dup c@
\         emit
\         swap 1-
\     repeat
\     2drop
\ ;
\ 
\ : ?hidden 8 + c@ flag_hidden and ;
\ 
\ : words
\     latest @
\     begin
\         ?dup
\     while
\         dup ?hidden not if
\             dup id.
\             space
\         then
\         @
\     repeat
\     cr
\ ;
