; ****************************************************************************
; ac97play.s (for TRDOS 386)
; ----------------------------------------------------------------------------
; AC97PLAY.PRG ! AC'97 (ICH) .WAV PLAYER program by Erdogan TAN
;
; 30/11/2024
;
; [ Last Modification: 18/12/2024 ]
;
; Modified from AC97PLAY.COM .wav player program by Erdogan Tan, 29/11/2024
;
; Assembler: FASM 1.73
;	     fasm ac97play.s AC97PLAY.PRG
; ----------------------------------------------------------------------------
; In the visualization part of the code, the source code of Matan Alfasi's
; (Ami-Asaf) player.exe program was partially used.
; ----------------------------------------------------------------------------
; Previous versions of this Wav Player were based in part on .wav file player
; (for DOS) source code written by Jeff Leyla in 2002.

; ac97play.asm (DOS, 29/11/2024) -- ref: TRDOS 386, playwav7.s, 01/06/2024 --
; ------------------------------------------------------------------
; playwav7.s (TRDOS 386) - tuneloop (user mode) version (29/05/2024)
; ------------------------------------------------------------------
; playwav8.asm (DOS, 25/11/2024)
; playwav7.asm (DOS, 13/11/2024)
; playwav6.asm (DOS, 30/05/2024)
; ------------------------------
; TUNELOOP version (playing without AC97 interrupt) - 06/11/2023 - Erdogan Tan
; sample rate conversion version - 18/11/2023 - Erdogan Tan

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

; player internal variables and other equates.
; 17/11/2024 (16bit DOS, segment-offset 64KB-16bit limit)
;BUFFERSIZE	equ 65520
; 30/11/2024 (TRDOS 386, 32bit DOS, there is not a 64KB limit)
BUFFERSIZE	equ 65536
ENDOFFILE	equ 1		; flag for knowing end of file

; 30/11/2024
use32

org 0

	include 'ac97.inc' ; 17/02/2017

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
	shr	ecx, 1
	xor	eax, eax
	rep	stosw

	; Detect (& Enable) AC'97 Audio Device
	call	DetectAC97
	;jnc	short GetFileName
	; 30/11/2024
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

	;;;
	; 18/12/2024
vbuffer_map:
	; 01/12/2024
	; Map video buffer (0B8000h) to user memory (same addr)
	sys	_video, 0400h
	
	cmp	eax, 0B8000h
	jne	short jmp_Player_Quit ; terminate without error msg
	;;;

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
       	call    getWAVParameters
	jc	short _exit_		; nothing to do

	; 17/11/2024
	mov	bl, 4
	sub	bl, byte [WAVE_BlockAlign]
			; = 0 for 16 bit stereo
			; = 2 for 8 bit stereo or 16 bit mono
			; = 3 for 8 bit mono	

	shr	bl, 1	;  0 -->  0,  2 -->  1,  3 -->  1
	; 15/11/2024
	adc	bl, 0	; 3 --> 1 --> 2
	mov	byte [fbs_shift], bl	; = 2 mono and 8 bit
					; = 0 stereo and 16 bit
					; = 1 mono or 8 bit
	; 30/05/2024
	call	codecConfig		; unmute codec, set rates.
	jc	init_err

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

	; 28/11/2024 
	cmp	dword [filehandle], -1
	jne	StartPlay

	; 30/11/2024
	;;; wait for 3 seconds
	sys	_time, 0 ; get time in unix epoch format
	mov	ecx, eax
	add	ecx, 2 ; wait for 2 seconds ; 18/12/2024
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

	; 30/11/2024 (32bit)
	; 28/11/2024
Player_Template:
	;;;
	; 09/12/2024
	xor	edx, edx
	; 29/11/2024
	inc	byte [filecount]
	;mov	byte [command], 0
	; 09/12/2024
	;mov	dword [pbuf_s], 0
	mov	byte [command], dl ; 0
	mov	dword [pbuf_s], edx ; 0
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

	; 30/11/2024
	; 28/11/2024
StartPlay:
	; 25/11/2023
	; ------------------------------------------

	; 18/11/2023 (ich_wav4.asm)
	; 13/11/2023 (ich_wav3.asm)

	cmp	byte [VRA], 1
	jb	short chk_sample_rate

playwav_48_khz:	
	mov	dword [loadfromwavfile], loadFromFile
	;mov	dword [loadsize], 0 ; 65536
	;;;
	; 17/11/2024
	;mov	word [buffersize], 32768
	;mov	ax, BUFFERSIZE/2 ; 32760
	; 30/11/2024
	mov	eax, BUFFERSIZE/2 ; 32768
	mov	[buffersize], eax	; 16 bit samples
	shl	eax, 1			; bytes
	mov	cl, [fbs_shift]
	shr	eax, cl 
	;mov	[loadsize], ax ; 16380 or 32760 or 65520
	mov	[loadsize], eax ; 16384 or 32768 or 65536
	;;;
	jmp	PlayNow ; 30/05/2024

chk_sample_rate:
	; set conversion parameters
	; (for 8, 11.025, 16, 22.050, 24, 32 kHZ)
	mov	ax, [WAVE_SampleRate]
	cmp	ax, 48000
	je	short playwav_48_khz
chk_22khz:
	cmp	ax, 22050
	jne	short chk_11khz
	cmp	byte [WAVE_BitsPerSample], 8
	jna	short chk_22khz_1
	mov	ebx, load_22khz_stereo_16_bit
	cmp	byte [WAVE_NumChannels], 1 
	jne	short chk_22khz_2
	mov	ebx, load_22khz_mono_16_bit
	jmp	short chk_22khz_2
chk_22khz_1:
	mov	ebx, load_22khz_stereo_8_bit
	cmp	byte [WAVE_NumChannels], 1 
	jne	short chk_22khz_2
	mov	ebx, load_22khz_mono_8_bit
chk_22khz_2:
	mov	eax, 7514  ; (442*17)
	mov	edx, 37
	mov	ecx, 17 
	jmp	set_sizes	
chk_11khz:
	cmp	ax, 11025
	jne	short chk_44khz
	cmp	byte [WAVE_BitsPerSample], 8
	jna	short chk_11khz_1
	mov	ebx, load_11khz_stereo_16_bit
	cmp	byte [WAVE_NumChannels], 1 
	jne	short chk_11khz_2
	mov	ebx, load_11khz_mono_16_bit
	jmp	short chk_11khz_2
chk_11khz_1:
	mov	ebx, load_11khz_stereo_8_bit
	cmp	byte [WAVE_NumChannels], 1 
	jne	short chk_11khz_2
	mov	ebx, load_11khz_mono_8_bit
chk_11khz_2:
	mov	eax, 3757  ; (221*17)
	mov	edx, 74
	mov	ecx, 17
	jmp	set_sizes 
chk_44khz:
	cmp	ax, 44100
	jne	short chk_16khz
	cmp	byte [WAVE_BitsPerSample], 8
	jna	short chk_44khz_1
	mov	ebx, load_44khz_stereo_16_bit
	cmp	byte [WAVE_NumChannels], 1 
	jne	short chk_44khz_2
	mov	ebx, load_44khz_mono_16_bit
	jmp	short chk_44khz_2
chk_44khz_1:
	mov	ebx, load_44khz_stereo_8_bit
	cmp	byte [WAVE_NumChannels], 1 
	jne	short chk_44khz_2
	mov	ebx, load_44khz_mono_8_bit
chk_44khz_2:
	; 30/11/2024 (TRDOS 386, 32bit DOS)
	mov	eax, 15065 ; (655*23)
	; 18/11/2023 ((file size + bss + stack) <= 64KB)
	;mov	ax, 14076 ; (612*23)
	; 17/11/2024
	;mov	ax, 12650 ; (550*23)
	mov	edx, 25
	mov	ecx, 23
	jmp	set_sizes 
chk_16khz:
	cmp	ax, 16000
	jne	short chk_8khz
	cmp	byte [WAVE_BitsPerSample], 8
	jna	short chk_16khz_1
	mov	ebx, load_16khz_stereo_16_bit
	cmp	byte [WAVE_NumChannels], 1 
	jne	short chk_16khz_2
	mov	ebx, load_16khz_mono_16_bit
	jmp	short chk_16khz_2
chk_16khz_1:
	mov	ebx, load_16khz_stereo_8_bit
	cmp	byte [WAVE_NumChannels], 1 
	jne	short chk_16khz_2
	mov	ebx, load_16khz_mono_8_bit
chk_16khz_2:
	; 30/11/2024 (TRDOS 386, 32bit DOS)
	mov	eax, 5461
	; 17/11/2024
	;mov	ax, 5460
	mov	edx, 3
	mov	ecx, 1
	jmp	set_sizes 
chk_8khz:
	cmp	ax, 8000
	jne	short chk_24khz
	cmp	byte [WAVE_BitsPerSample], 8
	jna	short chk_8khz_1
	mov	ebx, load_8khz_stereo_16_bit
	cmp	byte [WAVE_NumChannels], 1 
	jne	short chk_8khz_2
	mov	ebx, load_8khz_mono_16_bit
	jmp	short chk_8khz_2
chk_8khz_1:
	mov	ebx, load_8khz_stereo_8_bit
	cmp	byte [WAVE_NumChannels], 1 
	jne	short chk_8khz_2
	mov	ebx, load_8khz_mono_8_bit
chk_8khz_2:
	mov	eax, 2730
	mov	edx, 6
	mov	ecx, 1
	jmp	set_sizes 
chk_24khz:
	cmp	ax, 24000
	jne	short chk_32khz
	cmp	byte [WAVE_BitsPerSample], 8
	jna	short chk_24khz_1
	mov	bx, load_24khz_stereo_16_bit
	cmp	byte [WAVE_NumChannels], 1 
	jne	short chk_24khz_2
	mov	bx, load_24khz_mono_16_bit
	jmp	short chk_24khz_2
chk_24khz_1:
	mov	ebx, load_24khz_stereo_8_bit
	cmp	byte [WAVE_NumChannels], 1 
	jne	short chk_24khz_2
	mov	ebx, load_24khz_mono_8_bit
chk_24khz_2:
	; 30/11/2024 (TRDOS 386, 32bit DOS)
	mov	eax, 8192
	; 17/11/2024
	;mov	ax, 8190
	mov	edx, 2
	mov	ecx, 1
	jmp	short set_sizes 
chk_32khz:
	cmp	ax, 32000
	jne	short vra_needed
	cmp	byte [WAVE_BitsPerSample], 8
	jna	short chk_32khz_1
	mov	ebx, load_32khz_stereo_16_bit
	cmp	byte [WAVE_NumChannels], 1 
	jne	short chk_32khz_2
	mov	ebx, load_32khz_mono_16_bit
	jmp	short chk_32khz_2
chk_32khz_1:
	mov	ebx, load_32khz_stereo_8_bit
	cmp	byte [WAVE_NumChannels], 1 
	jne	short chk_32khz_2
	mov	ebx, load_32khz_mono_8_bit
chk_32khz_2:
	; 30/11/2024 (TRDOS 386, 32bit DOS)
	mov	eax, 10922
	; 17/11/2024
	;mov	ax, 10920
	mov	edx, 3
	mov	ecx, 2
	;jmp	short set_sizes 
set_sizes:
	; 30/11/2024 (TRDOS 386, 32bit DOS)
	;;;
	; 17/11/2024
	push	ecx
	mov	cl, 2
	sub	cl, [fbs_shift]
		; = 2 for 16 bit stereo 
		; = 1 for 16 bit mono or 8 bit stereo
		; = 0 for 8 bit mono
	shl	eax, cl
	pop	ecx	
	mov	[loadsize], eax	; (one) read count in bytes 
	;;;
	mul	edx
	cmp	ecx, 1
	je	short s_2
s_1:
	div	ecx
s_2:	
	;;;
	; eax = byte count of (to be) converted samples 
	
	; 17/11/2024
	;;;
	mov	cl, [fbs_shift]

	shl	eax, cl
		; *1 for 16 bit stereo
		; *2 for 16 bit mono or 8 bit stereo
		; *4 for for 8 bit mono
	;;;

	; eax = 16 bit stereo byte count (target buffer size)
	
	shr	eax, 1	; buffer size is 16 bit sample count
	mov	[buffersize], eax 
	mov	[loadfromwavfile], ebx
	jmp	short PlayNow

vra_needed:
	; 30/11/2024 (TRDOS 386, ax -> eax)
	; 13/11/2023
	pop	eax ; discard return address to the caller
	; 30/05/2024
vra_err:
	; 30/11/2024
	sys	_msg, msg_no_vra, 255, 0Fh 
	jmp	Exit


	; 01/12/2024 (32bit)
PlayNow:
	;;;
	; 14/11/2024
	;mov	al, 3	; 0 = max, 31 = min
	; 14/12/2024
	mov	al, [volume]
	call	SetPCMOutVolume@
	; 15/11/2024
	;;call	SetMasterVolume
	;call	SetPCMOutVolume

	;;;
	; 18/12/2024
	cmp	dword [_bdl_buffer], 0
	ja	short PlayNow@
	;
	;; 29/11/2024
	;cmp	byte [IsInSplash], 0
	;;ja	short PlayNow@
	;; 02/12/2024
	;jna	short PlayNow@
	;;;

;PlayNow@:
	; 28/11/2024
	;cmp	byte [IsInSplash], 0
	;ja	short _3
	;
	;call	UpdateVolume
	;
	; 02/12/2024
	call    PlayWav@
	jmp	short _3

	; 02/12/2024
PlayNow@:
	; reset file loading and EOF parameters
	; 18/12/2024
	mov	dword [count], 0
	mov	dword [LoadedDataBytes], 0
	mov	byte [flags], 0
	mov	byte [stopped], 0
	;jmp	short PlayNow@@
	;;;

PlayNow@@:
	;;;
	;
	; 14/11/2024
	call	UpdateProgressBar
	;;;

 	; 30/05/2024
	; playwav4.asm
_2:	
	call	check4keyboardstop	; flush keyboard buffer
	jc	short _2		; 07/11/2023

; play the .wav file. Most of the good stuff is in here.
	
	; 05/12/2024
	; 02/12/2024
	;mov	eax, [_bdl_buffer]	; BDL_BUFFER physical address
;_3:
	call    PlayWav

_3:	; 02/12/2024
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
	jmp	short Exit

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

	; 02/12/2024
PlayWav@:
	; 29/05/2024
	; Allocate memory block (33 pages)
	sys	_alloc, BDL_BUFFER, 33*4096, 0	; no upper limit
	;jc	short Player_Quit ; 01/12/2024
	jc	short Player_Quit@ ; 02/12/2024

	mov	[_bdl_buffer], eax ; BDL_BUFFER physical address
	; 02/12/2024
	jmp	short PlayWav@@

	; 01/12/2024
	; 29/05/2024 (TRDOS 386, playwav7.s)
	; ((Modified from playwav4.asm, ich_wav4.asm))
	; ------------------
;playwav_vra:
PlayWav:
	; create Buffer Descriptor List

	;  Generic Form of Buffer Descriptor
	;  ---------------------------------
	;  63   62    61-48    47-32   31-0
	;  ---  ---  --------  ------- -----
	;  IOC  BUP -reserved- Buffer  Buffer
	;		      Length   Pointer
	;		      [15:0]   [31:0]

	;mov	esi, eax

	mov	eax, [_bdl_buffer] ; BDL_BUFFER physical address

PlayWav@@:	; 02/12/2024

	add	eax, 4096	; WAVBUFFER_1 physical address
	mov	ebx, eax
	;mov	[wav_buffer1], eax
	;add	eax, 65536	; WAVBUFFER_2 physical address
	;mov	[wav_buffer2], eax

	mov	edi, BDL_BUFFER
	mov	ecx, 16
_0:
	;mov	eax, WAVBUFFER_1
	mov	eax, ebx	; WAVBUFFER_1 physical address
	stosd

	mov	eax, [buffersize]
	; 02/12/2024
	;shr	eax, 1 ; buffer size in word
	or	eax, BUP	; tuneloop (without interrupt)
	stosd

	;mov	eax, WAVBUFFER_2
	mov	eax, ebx
	add	eax, 65536	; WAVBUFFER_2 physical address
	stosd

	mov	eax, [buffersize]
	; 02/12/2024
	;shr	eax, 1 ; buffer size in word
	or	eax, BUP	; tuneloop (without interrupt)
	stosd

	loop	_0

	; 14/11/2024
	;mov	dword [count], ecx ; 0
	;mov	dword [LoadedDataBytes], 0

	; 19/11/2024
RePlayWav:
	; 01/12/2024
	; load 64k into buffer 1
	mov	edi, WAVBUFFER_1
	call	dword [loadfromwavfile]
	; 01/12/2024
	; 14/11/2024
	mov	eax, [count]
	add	[LoadedDataBytes], eax

	; 18/12/2024
	mov	dword [count], 0

	; and 64k into buffer 2
	mov	edi, WAVBUFFER_2
	call	dword [loadfromwavfile]
	; 01/12/2024
	; 14/11/2024
	mov	eax, [count]
	add	[LoadedDataBytes], eax
	
	; write NABMBAR+10h with offset of buffer descriptor list

       	;;mov	eax, BDL_BUFFER
        ;mov	eax, esi	; BDL_BUFFER physical address

	;mov	eax, [_bdl_buffer] ; BDL_BUFFER physical address
	; 02/12/2024
	mov	ebx, [_bdl_buffer] 

	mov	dx, [NABMBAR]
        add     dx, PO_BDBAR_REG	; set pointer to BDL
	;out	dx, eax 		; write to AC97 controller
	; 29/05/2024
	;mov	ebx, eax ; data, dword
	; 02/12/2024
	; ebx = [_bdl_buffer] ; data, dword
	mov	ah, 5	; write port dword
	int	34h

	; 31/05/2024
	; 19/05/2024
	;call	delay1_4ms

        mov	al, 31
	call	setLastValidIndex

	; 31/05/2024
	; 19/05/2024
	;call	delay1_4ms

	; 17/02/2017
        mov	dx, [NABMBAR]
        add	dx, PO_CR_REG		; PCM out Control Register
        ;mov	al, IOCE + RPBM	; Enable 'Interrupt On Completion' + run
	;			; (LVBI interrupt will not be enabled)
	; 06/11/2023 (TUNELOOP version, without interrupt)
	mov	al, RPBM
	;out	dx, al			; Start bus master operation.
	; 29/05/2024
	; al = data, byte
	mov	ah, 1 ; write port, byte
	int	34h

	; 19/05/2024
	; 06/11/2023
	;call	delay1_4ms	; 31/05/2024
	;call	delay1_4ms
	;call	delay1_4ms
	;call	delay1_4ms

; while DMA engine is running, examine current index and wait until it hits 1
; as soon as it's 1, we need to refresh the data in wavbuffer1 with another
; 64k. Likewise when it's playing buffer 2, refresh buffer 1 and repeat.

; 18/11/2023
; 08/11/2023
; 07/11/2023

	; 19/11/2024
	mov	byte [wleds], 1
	
	;;;
	; 09/12/2024
	mov	eax, 10548 ; (48000*10/182)*4
	cmp	byte [VRA], 0
	jna	short sL0 ; 48kHZ (interpolation)	
	;;;
	; 01/12/2024 (32bit)
	;movzx	eax, word [WAVE_SampleRate]
	; 09/12/2024
	mov	ax, [WAVE_SampleRate]
	mov	ecx, 10
	mul	ecx
	mov	cl, 182
	div	ecx
	; ax = samples per 1/18.2 second
	;mov	cl, byte [WAVE_BlockAlign]
	; 09/12/2024 
	;mov	cl, 4 ; 16 bit, stereo
	;mul	ecx
	shl	eax, 2 ; * 4
sL0:
	mov	[wleds_dif], eax ; buffer read differential (distance)
				; for wave volume leds update
				; (byte stream per 1/18.2 second)

	; 28/11/2024
	cmp	byte [IsInSplash], 0
	jna	short tuneLoop	; 18/12/2024

sL1:
	call	updateLVI	; /set LVI != CIV/
	jz	short sL3
	call	getCurrentIndex
	test	al, BIT0
	jz	short sL1	; loop if buffer 2 is not playing

	; load buffer 1
	;mov	ax, [WAV_BUFFER1]
	;call	word [loadfromwavfile]
	; 01/12/2024
	mov	edi, WAVBUFFER_1
	call	dword [loadfromwavfile]
	jc	short sL3
sL2:
	call	updateLVI
	jz	short sL3
	call	getCurrentIndex
	test	al, BIT0
	jnz	short sL2	; loop if buffer 1 is not playing

	; load buffer 2
	;mov	ax, [WAV_BUFFER2]
	;call	word [loadfromwavfile]
	; 01/12/2024
	mov	edi, WAVBUFFER_2
	call	dword [loadfromwavfile]
	jnc	short sL1
sL3:
	mov	dx, [NABMBAR]
	add	dx, PO_CR_REG	; PCM out Control Register
	mov	al, 0
	;out	dx, al		; stop player
	; 01/12/2024
	; al = data, byte
	mov	ah, 1  ; write port, byte
	int	34h

	; 01/12/2024
	; 29/11/2024
	;; reset file loading and EOF parameters
	;;mov	dword [count], 0
	;mov	dword [LoadedDataBytes], 0
	;mov	byte [flags], 0

	retn

	; 01/12/2024 (32bit)
	; 29/11/2024
tuneLoop:
	; 30/05/2024
	; 18/11/2023 (ich_wav4.asm)
	; 08/11/2023
	; 06/11/2023

tLWait:
	; 18/11/2024
	cmp	byte [stopped], 0
	;jna	short tL@
	; 21/11/2024
	ja	short tLWait@
	mov	al, [tLP]
	cmp	al, '1'
	je	short tL1@
	ja	tL2@
	mov	al, '1'
	mov	[tLP], al
	jmp	short tL1@ 
tLWait@:	; 21/11/2024
	;;;
	; 09/12/2024
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

;tLO:	db 0
	
tL1@:
	;mov	al, '1'
	; 19/11/2024
	mov	[tLO], al
	call	tL0
tL1:
	call	updateLVI	; /set LVI != CIV/
	jz	_exitt_		; 08/11/2023
	;;;
	;call	check4keyboardstop
	; 14/11/2024
	call	checkUpdateEvents
	jc	_exitt_
	; 18/11/2024
	cmp	byte [stopped], 0
	ja	short tLWait@	; 21/11/2024
	;;;
	call	getCurrentIndex
	test	al, BIT0
	jz	short tL1	; loop if buffer 2 is not playing

	; load buffer 1
	;mov	ax, [WAV_BUFFER1]
	; 01/12/2024
	mov	edi, WAVBUFFER_1	

	;call	loadFromFile
	; 18/11/2023
	;call	word [loadfromwavfile]
	; 01/12/2024
	call	dword [loadfromwavfile]
	jc	short _exitt_	; end of file

	; 14/11/2024
	;mov	ax, [count]
	;add	[LoadedDataBytes], ax
	;adc	word [LoadedDataBytes+2], 0
	; 01/12/2024
	mov	eax, [count]
	add	[LoadedDataBytes], eax

	mov	al, '2'
	; 21/11/2024
	mov	[tLP], al
tL2@:
	; 19/11/2024
	mov	[tLO], al
	call	tL0
tL2:
	call    updateLVI
	jz	short _exitt_	; 08/11/2023
	;;;
	;call	check4keyboardstop
	; 14/11/2024
	call	checkUpdateEvents
	jc	short _exitt_
	; 18/11/2024
	cmp	byte [stopped], 0
	ja	tLWait@		; 21/11/2024 
	;;;
	call    getCurrentIndex
	test	al, BIT0
	jnz	short tL2	; loop if buffer 1 is not playing

	; load buffer 2
	;mov	ax, [WAV_BUFFER2]
	; 01/12/2024
	mov	edi, WAVBUFFER_2
	;call	loadFromFile
	; 18/11/2023
	;call	word [loadfromwavfile]
	; 01/12/2024
	call	dword [loadfromwavfile]
	;jnc	short tuneLoop
	jc	short _exitt_

	; 14/11/2024
	;mov	ax, [count]
	;add	[LoadedDataBytes], ax
	;adc	word [LoadedDataBytes+2], 0
	; 01/12/2024
	mov	eax, [count]
	add	[LoadedDataBytes], eax	

	; 21/11/2024
	mov	byte [tLP], '1'
	jmp	tuneLoop
_exitt_:
	mov	dx, [NABMBAR]
	add	dx, PO_CR_REG	; PCM out Control Register
	mov	al, 0
	;out	dx, al		; stop player
	; 29/05/2024
	; al = data, byte
	mov	ah, 1  ; write port, byte
	int	34h

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

	; 14/11/2024
;SetMasterVolume:
	; 15/11/2024
SetPCMOutVolume:
	;cmp	al, 31
	;ja	short setvolume_ok
	mov	[volume], al  ; max = 0, min = 31
SetPCMOutVolume@:	; 19/11/2024
	mov	ah, al
	mov	dx, [NAMBAR]
	; 15/11/2024 (QEMU)
  	;add	dx, CODEC_MASTER_VOL_REG
	add	dx, CODEC_PCM_OUT_REG
	;out	dx, ax
	; 01/12/2024
	; bx = data, word
	; 03/12/2024
	mov	ebx, eax
	mov	ah, 3  ; write port, word
	int	34h
;setvolume_ok:
	retn

; -------------------------------------------

	; 30/05/2024
DetectAC97:
DetectICH:
	; 22/11/2023
	; 19/11/2023
	; 01/11/2023 - TRDOS 386 Kernel v2.0.7
	;; 10/06/2017
	;; 05/06/2017
	;; 29/05/2017
	;; 28/05/2017

	; 01/12/2024
	; 19/11/2023
	mov	esi, valid_ids	; address of Valid ICH (AC97) Device IDs
	mov	ecx, valid_id_count
pfd_1:
	lodsd
	call	pciFindDevice
	jnc	short d_ac97_1
	loop	pfd_1

	;stc
	retn

d_ac97_1:
	; eax = BUS/DEV/FN
	;	00000000BBBBBBBBDDDDDFFF00000000
	; edx = DEV/VENDOR
	;	DDDDDDDDDDDDDDDDVVVVVVVVVVVVVVVV

	; playwav4.asm - 19/05/2024

	mov	[bus_dev_fn], eax
	mov	[dev_vendor], edx

	; get ICH base address regs for mixer and bus master

        mov     al, NAMBAR_REG
        call    pciRegRead16			; read PCI registers 10-11
        ;and    dx, IO_ADDR_MASK 		; mask off BIT0
	; 19/05/2024
	and	dl, 0FEh

        mov     [NAMBAR], dx			; save audio mixer base addr

	mov     al, NABMBAR_REG
        call    pciRegRead16
        ;and    dx, IO_ADDR_MASK
	; 19/05/2024
	and	dl, 0C0h

        mov     [NABMBAR], dx			; save bus master base addr

	mov	al, AC97_INT_LINE ; Interrupt line register (3Ch)
	call	pciRegRead8 ; 17/02/2017
	
	mov	[ac97_int_ln_reg], dl

	;clc

	retn

; ----------------------------------
	
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

; ----------------------------------

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

	; 14/12/2024
	; 01/12/2024
	; 30/05/2024 (ich_wav4.asm, 19/05/2024)
loadFromFile:
	; 07/11/2023

        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff_0		; no
	stc
	retn

lff_0:
	; 08/11/2023
	;mov	bp, ax ; save buffer segment

	; 01/12/2024 (TRDOS 386)
	; edi = audio buffer address

	; 14/12/2024
	; 01/12/2024
	; 17/11/2024
	;mov	ebx, [filehandle]
	; 02/12/2024
	;mov	edx, [loadsize]
	;xor	di, di ; 0

	;mov	cl, [fbs_shift]
	;and	cl, cl
	;jz	short lff_1 ; stereo, 16 bit
	; 17/11/2024
	cmp	byte [fbs_shift], 0
	jna	short lff_1 ; stereo, 16 bit

lff_2:
	;mov	di, BUFFERSIZE - 1 ; 65535

	;; fbs_shift =
	;;	2 for mono and 8 bit sample (multiplier = 4)
	;;	1 for mono or 8 bit sample (multiplier = 2)
	;shr	di, cl
	;inc	di ; 16384 for 8 bit and mono
	;	   ; 32768 for 8 bit or mono
	
	; 17/11/2024
	;mov	cx, [loadsize] ; 16380 or 32760

	;;mov	ax, cs
	;mov	dx, temp_buffer ; temporary buffer for wav data
	; 01/12/2024
	mov	esi, temp_buffer 

	; 17/02/2017 (stereo/mono, 8bit/16bit corrections)
	; load file into memory
	;mov	cx, di ; 17/11/2024              
	;mov	bx, [filehandle] ; 17/11/2024
	;mov    ds, ax
	; 01/12/2024
	;mov	ah, 3Fh
	;int	21h
	; 14/12/2024
	;sys 	_read, [filehandle], esi ; edx = read count
	; 14/12/2024
	sys 	_read, [filehandle], esi, [loadsize]

	;mov	bx, cs
	;mov	ds, bx
	; 17/11/2024
	;push	cs
	;pop	ds

	jc	lff_4 ; error !

	; 01/12/2024
	; 14/11/2024
	mov	[count], eax

	; 17/11/2024
	; 08/11/2023
	;xor	dx, dx ; 0

	; 01/12/2024
	and	eax, eax
	;jz	short lff_3
	; 14/12/2024
	jz	lff_10

	mov	bl, [fbs_shift]

	; 14/12/2024
	mov	edx, edi ; audio buffer start address

	;push	es
	;;mov	di, dx ; 0 ; [fbs_off]
	;; 17/11/2024
	;; di = 0
	;;mov	bp, [fbs_seg] ; buffer segment
	;mov	es, bp
	;mov	si, temp_buffer ; temporary buffer address
	;mov	cx, ax ; byte count
	; 01/12/2024
	mov	ecx, eax
	cmp	byte [WAVE_BitsPerSample], 8 ; bits per sample (8 or 16)
	jne	short lff_7 ; 16 bit samples
	; 8 bit samples
	dec	bl  ; shift count, 1 = stereo, 2 = mono
	jz	short lff_6 ; 8 bit, stereo
	; 01/12/2024 (32bit registers)
lff_5:
	; mono & 8 bit
	lodsb
	sub	al, 80h ; 08/11/2023
	shl	eax, 8 ; convert 8 bit sample to 16 bit sample
	stosw	; left channel
	stosw	; right channel
	loop	lff_5
	jmp	short lff_9	
lff_6:
	; stereo & 8 bit
	lodsb
	sub	al, 80h ; 08/11/2023
	shl	eax, 8 ; convert 8 bit sample to 16 bit sample
	stosw
	loop	lff_6			
	jmp	short lff_9
lff_7:
	shr	ecx, 1 ; word count
lff_8:
	lodsw
	stosw	; left channel
	stosw	; right channel
	loop	lff_8
lff_9:
	; 01/12/2024
	;pop	es
	
	;or	di, di
	;jz	short endLFF ; 64KB ok 
	;mov	ax, di ; [fbs_off]
	;dec	ax
	;cmp	ax, BUFFERSIZE ; 65520
	;jnb	short endLFF

	;mov	cx, BUFFERSIZE - 1 ; 65535
	; 14/12/2024
	mov	eax, edi
	mov	ecx, [buffersize] 
	add	ecx, edx ; + buffer start address
	; 17/11/2024
	; ax = di
	cmp	eax, ecx
	;jnb	short endLFF
	;jmp	short lff_3
	jb	short lff_3
	retn
	
lff_1:  
	;mov	bp, ax ; save buffer segment

	; 01/12/2024
	;xor	dx, dx
	;mov	esi, edi ; audio_buffer
	; edi = audio buffer

	; load file into memory
        ;mov	cx, (BUFFERSIZE / 2)	; 32k chunk
	
	; 17/11/2024
	;mov	cx, [buffersize] ; BUFFERSIZE / 2
	; 17/11/2024 (*)
	; cx = [loadsize] = 2*[buffersize]
	; 02/12/2024
	; edx = [loadsize]

	;mov	bx, [filehandle] ; 17/11/2024
	;mov	ds, ax ; mov ds, bp
       	;mov	ah, 3Fh
	;int	21h
	; 01/12/2024
	;;sys 	_read, [filehandle], esi
	;sys 	_read, [filehandle], edi ; edx = read count
	; 14/12/2024
	sys 	_read, [filehandle], edi, [loadsize]
	
	;mov	di, cs
	;mov	ds, di
	; 17/11/2024
	;push	cs
	;pop	ds

	; 07/11/2023
	jc	short lff_4 ; error !

	; 01/12/2024
	; 14/11/2024
	mov	[count], eax
	; 17/11/2024
	; di = 0

; 17/11/2024 (*)
if 0	
	cmp	ax, cx
	jne	short lff_3
lff_2:
	; 08/11/2023
	add	dx, ax
	;;mov	cx, (BUFFERSIZE / 2)	; 32k chunk
	;mov	cx, [buffersize] ; BUFFERSIZE / 2
	;mov	bx, [filehandle]
	mov     ds, bp
       	mov	ah, 3Fh
	int	21h

	;;mov	di, cs
	;mov	ds, di
	; 17/11/2024
	push	cs
	pop	ds

	jc	short lff_4 ; error !

	; 17/11/2024
	; 14/11/2024
	add	[count], ax
end if
	; 01/12/2024
	;cmp	ax, cx
	cmp	eax, edx ; 02/12/2024
	je	short endLFF
	; 17/11/2024
	; di = 0
	; 01/12/2024
	;mov	di, ax
	; edi = buffer (start) address
	add	edi, eax
	; 02/12/2024
	mov	ecx, edx
lff_3:
	call    padfill			; blank pad the remainder
        ;clc				; don't exit with CY yet.
        or	byte [flags], ENDOFFILE	; end of file flag
endLFF:
        retn
lff_4:
	; 08/11/2023
	mov	al, '!'  ; error
	call	tL0

	; 01/12/2024
	xor	eax, eax
lff_10:
	; 14/12/2024
	mov	ecx, [buffersize]
	jmp	short lff_3

; entry ds:ax points to last byte in file
; cx = target size
; note: must do byte size fill
; destroys bx, cx
;
padfill:
	; 14/12/2024
	; 01/12/2024 (TRDOS 386, 32bit registers)
	; 17/11/2024
	;   di = offset (to be filled with ZEROs)
	;   bp = buffer segment
	;   ax = di = number of bytes loaded
	;   cx = buffer size (> loaded bytes)	
	; 07/11/2023
	; 06/11/2023
	; 17/02/2017
	;push	es
        ;push	di
	;mov	di, [fbs_seg]
	;mov	es, di
        ;mov	es, bp
	;sub	cx, ax
	; 01/12/2024
	sub	ecx, eax
	; 08/11/2023
	;mov	di, ax ; (wrong)
	; 17/11/2024
	;mov	di, dx ; buffer offset
	;add	di, ax       	
	; 07/11/2023
	;add	di, [fbs_off]
 	; 01/12/2024
	; 25/11/2024
	xor	eax, eax
	; 14/12/2024
	rep	stosb
	;mov	[fbs_off], di
	;pop	di
	;pop	es
	retn
; /////
	
write_audio_dev_info:
	; 30/05/2024
     	;sys_msg msgAudioCardInfo, 0Fh
	; 01/12/2024
	sys 	_msg, msgAudioCardInfo, 255, 0Fh
	retn

write_ac97_pci_dev_info:
	; 19/11/2024
	; 30/05/2024
	; 06/06/2017
	; 03/06/2017
	; BUS/DEV/FN
	;	00000000BBBBBBBBDDDDDFFF00000000
	; DEV/VENDOR
	;	DDDDDDDDDDDDDDDDVVVVVVVVVVVVVVVV

	mov	eax, [dev_vendor]
	; 07/12/2024
	xor	ebx, ebx
	mov	bl, al
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
	shr	eax, 16
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

	mov	eax, [bus_dev_fn]
	shr	eax, 8
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

	;mov	ax, [ac97_NamBar]
	mov	ax, [NAMBAR]
	mov	bl, al
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [ebx+hex_chars]
	mov	[msgNamBar+3], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [ebx+hex_chars]
	mov	[msgNamBar+2], al
	mov	bl, ah
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [ebx+hex_chars]
	mov	[msgNamBar+1], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [ebx+hex_chars]
	mov	[msgNamBar], al

	;mov	ax, [ac97_NabmBar]
	mov	ax, [NABMBAR]
	mov	bl, al
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [ebx+hex_chars]
	mov	[msgNabmBar+3], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [ebx+hex_chars]
	mov	[msgNabmBar+2], al
	mov	bl, ah
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [ebx+hex_chars]
	mov	[msgNabmBar+1], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [ebx+hex_chars]
	mov	[msgNabmBar], al

	xor	eax, eax
	mov	al, [ac97_int_ln_reg]
	mov	cl, 10
	div	cl
	; 23/11/2024
	;add	[msgIRQ], ax
	add	ax, 3030h
	mov	[msgIRQ], ax
	;and	al, al
	cmp	al, 30h
	jnz	short _w_ac97imsg_
	mov	al, byte [msgIRQ+1]
	mov	ah, ' '
	mov	[msgIRQ], ax
_w_ac97imsg_:
	; 19/11/2024
	call 	clear_window
	mov	dh, 13
	mov	dl, 0
	call	setCursorPosition
	;;;
	; 30/05/2024
	;sys_msg msgAC97Info, 07h
	; 01/12/2024
	sys	_msg, msgAC97Info, 255, 07h

	; 19/11/2024
        ;retn

	; 30/05/2024
write_VRA_info:
	;sys_msg msgVRAheader, 07h
	; 01/12/2024
	sys	_msg, msgVRAheader, 255, 07h
	cmp	byte [VRA], 0
	jna	short _w_VRAi_no
_w_VRAi_yes:
	;sys_msg msgVRAyes, 07h
	sys	_msg, msgVRAyes, 255, 07h
	retn
_w_VRAi_no:
	;sys_msg msgVRAno, 07h
	sys	_msg, msgVRAno, 255, 07h
	retn

; 01/12/2024 - ac97play.s
; 29/05/2024
; 26/11/2023
; 25/11/2023 - playwav6.s (32 bit registers, TRDOS 386 adaption)
; 15/11/2023 - PLAYWAV5.COM, ich_wav5.asm
; 14/11/2023
; 13/11/2023 - Erdogan Tan - (VRA, sample rate conversion)
; --------------------------------------------------------

;;Note:	At the end of every buffer load,
;;	during buffer switch/swap, there will be discontinuity
;;	between the last converted sample and the 1st sample
;;	of the next buffer.
;;	(like as a dot noises vaguely between normal sound samples)
;;	-To avoid this defect, the 1st sample of
;;	the next buffer may be read from the wav file but
;;	the file pointer would need to be set to 1 sample back
;;	again via seek system call. Time comsumption problem! -
;;
;;	Erdogan Tan - 15/11/2023
;;
;;	((If entire wav data would be loaded at once.. conversion
;;	defect/noise would disappear.. but for DOS, to keep
;;	64KB buffer limit is important also it is important
;;	for running under 1MB barrier without HIMEM.SYS or DPMI.
;;	I have tested this program by using 2-30MB wav files.))
;;
;;	Test Computer:	ASUS desktop/mainboard, M2N4-SLI, 2010.
;;			AMD Athlon 64 X2 2200 MHZ CPU.
;;		       	NFORCE4 (CK804) AC97 audio hardware.
;;			Realtek ALC850 codec.
;;		       	Retro DOS v4.2 (MSDOS 6.22) operating system.

load_8khz_mono_8_bit:
	; 15/11/2023
	; 14/11/2023
	; 13/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff8m_0		; no
	stc
	retn

lff8m_0:
	; 01/12/2024
	; edi = audio buffer address
	; 13/12/2024
	mov	[audio_buffer], edi
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jnc	short lff8m_6
	jmp	lff8m_5  ; error !

lff8m_6:
	; 01/12/2024
	mov	[count], eax
	;mov	edi, audio_buffer
	; 29/05/2024
	mov	edi, [audio_buffer]
	;and	eax, eax
	jz	lff8_eof

	mov	ecx, eax		; byte count
lff8m_1:
	lodsb
	mov	[previous_val], al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (left channel)
	stosw		; original sample (right channel)
	;xor	eax, eax
	mov	al, 80h
	dec	ecx
	jz	short lff8m_2
	mov	al, [esi]
lff8m_2:
	;mov	[next_val], ax
	mov	bh, al	; [next_val]
	mov	ah, [previous_val]
	add	al, ah	; [previous_val]
	rcr	al, 1
	mov	dl, al	; this is interpolated middle (3th) sample
	add	al, ah	; [previous_val]
	rcr	al, 1	
	mov	bl, al 	; this is temporary interpolation value
	add	al, ah	; [previous_val]
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	
	stosw		; this is 1st interpolated sample (L)
	stosw		; this is 1st interpolated sample (R)
	mov	al, bl
	add	al, dl
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is 2nd interpolated sample (L)
	stosw		; this is 2nd interpolated sample (R)
	mov	al, dl
	sub	al, 80h
	shl	ax, 8
	stosw		; this is middle (3th) interpolated sample (L)
	stosw		; this is middle (3th) interpolated sample (R)
	;mov	al, [next_val]
	mov	al, bh
	add	al, dl
	rcr	al, 1
	mov	bl, al	; this is temporary interpolation value
	add	al, dl
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is 4th interpolated sample (L)
	stosw		; this is 4th interpolated sample (R)
	;mov	al, [next_val]
	mov	al, bh
	add	al, bl
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is 5th interpolated sample (L)
	stosw		; this is 5th interpolated sample (R)
	; 8 kHZ mono to 48 kHZ stereo conversion of the sample is OK
	or	ecx, ecx
	jnz	short lff8m_1

	; --------------

lff8s_3:
lff8m_3:
lff8s2_3:
lff8m2_3:
lff16s_3:
lff16m_3:
lff16s2_3:
lff16m2_3:
lff24_3:
lff32_3:
lff44_3:
lff22_3:
lff11_3:
	; 08/12/2024 (BugFix)
	; 31/05/2024
	mov	ecx, [buffersize] ; buffer size in words
	; 08/12/2024
	shl	ecx, 1 ; buffer size in bytes
	; 13/12/2024
	add	ecx, [audio_buffer] ; + start address of the buffer
	sub	ecx, edi
	jna	short lff8m_4
	;inc	ecx
	shr	ecx, 2
	xor	eax, eax ; fill (remain part of) buffer with zeros
	rep	stosd
lff8m_4:
	; 31/05/2024
	; cf=1
	; 08/12/2024
	;clc
	retn

lff8_eof:
lff16_eof:
lff24_eof:
lff32_eof:
lff44_eof:
lff22_eof:
lff11_eof:
	; 15/11/2023
	mov	byte [flags], ENDOFFILE
	jmp	short lff8m_3

lff8s_5:
lff8m_5:
lff8s2_5:
lff8m2_5:
lff16s_5:
lff16m_5:
lff16s2_5:
lff16m2_5:
lff24_5:
lff32_5:
lff44_5:
lff22_5:
lff11_5:
	mov	al, '!'  ; error
	call	tL0
	
	;jmp	short lff8m_3
	; 15/11/2023
	jmp	lff8_eof

	; --------------

load_8khz_stereo_8_bit:
	; 15/11/2023
	; 14/11/2023
	; 13/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff8s_0		; no
	stc
	retn

lff8s_0:
	; 01/12/2024
	; edi = audio buffer address
	; 13/12/2024
	mov	[audio_buffer], edi
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff8s_5 ; error !

	; 01/12/2024
	mov	[count], eax

	;mov	edi, audio_buffer
	; 29/05/2024
	;mov	edi, [audio_buffer]
	
	shr	eax, 1
	jz	short lff8_eof

	mov	ecx, eax	; word count
lff8s_1:
	lodsb
	mov	[previous_val_l], al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (L)
	lodsb
	mov	[previous_val_r], al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (R)

	;xor	eax, eax
	mov	ax, 8080h
	dec	ecx
	jz	short lff8s_2
		; convert 8 bit sample to 16 bit sample
	mov	ax, [esi]
lff8s_2:
	mov	[next_val_l], al
	mov	[next_val_r], ah
	mov	ah, [previous_val_l]
	add	al, ah
	rcr	al, 1
	mov	dl, al	; this is interpolated middle (3th) sample (L)
	add	al, ah
	rcr	al, 1
	mov	bl, al	; this is temporary interpolation value (L)
	add	al, ah
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is 1st interpolated sample (L)
	mov	al, [next_val_r]
	mov	ah, [previous_val_r]
	add	al, ah
	rcr	al, 1
	mov	dh, al	; this is interpolated middle (3th) sample (R)
	add	al, ah
	rcr	al, 1
	mov	bh, al	; this is temporary interpolation value (R)
	add	al, ah
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is 1st interpolated sample (R)
	mov	al, bl
	add	al, dl
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is 2nd interpolated sample (L)
	mov	al, bh
	add	al, dh
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw 		; this is 2nd interpolated sample (R)
	mov	al, dl
	sub	al, 80h
	shl	ax, 8
	stosw		; this is middle (3th) interpolated sample (L)
	mov	al, dh
	sub	al, 80h
	shl	ax, 8
	stosw		; this is middle (3th) interpolated sample (R)
	mov	al, [next_val_l]
	add	al, dl
	rcr	al, 1
	mov	bl, al	; this is temporary interpolation value (L)
	add	al, dl
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is 4th interpolated sample (L)
	mov	al, [next_val_r]
	add	al, dh
	rcr	al, 1
	mov	bh, al	; this is temporary interpolation value (R)
	add	al, dh
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is 4th interpolated sample (R)
	mov	al, [next_val_l]
	add	al, bl
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is 5th interpolated sample (L)
	mov	al, [next_val_r]
	add	al, bh
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is 5th interpolated sample (R)
	; 8 kHZ stereo to 48 kHZ stereo conversion of the sample is OK
	jecxz	lff8s_6
	jmp	lff8s_1
lff8s_6:
	jmp	lff8s_3

load_8khz_mono_16_bit:
	; 13/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff8m2_0		; no
	stc
	retn

lff8m2_0:
	; 01/12/2024
	; edi = audio buffer address
	; 13/12/2024
	mov	[audio_buffer], edi
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	lff8m2_7 ; error !

	; 01/12/2024
	mov	[count], eax

	;mov	edi, audio_buffer
	; 29/05/2024
	;mov	edi, [audio_buffer]
	
	shr	eax, 1
	jnz	short lff8m2_8
	jmp	lff8_eof

lff8m2_8:
	mov	ecx, eax	; word count
lff8m2_1:
	lodsw
	stosw		; original sample (left channel)
	stosw		; original sample (right channel)
	add	ah, 80h	; convert sound level to 0-65535 format
	mov	[previous_val], ax
	xor	eax, eax
	dec	ecx
	jz	short lff8m2_2
	mov	ax, [esi]
lff8m2_2:
	add	ah, 80h ; convert sound level to 0-65535 format
	mov	ebp, eax	; [next_val]
	add	ax, [previous_val]
	rcr	ax, 1
	mov	edx, eax ; this is interpolated middle (3th) sample
	add	ax, [previous_val]
	rcr	ax, 1	; this is temporary interpolation value
	mov	ebx, eax 		
	add	ax, [previous_val]
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; this is 1st interpolated sample (L)
	stosw		; this is 1st interpolated sample (R)
	mov	eax, ebx
	add	ax, dx
	rcr	ax, 1
	sub	ah, 80h
	stosw		; this is 2nd interpolated sample (L)
	stosw		; this is 2nd interpolated sample (R)
	mov	eax, edx
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; this is middle (3th) interpolated sample (L)
	stosw		; this is middle (3th) interpolated sample (R)
	mov	eax, ebp
	add	ax, dx
	rcr	ax, 1
	mov	ebx, eax ; this is temporary interpolation value
	add	ax, dx
	rcr	ax, 1
	sub	ah, 80h
	stosw		; this is 4th interpolated sample (L)
	stosw		; this is 4th interpolated sample (R)
	mov	eax, ebp
	add	ax, bx
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; this is 5th interpolated sample (L)
	stosw		; this is 5th interpolated sample (R)
	; 8 kHZ mono to 48 kHZ stereo conversion of the sample is OK
	or	ecx, ecx
	jnz	lff8m2_1
	jmp	lff8m2_3

lff8m2_7:
lff8s2_7:
	jmp	lff8m2_5  ; error

load_8khz_stereo_16_bit:
	; 16/11/2023
	; 15/11/2023
	; 13/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff8s2_0		; no
	stc
	retn

lff8s2_0:
	; 01/12/2024
	; edi = audio buffer address
	; 13/12/2024
	mov	[audio_buffer], edi
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff8s2_7 ; error !

	; 01/12/2024
	mov	[count], eax

	;mov	edi, audio_buffer
	; 29/05/2024
	;mov	edi, [audio_buffer]
	
	shr	eax, 2
	jnz	short lff8s2_8
	jmp	lff8_eof

lff8s2_8:
	mov	ecx, eax ; dword count
lff8s2_1:
	lodsw
	stosw		; original sample (L)
	; 15/11/2023
	add	ah, 80h	; convert sound level to 0-65535 format
	mov	[previous_val_l], ax
	lodsw
	stosw		; original sample (R)
	add	ah, 80h	; convert sound level to 0-65535 format
	mov	[previous_val_r], ax
	xor	edx, edx
	xor	eax, eax
	; 16/11/2023
	dec	ecx
	jz	short lff8s2_2
	mov	ax, [esi]
	mov	dx, [esi+2]
lff8s2_2:
	add	ah, 80h	; convert sound level to 0-65535 format
	mov	[next_val_l], ax
	add	dh, 80h	; convert sound level to 0-65535 format
	mov	[next_val_r], dx
	add	ax, [previous_val_l]
	rcr	ax, 1
	mov	edx, eax ; this is interpolated middle (3th) sample (L)
	add	ax, [previous_val_l]
	rcr	ax, 1	
	mov	ebx, eax ; this is temporary interpolation value (L)
	add	ax, [previous_val_l]
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; this is 1st interpolated sample (L)
	mov	ax, [next_val_r]
	add	ax, [previous_val_r]
	rcr	ax, 1
	mov	ebp, eax ; this is interpolated middle (3th) sample (R)
	add	ax, [previous_val_r]
	rcr	ax, 1
	push	eax ; *	; this is temporary interpolation value (R)
	add	ax, [previous_val_r]
	rcr	ax, 1
	sub	ah, 80h
	stosw		; this is 1st interpolated sample (R)
	mov	eax, ebx
	add	ax, dx
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; this is 2nd interpolated sample (L)
	pop	eax ; *
	add	ax, bp
	rcr	ax, 1
	sub	ah, 80h
	stosw 		; this is 2nd interpolated sample (R)
	mov	eax, edx
	sub	ah, 80h
	stosw		; this is middle (3th) interpolated sample (L)
	mov	eax, ebp
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; this is middle (3th) interpolated sample (R)
	mov	ax, [next_val_l]
	add	ax, dx
	rcr	ax, 1
	mov	ebx, eax ; this is temporary interpolation value (L)
	add	ax, dx
	rcr	ax, 1
	sub	ah, 80h
	stosw		; this is 4th interpolated sample (L)
	mov	ax, [next_val_r]
	add	ax, bp
	rcr	ax, 1
	push	eax ; ** ; this is temporary interpolation value (R)
	add	ax, bp
	rcr	ax, 1
	sub	ah, 80h
	stosw		; this is 4th interpolated sample (R)
	mov	ax, [next_val_l]
	add	ax, bx
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; this is 5th interpolated sample (L)
	pop	eax ; **
	add	ax, [next_val_r]
	rcr	ax, 1
	sub	ah, 80h
	stosw		; this is 5th interpolated sample (R)
	; 8 kHZ stereo to 48 kHZ stereo conversion of the sample is OK
	jecxz	lff8_s2_9
	jmp	lff8s2_1
lff8_s2_9:
	jmp	lff8s2_3

; .....................

load_16khz_mono_8_bit:
	; 14/11/2023
	; 13/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff16m_0		; no
	stc
	retn

lff16m_0:
	; 01/12/2024
	; edi = audio buffer address
	; 13/12/2024
	mov	[audio_buffer], edi
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff16m_7 ; error !

	; 01/12/2024
	mov	[count], eax

	;mov	edi, audio_buffer
	; 29/05/2024
	;mov	edi, [audio_buffer]
	
	and	eax, eax
	jnz	short lff16m_8
	jmp	lff16_eof

lff16m_8:
	mov	ecx, eax		; byte count
lff16m_1:
	lodsb
	;mov	[previous_val], al
	mov	bl, al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (left channel)
	stosw		; original sample (right channel)
	;xor	ax, ax
	; 14/11/22023
	mov	al, 80h
	dec	ecx
	jz	short lff16m_2
	mov	al, [esi]
lff16m_2:
	;mov	[next_val], al
	mov	bh, al
	;add	al, [previous_val]
	add	al, bl
	rcr	al, 1
	mov	dl, al	; this is interpolated middle (temp) sample
	;add	al, [previous_val]
	add	al, bl
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is 1st interpolated sample (L)
	stosw		; this is 1st interpolated sample (R)
	;mov	al, [next_val]
	mov	al, bh
	add	al, dl
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is 2nd interpolated sample (L)
	stosw		; this is 2nd interpolated sample (R)
	
	; 16 kHZ mono to 48 kHZ stereo conversion of the sample is OK
	or	ecx, ecx
	jnz	short lff16m_1
	jmp	lff16m_3

lff16m_7:
lff16s_7:
	jmp	lff16m_5  ; error

load_16khz_stereo_8_bit:
	; 14/11/2023
	; 13/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff16s_0		; no
	stc
	retn

lff16s_0:
	; 01/12/2024
	; edi = audio buffer address
	; 13/12/2024
	mov	[audio_buffer], edi
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff16s_7 ; error !

	; 01/12/2024
	mov	[count], eax

	;mov	edi, audio_buffer
	; 29/05/2024
	;mov	edi, [audio_buffer]
	
	shr	eax, 1
	jnz	short lff16s_8
	jmp	lff16_eof

lff16s_8:
	mov	ecx, eax	; word count
lff16s_1:
	lodsb
	mov	[previous_val_l], al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (L)
	lodsb
	mov	[previous_val_r], al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (R)

	;xor	eax, eax
	mov	ax, 8080h
	dec	ecx
	jz	short lff16s_2
		; convert 8 bit sample to 16 bit sample
	mov	ax, [esi]
lff16s_2:
	;mov	[next_val_l], al
	;mov	[next_val_r], ah
	mov	ebx, eax
	add	al, [previous_val_l]
	rcr	al, 1
	mov	dl, al	; this is temporary interpolation value (L)
	add	al, [previous_val_l]
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is 1st interpolated sample (L)
	mov	al, bh	; [next_val_r]
	add	al, [previous_val_r]
	rcr	al, 1
	mov	dh, al	; this is temporary interpolation value (R)
	add	al, [previous_val_r]
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is 1st interpolated sample (R)
	mov	al, dl
	add	al, bl	; [next_val_l]
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is 2nd interpolated sample (L)
	mov	al, dh
	add	al, bh	; [next_val_r]
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw 		; this is 2nd interpolated sample (R)
	
	; 16 kHZ stereo to 48 kHZ stereo conversion of the sample is OK
	or	ecx, ecx
	jnz	short lff16s_1
	jmp	lff16s_3

load_16khz_mono_16_bit:
	; 15/11/2023
	; 13/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff16m2_0		; no
	stc
	retn

lff16m2_0:
	; 01/12/2024
	; edi = audio buffer address
	; 13/12/2024
	mov	[audio_buffer], edi
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff16m2_7 ; error !

	; 01/12/2024
	mov	[count], eax

	;mov	edi, audio_buffer
	; 29/05/2024
	;mov	edi, [audio_buffer]
	
	shr	eax, 1
	jnz	short lff16m2_8
	jmp	lff16_eof

lff16m2_8:
	mov	ecx, eax  ; word count
lff16m2_1:
	lodsw
	stosw		; original sample (left channel)
	stosw		; original sample (right channel)
	add	ah, 80h ; convert sound level 0 to 65535 format
	;mov	[previous_val], ax
	mov	ebx, eax
	xor	eax, eax
	dec	ecx
	jz	short lff16m2_2
	mov	ax, [esi]
lff16m2_2:
	add	ah, 80h ; convert sound level 0 to 65535 format
	mov	ebp, eax	; [next_val]
	;add	ax, [previous_val]
	add	ax, bx
	rcr	ax, 1
	mov	edx, eax ; this is temporary interpolation value
	;add	ax, [previous_val]
	add	ax, bx
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; this is 1st interpolated sample (L)
	stosw		; this is 1st interpolated sample (R)
	mov	eax, ebp
	add	ax, dx
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; this is 2nd interpolated sample (L)
	stosw		; this is 2nd interpolated sample (R)
	; 16 kHZ mono to 48 kHZ stereo conversion of the sample is OK
	or	ecx, ecx
	jnz	short lff16m2_1
	jmp	lff16m2_3

lff16m2_7:
lff16s2_7:
	jmp	lff16m2_5  ; error

load_16khz_stereo_16_bit:
	; 16/11/2023
	; 15/11/2023
	; 13/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff16s2_0		; no
	stc
	retn

lff16s2_0:
	; 01/12/2024
	; edi = audio buffer address
	; 13/12/2024
	mov	[audio_buffer], edi
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff16s2_7 ; error !

	; 01/12/2024
	mov	[count], eax

	;mov	edi, audio_buffer
	; 29/05/2024
	;mov	edi, [audio_buffer]
	
	shr	eax, 2
	jnz	short lff16s2_8
	jmp	lff16_eof

lff16s2_8:
	mov	ecx, eax  ; dword count
lff16s2_1:
	lodsw
	stosw		; original sample (L)
	add	ah, 80h	; convert sound level 0 to 65535 format
	mov	[previous_val_l], ax
	lodsw
	stosw		; original sample (R)
	add	ah, 80h	; convert sound level 0 to 65535 format
	mov	[previous_val_r], ax
	xor	edx, edx
	xor	eax, eax
	; 16/11/2023
	dec	ecx
	jz	short lff16s2_2
	mov	ax, [esi]
	mov	dx, [esi+2]
lff16s2_2:
	add	ah, 80h	; convert sound level 0 to 65535 format
	;mov	[next_val_l], ax
	mov	ebp, eax
	add	dh, 80h	; convert sound level 0 to 65535 format
	mov	[next_val_r], dx
	add	ax, [previous_val_l]
	rcr	ax, 1
	mov	edx, eax ; this is temporary interpolation value (L)
	add	ax, [previous_val_l]
	rcr	ax, 1
	sub	ah, 80h ; -32768 to +32767 format again
	stosw		; this is 1st interpolated sample (L)
	mov	ax, [next_val_r]
	add	ax, [previous_val_r]
	rcr	ax, 1
	mov	ebx, eax ; this is temporary interpolation value (R)
	add	ax, [previous_val_r]
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; this is 1st interpolated sample (R)
	;mov	ax, [next_val_l]
	mov	eax, ebp
	add	ax, dx
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; this is 2nd interpolated sample (L)
	mov	ax, [next_val_r]
	add	ax, bx
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; this is 2nd interpolated sample (R)
	
	; 16 kHZ stereo to 48 kHZ stereo conversion of the sample is OK
	or	ecx, ecx
	jnz	lff16s2_1
	jmp	lff16s2_3

; .....................

load_24khz_mono_8_bit:
	; 15/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff24m_0		; no
	stc
	retn

lff24m_0:
	; 01/12/2024
	; edi = audio buffer address
	; 13/12/2024
	mov	[audio_buffer], edi
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff24m_7 ; error !

	; 01/12/2024
	mov	[count], eax

	;mov	edi, audio_buffer
	; 29/05/2024
	;mov	edi, [audio_buffer]
	
	and	eax, eax
	jnz	short lff24m_8
	jmp	lff24_eof

lff24m_8:
	mov	ecx, eax	; byte count
lff24m_1:
	lodsb
	;mov	[previous_val], al
	mov	bl, al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (left channel)
	stosw		; original sample (right channel)
	;xor	eax, eax
	mov	al, 80h
	dec	ecx
	jz	short lff24m_2
	mov	al, [esi]
lff24m_2:
	;;mov	[next_val], al
	;mov	bh, al
	;add	al, [previous_val]
	add	al, bl
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is interpolated sample (L)
	stosw		; this is interpolated sample (R)
	
	; 24 kHZ mono to 48 kHZ stereo conversion of the sample is OK
	or	ecx, ecx
	jnz	short lff24m_1
	jmp	lff24_3

lff24m_7:
lff24s_7:
	jmp	lff24_5  ; error

load_24khz_stereo_8_bit:
	; 15/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff24s_0		; no
	stc
	retn

lff24s_0:
	; 01/12/2024
	; edi = audio buffer address
	; 13/12/2024
	mov	[audio_buffer], edi
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff24s_7 ; error !

	; 01/12/2024
	mov	[count], eax

	;mov	edi, audio_buffer
	; 29/05/2024
	;mov	edi, [audio_buffer]
	
	shr	eax, 1
	jnz	short lff24s_8
	jmp	lff24_eof

lff24s_8:
	mov	ecx, eax  ; word count
lff24s_1:
	lodsb
	mov	[previous_val_l], al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (L)
	lodsb
	mov	[previous_val_r], al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (R)

	;xor	eax, eax
	mov	ax, 8080h
	dec	ecx
	jz	short lff24s_2
		; convert 8 bit sample to 16 bit sample
	mov	ax, [esi]
lff24s_2:
	;;mov	[next_val_l], al
	;;mov	[next_val_r], ah
	;mov	bx, ax
	mov	bh, ah
	add	al, [previous_val_l]
	rcr	al, 1
	;mov	dl, al
	sub	al, 80h
	shl	ax, 8
	stosw		; this is interpolated sample (L)
	mov	al, bh	; [next_val_r]
	add	al, [previous_val_r]
	rcr	al, 1
	;mov	dh, al
	sub	al, 80h
	shl	ax, 8
	stosw		; this is interpolated sample (R)
		
	; 24 kHZ stereo to 48 kHZ stereo conversion of the sample is OK
	or	ecx, ecx
	jnz	short lff24s_1
	jmp	lff24_3

load_24khz_mono_16_bit:
	; 15/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff24m2_0		; no
	stc
	retn

lff24m2_0:
	; 01/12/2024
	; edi = audio buffer address
	; 13/12/2024
	mov	[audio_buffer], edi
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff24m2_7 ; error !

	; 01/12/2024
	mov	[count], eax

	;mov	edi, audio_buffer
	; 29/05/2024
	;mov	edi, [audio_buffer]
	
	shr	eax, 1
	jnz	short lff24m2_8
	jmp	lff24_eof

lff24m2_8:
	mov	ecx, eax  ; word count
lff24m2_1:
	lodsw
	stosw		; original sample (left channel)
	stosw		; original sample (right channel)
	add	ah, 80h ; convert sound level 0 to 65535 format
	;mov	[previous_val], ax
	;mov	ebx, eax
	;xor	eax, eax
	xor	ebx, ebx
	dec	ecx
	jz	short lff24m2_2
	;mov	ax, [esi]
	mov	bx, [esi]
lff24m2_2:
	;add	ah, 80h ; convert sound level 0 to 65535 format
	;mov	ebp, eax	; [next_val]
	;add	ax, [previous_val]
	; ax = [previous_val]
	; bx = [next_val]
	add	ax, bx
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; this is interpolated sample (L)
	stosw		; this is interpolated sample (R)
	; 24 kHZ mono to 48 kHZ stereo conversion of the sample is OK
	or	ecx, ecx
	jnz	short lff24m2_1
	jmp	lff24_3

lff24m2_7:
lff24s2_7:
	jmp	lff24_5  ; error

load_24khz_stereo_16_bit:
	; 16/11/2023
	; 15/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff24s2_0		; no
	stc
	retn

lff24s2_0:
	; 01/12/2024
	; edi = audio buffer address
	; 13/12/2024
	mov	[audio_buffer], edi
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff24s2_7 ; error !

	; 01/12/2024
	mov	[count], eax

	;mov	edi, audio_buffer
	; 29/05/2024
	;mov	edi, [audio_buffer]
	
	shr	eax, 2
	jnz	short lff24s2_8
	jmp	lff24_eof

lff24s2_8:
	mov	ecx, eax  ; dword count
lff24s2_1:
	lodsw
	stosw		; original sample (L)
	add	ah, 80h	; convert sound level 0 to 65535 format
	mov	[previous_val_l], ax
	lodsw
	stosw		; original sample (R)
	add	ah, 80h	; convert sound level 0 to 65535 format
	;mov	[previous_val_r], ax
	mov	ebx, eax
	xor	edx, edx
	xor	eax, eax
	; 16/11/2023
	dec	ecx
	jz	short lff24s2_2
	mov	ax, [esi]
	mov	dx, [esi+2]
lff24s2_2:
	add	ah, 80h	; convert sound level 0 to 65535 format
	;;mov	[next_val_l], ax
	;mov	ebp, eax
	add	dh, 80h	; convert sound level 0 to 65535 format
	;mov	[next_val_r], dx
	add	ax, [previous_val_l]
	rcr	ax, 1
	sub	ah, 80h ; -32768 to +32767 format again
	stosw		; this is interpolated sample (L)
	;mov	ax, [next_val_r]
	mov	eax, edx
	;add	ax, [previous_val_r]
	add	ax, bx
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; this is interpolated sample (R)
	
	; 24 kHZ stereo to 48 kHZ stereo conversion of the sample is OK
	or	ecx, ecx
	jnz	short lff24s2_1
	jmp	lff24_3

; .....................

load_32khz_mono_8_bit:
	; 15/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff32m_0		; no
	stc
	retn

lff32m_0:
	; 01/12/2024
	; edi = audio buffer address
	; 13/12/2024
	mov	[audio_buffer], edi
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff32m_7 ; error !

	; 01/12/2024
	mov	[count], eax

	;mov	edi, audio_buffer
	; 29/05/2024
	;mov	edi, [audio_buffer]
	
	and	eax, eax
	jnz	short lff32m_8
	jmp	lff32_eof

lff32m_8:
	mov	ecx, eax	; byte count
lff32m_1:
	lodsb
	;mov	[previous_val], al
	mov	bl, al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (left channel)
	stosw		; original sample (right channel)
	;xor	eax, eax
	mov	al, 80h
	dec	ecx
	jz	short lff32m_2
	mov	al, [esi]
lff32m_2:
	;;mov	[next_val], al
	;mov	bh, al
	;add	al, [previous_val]
	add	al, bl
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is interpolated sample (L)
	stosw		; this is interpolated sample (R)
	
	; different than 8-16-24 kHZ !
	; 'original-interpolated-original' trio samples
	jecxz	lff32m_3

	lodsb
	sub	al, 80h
	shl	ax, 8
	stosw		; original sample (left channel)
	stosw		; original sample (right channel)

	; 32 kHZ mono to 48 kHZ stereo conversion of the sample is OK
	dec	ecx
	jnz	short lff32m_1
lff32m_3:
	jmp	lff32_3

lff32m_7:
lff32s_7:
	jmp	lff32_5  ; error

load_32khz_stereo_8_bit:
	; 15/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff32s_0		; no
	stc
	retn

lff32s_0:
	; 01/12/2024
	; edi = audio buffer address
	; 13/12/2024
	mov	[audio_buffer], edi
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff32s_7 ; error !

	; 01/12/2024
	mov	[count], eax

	;mov	edi, audio_buffer
	; 29/05/2024
	;mov	edi, [audio_buffer]
	
	shr	eax, 1
	jnz	short lff32s_8
	jmp	lff32_eof

lff32s_8:
	mov	ecx, eax  ; word count
lff32s_1:
	lodsb
	mov	[previous_val_l], al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (L)
	lodsb
	mov	[previous_val_r], al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (R)

	;xor	eax, eax
	mov	ax, 8080h
	dec	ecx
	jz	short lff32s_2
		; convert 8 bit sample to 16 bit sample
	mov	ax, [esi]
lff32s_2:
	;;mov	[next_val_l], al
	;;mov	[next_val_r], ah
	;mov	bx, ax
	mov	bh, ah
	add	al, [previous_val_l]
	rcr	al, 1
	;mov	dl, al
	sub	al, 80h
	shl	ax, 8
	stosw		; this is interpolated sample (L)
	mov	al, bh	; [next_val_r]
	add	al, [previous_val_r]
	rcr	al, 1
	;mov	dh, al
	sub	al, 80h
	shl	ax, 8
	stosw		; this is interpolated sample (R)

	; different than 8-16-24 kHZ !
	; 'original-interpolated-original' trio samples
	jecxz	lff32s_3

	lodsb
	sub	al, 80h
	shl	ax, 8
	stosw		; original sample (left channel)

	lodsb
	sub	al, 80h
	shl	ax, 8
	stosw		; original sample (right channel)
		
	; 32 kHZ stereo to 48 kHZ stereo conversion of the sample is OK
	dec	ecx
	jnz	short lff32s_1
lff32s_3:
	jmp	lff32_3

load_32khz_mono_16_bit:
	; 15/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff32m2_0		; no
	stc
	retn

lff32m2_0:
	; 01/12/2024
	; edi = audio buffer address
	; 13/12/2024
	mov	[audio_buffer], edi
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff32m2_7 ; error !

	; 01/12/2024
	mov	[count], eax

	;mov	edi, audio_buffer
	; 29/05/2024
	;mov	edi, [audio_buffer]
	
	shr	eax, 1
	jnz	short lff32m2_8
	jmp	lff32_eof

lff32m2_8:
	mov	ecx, eax  ; word count
lff32m2_1:
	lodsw
	stosw		; original sample (left channel)
	stosw		; original sample (right channel)
	add	ah, 80h ; convert sound level 0 to 65535 format
	;mov	[previous_val], ax
	;mov	ebx, eax
	;xor	eax, eax
	xor	ebx, ebx
	dec	ecx
	jz	short lff32m2_2
	;mov	ax, [esi]
	mov	bx, [esi]
lff32m2_2:
	;add	ah, 80h ; convert sound level 0 to 65535 format
	;mov	ebp, eax	; [next_val]
	;add	ax, [previous_val]
	; ax = [previous_val]
	; bx = [next_val]
	add	ax, bx
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; this is interpolated sample (L)
	stosw		; this is interpolated sample (R)

	; different than 8-16-24 kHZ !
	; 'original-interpolated-original' trio samples 
	jecxz	lff32m2_3

	lodsw
	stosw		; original sample (left channel)
	stosw		; original sample (right channel)

	; 32 kHZ mono to 48 kHZ stereo conversion of the sample is OK
	dec	ecx
	jnz	short lff32m2_1
lff32m2_3:
	jmp	lff32_3

lff32m2_7:
lff32s2_7:
	jmp	lff32_5  ; error

load_32khz_stereo_16_bit:
	; 16/11/2023
	; 15/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff32s2_0		; no
	stc
	retn

lff32s2_0:
	; 01/12/2024
	; edi = audio buffer address
	; 13/12/2024
	mov	[audio_buffer], edi
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff32s2_7 ; error !

	; 01/12/2024
	mov	[count], eax

	;mov	edi, audio_buffer
	; 29/05/2024
	;mov	edi, [audio_buffer]
	
	shr	eax, 2
	jnz	short lff32s2_8
	jmp	lff32_eof

lff32s2_8:
	mov	ecx, eax ; dword count
lff32s2_1:
	lodsw
	stosw		; original sample (L)
	add	ah, 80h	; convert sound level 0 to 65535 format 
	mov	[previous_val_l], ax
	lodsw
	stosw		; original sample (R)
	add	ah, 80h	; convert sound level 0 to 65535 format 
	;mov	[previous_val_r], ax
	mov	ebx, eax
	xor	edx, edx
	xor	eax, eax
	; 16/11/2023
	dec	ecx
	jz	short lff32s2_2
	mov	ax, [esi]
	mov	dx, [esi+2]
lff32s2_2:
	add	ah, 80h	; convert sound level 0 to 65535 format
	;;mov	[next_val_l], ax
	;mov	ebp, eax
	add	dh, 80h	; convert sound level 0 to 65535 format
	;mov	[next_val_r], dx
	add	ax, [previous_val_l]
	rcr	ax, 1
	sub	ah, 80h ; -32768 to +32767 format again
	stosw		; this is interpolated sample (L)
	;mov	ax, [next_val_r]
	mov	eax, edx
	;add	ax, [previous_val_r]
	add	ax, bx
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; this is interpolated sample (R)

	; different than 8-16-24 kHZ !
	; 'original-interpolated-original' trio samples
	jecxz	lff32s2_3

	lodsw
	stosw	; original sample (L)
	lodsw
	stosw	; original sample (R)
	
	; 32 kHZ stereo to 48 kHZ stereo conversion of the sample is OK
	dec	ecx
	jnz	short lff32s2_1
lff32s2_3:
	jmp	lff32_3

; .....................

load_22khz_mono_8_bit:
	; 16/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff22m_0		; no
	stc
	retn

lff22m_0:
	; 01/12/2024
	; edi = audio buffer address
	; 13/12/2024
	mov	[audio_buffer], edi
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff22m_7 ; error !

	; 01/12/2024
	mov	[count], eax

	;mov	edi, audio_buffer
	; 29/05/2024
	;mov	edi, [audio_buffer]
	
	and	eax, eax
	jnz	short lff22m_8
	jmp	lff22_eof

lff22m_8:
	mov	ecx, eax	; byte count
lff22m_9:
	mov	ebp, 5 ; interpolation (one step) loop count
	mov	byte [faz], 3  ; 3 steps/phases
lff22m_1:
	; 3:2:2:2:2:2::3:2:2:2:2::3:2:2:2:2:2  ; 37/17
	lodsb
	mov	dl, 80h
	dec	ecx
	jz	short lff22m_2_1
	mov	dl, [esi]
lff22m_2_1:	
	; al = [previous_val]
	; dl = [next_val]
	call	interpolating_3_8bit_mono ; 1 of 17
	jecxz	lff22m_3
lff22m_2_2:
	lodsb
	mov	dl, 80h
	dec	ecx
	jz	short lff22m_2_3
	mov	dl, [esi]
lff22m_2_3:
 	call	interpolating_2_8bit_mono ; 2 of 17 .. 6 of 17
	jecxz	lff22m_3
	dec	ebp
	jnz	short lff22m_2_2

	mov	al, [faz]
	dec	al
	jz	short lff22m_9
	dec	byte [faz]
	mov	ebp, 4
	dec	al
	jnz	short lff22m_1 ; 3:2:2:2:2 ; 7-11 of 17
	inc	ebp ; 5
	jmp	short lff22m_1 ; 3:2:2:2:2:2 ; 12-17 of 17

lff22m_3:
lff22s_3:
	jmp	lff22_3	; padfill
		; (put zeros in the remain words of the buffer)
lff22m_7:
lff22s_7:
	jmp	lff22_5  ; error

load_22khz_stereo_8_bit:
	; 16/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff22s_0		; no
	stc
	retn

lff22s_0:
	; 01/12/2024
	; edi = audio buffer address
	; 13/12/2024
	mov	[audio_buffer], edi
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff22s_7 ; error !

	; 01/12/2024
	mov	[count], eax

	;mov	edi, audio_buffer
	; 29/05/2024
	;mov	edi, [audio_buffer]
	
	shr	eax, 1
	jnz	short lff22s_8
	jmp	lff22_eof

lff22s_8:
	mov	ecx, eax	; word count
lff22s_9:
	mov	ebp, 5 ; interpolation (one step) loop count
	mov	byte [faz], 3  ; 3 steps/phase
lff22s_1:
	; 3:2:2:2:2:2::3:2:2:2:2::3:2:2:2:2:2  ; 37/17
	lodsw
	mov	dx, 8080h
	dec	ecx
	jz	short lff22s_2_1
	mov	dx, [esi]
lff22s_2_1:	
	; al = [previous_val_l]
	; ah = [previous_val_r]
	; dl = [next_val_l]
	; dh = [next_val_r]
	call	interpolating_3_8bit_stereo ; 1 of 17
	jecxz	lff22s_3
lff22s_2_2:
	lodsw
	mov	dx, 8080h
	dec	ecx
	jz	short lff22s_2_3
	mov	dx, [esi]
lff22s_2_3:
 	call	interpolating_2_8bit_stereo ; 2 of 17 .. 6 of 17
	jecxz	lff22s_3
	dec	ebp
	jnz	short lff22s_2_2

	mov	al, [faz]
	dec	al
	jz	short lff22s_9
	dec	byte [faz]
	mov	ebp, 4
	dec	al
	jnz	short lff22s_1 ; 3:2:2:2:2 ; 7-11 of 17
	inc	ebp ; 5
	jmp	short lff22s_1 ; 3:2:2:2:2:2 ; 12-17 of 17

load_22khz_mono_16_bit:
	; 16/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff22m2_0		; no
	stc
	retn

lff22m2_0:
	; 01/12/2024
	; edi = audio buffer address
	; 13/12/2024
	mov	[audio_buffer], edi
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff22m2_7 ; error !

	; 01/12/2024
	mov	[count], eax

	;mov	edi, audio_buffer
	; 29/05/2024
	;mov	edi, [audio_buffer]
	
	shr	eax, 1
	jnz	short lff22m2_8
	jmp	lff22_eof

lff22m2_8:
	mov	ecx, eax	; word count
lff22m2_9:
	mov	ebp, 5 ; interpolation (one step) loop count
	mov	byte [faz], 3  ; 3 steps/phases
lff22m2_1:
	; 3:2:2:2:2:2::3:2:2:2:2::3:2:2:2:2:2  ; 37/17
	lodsw
	xor	edx, edx
	dec	ecx
	jz	short lff22m2_2_1
	mov	dx, [esi]
lff22m2_2_1:	
	; ax = [previous_val]
	; dx = [next_val]
	call	interpolating_3_16bit_mono ; 1 of 17
	jecxz	lff22m2_3
lff22m2_2_2:
	lodsw
	xor	edx, edx
	dec	ecx
	jz	short lff22m2_2_3
	mov	dx, [esi]
lff22m2_2_3:
 	call	interpolating_2_16bit_mono ; 2 of 17 .. 6 of 17
	jecxz	lff22m2_3
	dec	ebp
	jnz	short lff22m2_2_2

	mov	al, [faz]
	dec	al
	jz	short lff22m2_9
	dec	byte [faz]
	mov	ebp, 4
	dec	al
	jnz	short lff22m2_1 ; 3:2:2:2:2 ; 7-11 of 17
	inc	ebp ; 5
	jmp	short lff22m2_1 ; 3:2:2:2:2:2 ; 12-17 of 17

lff22m2_3:
lff22s2_3:
	jmp	lff22_3	; padfill
		; (put zeros in the remain words of the buffer)
lff22m2_7:
lff22s2_7:
	jmp	lff22_5  ; error

load_22khz_stereo_16_bit:
	; 16/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff22s2_0		; no
	stc
	retn

lff22s2_0:
	; 01/12/2024
	; edi = audio buffer address
	; 13/12/2024
	mov	[audio_buffer], edi
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff22s2_7 ; error !

	; 01/12/2024
	mov	[count], eax

	;mov	edi, audio_buffer
	; 29/05/2024
	;mov	edi, [audio_buffer]
	
	shr	eax, 2	; dword (left chan word + right chan word)
	jnz	short lff22s2_8
	jmp	lff22_eof

lff22s2_8:
	mov	ecx, eax	; dword count
lff22s2_9:
	mov	ebp, 5 ; interpolation (one step) loop count
	mov	byte [faz], 3  ; 3 steps/phase
lff22s2_1:
	; 3:2:2:2:2:2::3:2:2:2:2::3:2:2:2:2:2  ; 37/17
	lodsw
	mov	ebx, eax
	lodsw
	mov	edx, [esi]
	mov	[next_val_l], dx
	; 26/11/2023
	shr	edx, 16
	dec	ecx
	jnz	short lff22s2_2_1
	xor	edx, edx ; 0
	mov	[next_val_l], dx
lff22s2_2_1:
	; bx = [previous_val_l]
	; ax = [previous_val_r]
	; [next_val_l]
	; dx = [next_val_r]
	call	interpolating_3_16bit_stereo ; 1 of 17 
	jecxz	lff22s2_3
lff22s2_2_2:
	lodsw
	mov	ebx, eax
	lodsw
	mov	edx, [esi]
	mov	[next_val_l], dx
	; 26/11/2023
	shr	edx, 16
	dec	ecx
	jnz	short lff22s2_2_3
	xor	edx, edx ; 0
	mov	[next_val_l], dx
lff22s2_2_3:
 	call	interpolating_2_16bit_stereo ; 2 of 17 .. 6 of 17
	jecxz	lff22s2_2_4

	dec	ebp
	jnz	short lff22s2_2_2

	mov	al, [faz]
	dec	al
	jz	short lff22s2_9
	dec	byte [faz]
	mov	ebp, 4
	dec	al
	jnz	short lff22s2_1 ; 3:2:2:2:2 ; 7-11 of 17
	inc	ebp ; 5
	jmp	short lff22s2_1 ; 3:2:2:2:2:2 ; 12-17 of 17

lff22s2_2_4:
	; 26/11/2023
	jmp	lff22_3	; padfill

; .....................

load_11khz_mono_8_bit:
	; 18/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff11m_0		; no
	stc
	retn

lff11m_0:
	; 01/12/2024
	; edi = audio buffer address
	; 13/12/2024
	mov	[audio_buffer], edi
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff11m_7 ; error !

	; 01/12/2024
	mov	[count], eax

	;mov	edi, audio_buffer
	; 29/05/2024
	;mov	edi, [audio_buffer]
	
	and	eax, eax
	jnz	short lff11m_8
	jmp	lff11_eof

lff11m_8:
	mov	ecx, eax		; byte count
lff11m_9:
	mov	ebp, 6 ; interpolation (one step) loop count
lff11m_1:
	; 5:4:4::5:4:4::5:4:4::5:4:4::5:4:4::5:4  ; 74/17
	lodsb
	mov	dl, 80h
	dec	ecx
	jz	short lff11m_2_1
	mov	dl, [esi]
lff11m_2_1:	
	; al = [previous_val]
	; dl = [next_val]
	call	interpolating_5_8bit_mono
	jecxz	lff11m_3
lff11m_2_2:
	lodsb
	mov	dl, 80h
	dec	ecx
	jz	short lff11m_2_3
	mov	dl, [esi]
lff11m_2_3:
 	call	interpolating_4_8bit_mono
	jecxz	lff11m_3

	dec	ebp
	jz	short lff11m_9

	lodsb
	mov	dl, 80h
	dec	ecx
	jz	short lff11m_2_4
	mov	dl, [esi]
lff11m_2_4:
	call	interpolating_4_8bit_mono
	jecxz	lff11m_3
	jmp	short lff11m_1

lff11m_7:
lff11s_7:
	jmp	lff11_5  ; error

load_11khz_stereo_8_bit:
	; 18/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff11s_0		; no
	stc
	retn

lff11m_3:
lff11s_3:
	jmp	lff11_3	; padfill
		; (put zeros in the remain words of the buffer)

lff11s_0:
	; 01/12/2024
	; edi = audio buffer address
	; 13/12/2024
	mov	[audio_buffer], edi
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff11s_7 ; error !

	; 01/12/2024
	mov	[count], eax

	;mov	edi, audio_buffer
	; 29/05/2024
	;mov	edi, [audio_buffer]
	
	shr	eax, 1
	jnz	short lff11s_8
	jmp	lff11_eof

lff11s_8:
	mov	ecx, eax	; word count
lff11s_9:
	mov	ebp, 6 ; interpolation (one step) loop count
lff11s_1:
	; 5:4:4::5:4:4::5:4:4::5:4:4::5:4:4::5:4  ; 74/17
	lodsw
	mov	dx, 8080h
	dec	ecx
	jz	short lff11s_2_1
	mov	dx, [esi]
lff11s_2_1:	
	; al = [previous_val_l]
	; ah = [previous_val_r]
	; dl = [next_val_l]
	; dh = [next_val_r]
	call	interpolating_5_8bit_stereo
	jecxz	lff11s_3
lff11s_2_2:
	lodsw
	mov	dx, 8080h
	dec	ecx
	jz	short lff11s_2_3
	mov	dx, [esi]
lff11s_2_3:
 	call	interpolating_4_8bit_stereo
	jecxz	lff11s_3
	
	dec	ebp
	jz	short lff11s_9

	lodsw
	mov	dx, 8080h
	dec	ecx
	jz	short lff11s_2_4
	mov	dx, [esi]
lff11s_2_4:
	call	interpolating_4_8bit_stereo
	jecxz	lff11s_3
	jmp	short lff11s_1

load_11khz_mono_16_bit:
	; 18/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff11m2_0		; no
	stc
	retn

lff11m2_0:
	; 01/12/2024
	; edi = audio buffer address
	; 13/12/2024
	mov	[audio_buffer], edi
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff11m2_7 ; error !

	; 01/12/2024
	mov	[count], eax

	;mov	edi, audio_buffer
	; 29/05/2024
	;mov	edi, [audio_buffer]
	
	shr	eax, 1
	jnz	short lff11m2_8
	jmp	lff11_eof

lff11m2_8:
	mov	ecx, eax	; word count
lff11m2_9:
	mov	ebp, 6 ; interpolation (one step) loop count
lff11m2_1:
	; 5:4:4::5:4:4::5:4:4::5:4:4::5:4:4::5:4  ; 74/17
	lodsw
	xor	edx, edx
	dec	ecx
	jz	short lff11m2_2_1
	mov	dx, [esi]
lff11m2_2_1:	
	; ax = [previous_val]
	; dx = [next_val]
	call	interpolating_5_16bit_mono
	jecxz	lff11m2_3
lff11m2_2_2:
	lodsw
	xor	edx, edx
	dec	ecx
	jz	short lff11m2_2_3
	mov	dx, [esi]
lff11m2_2_3:
 	call	interpolating_4_16bit_mono
	jecxz	lff11m2_3

	dec	ebp
	jz	short lff11m2_9

	lodsw
	xor	edx, edx
	dec	ecx
	jz	short lff11m2_2_4
	mov	dx, [esi]
lff11m2_2_4:
 	call	interpolating_4_16bit_mono
	jecxz	lff11m2_3
	jmp	short lff11m2_1

lff11m2_7:
lff11s2_7:
	jmp	lff11_5  ; error

load_11khz_stereo_16_bit:
	; 18/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff11s2_0		; no
	stc
	retn

lff11s2_0:
	; 01/12/2024
	; edi = audio buffer address
	; 13/12/2024
	mov	[audio_buffer], edi
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff11s2_7 ; error !

	; 01/12/2024
	mov	[count], eax

	;mov	edi, audio_buffer
	; 29/05/2024
	;mov	edi, [audio_buffer]
	
	shr	eax, 2	; dword (left chan word + right chan word)
	jnz	short lff11s2_8
	jmp	lff11_eof

lff11m2_3:
lff11s2_3:
	jmp	lff11_3	; padfill
		; (put zeros in the remain words of the buffer)

lff11s2_8:
	mov	ecx, eax	; dword count
lff11s2_9:
	mov	ebp, 6 ; interpolation (one step) loop count
lff11s2_1:
	; 5:4:4::5:4:4::5:4:4::5:4:4::5:4:4::5:4  ; 74/17
	lodsw
	mov	ebx, eax
	lodsw
	mov	edx, [esi]
	mov	[next_val_l], edx
	; 26/11/2023
	shr	edx, 16
	;mov	[next_val_r], dx
	dec	ecx
	jnz	short lff11s2_2_1
	xor	edx, edx ; 0
	mov	[next_val_l], dx
	;mov	[next_val_r], dx
lff11s2_2_1:
	; bx = [previous_val_l]
	; ax = [previous_val_r]
	; [next_val_l]
	; dx = [next_val_r]
	call	interpolating_5_16bit_stereo
	jecxz	lff11s2_3
lff11s2_2_2:
	lodsw
	mov	ebx, eax
	lodsw
	mov	edx, [esi]
	mov	[next_val_l], dx
	; 26/11/2023
	shr	edx, 16
	;mov	[next_val_r], dx
	dec	ecx
	jnz	short lff11s2_2_3
	xor	edx, edx ; 0
	mov	[next_val_l], dx
	;mov	[next_val_r], dx
lff11s2_2_3:
 	call	interpolating_4_16bit_stereo
	jecxz	lff11s2_3
	
	dec	ebp
	jz	short lff11s2_9

	lodsw
	mov	ebx, eax
	lodsw
	mov	edx, [esi]
	mov	[next_val_l], dx
	; 26/11/2023
	shr	edx, 16
	;mov	[next_val_r], dx
	dec	ecx
	jnz	short lff11s2_2_4
	xor	edx, edx ; 0
	mov	[next_val_l], dx
	;mov	[next_val_r], dx
lff11s2_2_4:
 	call	interpolating_4_16bit_stereo
	jecxz	lff11s2_3
	jmp	short lff11s2_1

; .....................

load_44khz_mono_8_bit:
	; 18/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff44m_0		; no
	stc
	retn

lff44m_0:
	; 01/12/2024
	; edi = audio buffer address
	; 13/12/2024
	mov	[audio_buffer], edi
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff44m_7 ; error !

	; 01/12/2024
	mov	[count], eax

	;mov	edi, audio_buffer
	; 29/05/2024
	;mov	edi, [audio_buffer]
	
	and	eax, eax
	jnz	short lff44m_8
	jmp	lff44_eof

lff44m_8:
	mov	ecx, eax	; byte count
lff44m_9:
	mov	ebp, 10 ; interpolation (one step) loop count
	mov	byte [faz], 2  ; 2 steps/phases
lff44m_1:
	; 2:1:1:1:1:1:1:1:1:1:1::	; 25/23
	; 2:1:1:1:1:1:1:1:1:1:1:1
	lodsb
	mov	dl, 80h
	dec	ecx
	jz	short lff44m_2_1
	mov	dl, [esi]
lff44m_2_1:	
	; al = [previous_val]
	; dl = [next_val]
	call	interpolating_2_8bit_mono
	jecxz	lff44m_3
lff44m_2_2:
	lodsb
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; (L)
	stosw		; (R)

	dec	ecx
	jz	short lff44m_3
	dec	ebp
	jnz	short lff44m_2_2
	
	dec	byte [faz]
	jz	short lff44m_9 
	mov	ebp, 11
	jmp	short lff44m_1

lff44m_3:
lff44s_3:
	jmp	lff44_3	; padfill
		; (put zeros in the remain words of the buffer)
lff44m_7:
lff44s_7:
	jmp	lff44_5  ; error

load_44khz_stereo_8_bit:
	; 16/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff44s_0		; no
	stc
	retn

lff44s_0:
	; 01/12/2024
	; edi = audio buffer address
	; 13/12/2024
	mov	[audio_buffer], edi
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff44s_7 ; error !

	; 01/12/2024
	mov	[count], eax

	;mov	edi, audio_buffer
	; 29/05/2024
	;mov	edi, [audio_buffer]
	
	shr	eax, 1
	jnz	short lff44s_8
	jmp	lff44_eof

lff44s_8:
	mov	ecx, eax	; word count
lff44s_9:
	mov	ebp, 10 ; interpolation (one step) loop count
	mov	byte [faz], 2  ; 2 steps/phase
lff44s_1:
	; 2:1:1:1:1:1:1:1:1:1:1::	; 25/23
	; 2:1:1:1:1:1:1:1:1:1:1:1
	lodsw
	mov	dx, 8080h
	dec	ecx
	jz	short lff44s_2_1
	mov	dx, [esi]
lff44s_2_1:	
	; al = [previous_val_l]
	; ah = [previous_val_r]
	; dl = [next_val_l]
	; dh = [next_val_r]
	call	interpolating_2_8bit_stereo
	jecxz	lff44s_3
lff44s_2_2:
	lodsb
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; (L)
	lodsb
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; (R)

	dec	ecx
	jz	short lff44s_3	
	dec	ebp
	jnz	short lff44s_2_2
	
	dec	byte [faz]
	jz	short lff44s_9 
	mov	ebp, 11
	jmp	short lff44s_1

load_44khz_mono_16_bit:
	; 18/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff44m2_0		; no
	stc
	retn

lff44m2_0:
	; 01/12/2024
	; edi = audio buffer address
	; 13/12/2024
	mov	[audio_buffer], edi
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff44m2_7 ; error !

	; 01/12/2024
	mov	[count], eax

	;mov	edi, audio_buffer
	; 29/05/2024
	;mov	edi, [audio_buffer]
	
	shr	eax, 1
	jnz	short lff44m2_8
	jmp	lff44_eof

lff44m2_8:
	mov	ecx, eax	; word count
lff44m2_9:
	mov	ebp, 10 ; interpolation (one step) loop count
	mov	byte [faz], 2  ; 2 steps/phases
lff44m2_1:
	; 2:1:1:1:1:1:1:1:1:1:1::	; 25/23
	; 2:1:1:1:1:1:1:1:1:1:1:1
	lodsw
	xor	edx, edx
	dec	ecx
	jz	short lff44m2_2_1
	mov	dx, [esi]
lff44m2_2_1:	
	; ax = [previous_val]
	; dx = [next_val]
	call	interpolating_2_16bit_mono
	jecxz	lff44m2_3
lff44m2_2_2:
	lodsw
	stosw		; (L)eft Channel
	stosw		; (R)ight Channel

	dec	ecx
	jz	short lff44m2_3	
	dec	ebp
	jnz	short lff44m2_2_2
	
	dec	byte [faz]
	jz	short lff44m2_9 
	mov	ebp, 11
	jmp	short lff44m2_1

lff44m2_3:
lff44s2_3:
	jmp	lff44_3	; padfill
		; (put zeros in the remain words of the buffer)
lff44m2_7:
lff44s2_7:
	jmp	lff44_5  ; error

load_44khz_stereo_16_bit:
	; 18/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff44s2_0		; no
	stc
	retn

lff44s2_0:
	; 01/12/2024
	; edi = audio buffer address
	; 13/12/2024
	mov	[audio_buffer], edi
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff44s2_7 ; error !

	; 01/12/2024
	mov	[count], eax

	;mov	edi, audio_buffer
	; 29/05/2024
	;mov	edi, [audio_buffer]
	
	shr	eax, 2	; dword (left chan word + right chan word)
	jnz	short lff44s2_8
	jmp	lff44_eof

lff44s2_8:
	mov	ecx, eax	; dword count
lff44s2_9:
	mov	ebp, 10 ; interpolation (one step) loop count
	mov	byte [faz], 2  ; 2 steps/phase
lff44s2_1:
	; 2:1:1:1:1:1:1:1:1:1:1::	; 25/23
	; 2:1:1:1:1:1:1:1:1:1:1:1
	lodsw
	mov	ebx, eax
	lodsw
	;mov	dx, [esi]
	;mov	[next_val_l], dx
	;mov	dx, [esi+2]
	; 26/11/2023
	mov	edx, [esi]
	mov	[next_val_l], dx
	shr	edx, 16
	dec	ecx
	jnz	short lff44s2_2_1
	xor	edx, edx ; 0
	mov	[next_val_l], dx
lff44s2_2_1:
	; bx = [previous_val_l]
	; ax = [previous_val_r]
	; [next_val_l]
	; dx = [next_val_r]
	call	interpolating_2_16bit_stereo
	jecxz	lff44s2_3
lff44s2_2_2:
	;movsw		; (L)eft Channel
	;movsw		; (R)ight Channel
	movsd

	dec	ecx
	jz	short lff44s2_3	
	dec	ebp
	jnz	short lff44s2_2_2
	
	dec	byte [faz]
	jz	short lff44s2_9 
	mov	ebp, 11
	jmp	short lff44s2_1

; .....................

interpolating_3_8bit_mono:
	; 16/11/2023
	; al = [previous_val]
	; dl = [next_val]
	; original-interpolated-interpolated
	mov	bl, al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (L)
	stosw		; original sample (R)
	mov	al, bl
	add	al, dl
	rcr	al, 1
	mov	bh, al	; interpolated middle (temporary)
	add	al, bl
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 1 (L)
	stosw		; interpolated sample 1 (R)
	mov	al, bh
	add	al, dl	; [next_val]
	rcr	al, 1
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 2 (L)
	stosw		; interpolated sample 2 (R)
	retn

interpolating_3_8bit_stereo:
	; 16/11/2023
	; al = [previous_val_l]
	; ah = [previous_val_r]
	; dl = [next_val_l]
	; dh = [next_val_r]
	; original-interpolated-interpolated
	mov	ebx, eax
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (L)
	mov	al, bh
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (R)
	mov	al, bl
	add	al, dl	; [next_val_l]
	rcr	al, 1
	push	eax ; *	; al = interpolated middle (L) (temporary)
	add	al, bl	; [previous_val_l]
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 1 (L)
	mov	al, bh
	add	al, dh	; [next_val_r]
	rcr	al, 1
	push	eax ; ** ; al = interpolated middle (R) (temporary)
	add	al, bh	; [previous_val_r]
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 1 (R)
	pop	ebx ; **
	pop	eax ; *
	add	al, dl	; [next_val_l]
	rcr	al, 1
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 2 (L)
	mov	al, bl
	add	al, dh	; [next_val_r]
	rcr	al, 1
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 2 (R)
	retn

interpolating_2_8bit_mono:
	; 16/11/2023
	; al = [previous_val]
	; dl = [next_val]
	; original-interpolated
	mov	bl, al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (L)
	stosw		; original sample (R)
	mov	al, bl
	add	al, dl
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample (L)
	stosw		; interpolated sample (R)
	retn

interpolating_2_8bit_stereo:
	; 16/11/2023
	; al = [previous_val_l]
	; ah = [previous_val_r]
	; dl = [next_val_l]
	; dh = [next_val_r]
	; original-interpolated
	mov	ebx, eax
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (L)
	mov	al, bh
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (R)
	mov	al, bl	; [previous_val_l]
	add	al, dl	; [next_val_l]
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample (L)
	mov	al, bh
	add	al, dh	; [next_val_r]
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample (R)
	retn

interpolating_3_16bit_mono:
	; 16/11/2023
	; ax = [previous_val]
	; dx = [next_val]
	; original-interpolated-interpolated

	stosw		; original sample (L)
	stosw		; original sample (R)
	add	ah, 80h ; convert sound level 0 to 65535 format
	push	eax ; *	; [previous_val]
	add	dh, 80h
	add	ax, dx
	rcr	ax, 1
	pop	ebx ; *
	xchg	ebx, eax ; bx  = interpolated middle (temporary)
	add	ax, bx	; [previous_val] + interpolated middle
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 1 (L)
	stosw		; interpolated sample 1 (R)
	mov	eax, ebx
	add	ax, dx	; interpolated middle + [next_val]
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; interpolated sample 2 (L)
	stosw		; interpolated sample 2 (R)
	retn

interpolating_3_16bit_stereo:
	; 16/11/2023
	; bx = [previous_val_l]
	; ax = [previous_val_r]
	; [next_val_l]
	; dx = [next_val_r]
	; original-interpolated-interpolated

	xchg	eax, ebx
	stosw		; original sample (L)
	xchg	eax, ebx
	stosw		; original sample (R)
	add	ah, 80h ; convert sound level 0 to 65535 format
	push	eax ; *	; [previous_val_r]
	add	bh, 80h
	add	byte [next_val_l+1], 80h
	mov	ax, [next_val_l]
	add	ax, bx	; [previous_val_l]
	rcr	ax, 1
	xchg	eax, ebx ; ax = [previous_val_l]
	add	ax, bx	; bx = interpolated middle (L)
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 1 (L)
	pop	eax  ; *
	add	dh, 80h ; convert sound level 0 to 65535 format
	push	edx  ; * ; [next_val_r]
	xchg	eax, edx
	add	ax, dx	; [next_val_r] + [previous_val_r]
	rcr	ax, 1	; / 2
	push	eax ; ** ; interpolated middle (R)
	add	ax, dx	; + [previous_val_r]
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 1 (R)
	mov	ax, [next_val_l]
	add	ax, bx	; + interpolated middle (L)
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 2 (L)
	pop	eax ; **
	pop	edx ; *
	add	ax, dx	; interpolated middle + [next_val_r]
	rcr	ax, 1	; / 2
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 2 (L)
	retn

interpolating_2_16bit_mono:
	; 16/11/2023
	; ax = [previous_val]
	; dx = [next_val]
	; original-interpolated

	stosw		; original sample (L)
	stosw		; original sample (R)
	add	ah, 80h ; convert sound level 0 to 65535 format
	add	dh, 80h
	add	ax, dx
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; interpolated sample (L)
	stosw		; interpolated sample (R)
	retn

interpolating_2_16bit_stereo:
	; 16/11/2023
	; bx = [previous_val_l]
	; ax = [previous_val_r]
	; [next_val_l]
	; dx = [next_val_r]
	; original-interpolated

	xchg	eax, ebx
	stosw		; original sample (L)
	xchg	eax, ebx
	stosw		; original sample (R)
	add	ah, 80h ; convert sound level 0 to 65535 format
	add	dh, 80h
	add	ax, dx	; [previous_val_r] + [next_val_r]
	rcr	ax, 1	; / 2
	push	eax ; *	; interpolated sample (R)
	mov	ax, [next_val_l]
	add	ah, 80h
	add	bh, 80h
	add	ax, bx	; [next_val_l] + [previous_val_l]
	rcr	ax, 1	; / 2
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample (L)
	pop	eax ; *	
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample (R)
	retn

interpolating_5_8bit_mono:
	; 17/11/2023
	; al = [previous_val]
	; dl = [next_val]
	; original-interpltd-interpltd-interpltd-interpltd
	mov	bl, al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (L)
	stosw		; original sample (R)
	mov	al, bl
	add	al, dl
	rcr	al, 1
	mov	bh, al	; interpolated middle (temporary)
	add	al, bl  ; [previous_val]
	rcr	al, 1 	
	mov	dh, al	; interpolated 1st quarter (temporary)
	add	al, bl
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 1 (L)
	stosw		; interpolated sample 1 (R)
	mov	al, bh
	add	al, dh
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 2 (L)
	stosw		; interpolated sample 2 (R)
	mov	al, bh
	add	al, dl	; [next_val]
	rcr	al, 1
	mov	dh, al	; interpolated 3rd quarter (temporary)
	add	al, bh
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 3 (L)
	stosw		; interpolated sample 3 (R)
	mov	al, dh
	add	al, dl
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 4 (L)
	stosw		; interpolated sample 4 (R)
	retn

interpolating_5_8bit_stereo:
	; 17/11/2023
	; al = [previous_val_l]
	; ah = [previous_val_r]
	; dl = [next_val_l]
	; dh = [next_val_r]
	; original-interpltd-interpltd-interpltd-interpltd
	mov	ebx, eax
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (L)
	mov	al, bh
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (R)
	push	edx ; *
	mov	al, bl
	add	al, dl	; [next_val_l]
	rcr	al, 1
	push	eax ; **	; al = interpolated middle (L) (temporary)
	add	al, bl	; [previous_val_l]
	rcr	al, 1
	xchg	al, bl
	add	al, bl	; bl = interpolated 1st quarter (L) (temp)
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 1 (L)
	mov	al, bh
	add	al, dh	; [next_val_r]
	rcr	al, 1
	push	eax ; *** ; al = interpolated middle (R) (temporary)
	add	al, bh	; [previous_val_r]
	rcr	al, 1
	xchg	al, bh
	add	al, bh	; bh = interpolated 1st quarter (R) (temp)
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 1 (R)
	pop	edx ; ***
	pop	eax ; **	; al = interpolated middle (L) (temporary)
	xchg	al, bl	; al = interpolated 1st quarter (L) (temp)
	add	al, bl	; bl = interpolated middle (L) (temporary)
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 2 (L)
	mov	al, dl 	; interpolated middle (R) (temporary)
	xchg	al, bh	; al = interpolated 1st quarter (R) (temp)
	add	al, bh	; bh = interpolated middle (R) (temporary)
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 2 (R)
	pop	edx ; *
	mov	al, bl	; interpolated middle (L) (temporary)
	add	al, dl	; [next_val_l]
	rcr	al, 1
	xchg	al, bl	; al = interpolated middle (R) (temporary)
	add	al, bl	; bl = interpolated 3rd quarter (L) (temp)
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 3 (L)
	mov	al, bh	
	add	al, dh	; interpolated middle (R) + [next_val_r]
	rcr	al, 1
	xchg	al, bh	; al = interpolated middle (R)
	add	al, bh	; bh = interpolated 3rd quarter (R) (temp)
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 3 (R)
	mov	al, bl
	add	al, dl	; [next_val_l]
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 4 (L)
	mov	al, bh
	add	al, dh	; [next_val_r]
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 4 (R)
	retn

interpolating_4_8bit_mono:
	; 17/11/2023
	; al = [previous_val]
	; dl = [next_val]
	; original-interpolated-interpolated-interpolated
	mov	bl, al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (L)
	stosw		; original sample (R)
	mov	al, bl
	add	al, dl	
	rcr	al, 1
	xchg	al, bl  ; al = [previous_val]
	add	al, bl	; bl = interpolated middle (sample 2)
	rcr	al, 1 	
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 1 (L)
	stosw		; interpolated sample 1 (R)
	mov	al, bl	; interpolated middle (sample 2)
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 2 (L)
	stosw		; interpolated sample 2 (R)
	mov	al, bl
	add	al, dl	; [next_val]
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 3 (L)
	stosw		; interpolated sample 3 (R)
	retn

interpolating_4_8bit_stereo:
	; 17/11/2023
	; al = [previous_val_l]
	; ah = [previous_val_r]
	; dl = [next_val_l]
	; dh = [next_val_r]	
	; original-interpolated-interpolated-interpolated
	mov	ebx, eax
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (L)
	mov	al, bh
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (R)
	mov	al, bl
	add	al, dl	; [next_val_l]
	rcr	al, 1
	xchg	al, bl	; al = [previous_val_l]
	add	al, bl	; bl = interpolated middle (L) (sample 2)
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 1 (L)
	mov	al, bh
	add	al, dh	; [next_val_r]
	rcr	al, 1
	xchg	al, bh	; al = [previous_val_h]
	add	al, bh	; bh = interpolated middle (R) (sample 2)
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 1 (R)
	mov	al, bl	; interpolated middle (L) (sample 2)
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 2 (L)
	mov	al, bh	; interpolated middle (L) (sample 2)
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 2 (L)
	mov	al, bl
	add	al, dl	; [next_val_l]
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 3 (L)
	mov	al, bh
	add	al, dh	; [next_val_r]
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 3 (R)
	retn

interpolating_5_16bit_mono:
	; 18/11/2023
	; ax = [previous_val]
	; dx = [next_val]
	; original-interpltd-interpltd-interpltd-interpltd
	stosw		; original sample (L)
	stosw		; original sample (R)
	add	ah, 80h ; convert sound level 0 to 65535 format
	mov	ebx, eax ; [previous_val]
	add	dh, 80h
	add	ax, dx
	rcr	ax, 1
	push	eax ; *	; interpolated middle (temporary)
	add	ax, bx	; interpolated middle + [previous_val] 
	rcr	ax, 1
	push	eax ; **	; interpolated 1st quarter (temporary)
	add	ax, bx	; 1st quarter + [previous_val]
	rcr	ax, 1	
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 1 (L)
	stosw		; interpolated sample 1 (R)
	pop	eax ; **
	pop	ebx ; *
	add	ax, bx	; 1st quarter + middle
	rcr	ax, 1	; / 2
	sub	ah, 80h	; -32768 to +32767 format again	
	stosw		; interpolated sample 2 (L)
	stosw		; interpolated sample 2 (R)
	mov	eax, ebx
	add	ax, dx	; interpolated middle + [next_val]
	rcr	ax, 1
	push	eax ; *	; interpolated 3rd quarter (temporary)
	add	ax, bx	; + interpolated middle
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; interpolated sample 3 (L)
	stosw		; interpolated sample 3 (R)
	pop	eax ; *	
	add	ax, dx	; 3rd quarter + [next_val]
	rcr	ax, 1	; / 2
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; interpolated sample 4 (L)
	stosw		; interpolated sample 4 (R)
	retn

interpolating_5_16bit_stereo:
	; 18/11/2023
	; bx = [previous_val_l]
	; ax = [previous_val_r]
	; [next_val_l]
	; [next_val_r]
	; original-interpltd-interpltd-interpltd-interpltd
	push	ecx ; !
	xchg	eax, ebx
	stosw		; original sample (L)
	xchg	eax, ebx
	stosw		; original sample (R)
	add	ah, 80h ; convert sound level 0 to 65535 format
	push	eax ; *	; [previous_val_r]
	add	bh, 80h
	add	byte [next_val_l+1], 80h
	mov	ax, [next_val_l]
	add	ax, bx	; [previous_val_l]
	rcr	ax, 1
	mov	ecx, eax ; interpolated middle (L)
	add	ax, bx	
	rcr	ax, 1
	mov	edx, eax ; interpolated 1st quarter (L)
	add	ax, bx	; [previous_val_l]
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 1 (L)
	mov	eax, ecx
	add	ax, dx	; middle (L) + 1st quarter (L)
	rcr	ax, 1	; / 2
	mov	ebx, eax  ; interpolated sample 2 (L)
	pop	edx ; *	; [previous_val_r]
	mov	eax, edx
	add	byte [next_val_r+1], 80h
	add	ax, [next_val_r]
	rcr	ax, 1
	push	eax ; *	; interpolated middle (R)
	add	ax, dx
	rcr	ax, 1
	push	eax ; ** ; interpolated 1st quarter (R)
	add	ax, dx	; [previous_val_r]
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 1 (R)
	mov	eax, ebx
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 2 (L)
	pop	eax ; **
	pop	edx ; *
	add	ax, dx	; 1st quarter (R) + middle (R)
	rcr	ax, 1	; / 2
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 2 (R)
	mov	eax, ecx
	add	ax, [next_val_l]
	rcr	ax, 1
	push	eax ; * ; interpolated 3rd quarter (L)
	add	ax, cx	; interpolated middle (L)
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 3 (L)
	mov	eax, edx
	add	ax, [next_val_r]
	rcr	ax, 1
	push	eax ; ** ; interpolated 3rd quarter (R)
	add	ax, dx	; interpolated middle (R)
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 3 (R)
	pop	ebx ; **
	pop	eax ; *
	add	ax, [next_val_l]
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 4 (L)
	mov	eax, ebx
	add	ax, [next_val_r]
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 4 (R)
	pop	ecx ; !
	retn

interpolating_4_16bit_mono:
	; 18/11/2023
	; ax = [previous_val]
	; dx = [next_val]
	; original-interpolated

	stosw		; original sample (L)
	stosw		; original sample (R)
	add	ah, 80h ; convert sound level 0 to 65535 format
	mov	ebx, eax ; [previous_val]
	add	dh, 80h
	add	ax, dx	; [previous_val] + [next_val]
	rcr	ax, 1
	xchg	eax, ebx
	add	ax, bx	; [previous_val] + interpolated middle
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 1 (L)
	stosw		; interpolated sample 1 (R)
	mov	eax, ebx ; interpolated middle
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 2 (L)
	stosw		; interpolated sample 2 (R)
	mov	eax, ebx
	add	ax, dx	; interpolated middle + [next_val]
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; interpolated sample 3 (L)
	stosw		; interpolated sample 3 (R)
	retn

interpolating_4_16bit_stereo:
	; 18/11/2023
	; bx = [previous_val_l]
	; ax = [previous_val_r]
	; [next_val_l]
	; [next_val_r]
	; original-interpolated-interpolated-interpolated
	xchg	eax, ebx
	stosw		; original sample (L)
	xchg	eax, ebx
	stosw		; original sample (R)
	add	ah, 80h ; convert sound level 0 to 65535 format
	mov	edx, eax ; [previous_val_r]
	add	bh, 80h
	add	byte [next_val_l+1], 80h
	mov	ax, [next_val_l]
	add	ax, bx	; [previous_val_l]
	rcr	ax, 1
	xchg	eax, ebx
	add	ax, bx	; bx = interpolated middle (L)
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 1 (L)
	add	byte [next_val_r+1], 80h
	mov	eax, edx ; [previous_val_r]
	add	ax, [next_val_r]
	rcr	ax, 1
	xchg	eax, edx
	add	ax, dx	; dx = interpolated middle (R)
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 1 (R)
	mov	eax, ebx
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 2 (L)
	mov	eax, edx
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 2 (R)
	mov	eax, ebx
	add	ax, [next_val_l]
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 3 (L)
	mov	eax, edx
	add	ax, [next_val_r]
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 3 (R)
	retn

; 13/11/2023
previous_val:
previous_val_l: dw 0
previous_val_r: dw 0
next_val:
next_val_l: dw 0
next_val_r: dw 0

; 16/11/2023
faz:	db 0
	
; --------------------------------------------------------
; 27/05/2024 - (TRDOS 386 Kernel) audio.s
; --------------------------------------------------------

NOT_PCI32_PCI16	EQU 03FFFFFFFh ; NOT BIT31+BIT30 ; 19/03/2017
NOT_BIT31 EQU 7FFFFFFFh

pciFindDevice:
	; 19/11/2023
	; 03/04/2017 ('pci.asm', 20/03/2017)
	;
	; scan through PCI space looking for a device+vendor ID
	;
	; Entry: EAX=Device+Vendor ID
	;
	; Exit: EAX=PCI address if device found
	;	EDX=Device+Vendor ID
	;       CY clear if found, set if not found. EAX invalid if CY set.
	;
	; Destroys: ebx, edi ; 19/11/2023

        ; 19/11/2023
	mov	ebx, eax
	mov	edi, 80000000h
nextPCIdevice:
	mov 	eax, edi		; read PCI registers
	call	pciRegRead32
	; 19/11/2023
	cmp	edx, ebx
	je	short PCIScanExit	; found
	; 19/11/2023
	cmp	edi, 80FFF800h
	jnb	short pfd_nf		; not found
	add	edi, 100h
	jmp	short nextPCIdevice
pfd_nf:
	stc
	retn
PCIScanExit:
	;pushf
	mov	eax, NOT_BIT31 	; 19/03/2017
	and	eax, edi	; return only bus/dev/fn #
	retn

pciRegRead:
	; 01/12/2024
	; 03/04/2017 ('pci.asm', 20/03/2017)
	;
	; 8/16/32bit PCI reader
	;
	; Entry: EAX=PCI Bus/Device/fn/register number
	;           BIT30 set if 32 bit access requested
	;           BIT29 set if 16 bit access requested
	;           otherwise defaults to 8 bit read
	;
	; Exit:  DL,DX,EDX register data depending on requested read size
	;
	; Note1: this routine is meant to be called via pciRegRead8,
	;	 pciRegread16 or pciRegRead32, listed below.
	;
	; Note2: don't attempt to read 32 bits of data from a non dword
	;	 aligned reg number. Likewise, don't do 16 bit reads from
	;	 non word aligned reg #

	push	ebx
	push	ecx
        mov     ebx, eax		; save eax, dh
        mov     cl, dh

        and     eax, NOT_PCI32_PCI16	; clear out data size request
        or      eax, BIT31		; make a PCI access request
        and     al, NOT 3 ; 0FCh	; force index to be dword

        mov     dx, PCI_INDEX_PORT
        ;out	dx, eax			; write PCI selector
	; 29/05/2024
	push	ebx
	mov	ebx, eax ; data, dword
	mov	ah, 5 ; write port, dword
	; dx = port number
	int	34h
	pop	ebx
	
        mov     dx, PCI_DATA_PORT
        mov     al, bl
        and     al, 3			; figure out which port to
        add     dl, al			; read to

	test    ebx, PCI32+PCI16
        jnz     short _pregr0

	;in	al, dx			; return 8 bits of data
	; 29/05/2024
	mov	ah, 0 ; read port, byte
	; dx = port number
	int	34h
        
	mov	dl, al
	mov     dh, cl			; restore dh for 8 bit read
	jmp	short _pregr2
_pregr0:	
	test    ebx, PCI32
        jnz	short _pregr1

	;in	ax, dx
	; 29/05/2024
	mov	ah, 2 ; read port, word
	; dx = port number
	int	34h

	mov     dx, ax			; return 16 bits of data
	jmp	short _pregr2
_pregr1:
	;in	eax, dx			; return 32 bits of data
	; 29/05/2024
	mov	ah, 4 ; read port, dword
	; dx = port number
	int	34h

	mov	edx, eax
_pregr2:
	mov     eax, ebx		; restore eax
        and     eax, NOT_PCI32_PCI16	; clear out data size request
	pop	ecx
	pop	ebx
	retn

pciRegRead8:
        and     eax, NOT_PCI32_PCI16	; set up 8 bit read size
        jmp     short pciRegRead	; call generic PCI access

pciRegRead16:
        and     eax, NOT_PCI32_PCI16	; set up 16 bit read size
        or      eax, PCI16		; call generic PCI access
        jmp     short pciRegRead

pciRegRead32:
        and     eax, NOT_PCI32_PCI16	; set up 32 bit read size
        or      eax, PCI32		; call generic PCI access
        jmp     pciRegRead

pciRegWrite:
	; 01/12/2024
	; 03/04/2017 ('pci.asm', 29/11/2016)
	;
	; 8/16/32bit PCI writer
	;
	; Entry: EAX=PCI Bus/Device/fn/register number
	;           BIT31 set if 32 bit access requested
	;           BIT30 set if 16 bit access requested
	;           otherwise defaults to 8bit read
	;        DL/DX/EDX data to write depending on size
	;
	; Note1: this routine is meant to be called via pciRegWrite8,
	;	 pciRegWrite16 or pciRegWrite32 as detailed below.
	;
	; Note2: don't attempt to write 32bits of data from a non dword
	;	 aligned reg number. Likewise, don't do 16 bit writes from
	;	 non word aligned reg #

	push	ebx
	push	ecx
        mov     ebx, eax		; save eax, edx
        mov     ecx, edx
	and     eax, NOT_PCI32_PCI16	; clear out data size request
        or      eax, BIT31		; make a PCI access request
        and     al, NOT 3 ; 0FCh	; force index to be dword

        mov     dx, PCI_INDEX_PORT
	;out	dx, eax			; write PCI selector
	; 29/05/2024
	push	ebx
	mov	ebx, eax ; data, dword
	mov	ah, 5 ; write port, dword
	; dx = port number
	int	34h
	pop	ebx
	
        mov     dx, PCI_DATA_PORT
        mov     al, bl
        and     al, 3			; figure out which port to
        add     dl, al			; write to

	test    ebx, PCI32+PCI16
        jnz     short _pregw0
	mov	al, cl 			; put data into al
	;out	dx, al
	; 29/05/2024
	; al = data, byte
	mov	ah, 1 ; write port, byte
	; dx = port number
	int	34h

	jmp	short _pregw2
_pregw0:
	test    ebx, PCI32
        jnz     short _pregw1
	mov	ax, cx			; put data into ax
	;out	dx, ax
	; 29/05/2024
	push	ebx
	mov	ebx, eax ; data, word
	mov	ah, 3 ; write port, word
	; dx = port number
	int	34h
	pop	ebx

	jmp	short _pregw2
_pregw1:
	mov	eax, ecx		; put data into eax
	;out	dx, eax
	; 29/05/2024
	push	ebx
	mov	ebx, eax ; data, dword
	mov	ah, 5 ; write port, dword
	; dx = port number
	int	34h
	pop	ebx
_pregw2:
        mov     eax, ebx		; restore eax
        and     eax, NOT_PCI32_PCI16	; clear out data size request
        mov     edx, ecx		; restore dx
	pop	ecx
	pop	ebx
	retn

pciRegWrite8:
        and     eax, NOT_PCI32_PCI16	; set up 8 bit write size
        jmp	short pciRegWrite	; call generic PCI access

pciRegWrite16:
        and     eax, NOT_PCI32_PCI16	; set up 16 bit write size
        or      eax, PCI16		; call generic PCI access
        jmp	short pciRegWrite

pciRegWrite32:
        and     eax, NOT_PCI32_PCI16	; set up 32 bit write size
        or      eax, PCI32		; call generic PCI access
        jmp	pciRegWrite

; --------------------------------------------------------
; 19/05/2024 - (playwav4.asm) ac97_vra.asm
; --------------------------------------------------------

	; 13/11/2023

;VRA:	db 1

codecConfig:
	; 01/12/2024 (ac97play.s)
	; 29/05/2024 (playwav7.s modification)
	; 19/05/2024
	; 19/11/2023
	; 15/11/2023
	; 04/11/2023
	; 17/02/2017 
	; 07/11/2016 (Erdogan Tan)

	;AC97_EA_VRA equ 1
	AC97_EA_VRA equ BIT0

	; 04/11/2023
init_ac97_controller:
	mov	eax, [bus_dev_fn]
	mov	al, PCI_CMD_REG
	call	pciRegRead16		; read PCI command register
	or      dl, IO_ENA+BM_ENA	; enable IO and bus master
	call	pciRegWrite16

	;call	delay_100ms

	; 19/05/2024
	; ('PLAYMOD3.ASM', Erdogan Tan, 18/05/2024)

init_ac97_codec:
	; 18/11/2023
	mov	ebp, 40
	; 29/05/2024
	;mov	ebp, 1000
_initc_1:
	; 29/05/2024
	mov	dx, GLOB_STS_REG ; 30h
	add	dx, [NABMBAR]
	;in	eax, dx
	mov	ah, 4	; read port, dword
	int	34h

	; 19/05/2024
	;call	delay1_4ms

	cmp	eax, 0FFFFFFFFh ; -1
	jne	short _initc_3
_initc_2:
	dec	ebp
	jz	short _ac97_codec_ready

	; 31/05/2024
	call	delay_100ms
	jmp	short _initc_1
_initc_3:
	test	eax, CTRL_ST_CREADY
	jnz	short _ac97_codec_ready

	; 30/05/2024
	cmp	byte [reset], 1
	jnb	short _initc_2

	call	reset_ac97_codec
	; 30/05/2024
	mov	byte [reset], 1
	; 19/05/2024
	jmp	short _initc_2

_ac97_codec_ready:
	mov	dx, [NAMBAR]
	;add	dx, 0 ; ac_reg_0 ; reset register
	;out	dx, ax
	; 29/05/2024
	push	ebx
	mov	ebx, eax ; bx = data, word
	mov	ah, 3	; write port, word
	int	34h
	pop	ebx

	; 31/05/2024
	; 29/05/2024
	;call	delay_100ms

	; 19/11/2023
	or	ebp, ebp
	jnz	short _ac97_codec_init_ok

	xor	eax, eax ; 0
	mov	dx, [NAMBAR]
	add	dx, CODEC_REG_POWERDOWN
	;out	dx, ax
	; 29/05/2024
	push	ebx
	mov	ebx, eax
	mov	ah, 3	; write port, word
	int	34h
	pop	ebx

	; 19/11/2023
	; wait for 1 second
	; 19/05/2024
	mov	ecx, 1000 ; 1000*4*0.25ms = 1s
	;;mov	ecx, 10
	; 30/05/2024
	;mov	ecx, 40
_ac97_codec_rloop:
	;call	delay_100ms
	; 31/05/2024
	call	delay1_4ms

	;mov	dx, [NAMBAR]
	;add	dx, CODEC_REG_POWERDOWN
	;in	ax, dx
	; 29/05/2024
	mov	dx, [NAMBAR]
	add	dx, CODEC_REG_POWERDOWN
	; 31/05/2024
	mov	ah, 2	; read port, word
	int	34h

	; 31/05/2024
	;call	delay1_4ms
	
	and	ax, 0Fh
	cmp	al, 0Fh
	je	short _ac97_codec_init_ok
	loop	_ac97_codec_rloop 

init_ac97_codec_err1:
	;stc	; cf = 1 ; 19/05/2024
init_ac97_codec_err2:
	retn

_ac97_codec_init_ok:
	call 	reset_ac97_controller

	; 31/05/2024
	; 30/05/2024
	; 19/05/2024
	;call	delay_100ms

	; 30/05/2024
	;call	delay1_4ms
	;call	delay1_4ms
	;call	delay1_4ms
	;call	delay1_4ms

	; 01/12/2024
setup_ac97_codec:
	; 12/11/2023
	cmp	word [WAVE_SampleRate], 48000
	je	skip_rate
	
	; 31/05/2024
	; 30/05/2024
	; 29/05/2024
	;cmp	byte [VRA], 0
	;jna	short skip_rate

	; 11/11/2023
	mov	dx, [NAMBAR]
	add	dx, CODEC_EXT_AUDIO_CTRL_REG  	; 2Ah
	;in	ax, dx
	; 29/05/2024
	mov	ah, 2 ; read port, word
	int	34h

	; 30/05/2024
	; 19/05/2024
	call	delay1_4ms

	;and	al, ~BIT1 ; Clear DRA
	;;;
	; 30/05/2024
	;and	al, ~(BIT1+BIT0) ; Clear DRA+VRA
	; 01/12/2024 (FASM)
	and	al, NOT (BIT1+BIT0) ; 0FCh
	;out	dx, ax
	; 31/05/2024
	push	ebx
	mov	ebx, eax
	mov	dx, [NAMBAR]
	add	dx, CODEC_EXT_AUDIO_CTRL_REG  	; 2Ah
	mov	ah, 3 ; write port, word
	int	34h
	pop	ebx

	; 31/05/2024
	call	check_vra

	; 31/05/2024 - temporary (interpolated sample rate test)
	;mov	byte [VRA], 0

	; 31/05/2024
	cmp	byte [VRA], 0
	jna	short skip_rate

	mov	dx, [NAMBAR]
	add	dx, CODEC_EXT_AUDIO_CTRL_REG  	; 2Ah
	;in	ax, dx
	; 31/05/2024
	mov	ah, 2 ; read port, word
	int	34h

	;and	al, ~BIT1 ; Clear DRA
	;;;

	or	al, AC97_EA_VRA ; 1 ; 04/11/2023
	;out	dx, ax	; Enable variable rate audio
	; 29/05/2024
	push	ebx
	mov	ebx, eax
	;
	; 30/05/2024
	mov	dx, [NAMBAR]
	add	dx, CODEC_EXT_AUDIO_CTRL_REG  	; 2Ah
	;
	mov	ah, 3 ; write port, word
	int	34h
	pop	ebx

	;mov	cx, 10
	mov	ecx, 10 ; 30/05/2024
check_vra_loop:
	; 31/05/2024
	;call	delay_100ms
	; 30/05/2024
	call	delay1_4ms

	; 11/11/2023
	;in	ax, dx
	; 29/05/2024
	mov	dx, [NAMBAR]
	add	dx, CODEC_EXT_AUDIO_CTRL_REG  	; 2Ah
	mov	ah, 2 ; read port, word
	int	34h

	test	al, AC97_EA_VRA ; 1
	jnz	short set_rate

	; 11/11/2023
	loop	check_vra_loop

;vra_not_supported:	; 19/05/2024
	mov	byte [VRA], 0
	jmp	short skip_rate

set_rate:
	;mov	ax, [sample_rate] ; 17/02/2017 (Erdogan Tan)
	; 01/12/2024
	mov	ax, [WAVE_SampleRate]

	mov    	dx, [NAMBAR]
	add    	dx, CODEC_PCM_FRONT_DACRATE_REG	; 2Ch
	;out	dx, ax 	; PCM Front/Center Output Sample Rate
	; 29/05/2024
	push	ebx
	mov	ebx, eax  ; bx = data, word
	mov	ah, 3 ; write port, word
	int	34h
	pop	ebx

	; 29/05/2024
	;call	delay_100ms
	; 30/05/2024
	;call	delay1_4ms

	; 12/11/2023
skip_rate:
	mov	ax, 0202h
  	mov	dx, [NAMBAR]
  	add	dx, CODEC_MASTER_VOL_REG ;02h
	;out	dx, ax
	; 29/05/2024
	push	ebx
	mov	ebx, eax  ; bx = data, word
	mov	ah, 3 ; write port, word
	int	34h
	pop	ebx

	; 29/05/2024
	;call	delay1_4ms
	;call	delay1_4ms
	;call	delay1_4ms
	;call	delay1_4ms

	mov	ax, 0202h
  	mov	dx, [NAMBAR]
  	add	dx, CODEC_PCM_OUT_REG		;18h
  	;out	dx, ax
	; 29/05/2024
	push	ebx
	mov	ebx, eax  ; bx = data, word
	mov	ah, 3 ; write port, word
	int	34h
	pop	ebx

 	; 29/05/2024
	;call	delay1_4ms
	;call	delay1_4ms
	;call	delay1_4ms
	;call	delay1_4ms

	; 19/05/2024
	;clc

        retn

reset_ac97_controller:
	; 29/05/2024 (TRDOS 386)
	; 19/05/2024
	; 11/11/2023
	; 10/06/2017
	; 29/05/2017
	; 28/05/2017
	; reset AC97 audio controller registers
	xor	eax, eax
        mov	dx, PI_CR_REG
	add	dx, [NABMBAR]
	;out	dx, al
	; 29/05/2024
	; al = data, byte
	mov	ah, 1 ; write port, byte
	int	34h

	; 19/05/2024
	;call	delay1_4ms

        mov     dx, PO_CR_REG
	add	dx, [NABMBAR]
	;out	dx, al
	; 29/05/2024
	; al = data, byte
	mov	ah, 1 ; write port, byte
	int	34h

	; 19/05/2024
	;call	delay1_4ms

        mov     dx, MC_CR_REG
	add	dx, [NABMBAR]
	;out	dx, al
	; 29/05/2024
	; al = data, byte
	mov	ah, 1 ; write port, byte
	int	34h

	; 19/05/2024
	;call	delay1_4ms

        mov	al, RR
        mov	dx, PI_CR_REG
	add	dx, [NABMBAR]
	;out	dx, al
	; 29/05/2024
	; al = data, byte
	mov	ah, 1 ; write port, byte
	int	34h

	; 19/05/2024
	;call	delay1_4ms

        mov	dx, PO_CR_REG
	add	dx, [NABMBAR]
	;out	dx, al
	; 29/05/2024
	; al = data, byte
	mov	ah, 1 ; write port, byte
	int	34h

	; 19/05/2024
	;call	delay1_4ms

        mov	dx, MC_CR_REG
	add	dx, [NABMBAR]
	;out	dx, al
	; 29/05/2024
	; al = data, byte
	mov	ah, 1 ; write port, byte
	int	34h

	; 19/05/2024
	;call	delay1_4ms

	retn

reset_ac97_codec:
	; 29/05/2024 (TRDOS 386)
	; 11/11/2023
	; 28/05/2017 - Erdogan Tan (Ref: KolibriOS, intelac97.asm)
	mov	dx, GLOB_CNT_REG ; 2Ch
	add	dx, [NABMBAR]
	;in	eax, dx
	; 29/05/2024
	mov	ah, 4 ; read port, dword
	int	34h

	;test	eax, 2
	; 06/08/2022
	test	al, 2
	jz	short _r_ac97codec_cold

	call	warm_ac97codec_reset
	jnc	short _r_ac97codec_ok
_r_ac97codec_cold:
        call	cold_ac97codec_reset
        jnc	short _r_ac97codec_ok
	
	; 16/04/2017
        ;xor	eax, eax	; timeout error
       	;stc
	retn

_r_ac97codec_ok:
        xor     eax, eax
        ;mov	al, VIA_ACLINK_C00_READY ; 1
        inc	al
	retn

warm_ac97codec_reset:
	; 29/05/2024 (TRDOS 386)
	; 11/11/2023
	; 06/08/2022 - TRDOS 386 v2.0.5
	; 28/05/2017 - Erdogan Tan (Ref: KolibriOS, intelac97.asm)
	mov	eax, 6
	mov	dx, GLOB_CNT_REG ; 2Ch
	add	dx, [NABMBAR]
	;out	dx, eax
	; 29/05/2024
	push	ebx
	mov	ebx, eax  ; ebx = data, dword
	mov	ah, 5 ; write port, dword
	int	34h
	pop	ebx

	; 30/05/2024
	mov	ecx, 10	; total 1s
	; 29/05/2024
	;mov	ecx, 4000
_warm_ac97c_rst_wait:
	; 30/05/2024
	call	delay_100ms

	mov	dx, GLOB_STS_REG ; 30h
	add	dx, [NABMBAR]
	;in	eax, dx
	; 29/05/2024
	mov	ah, 4 ; read port, dword
	int	34h

	test	eax, CTRL_ST_CREADY
	jnz	short _warm_ac97c_rst_ok

	dec	ecx
	jnz	short _warm_ac97c_rst_wait

_warm_ac97c_rst_fail:
        stc
_warm_ac97c_rst_ok:
	retn

cold_ac97codec_reset:
	; 11/11/2023
	; 06/08/2022 - TRDOS 386 v2.0.5
	; 28/05/2017 - Erdogan Tan (Ref: KolibriOS, intelac97.asm)
        mov	eax, 2
	mov	dx, GLOB_CNT_REG ; 2Ch
	add	dx, [NABMBAR]
	;out	dx, eax
	; 29/05/2024
	push	ebx
	mov	ebx, eax  ; ebx = data, dword
	mov	ah, 5 ; write port, dword
	int	34h
	pop	ebx

	; 30/05/2024
	call	delay_100ms 	; wait 100 ms
	call	delay_100ms 	; wait 100 ms
	call	delay_100ms 	; wait 100 ms
	call	delay_100ms 	; wait 100 ms

	; 30/05/2024
	mov	ecx, 16	; total 20*100 ms = 2s
	; 29/05/2024
	;mov	ecx, 16000
_cold_ac97c_rst_wait:
	mov	dx, GLOB_STS_REG ; 30h
	add	dx, [NABMBAR]
	;in	eax, dx
	; 29/05/2024
	mov	ah, 4 ; read port, dword
	int	34h

	test	eax, CTRL_ST_CREADY
	jnz	short _cold_ac97c_rst_ok

	; 30/05/2024
	; 29/05/2024
	call	delay_100ms

	dec	ecx
	jnz	short _cold_ac97c_rst_wait

_cold_ac97c_rst_fail:
        stc
_cold_ac97c_rst_ok:
	retn

; 13/11/2024
; 30/05/2024
if 1
check_vra:
	; 29/05/2024
	mov	byte [VRA], 1

	; 29/05/2024 - audio.s (TRDOS 386 Kernel) - 27/05/2024
	; 24/05/2024
	; 23/05/2024
	mov	dx, [NAMBAR]
	add	dx, CODEC_EXT_AUDIO_REG	; 28h
	;in	ax, dx
	; 29/05/2024
	mov	ah, 2 ; read port, word
	int	34h

	; 30/05/2024
	; 23/05/2024
	call	delay1_4ms

	; 29/05/2024
	test	al, BIT0
	;test	al, 1 ; BIT0 ; Variable Rate Audio bit
	jnz	short check_vra_ok

vra_not_supported:
	; 13/11/2023
	mov	byte [VRA], 0
check_vra_ok:
	retn
end if

; --------------------------------------------------------

; 18/11/2024
; Ref: TRDOS 386 v2.0.9, audio.s, Erdogan Tan, 06/06/2024

ac97_stop: 
	; 18/11/2024
	mov	byte [stopped], 2

ac97_po_cmd@:
	xor	al, al ; 0
ac97_po_cmd:
	mov     dx, [NABMBAR]
        add     dx, PO_CR_REG	; PCM out control register
	;out	dx, al
	; 01/12/2024
	mov	ah, 1 ; write port, byte
	int	34h
	retn

ac97_pause:
	mov	byte [stopped], 1 ; paused
	;mov	al, 0
	;jmp	short ac97_po_cmd
	jmp	short ac97_po_cmd@

ac97_play: ; continue to play (after pause)
	mov	byte [stopped], 0
	mov	al, RPBM
	jmp	short ac97_po_cmd

; --------------------------------------------------------

PORTB		EQU 061h
REFRESH_STATUS	EQU 010h	; Refresh signal status

	; 01/12/2024 (ac97play.s)
delay_100ms:
	; 30/05/2024 (playwav7.s)
	push	ecx
	mov	ecx, 400  ; 400*0.25ms
_delay_x_ms:
	call	delay1_4ms
        loop	_delay_x_ms
	pop	ecx
	retn

delay1_4ms:
	; 30/05/2024 (TRDOS 386)
        push    eax 
        push    ecx
	push	ebx
	push	edx
        mov     ecx, 16			; close enough.
	;in	al, PORTB
	; 30/05/2024
	mov	dx, PORTB
	mov	ah, 0  ; read port, byte
	int	34h

	and	al, REFRESH_STATUS
	;mov	ah, al			; Start toggle state
	mov	bl, al
	or	ecx, ecx
	jz	short _d4ms1
	inc	ecx			; Throwaway first toggle
_d4ms1:	
	;in	al, PORTB		; Read system control port
	; 30/05/2024
	mov	dx, PORTB
	mov	ah, 0  ; read port, byte
	int	34h

	and	al, REFRESH_STATUS	; Refresh toggles 15.085 microseconds
	;cmp	ah, al
	cmp	bl, al
	je	short _d4ms1		; Wait for state change

	;mov	ah, al			; Update with new state
	mov	bl, al
	dec	ecx
	jnz	short _d4ms1

	pop	edx
        pop	ebx
	pop	ecx
        pop	eax
c4ue_okk:
        retn

; --------------------------------------------------------
; 14/11/2024 - Erdogan Tan
; --------------------------------------------------------

	; 01/12/2024 (32bit registers)
	; 29/11/2024
checkUpdateEvents:
	call	check4keyboardstop
	;jc	short c4ue_ok
	jc	short c4ue_okk ; 01/12/2024

	; 18/11/2024
	push	eax ; *
	or	eax, eax
	jz	c4ue_cpt

	; 18/11/2024
	cmp	al, 20h ; SPACE (spacebar) ; pause/play
	jne	short ch4ue_chk_s
	cmp	byte [stopped], 0
	ja	short c4ue_chk_ps
	; pause
	call	ac97_pause
	; 21/11/2024
	mov	al, [tLO]
	mov	byte [tLP], al
	jmp	c4ue_cpt
c4ue_chk_ps:
	cmp	byte [stopped], 1
	ja	short c4ue_replay
	; continue to play (after a pause)
	call	ac97_play 
	jmp	c4ue_cpt
c4ue_replay:
	; 19/11/2024
	pop	eax ; *
	pop	eax ; return address
	call	codecConfig
	mov	al, [volume]
	call	SetPCMOutVolume@
	mov	byte [stopped], 0
	call	move_to_beginning
	jmp	PlayWav	

ch4ue_chk_s:
	cmp	al, 'S'	; stop
	jne	short ch4ue_chk_fb
	cmp	byte [stopped], 0
	ja	c4ue_cpt ; Already stopped/paused
	call	ac97_stop
	; 19/11/2024
	mov	byte [tLO], 0
	; 21/11/2024
	mov	byte [tLP], '0'
	jmp	short c4ue_cpt	

ch4ue_chk_fb:
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

	; 01/12/2024
	; 18/11/2024
c4ue_ok:
	retn

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
	call 	write_ac97_pci_dev_info
	mov	dh, 24
	mov	dl, 79
	call	setCursorPosition
c4ue_chk_cr:
	; 19/11/2024
	cmp	al, 0Dh ; ENTER/CR key
	jne	short c4ue_cpt
	;inc	byte [wleds]
	;jnz	short c4ue_cpt
	;inc	byte [wleds]
	;;;
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
	jz	short c4ue_ok
c4ue_cpt_@:
	; 18/11/2024
	cmp	byte [stopped], 0
	ja	short c4ue_ok
	
	call	CalcProgressTime

	;cmp	ax, [ProgressTime]
	; 01/12/2024
	cmp	eax, [ProgressTime]
	;je	short c4ue_ok
			; same second, no need to update
	; 23/11/2024
	je	short c4ue_uvb

	;call	UpdateProgressTime
	;call	UpdateProgressBar@
	call	UpdateProgressBar

	; 23/11/2024
c4ue_uvb:
	cmp	byte [wleds], 0
	jna	short c4ue_vb_ok

	call	UpdateWaveLeds

c4ue_vb_ok:
	retn	

	;clc
;c4ue_ok:
;	retn

; --------------------------------------------------------
; 19/05/2024 - (playwav4.asm) ich_wav4.asm
; --------------------------------------------------------

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
	call	SetPCMOutVolume
	; 15/11/2024 (QEMU)
	;call	SetMasterVolume
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
	; 18/12/2024
	xor	eax, eax
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

; returns AL = current index value
getCurrentIndex:
	; 01/12/2024
	; 29/05/2024 (TRDOS 386)
	; 08/11/2023
	mov	dx, [NABMBAR]
	add	dx, PO_CIV_REG
	;in	al, dx
	; 29/05/2024
	mov	ah, 0 ; read port, byte
	int	34h
uLVI2:	;	06/11/2023
	retn

updateLVI:
	; 01/12/2024
	; 29/05/2024 (TRDOS 386)
	; 08/11/2023
	; 07/11/2023
	; 06/11/2023
	mov	dx, [NABMBAR]
	add	dx, PO_CIV_REG
	; (Current Index Value and Last Valid Index value)
	;in	ax, dx
	; 29/05/2024
	mov	ah, 2 ; read port, word
	int	34h

	cmp	al, ah ; is current index = last index ?
	jne	short uLVI2

	; 08/11/2023	
	call	getCurrentIndex
 
	test	byte [flags], ENDOFFILE
	;jnz	short uLVI1
	jz	short uLVI0  ; 08/11/2023

	; 08/11/2023
	push	eax	; 29/05/2024 (32 bit)
	mov	dx, [NABMBAR]
	add	dx, PO_SR_REG  ; PCM out status register
	;in	ax, dx
	; 29/05/2024
	mov	ah, 2 ; read port, word
	int	34h

	test	al, 3 ; bit 1 = Current Equals Last Valid (CELV)
		      ; (has been processed)
		      ; bit 0 = 1 -> DMA Controller Halted (DCH)
	pop	eax
	jz	short uLVI1
uLVI3:
	xor	eax, eax
	; zf = 1
	retn
uLVI0:
        ; not at the end of the file yet.
	dec	al
	and	al, 1Fh
uLVI1:
	;call	setLastValidIndex
;uLVI2:
	;retn

;input AL = index # to stop on
setLastValidIndex:
	; 01/12/2024
	; 29/05/2024 (TRDOS 386)
	; 08/11/2023
	mov	dx, [NABMBAR]
	add	dx, PO_LVI_REG
        ;out	dx, al
	; 29/05/2024
	; al = data, byte
	mov	ah, 1 ; write port, byte
	int	34h
	retn

; 29/05/2024
; 19/05/2024
volume: ;db	02h
	db	03h	; 13/12/2024

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

	; 09/12/2024
	; 19/11/2024
UpdateWaveLeds:
	; 23/11/2024
	call	reset_wave_leds
	; 09/12/2024
	;jmp	short turn_on_leds

; --------------------------------------------------------

	; 09/12/2024
	; 01/12/2024 (TRDOS 386, 32bit registers, flat memory)
	; 23/11/2024 (Retro DOS, 16bit registers, segmented)
	; 21/11/2024, 22/11/2024
	; 19/11/2024
turn_on_leds:
	cmp	byte [tLO],'2'
	jne	short tol_buffer_1

tol_buffer_2:
	mov	edx, WAVBUFFER_2
	jmp	short tol_@

tol_buffer_1:
	cmp	byte [tLO],'1'
	jne	short tol_clc_retn

	mov	edx, WAVBUFFER_1
tol_@:
	; calculate differential
	cmp	[pbuf_s], edx
	jne	short tol_ns_buf
	mov	ebx, [wleds_dif]
	mov	esi, [pbuf_o]
	mov	ecx, [buffersize] ; word
	shl	ecx, 1 ; byte
	sub	ecx, ebx ; sub ecx, [wleds_dif]
	add	esi, ebx
	jc	short tol_o_@
	cmp	esi, ecx
	jna	short tol_s_buf
tol_o_@:
	mov	esi, ecx
	jmp	short tol_s_buf

tol_clc_retn:
	clc
tol_retn:
	retn

tol_ns_buf:
	mov	[pbuf_s], edx
	xor	esi, esi ; 0
tol_s_buf:
	mov	[pbuf_o], esi

tol_buf_@:
	;mov	esi, [pbuf_o]
	add	esi, edx ; [pbuf_s]
	mov	ecx, 80
	xor	eax, eax ; 0
	mov	ebx, wleds_addr
tol_fill_c:
	lodsw	; left
	;shr	ax, 8
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
	add	ax, dx
	add	ah, 80h
	shr	eax, 13
	;;;
	push	ebx
	;shl	ax, 1
	; 01/12/2024
	shl	eax, 2
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

; --------------------------------------------------------
; --------------------------------------------------------

; DATA

; 30/05/2024
;reset:	db	0

Credits:
	db	'Tiny WAV Player for TRDOS 386 by Erdogan Tan. '
	db	'December 2024.',10,13,0
	db	'18/12/2024', 10,13
; 15/11/2024
reset:
	db	0

msgAudioCardInfo:
	db 	'for Intel AC97 (ICH) Audio Controller.', 10,13,0

msg_usage:
	db	'usage: AC97PLAY <FileName1> <FileName2> <...>',10,13,0 ; 28/11/2024

noDevMsg:
	db	'Error: Unable to find AC97 audio device!'
	db	10,13,0

noFileErrMsg:
	db	'Error: file not found.',10,13,0

msg_error:	; 30/05/2024

; 29/05/2024
; 11/11/2023
msg_init_err:
	db	CR, LF
	db	"AC97 Controller/Codec initialization error !"
	db	CR, LF, 0 ; 07/12/2024

; 25/11/2023
msg_no_vra:
	db	10,13
	db	"No VRA support ! Only 48 kHZ sample rate supported !"
	db	10,13,0

; 13/11/2024
; ('<<' to 'shl' conversion for FASM)
;
; 29/05/2024 (TRDOS 386)
; 17/02/2017
; Valid ICH device IDs

valid_ids:
;dd	(ICH_DID << 16) + INTEL_VID  	  ; 8086h:2415h
dd	(ICH_DID shl 16) + INTEL_VID  	  ; 8086h:2415h
dd	(ICH0_DID shl 16) + INTEL_VID 	  ; 8086h:2425h
dd	(ICH2_DID shl 16) + INTEL_VID 	  ; 8086h:2445h
dd	(ICH3_DID shl 16) + INTEL_VID 	  ; 8086h:2485h
dd	(ICH4_DID shl 16) + INTEL_VID 	  ; 8086h:24C5h
dd	(ICH5_DID shl 16) + INTEL_VID 	  ; 8086h:24D5h
dd	(ICH6_DID shl 16) + INTEL_VID 	  ; 8086h:266Eh
dd	(ESB6300_DID shl 16) + INTEL_VID  ; 8086h:25A6h
dd	(ESB631X_DID shl 16) + INTEL_VID  ; 8086h:2698h
dd	(ICH7_DID shl 16) + INTEL_VID 	  ; 8086h:27DEh
; 03/11/2023 - Erdogan Tan
dd	(MX82440_DID shl 16) + INTEL_VID  ; 8086h:7195h
dd	(SI7012_DID shl 16)  + SIS_VID	  ; 1039h:7012h
dd 	(NFORCE_DID shl 16)  + NVIDIA_VID ; 10DEh:01B1h
dd 	(NFORCE2_DID shl 16) + NVIDIA_VID ; 10DEh:006Ah
dd 	(AMD8111_DID shl 16) + AMD_VID 	  ; 1022h:746Dh
dd 	(AMD768_DID shl 16)  + AMD_VID 	  ; 1022h:7445h
dd 	(CK804_DID shl 16) + NVIDIA_VID	  ; 10DEh:0059h
dd 	(MCP04_DID shl 16) + NVIDIA_VID	  ; 10DEh:003Ah
dd 	(CK8_DID shl 16) + NVIDIA_VID	  ; 1022h:008Ah
dd 	(NFORCE3_DID shl 16) + NVIDIA_VID ; 10DEh:00DAh
dd 	(CK8S_DID shl 16) + NVIDIA_VID	  ; 10DEh:00EAh

;valid_id_count equ ($ - valid_ids)>>2 ; 05/11/2023
; 13/11/2024
valid_id_count = ($ - valid_ids) shr 2 ; 05/11/2023

; 19/11/2024
; 03/06/2017
hex_chars	db "0123456789ABCDEF", 0
msgAC97Info	db 0Dh, 0Ah
		db " AC97 Audio Controller & Codec Info", 0Dh, 0Ah 
		db " Vendor ID: "
msgVendorId	db "0000h Device ID: "
msgDevId	db "0000h", 0Dh, 0Ah
		db " Bus: "
msgBusNo	db "00h Device: "
msgDevNo	db "00h Function: "
msgFncNo	db "00h"
		db 0Dh, 0Ah
		db " NAMBAR: "
msgNamBar	db "0000h  "
		db "NABMBAR: "
msgNabmBar	db "0000h  IRQ: "
msgIRQ		dw 3030h
		db 0Dh, 0Ah, 0
; 25/11/2023
msgVRAheader	db " VRA support: "
		db 0	
msgVRAyes	db "YES", 0Dh, 0Ah, 0
msgVRAno	db "NO ", 0Dh, 0Ah
		db " (Interpolated sample rate playing method)"
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
; 28/11/2024
IsInSplash:	db 1

SplashFileName: db "SPLASH.WAV", 0

; 23/11/2024
colors:		db 0Fh, 0Bh, 0Ah, 0Ch, 0Eh, 09h, 0Dh, 0Fh
			; white, cyan, green, red, yellow, blue, magenta
ccolor:		db 0Bh	; cyan

EOF: 

; BSS

; 30/11/2024 (32bit address and pointers for TRDOS 386)
align 4

; 13/12/2024
audio_buffer:	rd 1

; 09/12/2024
pbuf_s:		rd 1

; 30/11/2024
; 22/11/2024
; wave volume leds address array
;wleds_addr:	rw 80*8 ; rb 2*80*8
; 01/12/2024
wleds_addr:	rd 80*8 ; 32bit address

; 14/11/2024
; 17/02/2017
bss_start:

; 13/11/2024
; ('resb','resw','resd' to 'rb','rw','rd' conversions for FASM)

; 18/11/2024
stopped:	rb 1
tLO:		rb 1
; 21/11/2024
tLP:		rb 1
; 19/11/2024
wleds:		rb 1
wleds_dif:	rd 1
; 09/12/2024
;pbuf_s:	rd 1
pbuf_o:		rd 1

; 29/11/2024
command:	rb 1

; 30/05/2024
VRA:		rb 1	; Variable Rate Audio Support Status

; 30/11/2024
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

; 15/11/2024
cursortype:	rw 1

flags:		rb 1
; 06/11/2023
ac97_int_ln_reg: rb 1

filehandle:	rd 1

; 30/11/2024
;argc:		rb 1	; argument count
argv:		rd 1	; current argument (wav file) ptr
argvf:		rd 1	; 1st argument (wav file) ptr
argvl:		rd 1	; last argument (wav file) ptr

; 30/05/2024
wav_file_name:
		rb 80	; wave file, path name (<= 80 bytes)

		rd 1	; 30/11/2024

; 17/02/2017
; NAMBAR:  Native Audio Mixer Base Address Register
;    (ICH, Audio D31:F5, PCI Config Space) Address offset: 10h-13h
; NABMBAR: Native Audio Bus Mastering Base Address register
;    (ICH, Audio D31:F5, PCI Config Space) Address offset: 14h-17h
NAMBAR:		rw 1			; BAR for mixer
NABMBAR:	rw 1			; BAR for bus master regs

; 01/12/2024
; 256 byte buffer for descriptor list
;BDL_BUFFER:	rd 1			; segment of our 256byte BDL buffer
;WAV_BUFFER1:	rd 1			; segment of our WAV storage
; 64k buffers for wav file storage
;WAV_BUFFER2:	rd 1			; segment of 2nd wav buffer

; 09/12/2024
; 23/11/2024
;turn_on_leds:	rd 1	; turn_on_leds procedure pointer (m8,m16,s8,s16)

; 12/11/2016 - Erdogan Tan
bus_dev_fn:	rd 1
dev_vendor:	rd 1

; 08/11/2023
; 07/11/2023
fbs_shift:	rb 1
; 29/11/2024
filecount:	rb 1

		rw 1	; 30/11/2024

; 15/11/2024
loadfromwavfile:
		rd 1	; 'loadfromfile' or load+conversion proc address
loadsize:	rd 1	; (.wav file) read count (bytes) per one time
buffersize:	rd 1	; 16 bit samples (not bytes)
		
; 14/11/2024
TotalTime:	rd 1	; Total (WAV File) Playing Time in seconds
ProgressTime:	rd 1
count:		rd 1	; byte count of one (wav file) read
LoadedDataBytes:
		rd 1	; total read/load count

timerticks:	rd 1	; (to eliminate excessive lookup of events in tuneloop)
			; (in order to get the emulator/qemu to run correctly)
; 01/12/2024
_bdl_buffer:	rd 1

; 14/11/2024	
bss_end:

; 02/12/2024
align 4096

; 01/12/2024

BDL_BUFFER:	rb 256
		; 02/12/2024
		rb 4096-256
;align 4096

; 29/05/2024
WAVBUFFER_1:	rb 65536
WAVBUFFER_2:	rb 65536

; 32 kilobytes for temporay buffer
; (for stereo-mono, 8bit/16bit corrections)
; 14/11/2024
;temp_buffer:	rb 32768
; 17/11/2024
;temp_buffer:	rb 50600  ; (44.1 kHZ stereo 12650 samples)
; 01/12/2024
temp_buffer:	rb 65536  ; rb BUFFERSIZE

;alignb 16
;bss_end: