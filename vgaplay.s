; ****************************************************************************
; vgaplay.s - TRDOS 386 (TRDOS v2.0.9) WAV PLAYER - VESA VBE Video Mode 101h
; ----------------------------------------------------------------------------
; VGAPLAY.PRG ! AC'97 (ICH) .WAV PLAYER program by Erdogan TAN
;
; 25/12/2024				- play music from multiple wav files -
;
; [ Last Modification: 27/12/2024 ]
;
; Modified from DPLAYWAV.PRG .wav player program by Erdogan Tan, 25/12/2024
;	    and AC97PLAY.PRG, 18/12/2024	
;
; ****************************************************************************
; nasm vgaplay.s -l vgaplay.txt -o VGAPLAY.PRG -Z error.txt

; dplayvga.s (25/12/2024) - play music from single wav file -
; ac97play.s (18/12/2024) - play music from multiple wav files -

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
BUFFERSIZE	equ 65536
ENDOFFILE	equ 1		; flag for knowing end of file

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

	; 21/12/2024
	; Detect (& Enable) AC'97 Audio Device
	call	DetectAC97
	jnc	short ac97_hardware_ready

	; 30/11/2024
	; 30/05/2024
_dev_not_ready:
	; couldn't find the audio device!
	sys	_msg, noDevMsg, 255, 0Fh
        jmp     Exit

ac97_hardware_ready:
	call	write_audio_dev_info

; -------------------------------------------------------------

	; 21/12/2024
	;;;
	; Read (copy) 8x14 system fonts
	mov	esi, fontbuff1
	sys	_video, 0C03h, 256, 0

	; convert 8x14 fonts to 8x16 fonts
	; by inserting 2 empty rows to each characters
	;mov	esi, fontbuff1
	mov	edi, fontbuff2
	; 18/02/2021
	;mov	cx, 256
fontconvert:
	push	ecx
	mov	cx, 14
	rep	movsb
	sub	al, al
	stosb
	stosb
	pop	ecx
	loop	fontconvert
	;;;

; ------------------------------------------------------------- 

	; 21/12/2024
	; Set Video Mode to 101h ; 640x480, 256 colors
	sys	_video, 08FFh, 101h
	or	eax, eax
	jz	terminate    ; nothing to do				
	;jz	trdos386_err ; write (OS) error msg and exit

set_vesa_mode_101h_ok:
	; linear frame buffer access
	sys	_video, 06FFh
	and	eax, eax
	jz	error_exit ; set text mode and write err msg
	mov	[LFB_ADDR], eax

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

	; 25/12/2024
Player_ParseParameters:
	; 30/11/2024
	; 29/11/2024
	; 18/12/2024
	;mov	edx, wav_file_name
	
	; 26/12/2024
	;cmp	byte [IsInSplash], 0
	;jna	short check_p_command

	mov	edx, SplashFileName
	jmp	short _1

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
        call	openFile ; no error? ok.
        jnc	getwavparms	; 14/11/2024

	; 28/11/2024
	cmp	byte [IsInSplash], 0
	ja	Player_SplashScreen

	; 29/11/2024
	cmp	byte [filecount], 0
	ja	short check_p_command

	; 25/12/2024
	; 21/12/2024
	call	set_text_mode
	; file not found!
	; 30/11/2024
	sys	_msg, noFileErrMsg, 255, 0Ch
        jmp     Exit

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

; -------------------------------------------------------------

	; 25/12/2024
	cmp 	byte [IsInSplash], 0
	;jna	short StartPlay
	; 27/12/2024
	jna	short StartPlay@

; -------------------------------------------------------------

	; 26/12/2024
Player_SplashScreen:
	; 21/12/2024
	;mov	byte [tcolor], 15
_0:
	call	drawsplashscreen

	; 21/12/2024
	;;;
	; set wave volume led addresses
	mov	ebx, [LFB_ADDR]
	add	ebx, (13*80*8*14)
	mov	ebp, 80
	mov	edi, wleds_addr
wleds_sa_1:
	mov	ecx, 15
wleds_sa_2:
	mov	eax, 80*8*14 ; 640*14 pixels (next row)
	mul	ecx
	add	eax, ebx
	stosd
	loop	wleds_sa_2
	mov	eax, ebx
	stosd
	add	ebx, 8
	dec	ebp
	jnz	short wleds_sa_1
	;;;

	; 25/12/5024
	; 28/11/2024 
	cmp	dword [filehandle], -1
	jne	short StartPlay

	; 24/12/2024
	; 07/12/2024
	;;; wait for 3 seconds
	sys	_time, 0 ; get time in unix epoch format
	mov	ecx, eax
	add	ecx, 3
_wait_3s:
	nop
	sys	_time, 0
	cmp	eax, ecx
	jb	short _wait_3s
	;;;

	; 25/12/2024
	; 28/11/2024
	mov	byte [IsInSplash], 0
	;mov	edx, wav_file_name
	; 30/11/2024
	mov	esi, [argvf]
	; 29/11/2024
	jmp	Player_ParseNextParameter

; -------------------------------------------------------------

	; 27/12/2024
StartPlay@:

	; 27/12/2024 (Detect & Enable AC97 hardware again)
	; (this is needed after disabling audio system)
	; Detect (BH=1) AC'97 (BL=2) Audio Device
        sys	_audio, 0102h
	; ignore error at this stage
	;jc	short ac97_not_detected

; -------------------------------------------------------------

	; 25/12/2024
StartPlay:
	inc	byte [filecount]
	mov	byte [command], 0

; -------------------------------------------------------------

	; 07/12/2024 (playwav9.s)

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
	;mov	eax, BUFFERSIZE/2 ; 32768
	; 07/12/2024
	mov	eax, BUFFERSIZE ; 65536
	mov	[buffersize], eax	; 16 bit samples
	; 07/12/2024
	;shl	eax, 1			; bytes
	mov	cl, [fbs_shift]
	shr	eax, cl 
	;mov	[loadsize], ax ; 16380 or 32760 or 65520
	mov	[loadsize], eax ; 16384 or 32768 or 65536
	;;;
	;jmp	PlayNow ; 30/05/2024
	; 07/12/2024
	jmp	Player_Template

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

	; 07/12/2024
vra_needed:
	; 30/11/2024 (TRDOS 386, ax -> eax)
	; 13/11/2023
	pop	eax ; discard return address to the caller
	; 30/05/2024
vra_err:
	; 21/12/2024
	call	set_text_mode
	; 30/11/2024
	sys	_msg, msg_no_vra, 255, 0Fh
	jmp	Exit

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
	
	; 07/12/2024
	;shr	eax, 1	; buffer size is 16 bit sample count
	mov	[buffersize], eax ; buffer size in bytes
	mov	[loadfromwavfile], ebx

; -------------------------------------------------------------

Player_Template:

	; 26/12/2024
	cmp 	byte [IsInSplash], 0
	jna	short Player_Template_@

	; 24/12/2024 (setting for wave lighting points)
	mov	eax, [LFB_ADDR]
	;add	eax, 228*640 ; wave graphics start (top) line/row
	add	eax, 164*640 ; 256 volume levels ; 24/12/2024
	mov	[graphstart], eax

	; 26/12/2024
	jmp	short PlayNow

Player_Template_@:
	; 21/12/2024
	call	clearscreen
	call	drawplayingscreen

	; 14/11/2024
	call	SetTotalTime
	call	UpdateFileInfo

; -------------------------------------------------------------

	; 21/12/2024 (VGA/LFB modifications)
	; (Direct access/map to the LFB is already done here)
	; ((this program is in VESA/VBE graphics mode here))
PlayNow:
	; 07/12/2024
	sys	_audio, 0200h, [buffersize], audio_buffer
	jc	error_exit ; return to text mode and print err msg

	; 01/06/2024
	; Initialize Audio Device (bh = 3)
	sys	_audio, 0301h, 0, audio_int_handler
	;jc	short error_exit
	jc	init_err ; return to text mode and print err msg

	; 30/05/2024
	; playwav4.asm
;_2:	; 24/12/2024
	;call	check4keyboardstop	; flush keyboard buffer
	;jc	short _2		; 07/11/2023

	;;;
	; 26/12/2024
	; 14/11/2024
	;mov	al, 3	; 0 = max, 31 = min
	; 15/11/2024
	call	SetMasterVolume

	; 26/12/2024
	cmp 	byte [IsInSplash], 0
	ja	short _2

	; 07/12/2024
	;call	SetPCMOutVolume
	call	UpdateVolume
	;;;
	; 14/11/2024
	call	UpdateProgressBar
	;;;

	; 26/12/2024
_2:

; play the .wav file. Most of the good stuff is in here.
	
	; 05/12/2024
	call    PlayWav

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
	; 26/12/2024
	mov	byte [pbuf_s], 0FFh
	;;;

;	cmp	byte [IsInSplash], 0
;	jna	short _6
;	mov	byte [IsInSplash], 0
;	mov	esi, [argvf]
;	jmp	Player_ParseNextParameter
;
;	; 29/11/2024
;_6:
;	cmp	byte [command], 'Q'
;	je	short _7	; 25/12/2024
;	jmp	check_p_command
;
;_7:
	; 07/12/2024
	;;;
	; Stop Playing
	;sys	_audio, 0700h
	; Cancel callback service (for user)
	sys	_audio, 0900h
	; Deallocate Audio Buffer (for user)
	sys	_audio, 0A00h
	; Disable Audio Device
	sys	_audio, 0C00h
	;;;

	; 27/12/2024
	; 26/12/2024
	cmp	byte [IsInSplash], 0
	jna	short _6
	mov	byte [IsInSplash], 0
	mov	esi, [argvf]
	jmp	Player_ParseNextParameter
_6:
	cmp	byte [command], 'Q'
	je	short terminate
	jmp	check_p_command

terminate:
	call	set_text_mode
Exit:
	sys	_exit
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

	; 02/12/2024
Player_Quit@:
	pop	eax ; return addr (call PlayWav@)
	
	; 29/11/2024
Player_Quit:
	jmp	 short terminate


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

	; 21/12/2024
clearscreen:
	; fast clear
	; 640*480, 256 colors
	mov	edi, [LFB_ADDR]
	mov	ecx, (640*480*1)/4 ; 22/12/2024
	xor	eax, eax
	rep	stosd
	retn

; -------------------------------------------------------------

	; 26/12/2024
	; 21/12/2024
drawsplashscreen:
	mov	ebp, SplashScreen
	;;mov	dword [nextrow], 00100000h ; 8*16
	;mov	dword [nextrow], 000E0000h ; 8*14
	;mov	esi, 0 ; row 0, column 0
	mov	esi, 00020000h ; row 2, column 0 ; top margin = 2
	jmp	short p_d_x
drawplayingscreen:
	mov	ebp, PlayingScreen
	;mov	dword [nextrow], 000E0000h ; 8*14
	;mov	esi, 0 ; row 0, column 0
	mov	esi, 00070000h ; row 7, column 0 ; top margin = 7
p_d_x:
	mov	byte [columns], 80
p_d_x_n:
	xor	edx, edx
	mov	dl, [ebp]
	and	dl, dl
	jz	short p_d_x_ok
	shl	edx, 4 ; * 16 (for 8x16 font)

	mov	edi, fontbuff2 ; start of user font data
	add	edi, edx
	
	;; NOTE: Following system call writes fonts at
	;; Std VGA video memory 0A0000h, BL bit 7 selects
	;; screen width as 640 pixels (instead of 320 pixels)
	;; so 8Fh is sub function 0Fh (write char)
	;; with 640 pixels screen witdh. 
	;; (Even if VESA VBE mode -LFB- is in use, QEMU and
	;; a real computer with NVIDIA GEFORCE FX 550 uses
	;; A0000h, so.. even if fonts are written at A0000h-B0000h
	;; region, the text is appeared on screen
	;; while LFB is at C0000000h or E0000000h.)

	;sys	_video, 018Fh, [tcolor], 8001h
			;; use STD VGA video memory
			;; (0A0000h)
	;sys	_video, 020Fh, [tcolor], 8001h ; 8x16 user font
		 ; use LFB for current VBE mode
		 ; for writing fonts on screen
	; 26/12/2024
	sys	_video, 020Fh, 0Fh, 8001h ; 8x16 user font

	inc	ebp
	add	si, 8 ; next char pos
	dec	byte [columns]
	jnz	short p_d_x_n	; next column
	xor	si, si
	;;add	esi, 00100000h	; next row ; 8*16
	;add	esi, [nextrow]
	add	esi, 000E0000h	; next row ; 8*14
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

	; 07/12/2024 (playwav9.s)
	; 26/11/2023 (playwav8.s)
PlayWav:
	; 19/11/2024
	mov	byte [wleds], 1

	;;;
	; 09/12/2024
	mov	eax, 10548 ; (48000*10/182)*4
	cmp	byte [VRA], 0
	jna	short _3 ; 48kHZ (interpolation)
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
_3:
	mov	[wleds_dif], eax ; buffer read differential (distance)
				; for wave volume leds update
				; (byte stream per 1/18.2 second)
	;;;
	; 24/12/2024
	cmp	eax, 640*4 ; 640 samples (for 640 wave light points)
	jnb	short _4
	mov	eax, 640*4	
_4:
	mov	[wpoints_dif], eax
	;;;

RePlayWav:
	; 07/12/2024
	mov	edi, audio_buffer
	call	dword [loadfromwavfile]
	jc	error_exit

	mov	byte [half_buffer], 1 ; (DMA) Buffer 1

	mov	eax, [count]
	add	[LoadedDataBytes], eax

	test    byte [flags], ENDOFFILE  ; end of file
	jnz	short _5 ; yes
			 ; bypass filling dma half buffer 2

	; bh = 16 : update (current, first) dma half buffer
	; bl = 0  : then switch to the next (second) half buffer
	sys	_audio, 1000h

	; 18/12/2024
	mov	dword [count], 0

	; 07/12/2024
	mov	edi, audio_buffer
	call	dword [loadfromwavfile]
	;jc	error_exit
	
	mov	eax, [count]
	add	[LoadedDataBytes], eax
_5:
	; 07/12/2024
 	mov	cx, [WAVE_SampleRate]
	mov	bl, 3	; 16 bit, stereo
	mov	bh, 4	; start to play
	sys	_audio

	;;;
	; 26/12/2024
SplashLoop:
	cmp	byte [IsInSplash], 0
	jna	short _10
	;; skip 1st signal without sound data loading
	;nop
	;nop
	;nop
	;cmp	byte [SRB], 0
	;jna	short SplashLoop
	;mov	byte [SRB], 0
_8:
	test    byte [flags], ENDOFFILE  ; end of file
	jnz	ac97_stop ; yes

	; bh = 16 : update (current, first) dma half buffer
	; bl = 0  : then switch to the next (second) half buffer
	sys	_audio, 1000h

	cmp	byte [SRB], 0
	jna	short _9
	mov	byte [SRB], 0
	mov	edi, audio_buffer
	call	dword [loadfromwavfile]
	jnc	short _9
	; end of file
	;call	ac97_stop
	;retn
	jmp	ac97_stop
_9:
	call	check4keyboardstop
	jc	_exitt_
	jmp	short _8
_10:
	; 26/12/2024
	cmp	byte [p_mode], 0
	ja	short tuneLoop
	;;;

; -------------------------------------------

	; 22/12/2024
 	; prepare all leds as turned off
	call	reset_wave_leds

; -------------------------------------------

	; 07/12/2024 (playwav9.s)
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
	; 24/11/2024
	jna	short tL1

tLWait@:	; 21/11/2024
	;;;
	; 25/12/2024
	; 09/12/2024
	cmp	byte [stopped], 3
	jnb	_exitt_
	;;;
	call	checkUpdateEvents
	jc	_exitt_
	;;;
	; 25/12/2024
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
	; 27/11/2024
	; Check AC'97 interrupt status
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

	; 07/12/2024
	mov	edi, audio_buffer
	;call	loadFromFile
	; 18/11/2023
	;call	word [loadfromwavfile]
	; 01/12/2024
	call	dword [loadfromwavfile]
	jc	short _exitt_	; end of file

	; 07/12/2024
	;;;;
	; bh = 16 : update (current, first) dma half buffer
	; bl = 0  : then switch to the other half buffer
	sys	_audio, 1000h
	;;;;

	; 26/11/2024
	mov	al, [half_buffer]
	add	al, '1'
	; 19/11/2024
	mov	[tLO], al
	call	tL0

	; 24/11/2024
	; 14/11/2024
	;mov	ax, [count]
	;add	[LoadedDataBytes], ax
	;adc	word [LoadedDataBytes+2], 0
	; 01/12/2024
	mov	eax, [count]
	add	[LoadedDataBytes], eax

	; 07/12/2024 (playwav9.s)
	; 27/11/2024 (playwav9.asm)
	jmp	short tL2

_exitt_:
	; 07/12/2024
	; Stop Playing
	;mov	byte [stopped], 2
	;sys	_audio, 0700h
	call	ac97_stop

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

	; 22/12/2024 (graphics mode modification)
	; (640*480, 256 colors)
	;;;
	;mov	ebp, 16
	mov	ebp, 14
	mov	edi, [LFB_ADDR]
	movzx	esi, al
	shl	esi, 4 ; * 16
	add	esi, fontbuff2
tL0_1:
	mov	edx, 8 ; 8 pixels (8*16 pixel font)
	mov	ah, [esi]
tL0_2:
	mov	al, 0Ch ; red
	shl	ah, 1
	jnc	short tL0_3
	mov	al, 0Eh ; yellow
tL0_3:
	stosb
	dec	edx
	jnz	short tL0_2
	dec	ebp
	jz	short tL0_4
	add	edi, 640-8 ; next line
	inc	esi
	jmp	short tL0_1
tL0_4:
	;;;
	retn

; -------------------------------------------

	; 26/12/2024
	; 07/12/2024
SetMasterVolume:
	mov	al, [volume]
	; 26/12/2024
	;mov	[volume], al  ; max = 0, min = 31

	mov	ah, 31
	sub	ah, al
	mov	al, ah

	; Set Master Volume Level (BL=0 or 80h)
	; 	for next playing (BL>=80h)
	;sys	_audio, 0B80h, eax
	sys	_audio, 0B00h, eax
	
setvolume_ok:
ac97_not_detected:
	retn

; -------------------------------------------

	; 07/12/2024 (playwav9.s)
DetectAC97:
DetectICH:
	; 25/11/2023 (playwav8.s)
	; Detect (BH=1) AC'97 (BL=2) Audio Device
        sys	_audio, 0102h
	;jnc	short d_ac97_@
	;retn
	jc	short ac97_not_detected
d_ac97_@:
	; 07/12/2024 (playwav9.s)
	; 06/06/2017
	sys	_audio, 0E00h ; get audio controller info
	jc	error_exit ; 25/11/2023

	;cmp	ah, 2 ; ICH ? (Intel AC'97 Audio Controller)
	;jne	_dev_not_ready	

	; EAX = IRQ Number in AL
	;	Audio Device Number in AH 
	; EBX = DEV/VENDOR ID
	;       (DDDDDDDDDDDDDDDDVVVVVVVVVVVVVVVV)
	; ECX = BUS/DEV/FN 
	;       (00000000BBBBBBBBDDDDDFFF00000000)
	; EDX = NABMBAR/NAMBAR (for AC97)
	;      (Low word, DX = NAMBAR address)
	; EDX = Base IO Addr (DX) for SB16 & VT8233

	mov	[dev_vendor], ebx
	mov	[bus_dev_fn], ecx

        mov     [NAMBAR], dx			; save audio mixer base addr
	;shr	edx, 16
        ;mov    [NABMBAR], dx			; save bus master base addr
	mov	[NAMBAR], edx

	mov	[ac97_int_ln_reg], al

	; 07/12/2024
	; 01/06/2024
	; 25/11/2023
	; Get AC'97 Codec info
	; (Function 14, sub function 1)
	sys	_audio, 0E01h
	; Save Variable Rate Audio support bit
	and	al, 1
	mov	[VRA], al

	;clc

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

; --------------------------------------------------------
; 07/12/2024
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
	; 14/12/2024
	; 07/12/2024
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
	; 07/12/2024
	; 26/11/2023 (playwav8.s)
	;mov	edi, audio_buffer

	; 01/12/2024 (TRDOS 386)
	; edi = audio buffer address

	; 14/12/2024
	; 01/12/2024
	; 17/11/2024
	;mov	ebx, [filehandle]
	; 02/12/2024
	;mov	edx, [loadsize] 

	; 17/11/2024
	cmp	byte [fbs_shift], 0
	jna	short lff_1 ; stereo, 16 bit

lff_2:
	; 01/12/2024
	mov	esi, temp_buffer 
	; 14/12/2024
	sys 	_read, [filehandle], esi, [loadsize]
	jc	lff_4 ; error !

	; 01/12/2024
	; 14/11/2024
	mov	[count], eax

	; 01/12/2024
	and	eax, eax
	;jz	short lff_3
	; 14/12/2024
	jz	lff_10

	mov	bl, [fbs_shift]

	; 14/12/2024
	mov	edx, edi ; audio buffer start address

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
	; 14/12/2024
	mov	eax, edi
	mov	ecx, [buffersize] 
	add	ecx, edx ; + buffer start address
	cmp	eax, ecx	
	jb	short lff_3
	retn
	
lff_1:  
	; 07/12/2024
	; 01/12/2024
	;sys 	_read, [filehandle], esi, [loadsize] ; edx
	; 14/12/2024
	sys 	_read, [filehandle], edi, [loadsize]
	; 07/11/2023
	jc	short lff_4 ; error !

	; 01/12/2024
	; 14/11/2024
	mov	[count], eax

	; 02/12/2024
	cmp	eax, edx ; cmp eax, [loadsize]	
	je	short endLFF
	; edi = buffer (start) address
	add	edi, eax
	mov	ecx, edx
lff_3:
	;call	padfill			; blank pad the remainder
	; 21/12/2024
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
	; 01/12/2024
	sub	ecx, eax
	; 01/12/2024
	; 25/11/2024
	xor	eax, eax
	; 14/12/2024
	rep	stosb
	; 21/12/2024
	;retn
	; ----------
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
	xor	ebx, ebx
	mov	bl, al
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [hex_chars+ebx]
	mov	[msgVendorId+3], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [hex_chars+ebx]
	mov	[msgVendorId+2], al
	mov	bl, ah
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [hex_chars+ebx]
	mov	[msgVendorId+1], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [hex_chars+ebx]
	mov	[msgVendorId], al
	shr	eax, 16
	mov	bl, al
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [hex_chars+ebx]
	mov	[msgDevId+3], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [hex_chars+ebx]
	mov	[msgDevId+2], al
	mov	bl, ah
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [hex_chars+ebx]
	mov	[msgDevId+1], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [hex_chars+ebx]
	mov	[msgDevId], al

	mov	eax, [bus_dev_fn]
	shr	eax, 8
	mov	bl, al
	mov	dl, bl
	and	bl, 7 ; bit 0,1,2
	mov	al, [hex_chars+ebx]
	mov	[msgFncNo+1], al
	mov	bl, dl
	shr	bl, 3
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [hex_chars+ebx]
	mov	[msgDevNo+1], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [hex_chars+ebx]
	mov	[msgDevNo], al
	mov	bl, ah
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [hex_chars+ebx]
	mov	[msgBusNo+1], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [hex_chars+ebx]
	mov	[msgBusNo], al

	;mov	ax, [ac97_NamBar]
	mov	ax, [NAMBAR]
	mov	bl, al
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [hex_chars+ebx]
	mov	[msgNamBar+3], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [hex_chars+ebx]
	mov	[msgNamBar+2], al
	mov	bl, ah
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [hex_chars+ebx]
	mov	[msgNamBar+1], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [hex_chars+ebx]
	mov	[msgNamBar], al

	;mov	ax, [ac97_NabmBar]
	mov	ax, [NABMBAR]
	mov	bl, al
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [hex_chars+ebx]
	mov	[msgNabmBar+3], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [hex_chars+ebx]
	mov	[msgNabmBar+2], al
	mov	bl, ah
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [hex_chars+ebx]
	mov	[msgNabmBar+1], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [hex_chars+ebx]
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
	; 21/12/2024
	mov	ebp, msgAC97Info ; message
	; 22/12/2024
	;mov	cl, 07h ; color 
	call	sys_gmsg
	;
	; 30/05/2024
write_VRA_info:
	; 21/12/2024
	mov	ebp, msgVRAheader ; message
	;mov	cl, 07h ; color 
	call	sys_gmsg
	;
	cmp	byte [VRA], 0
	jna	short _w_VRAi_no
_w_VRAi_yes:
	mov	ebp, msgVRAyes
	jmp	short _w_VRAi_yn_msg
_w_VRAi_no:
	mov	ebp, msgVRAno
_w_VRAi_yn_msg:
	;mov	cl, 07h ; color 
	;call	sys_msg
	;retn
	;jmp	short sys_gmsg
	;;;
; --------------------------------------------------------

	; 22/12/2024
	;;;
	; 21/12/2024
	; (write message in VGA/VESA-VBE mode)
sys_gmsg:
	mov	al, [ebp]
	and	al, al
	jz	short sys_gmsg_ok
	cmp	al, 20h
	jnb	short sys_gmsg_3
	cmp	al, CR ; 13
	jne	short sys_gmsg_2
	; carriege return, move cursor to column 0
	mov	word [screenpos], 0
sys_gmsg_1:
	inc	ebp
	jmp	short sys_gmsg
sys_gmsg_2:
	cmp	al, LF ; 10
	jne	short sys_gmsg_ok ; 22/12/2024
	; line feed, move cursor to next row
	add	word [screenpos+2], 16
	jmp	short sys_gmsg_1
sys_gmsg_3:
	mov	esi, [screenpos]
		; hw = (cursor) row
		; si = (cursor) column
	mov	ecx, 07h ; gray (light)
	call	write_character
	add	esi, 8
	;;;
	cmp	si, 640
	jb	short sys_gmsg_5
	shr	esi, 16
	add	si, 16
	cmp	si, 480
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

; 07/12/2024 - playwav9.s
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
	;;;
	; 07/12/2024
	;mov	edi, audio_buffer
	;;;
	and	eax, eax
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
	; 31/05/2024 (BugFix)
	mov	ecx, [buffersize] ; 16 bit (48 kHZ, stereo) sample size
	;shl	ecx, 1	; byte count ; Bug !
	; 08/12/2024
	add	ecx, audio_buffer
	sub	ecx, edi
	jna	short lff8m_4
	;inc	ecx
	shr	ecx, 2
	xor	eax, eax ; fill (remain part of) buffer with zeros
	rep	stosd
lff8m_4:
	; 31/05/2024 (BugFix)
	; cf=1 ; Bug !
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
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff8s_5 ; error !

	; 01/12/2024
	mov	[count], eax
	;;;
	; 07/12/2024
	;mov	edi, audio_buffer
	;;;
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
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	lff8m2_7 ; error !

	; 01/12/2024
	mov	[count], eax
	;;;
	; 07/12/2024
	;mov	edi, audio_buffer
	;;;
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
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff8s2_7 ; error !

	; 01/12/2024
	mov	[count], eax
	;;;
	; 07/12/2024
	;mov	edi, audio_buffer
	;;;
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
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff16m_7 ; error !

	; 01/12/2024
	mov	[count], eax
	;;;
	; 07/12/2024
	;mov	edi, audio_buffer
	;;;
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
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff16s_7 ; error !

	; 01/12/2024
	mov	[count], eax
	;;;
	; 07/12/2024
	;mov	edi, audio_buffer
	;;;
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
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff16m2_7 ; error !

	; 01/12/2024
	mov	[count], eax
	;;;
	; 07/12/2024
	;mov	edi, audio_buffer
	;;;
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
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff16s2_7 ; error !

	; 01/12/2024
	mov	[count], eax
	;;;
	; 07/12/2024
	;mov	edi, audio_buffer
	;;;
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
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff24m_7 ; error !

	; 01/12/2024
	mov	[count], eax
	;;;
	; 07/12/2024
	;mov	edi, audio_buffer
	;;;
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
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff24s_7 ; error !

	; 01/12/2024
	mov	[count], eax
	;;;
	; 07/12/2024
	;mov	edi, audio_buffer
	;;;
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
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff24m2_7 ; error !

	; 01/12/2024
	mov	[count], eax
	;;;
	; 07/12/2024
	;mov	edi, audio_buffer
	;;;
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
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff24s2_7 ; error !

	; 01/12/2024
	mov	[count], eax
	;;;
	; 07/12/2024
	;mov	edi, audio_buffer
	;;;
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
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff32m_7 ; error !

	; 01/12/2024
	mov	[count], eax
	;;;
	; 07/12/2024
	;mov	edi, audio_buffer
	;;;
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
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff32s_7 ; error !

	; 01/12/2024
	mov	[count], eax
	;;;
	; 07/12/2024
	;mov	edi, audio_buffer
	;;;
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
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff32m2_7 ; error !

	; 01/12/2024
	mov	[count], eax
	;;;
	; 07/12/2024
	;mov	edi, audio_buffer
	;;;
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
	;mov	ebp, eax ; [next_val]
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
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff32s2_7 ; error !

	; 01/12/2024
	mov	[count], eax
	;;;
	; 07/12/2024
	;mov	edi, audio_buffer
	;;;
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
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff22m_7 ; error !

	; 01/12/2024
	mov	[count], eax
	;;;
	; 07/12/2024
	;mov	edi, audio_buffer
	;;;
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
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff22s_7 ; error !

	; 01/12/2024
	mov	[count], eax
	;;;
	; 07/12/2024
	;mov	edi, audio_buffer
	;;;
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
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff22m2_7 ; error !

	; 01/12/2024
	mov	[count], eax
	;;;
	; 07/12/2024
	;mov	edi, audio_buffer
	;;;
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
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff22s2_7 ; error !

	; 01/12/2024
	mov	[count], eax
	;;;
	; 07/12/2024
	;mov	edi, audio_buffer
	;;;
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
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff11m_7 ; error !

	; 01/12/2024
	mov	[count], eax
	;;;
	; 07/12/2024
	;mov	edi, audio_buffer
	;;;
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

lff11m_3:
lff11s_3:
	jmp	lff11_3	; padfill
		; (put zeros in the remain words of the buffer)

load_11khz_stereo_8_bit:
	; 18/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff11s_0		; no
	stc
	retn

lff11s_0:
	; 01/12/2024
	; edi = audio buffer address
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff11s_7 ; error !

	; 01/12/2024
	mov	[count], eax
	;;;
	; 07/12/2024
	;mov	edi, audio_buffer
	;;;
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
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff11m2_7 ; error !

	; 01/12/2024
	mov	[count], eax
	;;;
	; 07/12/2024
	;mov	edi, audio_buffer
	;;;
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
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff11s2_7 ; error !

	; 01/12/2024
	mov	[count], eax
	;;;
	; 07/12/2024
	;mov	edi, audio_buffer
	;;;
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
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff44m_7 ; error !

	; 01/12/2024
	mov	[count], eax
	;;;
	; 07/12/2024
	;mov	edi, audio_buffer
	;;;
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
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff44s_7 ; error !

	; 01/12/2024
	mov	[count], eax
	;;;
	; 07/12/2024
	;mov	edi, audio_buffer
	;;;
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
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff44m2_7 ; error !

	; 01/12/2024
	mov	[count], eax
	;;;
	; 07/12/2024
	;mov	edi, audio_buffer
	;;;
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
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [filehandle], esi, [loadsize]
	jc	short lff44s2_7 ; error !

	; 01/12/2024
	mov	[count], eax
	;;;
	; 07/12/2024
	;mov	edi, audio_buffer
	;;;
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
; --------------------------------------------------------

; 07/12/2024
; Ref: TRDOS 386 v2.0.9, trdosk8.s (18/09/2024)
;		'sysaudio' system call (23/08/2024)
; 18/11/2024
; Ref: TRDOS 386 v2.0.9, audio.s, Erdogan Tan, 06/06/2024

ac97_stop: 
	; 18/11/2024
	mov	byte [stopped], 2
	; 07/12/2024
	sys	_audio, 0700h
	retn

ac97_pause:
	; 18/11/2024
	mov	byte [stopped], 1 ; paused
	; 07/12/2024
	sys	_audio, 0500h
	retn

ac97_play: ; continue to play (after pause)
	; 18/11/2024
	mov	byte [stopped], 0
	; 07/12/2024	
	sys	_audio, 0600h
	retn
	
; --------------------------------------------------------
; 14/11/2024 - Erdogan Tan
; --------------------------------------------------------

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
	; 07/02/2024
	;mov	al, [volume]
	;call	SetmasterVolume
	mov	byte [stopped], 0
	call	move_to_beginning
	;jmp	PlayWav
	; 07/12/2024
	jmp	RePlayWav

c4ue_chk_s:
	cmp	al, 'S'	; stop
	jne	short c4ue_chk_fb
	cmp	byte [stopped], 0
	ja	c4ue_cpt ; Already stopped/paused
	call	ac97_stop
	; 19/11/2024
	mov	byte [tLO], 0
	; 21/11/2024
	mov	byte [tLP], '0'
	jmp	c4ue_cpt

	; 01/12/2024
	; 18/11/2024
c4ue_ok:
	retn

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
	mov	byte [wleds], 0
	call 	write_ac97_pci_dev_info
	;;;
	;24/12/2024 (wave lighting points option)
	mov	byte [p_mode], 1
	;;;
	;mov	dh, 24
	;mov	dl, 79
	;call	setCursorPosition
	; 21/12/2024
	jmp	short c4ue_cpt
c4ue_chk_cr:
	;;;
	; 24/12/2024 (wave lighting points option)
	mov	ah, [wleds]
	cmp	al, 'G'
	je	short c4ue_g
;	;;;
;	; 26/12/2024
;	cmp	al, 'T'
;	jne	short c4ue_chk_cr_@
;	inc	byte [tcolor]
;	and 	byte [tcolor], 0Fh
;	jnz	short c4ue_cpt
;	inc	byte [tcolor]
;	jmp	short c4ue_cpt
;c4ue_chk_cr_@:
;	;;;
	; 19/11/2024
	cmp	al, 0Dh ; ENTER/CR key
	jne	short c4ue_cpt
	;inc	byte [wleds]
	;jnz	short c4ue_cpt
	;inc	byte [wleds]
	;;;
	; 24/12/2024
	; 22/12/2024 (faster method)
	; (UpdateWaveLeds procedure turns off previously
	;  lighting wave leds only)
	;call	reset_wave_leds ; prepare all leds as turned off
	;;;
	; 23/11/2024
	xor	ebx, ebx
	; 24/12/2024 (wave lighting points option)
	mov	[p_mode], bl ; 0
	;
	;mov	bl, [wleds]
	mov	bl, ah ; 24/12/2024
	inc	bl
	and	bl, 0Fh
	jnz	short c4ue_sc
	inc	ebx
c4ue_sc:
	mov	[wleds], bl
	shr	bl, 1
	mov	al, [ebx+colors]
	; 24/12/2024
	mov	[ccolor], al
	jc	short c4ue_g_@
	; 24/12/2024
	call	reset_wave_leds ; prepare all leds as turned off
	jmp	short c4ue_cpt
	; 24/12/2024
c4ue_g:
	or	ah, ah	; byte [wleds]
	jnz	short c4ue_g_@
	inc	byte [wleds]	; force wave lighting ('G' key)
c4ue_g_@:
	; 24/12/2024 (wave lighting points option)
	mov	byte [p_mode], 1
	call	clear_window
	;;;
c4ue_cpt:
	; 24/12/2024
	; 18/11/2024
	pop	ecx ; *
	;;;
	; 24/12/2024 (skip wave lighting if data is not loaded yet)
	cmp	byte [SRB], 0
	ja	short c4ue_vb_ok
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
	cmp	byte [wleds], 0
	jna	short c4ue_vb_ok

	; 24/12/2024 (wave points mode)
	cmp	byte [p_mode], 0
	ja	short c4ue_uwp

	call	UpdateWaveLeds

c4ue_vb_ok:
	retn

	; 22/12/2024
c4ue_uwp:
	;call	UpdateWavePoints
	;retn

; --------------------------------------------------------
; 24/12/2024 - Erdogan Tan
; --------------------------------------------------------

	; 26/12/2024
	; 24/12/2024
UpdateWavePoints:
	mov	esi, prev_points
	cmp	dword [esi], 0
	jz	short lights_off_ok
	mov	ecx, 640
light_off:
	lodsd
	; eax = wave point (lighting point) address
	mov	byte [eax], 0 ; black point (light off)
	loop	light_off	
lights_off_ok:
	mov	dl, [half_buffer]
	cmp	[pbuf_s], dl
	jne	short lights_on_2
	mov	ebx, [wpoints_dif]
	mov	esi, [pbuf_o]
	mov	ecx, [buffersize] ; bytes
	sub	ecx, ebx ; sub ecx, [wpoints_dif]
	add	esi, ebx
	jc	short lights_on_1
	cmp	esi, ecx
	jna	short lights_on_3
lights_on_1:
	mov	esi, ecx
	jmp	short lights_on_3

lights_on_2:
	mov	[pbuf_s], dl
	xor	esi, esi ; 0
lights_on_3:
	mov	[pbuf_o], esi
	;
	add	esi, audio_buffer
	mov	ecx, 640
	mov	ebp, ecx
	; 26/12/2024
	mov	edi, prev_points
	mov	ebx, [graphstart] ; start (top) line
lights_on_4:
	xor	eax, eax ; 0
	lodsw	; left
	add	ah, 80h
	mov	edx, eax
	lodsw	; right
	;add	ax, dx
	add	ah, 80h
	;shr	eax, 9	; 128 volume levels
	add	eax, edx
	;shr	eax, 10	; (L+R/2) & 128 volume levels
	shr	eax, 9	; (L+R/2) & 256 volume levels
	mul	ebp	; * 640 (row)
	add	eax, ebx ; + column
	mov	dl, [ccolor]
	mov	[eax], dl ; pixel (light on) color
	stosd		; save light on addr in prev_points
	inc	ebx
	loop	lights_on_4
	retn

; --------------------------------------------------------
; 19/05/2024 - (playwav4.asm) ich_wav4.asm
; --------------------------------------------------------

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
	; 15/11/2024 (QEMU)
	; 07/12/2024
	call	SetMasterVolume
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

	; 22/12/2024
	; 21/12/2024
	; simulate cursor position in VGA (VESA VBE) mode
	; ! for 640*480, 256 colors (1 byte/pixel) !
setCursorPosition:
	; dh = Row
	; dl = Column
	
	xor	eax, eax
	mov	al, 14	; row height is 14 pixels (8*14)
	mul	dh
	add	ax, 7	; top margin
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
	mov	dh, 32
	mov	dl, 42
	call	setCursorPosition

	pop	eax ; *
	xor	ah, ah
	mov	ebp, 2
	call	PrintNumber
	
	;mov	dh, 24
	; 21/12/2024 (640*480)
	mov	dh, 32
	mov	dl, 45
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
	mov	dh, 32
	mov	dl, 33
	call	setCursorPosition

	pop	eax ; *
	xor	ah, ah
	mov	ebp, 2
	call	PrintNumber
	
	;mov	dh, 24
	; 21/12/2024 (640*480)
	mov	dh, 32
	mov	dl, 36
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
	mov	dh, 8
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
_fnl_chk:
	; 26/12/2024 (file name length limit -display-)
	;mov	ebx, 12
	mov	ebx, 17 ; ????????.wav?????
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
	mov	dh, 9
	mov	dl, 23
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
	mov	dh, 8
	mov	dl, 57
	call	setCursorPosition
	mov	ax, [WAVE_BitsPerSample]
	mov	bp, 2
	call	PrintNumber

	;; Print Channel Number
	;mov	dh, 10
	; 21/12/2024 (640*480 graphics display)
	mov	dh, 9
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
	;mov	dh, 24
	; 21/12/2024 (640*480)
	mov	dh, 32
	mov	dl, 75
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

	; 22/12/2024
	push	eax
	; clear previous character pixels
	mov	edi, fillblock
	sys	_video, 020Fh, 0, 8001h
	pop	eax

	shl	eax, 4 ; 8*16 pixel user font
	mov	edi, fontbuff2 ; start of user font data
	add	edi, eax

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

	sys	_video, 020Fh, [wcolor], 8001h

	retn

; --------------------------------------------------------

	; 22/12/2024
	; 21/12/2024
	; (write chars in VESA VBE graphics mode)
	; 14/11/2024
	; (Ref: player.asm, Matan Alfasi, 2017)
	; (Modification: Erdogan Tan, 14/11/2024)

	;PROGRESSBAR_ROW equ 23
	; 21/12/2024 (640*480)
	PROGRESSBAR_ROW equ 31

UpdateProgressBar:
	call	SetProgressTime	; 14/11/2024

	; 01/12/2024 (32bit registers)
	mov	eax, [ProgressTime]
UpdateProgressBar@:
	mov	edx, 80
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
	; 21/12/2024
	mov	ebp, 80
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

	; 25/12/2024
	; 22/12/2024 (VESA VBE mode graphics) 
	; (640*480, 256 colors)
clear_window:
	mov	edi, [LFB_ADDR]
	;add	edi, (13*80*8*14)
	; 25/12/2024
	add	edi, 164*640
	sub	eax, eax
	;mov	ecx, (16*640*14)/4 ; 16 rows
	mov	ecx, 64*640 ; 256 volume level points
	rep	stosd
	; 24/12/2024
	mov	[prev_points], eax ; 0
	;
	retn

; --------------------------------------------------------

	; 22/12/2024
	; 21/12/2024
	; (simulate wave leds in graphics mode)
	; (640*480, 256 colors)
reset_wave_leds:
	; 22/12/2024
	mov	dword [prev_leds], 0
	;
	mov	ebp, 16*80 ; 80 columns with 16 levels
	mov	esi, wleds_addr
next_led:
	lodsd
	mov	edi, eax
	mov	edx, 14 ; 14 lines (8*14 pixel font)
	mov	ebx, fontbuff2+(254*16) ; char = 254
led_line:
	mov	ah, [ebx]
	mov	ecx, 8 ; 8 pixels (8*16 pixel font)
next_pixel:
	shl	ah, 1
	jnc	short skip_this
	mov	al, 8 ; gray
	stosb
	dec	ecx
	jnz	short next_pixel
	jmp	short next_line
skip_this:
	mov	al, 0 ; black
	stosb
	dec	ecx
	jnz	short next_pixel
next_line:
	dec	edx
	jnz	short next_line_@
	dec	ebp
	jnz	short next_led
	;clc	; 25/12/2024
	retn
next_line_@:
	; 22/12/2024
	add	edi, 640-8 ; next line
	inc	ebx
	jmp	short led_line	

; --------------------------------------------------------

	; 22/12/2024 (graphics mode)
	; 09/12/2024
	; 19/11/2024
UpdateWaveLeds:
	; 23/11/2024
	;call	reset_wave_leds
	; 22/12/2024 (faster method, 80 against 80*16)
	; turn off previously lighting wave leds at first
	;;;
	mov	esi, prev_leds
	cmp	dword [esi], 0
	jz	short UpdateWaveLeds_ok
	mov	ecx, 80
turn_off_led:
	lodsd
	mov	edi, eax
	; edi = wave led address
	mov	ebp, 14
	mov	ebx, fontbuff2+(254*16) ; char = 254
	xor	edx, edx
	mov	al, 8 ; gray (dark)
toffl_next_line:
	;;mov	edx, 8 ; 8 pixels (8*14 pixel font)
	;mov	dl, 8
	mov	dl, al ; 8
	mov	ah, [ebx]
toffl_next_pixel:
	shl	ah, 1
	jnc	short toffl_skip_this
	stosb
toffl_next_pixel_@:
	dec	edx
	jnz	short toffl_next_pixel
	dec	ebp
	jz	short toffl_next_led
	add	edi, 640-8 ; next line
	inc	ebx
	jmp	short toffl_next_line
toffl_skip_this:
	inc	edi
	jmp	short toffl_next_pixel_@
toffl_next_led:
	loop	turn_off_led
UpdateWaveLeds_ok:
	;;;
	; 09/12/2024
	;jmp	short turn_on_leds

; --------------------------------------------------------

	; 21/12/2024 (VESA VBE Mode, 640*480, 256 colors)
	; 09/12/2024
	; 01/12/2024 (TRDOS 386, 32bit registers, flat memory)
	; 23/11/2024 (Retro DOS, 16bit registers, segmented)
	; 21/11/2024, 22/11/2024
	; 19/11/2024
turn_on_leds:
	; 09/12/2024
	; 07/12/2024
	mov	dl, [half_buffer]
tol_@:
	; 07/12/2024
	cmp	[pbuf_s], dl
	jne	short tol_ns_buf
	mov	ebx, [wleds_dif]
	mov	esi, [pbuf_o]
	mov	ecx, [buffersize] ; bytes
	sub	ecx, ebx ; sub ecx, [wleds_dif]
	add	esi, ebx
	jc	short tol_o_@
	cmp	esi, ecx
	jna	short tol_s_buf
tol_o_@:
	mov	esi, ecx
	jmp	short tol_s_buf

tol_ns_buf:
	mov	[pbuf_s], dl
	xor	esi, esi ; 0
tol_s_buf:
	mov	[pbuf_o], esi

tol_buf_@:
	; 07/12/2024
	add	esi, audio_buffer
	mov	ecx, 80
	;xor	eax, eax ; 0
	mov	ebx, wleds_addr
	; 22/12/2024
	mov	edi, prev_leds
tol_fill_c:
	xor	eax, eax ; 0 ; 22/12/2024
	lodsw	; left
	add	ah, 80h	; 24/12/2024
	mov	edx, eax
	lodsw	; right
	;add	ax, dx
	add	ah, 80h
	;; 21/12/2024 (16 volume levels)
	;shr	eax, 12
	; 24/12/2024
	add	eax, edx
	shr	eax, 13	; (L+R/2) & 16 volume levels

	push	ebx ; *
	; 01/12/2024
	shl	eax, 2
	add	ebx, eax
	; 01/12/2024 (32bit address)
	;mov	edi, [ebx]
	; 22/12/2024
	mov	eax, [ebx]
	stosd
	push	edi ; **
	mov	edi, eax
	;;;
	; 21/12/2024
	; (simulate wave leds in graphics mode)
	; (640*480, 256 colors)
turn_on_led:
	; edi = wave led address
	mov	ebp, 14
	mov	ebx, fontbuff2+(254*16) ; char = 254
	mov	al, [ccolor]
tol_next_line:
	mov	edx, 8 ; 8 pixels (8*14 pixel font)
	mov	ah, [ebx]
tol_next_pixel:
	shl	ah, 1
	jnc	short tol_skip_this
	stosb
tol_next_pixel_@:
	dec	edx
	jnz	short tol_next_pixel
	dec	ebp
	jz	short tol_next_led
	; 22/12/2024
	add	edi, 640-8 ; next line
	inc	ebx
	jmp	short tol_next_line
tol_skip_this:
	inc	edi
	jmp	short tol_next_pixel_@
tol_next_led:
	; 22/12/2024
	pop	edi ; **
	;;;
	pop	ebx ; *
	add	ebx, 16*4
	loop	tol_fill_c

	retn

; -------------------------------------------------------------

; -------------------------------------------------------------
; ac97.inc (11/11/2023)
; -------------------------------------------------------------

; special characters
LF      EQU 10
CR      EQU 13

; PCI stuff

; Intel ICH2 equates. It is assumed that ICH0 and plain ole ICH are compatible.

INTEL_VID       equ     8086h           ; Intel's PCI vendor ID
; 03/11/2023 - Erdogan Tan (Ref: MenuetOS AC97 WAV Player source code, 2004)
SIS_VID		equ	1039h
NVIDIA_VID	equ	10DEh	 ; Ref: MPXPLAY/SBEMU/KOLIBRIOS AC97 source c.
AMD_VID		equ	1022h

ICH_DID         equ     2415h           ; ICH device ID
ICH0_DID        equ     2425h           ; ICH0
ICH2_DID        equ     2445h           ; ICH2 I think there are more ICHes.
                                        ; they all should be compatible.

; 17/02/2017 (Erdogan Tan, ref: ALSA Device IDs, ALSA project)
ICH3_DID	equ     2485h           ; ICH3
ICH4_DID        equ     24C5h           ; ICH4
ICH5_DID	equ     24D5h           ; ICH5
ICH6_DID	equ     266Eh           ; ICH6
ESB6300_DID	equ     25A6h           ; 6300ESB
ESB631X_DID	equ     2698h           ; 631XESB
ICH7_DID	equ	27DEh		; ICH7
; 03/11/2023 - Erdogan Tan (Ref: MenuetOS AC97 WAV Player source code, 2004)
MX82440_DID	equ	7195h
SI7012_DID	equ	7012h
NFORCE_DID	equ	01B1h
NFORCE2_DID	equ	006Ah
AMD8111_DID	equ	746Dh
AMD768_DID	equ	7445h
; 03/11/2023 - Erdogan Tan - Ref: MPXPLAY/SBEMU/KOLIBRIOS AC97 source code
CK804_DID	equ	0059h
MCP04_DID	equ	003Ah
CK8_DID		equ	008Ah
NFORCE3_DID	equ	00DAh
CK8S_DID	equ	00EAh

; -------------------------------------------------------------

; 22/12/2024
align 4

; 13/11/2024
; ('<<' to 'shl' conversion for FASM)
;
; 29/05/2024 (TRDOS 386)
; 17/02/2017
; Valid ICH device IDs

valid_ids:
	;dd (ICH_DID shl 16) + INTEL_VID	; 8086h:2415h
	dd (ICH_DID << 16) + INTEL_VID		; 8086h:2415h
	dd (ICH0_DID << 16) + INTEL_VID		; 8086h:2425h
	dd (ICH2_DID << 16) + INTEL_VID		; 8086h:2445h
	dd (ICH3_DID << 16) + INTEL_VID		; 8086h:2485h
	dd (ICH4_DID << 16) + INTEL_VID		; 8086h:24C5h
	dd (ICH5_DID << 16) + INTEL_VID		; 8086h:24D5h
	dd (ICH6_DID << 16) + INTEL_VID		; 8086h:266Eh
	dd (ESB6300_DID << 16) + INTEL_VID	; 8086h:25A6h
	dd (ESB631X_DID << 16) + INTEL_VID	; 8086h:2698h
	dd (ICH7_DID << 16) + INTEL_VID		; 8086h:27DEh
	; 03/11/2023 - Erdogan Tan
	dd (MX82440_DID << 16) + INTEL_VID	; 8086h:7195h
	dd (SI7012_DID << 16)  + SIS_VID	; 1039h:7012h
	dd (NFORCE_DID << 16)  + NVIDIA_VID	; 10DEh:01B1h
	dd (NFORCE2_DID << 16) + NVIDIA_VID	; 10DEh:006Ah
	dd (AMD8111_DID << 16) + AMD_VID	; 1022h:746Dh
	dd (AMD768_DID << 16)  + AMD_VID	; 1022h:7445h
	dd (CK804_DID << 16) + NVIDIA_VID	; 10DEh:0059h
	dd (MCP04_DID << 16) + NVIDIA_VID	; 10DEh:003Ah
	dd (CK8_DID << 16) + NVIDIA_VID		; 1022h:008Ah
	dd (NFORCE3_DID << 16) + NVIDIA_VID	; 10DEh:00DAh
	dd (CK8S_DID << 16) + NVIDIA_VID	; 10DEh:00EAh

valid_id_count equ (($ - valid_ids)>>2)	; 05/11/2023
; 13/11/2024
;valid_id_count = ($ - valid_ids) shr 2	; 05/11/2023

	dd 0

Credits:
	db 'VGA WAV Player for TRDOS 386 by Erdogan Tan. '
	db 'December 2024.',10,13,0
	db '27/12/2024', 10,13
; 15/11/2024
reset:
	db 0

msgAudioCardInfo:
	db 'for Intel AC97 (ICH) Audio Controller.', 10,13,0

	; 25/12/2024
msg_usage:
	db 'usage: VGAPLAY <FileName1> <FileName2> <...>',10,13,0

noDevMsg:
	db 'Error: Unable to find AC97 audio device!'
	db 10,13,0

noFileErrMsg:
	db 'Error: file not found.',10,13,0

; 07/12/2024
trdos386_err_msg:
	db 'TRDOS 386 System call error !',10,13,0

; 29/05/2024
; 11/11/2023
msg_init_err:
	db CR, LF
	db 'AC97 Controller/Codec initialization error !'
	db CR, LF, 0 ; 07/12/2024

; 25/11/2023
msg_no_vra:
	db 10,13
	db 'No VRA support ! Only 48 kHZ sample rate supported !'
	db 10,13,0

; 19/11/2024
; 03/06/2017
hex_chars:
	db '0123456789ABCDEF', 0
msgAC97Info:
	db 0Dh, 0Ah
	db ' AC97 Audio Controller & Codec Info', 0Dh, 0Ah 
	db ' Vendor ID: '
msgVendorId:
	db '0000h Device ID: '
msgDevId:
	db '0000h', 0Dh, 0Ah
	db ' Bus: '
msgBusNo:
	db '00h Device: '
msgDevNo:
	db '00h Function: '
msgFncNo:
	db '00h'
	db 0Dh, 0Ah
	db ' NAMBAR: '
msgNamBar:
	db '0000h  '
	db 'NABMBAR: '
msgNabmBar:
	db '0000h  IRQ: '
msgIRQ:
	dw 3030h
	db 0Dh, 0Ah, 0
; 25/11/2023
msgVRAheader:
	db ' VRA support: '
	db 0	
msgVRAyes:
	db 'YES', 0Dh, 0Ah, 0
msgVRAno:
	db 'NO ', 0Dh, 0Ah
	db ' (Interpolated sample rate playing method)'
	db 0Dh, 0Ah, 0

align 4

; -------------------------------------------------------------

	; 21/12/2024
SplashScreen:
	db  221, 219, 222, "                                                                          ", 221, 219, 222
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
	db  221, 219, 222, "                                                                          ", 221, 219, 222
	db  221, 219, 222, "                                WELCOME TO                                ", 221, 219, 222
	db  221, 219, 222, "                                DOS PLAYER                                ", 221, 219, 222
	db  221, 219, 222, "                                                                          ", 221, 219, 222
	db  221, 219, 222, "                                                                          ", 221, 219, 222
	db  221, 219, 222, "                                                                          ", 221, 219, 222
	db  221, 219, 222, "                                                                          ", 221, 219, 222
	db  221, 219, 222, "                                                                          ", 221, 219, 222
	db  221, 219, 222, "                                                                          ", 221, 219, 222
	db  221, 219, 222, "                                                                          ", 221, 219, 222
	db  221, 219, 222, "                                                                          ", 221, 219, 222
	db  221, 219, 222, "                                                                          ", 221, 219, 222
	db  221, 219, 222, "                                                                          ", 221, 219, 222
	db 0

; -------------------------------------------------------------

	; 25/12/2024
PlayingScreen:
	db  34 dup(219), " DOS Player ", 34 dup(219)
	db  201, 78 dup(205), 187
	db  186, 33 dup(32), " User Guide ", 33 dup(32), 186
	db  186, 6  dup(32), "<Space>         Play/Pause    ", 4 dup(32), "<N>/<P>         Next/Previous", 9 dup(32), 186
	db  186, 6  dup(32), "<S>             Stop          ", 4 dup(32), "<Enter>/<G>     Wave Lighting", 9 dup(32), 186
	db  186, 6  dup(32), "<F>             Forwards      ", 4 dup(32), "<+>/<->         Inc/Dec Volume", 8 dup(32), 186
	db  186, 6  dup(32), "<B>             Backwards     ", 4 dup(32), "<Q>             Quit Program ", 9 dup(32), 186
	db  204, 78 dup(205), 185
	db  186, 6  dup(32), "File Name :                   ", 4 dup(32), "Bit-Rate  :     0  Bits      ", 9 dup(32), 186
	db  186, 6  dup(32), "Frequency :     0     Hz      ", 4 dup(32), "#-Channels:     0            ", 9 dup(32), 186
	db  200, 78 dup(205), 188
	db  80 dup(32)
improper_samplerate_txt:
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
	db 0

; 25/12/2024
; 28/11/2024
IsInSplash:
	db 1

SplashFileName:
	db "SPLASH.WAV", 0

; -------------------------------------------------------------

	; 22/12/2024
fillblock:
	times 14 db 0FFh
	dw 0

; -------------------------------------------------------------

; 23/11/2024
colors:
	db 0Fh, 0Bh, 0Ah, 0Ch, 0Eh, 09h, 0Dh, 0Fh
	; white, cyan, green, red, yellow, blue, magenta
ccolor:	db 0Bh	; cyan

EOF: 

; -------------------------------------------------------------

bss:

ABSOLUTE bss

alignb 4

; 21/12/2024
fontbuff1:
	resb 256*14 ; 8x14 font data (from system)
fontbuff2:
	resb 256*16 ; 8x16 font data (modif. from 8x14)

; 11/12/2024
wleds_addr:
	resd 80*16 ; 32 bit addrs, 80 leds, 16 volume levels
; 22/12/2024
prev_leds:
	resd 80	; previous lighting leds

; 24/12/2024
wpoints_dif:	; wave lighting points factor (differential) 
	resd 1	; required bytes for 1/18 second wave lighting
graphstart:
	resd 1	; start (top) line/row for wave lighting points 	 

LFB_ADDR:
	resd 1
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

; 24/12/2024
prev_points:
	resd 640 ; previous wave points (which are lighting)	

; 18/11/2024
stopped:
	resb 1
tLO:	resb 1
; 21/11/2024
tLP:	resb 1
; 19/11/2024
wleds:	resb 1
wleds_dif:
	resd 1
pbuf_o:	resd 1
; 07/12/2024
pbuf_s:	resb 1

; 07/12/2024
; 24/11/2024
half_buffer:
	resb 1	; dma half buffer 1 or 2 (0 or 1)

; 30/05/2024
VRA:	resb 1	; Variable Rate Audio Support Status

; 24/12/2024
p_mode: resb 1	; point mode (as alternative to LED mode)

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

; 15/11/2024
cursortype:
	resw 1
flags:	resb 1
; 06/11/2023
ac97_int_ln_reg:
	resb 1
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

; 08/11/2023
; 07/11/2023
fbs_shift:
	resb 1
; 07/12/2024
SRB:	resb 1

; 12/11/2016 - Erdogan Tan
bus_dev_fn:
	resd 1
dev_vendor:
	resd 1

; 17/02/2017
; NAMBAR:  Native Audio Mixer Base Address Register
;    (ICH, Audio D31:F5, PCI Config Space) Address offset: 10h-13h
; NABMBAR: Native Audio Bus Mastering Base Address register
;    (ICH, Audio D31:F5, PCI Config Space) Address offset: 14h-17h
NAMBAR:	resw 1	; BAR for mixer
NABMBAR:
	resw 1	; BAR for bus master regs

; 15/11/2024
loadfromwavfile:
	resd 1	; 'loadfromfile' or load+conversion proc address
loadsize:
	resd 1	; (.wav file) read count (bytes) per one time
buffersize:
	resd 1	; 16 bit samples (not bytes)
		
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
; 14/11/2024	
bss_end:

; 02/12/2024
alignb 4096

; 07/12/2024
; 26/11/2023
audio_buffer:
	resb 65536  ; DMA Buffer Size / 2	

; 01/12/2024
; 26/11/2023
temp_buffer:
	resb 65536  ;  rb BUFFERSIZE
