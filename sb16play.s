; ****************************************************************************
; sb16play.asm (for TRDOS 386)
; ----------------------------------------------------------------------------
; SB16PLAY.PRG ! Sound Blaster 16 .WAV PLAYER program by Erdogan TAN
;
; 15/12/2024
;
; [ Last Modification: 05/02/2025 ]
;
; Modified from SB16PLAY.COM .wav player program by Erdogan Tan, 18/12/2024
;		PLAYWAV9.PRG, 18/12/2024
;               AC97PLAY.PRG, 18/12/2024
;          Ref: PLAYWAV4.PRG, 18/08/2020 - SB16 .WAV player for TRRDOS 386 
;
; Assembler: FASM 1.73
;	     fasm sb16play.s SB16PLAY.PRG	
; ----------------------------------------------------------------------------
; In the visualization part of the code, the source code of Matan Alfasi's
; (Ami-Asaf) player.exe program was partially used.
; ----------------------------------------------------------------------------
; Previous versions of this Wav Player were based in part on .wav file player
; (for DOS) source code written by Jeff Leyla in 2002.

; sb16play.asm (18/12/2024)
; ac97play.s (18/12/2024)
; playwav9.s (18/12/2024)

; ----------------------------
; ref: playwav4.s (18/08/2020)
; ----------------------------

; INTERRUPT (SRB) + TUNELOOP version ; 24/11/2024
;	(running in DOSBOX, VIRTUALBOX, QEMU is ok)
; Signal Response Byte = message/signal to user about an event/interrupt
;	    as requested (TuneLoop procedure continuously checks this SRB)
; (TRDOS 386 v2 feature is used here as very simple interrupt handler output) 

; CODE

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

	; 30/11/2024
	; 12/09/2024 ('sys' macro in FASM format)

macro sys op1,op2,op3,op4
{
    if op4 eq
    else
	mov	edx, op4
    end if
    if op3 eq
    else
        mov	ecx, op3
    end if
    if op2 eq
    else
	mov	ebx, op2
    end if
	mov	eax, op1
	int	40h
}

;	; 15/12/2024 (TRDOS 386)
;	; 24/11/2024
;macro SbOut op1
;{
;local .wait
;.wait:
;	;in	al, dx
;	; dx = port number
;	mov	ah, 0 ; read port (byte)
;	int	34h
;	or	al, al
;	js	short .wait
;	mov	al, op1	; command
;	;out	dx, al
;	; dx = port number
;	mov	ah, 1 ; write port (byte)
;	int	34h
;}

; 15/12/2024 (ref: playwav4.s, 18/08/2020)
; ----------
BUFFERSIZE equ 32768	; audio buffer size 
ENDOFFILE  equ 1	; flag for knowing end of file

use32

org 0

	; 15/12/2024
_STARTUP:
	; 30/11/2024
	; 30/05/2024
	; Prints the Credits Text.
	sys	_msg, Credits, 255, 0Bh

	; 30/11/2024
	; clear bss
	mov	ecx, bss_end
	mov	edi, bss_start
	sub	ecx, edi
	; 16/12/2024
	shr	ecx, 2
	xor	eax, eax
	rep	stosd

	; 24/11/2024
	; Detect (& Reset) Sound Blaster 16 Audio Device
	call	DetectSB16
	;jnc	short GetFileName
	; 29/11/2024
	jnc	short Player_InitalizePSP

	; 30/11/2024
	; 30/05/2024
_dev_not_ready:
	; couldn't find the audio device!
	sys	_msg, noDevMsg, 255, 0Fh
        jmp     Exit

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

Player_ParseParameters:
	; 30/11/2024
	; 29/11/2024
	; 18/12/2024
	;mov	edx, wav_file_name
	cmp	byte [IsInSplash], 0
	jna	short check_p_command

	call	write_audio_dev_info

	; 20/12/2024 (playwavx.s, sb16play.s)
	; 07/12/2024 (playwav9.s)
	; 06/06/2017
	sys	_audio, 0E00h ; get audio controller info
	jc	error_exit ; 25/11/2023
	; 20/12/2024
	mov	[audio_io_base], edx
	mov	[audio_intr], al

	mov	edx, SplashFileName
	jmp	short _1

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
	; 07/12/2024
	;mov	ecx, esi
	;mov	esi, [ecx]

	; 29/11/2024
	call	GetFileName
	;jcxz	jmp_Player_Quit
	jecxz	jmp_Player_Quit ; 30/11/2024

	; 30/11/2024
	; 28/11/2024
	mov	edx, wav_file_name
	;;;
_1:
; open the file
        ; open existing file
	; 28/11/2024
	;mov	edx, wav_file_name
        call    openFile ; no error? ok.
        jnc     getwavparms	; 14/11/2024

	; 28/11/2024
	cmp 	byte [IsInSplash], 0
	ja	Player_SplashScreen

	; 29/11/2024
	cmp	byte [filecount], 0
	ja	short check_p_command

	call	ClearScreen
	; 30/11/2024
	sys	_msg, Credits, 255, 0Bh
	call	write_audio_dev_info
	
wav_file_open_error:
; file not found!
	; 30/11/2024
	sys	_msg, noFileErrMsg, 255, 0Ch
_exit_:
        jmp     Exit

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

getwavparms:
	; 14/11/2024
       	call	getWAVParameters
	jc	short _exit_		; nothing to do

	; 16/12/2024
	; 28/11/2024
	cmp 	byte [IsInSplash], 0
	jna	Player_Template

	; 30/11/2024 (TRDOS 386 version, Int 31h)
	; 28/11/2024
Player_SplashScreen:
	; 15/11/2024
	;; Set video mode to 03h (not necessary)
	mov	eax, 03h
	;int	10h
	int	31h

	; 15/11/2024
	;; Get the cursor type
	mov	ah, 03h
	;int	10h
	int	31h
	mov	[cursortype], cx ; save

	; 15/11/2024
	;; Set the cursor to invisible
	mov	ah, 01h
	mov	ecx, 2607h
	;int	10h
	int	31h

	; 15/11/2024
	;xor	edx, edx
	;call	setCursorPosition

	;; Print the splash screen in white
	mov	eax, 1300h
	mov	ebx, 000Fh
	mov	ecx, 1999
	mov	edx, 0

	mov	ebp, SplashScreen
	;int	10h
	int	31h
	;;;

	; 01/12/2024
	; 30/11/2024 (32bit)
	;;;
	; 22/11/2024
	; set wave volume led addresses
	;mov	ebx, 13*80*2
	; 01/12/2024
	mov	ebx, 0B8000h + 13*80*2
	mov	ebp, 80
	mov	edi, wleds_addr
wleds_sa_1:
	mov	ecx, 7
wleds_sa_2:
	mov	eax, 80*2
	mul	ecx
	add	eax, ebx
	;stosw
	stosd	; 01/12/2024
	loop	wleds_sa_2
	mov	eax, ebx
	;stosw
	stosd	; 01/12/2024
	inc	ebx
	inc	ebx
	dec	ebp
	jnz	short wleds_sa_1
	;;;

	; 16/12/2024 (sb16play.s)
	; 07/12/2024 (playwav9.s) -ac97-
	; Allocate Audio Buffer (for user)
	sys	_audio, 0200h, BUFFERSIZE, audio_buffer
	; 26/11/2023
	;sys	_audio, 0200h, [buffersize], audio_buffer
	jc	error_exit ; 07/12/2024

	; 17/12/2024
	inc	byte [allocated]

	; 17/12/2024
	; DIRECT CGA (TEXT MODE) MEMORY ACCESS
	; bl = 0, bh = 4
	; Direct access/map to CGA (Text) memory (0B8000h)
	sys	_video, 0400h
	cmp	eax, 0B8000h
	jne	error_exit ; short olacak

	; 17/12/2024
	; Initialize Audio Device (bh = 3)
	sys	_audio, 301h, 0, audio_int_handler
	jc	short error_exit

	; 17/12/2024
	inc	byte [interrupt]

	; 17/12/2024
	; 16/12/2024
	; Map DMA Buffer to User (for wave graphics)
	sys	_audio, 0D00h, BUFFERSIZE*2, dma_buffer
	jc	short error_exit

	; 28/11/2024 
	cmp	dword [filehandle], -1
	jne	StartPlay

	; 30/11/2024
	;;; wait for 3 seconds
	sys	_time, 0 ; get time in unix epoch format
	mov	ecx, eax
	;add	ecx, 3
	; 17/12/2024
	add	ecx, 2 ; 2 seconds
_wait_3s:
	nop
	sys	_time, 0
	cmp	eax, ecx
	jb	short _wait_3s
	;;;

	; 28/11/2024
	mov	byte [IsInSplash], 0
	;mov	edx, wav_file_name
	; 30/11/2024
	mov	esi, [argvf]
	; 29/11/2024
	jmp	Player_ParseNextParameter

	; 17/12/2024
	; 07/12/2024
error_exit:
	sys	_msg, trdos386_err_msg, 255, 0Eh
	jmp	Exit

	; 16/12/2024 (sb16play.s)
	; 07/12/2024 (playwav9.s)
	; 30/11/2024 (32bit)
	; 28/11/2024
Player_Template:
	;;;
	; 23/11/2024
	cmp	byte [WAVE_NumChannels], 1
	ja	short stolp_s
stolp_m:
	cmp	byte [WAVE_BitsPerSample], 8
	ja	short stolp_m16
stolp_m8:
	mov	dword [turn_on_leds], turn_on_leds_mono_8bit
	jmp	short stolp_ok
stolp_m16:
	mov	dword [turn_on_leds], turn_on_leds_mono_16bit
	jmp	short stolp_ok
stolp_s:
	cmp	byte [WAVE_BitsPerSample], 8
	ja	short stolp_s16
stolp_s8:
	mov	dword [turn_on_leds], turn_on_leds_stereo_8bit
	jmp	short stolp_ok
stolp_s16:
	mov	dword [turn_on_leds], turn_on_leds_stereo_16bit
stolp_ok:
	;;;
	; 09/12/2024
	xor	edx, edx
	; 29/11/2024
	inc	byte [filecount]
	;mov	byte [command], 0
	; 09/12/2024
	;mov	dword [pbuf_s], 0
	mov	byte [command], dl ; 0
	; 16/12/2024
	;mov	dword [pbuf_s], edx ; 0
	;;;
	;xor	edx, edx
	call	setCursorPosition

	;; Print the splash screen in white
	mov	eax, 1300h
	mov	ebx, 000Fh
	mov	ecx, 1999
	; 09/12/2024
	; edx = 0
	;mov	edx, 0

	mov	ebp, Template
	;int	10h
	; 30/11/2024
	int	31h
	;;;

	; 14/11/2024
	call	SetTotalTime
	call	UpdateFileInfo

StartPlay:
	; 15/12/2024 (SB16)
	; ------------------------------------------
	; 01/12/2024 (32bit)
PlayNow:
	;;;
	; 14/11/2024
	;mov	al, 3	; 0 = max, 31 = min
	; 18/12/2024
	; 14/12/2024
	;mov	al, [volume]
	;call	SetPCMOutVolume@
	; 18/12/2024
	; 16/12/2024 (sb16play.s)
	; 15/11/2024
	call	SetMasterVolume
	;call	SetPCMOutVolume

	; 29/11/2024
	cmp	byte [IsInSplash], 0
	;ja	short PlayNow@
	; 02/12/2024
	;jna	short PlayNow@
	; 16/12/2024
	ja	short _3

;PlayNow@:
	; 28/11/2024
	;cmp	byte [IsInSplash], 0
	;ja	short _3
	;
	;call	UpdateVolume
	;
	; 16/12/2024
	; 02/12/2024
	;call	PlayWav@
	;jmp	short _3

	; 02/12/2024
;PlayNow@:
	; reset file loading and EOF parameters
	;mov	dword [count], 0
	mov	dword [LoadedDataBytes], 0
	mov	byte [flags], 0
	mov	byte [stopped], 0
	;jmp	short PlayNow@@
	;;;

;PlayNow@@:
	;;;
	;
	; 14/11/2024
	call	UpdateProgressBar
	;;;
_2:	
	call	check4keyboardstop	; flush keyboard buffer
	jc	short _2		; 07/11/2023

; play the .wav file. Most of the good stuff is in here.
	
	; 05/12/2024
_3:
	call    PlayWav

;_3:	; 02/12/2024
	; 29/11/2024
	; 28/11/2024
	call    closeFile
	;mov	edx, wav_file_name
	cmp	byte [IsInSplash], 0
	;jna	short Exit
        jna	short _4 ; 29/11/2024
	mov	byte [IsInSplash], 0
	;jmp	_1
	; 01/12/2024
	mov	esi, [argvf]
	; 29/11/2024
	jmp	Player_ParseNextParameter

	; 29/11/2024
_4:
	cmp	byte [command], 'Q'
	je	short Exit
	jmp	check_p_command

; close the .wav file and exit.

Exit:
	; 15/11/2024
	;; Restore Cursor Type
	mov	cx, [cursortype]
	cmp	cx, 0
	jz	short Exit@
	mov	ah, 01h
	;int	10h
	; 01/12/2024
	int	31h
Exit@:
	; 29/11/2024
	;call	closeFile
Exit@@:
	; 17/12/2024
	;;;
	; Stop Playing
	;sys	_audio, 0700h

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

	;mov	ax, 4C00h	; bye !
	;int	21h
	; 01/12/2024
	sys	_exit, 0
here:
	jmp	short here	; do not come here !

	; 30/05/2024
pmsg_usage:
	;sys_msg msg_usage, 0Fh	; 14/11/2024
	; 01/12/2024
	sys	_msg, msg_usage, 255, 0Fh
	jmp	short Exit

	; 30/05/2024
init_err:
	;sys_msg msg_init_err, 0Fh
	; 01/12/2024
	sys	_msg, msg_init_err, 255, 0Fh
	jmp	Exit

	; 02/12/2024
Player_Quit@:
	pop	eax ; return addr (call PlayWav@)
	
	; 29/11/2024
Player_Quit:
	call	ClearScreen
	jmp	short Exit@@
ClearScreen:
	mov	ax, 03h
	;int	10h
	; 01/12/2024
	int	31h
	retn

	; --------------------------------------------

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

	test    byte [flags], ENDOFFILE  ; end of file
	jnz	short _5 ; yes
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
_5:
	; 20/12/2024
	; 19/11/2024
	mov	byte [wleds], 1

	; 15/12/2024
	movzx	eax, word [WAVE_SampleRate]
	mov	ecx, 10
	mul	ecx
	mov	cl, 182
	div	ecx
	; ax = samples per 1/18.2 second
	mov	cl, byte [WAVE_BlockAlign]
	mul	ecx
	mov	[wleds_dif], ax ; buffer read differential (distance)
				; for wave volume leds update
				; (byte stream per 1/18.2 second)
	; 18/12/2024
	;; 26/11/2024
	;call	check4keyboardstop
	;jc	_exitt_

	; 20/12/2024
	; 25/11/2024
	call	SB16Init_play	; initialize SB16 card
				; set sample rate, start to play
	jc	init_err

	; 20/12/2024
	test    byte [flags], ENDOFFILE ; end of file
	jnz	short _6	; yes

	; 20/12/2024	
	;mov     edi, audio_buffer
	call	loadFromFile
	;jc	short p_return
	;xor	byte [half_buffer], 1

	mov	eax, [count]
	add	[LoadedDataBytes], eax
_6:
	;;;
	; 18/12/2024
	cmp	byte [IsInSplash], 0
	jna	short TuneLoop
sL0:
	cmp	dword [filehandle], -1
	je	short sL3
sL1:
	cmp	byte [SRB], 0
	jna	short sL2
	mov	byte [SRB], 0
	;mov	edi, audio_buffer
	call	loadFromFile
	jc	short sL3
sL2:
	nop
	nop
	nop
	jmp	short sL0
sL3:
	retn
	;;;
	
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

	; 16/12/2024
	; 06/11/2023
tL0:
	; 29/05/2024 (TRDOS 386)
	; 08/11/2023
	; 05/11/2023
	; 17/02/2017 - Buffer switch test (temporary)
	; 06/11/2023
	; al = buffer indicator ('1', '2' or '0' -stop- )

	; 01/12/2024
	mov	ebx, 0B8000h ; video display page address
	mov	ah, 4Eh
	mov	[ebx], ax ; show current play buffer (1, 2)

	retn

; -------------------------------------------

	; 18/12/2024
	; 16/12/2024 (sb16play.s)
	; 07/12/2024 (playwav9.s)

;SetMasterVolume:
;	;cmp	al, 31
;	;ja	short setvolume_ok
;	mov	[volume], al  ; max = 0, min = 31

SetMasterVolume:
	; 18/12/2024 
	mov	al, [volume]
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

; -----------------

; 16/12/2024
volume: db	02h  ; 1Fh-1Dh

; --------------------------------------------

	; 16/12/2024
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
;ac97_stop:
	; 18/11/2024
	mov	byte [stopped], 2
	; 07/12/2024
	sys	_audio, 0700h
	retn

sb16_pause:
;ac97_pause:
	; 18/11/2024
	mov	byte [stopped], 1 ; paused
	; 07/12/2024
	sys	_audio, 0500h
	retn

sb16_play:
sb16_continue:
;ac97_play: ; continue to play (after pause)
	; 18/11/2024
	mov	byte [stopped], 0
	; 07/12/2024
	sys	_audio, 0600h
	retn

; ac97play.s
; --------------------------------------------
	
	; 01/12/2024
	; 14/11/2024
	; INPUT: ds:dx = file name address
	; OUTPUT: [filehandle] = ; -1 = not open
openFile:
	;mov	ax, 3D00h	; open File for read
	;int	21h
	;jnc	short _of1
	; 01/12/2024 (TRDOS 386)
	sys	_open, edx, 0
	jnc	short _of1

	mov	eax, -1
	; cf = 1 -> not found or access error
_of1:
	mov	[filehandle], eax
	retn

; ac97play.s
; --------------------------------------------

; close the currently open file

	; 01/12/2024
	; 14/11/2024
	; INPUT: [filehandle] ; -1 = not open
	; OUTPUT: none
closeFile:
	cmp	dword [filehandle], -1
	jz	short _cf1
	;mov	bx, [filehandle]
	;mov	ax, 3E00h
        ;int	21h              ; close file
	; 01/12/2024
	sys	_close, [filehandle]
	;mov 	dword [filehandle], -1
_cf1:
	retn

; ac97play.s
; --------------------------------------------

	; 05/02/2025
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
	; 05/02/2025
	jne	short gwavp_stc_retn
	;je	short gwavp_retn ; 15/11/2024

	; 05/02/2025
	; (Open MPT creates wav files with a new type header,
	;  this program can not use the new type
	;  because of 'data' offset is not at DATA_SubchunkID.)
	; ((GoldWave creates common type wav file.))
	cmp	dword [DATA_SubchunkID], 'data'
	je	short gwavp_retn

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
; 16/12/2024 - load wav/audio data
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
     	sys	_msg, msgAudioCardInfo, 255, 0Fh
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
	mov	dh, 13
	mov	dl, 0
	call	setCursorPosition

	; 20/12/2024
	sys	_msg, msgSB16Info, 255, 07h

	retn

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

	; 18/12/2024
	; 16/12/2024 (sb16play.s, 32bit)
	; 01/12/2024 (ac97play.s, 32bit registers)
	; 29/11/2024 (sb16play.asm, 16bit)
	; 24/11/2024 (SB16 version)
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
	; pause
	call	sb16_pause	; 24/11/2024
	; 27/11/2024
	mov	byte [stopped], 1
	jmp	c4ue_cpt
c4ue_chk_ps:
	cmp	byte [stopped], 1
	ja	short c4ue_replay
	; continue to play (after a pause)
	call	sb16_play	; 24/11/2024
	; 27/11/2024
	mov	byte [stopped], 0
	jmp	c4ue_cpt

c4ue_replay:
	; 19/11/2024
	pop	eax ; *
	pop	eax ; return address
	; 18/12/2024
	;;mov	al, [volume]
	;call	SetMasterVolume	; 24/11/2024
	;;;
	mov	byte [stopped], 0
	; 24/11/2024
	mov	byte [half_buffer], 1
	call	move_to_beginning
	jmp	PlayWav

c4ue_chk_s:
	cmp	al, 'S'	; stop
	jne	short c4ue_chk_fb
	cmp	byte [stopped], 0
	ja	short c4ue_cpt	; Already stopped/paused
	call	sb16_stop	; 24/11/2024
	; 19/11/2024
	mov	byte [tLO], 0
	jmp	short c4ue_cpt

c4ue_chk_fb:
	; 17/11/2024
	cmp	al, 'F'
	jne	short c4ue_chk_b
	call 	Player_ProcessKey_Forwards
	jmp	short c4ue_cpt
	
c4ue_chk_b:
	cmp	al, 'B'
	;;jne	short c4ue_cpt
	; 19/11/2024
	;jne	short c4ue_chk_h
	; 29/11/2024
	jne	short c4ue_chk_n
	call 	Player_ProcessKey_Backwards
	jmp	short c4ue_cpt

	;;;
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
	mov	byte [wleds], 0
	; 20/12/2024
	; 18/12/2024
	call 	write_sb16_dev_info
	mov	dh, 24
	mov	dl, 79
	call	setCursorPosition

c4ue_chk_cr:
	; 19/11/2024
	cmp	al, 0Dh ; ENTER/CR key
	jne	short c4ue_cpt
	; 23/11/2024
	xor	ebx, ebx
	mov	bl, [wleds]
	inc	bl
	and	bl, 0Fh
	jnz	short c4ue_sc
	inc	ebx
c4ue_sc:
	mov	[wleds], bl
	shr	bl, 1
	mov	al, [ebx+colors]
	jnc	short c4ue_sc_@
	or	al, 10h ; blue (dark) background
c4ue_sc_@:
	mov	[ccolor], al
	;;;
c4ue_cpt:
	;push	ds
	;mov	bx, 40h
	;mov	ds, bx
	;mov	bx, 6Ch  ; counter (INT 08h, 18.2 ticks per sec)
	;;cli
	;mov	ax, [bx]
	;mov	dx, [bx+2]
	;;sti
	;pop	ds
	; 26/11/2024
	;call	GetTimerTicks
	; 01/12/2024 (TRDOS 386)
	sys	_time, 4 ; get timer ticks (18.2 ticks/second)

	; 18/11/2024
	pop	ecx ; *
	;cmp	dx, [timerticks+2]
	;jne	short c4ue_utt
	;cmp	ax, [timerticks]
	; 01/12/2024
	cmp	eax, [timerticks]
	;je	short c4ue_ok
	; 18/11/2024
	je	short c4ue_skip_utt
c4ue_utt:	
	;mov	[timerticks], ax
	;mov	[timerticks+2], dx
	; 01/12/2024
	mov	[timerticks], eax
	jmp	short c4ue_cpt_@
c4ue_skip_utt:
	; 18/11/2024
	and	ecx, ecx
	jz	short c4ue_vb_ok ; 16/12/2024
c4ue_cpt_@:
	; 18/11/2024
	cmp	byte [stopped], 0
	ja	short c4ue_vb_ok ; 16/12/2024
	
	call	CalcProgressTime
	
	; 01/12/2024
	cmp	eax, [ProgressTime]
	; 23/11/2024
	je	short c4ue_uvb
			; same second, no need to update

	call	UpdateProgressBar

	; 23/11/2024
c4ue_uvb:
	; 20/12/2024
	cmp	byte [wleds], 0
	jna	short c4ue_vb_ok

	call	UpdateWaveLeds

c4ue_vb_ok:
	retn

; --------------------------------------------------------
; 19/05/2024 - (playwav4.asm) ich_wav4.asm
; --------------------------------------------------------

	; 01/12/2024 (TRDOS 386, ac97play.s)
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

	; 29/11/2024
	mov	[command], al

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
	;mov	ah, al
	;mov    dx, [NAMBAR]
  	;;add   dx, CODEC_MASTER_VOL_REG
	;add	dx, CODEC_PCM_OUT_REG
	;out    dx, ax
	;
	;call   delay1_4ms
        ;call   delay1_4ms
        ;call   delay1_4ms
        ;call   delay1_4ms
_cksr:		; 19/05/2024
	; 18/11/2024
	xor	eax, eax ; 16/12/2024
	;clc
p_3:
	retn
p_4:
	; 17/11/2024
	cmp	ah, 01h  ; ESC
    	je	short p_q
	cmp	al, 03h  ; CTRL+C
	je	short p_q

	; 18/11/2024
	cmp	al, 20h
	je	short p_r

	; 19/11/2024
	cmp	al, 0Dh ; CR/ENTER
	je	short p_r

	and	al, 0DFh

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
	; 29/11/2024
	mov	byte [command], 'Q'
p_quit:
	stc
p_r:
	retn

; --------------------------------------------------------

	; 14/11/2024
setCursorPosition:
	; dh = Row
	; dl = Column
	mov	ax, 0500h
	;int	10h
	; 01/12/2024 (TRDOS 386 video interrupt)
	int	31h
	mov	ah, 02h
	mov	bh, 00h
	;mov	dh, setCursorPosition_Row
	;mov	dl, setCursorPosition_Column
	;int	10h
	; 01/12/2024 (TRDOS 386 video interrupt)
	int	31h
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

	mov	dh, 24
	mov	dl, 42
	call	setCursorPosition

	pop	eax ; *
	xor	ah, ah
	mov	ebp, 2
	call	PrintNumber
	
	mov	dh, 24
	mov	dl, 45
	call	setCursorPosition

	pop	eax ; **
	mov	al, ah
	xor	ah, ah
	;mov	bp, 2
	;jmp	short PrintNumber

; --------------------------------------------------------

	; 01/12/2024 (32bit registers)
PrintNumber:
	; eax = binary number
	; ebp = digits
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
	;mov	dl, '0'
	;add	dl, al
	;mov	ah, 02h
	;int	21h
	; 01/12/2024
	mov	ah, 0Eh	; write as TTY
	add	al, '0'
	;mov	ebx, 07h ; light gray
	mov	bl, 0Fh  ; white
	;int	10h
	int	31h  ; TRDOS 386 video interrupt
	loop	printNumber_printloop
	
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

	mov	dh, 24
	mov	dl, 33
	call	setCursorPosition

	pop	eax ; *
	xor	ah, ah
	mov	ebp, 2
	call	PrintNumber
	
	mov	dh, 24
	mov	dl, 36
	call	setCursorPosition

	pop	eax ; **
	mov	al, ah
	xor	ah, ah
	;mov	bp, 2
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
	mov	dh, 9
	mov	dl, 23
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

	call	PrintString
	
	;; Print Frequency
	mov	dh, 10
	mov	dl, 23
	call	setCursorPosition
	movzx	eax, word [WAVE_SampleRate]
	mov	ebp, 5
	call	PrintNumber

	;; Print BitRate
	mov	dh, 9
	mov	dl, 57
	call	setCursorPosition
	mov	ax, [WAVE_BitsPerSample]
	mov	bp, 2
	call	PrintNumber

	;; Print Channel Number
	mov	dh, 10
	mov	dl, 57
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
	mov	dh, 24
	mov	dl, 75
	call	setCursorPosition

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

	; 01/12/2024
	; 14/11/2024
PrintString:
	; esi = string address 
	mov	bx, 0Fh	 ; white
	mov	ah, 0Eh	 ; write as tty
printstr_loop:
	lodsb
	or	al, al
	jz	short printstr_ok
	;int	10h
	; 01/12/2024 (TRDOS 386 video interrupt)
	int	31h
	jmp	short printstr_loop
printstr_ok:
	retn

; --------------------------------------------------------

	; 14/11/2024
	; (Ref: player.asm , Matan Alfasi, 2017)
	; (Modification: Erdogan Tan, 14/11/2024)

	PROGRESSBAR_ROW equ 23

UpdateProgressBar:
	call	SetProgressTime	; 14/11/2024

	; 01/12/2024 (32bit registers)
	mov	eax, [ProgressTime]
UpdateProgressBar@:
	mov	edx, 80
	mul	edx
	mov	ebx, [TotalTime]
	div	ebx
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
	mov	ecx, eax
	mov	ah, 09h
	mov	al, 223
	mov	ebx, 0Fh
	;int	10h
	; 01/12/2024 (TRDOS 386 video interrupt)
	int	31h

UpdateProgressBar_DrawCursor:
	;mov	eax, ecx
	mov	dh, PROGRESSBAR_ROW
	;mov	dl, al
	dec	ecx
	mov	dl, cl
	call	setCursorPosition

	mov	ah, 09h
	mov	al, 223
	mov	ebx, 0Ch
	mov	ecx, 1
	;int	10h
	; 01/12/2024 (TRDOS 386 video interrupt)
	int	31h

UpdateProgressBar_Clean:
	pop	eax  ; **
	; 05/12/2024
	;mov	ecx, eax
	mov	ecx, 80
	sub	cx, ax
	; 07/12/2024
	jz	short UpdateProgressBar_ok
	mov	dh, PROGRESSBAR_ROW
	mov	dl, al
	call	setCursorPosition

	; 05/12/2024
	;neg	ecx
	;add	ecx, 80 ; cf = 1 ; +
	;; CX = No. of times to print a clean character
	;mov	cx, 80
	;sub	cx, ax
	;; 09h = Write character multiple times
	mov	ah, 09h
	;; 32 = Space ASCII code
	;mov	al, 32
	;mov	bx, 0
	; 15/11/2024
	mov	al, 223
	mov	ebx, 8
	;int	10h
	; 01/12/2024 (TRDOS 386 video interrupt)
	int	31h

	; 14/11/2024
	clc	; +
UpdateProgressBar_ok:
	retn

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

	; 19/11/2024
UpdateWaveLeds:
	; 23/11/2024
	call	reset_wave_leds
	;call	word [turn_on_leds]
	;retn
	;jmp	word [turn_on_leds]
	; 16/12/2024 (TRDOS 386)
	jmp	dword [turn_on_leds]

; --------------------------------------------------------

	; 01/12/2024 (32bit registers)
	; 23/11/2024
	; 19/11/2024
clear_window:
	xor	eax, eax
	jmp	short clear_window_@

reset_wave_leds:
	; 23/11/2024
	;mov	al, 254
	;mov	ah, 8 ; gray (dark)
	;mov	ax, 08FEh
	; 01/12/2024
	mov	eax, 08FE08FEh
clear_window_@:
	;push	es
	;mov	di, 0B800h
	;mov	es, di
	;mov	di, 2080 ; 13*80*2
	;mov	cx, 8*80 ; 8 rows
	;rep	stosw
	;pop	es
	; 01/12/2024
	mov	edi, 0B8000h + 2080
	mov	ecx, 8*80/2
	rep	stosd
	xor	eax, eax ; 0
	retn

; --------------------------------------------------------

	; 23/01/2025
	; 16/12/2024 (sb16play.s, TRDOS 386)
	; 	     (DMA buffer monitoring/tracking)
	; 09/12/2024 (ac97play.s)
	; 07/12/2024 (playwav9.s) -ac97-
	; 24/11/2024 (sb16play.asm, DOS)
	; 19/11/2024
turn_on_leds_stereo_16bit:
	; 16/12/2024
	call	get_gdata_address
	; esi = start address of the graphics data
	;		in dma buffer
	; ecx = 80 ; 18/12/2024
	; ebx = wleds_addr
	; eax = 0

tol_fill_c:
	lodsw	; left
	;shr	ax, 8
	; 23/01/2025
	add	ah, 80h
	mov	edx, eax
	lodsw	; right
	;shr	ax, 8
	;;;
	;add	eax, edx
	;shr	eax, 8
	;;shr	ax, 9
	;add	al, 80h
	;shr	eax, 5
	;;;
	;shr	ax, 6
	;;;
	; 09/12/2024
	;add	ax, dx
	;add	ah, 80h
	;shr	eax, 13
	; 23/01/2025
	add	ah, 80h
	add	eax, edx  ; L+R	
	shr	eax, 14	; 8 volume levels

	; eax = 0 to 7 ; 18/12/2024
	;;;
	push	ebx
	;shl	ax, 1
	; 01/12/2024
	shl	eax, 2
	; eax = 0 to 28 ; 18/12/2024
	add	ebx, eax
	; 01/12/2024 (32bit address)
	mov	edi, [ebx]
	mov	ah, [ccolor]
	mov	al, 254
	mov	[edi], ax
	pop	ebx
	;add	ebx, 16
	add	ebx, 32
	loop	tol_fill_c

	retn

	; 24/11/2024
	; 23/11/2024
turn_on_leds_mono_16bit:
	; 16/12/2024
	call	get_gdata_address
	; esi = start address of the graphics data
	;		in dma buffer
	; ecx = 80 ; 18/12/2024
	; ebx = wleds_addr
	; eax = 0

tol2_fill_c:
	lodsw
	;;;
	; 18/12/2024
	;shr	eax, 8
	;add	al, 80h
	;shr	eax, 5
	add	ah, 80h
	shr	eax, 13
	; eax = 0 to 7 ; 18/12/2024
	;;;
	push	ebx
	;shl	ax, 1
	; 01/12/2024
	shl	eax, 2
	; eax = 0 to 28 ; 18/12/2024
	add	ebx, eax
	; 01/12/2024 (32bit address)
	mov	edi, [ebx]
	mov	ah, [ccolor]
	mov	al, 254
	mov	[edi], ax
	pop	ebx
	;add	ebx, 16
	add	ebx, 32
	loop	tol2_fill_c

	retn

	; 23/01/2025
	; 24/11/2024
turn_on_leds_stereo_8bit:
	; 16/12/2024
	call	get_gdata_address
	; esi = start address of the graphics data
	;		in dma buffer
	; ecx = 80 ; 18/12/2024
	; ebx = wleds_addr
	; eax = 0 

tol3_fill_c:
	;lodsw	; left (al), right (ah)
	;add	al, ah
	;add	al, 80h
	;xor	ah, ah
	;;shr	ax, 6
	;shr	eax, 5
	; 23/01/2025
	xor	eax, eax ; 0
	lodsb	; left
	mov	edx, eax
	lodsb	; right
	add	eax, edx
	shr	eax, 1 ; (L+R/2)
	sub	al, 255	; max. value will be shown on top
	shr	eax, 5	; 8 volume levels

	; eax = 0 to 7 ; 18/12/2024
	push	ebx
	;shl	ax, 1
	shl	eax, 2
	; eax = 0 to 28 ; 18/12/2024
	add	ebx, eax
	mov	edi, [ebx]
	mov	ah, [ccolor]
	mov	al, 254
	mov	[edi], ax
	pop	ebx
	;add	ebx, 16
	add	ebx, 32
	loop	tol3_fill_c

	retn

	; 23/01/2025
	; 24/11/2024
	; 23/11/2024
turn_on_leds_mono_8bit:
	; 16/12/2024
	call	get_gdata_address
	; esi = start address of the graphics data
	;		in dma buffer
	; ecx = 80 ; 18/12/2024
	; ebx = wleds_addr
	; eax = 0

tol4_fill_c:
	;lodsb
	;xor	ah, ah
	;; 16/12/2024
	;;add	al, 80h
	;shr	eax, 5
	; 23/01/2025
	xor	eax, eax ; 0
	lodsb
	sub	al, 255	; max. value will be shown on top
	shr	eax, 5  ; 8 volume levels

	; eax = 0 to 7 ; 18/12/2024
	push	ebx
	;shl	ax, 1
	shl	eax, 2
	; eax = 0 to 28 ; 18/12/2024
	add	ebx, eax
	mov	edi, [ebx]
	mov	ah, [ccolor]
	mov	al, 254
	mov	[edi], ax
	pop	ebx
	;add	ebx, 16
	add	ebx, 32
	loop	tol4_fill_c

	retn

; --------------------------------------------------------

	; 18/12/2024
	; 16/12/2024 (sb16play.s, TRDOS 386)
	; ref: TRDOS 386 v2.0.9, trdosk8.s, 18/09/2024
get_gdata_address:
	; GET CURRENT SOUND DATA (for graphics)
	; ((get DMA buffer pointer))
	sys	_audio, 0F00h, 0
	
	; eax = current DMA buffer position/offset
	mov	esi, dma_buffer
	; 18/12/2024
	;jc	short g_gdata_parms_2 ; ecx = 0
	mov	ecx, [wleds_dif]
	mov	edx, dma_buffer + BUFFERSIZE*2
	add	esi, eax
	cmp	esi, edx
	jnb	short g_gdata_parms_1
	add	esi, ecx
	cmp	esi, edx
	jna	short g_gdata_parms_2
g_gdata_parms_1:
	mov	esi, edx	
g_gdata_parms_2:
	sub	esi, ecx
	mov	ebx, wleds_addr
	; 18/12/2024
	mov	ecx, 80
	xor	eax, eax
	retn
	
; --------------------------------------------------------
; DATA (initialized DATA)
; --------------------------------------------------------

Credits:
	db	'Tiny WAV Player for TRDOS 386 by Erdogan Tan. '
	;;db	'December 2024.',10,13,0
	;db	'January 2025.',10,13,0
	db	'February 2025.',10,13,0
	db	'20/12/2024', 10,13,0
	db	'23/01/2025', 10,13,0
	db	'05/02/2025', 10,13,0

msgAudioCardInfo:
	db 	'for Sound Blaster 16 audio device.', 10,13,0

msg_usage:
	db	'usage: SB16PLAY <FileName1> <FileName2> <...>',10,13,0 ; 29/11/2024

	; 24/11/2024
noDevMsg:
	db	'Error: Unable to find Sound Blaster 16 audio device!'
	db	10,13,0

noFileErrMsg:
	db	'Error: file not found.',10,13,0

; 07/12/2024
trdos386_err_msg:
	db	'TRDOS 386 System call error !',10,13,0

; 24/11/2024
msg_init_err:
	db	0Dh, 0Ah
	db	"Sound Blaster 16 hardware initialization error !"
	db	0Dh, 0Ah, 0

; 19/11/2024
; 03/06/2017
hex_chars:	db "0123456789ABCDEF", 0

; 24/11/2024
msgSB16Info:	db 0Dh, 0Ah
		db " Audio Hardware: Sound Blaster 16", 0Dh, 0Ah 
		db "      Base Port: "
msgBasePort:	db "000h", 0Dh, 0Ah 
		db "            IRQ: "
msgIRQ:		db 30h
		db 0Dh, 0Ah, 0

; --------------------------------------------------------
; 14/11/2024 (Ref: player.asm, Matan Alfasi, 2017)

SplashScreen:
		db  221, 219, 222, "                                                                          ", 221, 219, 222
		db  221, 219, 222, "                                                                          ", 221, 219, 222
		db  221, 219, 222, "                                                                          ", 221, 219, 222
		db  221, 219, 222, "                                                                          ", 221, 219, 222
		db  221, 219, 222, "                     _______   ______        _______.                     ", 221, 219, 222
		db  221, 219, 222, "                    |       \ /  __  \      /       |                     ", 221, 219, 222
		db  221, 219, 222, "                    |  .--.  |  |  |  |    |   (----`                     ", 221, 219, 222
		db  221, 219, 222, "                    |  |  |  |  |  |  |     \   \                         ", 221, 219, 222
		db  221, 219, 222, "                    |  '--'  |  `--'  | .----)   |                        ", 221, 219, 222
		db  221, 219, 222, "                    |_______/ \______/  |_______/                         ", 221, 219, 222
		db  221, 219, 222, "                                                                          ", 221, 219, 222
		db  221, 219, 222, "     .______    __          ___   ____    ____  _______ .______           ", 221, 219, 222
		db  221, 219, 222, "     |   _  \  |  |        /   \  \   \  /   / |   ____||   _  \          ", 221, 219, 222
		db  221, 219, 222, "     |  |_)  | |  |       /  ^  \  \   \/   /  |  |__   |  |_)  |         ", 221, 219, 222
		db  221, 219, 222, "     |   ___/  |  |      /  /_\  \  \_    _/   |   __|  |      /          ", 221, 219, 222
		db  221, 219, 222, "     |  |      |  `----./  _____  \   |  |     |  |____ |  |\  \----.     ", 221, 219, 222
		db  221, 219, 222, "     | _|      |_______/__/     \__\  |__|     |_______|| _| `._____|     ", 221, 219, 222
		db  221, 219, 222, "                                                                          ", 221, 219, 222
		db  221, 219, 222, "                                                                          ", 221, 219, 222
		db  221, 219, 222, "                                                                          ", 221, 219, 222
		db  221, 219, 222, "                                WELCOME TO                                ", 221, 219, 222
		db  221, 219, 222, "                                DOS PLAYER                                ", 221, 219, 222
		db  221, 219, 222, "                                                                          ", 221, 219, 222
		db  221, 219, 222, "                                                                          ", 221, 219, 222
		db  "                                                                                         "
Template:
		db  201, 78 dup(205), 187
		db  186, 33 dup(219), " DOS Player ", 33 dup(219), 186
		db  204, 78 dup(205), 185
		db  186, 33 dup(32), " User Guide ", 33 dup(32), 186
		; 29/11/2024
		db  186, 6  dup(32), "<Space>         Play/Pause    ", 4 dup(32), "<N>/<P>         Next/Previous", 9 dup(32), 186
		db  186, 6  dup(32), "<S>             Stop          ", 4 dup(32), "<Enter>         Wave Lighting", 9 dup(32), 186
		db  186, 6  dup(32), "<F>             Forwards      ", 4 dup(32), "<+>/<->         Inc/Dec Volume", 8 dup(32), 186
		db  186, 6  dup(32), "<B>             Backwards     ", 4 dup(32), "<Q>             Quit Program ", 9 dup(32), 186
		db  204, 78 dup(205), 185
		db  186, 6  dup(32), "File Name :                   ", 4 dup(32), "Bit-Rate  :     0  Bits      ", 9 dup(32), 186
		db  186, 6  dup(32), "Frequency :     0     Hz      ", 4 dup(32), "#-Channels:     0            ", 9 dup(32), 186
		db  200, 78 dup(205), 188
		db  80 dup(32)
improper_samplerate_txt:			; 03/11/2024
read_error_txt:
		db  80 dup(32)
		db  80 dup(32)
		db  80 dup(32)
		db  80 dup(32)
		db  80 dup(32)
		db  80 dup(32)
		db  80 dup(32)
		db  80 dup(32)
		db  80 dup(32)
		db  80 dup(205)
		db  80 dup(32)
		db  33 dup(32), "00:00 ", 174, 175, " 00:00", 24 dup(32), "VOL 000%"
; 29/11/2024
IsInSplash:	db 1
SplashFileName: db "SPLASH.WAV", 0

; 23/11/2024
colors:		db 0Fh, 0Bh, 0Ah, 0Ch, 0Eh, 09h, 0Dh, 0Fh
			; white, cyan, green, red, yellow, blue, magenta
ccolor:		db 0Bh	; cyan

; 24/11/2024
half_buffer:	db 1	; dma half buffer 1 or 2 (0 or 1)
			; (initial value = 1 -> after xor in TuneLoop -> 0)
EOF: 

; --------------------------------------------------------
; BSS (uninitialized DATA)
; --------------------------------------------------------

align 4	; 16/12/2024

; 24/11/2024
; 22/11/2024
; wave volume leds address array
;wleds_addr:	rw 80*8 ; rb 2*80*8
; 01/12/2024 (ac97play.s)
wleds_addr:	rd 80*8 ; 32bit address

; 24/11/2024 (SB16 version of playwav8.com -> playwav9.com)
; 14/11/2024
; 17/02/2017
bss_start:

; 13/11/2024
; ('resb','resw','resd' to 'rb','rw','rd' conversions for FASM)

; 20/12/2024 (playwavx.s)
audio_io_base:	rd 1
audio_intr:	rb 1

; 16/12/2024 (sb16play.s)
; 18/11/2024
stopped:	rb 1
tLO:		rb 1
; 19/11/2024
wleds:		rb 1

wleds_dif:	rd 1
; 16/12/2024
;pbuf_s:	rw 1
;pbuf_o:	rw 1

; 25/11/2024
align 4

;;;;;;;;;;;;;;
; 14/11/2024
; (Ref: player.asm, Matan Alfasi, 2017)
WAVFILEHEADERbuff:
RIFF_ChunkID:	rd 1	; Must be equal to "RIFF" - big-endian
			; 0x52494646
RIFF_ChunkSize:
		rd 1	; Represents total file size, not
                        ; including the first 2 fields 
			; (Total_File_Size - 8), little-endian
RIFF_Format:
		rd 1	; Must be equal to "WAVE" - big-endian
			; 0x57415645

;; WAVE header parameters ("Sub-chunk")
WAVE_SubchunkID:
		rd 1	; Must be equal to "fmt " - big-endian
			; 0x666d7420
WAVE_SubchunkSize:
		rd 1	; Represents total chunk size
WAVE_AudioFormat:
		rw 1	; PCM (Raw) - is 1, other - is a form
			; of compression, not supported.
WAVE_NumChannels:
		rw 1	; Number of channels, Mono-1, Stereo-2
WAVE_SampleRate:
		rd 1	; Frequency rate, in Hz (8000, 44100 ...)
WAVE_ByteRate:	rd 1	; SampleRate * NumChannels * BytesPerSample
WAVE_BlockAlign:
		rw 1	; NumChannels * BytesPerSample
			; Number of bytes for one sample.
WAVE_BitsPerSample:
		rw 1	; 8 = 8 bits, 16 = 16 bits, etc.

;; DATA header parameters
DATA_SubchunkID:
		rd 1	; Must be equal to "data" - big-endian
                        ; 0x64617461
DATA_SubchunkSize:
		rd 1	; NumSamples * NumChannels * BytesPerSample
                        ; Number of bytes in the data.
;;;;;;;;;;;;;;

; 16/12/2024 (sb16play.s)
; 30/11/2024 (ac97play.s)
;argc:		rb 1	; argument count
argv:		rd 1	; current argument (wav file) ptr
argvf:		rd 1	; 1st argument (wav file) ptr
argvl:		rd 1	; last argument (wav file) ptr

filehandle:	rd 1

; 15/11/2024
cursortype:	rw 1

flags:		rb 1	; (END_OF_FILE flag)
; 16/12/2024 (sb16play.s) 
; 07/12/2024 (playwav9.s) -ac97-
SRB:		rb 1

; 29/11/2024
command:	rb 1
filecount:	rb 1

; 30/05/2024
wav_file_name:
		rb 80	; wave file, path name (<= 80 bytes)

		rw 1
; 24/11/2024
align 4

; 16/12/2024 (sb16play.s)
; 23/11/2024 (sb16play.asm)
turn_on_leds:	rd 1	; turn_on_leds procedure pointer (m8,m16,s8,s16)

; (ac97play.s)
; 14/11/2024
TotalTime:	rd 1	; Total (WAV File) Playing Time in seconds
ProgressTime:	rd 1
count:		rd 1	; byte count of one (wav file) read
LoadedDataBytes:
		rd 1	; total read/load count

timerticks:	rd 1	; (to eliminate excessive lookup of events in TuneLoop)
			; (in order to get the emulator/qemu to run correctly)
; 17/12/2024
allocated:	rb 1
interrupt:	rb 1

; 18/12/2024
; (the audio buffer must be aligned with the memory page, 
;  otherwise the bss area before the buffer will be truncated)
; ((ref: TRDOS 386 v2.0.9 Kernel, trdosk8.s, 'sysaudio' function 2))

align 4096	; align to memory page boundary

; 16/12/2024 (sb16play.s)
audio_buffer:	rb BUFFERSIZE ; 32768 ; DMA Buffer Size / 2

bss_end:

; 16/12/2024 (sb16play.s)
align 4096

dma_buffer:	rb BUFFERSIZE*2 ; 65536 ; (this is used for WAVE graphics)

