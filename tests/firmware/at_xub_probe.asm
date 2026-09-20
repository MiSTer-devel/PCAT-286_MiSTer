; Simulation setup only: execute XUB with the real Sergey IVT setup,
; IRQ0/INT13/INT15 handlers. Video and keyboard services are minimal stubs.
bits 16
org 0
%ifndef PIT_DIVISOR
%define PIT_DIVISOR 0
%endif
    cli
    xor ax,ax
    mov ss,ax
    mov sp,0x7000
    mov ds,ax
    mov es,ax
    cld
    mov di,0
    mov cx,0x280
    rep stosw
    ; Actual POST IVT setup, including the patch CALL at E1AB. The bench
    ; places a private RET at E1B0 to return before the rest of POST.
    call 0xe198
    xor ax,ax
    mov ds,ax
    mov word [0x40],video_stub
    mov word [0x58],keyboard_stub
    mov word [0x60],finished
    mov word [0x413],640
    mov byte [0x449],3
    mov word [0x44a],80
    mov word [0x44c],0x1000
    mov word [0x463],0x3d4
    mov byte [0x484],24
    mov word [0x410],0x41
    mov al,0x11
    out 0x20,al
    out 0xa0,al
    mov al,8
    out 0x21,al
    mov al,0x70
    out 0xa1,al
    mov al,4
    out 0x21,al
    mov al,2
    out 0xa1,al
    mov al,1
    out 0x21,al
    out 0xa1,al
    mov al,0xff
    out 0xa1,al
    mov al,0xb8 ; IRQ0 + IRQ1 + IRQ2 + IRQ6, matching the AT-PIC BIOS
    out 0x21,al
    mov al,0x36
    out 0x43,al
    mov ax,PIT_DIVISOR ; nonzero only in accelerated simulation runs
    out 0x40,al
    mov al,ah
    out 0x40,al
    sti
    call 0xc800:3
    int 0x19
finished:
    mov al,0x99
    out 0x80,al
    cli
    hlt
iret_stub:
    iret
keyboard_stub:
    push bp
    mov bp,sp
    or word [ss:bp+6],0x40 ; ZF: no key
    pop bp
    iret
video_stub:
    cmp ah,3
    je .get_cursor
    cmp ah,2
    je .set_cursor
    cmp ah,0x0e
    jne iret_stub
    push ds
    push ax
    xor ax,ax
    mov ds,ax
    pop ax
    cmp al,10
    jne .not_lf
    inc byte [0x451]
.not_lf:
    cmp al,13
    jne .done
    mov byte [0x450],0
.done:
    pop ds
    iret
.get_cursor:
    push ds
    push ax
    xor ax,ax
    mov ds,ax
    mov dx,[0x450]
    mov cx,0x0607
    pop ax
    pop ds
    iret
.set_cursor:
    push ds
    push ax
    xor ax,ax
    mov ds,ax
    mov [0x450],dx
    pop ax
    pop ds
    iret
