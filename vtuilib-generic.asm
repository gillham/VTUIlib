!cpu w65c02
; Program counter is set to 0 to make it easier to calculate the addresses
; in the jumptable as all that needs to be done is add the actual offset.
*=$0000

; ******************************* Jumptable *******************************
	bra	initialize	; No inputs
	jmp	vtui_screen_set	; .A = Screenmode ($00, $02 or $FF)
	jmp	vtui_set_bank	; .C = bank number (0 or 1)
	jmp	vtui_set_stride	; .A = Stride value
	jmp	vtui_set_decr	; .C (1 = decrement, 0 = increment)
	jmp	vtui_gotoxy	; .A = x coordinate, .Y = y coordinate
	jmp	vtui_plot_char	; .A = character, .X = bg-/fg-color
	jmp	vtui_scan_char	; like plot_char
	jmp	vtui_hline	; .A = Character, .Y = length, .X = color
	jmp	vtui_vline	; .A = Character, .Y = height, .X = color
	jmp	vtui_print_str	; r0 = pointer to string, .X = color
	jmp	vtui_fill_box	; .A=Char,r1l=width,r2l=height,.X=color
	jmp	vtui_pet2scr	; .A = character to convert to screencode
	jmp	vtui_scr2pet	; .A = character to convert to petscii
	jmp	vtui_border	; .A=border,r1l=width,r2l=height,.X=color
	jmp	vtui_save_rect	; .C=vrambank,.A=destram,r0=destaddr,r1l=width,r2l=height
	jmp	vtui_rest_rect	; .C=vrambank,.A=srcram,r0=srcaddr,r1l=width,r2l=height
	jmp	$0000		; Show that there are no more jumps

; ******************************* Constants *******************************
VERA_ADDR_L		= $9F20
VERA_ADDR_M		= $9F21
VERA_ADDR_H		= $9F22
VERA_DATA0		= $9F23
VERA_DATA1		= $9F24
VERA_CTRL		= $9F25

r0	= $02
r0l	= r0
r0h	= r0+1
r1	= $04
r1l	= r1
r1h	= r1+1
r2	= $06
r2l	= r2
r2h	= r2+1
r3	= $08
r3l	= r3
r3h	= r3+1
r4	= $0A
r4l	= r4
r4h	= r4+1
r5	= $0C
r5l	= r5
r5h	= r5+1
r6	= $0E
r6l	= r6
r6h	= r6+1

; ******************************* Functions *******************************

; *****************************************************************************
; Initialize the jumptable with correct addresses calculated from the address
; where this code is loaded.
; *****************************************************************************
; USES:		.A, .X & .Y
;		r0, r1, r2 & r3 (ZP addresses $02-$09)
; *****************************************************************************
initialize:
	; Write code to ZP to figure out where the library is loaded.
	; This is done by jsr'ing to the code in ZP which in turn reads the
	; return address from the stack.
	lda	#$BA		; TSX
	sta	r0
	lda	#$BD		; LDA absolute,x
	sta	r0+1
	lda	#$01		; $0101
	sta	r0+2
	sta	r0+3
	sta	r0+6
	lda	#$BC		; LDY absolute,x
	sta	r0+4
	lda	#$02		; $0102
	sta	r0+5
	lda	#$60		; RTS
	sta	r0+7
	; Jump to the code in ZP that was just copied there by the code above.
	; This is to get the return address stored on stack
	jsr	r0		; Get current PC value
	sec
	sbc	#*-2		; Calculate start of our program
	sta	r0		; And store it in r0
	tya
	sbc	#$00
	sta	r0+1
	lda	r0		; Calculate location of first address in
	clc			; jump table
	adc	#$03
	sta	r1
	lda	r0+1
	adc	#$00
	sta	r1+1
	ldy	#$01		; .Y used for indexing high byte of pointers
	lda	(r1),y
	beq	@loop		; If high byte of pointer is 0, we can continue
	rts			; Otherwise initialization has already been run
@loop:	clc
	lda	(r1)		; Low part of jumptable address
	beq	@mightend	; If it is zero, we might have reaced the end of jumptable
	adc	r0l		; Add start address of our program to the jumptable address
	sta	(r1)
	lda	(r1),y
	adc	r0h
	sta	(r1),y
	bra	@prepnext
@mightend:
	adc	r0l		; Add start address of our program to the jumptable address
	sta	(r1)
	lda	(r1),y		; High part of jumptable address
	beq	@end		; If it is zero, we have reaced end of jumptable
	adc	r0h
	sta	(r1),y
@prepnext:			; Prepare r1 pointer for next entry in jumptable
	clc			; (add 3 to current value)
	lda	r1l
	adc	#$03
	sta	r1l
	lda	r1h
	adc	#$00
	sta	r1h
	bra	@loop
@end:	rts

; *****************************************************************************
; Use KERNAL API to set screen to 80x60 or 40x30 or swap between them.
; *****************************************************************************
; INPUT:		.A = Screenmode ($00, $02 or $FF)
; USES:			.A, .X & ,Y
; RETURNS:		.C = 1 in case of error.
; *****************************************************************************
!macro VTUI_SCREEN_SET {
	beq	.doset		; If 0, we can set mode
	cmp	#$02
	beq	.doset		; If 2, we can set mode
	cmp	#$FF
	bne	.end		; If $FF, we can set mode
.doset:	jsr	$FF5F
.end:
}
vtui_screen_set:
	+VTUI_SCREEN_SET
	rts

; *****************************************************************************
; Set VERA bank (High memory) without touching anything else
; *****************************************************************************
; INPUTS:	.C = Bank number, 0 or 1
; USES:		.A
; *****************************************************************************
!macro VTUI_SET_BANK {
	lda	VERA_ADDR_H
	bcc	.setzero
	; Bank = 1
	ora	#$01
	bra	.end
.setzero:
	; Bank = 0
	and	#$FE
.end:	sta	VERA_ADDR_H
}
vtui_set_bank:
	+VTUI_SET_BANK
	rts

; *****************************************************************************
; Set the stride without changing other values in VERA_ADDR_H
; *****************************************************************************
; INPUT:		.A = Stride value
; USES:			r0l
; *****************************************************************************
!macro VTUI_SET_STRIDE {
	asl			; Stride is stored in upper nibble
	asl
	asl
	asl
	sta	r0l
	lda	VERA_ADDR_H	; Set stride value to 0 in VERA_ADDR_H
	and	#$0F
	ora	r0l
	sta	VERA_ADDR_H
}
vtui_set_stride:
	+VTUI_SET_STRIDE
	rts

; *****************************************************************************
; Set the decrement value without changing other values in VERA_ADDR_H
; *****************************************************************************
; INPUT:		.C (1 = decrement, 0 = increment)
; USES:			.A
; *****************************************************************************
!macro VTUI_SET_DECR {
	lda	VERA_ADDR_H
	bcc	.setnul
	ora	#%00001000
	bra	.end
.setnul:
	and	#%11110111
.end:	sta	VERA_ADDR_H
}
vtui_set_decr:
	+VTUI_SET_DECR
	rts

; *****************************************************************************
; Write character and color to current VERA address
; Function assumes that stride is set to 1 and decrement set to 0
; *****************************************************************************
; INPUTS:	.A = character
;		.X = bg-/fg-color
; *****************************************************************************
!macro VTUI_PLOT_CHAR {
	sta	VERA_DATA0
	stx	VERA_DATA0
}
vtui_plot_char:
	+VTUI_PLOT_CHAR
	rts

; *****************************************************************************
; Read character and color from current VERA address
; Function assumes that stride is set to 1 and decrement set to 0
; *****************************************************************************
; OUTPUS:	.A = character
;		.X = bg-/fg-color
; *****************************************************************************
!macro VTUI_SCAN_CHAR {
	lda	VERA_DATA0
	ldx	VERA_DATA0
}
vtui_scan_char:
	+VTUI_SCAN_CHAR
	rts

; *****************************************************************************
; Create a horizontal line going from left to right.
; *****************************************************************************
; INPUTS:	.A	= Character to use for drawing the line
;		.Y	= Length of the line
;		.X	= bg- & fg-color
; *****************************************************************************
!macro VTUI_HLINE {
.loop:	+VTUI_PLOT_CHAR
	dey
	bne	.loop
}
vtui_hline:
	+VTUI_HLINE
	rts

; *****************************************************************************
; Create a vertical line going from top to bottom.
; *****************************************************************************
; INPUTS:	.A	= Character to use for drawing the line
;		.Y	= Height of the line
;		.X	= bg- & fg-color
; *****************************************************************************
!macro VTUI_VLINE {
.loop:	+VTUI_PLOT_CHAR
	dec	VERA_ADDR_L	; Return to original X coordinate
	dec	VERA_ADDR_L
	inc	VERA_ADDR_M	; Increment Y coordinate
	dey
	bne	.loop
}
vtui_vline:
	+VTUI_VLINE
	rts

; *****************************************************************************
; Set VERA address to point to specific point on screen
; *****************************************************************************
; INPUTS:	.A = x coordinate
;		.Y = y coordinate
; *****************************************************************************
!macro VTUI_GOTOXY {
	sty	VERA_ADDR_M	; Set y coordinate
	asl			; Multiply x coord with 2 for correct coordinate
	sta	VERA_ADDR_L	; Set x coordinate
}
vtui_gotoxy:
	+VTUI_GOTOXY
	rts

; *****************************************************************************
; Convert PETSCII codes between $20 and $5F to screencodes.
; *****************************************************************************
; INPUTS:	.A = character to convert
; OUTPUS:	.A = converted character or $56 if invalid input
; *****************************************************************************
!macro VTUI_PET2SCR {
	cmp	#$20
	bcc	.nonprintable	; .A < $20
	cmp	#$40
	bcc	.end		; .A < $40 means screen code is the same
	; .A >= $40 - might be letter
	cmp	#$60
	bcs	.nonprintable	; .A < $60 so it is a letter, subtract ($3F+1)
	sbc	#$3F		; to convert to screencode
	bra	.end
.nonprintable:
	lda	#$56
.end:
}
vtui_pet2scr:
	+VTUI_PET2SCR
	rts

; *****************************************************************************
; Convert screencodes between $00 and $3F to PETSCII.
; *****************************************************************************
; INPUTS:	.A = character to convert
; OUTPUS:	.A = converted character or $76 if invalid input
; *****************************************************************************
!macro VTUI_SCR2PET {
	cmp	#$40
	bcs	.nonprintable	; .A >= $40
	cmp	#$20
	bcs	.end		; .A >=$20 & < $40 means petscii is the same
	; .A < $20 and is a letter
	adc	#$40
	bra	.end
.nonprintable:
	lda	#$76
.end:
}
vtui_scr2pet:
	+VTUI_SCR2PET
	rts

; *****************************************************************************
; Print a 0 terminated string PETSCII string
; *****************************************************************************
; INPUTS	.A = Convert string (0 = no converstion, $80 = convert)
;		r0 = pointer to string
;		.X  = bg-/fg color
; USES:		.A, .Y & r2
; *****************************************************************************
!macro VTUI_PRINT_STR {
	sta	r2l
	ldy	#0
.loop:	lda	(r0),y		; Load character
	beq	.end		; If 0, we are done
	bit	r2l
	bpl	+
	+VTUI_PET2SCR
+	+VTUI_PLOT_CHAR
	ldy	r2h
	iny
	bne	.loop		; Get next character
.end:
}
vtui_print_str:
	+VTUI_PRINT_STR
	rts

; *****************************************************************************
; Create a filled box drawn from top left to bottom right
; *****************************************************************************
; INPUTS:	.A	= Character to use for drawing the line
;		r1l	= Width of box
;		r2l	= Height of box
;		.X	= bg- & fg-color
; *****************************************************************************
!macro VTUI_FILL_BOX {
	ldy	VERA_ADDR_L
	sty	r0l
.vloop:	ldy	r0l		; Load x coordinate
	sty	VERA_ADDR_L	; Set x coordinate
	ldy	r1l
.hloop:	+VTUI_PLOT_CHAR
	dey
	bne	.hloop
	inc	VERA_ADDR_M
	dec	r2l
	bne	.vloop
}
vtui_fill_box:
	+VTUI_FILL_BOX
	rts

; *****************************************************************************
; Create a box with a specific border
; *****************************************************************************
; INPUTS:	.A	= Border mode (0-6) any other will default to mode 0
;		r1l	= width
;		r2l	= height
;		.X	= bg-/fg-color
; USES		.Y, r0l & r0h
; *****************************************************************************
!macro VTUI_BORDER {
	; Define local variable names for ZP variables
	; Makes the source a bit more readable
.top_right=r3l
.top_left =r3h
.bot_right=r4l
.bot_left =r4h
.top	  =r5l
.bottom   =r5h
.left	  =r6l
.right	  =r6h

	; Set the border drawing characters according to the border mode in .A
.mode1: cmp	#1
	bne	.mode2
	lda	#$66
	bra	.def
.mode2: cmp	#2
	bne	.mode3
	lda	#$6E
	sta	.top_right
	lda	#$70
	sta	.top_left
	lda	#$7D
	sta	.bot_right
	lda	#$6D
	sta	.bot_left
.clines:
	lda	#$40		; centered lines
	sta	.top
	sta	.bottom
	lda	#$42
	sta	.left
	sta	.right
	bra	.dodraw
.mode3:	cmp	#3
	bne	.mode4
	lda	#$49
	sta	.top_right
	lda	#$55
	sta	.top_left
	lda	#$4B
	sta	.bot_right
	lda	#$4A
	sta	.bot_left
	bra	.clines
.mode4:	cmp	#4
	bne	.mode5
	lda	#$50
	sta	.top_right
	lda	#$4F
	sta	.top_left
	lda	#$7A
	sta	.bot_right
	lda	#$4C
	sta	.bot_left
.elines:
	lda	#$77		; lines on edges
	sta	.top
	lda	#$6F
	sta	.bottom
	lda	#$74
	sta	.left
	lda	#$6A
	sta	.right
	bra	.dodraw
.mode5:	cmp	#5
	bne	.mode6
	lda	#$5F
	sta	.top_right
	lda	#$69
	sta	.top_left
	lda	#$E9
	sta	.bot_right
	lda	#$DF
	sta	.bot_left
	bra	.elines
.mode6:	cmp	#6
	beq	.dodraw		; Assume border chars are already set
.default:
	lda	#$20
.def:	sta	.top_right
	sta	.top_left
	sta	.bot_right
	sta	.bot_left
	sta	.top
	sta	.bottom
	sta	.left
	sta	.right
.dodraw:
	; Save initial position
	lda	VERA_ADDR_L
	sta	r0l
	lda	VERA_ADDR_M
	sta	r0h
	ldy	r1l		; width
	dey
	lda	.top_left
	+VTUI_PLOT_CHAR		; Top left corner
	dey
	lda	.top
	+VTUI_HLINE		; Top line
	lda	.top_right
	+VTUI_PLOT_CHAR		; Top right corner
	dec	VERA_ADDR_L
	dec	VERA_ADDR_L
	inc	VERA_ADDR_M
	ldy	r2l		;height
	dey
	dey
	lda	.right
	+VTUI_VLINE		; Right line
	; Restore initial VERA address
	lda	r0l
	sta	VERA_ADDR_L
	lda	r0h
	inc
	sta	VERA_ADDR_M
	ldy	r2l		;height
	dey
	lda	.left
	+VTUI_VLINE		; Left line
	dec	VERA_ADDR_M
	lda	.bot_left
	+VTUI_PLOT_CHAR		; Bottom left corner
	ldy	r1l
	dey
	lda	.bottom
	+VTUI_HLINE		; Bottom line
	dec	VERA_ADDR_L
	dec	VERA_ADDR_L
	lda	.bot_right
	+VTUI_PLOT_CHAR		; Bottom right corner
}
vtui_border:
	+VTUI_BORDER
	rts

; *****************************************************************************
; Increment 16bit value
; *****************************************************************************
; INPUT:	.addr = low byte of the 16bit value to increment
; *****************************************************************************
!macro VTUI_INC16 .addr {
	inc	.addr
	bne	.end
	inc	.addr+1
.end:
}

; *****************************************************************************
; Copy contents of screen from current position to other memory area in
; either system RAM or VRAM
; *****************************************************************************
; INPUTS:	.C	= VRAM Bank (0 or 1) if .A>0
;		.A	= Destination RAM (0=system RAM, 1=VRAM)
;		r0 	= Destination address
;		r1l	= width
;		r2l	= height
; *****************************************************************************
!macro VTUI_SAVE_RECT {
	ldy	VERA_ADDR_L	; Save X coordinate for later
	cmp	#0
	beq	.sysram
	; VRAM
	ldx	#1		; Set ADDRsel to 1
	stx	VERA_CTRL
	+VTUI_SET_BANK		; Set bank according to .C
	lda	#1
	+VTUI_SET_STRIDE	; Set stride to 1
	lda	r0l		; Set destination address
	sta	VERA_ADDR_L
	lda	r0h
	sta	VERA_ADDR_M
	stz	VERA_CTRL	; Set ADDRsel back to 0
	ldx	r1l		; Load width
.vloop:	lda	VERA_DATA0	; Copy Character
	sta	VERA_DATA1
	lda	VERA_DATA0	; Copy Color Code
	sta	VERA_DATA1
	dex
	bne	.vloop
	ldx	r1l		; Restore width
	sty	VERA_ADDR_L	; Restore X coordinate
	inc	VERA_ADDR_M	; Increment Y coordinate
	dec	r2l
	bne	.vloop
	bra	.end
.sysram:
	; System RAM
	ldx	r1l		; Load width
.sloop:	lda	VERA_DATA0	; Copy Character
	sta	(r0)
	+VTUI_INC16 r0		; Increment destination address
	lda	VERA_DATA0	; Copy Color Code
	sta	(r0)
	+VTUI_INC16 r0		; Increment destination address
	dex
	bne	.sloop
	ldx	r1l		; Restore width
	sty	VERA_ADDR_L	; Restore X coordinate
	inc	VERA_ADDR_M
	dec	r2l
	bne	.sloop
.end:
}
vtui_save_rect:
	+VTUI_SAVE_RECT
	rts

; *****************************************************************************
; Restore contents of screen from other memory area in either system RAM
; or VRAM starting at current position
; *****************************************************************************
; INPUTS:	.C	= VRAM Bank (0 or 1) if .A>0
;		.A	= Source RAM (0=system RAM, 1=VRAM)
;		r0 	= Source address
;		r1l	= width
;		r2l	= height
; *****************************************************************************
!macro VTUI_REST_RECT {
	ldy	VERA_ADDR_L	; Save X coordinate for later
	cmp	#0
	beq	.sysram
	; VRAM
	ldx	#1		; Set ADDRsel to 1
	stx	VERA_CTRL
	+VTUI_SET_BANK		; Set bank according to .C
	lda	#1
	+VTUI_SET_STRIDE
	lda	r0l		; Set destination address
	sta	VERA_ADDR_L
	lda	r0h
	sta	VERA_ADDR_M
	stz	VERA_CTRL	; Set ADDRsel back to 0
	ldx	r1l		; Load width
.vloop:	lda	VERA_DATA1	; Copy Character
	sta	VERA_DATA0
	lda	VERA_DATA1	; Copy Color Code
	sta	VERA_DATA0
	dex
	bne	.vloop
	ldx	r1l		; Restore width
	sty	VERA_ADDR_L	; Restore X coordinate
	inc	VERA_ADDR_M	; Increment Y coordinate
	dec	r2l
	bne	.vloop
	bra	.end
.sysram:
	; System RAM
	ldx	r1l		; Load width
.sloop:	lda	(r0)		; Copy Character
	sta	VERA_DATA0
	+VTUI_INC16	r0	; Increment destination address
	lda	(r0)		; Copy Color Code
	sta	VERA_DATA0
	+VTUI_INC16	r0	; Increment destination address
	dex
	bne	.sloop
	ldx	r1l		; Restore width
	sty	VERA_ADDR_L	; Restore X coordinate
	inc	VERA_ADDR_M
	dec	r2l
	bne	.sloop
.end:
}
vtui_rest_rect:
	+VTUI_REST_RECT
	rts
