; ****************************************************************************
; twavplay.asm (for TRDOS 386) -twavplay3.s-
; ----------------------------------------------------------------------------
; TWAVPLAY.PRG ! AC'97 & SB16 WAV PLAYER & VGA DEMO program by Erdogan TAN
;
; 09/02/2025
;
; [ Last Modification: 10/02/2025 ]
;
; Assembler: NASM 2.15
; ----------------------------------------------------------------------------
;	   nasm  twavplay.s -l twavplay.txt -o TWAVPLAY.PRG
; ****************************************************************************

; VGA Video Mode 12h, 640*480 16 colors, stereo wave scope/graphics

; ----------------------------------------------------------------------------
; TuneLoop method for AC97 - Interrupt/Callback (syscalbac) method for SB16
; ----------------------------------------------------------------------------

; 09/02/2025
; Code reference:
;	twavplay.asm (TWAVPLAY.COM, 09/02/2025)
;	ac97play.s (AC97PLAY.PRG, 05/02/2025

; ----------------------------------------------------------------------------

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

; ----------------------------------------------------------------------------

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

; ----------------------------------------------------------------------------

%macro	SbOut	1
%%Wait:
	;in	al, dx
	mov	ah, 0
	int	34h
	or	al, al
	js	short %%Wait
	mov	al, %1
	;out	dx, al
	mov	ah, 1
	int	34h
%endmacro

; ----------------------------------------------------------------------------

;BUFFERSIZE equ 65520 ; AC97
; 07/02/2025
;BUFFERSIZE equ 33680 ; AC97
; 08/02/2025	
;BUFFERSIZE equ 10548 ; AC97 ; 48kHZ 16bit stereo audio block (18.2 block/s) 

ENDOFFILE equ 1	; flag for knowing end of file

;LOADSIZE equ 16384 ; SB16
;dma_buffer_size equ 32768  ; SB16
; 08/02/2025
;LOADSIZE equ 10560 ; SB16 ; 48kHZ 16bit stereo audio block (18.2 block/s)

; ----------------------------------------------------------------------------
; Reference:
; ----------
; Tiny Player v2.11 by Carlos Hasan.
;	June, 1994.

;=============================================================================
;	code
;=============================================================================

[BITS 32] ; 32-bit intructions

[ORG 0]

	; 09/02/2025
Start:
	; Prints the Credits Text.
	sys	_msg, Credits, 255, 0Bh

	; Clear BSS (uninitialized data) area
	mov	ecx, (bss_end - bss_start) / 4
	mov	edi, bss_start
	xor	eax, eax
	rep	stosw

	; Detect (& Enable) AC'97 or SB16 Audio Device
	call	detect_audio_device
	jnc     short GetFileName

_dev_not_ready:
	; couldn't find the audio device!
	sys	_msg, noDevMsg, 255, 0Fh
        jmp     Exit

; ----------------------------------------------------------------------------

GetFileName:
	; (TRDOS 386 -Retro UNIX 386- argument transfer method)
	; (stack: argc,argv0addr,argv1addr,argv2addr ..
	;			.. argv0text, argv1text ..) 
	; ---- argc, argv[] ----
	mov	esi, esp
	lodsd
	cmp	eax, 2 ; two arguments 
	jnb	short _x
	jmp	pmsg_usage

_x:
	lodsd	; skip program (PRG) file name
	mov	esi, [esi] ; WAV file name 

	mov	edi, wav_file_name
	xor	ecx, ecx ; 0
ScanName:       
	lodsb

	cmp	al, 0Dh	; CR
	jna	short a_4
_y:
	cmp	al, 20h
	je	short ScanName	; scan start of name.
	stosb
	mov	ah, 0FFh
a_0:	
	inc	ah
a_1:
	inc	ecx
	lodsb
	stosb
	cmp	al, '.'
	je	short a_0
	cmp	al, 20h
	jna	short a_3
	and	ah, ah
	jz	short a_2

	cmp	al, '\'
	jne	short a_2
	mov	ah, 0
a_2:
	cmp	cl, 75	; 64+8+'.'+3 -> offset 75 is the last chr
	jb	short a_1
	jmp	short a_4
a_3:
	dec	edi
	or	ah, ah		; if period NOT found,
	jnz	short a_4 	; then add a .WAV extension.
SetExt:
	mov	dword [edi], '.WAV' ; ! 64+12 is DOS limit
				    ;   but writing +4 must not
				    ;   destroy the following data
				; so, 80 bytes path + 0 is possible here
	add	edi, 4
a_4:	
	mov	byte [edi], 0
	
	cmp	byte [wav_file_name], 20h
	ja	short open_wav_file

; ----------------------------------------------------------------------------

pmsg_usage: 
	sys	_msg, msg_usage, 255, 0Fh

Exit:
	xor	ebx, ebx ; exit code = 0 ; not necessary
	sys	_exit
halt:
	jmp	short halt

; ----------------------------------------------------------------------------

open_wav_file:
        ; open existing file
	mov	edx, wav_file_name
        call    openFile ; no error? ok.
        jnc     short _z

	; file not found!
	sys	_msg, noFileErrMsg, 255, 0Ch

	jmp	short Exit

not_valid_wav:
	; not a proper/valid wav file !
	sys	_msg, not_valid_wavf, 255, 0Fh

	jmp	short Exit

_z:
       	call    getWAVParameters
	jc	short not_valid_wav

	mov	bl, 4
	mov	cl, [WAVE_BlockAlign]
	sub	bl, cl	; = 0 for 16 bit stereo
			; = 2 for 8 bit stereo or 16 bit mono
			; = 3 for 8 bit mono

	shr	bl, 1	; 0 --> 0, 2 --> 1, 3 --> 1
	adc	bl, 0	; 3 --> 1 --> 2
	mov	[fbs_shift], bl	; = 2 mono and 8 bit
				; = 0 stereo and 16 bit
				; = 1 mono or 8 bit
	xor	eax, eax

	cmp	byte [audio_hardware], 1 ; SB16 ?
	jne	short _r
				; no, skip [g_samples] calculation

	; count of audio samples for graphics data
	inc	ah
	; eax = 256
	shr	cl, 1
	; 0 = 8 bit mono, 1 = 16 bit mono or 8 bit stereo
	; 2 = 16 bit stereo  
	shl	eax, cl
	mov	[g_samples], eax ; 256 .. 1024

_r:
	; calculate 18.2 block/s buffer size for proper wave scope
	mov	ax, [WAVE_SampleRate]
	xor	edx, edx
	mov	dl, 4*10
	mul	edx
	xor	ecx, ecx
	mov	cl, 182
	div	ecx
	mov	cl, bl	; 0 = stereo & 16bit
			; 1 = mono 16bit or stereo 8bit
			; 2 = mono & 8bit
	and	al, ~3 ; NOT 3
	shr	eax, cl
		; AX = 
		; 10548 bytes for 48kHZ 16bit stereo
		; 9692 bytes for 44kHZ 16bit stereo
		; 7032 bytes for 32kHZ 16bit stereo
		; 5272 bytes for 24kHz 16bit stereo
		; 4844 bytes for 22kHZ 16bit stereo 
		; 3516 bytes for 16kHZ 16bit stereo
		; 2636 bytes for 12kHZ 16bit stereo
		; 2420 bytes for 11kHZ 16bit stereo
		; 1756 bytes for 8kHZ 16bit stereo

	mov	[loadsize], eax
	
	cmp	byte [audio_hardware], 1 ; SB16 ?
	je	short _t		; yes	

	; AC97 codec plays 16 bit stereo PCM data only
	shl	eax, cl
	; count of 16 bit samples
	shr	eax, 1
_t:
	mov	[buffersize], eax ; (if audio hardware supports vra)	
		 
; ----------------------------------------------------------------------------

	; 10/02/2025
	; 20/10/2017 - playwav.s

allocate_dma_buffer:
	cmp	byte [audio_hardware], 1
	jne	short allocate_ac97_buffers

	; SB16

	dmabufsize equ 24576 ; rounded up to page border (21120 will be use)

	; DIRECT MEMORY ACCESS (for Audio DMA)
	; ebx = DMA buffer address (virtual, user)
	; ecx = buffer size (in bytes)
	; edx = upper limit = 16MB

	_16MB	equ 1024*1024*16

	sys	_alloc, dma_buffer, dmabufsize, _16MB 
	jc	short syscall_err

	mov	[DMA_phy_buff], eax	; physical address
	     				; of the buffer
					; (which is needed
					; for DMA controller)

	jmp	short audio_hardware_init

; ----------------------------------------------------------------------------

	; 10/02/2025
	; 05/02/2025 - ac97play.s

allocate_ac97_buffers:

	; AC97

	sys	_alloc, BDL_BUFFER, 33*4096, 0	; no upper limit
	jc	short syscall_err

	mov	[_bdl_buffer], eax ; BDL_BUFFER physical address

; ----------------------------------------------------------------------------

audio_hardware_init:

	call	audio_system_init
	;jc	short Exit
	jnc	short write_info
	jmp	Exit

; ----------------------------------------------------------------------------

syscall_err:
	sys	_msg, trdos386_err_msg, 255, 0Eh
	jmp	Exit

; ----------------------------------------------------------------------------

write_info:
	call	write_audio_dev_info

	call	write_wav_file_info

	sys	_msg, msgPressAKey, 255, 07h

	xor	ah, ah
	int	32h	; TRDOS 386 keyboard interrupt
			; getchar (wait for keystroke)

	cmp	al, 1Bh ; ESC
	jne	short _continue
	jmp	Exit

_continue:
	;call	audio_system_init
	;jc	short Exit

; ----------------------------------------------------------------------------

PlayNow: 
	mov	ecx, 256
	xor	ebx, ebx
	mov	edi, RowOfs
MakeOfs:
	mov	eax, ebx
	shl	eax, 7 ; * 128
	mov	al, 80
	mul	ah
	stosw
	inc	ebx
	loop	MakeOfs

; ----------------------------------------------------------------------------

	; DIRECT VGA MEMORY ACCESS
	; bl = 0, bh = 5
	; Direct access/map to VGA memory (0A0000h)

	sys	_video, 0500h
	cmp	eax, 0A0000h
	jne	short syscall_err

; ----------------------------------------------------------------------------

	;;;;
setgraphmode:
	; set VGA 640x480x16 graphics mode
	mov	ax, 12h
	int	31h	; TRDOS 386 Video Interrupt
			; Set video mode
	mov	dx, 3C0h
	xor	al, al
setgraphmodel0:
	;out	dx, al
	mov	ah, 1	; outb
	int	34h	; TRDOS 386 IOCTL Interrupt
	;out	dx, al
	;mov	ah, 1	; outb
	int	34h
	inc	al
	cmp	al, 10h
	jb	short setgraphmodel0
	mov	al, 20h
	;out	dx, al
	;mov	ah, 1	; outb
	int	34h
	;;;;

; ----------------------------------------------------------------------------
	
	;mov	esi, LOGO_ADDRESS
	call	putlbm
;	jnc	short loadlbm_ok
;
;loadlbm_err:
;	call	settextmode
;	sys	_msg, LOGO_ERROR_MSG, 255, 0Ch
;	jmp	Exit
;
;LOGO_ERROR_MSG:
;	db "Error loading the IFF/ILBM logo picture !", 0Dh, 0Ah, 0
;
;loadlbm_ok:

; ----------------------------------------------------------------------------
	
	cmp	byte [audio_hardware], 1
	jne	short skip_sdc
	
	; parepare g_buffer wave graphics parameters

	mov	ebx, sdc_16bit_stereo

	mov	al, [WAVE_BlockAlign]
	cmp	al, 4
	je	short set_sdc_p_ok
	mov	ebx, sdc_8bit_mono
	cmp	al, 1
	je	short set_sdc_p_ok
	mov	ebx, sdc_8bit_stereo
	cmp	byte [WAVE_BitsPerSample], 8
	je	short set_sdc_p_ok
	mov	ebx, sdc_16bit_mono
set_sdc_p_ok:
	mov	[sound_data_copy], ebx

skip_sdc:

; ----------------------------------------------------------------------------

	; play the .wav file.

	call	PlayWav

; ----------------------------------------------------------------------------

	; close the .wav file and exit.
	call	closeFile

; ----------------------------------------------------------------------------

	cmp	byte [audio_hardware], 1
	jne	short terminate

	; Cancel syscalback service for Sound Blaster 16
	
	mov	al, [audio_intr] ; 5 or 7
	xor	ah, ah ; reset
	call	set_hardware_int_vector

; ----------------------------------------------------------------------------

terminate:
	call	settextmode
	
	jmp	Exit

; ----------------------------------------------------------------------------

	; INPUT: edx = file name address
	; OUTPUT: [FileHandle]
openFile:
	; open File for read
	sys	_open, edx, 0
	jc	short _of_err
		; cf = 1 -> not found or access error
	mov	[FileHandle], eax
_of_err:
	retn

; ----------------------------------------------------------------------------

	; INPUT: [FileHandle]
	; OUTPUT: none
closeFile:
	sys	_close, [FileHandle]
	retn

; ----------------------------------------------------------------------------

getWAVParameters:
	sys	_read, [FileHandle], WAVFILEHEADERbuff, 44
	jc	short gwavp_retn

	cmp	eax, 44
	jb	short gwavp_retn

	cmp	dword [RIFF_Format], 'WAVE'
	jne	short gwavp_stc_retn

	cmp	word [WAVE_AudioFormat], 1 ; Offset 20, must be 1 (= PCM)
	jne	short gwavp_stc_retn

	; (OpenMPT creates wav files with a new type header,
	;  this program can not use the new type
	;  because of 'data' offset is not at DATA_SubchunkID.)
	; ((GoldWave creates common type wav file.))

	cmp	dword [DATA_SubchunkID], 'data'
	je	short gwavp_retn

gwavp_stc_retn:
	stc
gwavp_retn:
	retn

;=============================================================================
;
;=============================================================================

	; 10/02/2025
	; 09/02/2025
PlayWav:
	cmp	byte [audio_hardware], 1
	ja	short playwav_ac97

playwav_sb16:
	cmp	byte [stopped], 1
	jb	short playwav_sb16_@

	; replay
	mov	byte [stopped], 0
	mov	byte [half_buffer], 1

	jmp	short playwav_sb16_@@

playwav_sb16_@:
	; set audio interrupt vector (to user's handler)
	; set syscallback service for Sound Blaster 16
	mov	al, [IRQnum]
	mov	ah, 1 ; set
	; 10/02/2025
	mov	edx, IRQnum
	call	set_hardware_int_vector

playwav_sb16_@@:
	mov	edi, dma_buffer
	call	SB16_LoadFromFile

	mov	eax, [count]
	add	[LoadedDataBytes], eax

	mov	edi, dma_buffer
	add	edi, [loadsize] ; = add edi, [buffersize]
	call	SB16_LoadFromFile

	mov	eax, [count]
	add	[LoadedDataBytes], eax

	call	sb16_init_play

	mov	byte [IRQnum], 0
	jmp	SB16_TuneLoop

playwav_ac97:
	cmp	byte [stopped], 1
	jb	short playwav_ac97_@

	mov	byte [stopped], 0

	call	ac97_RePlayWav

	jmp	short AC97_TuneLoop

playwav_ac97_@:
	call	ac97_play_setup

	call	ac97_init_play

	;jmp	short AC97_TuneLoop

; ----------------------------------------------------------------------------

	; 09/02/2025
AC97_TuneLoop:

;tuneLoop:
tLWait:
	cmp	byte [stopped], 0
	jna	short tL1 
tLWait@:
	cmp	byte [stopped], 3
	jnb	short tL0

	call	checkUpdateEvents
	jnc	short tLWait
tL0:
	jmp	_exitt_
tL1:
	call	updateLVI	; /set LVI != CIV/
	jz	short tL0

	call	checkUpdateEvents
	jc	short tL0

	cmp	byte [stopped], 0
	ja	short tLWait@

	call	getCurrentIndex
	test	al, BIT0
	jz	short tL1	; loop if buffer 2 is not playing

	; load buffer 1
	mov     edi, WAV_BUFFER_1
	mov	[audio_buffer], edi
	call	dword [loadfromwavfile]
	jnc	short tL2

	; end of file
_exitt_:
	; Stop Playing
	call	ac97_stop
	retn
tL2:
	mov	eax, [count]
	add	[LoadedDataBytes], eax
tL3:
	call    updateLVI
	jz	short _exitt_

	call	checkUpdateEvents
	jc	short _exitt_

	cmp	byte [stopped], 0
	ja	short tLWait@

	call    getCurrentIndex
	test	al, BIT0
	jnz	short tL3	; loop if buffer 1 is not playing

	; load buffer 2
	mov     edi, WAV_BUFFER_2
	mov	[audio_buffer], edi
	call	dword [loadfromwavfile]
	jc	short _exitt_

	mov	eax, [count]
	add	[LoadedDataBytes], eax

	jmp	tLWait

; ----------------------------------------------------------------------------

	; 10/02/2025
	; 09/02/2025
SB16_TuneLoop:
;TuneLoop:
.tLWait:
	cmp	byte [stopped], 0
	jna	short .tL2
.tL1:
	call	checkUpdateEvents
	jnc	short .tLWait
._exit_:
	call	sb16_stop
	retn
.tL2:
	; Check SB 16 interrupt status
	cmp	byte [IRQnum], 0
	jna	short .tL1

	;;;;
	; 10/02/2025
	mov 	dx, [audio_io_base]
	add	dl, 0Eh ; 8bit DMA-mode int ack
	;in	al, dx
	mov	ah, 0 ; inb
	int	34h
	inc	edx ; 0Fh ; 16bit DMA-mode int ack
	;in	al, dx	; SB 16 acknowledge.
	mov	ah, 0 ; inb
	int	34h
	;;;;

	xor	byte [half_buffer], 1

	mov	byte [IRQnum], 0

	; load buffer 1
	mov	edi, dma_buffer  ; wav_buffer1
	cmp	byte [half_buffer], 0
	jna	short .tL3

	; load buffer 2
	add	edi, [loadsize]
.tL3:
	call	SB16_LoadFromFile
	jc	short ._exit_	; end of file

	mov	eax, [count]
	add	[LoadedDataBytes], eax

	jmp	short .tL1

;=============================================================================
;
;=============================================================================

c4ue_ok:
	retn

	; 09/02/2025
checkUpdateEvents:
	call	check4keyboardstop
	jc	short c4ue_ok

	push	eax ; *
	or	eax, eax
	jz	short c4ue_cpt

	cmp	al, 20h ; SPACE (spacebar) ; pause/play
	jne	short c4ue_chk_s
	cmp	byte [stopped], 0
	ja	short c4ue_chk_ps

	call	audio_pause

	jmp	short c4ue_cpt

c4ue_chk_ps:
	cmp	byte [stopped], 1
	ja	short c4ue_replay

	; continue to play (after a pause)
	call	audio_play

	jmp	short c4ue_cpt

c4ue_replay:
	pop	ax ; *
	pop	ax ; return address

	call	move_to_beginning

	;mov	byte [stopped], 0

	jmp	PlayWav

c4ue_chk_s:
	cmp	al, 'S'	; stop
	jne	short c4ue_chk_fb
	cmp	byte [stopped], 0
	ja	c4ue_cpt ; Already stopped/paused

	call	audio_stop

	jmp	short c4ue_cpt

c4ue_chk_fb:
	cmp	al, 'F'
	jne	short c4ue_chk_b
	call 	move_forward
	jmp	short c4ue_cpt

c4ue_chk_b:
	cmp	al, 'B'
	jne	short c4ue_cpt

	call 	move_backward

c4ue_cpt:
	pop	ecx ; *

	sys	_time, 4 ; get timer ticks (18.2 ticks/second)

	cmp	eax, [timerticks]
	je	short c4ue_skip_utt
c4ue_utt:
	mov	[timerticks], eax
	jmp	short c4ue_cpt_@

c4ue_skip_utt:
	and	ecx, ecx
	jz	short c4ue_cpt_@
c4ue_vb_ok:
	retn

c4ue_cpt_@:
	cmp	byte [stopped], 0
	ja	short c4ue_vb_ok

	jmp	drawscopes

;=============================================================================
;
;=============================================================================

	; 09/02/2025
check4keyboardstop:
	mov	ah, 1	; check keyboard buffer
	int	32h	; TRDOS 386 Keyboard Interrupt
	;clc
	jz	short _cksr ; empty

	xor	ah, ah	; Getchar
	int	32h

	;;;;
	; 10/02/2025
clear_keyb_buf:
	push	eax
	mov	ah, 1	; Getchar
	int	32h
	jz	short p_0
	sub	ah, ah
	int	32h
	pop	edx
	jmp	short clear_keyb_buf
p_0:		
	pop	eax
	;;;;

	; (change PCM out volume)
	cmp	al, '+'
	jne	short p_1

	inc	byte [volume]
	jmp	short p_2
p_1:
	cmp	al, '-'
	jne	short p_4

	dec	byte [volume]
p_2:
	call	SetPCMOutVolume
_cksr:
	xor	eax, eax
p_3:
	retn
p_4:
	cmp	ah, 01h  ; ESC
    	je	short p_quit
	cmp	al, 03h  ; CTRL+C
	je	short p_quit

	cmp	al, 20h
	je	short p_3

	cmp	al, 0Dh ; CR/ENTER
	je	short p_3

	and	al, 0DFh

	cmp	al, 'Q'
	je	short p_quit

	clc
	retn

p_quit:
	stc
	retn

;-----------------------------------------------------------------------------
;
;-----------------------------------------------------------------------------

	; 09/02/2025
SetPCMOutVolume:
	cmp	byte [audio_hardware], 1
	je	short sb16_set_volume

;-----------------------------------------------------------------------------

ac97_set_volume:
	mov	al, [volume]
	mov	ah, 31
	cmp	al, ah ; 31
	jna	short _ac97sv_@
	mov	al, ah
	mov	[volume], al ; max = 31, min = 0
_ac97sv_@:
	; max = 0, min = 31
	sub	ah, al
	mov	al, ah
	mov	dx, [NAMBAR]
  	;add	dx, CODEC_MASTER_VOL_REG
	add	dx, CODEC_PCM_OUT_REG
	;out	dx, ax
	mov	ebx, eax
	mov	ah, 3	; write port, word
	int	34h	; TRDOS 386 IOCTL interrupt
	retn

;-----------------------------------------------------------------------------

sb16_set_volume:
	mov	al, [volume]
	mov	ah, 15
	cmp	al, ah ; 15
	jna	short _sb16sv_@
	mov	al, ah
	mov	[volume], al ; max = 15, min = 0
_sb16sv_@:
	; al = sound volume (15 = max, 0 = min)
	push	eax
	; Tell the SB 16 card which register to write
	mov	dx, [audio_io_base]
	;add	dx, 4 ; Mixer chip address port
	add	dl, 4
	mov	al, 22h
	;out	dx, al
	mov	ah, 1	; write port, byte
	int	34h	; TRDOS 386 IOCTL interrupt

	pop	eax
	;and	al, 0Fh
	; Set the volume for both L and R
	mov	bl, 11h
	mul	bl
	; Set new volume
	;mov	dx, [audio_io_base]
	;;add	dx, 5
	;add	dl, 5
	; 10/02/2025
	inc	edx
	;out	dx, al
	mov	ah, 1	; outb
	int	34h
	retn

;=============================================================================
; 09/02/2025 - change song (wave file) play position
;=============================================================================

move_backward:
move_forward:
	;; In order to go backwards 5 seconds:
	;; Update file pointer to the beginning, skip headers
	mov	cl, al ; 'B' or 'F'

move_backward_or_forward:
	; (Ref: player.asm, Matan Alfasi, 2017)
  
	mov	eax, 5
	movzx	ebx, word [WAVE_BlockAlign]
	mul	ebx
	mov	bx, [WAVE_SampleRate]
	mul	ebx
	; eax = transfer byte count for 5 seconds

	cmp	cl, 'B'
	mov	ecx, [LoadedDataBytes]
	jne	short move_fw ; cl = 'F'
move_bw:
	sub	ecx, eax
	jnc	short move_file_pointer
move_to_beginning:
	xor	ecx, ecx ; 0
	jmp	short move_file_pointer
move_fw: 
	add	ecx, eax
	jc	short move_to_end
	mov	ebx, [DATA_SubchunkSize]
	cmp	ecx, ebx
	jna	short move_file_pointer
move_to_end:
	mov	ecx, ebx
move_file_pointer:
	mov	[LoadedDataBytes], ecx
	add	ecx, 44 ; + header

	; seek
	xor	edx, edx ; offset from beginning of the file
	; ecx = offset	
	; ebx = file handle
	; edx = 0
	sys	_seek, [FileHandle]

	retn

;=============================================================================
; Wave Data Loading procedure for Sound Blaster 16 (there is not a conversion)
;=============================================================================

	; 09/02/2025
SB16_LoadFromFile:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short sblff_0		; no
	stc
	retn

sblff_0:
	; edi = audio buffer address

	; load/read file
	; --------------
	; ebx = file handle
	; ecx = buffer
	; edx = read count

	sys 	_read, [FileHandle], edi, [loadsize]
	jc	short sblff_2 ; error !

	mov	[count], eax

	cmp	eax, edx
	je	short _endLFF

	; edi = buffer address
	add	edi, eax
sblff_1:
	mov	ecx, edx
	call    sb_padfill		; blank pad the remainder
        ;clc				; don't exit with CY yet.
        or	byte [flags], ENDOFFILE	; end of file flag
	; 07/02/2025
	;cmp	word [count], 1
_endLFF:
        retn

sblff_2:
	xor	eax, eax
	jmp	short sblff_1

;-----------------------------------------------------------------------------

sb_padfill:
	; edi = offset (to be filled with ZEROs)
	; eax = number of bytes loaded
	; ecx = buffer size (> loaded bytes)
	sub	ecx, eax
	xor	eax, eax
	cmp	byte [WAVE_BitsPerSample], 8
	ja	short padfill@
	mov	al, 80h
padfill@:
	rep	stosb
	retn

;=============================================================================
; AC97 procedures - load and convert sound data
;=============================================================================

	; 09/02/2025

;-----------------------------------------------------------------------------
; /////
;-----------------------------------------------------------------------------

	; 05/02/2025 - ac97play.s
loadFromFile:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff_0		; no
	stc
	retn

lff_0:
	; edi = audio buffer address

	cmp	byte [fbs_shift], 0
	jna	short lff_1 ; stereo, 16 bit

lff_2:
	;; fbs_shift =
	;;	2 for mono and 8 bit sample (multiplier = 4)
	;;	1 for mono or 8 bit sample (multiplier = 2)
	;;;;;;	0 for stereo and 16 bit sample (multiplier = 1)
	
	mov	esi, temp_buffer 

	sys 	_read, [FileHandle], esi, [loadsize]
	jc	lff_4 ; error !

	mov	[count], eax

	and	eax, eax
	jz	lff_10

	mov	bl, [fbs_shift]

	mov	edx, edi ; audio buffer start address

	mov	ecx, eax
	cmp	byte [WAVE_BitsPerSample], 8 ; bits per sample (8 or 16)
	jne	short lff_7 ; 16 bit samples
	; 8 bit samples
	dec	bl  ; shift count, 1 = stereo, 2 = mono
	jz	short lff_6 ; 8 bit, stereo
lff_5:
	; mono & 8 bit
	lodsb
	sub	al, 80h
	shl	eax, 8 ; convert 8 bit sample to 16 bit sample
	stosw	; left channel
	stosw	; right channel
	loop	lff_5
	jmp	short lff_9	
lff_6:
	; stereo & 8 bit
	lodsb
	sub	al, 80h
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
	mov	eax, edi
	mov	ecx, [buffersize] ; words
	shl	ecx, 1 ; bytes
	add	ecx, edx ; + buffer start address
	cmp	eax, ecx
	jb	short lff_3
	retn

lff_1:  
	; edi = audio buffer address

	; load/read file
	; --------------
	; ebx = file handle
	; ecx = buffer
	; edx = read count

	sys 	_read, [FileHandle], edi, [loadsize]
	jc	short lff_4 ; error !

	mov	[count], eax

	cmp	eax, edx
	je	short endLFF

	add	edi, eax

	mov	ecx, edx
lff_3:
	call    padfill			; blank pad the remainder
        ;clc				; don't exit with CY yet.
        or	byte [flags], ENDOFFILE	; end of file flag
endLFF:
        retn
lff_4:
	xor	eax, eax
lff_10:
	mov	ecx, [buffersize] ; samples
	shl	ecx, 1	; bytes
	jmp	short lff_3

;-----------------------------------------------------------------------------

padfill:
	; edi = offset (to be filled with ZEROs)
	; eax = di = number of bytes loaded
	; ecx = buffer size (> loaded bytes)	

	sub	ecx, eax
	xor	eax, eax
	rep	stosb
	retn

;-----------------------------------------------------------------------------
; interpolation procedures
;-----------------------------------------------------------------------------

; 09/02/2025
; 05/02/2025 - ac97play.s
;----------------------------------------------------------------------------

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

;-----------------------------------------------------------------------------
;-----------------------------------------------------------------------------

load_8khz_mono_8_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff8m_0		; no
	stc
	retn

lff8m_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jnc	short lff8m_6
	jmp	lff8m_5  ; error !

lff8m_6:
	mov	[count], eax

	and	eax, eax
	jz	lff8_eof

	mov	ecx, eax	; byte count
lff8m_1:
	lodsb
	mov	[previous_val], al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (left channel)
	stosw		; original sample (right channel)
	;xor	eax, eax
	mov	al, [esi]
	dec	ecx
	jnz	short lff8m_2
	mov	al, 80h
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
lff12_3:
	mov	ecx, [buffersize] ; buffer size in words
	shl	ecx, 1 ; buffer size in bytes
	add	ecx, [audio_buffer]
	sub	ecx, edi
	jna	short lff8m_4
	;inc	ecx
	shr	ecx, 2
	xor	eax, eax ; fill (remain part of) buffer with zeros
	rep	stosd
lff8m_4:
	;clc
	retn

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
lff12_5:

lff8_eof:
lff16_eof:
lff24_eof:
lff32_eof:
lff44_eof:
lff22_eof:
lff11_eof:
lff12_eof:
	mov	byte [flags], ENDOFFILE
	jmp	short lff8m_3

;----------------------------------------------------------------------------

load_8khz_stereo_8_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff8s_0		; no
	stc
	retn

lff8s_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff8s_5 ; error !

	mov	[count], eax

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
	mov	ax, [esi]
	dec	ecx
	jnz	short lff8s_2
		; convert 8 bit sample to 16 bit sample
	mov	ax, 8080h
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

;----------------------------------------------------------------------------

load_8khz_mono_16_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff8m2_0		; no
	stc
	retn

lff8m2_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	lff8m2_7 ; error !

	mov	[count], eax

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
	mov	ax, [esi]
	dec	ecx
	jnz	short lff8m2_2
	xor	eax, eax
lff8m2_2:
	add	ah, 80h ; convert sound level to 0-65535 format
	mov	ebp, eax ; [next_val]
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

;----------------------------------------------------------------------------

load_8khz_stereo_16_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff8s2_0		; no
	stc
	retn

lff8s2_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff8s2_7 ; error !

	mov	[count], eax
	
	shr	eax, 2
	jnz	short lff8s2_8
	jmp	lff8_eof

lff8s2_8:
	mov	ecx, eax ; dword count
lff8s2_1:
	lodsw
	stosw		; original sample (L)
	add	ah, 80h	; convert sound level to 0-65535 format
	mov	[previous_val_l], ax
	lodsw
	stosw		; original sample (R)
	add	ah, 80h	; convert sound level to 0-65535 format
	mov	[previous_val_r], ax
	mov	ax, [esi]
	mov	dx, [esi+2]
	dec	ecx
	jnz	short lff8s2_2
	xor	edx, edx
	xor	eax, eax
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

;----------------------------------------------------------------------------

load_16khz_mono_8_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff16m_0		; no
	stc
	retn

lff16m_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff16m_7 ; error !

	mov	[count], eax
	
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
	;xor	eax, eax
	mov	al, [esi]
	dec	ecx
	jnz	short lff16m_2
	mov	al, 80h
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

;----------------------------------------------------------------------------

load_16khz_stereo_8_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff16s_0		; no
	stc
	retn

lff16s_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff16s_7 ; error !

	mov	[count], eax

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
	mov	ax, [esi]
	dec	ecx
	jnz	short lff16s_2
		; convert 8 bit sample to 16 bit sample
	mov	ax, 8080h
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

;----------------------------------------------------------------------------

load_16khz_mono_16_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff16m2_0		; no
	stc
	retn

lff16m2_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff16m2_7 ; error !

	mov	[count], eax
	
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
	mov	ax, [esi]
	dec	ecx
	jnz	short lff16m2_2
	xor	eax, eax
lff16m2_2:
	add	ah, 80h ; convert sound level 0 to 65535 format
	mov	ebp, eax ; [next_val]
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

;----------------------------------------------------------------------------

load_16khz_stereo_16_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff16s2_0		; no
	stc
	retn

lff16s2_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff16s2_7 ; error !

	mov	[count], eax
	
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
	mov	ax, [esi]
	mov	dx, [esi+2]
	dec	ecx
	jnz	short lff16s2_2
	xor	edx, edx
	xor	eax, eax
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

;----------------------------------------------------------------------------

load_24khz_mono_8_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff24m_0		; no
	stc
	retn

lff24m_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff24m_7 ; error !

	mov	[count], eax
	
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
	mov	al, [esi]
	dec	ecx
	jnz	short lff24m_2
	mov	al, 80h
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

;----------------------------------------------------------------------------

load_24khz_stereo_8_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff24s_0		; no
	stc
	retn

lff24s_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff24s_7 ; error !

	mov	[count], eax

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
	mov	ax, [esi]
	dec	ecx
	jnz	short lff24s_2
		; convert 8 bit sample to 16 bit sample
	mov	ax, 8080h
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

;----------------------------------------------------------------------------

load_24khz_mono_16_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff24m2_0		; no
	stc
	retn

lff24m2_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff24m2_7 ; error !

	mov	[count], eax

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
	mov	bx, [esi]
	dec	ecx
	jnz	short lff24m2_2
	;xor	eax, eax
	xor	ebx, ebx
lff24m2_2:
	add	bh, 80h ; convert sound level 0 to 65535 format
	;add	ah, 80h
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

;----------------------------------------------------------------------------

load_24khz_stereo_16_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff24s2_0		; no
	stc
	retn

lff24s2_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff24s2_7 ; error !

	mov	[count], eax

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
	mov	ax, [esi]
	mov	dx, [esi+2]
	dec	ecx
	jnz	short lff24s2_2
	xor	edx, edx
	xor	eax, eax
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

;----------------------------------------------------------------------------

load_32khz_mono_8_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff32m_0		; no
	stc
	retn

lff32m_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff32m_7 ; error !

	mov	[count], eax

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
	mov	al, [esi]
	dec	ecx
	jnz	short lff32m_2
	mov	al, 80h
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

;----------------------------------------------------------------------------

load_32khz_stereo_8_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff32s_0		; no
	stc
	retn

lff32s_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff32s_7 ; error !

	mov	[count], eax

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
	mov	ax, [esi]
	dec	ecx
	jnz	short lff32s_2
		; convert 8 bit sample to 16 bit sample
	mov	ax, 8080h
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

;----------------------------------------------------------------------------

load_32khz_mono_16_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff32m2_0		; no
	stc
	retn

lff32m2_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff32m2_7 ; error !

	mov	[count], eax

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
	;mov	ax, [esi]
	mov	bx, [esi]
	dec	ecx
	jnz	short lff32m2_2
	xor	ebx, ebx
lff32m2_2:
	add	bh, 80h ; convert sound level 0 to 65535 format
	;add	ah, 80h
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

;----------------------------------------------------------------------------

load_32khz_stereo_16_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff32s2_0		; no
	stc
	retn

lff32s2_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff32s2_7 ; error !

	mov	[count], eax

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
	mov	ax, [esi]
	mov	dx, [esi+2]
	dec	ecx
	jnz	short lff32s2_2
	xor	edx, edx
	xor	eax, eax
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

;----------------------------------------------------------------------------

load_22khz_mono_8_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff22m_0		; no
	stc
	retn

lff22m_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff22m_7 ; error !

	mov	[count], eax
	
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
	mov	dl, [esi]
	dec	ecx
	jnz	short lff22m_2_1
	mov	dl, 80h
lff22m_2_1:
	; al = [previous_val]
	; dl = [next_val]
	call	interpolating_3_8bit_mono ; 1 of 17
	jecxz	lff22m_3
lff22m_2_2:
	lodsb
	mov	dl, [esi]
	dec	ecx
	jnz	short lff22m_2_3
	mov	dl, 80h
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

;----------------------------------------------------------------------------

load_22khz_stereo_8_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff22s_0		; no
	stc
	retn

lff22s_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff22s_7 ; error !

	mov	[count], eax

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
	mov	dx, [esi]
	dec	ecx
	jnz	short lff22s_2_1
	mov	dx, 8080h
lff22s_2_1:
	; al = [previous_val_l]
	; ah = [previous_val_r]
	; dl = [next_val_l]
	; dh = [next_val_r]
	call	interpolating_3_8bit_stereo ; 1 of 17
	jecxz	lff22s_3
lff22s_2_2:
	lodsw
	mov	dx, [esi]
	dec	ecx
	jnz	short lff22s_2_3
	mov	dx, 8080h
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

;----------------------------------------------------------------------------

load_22khz_mono_16_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff22m2_0		; no
	stc
	retn

lff22m2_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff22m2_7 ; error !

	mov	[count], eax

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
	mov	dx, [esi]
	dec	ecx
	jnz	short lff22m2_2_1
	xor	edx, edx
lff22m2_2_1:	
	; ax = [previous_val]
	; dx = [next_val]
	call	interpolating_3_16bit_mono ; 1 of 17
	jecxz	lff22m2_3
lff22m2_2_2:
	lodsw
	mov	dx, [esi]
	dec	ecx
	jnz	short lff22m2_2_3
	xor	edx, edx
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

;----------------------------------------------------------------------------

load_22khz_stereo_16_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff22s2_0		; no
	stc
	retn

lff22s2_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff22s2_7 ; error !

	mov	[count], eax

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
	jmp	lff22_3	; padfill

;----------------------------------------------------------------------------

load_11khz_mono_8_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff11m_0		; no
	stc
	retn

lff11m_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff11m_7 ; error !

	mov	[count], eax

	and	eax, eax
	jnz	short lff11m_8
	jmp	lff11_eof

lff11m_8:
	mov	ecx, eax	; byte count
lff11m_9:
	mov	ebp, 6 ; interpolation (one step) loop count
lff11m_1:
	; 5:4:4::5:4:4::5:4:4::5:4:4::5:4:4::5:4  ; 74/17
	lodsb
	mov	dl, [esi]
	dec	ecx
	jnz	short lff11m_2_1
	mov	dl, 80h
lff11m_2_1:	
	; al = [previous_val]
	; dl = [next_val]
	call	interpolating_5_8bit_mono
	jecxz	lff11m_3
lff11m_2_2:
	lodsb
	mov	dl, [esi]
	dec	ecx
	jnz	short lff11m_2_3
	mov	dl, 80h
lff11m_2_3:
 	call	interpolating_4_8bit_mono
	jecxz	lff11m_3

	dec	ebp
	jz	short lff11m_9

	lodsb
	mov	dl, [esi]
	dec	ecx
	jnz	short lff11m_2_4
	mov	dl, 80h
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

;----------------------------------------------------------------------------

load_11khz_stereo_8_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff11s_0		; no
	stc
	retn

lff11s_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff11s_7 ; error !

	mov	[count], eax

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
	mov	dx, [esi]
	dec	ecx
	jnz	short lff11s_2_1
	mov	dx, 8080h
lff11s_2_1:
	; al = [previous_val_l]
	; ah = [previous_val_r]
	; dl = [next_val_l]
	; dh = [next_val_r]
	call	interpolating_5_8bit_stereo
	jecxz	lff11s_3
lff11s_2_2:
	lodsw
	mov	dx, [esi]
	dec	ecx
	jnz	short lff11s_2_3
	mov	dx, 8080h
lff11s_2_3:
 	call	interpolating_4_8bit_stereo
	jecxz	lff11s_3
	
	dec	ebp
	jz	short lff11s_9

	lodsw
	mov	dx, [esi]
	dec	ecx
	jnz	short lff11s_2_4
	mov	dx, 8080h
lff11s_2_4:
	call	interpolating_4_8bit_stereo
	jecxz	lff11s_3
	jmp	short lff11s_1

;----------------------------------------------------------------------------

load_11khz_mono_16_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff11m2_0		; no
	stc
	retn

lff11m2_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff11m2_7 ; error !

	mov	[count], eax
	
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
	mov	dx, [esi]
	dec	ecx
	jnz	short lff11m2_2_1
	xor	edx, edx
lff11m2_2_1:	
	; ax = [previous_val]
	; dx = [next_val]
	call	interpolating_5_16bit_mono
	jecxz	lff11m2_3
lff11m2_2_2:
	lodsw
	mov	dx, [esi]
	dec	ecx
	jnz	short lff11m2_2_3
	xor	edx, edx
lff11m2_2_3:
 	call	interpolating_4_16bit_mono
	jecxz	lff11m2_3

	dec	ebp
	jz	short lff11m2_9

	lodsw
	mov	dx, [esi]
	dec	ecx
	jnz	short lff11m2_2_4
	xor	edx, edx
lff11m2_2_4:
 	call	interpolating_4_16bit_mono
	jecxz	lff11m2_3
	jmp	short lff11m2_1

lff11m2_7:
lff11s2_7:
	jmp	lff11_5  ; error

;----------------------------------------------------------------------------

load_11khz_stereo_16_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff11s2_0		; no
	stc
	retn

lff11s2_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff11s2_7 ; error !

	mov	[count], eax
	
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
	;mov	[next_val_l], edx
	;shr	edx, 16
	;mov	[next_val_r], dx
	dec	ecx
	jnz	short lff11s2_2_1
	xor	edx, edx ; 0
	;mov	[next_val_l], dx
	;mov	[next_val_r], dx
lff11s2_2_1:
	; bx = [previous_val_l]
	; ax = [previous_val_r]
	; [next_val_l]
	; dx = [next_val_r]
	mov	[next_val_l], edx

	call	interpolating_5_16bit_stereo
	jecxz	lff11s2_3
lff11s2_2_2:
	lodsw
	mov	ebx, eax
	lodsw
	mov	edx, [esi]
	;mov	[next_val_l], dx
	;shr	edx, 16
	;mov	[next_val_r], dx
	dec	ecx
	jnz	short lff11s2_2_3
	xor	edx, edx ; 0
	;mov	[next_val_l], dx
	;mov	[next_val_r], dx
lff11s2_2_3:
	mov	[next_val_l], edx

	call	interpolating_4_16bit_stereo
	jecxz	lff11s2_3
	
	dec	ebp
	jz	short lff11s2_9

	lodsw
	mov	ebx, eax
	lodsw
	mov	edx, [esi]
	;mov	[next_val_l], dx
	;shr	edx, 16
	;mov	[next_val_r], dx
	dec	ecx
	jnz	short lff11s2_2_4
	xor	edx, edx ; 0
	;mov	[next_val_l], dx
	;mov	[next_val_r], dx
lff11s2_2_4:
	mov	[next_val_l], edx

 	call	interpolating_4_16bit_stereo
	jecxz	lff11s2_3
	jmp	short lff11s2_1

;----------------------------------------------------------------------------

load_44khz_mono_8_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff44m_0		; no
	stc
	retn

lff44m_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff44m_7 ; error !

	mov	[count], eax

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
	mov	dl, [esi]
	dec	ecx
	jnz	short lff44m_2_1
	mov	dl, 80h
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

;----------------------------------------------------------------------------

load_44khz_stereo_8_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff44s_0		; no
	stc
	retn

lff44s_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff44s_7 ; error !

	mov	[count], eax

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
	mov	dx, [esi]
	dec	ecx
	jnz	short lff44s_2_1
	mov	dx, 8080h
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

;----------------------------------------------------------------------------

load_44khz_mono_16_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff44m2_0		; no
	stc
	retn

lff44m2_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff44m2_7 ; error !

	mov	[count], eax

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
	mov	dx, [esi]
	dec	ecx
	jnz	short lff44m2_2_1
	xor	edx, edx
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

;----------------------------------------------------------------------------

load_44khz_stereo_16_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff44s2_0		; no
	stc
	retn

lff44s2_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff44s2_7 ; error !

	mov	[count], eax

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

;----------------------------------------------------------------------------

load_12khz_mono_8_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff12m_0		; no
	stc
	retn

lff12m_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff12m_7 ; error !

	mov	[count], eax

	and	eax, eax
	jnz	short lff12m_8
	jmp	lff12_eof

lff12m_8:
	mov	ecx, eax	; byte count
lff12m_1:
	; original-interpolated-interpolated-interpolated
	lodsb
	mov	dl, [esi]
	dec	ecx
	jnz	short lff12m_2
	mov	dl, 80h
lff12m_2:	
	; al = [previous_val]
	; dl = [next_val]
 	call	interpolating_4_8bit_mono
	jecxz	lff12m_3
	jmp	short lff12m_1

;----------------------------------------------------------------------------

load_12khz_stereo_8_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff12s_0		; no
	stc
	retn

lff12s_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff12s_7 ; error !

	mov	[count], eax
	
	shr	eax, 1
	jnz	short lff12s_8
	jmp	lff12_eof

lff12m_7:
lff12s_7:
	jmp	lff12_5  ; error

lff12s_8:
	mov	ecx, eax	; word count
lff12s_1:
	; original-interpolated-interpolated-interpolated
	lodsw
	mov	dx, [esi]
	dec	ecx
	jnz	short lff12s_2
	mov	dx, 8080h
lff12s_2:	
	; al = [previous_val_l]
	; ah = [previous_val_r]
	; dl = [next_val_l]
	; dh = [next_val_r]
	call	interpolating_4_8bit_stereo
	jecxz	lff12s_3
	jmp	short lff12s_1

lff12m_3:
lff12s_3:
	jmp	lff12_3	; padfill
		; (put zeros in the remain words of the buffer)

;----------------------------------------------------------------------------

load_12khz_mono_16_bit:
	test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff12m2_0		; no
	stc
	retn

lff12m2_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff12m2_7 ; error !

	mov	[count], eax

	shr	eax, 1
	jnz	short lff12m2_8
	jmp	lff12_eof

lff12m2_8:
	mov	ecx, eax	; word count
lff12m2_1:
	; original-interpolated-interpolated-interpolated
	lodsw
	mov	dx, [esi]
	dec	ecx
	jnz	short lff12m2_2
	xor	edx, edx
lff12m2_2:	
	; ax = [previous_val]
	; dx = [next_val]
 	call	interpolating_4_16bit_mono
	jecxz	lff12m_3
	jmp	short lff12m2_1

lff12m2_7:
lff12s2_7:
	jmp	lff12_5  ; error

;----------------------------------------------------------------------------

load_12khz_stereo_16_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff12s2_0		; no
	stc
	retn

lff12s2_0:
	; edi = audio buffer address

	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff12s2_7 ; error !

	mov	[count], eax

	shr	eax, 2	; dword (left chan word + right chan word)
	jnz	short lff12s2_8
	jmp	lff12_eof

lff12m2_3:
lff12s2_3:
	jmp	lff12_3	; padfill
		; (put zeros in the remain words of the buffer)

lff12s2_8:
	mov	ecx, eax	; dword count
lff12s2_1:
	; original-interpolated-interpolated-interpolated
	lodsw
	mov	ebx, eax
	lodsw
	mov	edx, [esi]
	dec	ecx
	jnz	short lff12s2_2
	xor	edx, edx ; 0
lff12s2_2:
	mov	[next_val_l], edx

	; bx = [previous_val_l]
	; ax = [previous_val_r]
	; [next_val_l]
	; [next_val_r]
	call	interpolating_4_16bit_stereo
	jecxz	lff12s2_3
	jmp	short lff12s2_1

;-----------------------------------------------------------------------------
;-----------------------------------------------------------------------------

	; 09/02/2025

interpolating_3_8bit_mono:
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
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 2 (L)
	stosw		; interpolated sample 2 (R)
	retn

;-----------------------------------------------------------------------------

interpolating_3_8bit_stereo:
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
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 2 (L)
	mov	al, bl
	add	al, dh	; [next_val_r]
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 2 (R)
	retn

;-----------------------------------------------------------------------------

interpolating_2_8bit_mono:
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

;-----------------------------------------------------------------------------

interpolating_2_8bit_stereo:
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

;-----------------------------------------------------------------------------

interpolating_3_16bit_mono:
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

;-----------------------------------------------------------------------------

interpolating_3_16bit_stereo:
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

;-----------------------------------------------------------------------------

interpolating_2_16bit_mono:
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

;-----------------------------------------------------------------------------

interpolating_2_16bit_stereo:
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
	sub	ah, 80h	; -32768 to +32767 format again
	;push	eax ; *	; interpolated sample (R)
	shl	eax, 16
	mov	ax, [next_val_l]
	add	ah, 80h
	add	bh, 80h
	add	ax, bx	; [next_val_l] + [previous_val_l]
	rcr	ax, 1	; / 2
	sub	ah, 80h	; -32768 to +32767 format again
	;stosw 		; interpolated sample (L)
	;pop	eax ; *
	;sub	ah, 80h	; -32768 to +32767 format again
	;stosw 		; interpolated sample (R)
	stosd
	retn

;-----------------------------------------------------------------------------

interpolating_5_8bit_mono:
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

;-----------------------------------------------------------------------------

interpolating_5_8bit_stereo:
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
	push	eax ; ** ; al = interpolated middle (L) (temporary)
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
	pop	eax ; ** ; al = interpolated middle (L) (temporary)
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

;-----------------------------------------------------------------------------

interpolating_4_8bit_mono:
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

;-----------------------------------------------------------------------------

interpolating_4_8bit_stereo:
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

;-----------------------------------------------------------------------------

interpolating_5_16bit_mono:
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

;-----------------------------------------------------------------------------

interpolating_5_16bit_stereo:
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

;-----------------------------------------------------------------------------

interpolating_4_16bit_mono:
	; ax = [previous_val]
	; dx = [next_val]
	; 02/02/2025
	; original-interpolated-interpolated-interpolated

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

;-----------------------------------------------------------------------------

interpolating_4_16bit_stereo:
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

;-----------------------------------------------------------------------------

previous_val:
previous_val_l: dw 0
previous_val_r: dw 0
next_val:
next_val_l: dw 0
next_val_r: dw 0

faz:	db 0

;=============================================================================
;	Write AC'97 Hadrware Information
;=============================================================================
	
	; 09/02/2025

write_audio_dev_info:
	xor	ebx, ebx
	cmp	byte [audio_hardware], 1
	jne	short write_ac97_pci_dev_info

;-----------------------------------------------------------------------------
	
	; 09/02/2025
	; 05/02/2025 - sb16play.s

write_sb16_dev_info:
	mov	eax, [audio_io_base]
	;xor	ebx, ebx
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
	mov	al, [audio_intr]
	add	al, 30h
	mov	[msgSB16IRQ], al

	sys	_msg, msgSB16Info, 255, 07h

	retn

;-----------------------------------------------------------------------------

	; 09/02/2025
	; 05/02/2025 - ac97play.s
	
write_ac97_pci_dev_info:
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
	;add	[msgIRQ], ax
	add	ax, 3030h
	mov	[msgIRQ], ax
	;and	al, al
	cmp	al, 30h
	jne	short _w_ac97imsg_
	mov	al, [msgIRQ+1]
	mov	ah, ' '
	mov	[msgIRQ], ax
_w_ac97imsg_:
	sys	_msg, msgAC97Info, 255, 07h

        ;retn

;-----------------------------------------------------------------------------

write_VRA_info:
	sys	_msg, msgVRAheader, 255, 07h
	cmp	byte [VRA], 0
	jna	short _w_VRAi_no
_w_VRAi_yes:
	sys	_msg, msgVRAyes, 255, 07h
	retn
_w_VRAi_no:
	sys	_msg, msgVRAno, 255, 07h
	retn

;=============================================================================
;	Write WAV File Information
;=============================================================================

	; 09/02/2025
	; 05/02/2025 - twavply2.s

write_wav_file_info:
	sys	_msg, msgWavFileName, 255, 0Fh
	sys	_msg, wav_file_name, 255, 0Fh

write_sample_rate:
	mov	ax, [WAVE_SampleRate]
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
	cmp	byte [WAVE_BitsPerSample], 16
	je	short wsr_1
	mov	esi, msg8Bits
wsr_1:
	sys	_msg, esi, 255, 0Fh

	mov	esi, msgMono
	cmp	byte [WAVE_BitsPerSample], 1
	je	short wsr_2
	mov	esi, msgStereo
wsr_2:
	sys	_msg, esi, 255, 0Fh
        retn

;=============================================================================
;	Audio System Initialization
;=============================================================================
	
	; 09/02/2025

audio_system_init:
	cmp	byte [audio_hardware], 1
	je	short sb16_init

	call	ac97_init
	jnc	short init_ok

	mov	esi, ac97_init_err_msg

init_error:
	sys	_msg, esi, 255, 0Fh
	stc
init_ok:
	retn

;=============================================================================
;	Sound Blaster 16 Initialization
;=============================================================================

	; 09/02/2025
	; 20/10/2017 - playwav.s

sb16_init:
	; 09/02/2025
	; Ref: TRDOS 386 Kernel v2.0.9, audio.s (06/06/2024)
	;      SbInit_play procedure (06/08/2022, v2.0.5)

	mov	ebx, [DMA_phy_buff] ; physical address of DMA buffer

	mov	ecx, [buffersize] ; = [loadsize] for SB16
	shl	ecx, 1	; 2*[buffersize] = dma buffer size

	cmp	byte [WAVE_BitsPerSample], 16
	jne	short sbInit_0	; set 8 bit DMA buffer

	; convert byte count to word count
	shr	ecx, 1
	dec	ecx	; word count - 1

	; convert byte offset to word offset
	shr	ebx, 1

	; 16 bit DMA buffer setting (DMA channel 5)
	mov	al, 05h  ; set mask bit for channel 5 (4+1)
	;out	0D4h, al
	mov	dx, 0D4h ; DMA mask register
	mov	ah, 1  ;outb
	int	34h
	
	xor	al, al   ; stops all DMA processes on selected channel
	;out	0D8h, al
	mov	dl, 0D8h ; clear selected channel register
	;mov	ah, 1  ;outb
	int	34h

	mov	al, bl	 ; byte 0 of DMA buffer offset in words (physical)
	;out	0C4, al
	mov	dl, 0C4h ; DMA channel 5 port number
	;mov	ah, 1  ;outb
	int	34h

	mov	al, bh   ; byte 1 of DMA buffer offset in words (physical)
	;out	0C4h, al
	;mov	dl, 0C4h ; DMA channel 5 port number
	;mov	ah, 1  ;outb
	int	34h
	
	shr	ebx, 15	 ; complete 16 bit shift
	and	bl, 0FEh ; clear bit 0 (not necessary, it will be ignored)

	mov	al, bl   ; byte 2 of DMA buffer address (physical)
	;out	8Bh, al
	mov	dl, 8Bh	 ; page register port addr for channel 5
	;mov	ah, 1  ;outb
	int	34h

	mov	al, cl   ; low byte of DMA count - 1
	;out	0C6h, al
	mov	dl, 0C6h ; count register port addr for channel 1
	;mov	ah, 1  ;outb
	int	34h

	mov	al, ch   ; high byte of DMA count - 1
	;out	0C6h, al
	;mov	dl, 0C6h ; count register port addr for channel 1
	;mov	ah, 1  ;outb
	int	34h

	; channel 5, read, autoinitialized, single mode
	mov	al, 59h
	;out	0D6h, al
	mov	dl, 0D6h ; DMA mode register port address
	;mov	ah, 1  ;outb
	int	34h

	mov	al, 01h  ; clear mask bit for channel 5
	;out	0D4h, al
	mov	dl, 0D4h ; DMA mask register port address
	;mov	ah, 1  ;outb
	int	34h

	jmp	short ResetDsp

sbInit_0:
	dec	ecx	; byte count - 1

	; 8 bit DMA buffer setting (DMA channel 1)
	mov	al, 05h ; set mask bit for channel 1 (4+1)
	;out	0Ah, al
	mov	dx, 0Ah ; DMA mask register
	mov	ah, 1  ;outb
	int	34h

	xor	al, al  ; stops all DMA processes on selected channel
	;out	0Ch, al
	mov	dl, 0Ch ; clear selected channel register
	;mov	ah, 1  ;outb
	int	34h

	mov	al, bl	; byte 0 of DMA buffer address (physical)
	;out	02h, al
	mov	dl, 02h	; DMA channel 1 port number
	;mov	ah, 1  ;outb
	int	34h

	mov	al, bh  ; byte 1 of DMA buffer address (physical)
	;out	02h, al
	;mov	dl, 02h ; DMA channel 1 port number
	;mov	ah, 1  ;outb
	int	34h

	shr	ebx, 16

	mov	al, bl  ; byte 2 of DMA buffer address (physical)
	;out	83h, al
	mov	dl, 83h ; page register port addr for channel 1
	;mov	ah, 1  ;outb
	int	34h

	mov	al, cl  ; low byte of DMA count - 1
	;out	03h, al
	mov	dl, 03h ; count register port addr for channel 1
	;mov	ah, 1  ;outb
	int	34h

	mov	al, ch  ; high byte of DMA count - 1
	;out	03h, al
	;mov	dl, 03h ; count register port addr for channel 1
	;mov	ah, 1  ;outb
	int	34h

	; channel 1, read, autoinitialized, single mode
	mov	al, 59h
	;out	0Bh, al
	mov	dl, 0Bh ; DMA mode register port address
	;mov	ah, 1  ;outb
	int	34h

	mov	al, 01h ; clear mask bit for channel 1
	;out	0Ah, al
	mov	dl, 0Ah ; DMA mask register port address
	;mov	ah, 1  ;outb
	int	34h

ResetDsp:
	mov	dx, [audio_io_base]
	;add	dx, 06h
	add	dl, 06h
	mov	al, 1
	;out	dx, al
	mov	ah, 1  ;outb
	int	34h

	;in	al, dx
	;in	al, dx
	;in	al, dx
	;in	al, dx

	xor	eax, eax
	;mov	ah, 0  ;inb
	int	34h
	;mov	ah, 0
	int	34h

	;out	dx, al
	inc	ah ; ah = 1 ;outb
	int	34h

	;mov	ecx, 100
	mov	cx, 100
	sub	ah, ah ; 0
WaitId:
	mov	dx, [audio_io_base]
	add	dl, 0Eh
	;in	al, dx
	;mov	ah, 0  ;inb
	int	34h
	or	al, al
	;js	short sb_GetId
	jns	short sb_next
	;loop	WaitId
	;jmp	sb_Exit

sb_GetId:
	mov	dx, [audio_io_base]
	;add	dx, 0Ah
	add	dl, 0Ah
	;in	al, dx
	;mov	ah, 0  ;inb
	int	34h
	cmp	al, 0AAh
	je	short SbOk
sb_next:
	loop	WaitId
	;stc

	mov	esi, sb16_init_err_msg
	jmp	init_error

SbOk:
	retn

;-----------------------------------------------------------------------------
;-----------------------------------------------------------------------------

	; 10/02/2025
	; 09/02/2025
	; 20/10/2017 - playwav.s

sb16_init_play:
	mov	dx, [audio_io_base]
	;add	dx, 0Ch
	add	dl, 0Ch
	SbOut	0D1h	; Turn on speaker
	SbOut	41h	; 8 bit or 16 bit transfer
	mov	bx, [WAVE_SampleRate] ; sampling rate (Hz)
	SbOut	bh	; sampling rate high byte
	SbOut	bl	; sampling rate low byte

StartDMA:
	; autoinitialized mode
	cmp	byte [WAVE_BitsPerSample], 16 ; 16 bit samples
	je	short sb_play_1
	; 8 bit samples
	mov	bx, 0C6h ; 8 bit output (0C6h)
	cmp	byte [WAVE_NumChannels], 2 ; 1 = mono, 2 = stereo
	jb	short sb_play_2
	mov	bh, 20h	; 8 bit stereo (20h)
	jmp	short sb_play_2
sb_play_1:
	; 16 bit samples
	mov	bx, 10B6h ; 16 bit output (0B6h)
	cmp	byte [WAVE_NumChannels], 2 ; 1 = mono, 2 = stereo
	jb	short sb_play_2
	add	bh, 20h	; 16 bit stereo (30h)
sb_play_2:
	; PCM output (8/16 bit mono autoinitialized transfer)
	SbOut   bl	; bCommand
	SbOut	bh	; bMode

	mov	ebx, [buffersize] ; = [loadsize] for SB16
			; half buffer size
	cmp	byte [WAVE_BitsPerSample], 16 ; 16 bit DMA
	jne	short sb_play_3
	shr	ebx, 1	; byte count to word count (samples)
sb_play_3:
	dec	ebx ; wBlkSize is one less than the actual size
	SbOut   bl
	SbOut   bh

	mov	byte [volume], 13 ; max = 15, min = 0

	call	SetPCMOutVolume

	retn

;-----------------------------------------------------------------------------

	; 10/02/2025
	; 09/02/2025
	; 20/10/2017 - playwav.s

sb16_stop:
	; 09/02/2025
	; Ref: TRDOS 386 Kernel v2.0.9 audio.s (06/06/2024)
	;      sb16_stop procedure (06/08/2022, v2.0.5)

	;mov	byte [stopped], 2
	;
	mov	dx, [audio_io_base]
	;add	dx, 0Ch
	add	dl, 0Ch

	mov	bl, 0D9h ; exit auto-initialize 16 bit transfer
	; stop  autoinitialized DMA transfer mode 
	cmp	byte [WAVE_BitsPerSample], 16 ; 16 bit samples
	je	short sb16_stop_1
	;mov	bl, 0DAh ; exit auto-initialize 8 bit transfer
	inc	bl
sb16_stop_1:
	SbOut	bl ; exit auto-initialize transfer command

	xor	al, al ; stops all DMA processes on selected channel
	mov	ah, 1

	cmp	byte [WAVE_BitsPerSample], 16 ; 16 bit samples
	je	short sb16_stop_2

	;out	0Ch, al ; clear selected channel register
	mov	dx, 0Ch
	;mov	ah, 1 ;outb
	int	34h

	jmp	short sb16_stop_3

sb16_stop_2:
	;out	0D8h, al ; clear selected channel register
	mov	dx, 0D8h
	;mov	ah, 1 ;outb
	int	34h

sb16_stop_3:
	mov	byte [stopped], 2 ; stop !
SbDone:
	; 10/02/2025
	mov	dx, [audio_io_base]
	add	dl, 0Ch
	SbOut   0D0h
	SbOut   0D3h
sb16_stop_4:
	retn

;-----------------------------------------------------------------------------

	; 09/02/2025
	
sb16_pause:
	; Ref: TRDOS 386 Kernel v2.0.9 audio.s (06/06/2024)
	;      sb16_pause procedure (06/08/2022, v2.0.5)

	mov	byte [stopped], 1 ; paused
	;
	mov	dx, [audio_io_base]
	;add	dx, 0Ch ; Command & Data Port
	add	dl, 0Ch
	cmp	byte [WAVE_BitsPerSample], 16 ; 16 bit samples
	je	short sb_pause_1
	; 8 bit samples
	mov	bl, 0D0h ; 8 bit DMA mode
	jmp	short sb_pause_2
sb_pause_1:
	; 16 bit samples
	mov	bl, 0D5h ; 16 bit DMA mode
sb_pause_2:
	SbOut   bl ; bCommand
sb_pause_3:
	retn

;-----------------------------------------------------------------------------

	; 09/02/2025

sb16_play:
sb16_continue:
	; Ref: TRDOS 386 Kernel v2.0.9 audio.s (06/06/2024)
	;      sb16_pause procedure (06/08/2022, v2.0.5)

	; continue to play (after pause)
	mov	byte [stopped], 0
	;
	mov	dx, [audio_io_base]
	;add	dx, 0Ch ; Command & Data Port
	add	dl, 0Ch
	cmp	byte [WAVE_BitsPerSample], 16 ; 16 bit samples
	je	short sb_cont_1
	; 8 bit samples
	mov	bl, 0D4h ; 8 bit DMA mode
	jmp	short sb_cont_2
sb_cont_1:
	; 16 bit samples
	mov	bl, 0D6h ; 16 bit DMA mode
sb_cont_2:     
	SbOut   bl ; bCommand
sb_cont_3:
	retn

;=============================================================================
;	AC'97 Audio System Initialization
;============================================================================

	; 09/02/2025
ac97_init:
	; 05/02/2025 - ac97play.s
codecConfig:
	;AC97_EA_VRA equ 1
	AC97_EA_VRA equ BIT0

init_ac97_controller:
	mov	eax, [bus_dev_fn]
	mov	al, PCI_CMD_REG
	call	pciRegRead16		; read PCI command register
	or      dl, IO_ENA+BM_ENA	; enable IO and bus master
	call	pciRegWrite16

	;call	delay_100ms

init_ac97_codec:
	mov	ebp, 40
	;mov	ebp, 1000
_initc_1:
	mov	dx, GLOB_STS_REG ; 30h
	add	dx, [NABMBAR]
	;in	eax, dx
	mov	ah, 4	; read port, dword
	int	34h

	call	delay1_4ms

	cmp	eax, 0FFFFFFFFh ; -1
	jne	short _initc_3
_initc_2:
	dec	ebp
	jz	short _ac97_codec_ready

	call	delay_100ms
	jmp	short _initc_1
_initc_3:
	test	eax, CTRL_ST_CREADY
	jnz	short _ac97_codec_ready

	cmp	byte [reset], 1
	jnb	short _initc_2

	call	reset_ac97_codec

	mov	byte [reset], 1

	jmp	short _initc_2

_ac97_codec_ready:
	mov	dx, [NAMBAR]
	;add	dx, 0 ; ac_reg_0 ; reset register
	;out	dx, ax
	mov	ebx, eax ; bx = data, word
	mov	ah, 3	; write port, word
	int	34h
	
	call	delay_100ms

	or	ebp, ebp
	jnz	short _ac97_codec_init_ok

	;xor	eax, eax ; 0
	mov	dx, [NAMBAR]
	add	dx, CODEC_REG_POWERDOWN
	;out	dx, ax
	;mov	ebx, eax
	xor	ebx, ebx
	mov	ah, 3	; write port, word
	int	34h

	;call	delay1_4ms

	; wait for 1 second
	mov	ecx, 1000 ; 1000*4*0.25ms = 1s
	;mov	ecx, 40
_ac97_codec_rloop:
	;call	delay_100ms
	call	delay1_4ms

	mov	dx, [NAMBAR]
	add	dx, CODEC_REG_POWERDOWN
	;in	ax, dx
	mov	ah, 2	; read port, word
	int	34h

	;call	delay1_4ms
	
	and	ax, 0Fh
	cmp	al, 0Fh
	je	short _ac97_codec_init_ok
	loop	_ac97_codec_rloop 

init_ac97_codec_err1:
	;stc	; cf = 1
init_ac97_codec_err2:
	retn

_ac97_codec_init_ok:
	call 	reset_ac97_controller

	;call	delay_100ms

	;call	delay1_4ms
	;call	delay1_4ms
	;call	delay1_4ms
	call	delay1_4ms

setup_ac97_codec:
	cmp	word [WAVE_SampleRate], 48000
	je	skip_rate
	
	;cmp	byte [VRA], 0
	;jna	short skip_rate

	mov	dx, [NAMBAR]
	add	dx, CODEC_EXT_AUDIO_CTRL_REG ; 2Ah
	;in	ax, dx
	mov	ah, 2 ; read port, word
	int	34h

	call	delay1_4ms
	
	;and	al, NOT BIT1 ; Clear DRA
	;;;
	; (FASM)
	;and	al, NOT (BIT1+BIT0) ; Clear DRA+VRA
	; (NASM)
	and	al, ~(BIT1+BIT0) ; 0FCh
	;out	dx, ax
	mov	ebx, eax
	mov	dx, [NAMBAR]
	add	dx, CODEC_EXT_AUDIO_CTRL_REG ; 2Ah
	mov	ah, 3 ; write port, word
	int	34h

	call	check_vra

	cmp	byte [VRA], 0
	jna	short skip_rate

	mov	dx, [NAMBAR]
	add	dx, CODEC_EXT_AUDIO_CTRL_REG ; 2Ah
	;in	ax, dx
	mov	ah, 2 ; read port, word
	int	34h

	;and	al, ~BIT1 ; Clear DRA
	;;;

	or	al, AC97_EA_VRA ; 1

	mov	dx, [NAMBAR]
	add	dx, CODEC_EXT_AUDIO_CTRL_REG ; 2Ah
	;out	dx, ax		; Enable variable rate audio
	mov	ebx, eax
	mov	ah, 3 ; write port, word
	int	34h

	mov	ecx, 10
check_vra_loop:
	;call	delay_100ms
	call	delay1_4ms

	mov	dx, [NAMBAR]
	add	dx, CODEC_EXT_AUDIO_CTRL_REG ; 2Ah
	;in	ax, dx
	mov	ah, 2 ; read port, word
	int	34h
	
	test	al, AC97_EA_VRA ; 1
	jnz	short set_rate

	loop	check_vra_loop

;vra_not_supported:
	mov	byte [VRA], 0
	jmp	short skip_rate

set_rate:
	;mov	ax, [WAVE_SampleRate]

	mov    	dx, [NAMBAR]               	
	add    	dx, CODEC_PCM_FRONT_DACRATE_REG	; 2Ch
	;out	dx, ax 		; PCM Front/Center Output Sample Rate
	;mov	ebx, eax  ; bx = data, word
	mov	bx, [WAVE_SampleRate]
	mov	ah, 3 ; write port, word
	int	34h

	;call	delay_100ms
	call	delay1_4ms

skip_rate:
	;mov	ax, 0202h
  	mov	dx, [NAMBAR]
  	add	dx, CODEC_MASTER_VOL_REG ; 02h
	;out	dx, ax
	;mov	ebx, eax  ; bx = data, word
	mov	bx, 0202h 
	mov	ah, 3 ; write port, word
	int	34h

	;call	delay1_4ms
	;call	delay1_4ms
	;call	delay1_4ms
	call	delay1_4ms

	;mov	ax, 0202h
  	mov	dx, [NAMBAR]
  	add	dx, CODEC_PCM_OUT_REG ; 18h
  	;out	dx, ax
	;mov	ebx, eax  ; bx = data, word
	mov	bx, 0202h
	mov	ah, 3 ; write port, word
	int	34h
	
	;call	delay1_4ms
	;call	delay1_4ms
	;call	delay1_4ms
	;call	delay1_4ms

	;clc

	mov	byte [volume], 29 ; max = 31, min = 0

        retn

;-----------------------------------------------------------------------------

	; 09/02/2025
	; 05/02/2025 - ac97play.s

reset_ac97_controller:
	; reset AC97 audio controller registers
	xor	eax, eax
        mov	dx, PI_CR_REG
	add	dx, [NABMBAR]
	;out	dx, al
	; al = data, byte
	mov	ah, 1 ; write port, byte
	int	34h

	;call	delay1_4ms

        mov     dx, PO_CR_REG
	add	dx, [NABMBAR]
	;out	dx, al
	; al = data, byte
	mov	ah, 1 ; write port, byte
	int	34h

	;call	delay1_4ms

        mov     dx, MC_CR_REG
	add	dx, [NABMBAR]
	;out	dx, al
	mov	ah, 1 ; write port, byte
	int	34h

	;call	delay1_4ms

        mov	al, RR
        mov	dx, PI_CR_REG
	add	dx, [NABMBAR]
	;out	dx, al
	mov	ah, 1 ; write port, byte
	int	34h

	;call	delay1_4ms

        mov	dx, PO_CR_REG
	add	dx, [NABMBAR]
	;out	dx, al
	mov	ah, 1 ; write port, byte
	int	34h

	;call	delay1_4ms

        mov	dx, MC_CR_REG
	add	dx, [NABMBAR]
	;out	dx, al
	mov	ah, 1 ; write port, byte
	int	34h

	;call	delay1_4ms

	retn

;-----------------------------------------------------------------------------

	; 09/02/2025
	; 05/02/2025 - ac97play.s

reset_ac97_codec:
	mov	dx, GLOB_CNT_REG ; 2Ch
	add	dx, [NABMBAR]
	;in	eax, dx
	mov	ah, 4 ; read port, dword
	int	34h

	test	al, 2
	jz	short _r_ac97codec_cold

	call	warm_ac97codec_reset
	jnc	short _r_ac97codec_ok
_r_ac97codec_cold:
        call	cold_ac97codec_reset
        jnc	short _r_ac97codec_ok
	
        ;xor	eax, eax ; timeout error
       	;stc
	retn

_r_ac97codec_ok:
        xor     eax, eax
        inc	eax
	retn

;-----------------------------------------------------------------------------

	; 09/02/2025
	; 05/02/2025 - ac97play.s

warm_ac97codec_reset:
	;mov	eax, 6
	mov	dx, GLOB_CNT_REG ; 2Ch
	add	dx, [NABMBAR]
	;out	dx, eax
	;mov	ebx, eax  ; ebx = data, dword
	mov	ebx, 6
	mov	ah, 5 ; write port, dword
	int	34h

	mov	ecx, 10	; total 1s
_warm_ac97c_rst_wait:
	call	delay_100ms

	mov	dx, GLOB_STS_REG ; 30h
	add	dx, [NABMBAR]
	;in	eax, dx
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

;-----------------------------------------------------------------------------

	; 09/02/2025
	; 05/02/2025 - ac97play.s

cold_ac97codec_reset:
        ;mov	eax, 2
	mov	dx, GLOB_CNT_REG ; 2Ch
	add	dx, [NABMBAR]
	;out	dx, eax
	;mov	ebx, eax  ; ebx = data, dword
	mov	ebx, 2
	mov	ah, 5 ; write port, dword
	int	34h

	call	delay_100ms 	; wait 100 ms
	call	delay_100ms 	; wait 100 ms
	call	delay_100ms 	; wait 100 ms
	call	delay_100ms 	; wait 100 ms

	mov	ecx, 16	; total 20*100 ms = 2s
_cold_ac97c_rst_wait:
	mov	dx, GLOB_STS_REG ; 30h
	add	dx, [NABMBAR]
	;in	eax, dx
	mov	ah, 4 ; read port, dword
	int	34h

	test	eax, CTRL_ST_CREADY
	jnz	short _cold_ac97c_rst_ok

	call	delay_100ms

	dec	ecx
	jnz	short _cold_ac97c_rst_wait

_cold_ac97c_rst_fail:
        stc
_cold_ac97c_rst_ok:
	retn

;-----------------------------------------------------------------------------

	; 09/02/2025
	; 05/02/2025 - ac97play.s

check_vra:
	mov	byte [VRA], 1

	mov	dx, [NAMBAR]
	add	dx, CODEC_EXT_AUDIO_REG	; 28h
	;in	ax, dx
	mov	ah, 2 ; read port, word
	int	34h

	;call	delay1_4ms

	test	al, BIT0 ; 1 ; Variable Rate Audio bit
	jnz	short check_vra_ok

vra_not_supported:
	mov	byte [VRA], 0
check_vra_ok:
	retn

;-----------------------------------------------------------------------------
;-----------------------------------------------------------------------------

	; 10/02/2025
	; 08/02/2025 - twavplay.asm
	; !!!! 18.2 block/second buffer sizing for proper wave scopes !!!!
	; (wave graphics synchronization) 

ac97_play_setup:
	cmp	byte [VRA], 1
	jb	short chk_sample_rate

playwav_48_khz:
	mov	dword [loadfromwavfile], loadFromFile
	retn

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
	mov	eax, 1207  ; (71*17)		
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
	mov	eax, 612  ; (36*17)	
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
	mov	eax, 2438  ; (106*23)
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
	mov	eax, 879
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
	mov	eax, 440
	mov	edx, 6
	mov	ecx, 1
	jmp	set_sizes
chk_24khz:
	cmp	ax, 24000
	jne	short chk_32khz
	cmp	byte [WAVE_BitsPerSample], 8
	jna	short chk_24khz_1
	mov	ebx, load_24khz_stereo_16_bit
	cmp	byte [WAVE_NumChannels], 1
	jne	short chk_24khz_2
	mov	ebx, load_24khz_mono_16_bit
	jmp	short chk_24khz_2
chk_24khz_1:
	mov	ebx, load_24khz_stereo_8_bit
	cmp	byte [WAVE_NumChannels], 1
	jne	short chk_24khz_2
	mov	ebx, load_24khz_mono_8_bit
chk_24khz_2:
	mov	eax, 1318
	mov	edx, 2
	mov	ecx, 1
	jmp	set_sizes

chk_32khz:
	cmp	ax, 32000
	jne	short chk_12khz
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
	mov	eax, 1758
	mov	edx, 3
	mov	ecx, 2
	jmp	short set_sizes

vra_needed:
	pop	eax ; discard return address to the caller
vra_err:
	sys	_msg, msg_no_vra, 255, 0Fh
	jmp	Exit

	;;;;
chk_12khz:
	cmp	ax, 12000
	jne	short vra_needed
	cmp	byte [WAVE_BitsPerSample], 8
	jna	short chk_12khz_1
	mov	ebx, load_12khz_stereo_16_bit
	cmp	byte [WAVE_NumChannels], 1
	jne	short chk_12khz_2
	mov	ebx, load_12khz_mono_16_bit
	jmp	short chk_12khz_2
chk_12khz_1:
	mov	ebx, load_12khz_stereo_8_bit
	cmp	byte [WAVE_NumChannels], 1
	jne	short chk_12khz_2
	mov	ebx, load_12khz_mono_8_bit
chk_12khz_2:
	mov	eax, 659
	mov	edx, 4
	mov	ecx, 1
	;jmp	short set_sizes
	;;;;

;-----------------------------------------------------------------------------

set_sizes:
	cmp	byte [WAVE_NumChannels], 1
	je	short ss_1
	shl	eax, 1
ss_1:
	cmp	byte [WAVE_BitsPerSample], 8
	jna	short ss_2
	; 16 bit samples
	shl	eax, 1
ss_2:
	mov	[loadsize], eax
	mul	edx

	cmp	ecx, 1
	je	short ss_3

	div	ecx
ss_3:	
	;;;
	; eax = byte count of (to be) converted samples 
	;;;
	mov	cl, [fbs_shift]

	shl	eax, cl
		; *1 for 16 bit stereo
		; *2 for 16 bit mono or 8 bit stereo
		; *4 for for 8 bit mono
	;;;

	; eax = 16 bit stereo byte count (target buffer size)
	
	shr	eax, 1	; buffer size is 16 bit sample count
	mov	[buffersize], eax  ; **
	mov	[loadfromwavfile], ebx

	retn

;-----------------------------------------------------------------------------
;-----------------------------------------------------------------------------

	; 10/02/2025
	; 05/02/2025 - ac97play.s

ac97_init_play:

_PlayNow:
	; create Buffer Descriptor List

	;  Generic Form of Buffer Descriptor
	;  ---------------------------------
	;  63   62    61-48    47-32   31-0
	;  ---  ---  --------  ------- -----
	;  IOC  BUP -reserved- Buffer  Buffer
	;		      Length   Pointer
	;		      [15:0]   [31:0]

	mov	ebx, [_bdl_buffer] ; BDL_BUFFER physical address

	add	ebx, 4096	; WAVBUFFER_1 physical address

	mov	edi, BDL_BUFFER
	mov	ecx, 16
_0:
	;mov	eax, WAV_BUFFER_1
	mov	eax, ebx	; WAVBUFFER_1 physical address
	stosd

	mov	eax, [buffersize]
	;shr	eax, 1 ; buffer size in word
	or	eax, BUP	; tuneloop (without interrupt)
	stosd

	;mov	eax, WAV_BUFFER_2
	mov	eax, ebx
	add	eax, 12288	; WAVBUFFER_2 physical address
	stosd

	mov	eax, [buffersize]
	; 02/12/2024
	;shr	eax, 1 ; buffer size in word
	or	eax, BUP	; tuneloop (without interrupt)
	stosd

	loop	_0
	
ac97_RePlayWav:
        mov     edi, WAV_BUFFER_1
	mov	[audio_buffer], edi
	call	dword [loadfromwavfile]

	mov	eax, [count]
	add	[LoadedDataBytes], eax

	mov     edi, WAV_BUFFER_2
	mov	[audio_buffer], edi
	call	dword [loadfromwavfile]

	mov	eax, [count]
	add	[LoadedDataBytes], eax

	; write NABMBAR+10h with offset of buffer descriptor list

	;mov	eax, [_bdl_buffer]
	mov	ebx, [_bdl_buffer]	; BDL_BUFFER physical address
	
	mov	dx, [NABMBAR]
	add	dx, PO_BDBAR_REG	; set pointer to BDL
	;out	dx, eax			; write to AC97 controller
	;mov	ebx, eax ; data, dword
	; ebx = [_bdl_buffer] ; data, dword
	mov	ah, 5	; write port dword
	int	34h

	;call	delay1_4ms

	mov	al, 31
	call	setLastValidIndex

	;call	delay1_4ms

	;mov	al, [volume]
	call	SetPCMOutVolume

	mov	dx, [NABMBAR]
        add	dx, PO_CR_REG		; PCM out Control Register
	;mov	al, IOCE + RPBM		; Enable 'Interrupt On Completion' + run
	;				; (LVBI interrupt will not be enabled)
	; (TUNELOOP version, without interrupt)
	mov	al, RPBM
	;out	dx, al			; Start bus master operation.
	; al = data, byte
	mov	ah, 1 ; write port, byte
	int	34h

	;call	delay1_4ms

	retn

;-----------------------------------------------------------------------------
;-----------------------------------------------------------------------------

	; 10/02/2025
	; 06/02/2025 - twavplay.asm
	; Ref: TRDOS 386 v2.0.9, audio.s, Erdogan Tan, 06/06/2024

audio_stop:
	cmp	byte [audio_hardware], 1
	ja	short ac97_stop
	jmp	sb16_stop

;-----------------------------------------------------------------------------

ac97_stop:
	mov	byte [stopped], 2

ac97_po_cmd@:
	xor	al, al ; 0
ac97_po_cmd:
	mov     dx, [NABMBAR]
        add     dx, PO_CR_REG	; PCM out control register
	;out	dx, al
	mov	ah, 1 ; write port, byte
	int	34h
	retn

;-----------------------------------------------------------------------------
;-----------------------------------------------------------------------------

	; 10/02/2025
audio_pause:
	cmp	byte [audio_hardware], 1
	ja	short ac97_pause
	jmp	sb16_pause

;-----------------------------------------------------------------------------

ac97_pause:
	mov	byte [stopped], 1 ; paused
	;mov	al, 0
	;jmp	short ac97_po_cmd
	jmp	short ac97_po_cmd@

;-----------------------------------------------------------------------------
;-----------------------------------------------------------------------------

	; 10/02/2025
audio_play:
	cmp	byte [audio_hardware], 1
	ja	short ac97_play
	jmp	sb16_play

;-----------------------------------------------------------------------------

ac97_play: ; continue to play (after pause)
	mov	byte [stopped], 0
	mov	al, RPBM
	jmp	short ac97_po_cmd

;-----------------------------------------------------------------------------
;-----------------------------------------------------------------------------

PORTB		EQU 061h
REFRESH_STATUS	EQU 010h	; Refresh signal status

	; 10/02/2025
	; 05/02/2025 - ac97play.s
delay_100ms:
	push	ecx
	mov	ecx, 400  ; 400*0.25ms
_delay_x_ms:
	call	delay1_4ms
        loop	_delay_x_ms
	pop	ecx
	retn

;-----------------------------------------------------------------------------

	; 10/02/2025
delay1_4ms:
        push    eax
        push    ecx
	push	ebx
	push	edx
        mov     ecx, 16		; close enough.
	;in	al, PORTB
	mov	dx, PORTB
	mov	ah, 0  ; read port, byte
	int	34h

	and	al, REFRESH_STATUS
	;mov	ah, al		; Start toggle state
	mov	bl, al
	or	ecx, ecx
	jz	short _d4ms1
	inc	ecx		; Throwaway first toggle
_d4ms1:	
	;in	al, PORTB	; Read system control port
	mov	dx, PORTB
	mov	ah, 0  ; read port, byte
	int	34h

	and	al, REFRESH_STATUS ; Refresh toggles 15.085 microseconds
	;cmp	ah, al
	cmp	bl, al
	je	short _d4ms1	; Wait for state change

	;mov	ah, al		; Update with new state
	mov	bl, al
	dec	ecx
	jnz	short _d4ms1

	pop	edx
        pop	ebx
	pop	ecx
        pop	eax

        retn

;-----------------------------------------------------------------------------

	; 10/02/2025
	; 05/02/2025 - ac97play.s

; returns AL = current index value
getCurrentIndex:
	mov	dx, [NABMBAR]
	add	dx, PO_CIV_REG
	;in	al, dx
	mov	ah, 0 ; read port, byte
	int	34h
uLVI2:
	retn

;-----------------------------------------------------------------------------

	; 10/02/2025
	; 05/02/2025 - ac97play.s

updateLVI:
	mov	dx, [NABMBAR]
	add	dx, PO_CIV_REG
	; (Current Index Value and Last Valid Index value)
	;in	ax, dx
	mov	ah, 2 ; read port, word
	int	34h

	cmp	al, ah ; is current index = last index ?
	jne	short uLVI2

	call	getCurrentIndex
 
	test	byte [flags], ENDOFFILE
	;jnz	short uLVI1
	jz	short uLVI0  ; 08/11/2023

	push	eax
	mov	dx, [NABMBAR]
	add	dx, PO_SR_REG  ; PCM out status register
	;in	ax, dx
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

;-----------------------------------------------------------------------------

	; 10/02/2025
	; 05/02/2025 - ac97play.s

;input AL = index # to stop on
setLastValidIndex:
	mov	dx, [NABMBAR]
	add	dx, PO_LVI_REG
        ;out	dx, al
	; al = data, byte
	mov	ah, 1 ; write port, byte
	int	34h
	retn

;=============================================================================
;	Detect (& Enable) Audio Device
;=============================================================================

	; 10/02/2025

detect_audio_device:

	; check for SB16 at first
	call	DetectSB16
	jnc	short detected
	
	call	DetectAC97
	jc	short not_detected

	inc	byte [audio_hardware] ; 2 = AC'97
detected:
	inc	byte [audio_hardware] ; 1 = SB16
	
not_detected:			      ; 0 = none
	retn

;=============================================================================
;	Detect AC'97 Hardware
;=============================================================================

	; 10/02/2025
	; 05/02/2025 - ac97play.s

DetectAC97:
DetectICH:
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

	mov	[bus_dev_fn], eax
	mov	[dev_vendor], edx

	; get ICH base address regs for mixer and bus master

        mov     al, NAMBAR_REG
        call    pciRegRead16		; read PCI registers 10-11
        ;and    dx, IO_ADDR_MASK 	; mask off BIT0
	and	dl, 0FEh

        mov     [NAMBAR], dx		; save audio mixer base addr

	mov     al, NABMBAR_REG
        call    pciRegRead16
        ;and    dx, IO_ADDR_MASK
	and	dl, 0C0h

        mov     [NABMBAR], dx		; save bus master base addr

	mov	al, AC97_INT_LINE ; Interrupt line register (3Ch)
	call	pciRegRead8
	
	mov	[ac97_int_ln_reg], dl

	;clc

	retn

;-----------------------------------------------------------------------------
;
;-----------------------------------------------------------------------------

	; 10/02/2025
	; 05/02/2025 - ac97play.s

; --------------------------------------------------------
; Ref: 27/05/2024 - (TRDOS 386 Kernel) audio.s
; --------------------------------------------------------

NOT_PCI32_PCI16	EQU 03FFFFFFFh ; NOT BIT31+BIT30
NOT_BIT31 EQU 7FFFFFFFh

pciFindDevice:
	; scan through PCI space looking for a device+vendor ID
	;
	; Entry: EAX=Device+Vendor ID
	;
	; Exit: EAX=PCI address if device found
	;	EDX=Device+Vendor ID
	;       CY clear if found, set if not found. EAX invalid if CY set.
	;
	; Destroys: ebx, edi


	mov	ebx, eax
	mov	edi, 80000000h
nextPCIdevice:
	mov 	eax, edi	; read PCI registers
	call	pciRegRead32

	cmp	edx, ebx
	je	short PCIScanExit ; found

	cmp	edi, 80FFF800h
	jnb	short pfd_nf	; not found
	add	edi, 100h
	jmp	short nextPCIdevice
pfd_nf:
	stc
	retn
PCIScanExit:
	;pushf
	mov	eax, NOT_BIT31
	and	eax, edi	; return only bus/dev/fn #
	retn

;-----------------------------------------------------------------------------

	; 10/02/2025
pciRegRead:
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
	mov	ebx, eax		; save eax, dh
	mov     cl, dh

	and     eax, NOT_PCI32_PCI16	; clear out data size request
	or      eax, BIT31		; make a PCI access request
	; (FASM)
	;and	al, NOT 3 ; 0FCh
	; (NASM)
	and	al, ~3 ; 0FCh		; force index to be dword

        mov     dx, PCI_INDEX_PORT
        ;out	dx, eax			; write PCI selector
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
	mov	ah, 2 ; read port, word
	; dx = port number
	int	34h

	mov     dx, ax			; return 16 bits of data
	jmp	short _pregr2
_pregr1:
	;in	eax, dx			; return 32 bits of data
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

;-----------------------------------------------------------------------------

	; 10/02/2025
pciRegWrite:
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
	; (FASM)
	;and	al, NOT 3 ; 0FCh
	; (NASM)
	and	al, ~3 ; 0FCh		; force index to be dword

        mov     dx, PCI_INDEX_PORT
	;out	dx, eax			; write PCI selector
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

;-----------------------------------------------------------------------------
; ac97.inc (11/11/2023)
;-----------------------------------------------------------------------------

; 10/02/2025
; 07/02/2025 - twavplay.asm
; 05/02/2025 - cgaplay.s

; special characters
LF      EQU 10
CR      EQU 13

; PCI stuff

BIT0  EQU 1
BIT1  EQU 2
BIT2  EQU 4
BIT8  EQU 100h
BIT9  EQU 200h
BIT28 EQU 10000000h
BIT30 EQU 40000000h
BIT31 EQU 80000000h

BUP		equ	BIT30		; Buffer Underrun Policy.
					; if this buffer is the last buffer
					; in a playback, fill the remaining
					; samples with 0 (silence) or not.
					; It's a good idea to set this to 1
					; for the last buffer in playback,
					; otherwise you're likely to get a lot
					; of noise at the end of the sound.

RR		equ	BIT1		; reset registers. Nukes all regs
                                        ; except bits 4:2 of this register.
                                        ; Only set this bit if BIT 0 is 0
RPBM		equ	BIT0		; Run/Pause
					; set this bit to start the codec!
IO_ENA		EQU	BIT0		; i/o decode enable
BM_ENA		EQU	BIT2		; bus master enable

PCI_INDEX_PORT  EQU     0CF8h
PCI_DATA_PORT   EQU     0CFCh
PCI32           EQU     BIT31           ; bitflag to signal 32bit access
PCI16           EQU     BIT30           ; bitflag for 16bit access

AC97_INT_LINE	equ	3Ch		; AC97 Interrupt Line register offset

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

NAMBAR_REG	equ	10h		; native audio mixer BAR
NABMBAR_REG	equ	14h		; native audio bus mastering BAR

CODEC_MASTER_VOL_REG	equ	02h	; master volume
CODEC_MASTER_TONE_REG	equ	08h	; master tone (R+L)
CODEC_PCM_OUT_REG 	equ	18h     ; PCM output volume
CODEC_EXT_AUDIO_REG	equ	28h	; extended audio
CODEC_EXT_AUDIO_CTRL_REG equ	2Ah	; extended audio control
CODEC_PCM_FRONT_DACRATE_REG equ	2Ch	; PCM out sample rate

; ICH supports 3 different types of register sets for three types of things
; it can do, thus:
;
; PCM in (for recording) aka PI
; PCM out (for playback) aka PO
; MIC in (for recording) aka MC

PI_BDBAR_REG	equ	0		; PCM in buffer descriptor BAR
PO_BDBAR_REG	equ	10h		; PCM out buffer descriptor BAR

GLOB_CNT_REG	equ	2Ch		; Global control register
GLOB_STS_REG 	equ	30h		; Global Status register (RO)

PI_CR_REG 	equ	0Bh		; PCM in Control Register
PO_CR_REG	equ	1Bh		; PCM out Control Register
MC_CR_REG	equ	2Bh		; MIC in Control Register

PCI_CMD_REG	EQU	04h		; reg 04h, command register

CTRL_ST_CREADY		equ	BIT8+BIT9+BIT28 ; Primary Codec Ready
CODEC_REG_POWERDOWN	equ	26h

PO_CIV_REG	equ	14h		; PCM out current Index value (RO)
PO_LVI_REG	equ	15h		; PCM out Last Valid Index
PO_SR_REG	equ	16h		; PCM out Status register

BDL_SIZE	equ	32*8		; Buffer Descriptor List size

; 07/02/2025 - twavplay.asm
PO_PICB_REG	equ 18h	; PCM Out Position In Current Buffer Register

;-----------------------------------------------------------------------------

; 06/05/2025

; 22/12/2024
align 4

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

	dd 0

;=============================================================================
;	Detect Sound Blaster 16 sound card (or compatible hardware)
;=============================================================================

	; 10/02/2025
	; 09/02/2025 - twavplay.asm
	; 20/10/2017 - playwav.s

DetectSB16:
	; Ref: TRDOS 386 Kernel v2.0.9 audio.s (06/06/2024)
	;      DetectSB procedure (06/08/2022, v2.0.5)
ScanPort:
	mov	bx, 0210h	; start scanning ports
				; 210h, 220h, .. 260h
ResetDSP:
	mov	dx, bx		; try to reset the DSP.
	add	dl, 06h

	mov	al, 1
	;out	dx, al
	mov	ah, 1 ; outb
	int	34h

	;in	al, dx
	;in	al, dx
	;in	al, dx
	;in	al, dx

	mov	ah, 0 ; inb
	int	34h
	;mov	ah, 0 ; inb
	int	34h

	xor     al, al
	;out	dx, al
	mov	ah, 1 ; outb
	int	34h

	;add     dx, 08h
	; 10/02/2025
	add	dl, 08h
	;mov	cx, 100
	mov	cx, 32
	sub	ah, ah ; 0
WaitID:
	;in	al, dx
	int	34h  ;ah = 0 ; inb
	or      al, al
	js      short GetID
	loop    WaitID
	jmp     short NextPort
GetID:
	;sub	dx, 04h
	; 10/02/2025
	sub	dl, 04h
	;in	al, dx
	int	34h  ;ah = 0 ; inb
	cmp     al, 0AAh
	je      short Found
	;add	dx, 04h
	; 10/02/2025
	add	dl, 04h	
	loop    WaitID
NextPort:
	;add	bx, 10h		; if not response,
	add	bl, 10h
	;cmp	bx, 260h	; try the next port.
	cmp	bl, 60h
	jbe     short ResetDSP
	stc
	retn
Found:
	mov     [audio_io_base], bx ; SB Port Address Found!
ScanIRQ:
SetIrqs:
	sub 	al, al ; 0
	mov 	[IRQnum], al ; reset
	;mov	[audio_intr], al

	; ah > 0 -> set IRQ vector
	; al = IRQ number
	mov	ax, 105h ; IRQ 5
	mov	edx, IRQ5_srb
	call	set_hardware_int_vector

	mov	ax, 107h ; IRQ 7
	mov	edx, IRQ7_srb
	call	set_hardware_int_vector

	mov     dx, [audio_io_base] ; tells to the SB to
	;add	dx, 0Ch		    ; generate a IRQ!
	add	dl, 0Ch
WaitSb:
	;in	al, dx
	mov	ah, 0 ; inb
	int	34h
	or      al, al
	js      short WaitSb
	mov     al, 0F2h
	;out	dx, al
	mov	ah,1  ; outb
	int	34h	

	xor	ecx, ecx	; wait until IRQ level
	;mov	ecx, 65536
WaitIRQ: 
	; 10/02/2025
	;mov	al, [IRQnum]
	;cmp    al, 0 ; is changed or timeout.
	;ja	short IrqOk
	mov	al, [IRQ5_srb]
	cmp	al, 5
	je	short IrqOk
	mov	al, [IRQ7_srb]
	cmp	al, 7
	je	short IrqOk	
	dec	cx
	;dec	ecx
	jnz	short WaitIRQ
	jmp	short RestoreIrqs
IrqOk:
	;;;
	; 10/02/2025
	mov	[IRQnum], al
	mov	[audio_intr], al
	mov 	dx, [audio_io_base]
	;add	dx, 0Eh
	add	dl, 0Eh ; 8bit DMA-mode int ack
	;in	al, dx
	mov	ah, 0 ; inb
	int	34h

	; 10/02/2025
	; 16bit DMA mode intr ack is
	; not necessary for initial IRQ scan
%if 0
	inc	edx ; 0Fh ; 16bit DMA-mode int ack
	;in	al, dx	; SB 16 acknowledge.
	;mov	ah, 0 ; inb
	int	34h
%endif
	;;;
	;mov	al, 20h
	;out	20h, al	; Hardware acknowledge.
RestoreIrqs:
	; ah = 0 -> reset IRQ vector
	; al = IRQ number
	mov	ax, 5 ; IRQ 5
	call	set_hardware_int_vector
	mov	ax, 7 ; IRQ 7
	call	set_hardware_int_vector

	cmp     byte [IRQnum], 1 ; IRQ level was changed?
	
	retn

;-----------------------------------------------------------------------------
;
;-----------------------------------------------------------------------------

	; 10/02/2025
	; 20/10/2027 - playwav.s

	; syscalbac:
	; ----------
	; Link or unlink IRQ callback service to/from user (ring 3)

	; sycalbac Input: 
	; 	bl = IRQ number
	;	bh = 0 -> reset/unlink
	;	bh = 1 -> set/link
	;	cl = signal response/return byte value (to user)
	;	bh = 3 -> counter (start value is cl+1)
	; 	edx = signal response (return) byte address
	;	      or callback service address

set_hardware_int_vector:
	or	ah, ah
	jnz	short shintv_1 ; set user's audio interrupt handler

rhintv_1:		
	cmp	al, 5
	jne	short rhintv_2

	; Signal Response Byte 
	sys	_calbac, 5	; unlink IRQ 5

	retn

rhintv_2:
	; al = 7

	; Signal Response Byte
	sys	_calbac, 7	; unlink IRQ 7

	retn

shintv_1:
	cmp	al, 5
	jne	short shintv_2

	; LINK SIGNAL RESPONSE/RETURN BYTE TO REQUESTED IRQ

	; edx = srb address (IRQnum or IRQ5_srb)

	sys	_calbac, 105h, 5 ; IRQ 5

	retn

shintv_2:	
	; al = 7

	; LINK SIGNAL RESPONSE/RETURN BYTE TO REQUESTED IRQ

	; edx = srb address (IRQnum or IRQ7_srb)

	sys	_calbac, 107h, 7 ; IRQ 7

	retn

;-----------------------------------------------------------------------------

	; 10/02/2025
IRQ5_srb: db 0
IRQ7_srb: db 0

;=============================================================================
; settextmode - restore the VGA 80x25x16 text mode
;=============================================================================
	
	; 10/02/2025
settextmode:
	mov	ax, 0003h
	;int	10h
	int	31h ; TRDOS 386 - Video interrupt
	retn
	
;=============================================================================
; drawscopes - draw wave/voice sample scopes
;=============================================================================
	
	; 10/02/2025 - twavply3.s
	; 09/02/2025 - twavplay.asm (16bit)
	; 05/02/2025 - twavplay2.s
drawscopes:
	call	get_current_sound_data
	mov	esi, g_buffer

	xor     ecx, ecx
	xor     edx, edx
	xor	edi, edi
drawscope0:
	lodsw
	xor	ah, 80h
	movzx	ebx, ah	; Left Channel
	shl	ebx, 1
	mov	ax, [RowOfs+ebx]
	mov	[NewScope_L+edi], ax
	xor	bh, bh
	lodsw
	xor	ah, 80h
	mov	bl, ah	; Right Channel
	shl	ebx, 1
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

	;mov	dx, 3CEh
	mov	dl, 0CEh
	mov	al, 08h
       ;out	dx, al
        mov	ah, 1 ; outb
	int	34h

	inc	edx

	xor	esi, esi
	mov	ebx, 0A0645h
drawscopel4:
	mov     al, 80h
drawscopel2:
	push	eax ; **
	push	edx ; *
	;out	dx, al
	mov	ah, 1 ; outb
	int	34h

	;mov	ecx, 32
	mov	cl, 32
	mov	ax, 0FF00h
drawscopel3:
        mov	di, [OldScope_L+esi]
	mov	dx, [NewScope_L+esi]
        cmp	edi, edx
        je	short drawscopef3
	mov	[ebx+edi], al ; L
	mov	[ebx+edx], ah ; L
        mov     [OldScope_L+esi], dx
drawscopef3:
	mov	di, [OldScope_R+esi]
	mov	dx, [NewScope_R+esi]
	cmp	edi, edx
	je	short drawscopef4
	mov	[ebx+edi+38], al ; R
	mov	[ebx+edx+38], ah ; R
	mov     [OldScope_R+esi], dx
drawscopef4:
	add	esi, 2*8
	inc	ebx
	loop    drawscopel3

        pop     edx ; *
        pop     eax ; **
	sub	esi, 2*256-2
	sub	ebx, 32
        shr     al, 1
        jnz	short drawscopel2
	clc
        retn

;=============================================================================
; Get Current Sound Data
;=============================================================================
; Reference: TRDOS 386 v2.0.9 Kernel - audio.s file (28/01/2025)

	; 10/02/2025 - twavplay.s
	; 08/02/2025 - twavplay.asm (16bit)

	; !!! 18.2 block/second buffer sizing for proper wave scopes !!!
	; (wave graphics synchronization) 

get_current_sound_data:
	; get current sound (PCM out) data for graphics

	mov	edi, g_buffer

	cmp	byte [audio_hardware], 1
	ja	short ac97_current_sound_data

;-----------------------------------------------------------------------------
	
	; 10/02/2025
	; 08/02/2025 - twavplay.asm (16bit)

sb16_current_sound_data:
	mov	ecx, [g_samples]
	
	cmp	byte [WAVE_BitsPerSample], 16
	jne	short sb16_gcd_1 ; 8 bit DMA channel
	;in	al, 0C6h ; DMA channel 5 count register
	mov	dx, 0C6h
	mov	ah, 0 ; inb
	int	34h
	; AL = Low Byte of the word count
	;;mov	ah, al
	shl	eax, 24	; (*)
	;in	al, 0C6h
	;mov	dx, 0C6h
	;mov	ah, 0 ; inb
	int	34h
	; AL = High Byte of the word count
	;;xchg	ah, al
	;rol	eax, 8	; (*)
	;shl	ax, 1 ; word count -> byte count
	rol	eax, 9
	jmp	short sb16_gcd_2

sb16_gcd_1:
	;in	al, 03h ; DMA channel 1 count register
	mov	dx, 03h
	mov	ah, 0 ; inb
	int	34h
	; AL = Low Byte of the byte count
	;;mov	ah, al
	shl	eax, 24	; (**)
	;in	al, 03h
	;mov	dx, 03h
	;mov	ah, 0 ; inb
	int	34h
	; AL = High Byte of the byte count
	;;xchg	ah, al
	rol	eax, 8	; (**)

sb16_gcd_2:
	; eax = remain count
	mov	ebx, [buffersize] ; half buffer size
	cmp	eax, ebx
	jna	short sb16_gcd_3 ; 2nd half
	xor	ebx, ebx ; 1st half
sb16_gcd_3:
	lea	esi, [dma_buffer+ebx] ; start of 1st half or 2nd half

	; esi = dma buffer offset
	; ecx = load (source) count
	; edi = g_buffer

	jmp	word [sound_data_copy]

;-----------------------------------------------------------------------------

	; 10/02/2025
	; 09/02/2025 - twavplay.asm (16bit)

ac97_current_sound_data:
	;;mov	ecx, 1024 ; always 16bit stereo
	;mov	ecx, 512
	mov	ecx, 256

	mov	dx, PO_CIV_REG ; Position In Current Buff Reg
	add	dx, [NABMBAR]
	;in	al, dx	; current index value
	mov	ah, 0 ; inb ; read port, byte
	int	34h
	;mov	ebx, WAV_BUFFER_1
	mov	esi, WAV_BUFFER_1
	test	al, 1
	jz	short ac97_gcd_1
	;mov	ebx, WAV_BUFFER_2
	mov	esi, WAV_BUFFER_2
ac97_gcd_1:
	;mov	dx, PO_PICB_REG ; Position In Current Buff Reg
	;add	dx, [NABMBAR]
	;;in	ax, dx	; remain words
	;mov	ah, 2 ; inw ; read port, word
	;int	34h
	;;shl	eax, 1	; remain bytes
ac97_gcd_2:
	;xor	esi, esi ; 1st half
ac97_gcd_3:
	;mov	esi, [buffersize] ; 16 bit sample count
	;sub	esi, eax
	;shl	esi, 1 ; byte offset

	; esi = 0, start of the wave/pcm data (dma) buffer
	; (buffer size is adjusted for playing in 1/18.2 second) 

	;add	esi, ebx

	; ds:si = dma buffer offset
	; cx = load (source) count
	; es:di = g_buffer

	; AC97 dma buffer contains 16bit stereo samples (only)
	; copy samples to g_buffer

	;shr	ecx, 1
	;rep	movsw

	;shr	ecx, 2
	rep	movsd

	retn

;-----------------------------------------------------------------------------

	; 10/02/2025
	; 09/02/2025 - twavplay.asm (16bit)
sdc_16bit_stereo:
	; esi = dma buffer offset
	; ecx = load (source) count = 1024
	; edi = g_buffer
	;shr	ecx, 1
	;rep	movsw
	shr	ecx, 2
	rep	movsd
	retn

;-----------------------------------------------------------------------------

	; 10/02/2025
	; 09/02/2025 - twavplay.asm (16bit)
sdc_16bit_mono:
	; esi = dma buffer offset
	; ecx = load (source) count = 512
	; edi = g_buffer
	shr	ecx, 1
sdc_16bm_loop:
	lodsw
	stosw
	stosw
	loop	sdc_16bm_loop
	retn

;-----------------------------------------------------------------------------

	; 10/02/2025
	; 09/02/2025 - twavplay.asm (16bit)
sdc_8bit_stereo:
	; esi = dma buffer offset
	; ecx = load (source) count = 512
	; edi = g_buffer

	; convert to 16 bit sample
sdc_8bs_loop:
	lodsb
	sub	al, 80h ; middle = 0, min = -128, max = 127
	shl	ax, 8
	stosw
	loop	sdc_8bs_loop
	retn

;-----------------------------------------------------------------------------

	; 10/02/2025
	; 09/02/2025 - twavplay.asm (16bit
sdc_8bit_mono:
	; si = dma buffer offset
	; cx = load (source) count = 256
	; di = g_buffer

	; convert to 16 bit sample
sdc_8bm_loop:
	lodsb
	sub	al, 80h ; middle = 0, min = -128, max = 127
	shl	ax, 8
	stosw	; L
	; convert to stereo
	stosw	; R
	loop	sdc_8bm_loop
	retn

;-----------------------------------------------------------------------------

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

	; 10/02/2025
	; 05/02/2025 - twavply2.s

putlbm:
	mov	esi, LOGO_ADDRESS
	
	;pushad

; check if this is a valid IFF/ILBM Deluxe Paint file

	;cmp	dword [esi+Form.ID], ID_FORM
	;jne	short putlbmd0
	;cmp	dword [esi+Form.Type], ID_ILBM
	;jne	short putlbmd0

; get the IFF/ILBM file length in bytes

	mov	eax, [esi+Form.Length]
	bswap	eax
	mov	ecx, eax

; decrease the file length and updates the file pointer

	sub	ecx, 4
	add	esi, Form.size

; IFF/ILBM main parser body loop

putlbml0:
	test	ecx, ecx
	jle	short putlbmd1

; get the next chunk ID and length in bytes

	mov	ebx, [esi+Chunk.ID]
	mov	eax, [esi+Chunk.Length]
	bswap	eax
	xchg	ebx, eax
	add	esi, Chunk.size

; word align the chunk length and decrease the file length counter

	inc	ebx
	and	bl, 0FEh ; ~1
	sub	ecx, Chunk.size
	sub	ecx, ebx

; check for the BMHD/CMAP/BODY chunk headers

	cmp	eax, ID_BMHD
	je	short putlbmf0
	cmp	eax, ID_CMAP
	je	short putlbmf1
	cmp	eax, ID_BODY
	je	short putlbmf2

; advance to the next IFF/ILBM chunk structure

putlbmc0:
	add	esi, ebx
	jmp	short putlbml0

putlbmd0:
	stc
	;popad
	retn

; process the BMHD bitmap header chunk

putlbmf0:
	cmp	byte [esi+BMHD.Planes], 4
	jne	short putlbmd0
	cmp	byte [esi+BMHD.Compression], 1
	jne	short putlbmd0
	cmp	byte [esi+BMHD.Pad], 0
	jne	short putlbmd0
	movzx	eax, word [esi+BMHD.Width]
	xchg	al, ah
	add	eax, 7
	shr	eax, 3
	mov	[picture.width], eax
	movzx	eax, word [esi+BMHD.Height]
	xchg	al, ah
	mov	[picture.height], eax
	jmp	short putlbmc0

putlbmd1:
	clc
	;popad
	retn

; process the CMAP colormap chunk

putlbmf1:
	mov	dx, 3C8h
	xor	al, al
	;out	dx, al
	mov	ah, 1 ; outb
	int	34h
	;inc	dx
	inc	edx
putlbml1:
	mov	al, [esi]
	shr	al, 2
	;out	dx, al
	;mov	ah, 1 ; outb
	int	34h ; IOCTL interrupt (IN/OUT)
	inc	esi
	dec	ebx
	jg	short putlbml1
	jmp	putlbml0

; process the BODY bitmap body chunk

putlbmf2:
	pushad
	mov	edi, 0A0000h
	;cld
	mov	dx, 3CEh
	;mov	ax, 0FF08h
	;out	dx, ax
	mov	bx, 0FF08h
	mov	ah, 3 ; outw
	int	34h ; IOCTL interrupt (IN/OUT)
	;mov	dx, 3C4h
	mov	dl, 0C4h
	mov	al, 02h
	;out	dx, al
	mov	ah, 1 ; outb
	int	34h ; IOCTL interrupt (IN/OUT)
	;inc	dx
	inc	edx
	mov	ecx, [picture.height]
putlbml2:
	push	ecx
	mov	al, 11h
putlbml3:
	push	eax
	push	edi
	;out	dx, al
	mov	ah, 1 ; outb
	int	34h ; IOCTL interrupt (IN/OUT)
	mov	ebx, [picture.width]
putlbml4:
	lodsb
	xor	ecx, ecx
	test	al, al
	jl	short putlbmf3
	;movzx	ecx, al
	mov	cl, al
	inc	ecx
	sub	ebx, ecx
	rep	movsb
	jmp	short putlbmc4
putlbmf3:
	neg	al
	;movzx	ecx, al
	mov	cl, al
	inc	ecx
	sub	ebx, ecx
	lodsb
	rep	stosb
putlbmc4:
	test	ebx, ebx
	jg	short putlbml4
	pop	edi
	pop	eax
	add	al, al
	jnc	short putlbml3
	add	edi, 80
	pop	ecx
	loop	putlbml2
	popad
	jmp	putlbmc0

;------------------------------------------------------------------------------
;------------------------------------------------------------------------------

align 2

; 22/10/2017
LOGO_ADDRESS:
; 27/10/2017
incbin "TINYPLAY.LBM"

;=============================================================================
;		preinitialized data
;=============================================================================
	
		db 0
FileHandle:	dd -1
		db 0

Credits:	db 'Tiny WAV Player for TRDOS 386 by Erdogan Tan. '
		db 'February 2025.',10,13,0
		db '09/02/2025',10,13
reset:		db 0

msg_usage:	db 10,13
		db 'usage: twavplay filename.wav',10,13,0

noDevMsg:	db 10,13
		db 'Error: Unable to find a proper audio device !'
		db 10,13,0

noFileErrMsg:	db 10,13
		db 'Error: file not found.',10,13,0

not_valid_wavf:	db 10,13
		db 'Not a proper/valid WAV file !',10,13,0

		; 08/02/2025
sb16_init_err_msg:
		db 10,13
		db 'Sound Blaster 16 initialization error !',10,13,0
ac97_init_err_msg:
		db 10,13
		db 'AC97 hardware initialization error !',10,13,0
		
;init_err_msg:	;db 10,13
		;db 'Audio system initialization error !',10,13,0

msg_no_vra:	db 10,13
		db "No VRA support ! Only 48 kHZ sample rate supported !"
		db 10,13,0

trdos386_err_msg:
		db 10,13
		db 'TRDOS 386 System call error !',10,13,0

hex_chars:	db "0123456789ABCDEF", 0

msgAC97Info:	db 0Dh, 0Ah
		db "AC97 Audio Controller & Codec Info", 0Dh, 0Ah
		db "Vendor ID: "
msgVendorId:	db "0000h Device ID: "
msgDevId:	db "0000h", 0Dh, 0Ah
		db "Bus: "
msgBusNo:	db "00h Device: "
msgDevNo:	db "00h Function: "
msgFncNo:	db "00h"
		db 0Dh, 0Ah

		db "NAMBAR: "
msgNamBar:	db "0000h  "
		db "NABMBAR: "
msgNabmBar:	db "0000h  IRQ: "
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

msgVRAheader:	db "VRA support: "
		db 0	
msgVRAyes:	db "YES", 0Dh, 0Ah, 0
msgVRAno:	db "NO ", 0Dh, 0Ah
		db "(Interpolated sample rate playing method)"
		db 0Dh, 0Ah, 0

msgSB16Info:	db 0Dh, 0Ah
		db " Audio Hardware: Sound Blaster 16", 0Dh, 0Ah
		db "      Base Port: "
msgBasePort:
		db "000h", 0Dh, 0Ah
		db "            IRQ: "
msgSB16IRQ:
		db 30h
		db 0Dh, 0Ah, 0

; 07/02/2025
msgPressAKey:	db 0Dh, 0Ah
		db ' ... press a key to continue ... '
		db 0Dh, 0Ah, 0

; 07/02/2025
half_buffer:	db 1

vra_ok:		db '.. VRA OK ..', 0Dh, 0Ah,0

;=============================================================================
;		uninitialized data
;=============================================================================

; 10/02/2025
; 09/02/2025

; BSS

bss_start:

ABSOLUTE bss_start

alignb 4

;------------------------------------------------------------------------------
; IFF/ILBM DATA
;------------------------------------------------------------------------------

picture.width:	resd 1 	; current picture width and height
picture.height:	resd 1

;------------------------------------------------------------------------------

;;;;;;;
WAVFILEHEADERbuff:
RIFF_ChunkID:	resd 1	; Must be equal to "RIFF" - big-endian
			; 0x52494646
RIFF_ChunkSize: resd 1	; Represents total file size, not
        		; including the first 2 fields
			; (Total_File_Size - 8), little-endian
RIFF_Format:	resd 1	; Must be equal to "WAVE" - big-endian
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
WAVE_ByteRate:	resd 1	; SampleRate * NumChannels * BytesPerSample
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
;;;;;;;

;------------------------------------------------------------------------------

wav_file_name:	resb 80 ; wave file, path name (<= 80 bytes)

		resw 1

;------------------------------------------------------------------------------

ac97_int_ln_reg:
audio_intr:	resb 1
VRA:		resb 1	; Variable Rate Audio Support Status
fbs_shift:	resb 1
flags:		resb 1

dev_vendor:	resd 1
bus_dev_fn:	resd 1
audio_io_base:		; Sound Blaster 16 base port address (220h)
NAMBAR:		resw 1
NABMBAR:	resw 1

audio_hardware:	resb 1
IRQnum:		resb 1
volume:		resb 1
stopped:	resb 1

;------------------------------------------------------------------------------

alignb 16

RowOfs:		resw 256

NewScope_L:	resw 256
NewScope_R:	resw 256
OldScope_L:	resw 256
OldScope_R:	resw 256

;------------------------------------------------------------------------------

loadfromwavfile:
		resd 1	; 'loadfromfile' or load+conversion proc address
loadsize:	resd 1	; (.wav file) read count (bytes) per one time
buffersize:	resd 1	; 16 bit samples (not bytes)

count:		resd 1	; byte count of one (wav file) read
LoadedDataBytes:
		resd 1	; total read/load count
		
timerticks:	resd 1	; (to eliminate excessive lookup of events in tuneloop)
			; (in order to get the emulator/qemu to run correctly)

audio_buffer:	resd 1	; temporary (saving) area for AC97 DMA buffer address

_bdl_buffer:	resd 1	; physcal address of buffer descriptor list (AC97)	
DMA_phy_buff:	resd 1	; physical address of 'dma_buffer' (SB16)

bss_end:

;------------------------------------------------------------------------------

sound_data_copy:	; address pointer for g_buffer fast (conversion) copy
		resd 1
g_samples:	resd 1	; count of samples for g_buffer copy/transfer

alignb 16

g_buffer:	resb 1024 ; 16 bit stereo samples for wave graphics display

;------------------------------------------------------------------------------

alignb 4096

; 256 byte buffer for descriptor list
BDL_BUFFER:	resb 256
		resb 4096-256
; DMA buffers (AC97) - ((max. 10600 bytes will be used per buffer))
WAV_BUFFER_1:	resb 12288 ; 3*4096 ; 1st wav/pcm data buffer
WAV_BUFFER_2:	resd 12288 ; 3*4096 ; segment of 2nd wav/pcm data buffer

;------------------------------------------------------------------------------

alignb 65536

temp_buffer:	
		; max. 10600 bytes (no-VRA AC97)
		; 10600: 44.1 kHZ stereo 2438 samples, 2650 (48kHZ) samples
		; 10656: 11.025 kHZ stereo 612 samples, 2664 (48kHZ) samples
		; 10508: 22.050 kHZ stereo 1207 samples, 2627 (48kHZ) samples
		; 10544: 24 kHZ stereo 1318 samples, 2636 (48kHZ) samples
		; 10548: 32 kHZ stereo 1758 samples, 2637 (48kHZ) samples
		; 10548: 16 kHZ stereo 879 samples, 2637 (48kHZ) samples
		; 10544: 12 kHZ stereo 659 samples, 2636 (48kHZ) samples
		; 10560: 8 kHZ stereo 440 samples, 2640 (48kHZ) samples
		
dma_buffer:	; max. 21120 bytes (SB16)
		resb 10560
		resb 10560
		resb 3456 ; memory allocation = 6*4096 bytes

;------------------------------------------------------------------------------
