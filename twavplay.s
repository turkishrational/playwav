; ****************************************************************************
; twavplay.s (for TRDOS 386)
; ----------------------------------------------------------------------------
; TWAVPLAY.PRG ! VIA VT8237R WAV PLAYER & VGA DEMO program by Erdogan TAN
;
; 23/08/2020
;
; [ Last Modification: 24/08/2020 ] 
;
; Derived from 'tmodply3.s' and 'wavplay2.s' source code by Erdogan Tan
; 
; Assembler: NASM 2.14
; ----------------------------------------------------------------------------
;	   nasm  twavplay.s -l twavplay.txt -o TWAVPLAY.PRG	
; ****************************************************************************

; 01/03/2017
; 16/10/2016
; 29/04/2016
; TRDOS 386 system calls (temporary list!)
_ver 	equ 0
_exit 	equ 1
_fork 	equ 2
_read 	equ 3
_write	equ 4
_open	equ 5
_close 	equ 6
_wait 	equ 7
_creat 	equ 8
_link 	equ 9
_unlink	equ 10
_exec	equ 11
_chdir	equ 12
_time 	equ 13
_mkdir 	equ 14
_chmod	equ 15
_chown	equ 16
_break	equ 17
_stat	equ 18
_seek	equ 19
_tell 	equ 20
_mount	equ 21
_umount	equ 22
_setuid	equ 23
_getuid	equ 24
_stime	equ 25
_quit	equ 26	
_intr	equ 27
_fstat	equ 28
_emt 	equ 29
_mdate 	equ 30
_video 	equ 31
_audio	equ 32
_timer	equ 33
_sleep	equ 34
_msg    equ 35
_geterr	equ 36
_fpsave	equ 37
_pri	equ 38
_rele	equ 39
_fff	equ 40
_fnf	equ 41
_alloc	equ 42
_dalloc equ 43
_calbac equ 44		

%macro sys 1-4
    ; 29/04/2016 - TRDOS 386 (TRDOS v2.0)	
    ; 03/09/2015	
    ; 13/04/2015
    ; Retro UNIX 386 v1 system call.	
    %if %0 >= 2   
        mov ebx, %2
        %if %0 >= 3    
            mov ecx, %3
            %if %0 = 4
               mov edx, %4   
            %endif
        %endif
    %endif
    mov eax, %1
    ;int 30h
    int 40h ; TRDOS 386 (TRDOS v2.0)	   
%endmacro

; TRDOS 386 (and Retro UNIX 386 v1) system call format:
; sys systemcall (eax) <arg1 (ebx)>, <arg2 (ecx)>, <arg3 (edx)>

; 19/06/2017
BUFFERSIZE equ 32768
; 23/08/2020
ENDOFFILE equ 1	; flag for knowing end of file

; ----------------------------------------------------------------------------
; Tiny MOD Player v0.1b by Carlos Hasan.
;	July 14th, 1993.

;=============================================================================
;  
;=============================================================================

[BITS 32]
[org 0]

Start:
	; clear bss
	mov	ecx, EOF
	mov	edi, bss_start
	sub	ecx, edi
	shr	ecx, 1
	xor	eax, eax
	rep	stosw

	; Detect (& Enable) VT8233 Audio Device
	call    DetectVT8233
	jnc     short GetFileName

_dev_not_ready:
; couldn't find the audio device!
	sys	_msg, noDevMsg, 255, 0Fh
        jmp     Exit

GetFileName:
	mov	esi, esp
	lodsd
	cmp	eax, 2 ; two arguments 
		; (program file name & mod file name)
	jb	pmsg_usage ; nothing to do

	lodsd ; program file name address 
	lodsd ; wav file name address (file to be read)
	mov	esi, eax
	mov	edi, wav_file_name
ScanName:       
	lodsb
	test	al, al
	je	pmsg_usage
	cmp	al, 20h
	je	short ScanName	; scan start of name.
	stosb
	mov	ah, 0FFh
a_0:	
	inc	ah
a_1:
	lodsb
	stosb
	cmp	al, '.'
	je	short a_0	
	and	al, al
	jnz	short a_1

	or	ah, ah		 ; if period NOT found,
	jnz	short PrintPMesg ; then add a .MOD extension.
SetExt:
	dec	edi
	mov	dword [edi], '.WAV'
	mov	byte [edi+4], 0
PrintPMesg: 
	; 23/08/2020
	mov	byte [credits_zero], 0
     
	; Prints the Credits Text.
	sys	_msg, Credits, 255, 0Fh
_1:
	; 19/06/2017
	; Allocate Audio Buffer (for user)
	sys	_audio, 0200h, BUFFERSIZE, audio_buffer
	jc	error_exit
_2:
	; 23/08/2020
	; Initialize Audio Device (bl = 1 -> Interrupt method)
	;sys	_audio, 0301h, 0, audio_int_handler 
	;jc	error_exit
	
	; 24/08/2020

	; 20/10/2017
	; Initialize Audio Device (bl = 0 -> SRB method)
	sys	_audio, 0300h, 1, srb
	jc	error_exit

	; 23/08/2020

; open the wav file
        ; open existing file
        call    openFile ; no error? ok.
        jnc     short _3

; file not found!
	sys	_msg, noFileErrMsg, 255, 0Fh
        jmp	Exit

_3:
       	call    getSampleRate	; read the sample rate
                             	; pass it onto codec.
	jc	Exit

	mov	[sample_rate], ax
	mov	[stmo], cl
	mov	[bps], dl

	; 10/06/2017
	sys	_audio, 0E00h ; get audio controller info
	jc	error_exit

	;cmp	ah, 3 ; VT 8233? (VIA AC'97 Audio Controller)
	;jne	_dev_not_ready		

	; EAX = IRQ Number in AL
	;	Audio Device Number in AH 
	; EBX = DEV/VENDOR ID
	;       (DDDDDDDDDDDDDDDDVVVVVVVVVVVVVVVV)
	; ECX = BUS/DEV/FN 
	;       (00000000BBBBBBBBDDDDDFFF00000000)
	; EDX = Base IO Addr (DX) for SB16 & VT8233
	; EDX = NABMBAR/NAMBAR (for AC97)
	;      (Low word, DX = NAMBAR address)

	mov	[ac97_int_ln_reg], al
	mov	[dev_vendor], ebx
	mov	[bus_dev_fn], ecx
	mov	[ac97_io_base], dx	
  
	call	write_audio_dev_info

	; 24/08/2020
	call	write_wav_file_info 

	; 23/08/2020
PlayNow: 
	; 27/10/2017
	mov	cx, 256
	xor	ebx, ebx
	mov	edi, RowOfs
MakeOfs:
	; 29/10/2017
	;mov	ax, 128
	;mul	bx
	;mov	al, ah
	;mov	ah, 80
	;mul	ah
	mov	eax, ebx
	shl	ax, 7 ; * 128
	mov	al, 80
	mul	ah
	stosw
	inc	ebx
	loop	MakeOfs

	; 23/08/2020

	; DIRECT VGA MEMORY ACCESS
	; bl = 0, bh = 5
	; Direct access/map to VGA memory (0A0000h)

	sys	_video, 0500h
	cmp	eax, 0A0000h
	je	short _4
error_exit:
	sys	_msg, trdos386_err_msg, 255, 0Eh
	jmp	Exit

; Note: Normally IRQ 0 calls the ModPlay Polling at 18.2Hz thru
;       the software interrupt 1Ch. If the IRQ 0 is disabled, then
;       the INT 1Ch MUST BE CALLED at least MixSpeed/1024 times per
;       second, or the module will sound "looped".
;       Because we need better sync with the ModPlayer to draw the scope,
;       the polling is called from my routine, and then the irq 0 must be
;       disabled. The [DmaBuffer] points to the current buffer of 8-bit
;       samples played by the Sound Blaster. Note that some samples are
;       discarded in the next code, just for fun!

_4:
	;mov     ax, 0013h	; Set Mode 320x200x256
	;int     31h

	; 21/10/2017
	;mov	ax, 0012h	; Set Mode 640x480x16
	;int	31h

	; 22/10/2017
	call	setgraphmode	; Set video mode to 640*480x16

	; 22/10/2017
	;call	loadlbm
	;jc	short loadlbm_err

	mov	esi, LOGO_ADDRESS
	call	putlbm
	;jnc	short loadlbm_ok
	jnc	short _5 ; 

	;mov	byte [error_color], 0Eh ; Yellow

loadlbm_err:
	; 21/10/2017
	;mov	ax, 0003h	; Set Text Mode 80x25x16
	;int	31h
	; 22/10/2017
	call	settextmode

	sys	_msg, LOGO_ERROR_MSG, 255, 0Ch
	jmp	short Exit

loadlbm_ok: 
	; 21/10/2017
_5:
	; 09/10/2017 (2*BUFFERSIZE, 64K)
	; 23/06/2017
	; Map DMA buffer to user's memory space
	sys	_audio, 0D00h, 2*BUFFERSIZE, DMA_Buffer
	;jc	error_exit

	; 23/08/2020

; position file pointer to start in actual wav data
; MUCH improvement should really be done here to check if sample size is
; supported, make sure there are 2 channels, etc.  
;
        ;mov     ah, 42h
        ;mov     al, 0	; from start of file
        ;mov     bx, [FileHandle]
        ;xor     cx, cx
        ;mov     dx, 44	; jump past .wav/riff header
        ;int     21h

	sys	_seek, [FileHandle], 44, 0

; play the .wav file. Most of the good stuff is in here.

        call    PlayWav

; close the .wav file and exit.

StopPlaying:
	; Stop Playing
	sys	_audio, 0700h
	; Cancel callback service (for user)
	sys	_audio, 0900h
	; Deallocate Audio Buffer (for user)
	sys	_audio, 0A00h
	; Disable Audio Device
	sys	_audio, 0C00h

	; 23/08/2020
	call	settextmode
Exit:  
        call    closeFile
         
	sys	_exit	; Bye!
here:
	jmp	short here

pmsg_usage:
	sys	_msg, msg_usage, 255, 0Bh
	jmp	short Exit

DetectVT8233:
	; Detect (BH=1) VT8233 (BL=3) Audio Controller
        sys	_audio, 0103h
	retn

	; 23/08/2020

;open or create file
;
;input: ds:dx-->filename (asciiz)
;       al=file Mode (create or open)
;output: none  cs:[FileHandle] filled
;
openFile:
	;mov	ah, 3Bh	; start with a mode
	;add	ah, al	; add in create or open mode
	;xor	cx, cx
	;int	21h
	;jc	short _of1
	;;mov	[cs:FileHandle], ax

	sys	_open, wav_file_name, 0
	jc	short _of1

	mov	[FileHandle], eax
_of1:
	retn

; close the currently open file
; input: none, uses cs:[FileHandle]
closeFile:
	cmp	dword [FileHandle], -1
	je	short _cf1
	;mov    bx, [FileHandle]  
	;mov    ax, 3E00h
        ;int    21h              ;close file

	sys	_close, [FileHandle]
	mov 	dword [FileHandle], -1
_cf1:
	retn

getSampleRate:
	
; reads the sample rate from the .wav file.
; entry: none - assumes file is already open
; exit: ax = sample rate (11025, 22050, 44100, 48000)
;	cx = number of channels (mono=1, stereo=2)
;	dx = bits per sample (8, 16)

	push    ebx

        ;mov	ah, 42h
        ;mov	al, 0	; from start of file
        ;mov	bx, [FileHandle]
        ;xor	cx, cx
        ;mov	dx, 08h	; "WAVE"
        ;int	21h
	
	sys	_seek, [FileHandle], 8, 0

        ;mov	dx, smpRBuff
        ;mov	cx, 28	; 28 bytes
	;mov	ah, 3fh
        ;int	21h

	sys	_read, [FileHandle], smpRBuff, 28

	cmp	dword [smpRBuff], 'WAVE'
	jne	short gsr_stc

	cmp	word [smpRBuff+12], 1	; Offset 20, must be 1 (= PCM)
	jne	short gsr_stc

	mov	cx, [smpRBuff+14]	; return num of channels in CX
        mov     ax, [smpRBuff+16]	; return sample rate in AX
	mov	dx, [smpRBuff+26]	; return bits per sample value in DX
gsr_retn:
        pop     ebx
        retn
gsr_stc:
	stc
	jmp	short gsr_retn

;=============================================================================

;	; 23/08/2020
;audio_int_handler:
;	; 14/10/2017
;	mov	byte [srb], 1
;
;	sys	_rele ; return from callback service 
;	; we must not come here !
;	sys	_exit

;=============================================================================

	; 23/08/2020
loadFromFile:
	mov     edi, audio_buffer
	mov	edx, BUFFERSIZE

	; 17/03/2017
	; edi = buffer address
	; edx = buffer size
	; 10/03/2017
        ;push	eax
        ;push	ecx
        ;push	edx
	;push	ebx
        test    byte [flags], ENDOFFILE	; have we already read the
        stc			; last of the file?
        jnz     short endLFF
	;clc
	; load file into memory
	sys 	_read, [FileHandle], edi
	mov	ecx, edx
	jc	short padfill ; error !
	and	eax, eax
	jz	short padfill
	sub	ecx, eax
	jz	short endLFF
	add	edi, eax  
padfill:
	cmp 	byte [bps], 16
	je	short _lff2
	; Minimum Value = 0
        xor     al, al
	rep	stosb
_lff1:
        ;clc			; don't exit with CY yet.
        or	byte [flags], ENDOFFILE	; end of file flag
endLFF:
	;pop	ebx
	;pop	edx
        ;pop	ecx
        ;pop	eax
        retn
_lff2:
	; Minimum value = 8000h (-32768)
	shr	ecx, 1 
	mov	ax, 8000h ; -32768
	rep	stosw
	jmp	short _lff1

;=============================================================================
;      
;=============================================================================

PlayWav:
	; 23/08/2020

       ; load 32768 bytes into audio buffer
	;mov	edi, audio_buffer
	;mov	edx, BUFFERSIZE
	call	loadFromFile
	jc	error_exit

	; 27/07/2020
	test    byte [flags], ENDOFFILE  ; end of file
	jnz	short _6 ; yes
			 ; bypass filling dma half buffer 2

	; bh = 16 : update (current, first) dma half buffer
	; bl = 0  : then switch to the next (second) half buffer
	sys	_audio, 1000h

	; 27/07/2020
	; [audio_flag] = 1  (in TRDOS 386 kernel)

	; audio_buffer must be filled again after above system call 
	; (Because audio interrupt will be generated by VT8237R
	; at the end of the first half of dma buffer.. so, 
	; the second half must be ready. 'sound_play' will use it.)

	; 13/10/2017
	;mov	edi, audio_buffer
	;mov	edx, BUFFERSIZE
	call    loadFromFile
	;jc	short p_return ; 27/07/2020
_6:
	; Set Master Volume Level
	sys	_audio, 0B00h, 1D1Dh
	; 24/06/2017
	;mov	byte [volume_level], 1Dh
	mov	[volume_level], cl	

	;mov	byte [srb], 0

	; Start	to play
	mov	al, [bps]
	shr	al, 4 ; 8 -> 0, 16 -> 1
	shl	al, 1 ; 16 -> 2, 8 -> 0
	mov	bl, [stmo]
	dec	bl
	or	bl, al
	mov	cx, [sample_rate] 
	mov	bh, 4 ; start to play	
	sys	_audio

	; 27/07/2020
	; Here..
	; If byte [flags] <> ENDOFFILE ...
	; user's audio_buffer has been copied to dma half buffer 2

	; [audio_flag] = 0  (in TRDOS 386 kernel)

	; audio_buffer must be filled again after above system call 
	; (Because, audio interrupt will be generated by VT8237R
	; at the end of the first half of dma buffer.. so, 
	; the 2nd half of dma buffer is ready but the 1st half
	; must be filled again.)

	; 27/07/2020
	test    byte [flags], ENDOFFILE  ; end of file
	jnz	short p_loop ; yes

	; 13/10/2017
	;mov	edi, audio_buffer
	;mov	edx, BUFFERSIZE
	call    loadFromFile
	;jc	short p_return ; 27/07/2020

	; we need to wait for 'SRB' (audio interrupt)
	; (we can not return from 'PlayWav' here 
	;  even if we have got an error from file reading)
	; ((!!current audio data must be played!!))

	;mov	ebx, 0B8000h ; video display page address
	;mov	ah, 4Eh
	;add	al, [half_buffer]
	;mov	[ebx], ax ; show playing buffer (1, 2)

	;; load 32768 bytes into audio buffer
	;; (for the second half of DMA buffer)
	;; 20/05/2017
	;mov	edi, audio_buffer
	;mov	edx, BUFFERSIZE
	;call	loadFromFile
	;jc	short p_return
	;mov	byte [half_buff], 2 ; (DMA) Buffer 2

	; 23/08/2020

	; 27/10/2017
	
	; 03/08/2020
     	;jmp	short modp_gs ; 23/06/2017

	; 24/08/2020
	inc	byte [counter]
p_loop:
	cmp	byte [srb], 0
	jna	short q_loop

	mov	byte [srb], 0
modp_gs:
	; 24/08/2020
	;mov	edi, audio_buffer
	;mov	edx, BUFFERSIZE
	call	loadFromFile
	jc	short q_return

	; 23/08/2020
	jmp	r_loop
q_loop:
	; 24/08/2020
	test	byte [counter], 63
	jnz	short r_loop
k_loop:
	mov     ah, 1		; any key pressed?
	int     32h		; no, Loop.
	jz	short r_loop

	mov     ah, 0		; flush key buffer...
	int     32h

	; 19/10/2017 (modplay6.s)
	cmp	al, 20h
	je	short change_pan
	; 09/10/2017 (playmod5.s)
	cmp	al, '+' ; increase sound volume
	je	short inc_volume_level
	cmp	al, '-'
	je	short dec_volume_level

	; 19/10/2017 (modplay6.s)
	and	al, 0DFh
	cmp	al, 'P'
	jne	short q_return

change_pan:
	; 19/10/2017 (modplay6.s)
	mov	cl, [pan_shift]
	inc	cl
	and	cl, 3
	mov	[pan_shift], cl
	jmp	short r_loop

q_return:
	retn

	; 09/10/2017 (playmod5.s)
	; 24/06/2017 (wavplay2.s)
inc_volume_level:
	mov	cl, [volume_level]
	cmp	cl, 1Fh ; 31
	jnb	short r_loop
	inc	cl
change_volume_level:
	mov	[volume_level], cl
	mov	ch, cl
	; Set Master Volume Level
	sys	_audio, 0B00h
	jmp	short r_loop
dec_volume_level:
	mov	cl, [volume_level]
	cmp	cl, 1 ; 1
	jna	short r_loop
	dec	cl
	jmp	short change_volume_level

r_loop:
	; 24/08/2020
	inc	byte [counter]
	jnz	short q_loop

	; 23/08/2020
	test	byte [stmo], 2
	jz	p_loop
	cmp	byte [bps], 16
	jne	p_loop

	; 27/10/2017
	; Get Current DMA buffer Pointer 
	; 23/06/2017 ('modplay6.s')
	; bh = 15, get current pointer (DMA buffer offset)
	; bl = 0, for PCM OUT
	; ecx = 0
	;
	sys	_audio, 0F00h, 0

	; 28/10/2017
	and	al, 0FCh  ; dword alignment (stereo, 16 bit)	
	; 23/06/2017
	mov     esi, DMA_Buffer
	add     esi, eax	; add offset value
	; 24/06/2017
	mov	ecx, DMA_Buffer + (65536 - (256*4))
	cmp	esi, ecx 
	jna	short _7
	mov	esi, ecx
_7:
	; 23/10/2017 ('tmodplay.s')
	call	drawscopes

	jmp	p_loop

;=============================================================================
; 
;=============================================================================

;dword2str:
;	; 13/11/2016 - Erdogan Tan 
;	; eax = dword value
;	;
;	call	dwordtohex
;	mov	[dword_str], edx
;	mov	[dword_str+4], eax
;	mov	si, dword_str
;	retn

	; 05/03/2017 (TRDOS 386)
	; trdos386.s (unix386.s) - 10/05/2015
	; Convert binary number to hexadecimal string

;bytetohex:
;	; INPUT ->
;	; 	AL = byte (binary number)
;	; OUTPUT ->
;	;	AX = hexadecimal string
;	;
;	push	ebx
;	movzx	ebx, al
;	shr	bl, 4
;	mov	bl, [ebx+hex_chars] 	 	
;	xchg	bl, al
;	and	bl, 0Fh
;	mov	ah, [ebx+hex_chars] 
;	pop	ebx	
;	retn

;wordtohex:
;	; INPUT ->
;	; 	AX = word (binary number)
;	; OUTPUT ->
;	;	EAX = hexadecimal string
;	;
;	push	ebx
;	xor	ebx, ebx
;	xchg	ah, al
;	push	eax
;	mov	bl, ah
;	shr	bl, 4
;	mov	al, [ebx+hex_chars] 	 	
;	mov	bl, ah
;	and	bl, 0Fh
;	mov	ah, [ebx+hex_chars]
;	shl	eax, 16
;	pop	eax
;	pop	ebx
;	jmp	short bytetohex

;dwordtohex:
;	; INPUT ->
;	; 	EAX = dword (binary number)
;	; OUTPUT ->
;	;	EDX:EAX = hexadecimal string
;	;
;	push	eax
;	shr	eax, 16
;	call	wordtohex
;	mov	edx, eax
;	pop	eax
;	call	wordtohex
;	retn

	; 19/06/2017
	; 05/03/2017 (TRDOS 386)
	; 13/11/2016 - Erdogan Tan
write_audio_dev_info:
	; BUS/DEV/FN
	;	00000000BBBBBBBBDDDDDFFF00000000
	; DEV/VENDOR
	;	DDDDDDDDDDDDDDDDVVVVVVVVVVVVVVVV

	mov	esi, [dev_vendor]
	mov	ax, si
	movzx	ebx, al
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [ebx+hex_chars]
	mov	[msgVendorId+3], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [ebx+hex_chars]
	mov	[msgVendorId+2], al
	mov	bl, ah
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [ebx+hex_chars]
	mov	[msgVendorId+1], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [ebx+hex_chars]
	mov	[msgVendorId], al
	shr	esi, 16
	mov	ax, si
	mov	bl, al
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [ebx+hex_chars]
	mov	[msgDevId+3], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [ebx+hex_chars]
	mov	[msgDevId+2], al
	mov	bl, ah
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [ebx+hex_chars]
	mov	[msgDevId+1], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [ebx+hex_chars]
	mov	[msgDevId], al

	mov	esi, [bus_dev_fn]
	shr	esi, 8
	mov	ax, si
	mov	bl, al
	mov	dl, bl
	and	bl, 7 ; bit 0,1,2
	mov	al, [ebx+hex_chars]
	mov	[msgFncNo+1], al
	mov	bl, dl
	shr	bl, 3
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [ebx+hex_chars]
	mov	[msgDevNo+1], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [ebx+hex_chars]
	mov	[msgDevNo], al
	mov	bl, ah
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [ebx+hex_chars]
	mov	[msgBusNo+1], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [ebx+hex_chars]
	mov	[msgBusNo], al

	mov	ax, [ac97_io_base]
	mov	bl, al
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [ebx+hex_chars]
	mov	[msgIOBaseAddr+3], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [ebx+hex_chars]
	mov	[msgIOBaseAddr+2], al
	mov	bl, ah
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [ebx+hex_chars]
	mov	[msgIOBaseAddr+1], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [ebx+hex_chars]
	mov	[msgIOBaseAddr], al

	; 24/11/2016
	xor	ah, ah
	mov	al, [ac97_int_ln_reg]
	mov	cl, 10
	div	cl
	add	[msgIRQ], ax
	and	al, al
	jnz	short _w_ac97imsg_ ; 19/06/2017
	mov	al, [msgIRQ+1]
	mov	ah, ' '
	mov	[msgIRQ], ax
_w_ac97imsg_:
	; EBX = Message address
	; ECX = Max. message length (or stop on ZERO character)
	;	(1 to 255)
	; DL  = Message color (07h = light gray, 0Fh = white) 
     	sys 	_msg, msgAC97Info, 255, 07h
        retn

	; 24/08/2020
write_wav_file_info:
	; 01/05/2017
	sys	_msg, msgWavFileName, 255, 0Fh
	sys	_msg, wav_file_name, 255, 0Fh

write_sample_rate:
	; 01/05/2017
	mov	ax, [sample_rate]
	; ax = sample rate (hertz)
	xor	edx, edx
	mov	cx, 10
	div	cx
	add	[msgHertz+4], dl
	sub	edx, edx
	div	cx
	add	[msgHertz+3], dl
	sub	edx, edx
	div	cx
	add	[msgHertz+2], dl
	sub	edx, edx
	div	cx
	add	[msgHertz+1], dl
	add	[msgHertz], al
	
	sys	_msg, msgSampleRate, 255, 0Fh

	mov	esi, msg16Bits
	cmp	byte [bps], 16
	je	short wsr_1
	mov	esi, msg8Bits
wsr_1:
	sys	_msg, esi, 255, 0Fh

	mov	esi, msgMono
	cmp	byte [stmo], 1
	je	short wsr_2
	mov	esi, msgStereo		
wsr_2:
	sys	_msg, esi, 255, 0Fh
        retn

;=============================================================================
;	gfx.asm - draw scopes in VGA 640x480x16 mode      
;=============================================================================

; EX1A.ASM (21/6/1994, Carlos Hasan; MSDOS, 'RUNME.EXE', 'TNYPL211')

;-----------------------------------------------------------------------------
; setgraphmode - setup the VGA 640x480x16 graphics mode
;-----------------------------------------------------------------------------
	; 22/10/2017
setgraphmode:
	;pushad
	mov	ax,0012h
	;int	10h
	int 	31h
	mov	dx,3C0h
	xor	al,al
setgraphmodel0:
	;out	dx,al
	mov	ah, 1 ; outb
	int	34h
	;out	dx, al
	;mov	ah, 1
	int	34h
	inc	al
	cmp	al, 10h
	jb	short setgraphmodel0
	mov	al, 20h
	;out	dx, al
	;mov	ah, 1
	int	34h
	;popad
	retn

;-----------------------------------------------------------------------------
; settextmode - restore the VGA 80x25x16 text mode
;-----------------------------------------------------------------------------
	; 22/10/2017
settextmode:
	;pushad
	mov	ax, 0003h
	;int	10h
	int	31h
	;popad
	retn

;-----------------------------------------------------------------------------
; drawscopes - draw the track voices sample scopes
; In:
;  ESI = (current) sample buffer
;-----------------------------------------------------------------------------
	; 29/10/2017
	; 28/10/2017
	; (ESI = Current DMA buffer offset)
	; 27/10/2017
	; 26/10/2017
	; 23/10/2017
drawscopes:
	;pushad
  	;mov	esi, g_buff
	;mov	esi, edx
	xor     ecx, ecx	
	xor     edx, edx
	xor	edi, edi
drawscope0:
	lodsw
	xor	ah, 80h
	movzx	ebx, ah  ; Left Channel
	shl	bx, 1
	mov	ax, [RowOfs+ebx]
	mov	[NewScope_L+edi], ax
	xor	bh, bh
	lodsw
	xor	ah, 80h
	mov	bl, ah	; Right Channel
	shl	bx, 1
	mov	ax, [RowOfs+ebx]
	mov	[NewScope_R+edi], ax
	add	di, 2
	inc	cl
	jnz	short drawscope0	

        mov	dx, 3C4h
        ;mov	ax, 0802h
        ;out	dx, ax
        mov	bx, 0802h
	mov	ah, 3 ; outw
	int	34h
	mov	dx, 3CEh
        mov	al, 08h
       ;out	dx, al
        mov	ah, 1 ; outb
	int	34h
	inc	dx

	; 26/10/2017
        xor	esi, esi
       ;xor	edi, edi
        mov     ebx, 0A0645h
drawscopel4:
        mov     al, 80h
drawscopel2:
        push    eax ; *
        push    edx ; **
	;out	dx, al
	mov	ah, 1 ; outb
	int	34h

        mov	ah, 0FFh
        ;mov	ecx, 32
	mov	cl, 32
	sub     al, al
drawscopel3:
	; 23/10/2017
        mov	dx, [OldScope_L+esi]
        cmp	dx, [NewScope_L+esi]
        je	short drawscopef3
        mov	[edx+ebx], al ; L
        mov     dx, [NewScope_L+esi]
	mov	[edx+ebx], ah ; L
        mov     [OldScope_L+esi], dx
drawscopef3:
	; 27/10/2017
        mov	dx, [OldScope_R+esi]
        cmp	dx, [NewScope_R+esi]
        je	short drawscopef4
	mov	[edx+ebx+38], al ; R
        mov     dx, [NewScope_R+esi]
        mov	[edx+ebx+38], ah ; R
        mov     [OldScope_R+esi], dx
drawscopef4:
	add	esi, 2*8
	inc	ebx
	loop    drawscopel3

        pop     edx ; **
        pop     eax ; *
	sub	esi, 2*256-2
	sub	ebx, 32
        shr     al, 1
        jnz	short drawscopel2
	;popad
        retn

;=============================================================================
;	Load IFF/ILBM files for VGA 640x480x16 graphics mode       
;=============================================================================

; EX1B.ASM (21/6/1994, Carlos Hasan; MSDOS, 'RUNME.EXE', 'TNYPL211')

; 21/10/2017 (TRDOS 386, 'tmodplay.s', Erdogan Tan, NASM syntax)

;-----------------------------------------------------------------------------
; EQUATES AND STRUCTURES
;-----------------------------------------------------------------------------

ID_FORM equ 4D524F46h		; IFF/ILBM chunk IDs
ID_ILBM equ 4D424C49h
ID_BMHD equ 44484D42h
ID_CMAP equ 50414D43h
ID_BODY equ 59444F42h

struc Form			; IFF/ILBM header file format
  .ID:		resd 1
  .Length:	resd 1
  .Type:	resd 1
  .size:
endstruc

struc Chunk			; IFF/ILBM header chunk format
  .ID:		resd 1
  .Length:	resd 1
  .size:	
endstruc

struc BMHD			; IFF/ILBM BMHD chunk format
  .Width: 	resw 1
  .Height:	resw 1
  .PosX:	resw 1
  .PosY:	resw 1
  .Planes:	resb 1
  .Masking:	resb 1
  .Compression:	resb 1
  .Pad:		resb 1
  .Transparent:	resw 1
  .AspectX	resb 1
  .AspectY:	resb 1
  .PageWidth:	resw 1
  .PageHeight:	resw 1
  .size:	
endstruc

struc CMAP			; IFF/ILBM CMAP chunk format
  .Colors:	resb 768
  .size:	
endstruc

;LOGO_ADDRESS	equ 100000h	; virtual address at the end of the 1st 1MB

;------------------------------------------------------------------------------
; bswap - macro to reverse the byte order of a 32-bit register, converting
;         a value in little/big endian form to big/little endian form.
;------------------------------------------------------------------------------
%macro	bswap   1
        xchg    al, ah
        rol     eax, 16
        xchg    al, ah
%endmacro

;------------------------------------------------------------------------------
; putlbm - draw the IFF/ILBM picture on VGA 640x480x16 graphics mode
; In:
;  ESI = IFF/ILBM image file address
;------------------------------------------------------------------------------
putlbm:
        pushad

; check if this is a valid IFF/ILBM Deluxe Paint file

        cmp     dword [esi+Form.ID], ID_FORM
        jne     short putlbmd0
        cmp     dword [esi+Form.Type], ID_ILBM
        jne     short putlbmd0

; get the IFF/ILBM file length in bytes

        mov     eax, [esi+Form.Length]
        bswap   eax
        mov     ecx, eax

; decrease the file length and update the file pointer

        sub     ecx, 4
        add     esi, Form.size

; IFF/ILBM main parser body loop

putlbml0:
        test    ecx, ecx
        jle     short putlbmd1

; get the next chunk ID and length in bytes

        mov     ebx, [esi+Chunk.ID]
        mov     eax, [esi+Chunk.Length]
        bswap   eax
        xchg    ebx, eax
        add     esi, Chunk.size

; word align the chunk length and decrease the file length counter

        inc     ebx
        and     bl, 0FEh ; ~1
        sub     ecx, Chunk.size
        sub     ecx, ebx

; check for the BMHD/CMAP/BODY chunk headers

        cmp     eax, ID_BMHD
        je      short putlbmf0
        cmp     eax, ID_CMAP
        je      short putlbmf1
        cmp     eax, ID_BODY
        je      short putlbmf2

; advance to the next IFF/ILBM chunk structure

putlbmc0:
        add     esi, ebx
        jmp     short putlbml0

putlbmd0:
        stc
        popad
        retn

; process the BMHD bitmap header chunk

putlbmf0:
        cmp     byte [esi+BMHD.Planes], 4
        jne     short putlbmd0
        cmp     byte [esi+BMHD.Compression], 1
        jne     short putlbmd0
        cmp     byte [esi+BMHD.Pad], 0
        jne     short putlbmd0
        movzx   eax, word [esi+BMHD.Width]
        xchg    al, ah
        add     eax, 7
        shr     eax, 3
        mov     [picture.width], eax
        movzx   eax, word [esi+BMHD.Height]
        xchg    al, ah
        mov     [picture.height], eax
        jmp     short putlbmc0

putlbmd1:
        clc
        popad
        retn

; process the CMAP colormap chunk

putlbmf1:
        mov     dx, 3C8h
        xor     al, al
        ;out	dx, al
	mov	ah, 1 ; outb
	int	34h
        inc     dx
putlbml1:
        mov     al, [esi]
        shr     al, 2
        ;out	dx, al
	;mov	ah, 1 ; outb
	int	34h ; IOCTL interrupt (IN/OUT)
        inc     esi
        dec     ebx
        jg      short putlbml1
        jmp     putlbml0

; process the BODY bitmap body chunk

putlbmf2:
        pushad
        mov     edi, 0A0000h
        ;cld
        mov     dx, 3CEh
        ;mov	ax, 0FF08h
        ;out	dx, ax
	mov	bx, 0FF08h
	mov	ah, 3 ; outw
	int	34h ; IOCTL interrupt (IN/OUT)
        mov     dx, 3C4h
        mov     al, 02h
        ;out	dx, al
	mov	ah, 1 ; outb
	int	34h ; IOCTL interrupt (IN/OUT)
        inc     dx
        mov     ecx, [picture.height]
putlbml2:
        push    ecx
        mov     al, 11h
putlbml3:
        push    eax
        push    edi
        ;out	dx, al
	mov	ah, 1 ; outb
	int	34h ; IOCTL interrupt (IN/OUT)
        mov     ebx, [picture.width]
putlbml4:
        lodsb
        test    al, al
        jl      short putlbmf3
        movzx   ecx, al
        inc     ecx
        sub     ebx, ecx
        rep     movsb
        jmp     short putlbmc4
putlbmf3:
        neg     al
        movzx   ecx, al
        inc     ecx
        sub     ebx, ecx
        lodsb
        rep     stosb
putlbmc4:
        test    ebx, ebx
        jg      short putlbml4
        pop     edi
        pop     eax
        add     al, al
        jnc     short putlbml3
        add     edi, 80
        pop     ecx
        loop    putlbml2
	popad
        jmp	putlbmc0

; EX1.C (Carlos Hasan, 21/06/1994)
;------------------------------------------------------------------------------
; loadlbm - load the IFF/ILBM image file ("LOGO.LBM") at memory
;  ESI = IFF/ILBM image file address
;------------------------------------------------------------------------------

;if ((Logo = loadlbm("LOGO.LBM")) == NULL) {
;       printf("Error loading the IFF/ILBM logo picture\n");
;       MODStopModule();
;       MODFreeModule(Song);
;       return;
;   }
;   setgraphmode();
;   putlbm(Logo);
;   while (!kbhit())
;       drawscopes(Song->NumTracks);
;   settextmode();
;   free(Logo);
;   MODStopModule();
;   MODFreeModule(Song);

;loadlbm:
;	; ebx = ASCIIZ file name address
;	; ecx = open mode (0 = open for read)	
;	sys	_open, LOGO_FILE_NAME, 0 ; open for reading
;	jc	short loadlbm_retn
;
;	mov     [LBM_FileHandle], eax
;
;	; get file size by moving file pointer to the end of file
;	; ebx = file handle/number
;	; ecx : offset = 0
;	; edx : switch = 2 (move fp to end of file + offset)
;	sys	_seek, eax, 0, 2
;	jc	short loadlbm_cf
;
;	mov	[LBM_FileSize], eax
;
;	; move file pointer to the beginning of the file
;	; ecx = 0
;	; edx = 0
;	;xor	ecx, ecx
; 	xor	dl, dl
;	; ebx = [LBM_FileHandle]
;	sys	_seek
;	;jc	short loadlbm_cf
;
;	; ebx = File handle
;	; ecx = Buffer address
;	; edx = Byte count
;	;sys	_read, [LBM_FileHandle], LOGO_ADDRESS, [LBM_FileSize]
;	mov	ecx, LOGO_ADDRESS
;	mov	edx, [LBM_FileSize]
;	sys	_read
;	jc	short loadlbm_cf
;
;	cmp	eax, edx  ; read count = file size ?
;	;jb	short loadlbm_cf		 
;loadlbm_cf:
;	pushf
;	sys	_close, [LBM_FileHandle]	
;	popf
;loadlbm_retn:
;	retn	
;
;LOGO_FILE_NAME:
;	db	"LOGO.LBM", 0

LOGO_ERROR_MSG:
	db	"Error loading the IFF/ILBM logo picture !", 0Dh, 0Ah, 0 

align 2
; 22/10/2017
LOGO_ADDRESS:
;incbin "LOGO.LBM"	  	 
; 27/10/2017
incbin "TINYPLAY.LBM"

;=============================================================================
;               preinitialized data
;=============================================================================
	
	db	0
	; 23/08/2020
FileHandle:	
	dd	-1
	db	0
Credits:
msg_usage:
	db	'Tiny WAV Player for TRDOS 386 by Erdogan Tan',10,13
	db 	'for VIA VT8233 Audio Controller.',10,13
	db	'August 2020.',10,13
credits_zero:
	db	10,13
	db	'usage: twavplay filename.wav',10,13,0
	db	'24/08/2020',10,13,0

noDevMsg:
	db	'Error: Unable to find VIA VT8233 based audio device!'
	db	10,13,0

noFileErrMsg:
	db	'Error: file not found.',10,13,0

trdos386_err_msg:
	db	'TRDOS 386 System call error !',10,13,0

; 13/11/2016
hex_chars:	db "0123456789ABCDEF", 0
;
msgAC97Info:	
		db 0Dh, 0Ah
		db "AC97 Audio Controller & Codec Info", 0Dh, 0Ah 
		db "Vendor ID: "
msgVendorId:	db "0000h Device ID: "
msgDevId:	db "0000h", 0Dh, 0Ah
		db "Bus: "
msgBusNo:	db "00h Device: "
msgDevNo:	db "00h Function: "
msgFncNo	db "00h"
		db 0Dh, 0Ah
		db "I/O Base Address: "
msgIOBaseAddr:	db "0000h IRQ: "
msgIRQ:		dw 3030h
		db 0Dh, 0Ah, 0

msgWavFileName:	db 0Dh, 0Ah, "WAV File Name: ",0
msgSampleRate:	db 0Dh, 0Ah, "Sample Rate: "
msgHertz:	db "00000 Hz, ", 0 
msg8Bits:	db "8 bits, ", 0 
msgMono:	db "Mono", 0Dh, 0Ah, 0
msg16Bits:	db "16 bits, ", 0 
msgStereo:	db "Stereo"
nextline:	db 0Dh, 0Ah, 0

;=============================================================================
;		uninitialized data
;=============================================================================

; 23/08/2020

; BSS

bss_start:

ABSOLUTE bss_start

alignb 4

;------------------------------------------------------------------------------
; IFF/ILBM DATA
;------------------------------------------------------------------------------

LBM_FileHandle:	resd 1
LBM_FileSize:	resd 1
;
picture.width:	resd 1 		; current picture width and height
picture.height:	resd 1

;------------------------------------------------------------------------------

;alignb 4

stmo:		resb 1 ; stereo or mono (1=stereo) 
bps:		resb 1 ; bits per sample (8,16)
sample_rate:	resw 1 ; Sample Frequency (Hz)

smpRBuff:	resw 14 

wav_file_name:
		resb 80 ; wave file, path name (<= 80 bytes)

alignb 4

dev_vendor:	resd 1
bus_dev_fn:	resd 1
ac97_io_base:	resw 1
ac97_int_ln_reg: resb 1
srb:		resb 1

flags:		resb 1

; 23/08/2020
counter:	resb 1

alignb 16

; PLAY.ASM
;Scope:		resw 320
RowOfs:		resw 256

; 23/10/2017
NewScope_L:	resw 256
NewScope_R:	resw 256
OldScope_L:	resw 256
OldScope_R:	resw 256

; 20/10/2017 (modplay7.s, SB16)
; 19/10/2017 (modplay6.s, AC97)
pan_shift:	resb 1
volume_level:	resb 1

alignb 4096

audio_buffer:
		resb BUFFERSIZE ; DMA Buffer Size / 2  (32768)

alignb 65536

DMA_Buffer:
		resb 2*BUFFERSIZE  ; 65536 ; 09/10/2017 
file_buffer:
	resb 65536*6
EOF: