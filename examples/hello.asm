; A minimal Tunguska program. GPL-2.0-or-later.
; Assemble with: build/tg_assembler -o build/hello.ternobj examples/hello.asm

@ORG %DDBDDD
@DT 'HELLO, TERNARY!', 0

@ORG %000000
    SEI                 ; This simple demo does not need interrupts.
    LDA #1              ; Text mode, refresh requested.
    STA %DDDDDB
idle:
    JMP idle
