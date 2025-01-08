; ****************************************************************************
; cgaplay2.s - TRDOS 386 (TRDOS v2.0.9) WAV PLAYER - Video Mode 13h
; ----------------------------------------------------------------------------
; CGAPLAY2.PRG ! Sound Blaster 16 .WAV PLAYER program by Erdogan TAN
;
; 06/01/2025				- play music from multiple wav files -
;
; [ Last Modification: 08/01/2025 ]
;
; Modified from CGAPLAY.PRG .wav player program by Erdogan Tan, 01/01/2025
;	        SB16PLAY.PRG, 20/12/2024
;
; ****************************************************************************
; nasm cgaplay2.s -l cgaplay2.txt -o CGAPLAY2.PRG -Z error.txt

; 02/01/2025
; cgaplay2.asm - CGAPLAY2.COM - Sound Blaster 16
; 01/01/2025
; cgaplay.s - CGAPLAY.PRG - AC97 - Video Mode 13h (320*200, 256 colors)
; 26/12/2024
; vgaplay.s - VGAPLAY.PRG - AC97 - VESA Mode 101h (640*480, 256 colors)
; 20/12/2024
; sb16play.s : Video Mode 03h (Text Mode)

; 07/12/2024 - playwav9.s - interrupt (srb) + tuneloop version
; ------------------------------------------------------------
; INTERRUPT (SRB) + TUNELOOP version ; 24/11/2024 (PLAYWAV9.ASM)
;	(running in DOSBOX, VIRTUALBOX, QEMU is ok)
; Signal Response Byte = message/signal to user about an event/interrupt
;	    as requested (TuneLoop procedure continuously checks this SRB)
; (TRDOS 386 v2 feature is used here as very simple interrupt handler output)

; ------------------------------------------------------------

; 30/11/2024
; 20/08/2024 ; TRDOS 386 v2.0.9
; 29/04/2016
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
_dma	equ 45
_stdio  equ 46

; ------------------------------------------------------------

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

; Retro UNIX 386 v1 system call format:
; sys systemcall (eax) <arg1 (ebx)>, <arg2 (ecx)>, <arg3 (edx)>

; ------------------------------------------------------------

; player internal variables and other equates.
BUFFERSIZE equ 32768	; audio (half) buffer size 
ENDOFFILE  equ 1	; flag for knowing end of file
; 06/01/2025
DMABUFFERSIZE equ BUFFERSIZE*2

; ------------------------------------------------------------

[BITS 32] ; 32-bit intructions

[ORG 0]

START_CODE:
	; Prints the Credits Text.
	sys	_msg, Credits, 255, 0Bh

	; clear bss
	mov	edi, bss_start
	mov	ecx, (bss_end - bss_start)/4
	xor	eax, eax
	rep	stosd

; -------------------------------------------------------------

	; 02/01/2025
	; 24/11/2024
	; Detect (& Reset) Sound Blaster 16 Audio Device
	call	DetectSB16
	;jnc	short GetFileName
	; 06/01/2025
	jnc	short get_audio_info

	; 30/11/2024
	; 30/05/2024
_dev_not_ready:
	; couldn't find the audio device!
	sys	_msg, noDevMsg, 255, 0Fh
        jmp     Exit

; -------------------------------------------------------------

	; 06/01/2025 (cgaplay2.s)
get_audio_info:
	; 20/12/2024 (playwavx.s, sb16play.s)
	; 07/12/2024 (playwav9.s)
	; 06/06/2017
	sys	_audio, 0E00h ; get audio controller info
	jc	error_exit ; 25/11/2023
	; 20/12/2024
	mov	[audio_io_base], edx
	mov	[audio_intr], al

; -------------------------------------------------------------

	; 06/01/2025
	; 30/12/2024
	;;;
	; DIRECT VGA MEMORY ACCESS
	; bl = 0, bh = 5
	; Direct access/map to VGA memory (0A0000h)

	sys	_video, 0500h
	cmp	eax, 0A0000h
	je	short set_video_mode_13h

	; 30/12/2024
	jmp	trdos386_error

set_video_mode_13h:
	;; Set Video Mode to 13h
	;sys	_video, 0813h
	;cmp	eax, 14h 
	;je	short mode_13h_set_ok

	; set VGA mode by using int 31h
	mov	ax, 13h	; mode 13h ; 
	int	31h	; real mode: int 10h

; -------------------------------------------------------------

mode_13h_set_ok:
	; 30/12/2024
	; 24/12/2024 (setting for wave lighting points)
	;mov	eax, 0A0000h
	;;add	eax, 12*8*320
	;add	eax, (13*8*320)+(2*320)
			; wave graphics start (top) line/row
			; 64 volume levels
	;mov	[graphstart], eax
	;; 30/12/2024
	;;mov	dword [graphstart], 0A0000h+(13*8*320)+(4*320)
	; 06/01/2025
	; 01/01/2025
	;mov	dword [graphstart], 0A0000h+(11*8*320)+(4*320)

; -------------------------------------------------------------

	; 25/12/2024
	; 28/11/2024
Player_InitalizePSP:
	; 30/11/2024
	; (TRDOS 386 -Retro UNIX 386- argument transfer method)
	; (stack: argc,argv0addr,argv1addr,argv2addr ..
	;			.. argv0text, argv1text ..) 
	; ---- argc, argv[] ----
	mov	esi, esp
	lodsd
	cmp	eax, 2 ; two arguments 
		; (program file name & mod file name)
	jb	pmsg_usage ; nothing to do
	;mov	[argc], al
	shl	eax, 2 ; *4
	add	eax, esp
	; eax = last argument's address pointer
	mov	[argvl], eax ; last wav file (argument)
	mov	[argv], esi ; current argument (PRG file name)
	lodsd	; skip program (PRG) file name
	mov	[argvf], esi ; 1st wav file (argument)

	; 30/12/2024
Player_ParseParameters:
	jmp	short Player_ParseNextParameter
	; 25/12/2024
check_p_command:
	; 07/12/2024
	mov	esi, [argv]
	;
  	cmp	byte [command], 'P'
	je	short Player_ParsePreviousParameter
    
	; 07/12/2024
	; 30/11/2024
	;mov	esi, [argv] ; current argument (wav file) ptr
	add	esi, 4
	cmp	esi, [argvl] ; last argument (wav file) ptr
	jna	short Player_ParseNextParameter
jmp_Player_Quit:
	jmp	Player_Quit

Player_ParsePreviousParameter:
	; 29/11/2024
	;mov	byte [command], 0
	; 30/11/2024
	;mov	esi, [argv] ; 07/12/2024	
	cmp	esi, [argvf] ; first argument (wav file) ptr
	jna	short Player_ParseNextParameter
	sub	esi, 4
Player_ParseNextParameter:
	; 30/11/2024
	mov	[argv], esi  ; set as current argument

	; 01/12/2024
	mov	esi, [esi]

	; 30/12/2024
	; 29/11/2024
	call	GetFileName
	;jcxz	jmp_Player_Quit
	jecxz	jmp_Player_Quit ; 30/11/2024

	; 30/12/2024
        ; open existing file
	; 28/11/2024
	mov	edx, wav_file_name
        call	openFile ; no error? ok.
        jnc	getwavparms	; 14/11/2024

	; 29/11/2024
	cmp	byte [filecount], 0
	ja	short check_p_command

	; 25/12/2024
	; 21/12/2024
	call	set_text_mode
	; file not found!
	; 30/11/2024
	sys	_msg, noFileErrMsg, 255, 0Ch
	jmp	Exit

_exit_:
	jmp	terminate

; -------------------------------------------------------------

	; 26/12/2024
	; 25/12/2024
	; 30/11/2024 (32bit)
	; 29/11/2024
	; 30/05/2024
GetFileName:
	mov	edi, wav_file_name 
	; 30/11/2024
	;mov	esi, [argv]
	xor	ecx, ecx ; 0
ScanName:
	lodsb
	;test	al, al
	;jz	short a_4
	; 29/11/2024
	cmp	al, 0Dh
	jna	short a_4
	cmp	al, 20h
	je	short ScanName	; scan start of name.
	stosb
	mov	ah, 0FFh
	;;;
	; 14/11/2024
	; (max. path length = 64 bytes for MSDOS ?) (*)
	;xor	ecx, ecx ; 0
	;;;
a_0:	
	inc	ah
a_1:
	;;;
	; 14/11/2024
	inc	ecx
	;;;
	lodsb
	stosb
	cmp	al, '.'
	je	short a_0
	; 29/11/2024
	cmp	al, 20h
	;and	al, al
	;jnz	short a_1
	;;;
	; 14/11/2024
	jna	short a_3
	and	ah, ah
	jz	short a_2
	cmp	al, '/'	; 14/12/2024
	jne	short a_2
	mov	ah, 0
a_2:
	cmp	cl, 75	; 64+8+'.'+3 -> offset 75 is the last chr
	jb	short a_1
	; 29/11/2024
	sub	ecx, ecx
	jmp	short a_4
a_3:
	; 29/11/2024
	dec	edi
	;;;
	or	ah, ah		; if period NOT found,
	jnz	short a_4 	; then add a .WAV extension.
SetExt:
	; 29/11/2024
	;dec	edi
	mov	dword [edi], '.WAV'
				; ! 64+12 is DOS limit
				; but writing +4 must not
				; destroy the following data	 
	;mov	byte [edi+4], 0	; so, 80 bytes path + 0 is possible here
	; 29/11/2024
	add	ecx, 4
	add	edi, 4
a_4:	
	mov	byte [edi], 0
	; 30/11/2024
	retn

; -------------------------------------------------------------

getwavparms:
	; 14/11/2024
       	call    getWAVParameters
	jc	short _exit_		; nothing to do

	; 07/01/2025
	cmp	byte [allocated], 0
	ja	short StartPlay

; -------------------------------------------------------------

	; 06/01/2025 (cgaplay2.s)
	
	; 16/12/2024 (sb16play.s)
	; 07/12/2024 (playwav9.s) -ac97-
	; Allocate Audio Buffer (for user)
	sys	_audio, 0200h, BUFFERSIZE, audio_buffer
	jc	error_exit

	; 17/12/2024
	inc	byte [allocated]

	; 17/12/2024
	; Initialize Audio Device (bh = 3)
	sys	_audio, 301h, 0, audio_int_handler
	jc	error_exit

	; 17/12/2024
	inc	byte [interrupt]

	; 08/01/2025
	;; 17/12/2024
	;; 16/12/2024
	;; Map DMA Buffer to User (for wave graphics)
	;sys	_audio, 0D00h, BUFFERSIZE*2, dma_buffer
	;jc	error_exit

; -------------------------------------------------------------

StartPlay:
	; 30/12/2024
	mov	byte [wpoints], 1

; 08/01/2025
%if 0
	;;;
	; 06/01/2025
	movzx	eax, word [WAVE_SampleRate]
	;mov	ax, [WAVE_SampleRate]
	mov	ecx, 10
	mul	ecx
	mov	cl, 182
	div	ecx
	; ax = samples per 1/18.2 second
	mov	cl, byte [WAVE_BlockAlign]
	mul	ecx
	mov	[wpoints_dif], eax ; buffer read differential (distance)
				; for wave volume leds update
				; (byte stream per 1/18.2 second)
%else
	; 08/01/2025
	xor	ecx, ecx
	mov	cl, byte [WAVE_BlockAlign]
%endif
	; 08/01/2025
	mov	eax, 320
	mul	ecx
	mov	[sd_count], eax
	;;;

; -------------------------------------------------------------

	; 06/01/2025 (cgaplay2.s)
	; 02/01/2025 (cgaplay2.asm)
	;;;
	; 23/11/2024 (sb16play.asm, [turn_on_leds])
	cmp	byte [WAVE_NumChannels], 1
	ja	short stolp_s
stolp_m:
	cmp	byte [WAVE_BitsPerSample], 8
	ja	short stolp_m16
stolp_m8:
	mov	word [UpdateWavePoints], UpdateWavePoints_8m
	jmp	short stolp_ok
stolp_m16:
	mov	word [UpdateWavePoints], UpdateWavePoints_16m
	jmp	short stolp_ok
stolp_s:
	cmp	byte [WAVE_BitsPerSample], 8
	ja	short stolp_s16
stolp_s8:
	mov	word [UpdateWavePoints], UpdateWavePoints_8s
	jmp	short stolp_ok
stolp_s16:
	mov	word [UpdateWavePoints], UpdateWavePoints_16s
	jmp	short stolp_ok
stolp_ok:
	;;;

; -------------------------------------------------------------

	; 25/12/2024
	inc	byte [filecount]
	mov	byte [command], 0
	; 30/12/2024
	mov	byte [pbprev], -1

	; 06/01/2025

; -------------------------------------------------------------

	; 30/12/2024
Player_Template:
	; 21/12/2024
	call	clearscreen
	call	drawplayingscreen

	; 14/11/2024
	call	SetTotalTime
	call	UpdateFileInfo

; -------------------------------------------------------------

	; 06/01/2025 (cgaplay2.s) -SB16-
	; 02/01/2025 (cgaplay2.asm) -SB16-
	; 01/01/2025 (cgaplay.asm) -AC97-
	; 30/12/2024 (cgaplay.s) -AC97-
	; 29/12/2024 (vgaplay3.s) -AC97-
	; 20/12/2024 (sb16play.asm) 
	; 18/12/2024 (ac97play.s)
PlayNow:
	; 01/12/2024 (32bit)
	; 14/11/2024
	;;mov	al, 3	; 0 = max, 31 = min
	; 24/11/2024
	;mov	al, 5	; 15 = max, 0 = min
	; 27/11/2024
	;mov	[volume], al
	; 14/12/2024
	mov	al, [volume]
	;call	SetPCMOutVolume@
	; 02/01/2025
	call	SetMasterVolume@
	; 15/11/2024
	;call	SetMasterVolume
	;;call	SetPCMOutVolume

	;;;
	; 14/11/2024
	call	UpdateProgressBar
	;;;

 	; 30/05/2024
	; playwav4.asm
_2:	
	call	check4keyboardstop	; flush keyboard buffer
	jc	short _2		; 07/11/2023

; play the .wav file. Most of the good stuff is in here.

	call    PlayWav

	; 30/12/2024
	; 29/12/2024 (vgaplay3.s)
	; 27/12/2024 (vgaplay.s)
_3:

; close the .wav file and exit.

	; 25/12/2024
	call	closeFile

	; 25/12/2024
	;;;
	; reset file loading and EOF parameters
	; 18/12/2024
	mov	dword [count], 0
	mov	dword [LoadedDataBytes], 0
	mov	byte [flags], 0
	mov	byte [stopped], 0
	; 08/01/2025
	; 29/12/2024
	;mov	dword [pbuf_s], 0
	;;;

	cmp	byte [command], 'Q'
	je	short terminate
	jmp	check_p_command

terminate:
	call	set_text_mode
	; 06/01/2025
Exit@:
	; 17/12/2024
	cmp	byte [interrupt], 0
	jna	short skip_cb_cancel

	; Cancel callback service (for user)
	sys	_audio, 0900h

skip_cb_cancel:
	; 17/12/2024
	cmp	byte [allocated], 0
	jna	short skip_ab_dalloc

	; Deallocate Audio Buffer (for user)
	sys	_audio, 0A00h

skip_ab_dalloc:
	; Disable Audio Device
	sys	_audio, 0C00h
	;;;
Exit:
	;mov	ax, 4C00h	; bye !
	;int	21h
	; 01/12/2024
	sys	_exit, 0
halt:
	jmp	short halt

; -------------------------------------------------------------

	; 30/05/2024
pmsg_usage:
	; 21/12/2024
	call	set_text_mode
	; 01/12/2024
	sys	_msg, msg_usage, 255, 0Fh
	jmp	short Exit

; -------------------------------------------------------------

	; 30/05/2024
init_err:
	; 21/12/2024
	call	set_text_mode
	; 01/12/2024
	sys	_msg, msg_init_err, 255, 0Fh
	jmp	short Exit

; -------------------------------------------------------------

	; 07/12/2024
error_exit:
	; 21/12/2024
	call	set_text_mode
trdos386_error:
	sys	_msg, trdos386_err_msg, 255, 0Eh
	jmp	short Exit

; -------------------------------------------------------------

	; 21/12/2024
print_msg:
	mov	ah, 0Eh
	mov	ebx, 7
	;mov	bl, 7 ; char attribute & color
p_next_chr:
	lodsb
	or	al, al
	jz	short p_retn ; retn
	int	31h
	jmp	short p_next_chr
p_retn:
	retn

; -------------------------------------------------------------

	; 30/12/2024
clearscreen:
	; fast clear
	; 320*200, 256 colors
	mov	edi, 0A0000h
	mov	ecx, (320*200*1)/4
	xor	eax, eax
	rep	stosd
	retn

; -------------------------------------------------------------

	; 30/12/2024 (VGA Mode 13h, 320*200 pixels, 256 colors)
	; 26/12/2024
	; 21/12/2024
drawplayingscreen:
	mov	ebp, PlayingScreen
	;mov	esi, 0 ; row 0, column 0
	mov	esi, 00020000h ; row 2, column 0 ; top margin = 2
p_d_x:
	mov	byte [columns], 40
	mov	dh, 01h ; 8x8 system font
p_d_x_n:
	mov	dl, [ebp]
	and	dl, dl
	jz	short p_d_x_ok

	; sysvideo system call
	; BH = 01h = VGA graphics (0A0000h) data transfers
	; BL = 0Fh = write character/font
	; DH = 01h = 8*8 system font 
	; CL = 0Fh = color (white)
	; ESI = cursor/writing position (pixels)
	;	HW = row, SI = column

	sys	_video, 010Fh, 0Fh

	inc	ebp
	add	si, 8 ; next char pos
	dec	byte [columns]
	jnz	short p_d_x_n	; next column
	xor	si, si
	add	esi, 00080000h	; next row ; 8*8
	jmp	short p_d_x
p_d_x_ok:
	retn

; -------------------------------------------------------------

	; 21/12/2024
set_text_mode:
	xor    ah, ah
	mov    al, 3                        
 	;int   10h ; al = 03h text mode, int 10 video
	int    31h ; TRDOS 386 - Video interrupt
	retn

; -------------------------------------------------------------

	; 02/12/2024
Player_Quit@:
	pop	eax ; return addr (call PlayWav@)
	
	; 29/11/2024
Player_Quit:
	jmp	 terminate

; -------------------------------------------------------------

	; 06/01/2025 (cgaplay2.s)
	; 02/01/2025 (cgaplay2.asm)
	; 20/12/2024
	; 15/12/2024 (sb16play.s)
	; ref: playwav4.s, 18/08/2020
	; 24/11/2024 (sb16play.asm)
PlayWav:
	; load 32768 bytes into audio buffer
	;mov	edi, audio_buffer ; 16/12/2024
	call	loadFromFile
	; 18/12/2024
	;jc	error_exit
	;mov	byte [half_buff], 1 ; (DMA) Buffer 1

	mov	eax, [count]
	add	[LoadedDataBytes], eax

	test    byte [flags], ENDOFFILE  ; end of file ?
	jnz	short _pw1 ; yes
			   ; bypass filling dma half buffer 2

	; bh = 16 : update (current, first) dma half buffer
	; bl = 0  : then switch to the next (second) half buffer
	sys	_audio, 1000h

	; [audio_flag] = 1 (in TRDOS 386 kernel)

	; audio_buffer must be filled again after above system call
	; (Because audio interrupt will be generated by sound hardware
	; at the end of the first half of dma buffer.. so,
	; the second half must be ready. 'sound_play' will use it.)

	;mov	edi, audio_buffer ; 16/12/2024
	call	loadFromFile
	;jc	short p_return

	mov	eax, [count]
	add	[LoadedDataBytes], eax

	; 06/01/2025
_pw1:	
	; 07/01/2025
	; 20/12/2024
	; 25/11/2024
	call	SB16Init_play	; initialize SB16 card
				; set sample rate, start to play
	jc	init_err

	; 08/01/2025
	; 20/12/2024
	test    byte [flags], ENDOFFILE ; end of file
	jnz	short _pw2	; yes

	; 20/12/2024	
	;mov     edi, audio_buffer
	call	loadFromFile
	;jc	short p_return
	;xor	byte [half_buffer], 1

	mov	eax, [count]
	add	[LoadedDataBytes], eax
_pw2:
	mov	byte [SRB], 0

; -------------------------------------------

	; 07/01/2025
	; 06/01/2025 (cgaplay2.s)
	; 30/12/2024 (cgaplay.s)
	; 29/12/2024 (vgaplay3.s)
	; 18/12/2024 (ac97play.s)
	; 01/12/2024 (32bit)
	; 29/11/2024
	; 16/12/2024 (TRDOS 386)
	; 29/11/2024
	; 27/11/2024
	; 24/11/2024
TuneLoop: 
	; 30/05/2024
	; 18/11/2023 (ich_wav4.asm)
	; 08/11/2023
	; 06/11/2023

	; 20/12/2024
	call	UpdateProgressBar

tLWait:
	; 07/12/2024 (playwav9.s)
	; 18/11/2024
	cmp	byte [stopped], 0
	; 24/11/2024
	jna	short tL1

	;;;
	; 09/12/2024 (ac97play.s)
	cmp	byte [stopped], 3
	jnb	_exitt_
	;;;
	call	checkUpdateEvents
	jc	_exitt_
	;;;
	; 29/11/2024
	cmp	byte [command], 'N'
	je	_exitt_
	cmp	byte [command], 'P'
	je	_exitt_
	;;;
	cmp	byte [tLO], '0'
	je	short tLWait
	call	tLZ
	mov	byte [tLO], '0'
	jmp	short tLWait

tL1:
	; 16/12/2024
	; 07/12/2024 (playwav9.s)
	; 27/11/2024
	; Check audio interrupt status
	cmp	byte [SRB], 0
	ja	short tL3
tL2:
	call	checkUpdateEvents
	jc	_exitt_
	jmp	short tLWait
tL3:
	; 07/01/2025
	xor	byte [half_buffer], 1
	; 07/12/2024
	mov	byte [SRB], 0

	; 16/12/2024
	;mov	edi, audio_buffer
	call	loadFromFile
	jc	short _exitt_	; end of file

	; 26/11/2024
	mov	al, [half_buffer]
	add	al, '1'
	; 19/11/2024
	mov	[tLO], al
	call	tL0
	; 16/12/2024 (TRDOS 386)
	; 24/11/2024
	; 14/11/2024
	mov	eax, [count]
	add	[LoadedDataBytes], eax

	; 27/11/2024
	jmp	short tL2

_exitt_:
	; 24/11/2024
	call	sb16_stop

	;;;
	; 14/11/2024
	call	UpdateProgressBar
	;;;


	; 18/11/2024
tLZ:
	; 30/05/2024
	mov	al, '0'

	;add	al, '0'
	;call	tL0
	;
	;retn
	; 06/11/2023
	;jmp	short tL0
	;retn

tL0:
	; 30/12/2024 (cgaplay.s)
	; 29/05/2024 (TRDOS 386)
	; 08/11/2023
	; 05/11/2023
	; 17/02/2017 - Buffer switch test (temporary)
	; 06/11/2023
	; al = buffer indicator ('1', '2' or '0' -stop- )

	; 30/12/2024 (video mode 13h modification)
	; (320*200, 256 colors)
	;;;
	mov	dl, al ; character
	mov	edi, 0A0000h

	mov	ebx, 8 ; 8 pixels (8*8 pixels font)

	mov	al, 0Ch ; red
tL0_1:
	;mov	ecx, 8 ; 8 pixels (8*8 pixels font)
	mov	ecx, 7
tL0_2:
	stosb
	dec	ecx
	jnz	short tL0_2
	dec	ebx
	jz	short tL0_3
	;add	edi, 320-8 ; next line
	add	edi, 320-7
	jmp	short tL0_1
tL0_3:
	; write system font
	mov	dh, 01h
	;mov	dl, al ; character
	xor	esi, esi ; = row 0, column 0
	sys	_video, 010Fh, 0Eh ; yellow
	;;;

	retn

; -------------------------------------------

	; 06/01/2025 (cgaplay2.s) -TRDOS386-
	; 02/01/2025 (cgaplay2.asm) -DOS-
	; 18/12/2024
	; 16/12/2024 (sb16play.s)
	; 07/12/2024 (playwav9.s)

SetMasterVolume:
	;cmp	al, 31
	;ja	short setvolume_ok
	mov	[volume], al  ; max = 0, min = 31
SetMasterVolume@:
	; al = [volume]
	mov	ah, 31
	sub	ah, al
	mov	al, ah

	; Set Master Volume Level (BL=0 or 80h)
	; 	for next playing (BL>=80h)
	;sys	_audio, 0B80h, eax
	sys	_audio, 0B00h, eax

setvolume_ok:
	retn

; -------------------------------------------

	; 16/12/2024 (sb16play.s)
	; Ref: playwav4.s (18/08/2020)
	; Detect (BH=1) SB16 (BL=1) Audio Card (or Emulator)
DetectSB16:
        sys	_audio, 101h
	retn

; --------------------------------------------

; 16/12/2024 (sb16play.s)
; 07/12/2024 (playwav9.s)
; Ref: TRDOS 386 v2.0.9, trdosk8.s (18/09/2024)
;		'sysaudio' system call (23/08/2024)
; 18/11/2024
; Ref: TRDOS 386 v2.0.9, audio.s, Erdogan Tan, 06/06/2024

sb16_stop:
	; 18/11/2024
	mov	byte [stopped], 2
	; 07/12/2024
	sys	_audio, 0700h
	retn

sb16_pause:
	; 18/11/2024
	mov	byte [stopped], 1 ; paused
	; 07/12/2024
	sys	_audio, 0500h
	retn

sb16_play:
sb16_continue:
	; continue to play (after pause)
	; 18/11/2024
	mov	byte [stopped], 0
	; 07/12/2024
	sys	_audio, 0600h
	retn

; ----------------------------------
	
	; 26/12/2024
	; 07/12/2024
	; 01/12/2024
	; 14/11/2024
	; INPUT: ds:dx = file name address
	; OUTPUT: [filehandle] = ; -1 = not open
openFile:
	; 26/12/2024
	; 01/12/2024
	sys	_open, edx, 0
	; 07/12/2024
	;sys	_open, wav_file_name, 0
	jnc	short _of1

	mov	eax, -1
	; cf = 1 -> not found or access error
_of1:
	mov	[filehandle], eax
	retn

; ----------------------------------

; close the currently open file

	; 01/12/2024
	; 14/11/2024
	; INPUT: [filehandle] ; -1 = not open
	; OUTPUT: none
closeFile:
	cmp	dword [filehandle], -1
	jz	short _cf1
	; 01/12/2024
	sys	_close, [filehandle]
	;mov 	dword [filehandle], -1
_cf1:
	retn

; ----------------------------------

	; 01/12/2024
	; 14/11/2024 - Erdogan Tan
getWAVParameters:
; reads WAV file header(s) (44 bytes) from the .wav file.
; entry: none - assumes file is already open
; exit: ax = sample rate (11025, 22050, 44100, 48000)
;	cx = number of channels (mono=1, stereo=2)
;	dx = bits per sample (8, 16)
;	bx = number of bytes per sample (1 to 4)

        ;mov	dx, WAVFILEHEADERbuff
	;mov	bx, [filehandle]
        ;mov	cx, 44			; 44 bytes
	;mov	ah, 3Fh
        ;int	21h
	;jc	short gwavp_retn
	; 01/12/2024 (TRDOS 386)
	sys	_read, [filehandle], WAVFILEHEADERbuff, 44
	jc	short gwavp_retn

	cmp	eax, 44
	jb	short gwavp_retn

	cmp	dword [RIFF_Format], 'WAVE'
	jne	short gwavp_stc_retn

	cmp	word [WAVE_AudioFormat], 1 ; Offset 20, must be 1 (= PCM)
	;jne	short gwavp_stc_retn
	je	short gwavp_retn ; 15/11/2024

	; 15/11/2024
	;mov	cx, [WAVE_NumChannels]	; return num of channels in CX
        ;mov    ax, [WAVE_SampleRate]	; return sample rate in AX
	;mov	dx, [WAVE_BitsPerSample] 
					; return bits per sample value in DX
	;mov	bx, [WAVE_BlockAlign]	; return bytes per sample in BX
;gwavp_retn:
        ;retn

gwavp_stc_retn:
	stc
gwavp_retn:
	retn

; /////

; 16/12/2024 (sb16play.s)
; --------------------------------------------------------
; 07/12/2024 (playwav9.s)
; --------------------------------------------------------
; ref: playwav8.s (04/06/2024)

audio_int_handler:
	; 18/08/2020 (14/10/2020, 'wavplay2.s')

	; 07/12/2024
	;mov	al, [stopped]
	;cmp	al, 2
	;je	short _callback_retn

	; 18/08/2020
	;mov	byte [SRB], 1
	; 07/12/2024
	inc	byte [SRB]

;_callback_retn:
	sys	_rele ; return from callback service 
	; we must not come here !
	sys	_exit
; --------------------------------------------------------
; 07/12/2024
; --------------------------------------------------------

; /////
	; 16/12/2024 (sb16play.s)
	; 14/12/2024 (playwav9.s)
	; 07/12/2024
	; 01/12/2024
	; 24/11/2024 (SB16 version of playwav8.asm -> playwav9.asm)
	; 30/05/2024 (ich_wav4.asm, 19/05/2024)
loadFromFile:
	; 18/12/2024
	mov	dword [count], 0

	; 07/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff_0		; no
	stc
	retn

lff_0:
	; 16/12/2024
	mov	edi, audio_buffer

	; 14/12/2024 (playwav9.s)
	;sys 	_read, [filehandle], esi, [loadsize]
	; 16/12/2024
	sys	_read, [filehandle], edi, BUFFERSIZE
	jc	short lff_4 ; error !

	; 20/12/2024
	mov	[count], eax

	; 16/12/2024
	cmp	eax, edx
	je	short endLFF
	; edi = buffer address
	add	edi, eax
lff_3:
	; 20/12/2024
	mov	ecx, edx ; BUFFERSIZE
	;call    padfill		; blank pad the remainder
	;;;
	; 20/12/2024
padfill:
	; 16/12/2024 (sb16play.s)
	;   edi = buffer offset
	;   ecx = buffer size
	;   eax = loaded bytes
	; 24/11/2024 (sb16play.asm)
	;   di = offset (to be filled with ZEROs)
	;   es = ds = cs
	;   ax = di = number of bytes loaded
	;   cx = buffer size (> loaded bytes)
	sub	ecx, eax
	xor	eax, eax
	cmp	byte [WAVE_BitsPerSample], 8
	ja	short padfill@
	mov	al, 80h
padfill@:
	rep	stosb
	;retn
	;;;

        ;clc				; don't exit with CY yet.
        or	byte [flags], ENDOFFILE	; end of file flag
endLFF:
        retn
lff_4:
	; 08/11/2023
	mov	al, '!'  ; error
	call	tL0

	; 16/12/2024
	sub	eax, eax
	;mov	ecx, edx ; BUFFERSIZE
	jmp	short lff_3

; /////

; --------------------------------------------------------
; --------------------------------------------------------
	
write_audio_dev_info:
	; 30/05/2024
     	;sys_msg msgAudioCardInfo, 0Fh
	; 01/12/2024
	sys 	_msg, msgAudioCardInfo, 255, 0Fh
	retn

; --------------------------------------------------------

	; 20/12/2024 (playwavx.s, sb16play.s)
write_sb16_dev_info:
	; 27/11/2024
	; 24/11/2024 (sb16play.asm)

	mov	eax, [audio_io_base]
	xor	ebx, ebx
	mov	bl, al
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [ebx+hex_chars]
	mov	[msgBasePort+2], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [ebx+hex_chars]
	mov	[msgBasePort+1], al
	mov	bl, ah
	;and	bl, 0Fh
	mov	al, [ebx+hex_chars]
	mov	[msgBasePort], al

	;xor	eax, eax
	; 27/11/2024
	mov	al, [audio_intr]
	;mov	cl, 10
	;div	cl
	;add	ah, 30h
	;mov	[msgIRQ], ah
	; 25/11/2024
	add	al, 30h
	mov	[msgIRQ], al

	call 	clear_window
	;mov	dh, 13
	; 02/01/2025
	mov	dh, 12
	mov	dl, 0
	call	setCursorPosition

	; 07/01/2025
	mov	ebp, msgSB16Info ; message
	;mov	cl, 07h ; color 
	;call	sys_gmsg
	;retn
	;;;

; --------------------------------------------------------

	; 30/12/2024 (Video Mode 13h)
	; (write message in VGA/CGA mode)
	; 22/12/2024
	; 21/12/2024
	; (write message in VGA/VESA-VBE mode)
sys_gmsg:
	mov	al, [ebp]
	and	al, al
	jz	short sys_gmsg_ok
	cmp	al, 20h
	jnb	short sys_gmsg_3
	cmp	al, 13
	jne	short sys_gmsg_2
	; carriege return, move cursor to column 0
	mov	word [screenpos], 0
sys_gmsg_1:
	inc	ebp
	jmp	short sys_gmsg
sys_gmsg_2:
	cmp	al, 10
	jne	short sys_gmsg_ok ; 22/12/2024
	; line feed, move cursor to next row
	;add	word [screenpos+2], 16
	; 30/12/2024
	add	word [screenpos+2], 8
	jmp	short sys_gmsg_1
sys_gmsg_3:
	mov	esi, [screenpos]
		; hw = (cursor) row
		; si = (cursor) column
	mov	ecx, 07h ; gray (light)
	call	write_character
	add	esi, 8
	;;;
	;cmp	si, 640
	; 30/12/2024 (cgaplay.s)
	cmp	si, 320
	jb	short sys_gmsg_5
	shr	esi, 16
	;add	si, 16
	;cmp	si, 480
	; 30/12/2024
	add	si, 8
	cmp	si, 200
	jb	short sys_gmsg_4
	xor	esi, esi
sys_gmsg_4:
	shl	esi, 16
	;;;
sys_gmsg_5:
	mov	[screenpos], esi
	inc	ebp
	jmp	short sys_gmsg
sys_gmsg_ok:
	retn
	;;;

; --------------------------------------------------------

; --------------------------------------------------------
; 16/12/2024 - Sound Blaster 16 initialization & play
; --------------------------------------------------------

	; 16/12/2024 - sb16play.s (TRDOS 386)
	; 18/08/2024 - playwav4.s (TRDOS 386)
SB16Init_play:
SB16_play@:
	; 16/12/2024
	mov	ecx, 31 ; 1Fh
	sub	cl, [volume] ; initial value = 2
			     ; cl = 1Dh (initial)
	mov	ch, cl

	; Set Master Volume Level (BL=0 or 80h)
	; 	for next playing (BL>=80h)
	;;sys	_audio, 0B80h, 1D1Dh
	;sys	_audio, 0B00h, 1D1Dh
	; 16/12/2024
	sys	_audio, 0B00h

	; 16/12/2024
	; Start	to play
	mov	al, [WAVE_BitsPerSample]
	shr	al, 4 ; 8 -> 0, 16 -> 1
	shl	al, 1 ; 16 -> 2, 8 -> 0
	mov	bl, [WAVE_NumChannels]
	dec	bl
	or	bl, al
 	mov	cx, [WAVE_SampleRate]
	mov	bh, 4 ; start to play
	sys	_audio

_init_err:
c4ue_ok:
	retn

; --------------------------------------------------------
; 14/11/2024 - Erdogan Tan
; --------------------------------------------------------

	; 06/01/2025 (cgaplay2.s)
	; 18/12/2024
	; 16/12/2024 (sb16play.s)
	; 07/12/2024
	; 01/12/2024 (32bit registers)
	; 29/11/2024
checkUpdateEvents:
	call	check4keyboardstop
	jc	short c4ue_ok

	; 18/11/2024
	push	eax ; *
	or	eax, eax
	jz	c4ue_cpt

	; 18/11/2024
	cmp	al, 20h ; SPACE (spacebar) ; pause/play
	jne	short c4ue_chk_s
	cmp	byte [stopped], 0
	ja	short c4ue_chk_ps
	; 24/11/2024
	; pause
	call	sb16_pause
	jmp	c4ue_cpt
c4ue_chk_ps:
	cmp	byte [stopped], 1
	ja	short c4ue_replay
	; continue to play (after a pause)
	call	sb16_play	; 24/11/2024
	jmp	c4ue_cpt
c4ue_replay:
	; 19/11/2024
	pop	eax ; *
	pop	eax ; return address
	; 07/02/2024
	;mov	al, [volume]
	;call	SetmasterVolume
	mov	byte [stopped], 0
	; 24/11/2024
	mov	byte [half_buffer], 1
	call	move_to_beginning
	jmp	PlayWav

c4ue_chk_s:
	cmp	al, 'S'	; stop
	jne	short c4ue_chk_fb
	cmp	byte [stopped], 0
	ja	c4ue_cpt ; Already stopped/paused
	call	sb16_stop	; 24/11/2024
	; 19/11/2024
	mov	byte [tLO], 0
	jmp	c4ue_cpt

c4ue_chk_fb:
	; 17/11/2024
	cmp	al, 'F'
	jne	short c4ue_chk_b
	call 	Player_ProcessKey_Forwards
	jmp	c4ue_cpt

c4ue_chk_b:
	cmp	al, 'B'
	;;jne	short c4ue_cpt
	; 19/11/2024
	;jne	short c4ue_chk_h
	; 25/12/2024
	; 29/11/2024
	jne	short c4ue_chk_n
	call 	Player_ProcessKey_Backwards
	jmp	short c4ue_cpt

	;;;
	; 25/12/2024
	; 29/11/2024
c4ue_chk_n:
	cmp	al, 'N'
	je	short c4ue_nps
c4ue_chk_p:
	cmp	al, 'P'
	jne	short c4ue_chk_h
c4ue_nps:
	mov	byte [stopped], 3
	jmp	short c4ue_cpt
	;;;

c4ue_chk_h:
	; 19/11/2024
	cmp	al, 'H'
	jne	short c4ue_chk_cr
	mov	byte [wpoints], 0
	; 20/12/2024
	; 18/12/2024
	call 	write_sb16_dev_info
	; 30/12/2024
	jmp	short c4ue_cpt
c4ue_chk_cr:
	;;;
	; 24/12/2024 (wave lighting points option)
	;mov	ah, [wpoints]
	; 30/12/2024
	xor	ebx, ebx
	mov	bl, [wpoints]
	cmp	al, 'G'
	je	short c4ue_g
	; 19/11/2024
	cmp	al, 0Dh ; ENTER/CR key
	jne	short c4ue_cpt
	; 23/11/2024
	;xor	ebx, ebx
	; 30/12/2024
	;mov	bl, ah ; 24/12/2024
	inc	bl
c4ue_g:	; 30/12/2024
	and	bl, 07h
	jnz	short c4ue_sc
	inc	ebx
c4ue_sc:
	mov	[wpoints], bl
	; 30/12/2024
	mov	al, [ebx+colors-1] ; 1 to 7
	; 24/12/2024
	mov	[ccolor], al
	; 30/12/2024
	call	clear_window
	;;;
c4ue_cpt:
	; 24/12/2024
	; 18/11/2024
	pop	ecx ; *
	;;;
	; 29/12/2024
	; 24/12/2024 (skip wave lighting if data is not loaded yet)
	;cmp	byte [SRB], 0
	;ja	short c4ue_vb_ok
	;;;
	; 01/12/2024 (TRDOS 386)
	sys	_time, 4 ; get timer ticks (18.2 ticks/second),
	; 24/12/2024
	; 18/11/2024
	;pop	ecx ; *
	; 01/12/2024
	cmp	eax, [timerticks]
	;je	short c4ue_ok
	; 18/11/2024
	je	short c4ue_skip_utt
c4ue_utt:	
	; 01/12/2024
	mov	[timerticks], eax
	jmp	short c4ue_cpt_@

	; 30/12/2024
c4ue_vb_ok:
	retn

c4ue_skip_utt:
	; 18/11/2024
	and	ecx, ecx
	jz	short c4ue_vb_ok
c4ue_cpt_@:
	; 18/11/2024
	cmp	byte [stopped], 0
	ja	short c4ue_vb_ok
	
	call	CalcProgressTime

	;cmp	ax, [ProgressTime]
	; 01/12/2024
	cmp	eax, [ProgressTime]
	;je	short c4ue_vb_ok
			; same second, no need to update
	; 23/11/2024
	je	short c4ue_uvb

	;call	UpdateProgressTime
	;call	UpdateProgressBar@
	call	UpdateProgressBar

	; 23/11/2024
c4ue_uvb:
	cmp	byte [wpoints], 0
	jna	short c4ue_vb_ok

	; 30/12/2024
	;call	UpdateWavePoints
	;retn

	; 08/01/2025
	call	dword [UpdateWavePoints]
	retn	

; --------------------------------------------------------
; 27/12/2024 - Erdogan Tan
; --------------------------------------------------------

	; 08/01/2025
	; 06/01/2025 (cgaplay2.s) -SB16- (32bit regs)
	; 02/01/2025 (cgaplay2.asm) -SB16-
	; 01/01/2025 (cgaplay.asm, 16bit registers)
	; 30/12/2024 (cgaplay.s) -AC97-
	;  * 320*200 pixels, 256 colors
	;  * 64 volume levels
	; 29/12/2024
	; 27/12/2024 (DMA Buffer Tracking)
	; 26/12/2024
	; 24/12/2024
;UpdateWavePoints:
	; 06/01/2025
UpdateWavePoints_16s:
	; 08/01/2025
	call	get_current_sounddata
	;
	mov	esi, prev_points
	cmp	dword [esi], 0
	jz	short lights_off_ok
	;mov	ecx, 640
	; 30/12/2024
	mov	ecx, 320
light_off:
	lodsd
	; eax = wave point (lighting point) address
	mov	byte [eax], 0 ; black point (light off)
	loop	light_off	

lights_off_ok:

; 08/01/2025
%if 0
	; 29/12/2024
	cmp	byte [tLO],'2'
	jne	short lights_on_buff_1
lights_on_buff_2:
	; 06/01/2025
	mov	edx, wav_buffer2
	jmp	short lights_on
lights_on_buff_1:
	; 06/01/2025
	mov	edx, wav_buffer1
lights_on:
	cmp	[pbuf_s], edx
	jne	short lights_on_2
	mov	ebx, [wpoints_dif]
	mov	esi, [pbuf_o]
	;mov	ecx, [buffersize] ; bytes
	; 06/01/2025
	mov	ecx, BUFFERSIZE
	sub	ecx, ebx ; sub ecx, [wpoints_dif]
	add	esi, ebx
	jc	short lights_on_1
	cmp	esi, ecx
	jna	short lights_on_3
lights_on_1:
	mov	esi, ecx
	jmp	short lights_on_3

lights_on_2:
	; 29/12/2024
	mov	[pbuf_s], edx
	xor	esi, esi ; 0
lights_on_3:
	mov	[pbuf_o], esi
	; 29/12/2024
	;add	esi, [pbuf_s]
	add	esi, edx
%else
	; 08/01/2025
	mov	esi, sounddata
%endif
	;mov	ecx, 640
	; 30/12/2024
	mov	ecx, 320
	mov	ebp, ecx
	; 26/12/2024
	mov	edi, prev_points
	;mov	ebx, [graphstart] ; start (top) line
	; 06/01/2025
	mov	ebx, 0A0000h+(11*8*320)+(4*320)
lights_on_4:
	xor	eax, eax ; 0
	lodsw	; left
	add	ah, 80h
	mov	edx, eax
	lodsw	; right
	;add	ax, dx
	add	ah, 80h
	;;shr	eax, 9	; 128 volume levels
	; 01/01/2025
	add	eax, edx
	;;shr	eax, 10	; (L+R/2) & 128 volume levels
	;shr	eax, 9	; (L+R/2) & 256 volume levels
	; 30/12/2024
	shr	eax, 11	; (L+R/2) & 64 volume levels
	; * 320 row  ; 30/12/2024
	mul	ebp	; * 640 (row) 
	add	eax, ebx ; + column
	mov	dl, [ccolor]
	mov	[eax], dl ; pixel (light on) color
	stosd		; save light on addr in prev_points
	inc	ebx
	loop	lights_on_4
	retn

; -------------------------

	; 08/01/2025
	; 06/01/2025 (cgaplay2.s, SB16, TRDOS386)
	; 02/01/2025 (cgaplay2.asm, SB16, RetroDOS)
	; 01/01/2025 (cgaplay.asm, AC97, RetroDOS)
	; 30/12/2024 (cgaplay.s, AC97, TRDOS386)
	;  * 320*200 pixels, 256 colors
	;  * 64 volume levels
UpdateWavePoints_16m:
	; 08/01/2025
	call	get_current_sounddata
	;
	mov	esi, prev_points
	cmp	dword [esi], 0
	jz	short lights_off_16m_ok
	;mov	ecx, 640
	; 30/12/2024
	mov	ecx, 320
light_16m_off:
	lodsd
	; eax = wave point (lighting point) address
	mov	byte [eax], 0 ; black point (light off)
	loop	light_16m_off

lights_off_16m_ok:

; 08/01/2025
%if 0
	; 29/12/2024
	cmp	byte [tLO],'2'
	jne	short lights_16m_on_buff_1
lights_16m_on_buff_2:
	; 06/01/2025
	mov	edx, wav_buffer2
	jmp	short lights_16m_on
lights_16m_on_buff_1:
	; 06/01/2025
	mov	edx, wav_buffer1
lights_16m_on:
	cmp	[pbuf_s], edx
	jne	short lights_16m_on_2
	mov	ebx, [wpoints_dif]
	mov	esi, [pbuf_o]
	; 06/01/2025
	mov	ecx, BUFFERSIZE
	sub	ecx, ebx ; sub ecx, [wpoints_dif]
	add	esi, ebx
	jc	short lights_16m_on_1
	cmp	esi, ecx
	jna	short lights_16m_on_3
lights_16m_on_1:
	mov	esi, ecx
	jmp	short lights_16m_on_3

lights_16m_on_2:
	; 06/01/2025
	mov	[pbuf_s], edx
	xor	esi, esi ; 0
lights_16m_on_3:
	mov	[pbuf_o], esi
	; 29/12/2024
	;add	esi, [pbuf_s]
	add	esi, edx
%else
	; 08/01/2025
	mov	esi, sounddata
%endif
	;mov	ecx, 640
	; 30/12/2024
	mov	ecx, 320
	mov	ebp, ecx
	; 26/12/2024
	mov	edi, prev_points
	; 06/01/2025
	mov	ebx, 0A0000h+(11*8*320)+(4*320)
lights_16m_on_4:
	; 06/01/2025
	; 02/01/2025 (16bit mono play modifications)
	xor	eax, eax ; 0
	lodsw
	add	ah, 80h
	; 06/01/2025
	shr	eax, 10	; 64 volume levels
	; * 320 row  ; 30/12/2024
	mul	ebp	; * 640 (row) 
	add	eax, ebx ; + column
	mov	dl, [ccolor]
	mov	[eax], dl ; pixel (light on) color
	stosd		; save light on addr in prev_points
	inc	ebx
	loop	lights_16m_on_4
	retn

; -------------------------

	; 06/01/2025
	; 02/01/2025
UpdateWavePoints_8s:
	; 08/01/2025
	call	get_current_sounddata
	;
	mov	esi, prev_points
	cmp	dword [esi], 0
	jz	short lights_off_8s_ok
	;mov	ecx, 640
	; 30/12/2024
	mov	ecx, 320
light_8s_off:
	lodsd
	; eax = wave point (lighting point) address
	mov	byte [eax], 0 ; black point (light off)
	loop	light_8s_off

lights_off_8s_ok:

; 08/01/2025
%if 0
	; 29/12/2024
	cmp	byte [tLO],'2'
	jne	short lights_8s_on_buff_1
lights_8s_on_buff_2:
	; 06/01/2025
	mov	edx, wav_buffer2
	jmp	short lights_8s_on
lights_8s_on_buff_1:
	; 06/01/2025
	mov	edx, wav_buffer1
lights_8s_on:
	cmp	[pbuf_s], edx
	jne	short lights_8s_on_2
	mov	ebx, [wpoints_dif]
	mov	esi, [pbuf_o]
	; 06/01/2025
	mov	ecx, BUFFERSIZE
	sub	ecx, ebx ; sub ecx, [wpoints_dif]
	add	esi, ebx
	jc	short lights_8s_on_1
	cmp	esi, ecx
	jna	short lights_8s_on_3
lights_8s_on_1:
	mov	esi, ecx
	jmp	short lights_8s_on_3

lights_8s_on_2:
	; 06/01/2025
	mov	[pbuf_s], edx
	xor	esi, esi ; 0
lights_8s_on_3:
	mov	[pbuf_o], esi
	; 29/12/2024
	;add	esi, [pbuf_s]
	add	esi, edx
%else
	; 08/01/2025
	mov	esi, sounddata
%endif
	;mov	ecx, 640
	; 30/12/2024
	mov	ecx, 320
	mov	ebp, ecx
	; 26/12/2024
	mov	edi, prev_points
	; 06/01/2025
	mov	ebx, 0A0000h+(11*8*320)+(4*320)
lights_8s_on_4:
	; 06/01/2025
	; 02/01/2025 (8bit stereo play modifications)
	xor	eax, eax ; 0
	lodsb	; left
	mov	edx, eax
	lodsb	; right
	add	eax, edx
	shr	eax, 1 ; (L+R/2)
	sub	al, 255	; max. value will be shown on top
	shr	eax, 2	; 64 volume levels
	; * 320 row  ; 30/12/2024
	mul	ebp	; * 640 (row) 
	add	eax, ebx ; + column
	mov	dl, [ccolor]
	mov	[eax], dl ; pixel (light on) color
	stosd		; save light on addr in prev_points
	inc	ebx
	loop	lights_8s_on_4
	retn

; -------------------------

	; 06/01/2025
	; 02/01/2025
UpdateWavePoints_8m:
	; 08/01/2025
	call	get_current_sounddata
	;
	mov	esi, prev_points
	cmp	dword [esi], 0
	jz	short lights_off_8m_ok
	;mov	ecx, 640
	; 30/12/2024
	mov	ecx, 320
light_8m_off:
	lodsd
	; eax = wave point (lighting point) address
	mov	byte [eax], 0 ; black point (light off)
	loop	light_8m_off

lights_off_8m_ok:

; 08/01/2025
%if 0
	; 29/12/2024
	cmp	byte [tLO],'2'
	jne	short lights_8m_on_buff_1
lights_8m_on_buff_2:
	; 06/01/2025
	mov	edx, wav_buffer2
	jmp	short lights_8m_on
lights_8m_on_buff_1:
	; 06/01/2025
	mov	edx, wav_buffer1
lights_8m_on:
	cmp	[pbuf_s], edx
	jne	short lights_8m_on_2
	mov	ebx, [wpoints_dif]
	mov	esi, [pbuf_o]
	; 06/01/2025
	mov	ecx, BUFFERSIZE
	sub	ecx, ebx ; sub ecx, [wpoints_dif]
	add	esi, ebx
	jc	short lights_8m_on_1
	cmp	esi, ecx
	jna	short lights_8m_on_3
lights_8m_on_1:
	mov	esi, ecx
	jmp	short lights_8m_on_3

lights_8m_on_2:
	; 06/01/2025
	mov	[pbuf_s], edx
	xor	esi, esi ; 0
lights_8m_on_3:
	mov	[pbuf_o], esi
	; 29/12/2024
	;add	esi, [pbuf_s]
	add	esi, edx
%else
	; 08/01/2025
	mov	esi, sounddata
%endif
	;mov	ecx, 640
	; 30/12/2024
	mov	ecx, 320
	mov	ebp, ecx
	; 26/12/2024
	mov	edi, prev_points
	; 06/01/2025
	mov	ebx, 0A0000h+(11*8*320)+(4*320)
lights_8m_on_4:
	; 06/01/2025
	; 02/01/2025 (16bit mono play modifications)
	xor	eax, eax ; 0
	lodsb
	sub	al, 255	; max. value will be shown on top
	shr	eax, 2	; 64 volume levels
	; * 320 row  ; 30/12/2024
	mul	ebp	; * 640 (row) 
	add	eax, ebx ; + column
	mov	dl, [ccolor]
	mov	[eax], dl ; pixel (light on) color
	stosd		; save light on addr in prev_points
	inc	ebx
	loop	lights_8m_on_4
	retn

; --------------------------------------------------------
; 08/01/2025 - Get Current Sound Data For Graphics
; --------------------------------------------------------

	; 08/01/2025
get_current_sounddata:
	sys	_audio,	0F00h, [sd_count], sounddata
	retn

; --------------------------------------------------------
; 19/05/2024 - (playwav4.asm) ich_wav4.asm
; --------------------------------------------------------

	; 06/01/2025
	; 29/12/2024
	; 25/12/2024
	; 07/12/2024
	; 01/12/2024 (TRDOS 386)
	; 29/11/2024
check4keyboardstop:
	; 19/05/2024
	; 08/11/2023
	; 04/11/2023
	mov	ah, 1
	;int	16h
	; 01/12/2024 (TRDOS 386 keyboard interrupt)
	int	32h
	;clc
	jz	short _cksr

	xor	ah, ah
	;int	16h
	; 01/12/2024 (TRDOS 386 keyboard interrupt)
	int	32h

	; 25/12/2024
	; 29/11/2024
	;mov	[command], al

	;;;
	; 19/05/2024 (change PCM out volume)
	cmp	al, '+'
	jne	short p_1
	
	mov	al, [volume]
	cmp	al, 0
	jna	short p_3
	dec	al
	jmp	short p_2
p_1:
	cmp	al, '-'
	jne	short p_4

	mov	al, [volume]
	cmp	al, 31
	jnb	short p_3
	inc	al
p_2:
	mov	[volume], al
	; 14/11/2024
	;call	SetPCMOutVolume
	; 16/12/2024 (TRDOS 386, SB16)
	; 15/11/2024 (QEMU)
	;call	SetMasterVolume
	; 18/12/2024
	call	SetMasterVolume@
	;call	UpdateVolume
	;;clc
	;retn
	jmp	UpdateVolume
_cksr:		; 19/05/2024
	; 18/12/2024
	xor	eax, eax
	;clc
p_3:
	retn
p_4:
	; 17/11/2024
	cmp	ah, 01h  ; ESC
    	je	short p_q
	;cmp	ax, 2E03h ; 21/12/2024 
	cmp	al, 03h  ; CTRL+C
	je	short p_q

	; 18/11/2024
	cmp	al, 20h
	je	short p_r

	; 19/11/2024
	cmp	al, 0Dh ; CR/ENTER
	je	short p_r

	and	al, 0DFh

	; 25/12/2024
	; 29/11/2024
	mov	[command], al

	;cmp	al, 'B'
	;je	short p_r
	;cmp	al, 'F'
	;je	short p_r

	; 29/11/2024
	;cmp	al, 'N'
	;je	short p_r
	;cmp	al, 'P'
	;je	short p_r

	cmp	al, 'Q'
	;je	short p_q
	je	short p_quit ; 29/11/2024

	clc
	retn

	;;;
;_cskr:	
p_q:
	; 27/12/2024
	mov	byte [command], 'Q'
p_quit:
	stc
p_r:
	retn

; 29/05/2024
; 19/05/2024
volume: 
	;db	02h
; 26/12/2024
	db	03h

; --------------------------------------------------------

	; 30/12/2024
	; simulate cursor position in VGA mode 13h
	; ! for 320*200, 256 colors (1 byte/pixel) !
setCursorPosition:
	; dh = Row
	; dl = Column
	
	xor	eax, eax
	; row height is 8 pixels (8*8)
	mov	al, dh
	shl	eax, 3
	add	ax, 2	; top margin
	shl	eax, 16
	mov	al, dl	; * 8 ; character width = 8 pixels
	shl	ax, 3
			; hw = row, ax = column
	mov	[screenpos], eax
	; 22/12/2024
	xor	eax, eax
	retn
	
; --------------------------------------------------------
; 14/11/2024
; (Ref: player.asm, out_cs.asm, Matan Alfasi, 2017)

;; NAME:	SetTotalTime
;; DESCRIPTION: Calculates the total time in seconds in file
;; INPUT:	DATA_SubchunkSize, WAVE_SampleRate, WAVE_BlockAlign
;; OUTPUT:	CurrentTotalTime=Total time in seconds in file,
;; 		Output on the screen of the total time in seconds

	; 01/12/2024 (32 bit registers)
SetTotalTime:
	;; Calculate total seconds in file
	;mov	ax, [DATA_SubchunkSize]
	;mov	dx, [DATA_SubchunkSize + 2]
	;mov	bx, [WAVE_SampleRate]
	;div	bx
	;xor	dx, dx
	; 01/12/2024
	mov	eax, [DATA_SubchunkSize]
	movzx	ebx, word [WAVE_SampleRate]
	xor	edx, edx
	div	ebx

	;mov	bx, [WAVE_BlockAlign]
	;div	bx
	; 01/12/2024
	mov	bx, [WAVE_BlockAlign]
	xor	edx, edx
	div	ebx

	;mov	[TotalTime], ax
	mov	[TotalTime], eax

	mov	bl, 60
	div	bl

	;; al = minutes, ah = seconds
	push	eax ; **
	push	eax ; *

	;mov	dh, 24
	; 21/12/2024 (640*480)
	;mov	dh, 32
	;mov	dl, 42
	; 30/12/2024 (320*200)
	mov	dh, 23
	mov	dl, 22
	call	setCursorPosition

	pop	eax ; *
	xor	ah, ah
	mov	ebp, 2
	call	PrintNumber
	
	;mov	dh, 24
	; 21/12/2024 (640*480)
	;mov	dh, 32
	;mov	dl, 45
	; 30/12/2024 (320*200)
	mov	dh, 23
	mov	dl, 25
	call	setCursorPosition

	pop	eax ; **
	mov	al, ah
	xor	ah, ah
	; 21/12/2024
	mov	bp, 2
	;jmp	short PrintNumber

; --------------------------------------------------------

	; 21/12/2024 (write numbers in VESA VBE graphics mode)
	; 01/12/2024 (32bit registers)
PrintNumber:
	; eax = binary number
	; ebp = digits
	mov	esi, [screenpos]
		; hw = row, si = column
	mov	ebx, 10
	xor	ecx, ecx
printNumber_CutNumber:
	inc	ecx
	xor	edx, edx
	div	ebx
	push	edx
	cmp	ecx, ebp
	je	short printNumber_printloop
	jmp	printNumber_CutNumber

printNumber_printloop:
	pop	eax
	; 21/12/2024
	; ebp = count of digits
	; eax <= 9

	add	al, '0'
	
	; esi = pixel position (hw = row, si = column)
	; eax = al = character
	;call	write_character
	; 22/12/2024
	call	write_character_white

	dec	ebp
 	jz	short printNumber_ok
	add	esi, 8	; next column
	jmp	short printNumber_printloop
printNumber_ok:
	retn

; --------------------------------------------------------

	; 14/11/2024 - Erdogan Tan
SetProgressTime:
	;; Calculate playing/progress seconds in file
	call	CalcProgressTime

	; 01/12/2024 (32bit registers)
UpdateProgressTime:
	; eax = (new) progress time 

	mov	[ProgressTime], eax

	mov	bl, 60
	div	bl

	;; al = minutes, ah = seconds
	push	eax ; **
	push	eax ; *

	;mov	dh, 24
	; 21/12/2024 (640*480)
	;mov	dh, 32
	;mov	dl, 33
	; 30/12/2024 (320*200)
	mov	dh, 23
	mov	dl, 13
	call	setCursorPosition

	pop	eax ; *
	xor	ah, ah
	mov	ebp, 2
	call	PrintNumber
	
	;mov	dh, 24
	; 21/12/2024 (640*480)
	;mov	dh, 32
	;mov	dl, 36
	; 30/12/2024 (320*200)
	mov	dh, 23
	mov	dl, 16
	call	setCursorPosition

	pop	eax ; **
	mov	al, ah
	xor	ah, ah
	; 21/12/2024
	mov	bp, 2
	jmp	short PrintNumber

; --------------------------------------------------------

	; 01/12/2024 (32bit registers)
	; 17/11/2024
	; 14/11/2024
CalcProgressTime:
	;mov	ax, [LoadedDataBytes]
	;mov	dx, [LoadedDataBytes+2]
	;mov	bx, ax
	;or	bx, dx
	;jz	short cpt_ok
	; 01/12/2024
	mov	eax, [LoadedDataBytes]
	or	eax, eax
	jz	short cpt_ok

	;mov	bx, [WAVE_SampleRate]
	;div	bx
	;xor	dx, dx
	;mov	bx, [WAVE_BlockAlign]
	;div	bx
	; 01/12/2024
	movzx	ebx, word [WAVE_SampleRate]
	xor	edx, edx
	div	ebx
	xor	edx, edx
	mov	bx, [WAVE_BlockAlign]
	div	ebx
cpt_ok:
	; eax = (new) progress time
	retn

; --------------------------------------------------------
; 14/11/2024
; (Ref: player.asm, out_cs.asm, Matan Alfasi, 2017)

;; DESCRIPTION: Update file information on template
;; PARAMS:	WAVE parameters and other variables
;; REGS:	AX(RW)
;; VARS:	CurrentFileName, WAVE_SampleRate, 
;; RETURNS:	On-screen file info is updated.

	; 01/12/2024 (32bit registers)
UpdateFileInfo:
	;; Print File Name
	;mov	dh, 9
	; 21/12/2024 (640*480 graphics display)
	;mov	dh, 8
	;mov	dl, 23
	; 30/12/2024 (320*200, video mode 13h)
	mov	dh, 7
	mov	dl, 8
	call	setCursorPosition
	
	mov	esi, wav_file_name
	
	;;;
	; 14/11/2024
	; skip directory separators
	; (note: asciiz string, max. 79 bytes except zero tail)
	mov	ebx, esi
chk4_nxt_sep:
	lodsb
	cmp	al, '/'	; 14/12/2024
	je	short chg_fpos
	and	al, al
	jz	short chg_fpos_ok
	jmp	short chk4_nxt_sep
chg_fpos:
	mov	ebx, esi
	jmp	short chk4_nxt_sep
chg_fpos_ok:
	mov	esi, ebx ; file name (without its path/directory)
	;;;
_fnl_chk:
	; 30/12/2024 (cgaplay.s)
	; ????????.wav
	; 26/12/2024 (file name length limit -display-)
	mov	ebx, 12
	;mov	ebx, 17 ; ????????.wav?????
	push	esi
_fnl_chk_loop:
	lodsb
	and	al, al
	jz	short _fnl_ok
 	dec	ebx
	jnz	short _fnl_chk_loop
	mov	byte [esi], 0
_fnl_ok:
	pop	esi
	;;;

	call	PrintString
	
	;; Print Frequency
	;mov	dh, 10
	; 21/12/2024 (640*480 graphics display)
	;mov	dh, 9
	;mov	dl, 23
	; 30/12/2024 (320*200, video mode 13h)
	mov	dh, 8
	mov	dl, 8
	call	setCursorPosition
	;movzx	eax, word [WAVE_SampleRate]
	; 22/12/2024
	; eax = 0
	mov	ax, [WAVE_SampleRate]
	mov	ebp, 5
	call	PrintNumber

	;; Print BitRate
	;mov	dh, 9
	; 21/12/2024 (640*480 graphics display)
	;mov	dh, 8
	;mov	dl, 57
	; 30/12/2024 (320*200, video mode 13h)
	mov	dh, 7
	mov	dl, 31
	call	setCursorPosition
	mov	ax, [WAVE_BitsPerSample]
	mov	bp, 2
	call	PrintNumber

	;; Print Channel Number
	;mov	dh, 10
	; 21/12/2024 (640*480 graphics display)
	;mov	dh, 9
	;mov	dl, 57
	; 30/12/2024 (320*200, video mode 13h)
	mov	dh, 8
	mov	dl, 31
	call	setCursorPosition
	mov	ax, [WAVE_NumChannels]
	mov	bp, 1
	call	PrintNumber

	;call	UpdateVolume
	;retn

; --------------------------------------------------------

	; 14/11/2024
UpdateVolume:
	;; Print Volume
	;mov	dh, 24
	; 21/12/2024 (640*480)
	;mov	dh, 32
	;mov	dl, 75
	; 30/12/2024 (320*200, video mode 13h)
	mov	dh, 23
	mov	dl, 35
	call	setCursorPosition
	; 22/12/2024
	; eax = 0

	mov	al, [volume]

	mov	bl, 100
	mul	bl

	mov	bl, 31
	div	bl

	;neg	ax
	;add	ax, 100	
	; 01/12/2024
	mov	ah, 100
	sub	ah, al
	movzx	eax, ah
	;xor	ah, ah
	;mov	bp, 3
	mov	ebp, 3
	;call	PrintNumber
	;retn
	jmp	PrintNumber	

; --------------------------------------------------------

	; 21/12/2024
	; write text in VESA VBE graphics mode
PrintString:
	; esi = string address
printstr_loop:
	xor	eax, eax
	lodsb
	or	al, al
	jz	short printstr_ok

	push	esi

	mov	esi, [screenpos]

	; esi = pixel position (hw = row, si = column)
	; eax = al = character
	;call	write_character
	; 22/12/2024
	call	write_character_white

	add	word [screenpos], 8 ; update column (only, not row)

	pop	esi
	jmp	short printstr_loop

printstr_ok:
	retn

; --------------------------------------------------------

	; 30/12/2024
	; write character (at cursor position)
	; in video mode 13h (320*200, 256 colors)
	; 21/12/2024
	; write character (at cursor position)
	; in graphics mode (640*480, 256 colors)
	; 22/12/2024
write_character_white:
	mov	ecx, 0Fh
	; 26/12/2024
	;movzx	ecx, byte [tcolor]
write_character:
	; esi = pixel position (hw = row, si = column)
	; eax = al = character
	; cl = color
	mov	[wcolor], ecx ; 22/12/2024

	; 30/12/2024
	; 22/12/2024
	push	eax
	; clear previous character pixels
	mov	edi, fillblock
	;;sys	_video, 020Fh, 0, 8001h
	; 30/12/2024
	sys	_video, 010Fh, 0, 8000h ; 8*8 userfont
	pop	eax

	; 30/12/2024
	;shl	eax, 4 ; 8*16 pixel user font
	;mov	edi, fontbuff2 ; start of user font data
	;add	edi, eax

	; 21/12/2024
	; NOTE:
	; TRDOS 386 does not use 8*14 pixel fonts in sysvideo
	; system calls -in graphics mode-
	; because 8*16 pixel operations are faster
	;			than 8*14 pixel operations.
	; ((so, 8*14 fonts can be converted to 8*16 fonts by
	; adding 2 empty lines))
	; (8*14 characters can be written via pixel operations)
  	
	; 21/12/2024 (TRDOS 386 v2.0.9, trdosk6.s, 27/09/2024)
	;;;;;;;;;;;;;;;;; ; sysvideo system call
	;sysvideo:
	;   function in BH
	;	02h: Super VGA, LINEAR FRAME BUFFER data transfers
	;   sub function in BL
	;	0Fh: WRITE CHARACTER (FONT)
	;          CL = char's color (8 bit, 256 colors)
	;	If DH bit 7 = 1
	;	   USER FONT (from user buffer)
	;	         DL = 1 -> 8x16 pixel font
 	;	   EDI = user's font buffer address
	;		(NOTE: byte order is as row0,row1,row2..)
	;	   ESI = start position (row, column)
	;		(HW = row, SI = column)
	;;;;;;;;;;;;;;;;;

	;sys	_video, 020Fh, [wcolor], 8001h

	; 30/12/2024
	; sysvideo system call
	; BH = 01h = VGA graphics (0A0000h) data transfers
	; BL = 0Fh = write character/font
	; DH = 01h = 8*8 system font 
	; CL = [wcolor] = color
	; ESI = cursor/writing position (pixels)
	;	HW = row, SI = column
	; DL = character (ASCII code)

	mov	ah, 01h ; 8*8 pixels

	sys	_video, 010Fh, [wcolor], eax

	retn

; --------------------------------------------------------

	; 30/12/2024
	; write characters in video mode 13h
	; (320*200 pixels, 256 colors)
	; 22/12/2024
	; 21/12/2024
	; (write chars in VESA VBE graphics mode)
	; 14/11/2024
	; (Ref: player.asm, Matan Alfasi, 2017)
	; (Modification: Erdogan Tan, 14/11/2024)

	;PROGRESSBAR_ROW equ 23
	; 21/12/2024 (640*480)
	;PROGRESSBAR_ROW equ 31
	; 30/12/2024 (320*200)
	PROGRESSBAR_ROW equ 22

UpdateProgressBar:
	call	SetProgressTime	; 14/11/2024

	; 01/12/2024 (32bit registers)
	mov	eax, [ProgressTime]
UpdateProgressBar@:
	;mov	edx, 80
	; 30/12/2024
	mov	edx, 40 ; 320*200 pixels, 40 columns 
	mul	edx
	mov	ebx, [TotalTime]
	div	ebx

	; 22/12/2024
	; check progress bar indicator position if it is same 
	cmp	al, [pbprev]
	je	short UpdateProgressBar_ok
	mov	[pbprev], al

UpdateProgressBar@@:
	;; Push for the 'Clean' part
	push	eax ; **
	push	eax ; *

	;; Set cursor position
	mov	dh, PROGRESSBAR_ROW
	mov	dl, 0
	call	setCursorPosition

	pop	eax ; *
	or	eax, eax
	jz	short UpdateProgressBar_Clean

UpdateProgressBar_DrawProgress:
	; 22/12/2024
	; 21/12/2024
	; (write progress bar chars in graphics mode)
	;;;;
	mov	ebp, eax
	push	eax ; ***
	mov	esi, [screenpos]
UpdateProgressBar_DrawProgress_@:
	mov	eax, 223
	
	; esi = pixel position (hw = row, si = column)
	; eax = al = character
	;call	write_character
	; 22/12/2024
	call	write_character_white

	dec	ebp
	jz	short UpdateProgressBar_DrawCursor

	add	esi, 8 ; next column
	jmp	short UpdateProgressBar_DrawProgress_@
	;;;

UpdateProgressBar_ok:
	retn

UpdateProgressBar_DrawCursor:
	; 22/12/2024
	pop	edx ; ***
	mov	dh, PROGRESSBAR_ROW
	call	setCursorPosition

	; 21/12/2024
	; (write progress bar character in graphics mode)
	;;;;
	;;;mov	eax, 223
	;;;shl	eax, 4 ; 8*16 pixel user font
	;;mov	eax, 223*16
	;;mov	edi, fontbuff2 ; start of user font data
	;;add	edi, eax
	;mov	edi, fontbuff2+(223*16)
	;
	;sys	_video, 020Fh, 0Ch, 8001h
	; 22/12/2024
	;mov	eax, 223
	; eax = 0
	mov	al, 223
	mov	cl, 0Ch ; red
	call	write_character
	;;;;

UpdateProgressBar_Clean:
	;pop	eax  ; **
	; 22/12/2024
	pop	edx  ; **
	; 30/12/2024
	; 21/12/2024
	;mov	ebp, 80
	; 30/12/2024
	mov	ebp, 40 ; 40 columns (320*200 pixels)
	;sub	bp, ax
	sub	bp, dx ; 22/12/2024
	jz	short UpdateProgressBar_ok

	mov	dh, PROGRESSBAR_ROW
	;mov	dl, al ; 22/12/2024
	call	setCursorPosition

	; 21/12/2024
	; (write progress bar chars in graphics mode)
	;;;;
	mov	esi, [screenpos]
UpdateProgressBar_Clean_@:
	;;;mov	eax, 223
	;;;shl	eax, 4 ; 8*16 pixel user font
	;;mov	eax, 223*16
	;mov	edi, fontbuff2 ; start of user font data
	;add	edi, eax
	;mov	edi, fontbuff2+(223*16)
	;
	;sys	_video, 020Fh, 08h, 8001h
	; 22/12/2024
	;mov	eax, 223
	; eax = 0
	mov	al, 223
	mov	cl, 08h ; gray (dark)
	call	write_character
	;;;;

	dec	ebp
	jz	short UpdateProgressBar_ok

	add	esi, 8 ; next column
	jmp	short UpdateProgressBar_Clean_@
	;;;;

; --------------------------------------------------------
; 17/11/2024

Player_ProcessKey_Backwards:
	;; In order to go backwards 5 seconds:
	;; Update file pointer to the beginning, skip headers
	mov	cl, 'B'
	jmp	short Player_ProcessKey_B_or_F

Player_ProcessKey_Forwards:
	;; In order to fast-forward 5 seconds, set the file pointer
	;; to CUR_SEEK + 5 * Freq

	mov	cl, 'F'
	;jmp	short Player_ProcessKey_B_or_F

	; 01/12/2024 (32bit regsisters)
Player_ProcessKey_B_or_F:
	; 17/11/2024
	; 04/11/2024
	; (Ref: player.asm, Matan Alfasi, 2017)
  
	; 04/11/2024
	mov	eax, 5
	movzx	ebx, word [WAVE_BlockAlign]
	mul	ebx
	mov	bx, [WAVE_SampleRate]
	mul	ebx
	; eax = transfer byte count for 5 seconds
	
	; 17/11/2024
	cmp	cl, 'B'
	;mov	bx, [LoadedDataBytes]
	;mov	cx, [LoadedDataBytes+2]
	; 01/12/2024
	mov	ecx, [LoadedDataBytes]
	jne	short move_forward ; cl = 'F'
move_backward:
	;sub	bx, ax
	;sbb	cx, dx
	sub	ecx, eax
	jnc	short move_file_pointer
move_to_beginning:
	;xor	cx, cx ; 0
	;xor	bx, bx ; 0
	xor	ecx, ecx
	jmp	short move_file_pointer
move_forward: 
	;add	bx, ax
	;adc	cx, dx
	add	ecx, eax
	jc	short move_to_end
	;cmp	cx, [DATA_SubchunkSize+2]
	;ja	short move_to_end
	;jb	short move_file_pointer
	;cmp	bx, [DATA_SubchunkSize]
	;jna	short move_file_pointer
	cmp	ecx, [DATA_SubchunkSize]
	jna	short move_file_pointer
move_to_end:
	;mov	bx, [DATA_SubchunkSize]
	;mov	cx, [DATA_SubchunkSize+2]
	mov	ecx, [DATA_SubchunkSize]
move_file_pointer:
	;mov	dx, bx    
	;mov	[LoadedDataBytes], dx
	;mov	[LoadedDataBytes+2], cx
	mov	[LoadedDataBytes], ecx
	;add	dx, 44 ; + header
	;adc	cx, 0
	add	ecx, 44 

	; seek
	;mov	bx, [filehandle]
	;mov	ax, 4200h
	;int	21h
	; 01/12/2024
	xor	edx, edx ; offset from beginning of the file
	; ecx = offset	
	; ebx = file handle
	; edx = 0
	sys	_seek, [filehandle]
	retn

; --------------------------------------------------------

	; 30/12/2024 (video mode 13h)
	; (320*200, 256 colors)
	; 25/12/2024
	; 22/12/2024 (VESA VBE mode graphics) 
	; (640*480, 256 colors)
clear_window:
	;mov	edi, [LFB_ADDR]
	; 30/12/2024
	;mov	edi, 0A0000h
	;;add	edi, (13*80*8*14)
	; 25/12/2024
	;;add	edi, 164*640
	;add	edi, 12*8*320
	; 30/12/2024
	;mov	edi, [graphstart] ; 12*8*320
	mov	edi, 0A0000h+(11*8*320)+(2*320) ; *
				; AC97 info start 
	sub	eax, eax
	;;mov	ecx, (16*640*14)/4 ; 16 rows
	;mov	ecx, 64*640 ; 256 volume level points
	; 30/12/2024
	;mov	ecx, (8*8*320)/4 ; 8 rows 
	mov	ecx, (10*8*320)/4 ; *
	rep	stosd
	; 24/12/2024
	mov	[prev_points], eax ; 0
	;
	retn

; -------------------------------------------------------------
; DATA (INFO)
; -------------------------------------------------------------

Credits:
	db 'VGA WAV Player for TRDOS 386 by Erdogan Tan. '
	db 'January 2025.',10,13,0
	db '08/01/2025', 10,13,0

msgAudioCardInfo:
	db  'for Sound Blaster 16 audio device.', 10,13,0

	; 02/01/2025
msg_usage:
	db 'usage: CGAPLAY2 <FileName1> <FileName2> <...>',10,13,0

	; 24/11/2024
noDevMsg:
	db 'Error: Unable to find Sound Blaster 16 audio device!'
	db 10,13,0

noFileErrMsg:
	db 'Error: file not found.',10,13,0

; 07/12/2024
trdos386_err_msg:
	db 'TRDOS 386 System call error !',10,13,0

; 24/11/2024
msg_init_err:
	db 0Dh, 0Ah
	db "Sound Blaster 16 hardware initialization error !"
	db 0Dh, 0Ah, 0

; 19/11/2024
; 03/06/2017
hex_chars:
	db '0123456789ABCDEF', 0
; 24/11/2024
msgSB16Info:
	db 0Dh, 0Ah
	db " Audio Hardware: Sound Blaster 16", 0Dh, 0Ah 
	db "      Base Port: "
msgBasePort:
	db "000h", 0Dh, 0Ah 
	db "            IRQ: "
msgIRQ:
	db 30h
	db 0Dh, 0Ah, 0

align 4

; -------------------------------------------------------------

	; 30/12/2024
PlayingScreen:
	db  14 dup(219), " DOS Player ", 14 dup(219)
	db  201, 38 dup(205), 187
	db  186, " <Space> Play/Pause <N>/<P> Next/Prev ", 186
	db  186, " <S>     Stop       <Enter> Color     ", 186
	db  186, " <F>     Forwards   <+>/<-> Volume    ", 186
	db  186, " <B>     Backwards  <Q>     Quit Prg  ", 186
	db  204, 38 dup(205), 185
	db  186, " File:              Bits:     0       ", 186
	db  186, " Freq: 0     Hz     Channels: 0       ", 186
	db  200, 38 dup(205), 188
	db  40 dup(32)
improper_samplerate_txt:
read_error_txt:
	db  40 dup(32)
	db  40 dup(32)
	db  40 dup(32)
	db  40 dup(32)
	db  40 dup(32)
	db  40 dup(32)
	db  40 dup(32)
	db  40 dup(32)
	db  40 dup(32)
	db  40 dup(32)
	db  40 dup(205)
	db  40 dup(32)
	db  13 dup(32), "00:00 ", 174, 175, " 00:00", 4 dup(32), "VOL 000%"
	;db  40 dup(32) ; not necessary
	db 0

; -------------------------------------------------------------

	; 30/12/2024
fillblock:
	times 8 db 0FFh
	dw 0

; -------------------------------------------------------------

; 30/12/2024
; 23/11/2024
colors:
	db 0Fh, 0Bh, 0Ah, 0Ch, 0Eh, 09h, 0Dh
	; white, cyan, green, red, yellow, blue, magenta
ccolor:	db 0Bh	; cyan

; 06/01/2025
; 24/11/2024
half_buffer:
	db 1	; dma half buffer 1 or 2 (0 or 1)
		; (initial value = 1 -> after xor in TuneLoop -> 0)
EOF: 

; -------------------------------------------------------------

bss:

ABSOLUTE bss

alignb 4

; 08/01/2025
sd_count:
	;resd 1	; byte count of sound data (320 points)

; 24/12/2024
;wpoints_dif:	; wave lighting points factor (differential) 
	resd 1	; required bytes for 1/18 second wave lighting

; 06/01/2025
;graphstart:
;	resd 1	; start (top) line/row for wave lighting points 	 

; 30/12/2024
;LFB_ADDR:
;	resd 1

;nextrow:
	;resd 1
screenpos: ; hw = (cursor) row, lw = (cursor) column
	resd 1
wcolor:	resd 1
; 26/12/2024
;tcolor: resb 1 ; text color
columns:
	resb 1
pbprev:	resb 1 ; previous progress bar indicator position

alignb 4

bss_start:

; 30/12/2024
prev_points:
	resd 320 ; previous wave points (which are lighting)	

; 06/01/2025
; 20/12/2024 (playwavx.s)
audio_io_base:
	resd 1
audio_intr:
	resb 1

; 18/11/2024
stopped:
	resb 1
tLO:	resb 1

; 21/11/2024
;tLP:	resb 1

; 30/12/2024
wpoints:
	resb 1

; 08/01/2025
;pbuf_o: resd 1
; 29/12/2024
;pbuf_s: resd 1

; 25/12/2024
; 29/11/2024
command:
	resb 1
filecount:
	resb 1

; 30/11/2024
alignb 4

;;;;;;;;;;;;;;
; 14/11/2024
; (Ref: player.asm, Matan Alfasi, 2017)  
WAVFILEHEADERbuff:
RIFF_ChunkID:
	resd 1	; Must be equal to "RIFF" - big-endian
		; 0x52494646
RIFF_ChunkSize:
	resd 1	; Represents total file size, not 
        	; including the first 2 fields 
		; (Total_File_Size - 8), little-endian
RIFF_Format:
	resd 1	; Must be equal to "WAVE" - big-endian
		; 0x57415645

;; WAVE header parameters ("Sub-chunk")
WAVE_SubchunkID:
	resd 1	; Must be equal to "fmt " - big-endian
		; 0x666d7420
WAVE_SubchunkSize:
	resd 1	; Represents total chunk size
WAVE_AudioFormat:
	resw 1	; PCM (Raw) - is 1, other - is a form 
		; of compression, not supported.
WAVE_NumChannels:
	resw 1	; Number of channels, Mono-1, Stereo-2
WAVE_SampleRate:
	resd 1	; Frequency rate, in Hz (8000, 44100 ...)
WAVE_ByteRate:
	resd 1	; SampleRate * NumChannels * BytesPerSample
WAVE_BlockAlign:
	resw 1	; NumChannels * BytesPerSample
		; Number of bytes for one sample.
WAVE_BitsPerSample:
	resw 1	; 8 = 8 bits, 16 = 16 bits, etc.

;; DATA header parameters
DATA_SubchunkID:
	resd 1	; Must be equal to "data" - big-endian
        	; 0x64617461
DATA_SubchunkSize:
	resd 1	; NumSamples * NumChannels * BytesPerSample
        	; Number of bytes in the data.
;;;;;;;;;;;;;;

; 06/01/2025

filehandle:
	resd 1

; 25/12/2024
; 30/11/2024
;argc:	resb 1	; argument count
argv:	resd 1	; current argument (wav file) ptr
argvf:	resd 1	; 1st argument (wav file) ptr
argvl:	resd 1	; last argument (wav file) ptr

; 30/05/2024
wav_file_name:
	resb 80	; wave file, path name (<= 80 bytes)
	resw 1	; 30/11/2024

flags:	resb 1

; 07/12/2024
SRB:	resb 1

; 14/11/2024
TotalTime:
	resd 1	; Total (WAV File) Playing Time in seconds
ProgressTime:
	resd 1
count:	resd 1	; byte count of one (wav file) read
LoadedDataBytes:
	resd 1	; total read/load count

timerticks:
	resd 1	; (to eliminate excessive lookup of events in tuneloop)
		; (in order to get the emulator/qemu to run correctly)

; 06/01/2025
UpdateWavePoints:
	resd 1	; wave lighting procedure pointer (8m,16m,8s,16s)

; 06/01/2025
; 17/12/2024
allocated:
	resb 1
interrupt:
	resb 1

; 18/12/2024
; (the audio buffer must be aligned with the memory page, 
;  otherwise the bss area before the buffer will be truncated)
; ((ref: TRDOS 386 v2.0.9 Kernel, trdosk8.s, 'sysaudio' function 2))

; 08/01/2025
alignb 4

; 08/01/2025
sounddata:	; (wave lighting points) graphics data	
	resb 320*4

alignb 4096	; align to memory page boundary

; 06/01/2025 (cgaplay2.s)
; 16/12/2024 (sb16play.s)
audio_buffer:
	resb BUFFERSIZE ; 32768

bss_end:

; 08/01/2025
; 16/12/2024 (sb16play.s)
;alignb 4096

; 08/01/2025
; 06/01/2025
; 24/11/2024
;dma_buffer:	; 65536 bytes
;wav_buffer1:
;	resb BUFFERSIZE ; 32768
;wav_buffer2:
;	resb BUFFERSIZE ; 32768
