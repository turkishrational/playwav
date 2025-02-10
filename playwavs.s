; ****************************************************************************
; playwav6.s (for TRDOS 386)
; ----------------------------------------------------------------------------
; PLAYWAV6.PRG ! AC'97 (ICH) .WAV PLAYER program by Erdogan TAN
;
; 25/11/2023
;
; [ Last Modification: 02/02/2025 ]
;
; Modified from PLAYWAV5.PRG .wav player program by Erdogan Tan, 18/08/2020
;
; Assembler: NASM version 2.15
;	     nasm playwav6.s -l playwav6.txt -o PLAYWAV6.PRG	
; ----------------------------------------------------------------------------
; Derived from '.wav file player for DOS' Jeff Leyda, Sep 02, 2002

; previous version: playwav3.s (17/06/2017)

; CODE

; 20/10/2024
; 20/08/2024 ; TRDOS 386 v2.0.9
; TRDOS 386 system calls
_ver 	equ 0
_exit 	equ 1
_fork 	equ 2
_read 	equ 3
_write	equ 4
_open	equ 5
_close 	equ 6
_wait 	equ 7
_creat 	equ 8
_rename equ 9
_delete equ 10
_exec	equ 11
_chdir	equ 12
_time 	equ 13
_mkdir 	equ 14
_chmod	equ 15
_rmdir	equ 16
_break	equ 17
_drive	equ 18
_seek	equ 19
_tell 	equ 20
_mem	equ 21
_prompt	equ 22
_path	equ 23
_env	equ 24
_stime	equ 25
_quit	equ 26
_intr	equ 27
_dir	equ 28
_emt 	equ 29
_ldvrt 	equ 30
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
_stdio  equ 46	;  TRDOS 386 v2.0.9

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

BUFFERSIZE	equ	32768	; audio buffer size 
ENDOFFILE       equ     1	; flag for knowing end of file

[BITS 32]

[ORG 0] 

_STARTUP:
	; Prints the Credits Text.
	sys	_msg, Credits, 255, 0Bh

	; clear bss
	mov	ecx, bss_end
	mov	edi, bss_start
	sub	ecx, edi
	shr	ecx, 1
	xor	eax, eax
	rep	stosw

	; Detect (& Enable) AC'97 Audio Device
	call	DetectAC97
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
	lodsd ; mod file name address (file to be read)
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

	or	ah, ah		; if period NOT found,
	jnz	short _1 	; then add a .WAV extension.
SetExt:
	dec	edi
	mov	dword [edi], '.WAV'
	mov	byte [edi+4], 0

_1:

; 26/11/2023
%if 0
	; Allocate Audio Buffer (for user)
	;sys	_audio, 0200h, BUFFERSIZE, audio_buffer
	; 26/11/2023
	sys	_audio, 0200h, [buffersize], audio_buffer
	jnc	short _2
error_exit:
	sys	_msg, trdos386_err_msg, 255, 0Eh
	jmp	Exit
_2:
	; DIRECT CGA (TEXT MODE) MEMORY ACCESS
	; bl = 0, bh = 4
	; Direct access/map to CGA (Text) memory (0B8000h)

	sys	_video, 0400h
	cmp	eax, 0B8000h
	jne	short error_exit

	; Initialize Audio Device (bh = 3)
	sys	_audio, 0301h, 0, audio_int_handler 
;	jc	short error_exit
_3:

%endif
	call	write_audio_dev_info 

; open the file
        ; open existing file
        call    openFile ; no error? ok.
        jnc     short _gsr

; file not found!
	sys	_msg, noFileErrMsg, 255, 0Fh
_exit_:
        jmp     Exit

_gsr:  
       	call    getSampleRate		; read the sample rate
                                        ; pass it onto codec.
	;jc	Exit
	; 25/11/2023
	jc	short _exit_

	mov	[sample_rate], ax
	mov	[stmo], cl
	mov	[bps], dl

	; 26/11/2023
	mov	byte [fbs_shift], 0 ; 0 = stereo and 16 bit 
	dec	cl
	jnz	short _gsr_1 ; stereo
	inc	byte [fbs_shift] ; 1 = mono or 8 bit		
_gsr_1:	
	cmp	dl, 8 
	ja	short _gsr_2 ; 16 bit samples
	inc	byte [fbs_shift] ; 2 = mono and 8 bit
_gsr_2:	
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

	mov	[ac97_int_ln_reg], al
	mov	[dev_vendor], ebx
	mov	[bus_dev_fn], ecx
	;mov	[ac97_NamBar], dx
	;shr	dx, 16
	;mov	[ac97_NabmBar], dx
	mov	[ac97_NamBar], edx	
  
	; 06/06/2024
	;; 01/06/2024
	;; Reset Audio Device (bh = 8)
	;sys	_audio, 0800h
	;;jc	error_exit	
	;jc	short init_err

	call	write_ac97_pci_dev_info

	; 01/06/2024
	; 25/11/2023
	; Get AC'97 Codec info
	; (Function 14, sub function 1)
	sys	_audio, 0E01h
	; 06/06/2024
	jnc	short _gsr_3

	; 06/06/2024
	; a 2nd attempt
	sys	_audio, 0E01h
	jnc	short _gsr_3

	shl	eax, 1 ; clears AL BIT 0
_gsr_3:
	; Save Variable Rate Audio support bit
	and	al, 1
	mov	[VRA], al

	; 06/06/2024
	; ebx = codec vendor id1 & id2 (bx)
	call	write_codec_info

	; 25/11/2023
	call	write_VRA_info

	; 01/05/2017
	call	write_wav_file_info

	; 25/11/2023
	; ------------------------------------------

	cmp	byte [VRA], 1
	jb	short chk_sample_rate

playwav_48_khz:	
	;mov	dword [loadfromwavfile], loadFromFile
	;mov	dword [buffersize], 65536
	jmp	PlayNow

	; 01/06/2024
init_err:
	sys	_msg, msg_init_err, 255, 0Eh
	jmp	Exit

	; 02/02/2025
chk_sample_rate:
	; set conversion parameters
	; (for 8, 11.025, 16, 22.050, 24, 32 kHZ)
	mov	ax, [sample_rate]
	cmp	ax, 48000
	je	short playwav_48_khz
chk_22khz:
	cmp	ax, 22050
	jne	short chk_11khz
	cmp	byte [bps], 8
	jna	short chk_22khz_1
	mov	ebx, load_22khz_stereo_16_bit
	cmp	byte [stmo], 1 
	jne	short chk_22khz_2
	mov	ebx, load_22khz_mono_16_bit
	jmp	short chk_22khz_2
chk_22khz_1:
	mov	ebx, load_22khz_stereo_8_bit
	cmp	byte [stmo], 1 
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
	cmp	byte [bps], 8
	jna	short chk_11khz_1
	mov	ebx, load_11khz_stereo_16_bit
	cmp	byte [stmo], 1 
	jne	short chk_11khz_2
	mov	ebx, load_11khz_mono_16_bit
	jmp	short chk_11khz_2
chk_11khz_1:
	mov	ebx, load_11khz_stereo_8_bit
	cmp	byte [stmo], 1 
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
	cmp	byte [bps], 8
	jna	short chk_44khz_1
	mov	ebx, load_44khz_stereo_16_bit
	cmp	byte [stmo], 1 
	jne	short chk_44khz_2
	mov	ebx, load_44khz_mono_16_bit
	jmp	short chk_44khz_2
chk_44khz_1:
	mov	ebx, load_44khz_stereo_8_bit
	cmp	byte [stmo], 1 
	jne	short chk_44khz_2
	mov	ebx, load_44khz_mono_8_bit
chk_44khz_2:
	mov	eax, 15065 ; (655*23)
	mov	edx, 25
	mov	ecx, 23
	jmp	set_sizes 
chk_16khz:
	cmp	ax, 16000
	jne	short chk_8khz
	cmp	byte [bps], 8
	jna	short chk_16khz_1
	mov	ebx, load_16khz_stereo_16_bit
	cmp	byte [stmo], 1 
	jne	short chk_16khz_2
	mov	ebx, load_16khz_mono_16_bit
	jmp	short chk_16khz_2
chk_16khz_1:
	mov	ebx, load_16khz_stereo_8_bit
	cmp	byte [stmo], 1 
	jne	short chk_16khz_2
	mov	ebx, load_16khz_mono_8_bit
chk_16khz_2:
	mov	eax, 5461
	mov	edx, 3
	mov	ecx, 1
	jmp	set_sizes 
chk_8khz:
	cmp	ax, 8000
	jne	short chk_24khz
	cmp	byte [bps], 8
	jna	short chk_8khz_1
	mov	ebx, load_8khz_stereo_16_bit
	cmp	byte [stmo], 1 
	jne	short chk_8khz_2
	mov	ebx, load_8khz_mono_16_bit
	jmp	short chk_8khz_2
chk_8khz_1:
	mov	ebx, load_8khz_stereo_8_bit
	cmp	byte [stmo], 1 
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
	cmp	byte [bps], 8
	jna	short chk_24khz_1
	mov	ebx, load_24khz_stereo_16_bit
	cmp	byte [stmo], 1 
	jne	short chk_24khz_2
	mov	ebx, load_24khz_mono_16_bit
	jmp	short chk_24khz_2
chk_24khz_1:
	mov	ebx, load_24khz_stereo_8_bit
	cmp	byte [stmo], 1 
	jne	short chk_24khz_2
	mov	ebx, load_24khz_mono_8_bit
chk_24khz_2:
	mov	eax, 8192
	mov	edx, 2
	mov	ecx, 1
	jmp	short set_sizes 
chk_32khz:
	cmp	ax, 32000
	;jne	short vra_needed
	; 02/02/2025
	jne	short chk_12khz
	cmp	byte [bps], 8
	jna	short chk_32khz_1
	mov	ebx, load_32khz_stereo_16_bit
	cmp	byte [stmo], 1 
	jne	short chk_32khz_2
	mov	ebx, load_32khz_mono_16_bit
	jmp	short chk_32khz_2
chk_32khz_1:
	mov	ebx, load_32khz_stereo_8_bit
	cmp	byte [stmo], 1 
	jne	short chk_32khz_2
	mov	ebx, load_32khz_mono_8_bit
chk_32khz_2:
	mov	eax, 10922
	mov	edx, 3
	mov	ecx, 2
	;jmp	short set_sizes

set_sizes:
	cmp	byte [stmo], 1
	je	short ss_1
	shl	eax, 1
ss_1:
	cmp	byte [bps], 8
	jna	short ss_2
	; 16 bit samples
	shl	eax, 1
ss_2:
	mov	[loadsize], eax
	mul	edx
	;cmp	ecx, 1
	;je	short ss_3
;ss_3:
	div	ecx
	mov	cl, [fbs_shift]
	shl	eax, cl
	; 26/11/2023
	;shr	eax, 1	; buffer size is 16 bit sample count
	mov	[buffersize], eax ; buffer size in bytes
	mov	[loadfromwavfile], ebx
	jmp	short PlayNow

	;;;;
	; 02/02/2025
chk_12khz:
	cmp	ax, 12000
	jne	short vra_needed
	cmp	byte [bps], 8
	jna	short chk_12khz_1
	mov	ebx, load_12khz_stereo_16_bit
	cmp	byte [stmo], 1 
	jne	short chk_12khz_2
	mov	ebx, load_12khz_mono_16_bit
	jmp	short chk_12khz_2
chk_12khz_1:
	mov	ebx, load_12khz_stereo_8_bit
	cmp	byte [stmo], 1 
	jne	short chk_12khz_2
	mov	ebx, load_12khz_mono_8_bit
chk_12khz_2:
	mov	eax, 4096
	mov	edx, 4
	mov	ecx, 1
	jmp	set_sizes 
	;;;;

vra_needed:
	sys	_msg, msg_no_vra, 255, 07h
	jmp	Exit

	; 26/11/2023
	; 13/11/2023
loadfromwavfile:
	dd	loadFromFile
loadsize:	; read from wav file
	dd	0
buffersize:	; write to DMA buffer
	dd	65536 ; bytes

PlayNow: 

; 26/11/2023
%if 1
	; Allocate Audio Buffer (for user)
	;sys	_audio, 0200h, BUFFERSIZE, audio_buffer
	; 26/11/2023
	sys	_audio, 0200h, [buffersize], audio_buffer
	jnc	short _2

	; 26/11/2023 - temporary
	;sys	_msg, test_1, 255, 0Ch

error_exit:
	sys	_msg, trdos386_err_msg, 255, 0Eh
	jmp	Exit
_2:
	; DIRECT CGA (TEXT MODE) MEMORY ACCESS
	; bl = 0, bh = 4
	; Direct access/map to CGA (Text) memory (0B8000h)

	sys	_video, 0400h
	cmp	eax, 0B8000h
	jne	short error_exit

	; 01/06/2024
	; Initialize Audio Device (bh = 3)
	sys	_audio, 0301h, 0, audio_int_handler 
	;jc	short error_exit
	jc	init_err
_3:

%endif

;
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

	sys	_msg, nextline, 255, 07h ; 01/05/2017

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
Exit:  
        call    closeFile
         
	sys	_exit	; Bye!
here:
	jmp	short here

pmsg_usage:
	sys	_msg, msg_usage, 255, 0Bh
	jmp	short Exit

	; 25/11/2023
DetectAC97:
	; Detect (BH=1) AC'97 (BL=2) Audio Device
        sys	_audio, 0102h

; 01/06/2024
%if 0
	jc	short DetectAC97_retn

	; 25/11/2023
	; Get AC'97 Codec info
	; (Function 14, sub function 1)
	sys	_audio, 0E01h
	; Save Variable Rate Audio support bit
	and	al, 1
	mov	[VRA], al
%endif

DetectAC97_retn:
	retn

;open or create file
;
;input: ds:dx-->filename (asciiz)
;       al=file Mode (create or open)
;output: none  cs:[FileHandle] filled
;
openFile:
	;mov	ah, 3Bh	; start with a mode
	;add	ah, al	; add in create or open mode
	;xor	ecx, ecx
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
        ;xor	ecx, ecx
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

audio_int_handler:
	; 13/12/2024
	; 18/08/2020 (14/10/2020, 'wavplay2.s')

	;mov	byte [srb], 1 ; interrupt (or signal response byte)
	
	;cmp	byte [cbs_busy], 1
	;jnb	short _callback_bsy_retn
	
	;mov	byte [cbs_busy], 1

	; 13/12/2024
	;mov	al, [half_buff]
	;
	;cmp	al, 1
	;jb	short _callback_retn

	; 18/08/2020
	;mov	byte [srb], 1
	; 13/12/2024
	inc	byte [srb]

	; 13/12/2024
	;xor	byte [half_buff], 3 ; 2->1, 1->2

	; 13/12/2024
	;add	al, '0'
;tL0:	; 26/11/2023
	;mov	ah, 4Eh
	;mov	ebx, 0B8000h ; video display page address
	;mov	[ebx], ax ; show playing buffer (1, 2)
;_callback_retn:
	;;mov	byte [cbs_busy], 0
;_callback_bsy_retn:
	sys	_rele ; return from callback service 
	; we must not come here !
	sys	_exit
	
loadFromFile:
	; 26/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff_0		; no
	stc
	retn
lff_0:
	; 13/06/2017
	;mov	edx, BUFFERSIZE
	; 26/11/2023
	mov	edi, audio_buffer
	mov	edx, [buffersize]	; bytes
	mov	cl, [fbs_shift]   
	and	cl, cl
	jz	short lff_1 ; stereo, 16 bit

	; fbs_shift =
	;	2 for mono and 8 bit sample (multiplier = 4)
	;	1 for mono or 8 bit sample (multiplier = 2)
	shr	edx, cl
	;inc	edx

	mov     esi, temp_buffer
	jmp	short lff_2
lff_1:
	;mov	esi, audio_buffer
	mov	esi, edi ; audio_buffer
lff_2:
	; 17/03/2017
	; esi = buffer address
	; edx = buffer size
 
	; 26/11/2023
	; load file into memory
	sys 	_read, [FileHandle], esi
	; 14/12/2024
	mov	ecx, [buffersize]
	;jc	short padfill ; error !
	; 14/12/2024
	jc	short lff_10

	and	eax, eax
	jz	short padfill
lff_3:
	; 26/11/2023
	mov	bl, [fbs_shift]
	and	bl, bl
	jz	short lff_11

	; 14/12/2024
	;sub	ecx, eax
	;mov	ebp, ecx
	; 14/12/2024
	sub	edx, eax

	;mov	esi, temp_buffer
	;mov	edi, audio_buffer
	mov	ecx, eax   ; byte count

	cmp	byte [bps], 8 ; bits per sample (8 or 16)
	jne	short lff_6 ; 16 bit samples
	; 8 bit samples
	dec	bl  ; shift count, 1 = stereo, 2 = mono
	jz	short lff_5 ; 8 bit, stereo
lff_4:
	; mono & 8 bit
	lodsb
	sub	al, 80h ; 08/11/2023
	shl	eax, 8 ; convert 8 bit sample to 16 bit sample
	stosw	; left channel
	stosw	; right channel
	loop	lff_4
	jmp	short lff_8
lff_5:
	; stereo & 8 bit
	lodsb
	sub	al, 80h ; 08/11/2023
	shl	eax, 8 ; convert 8 bit sample to 16 bit sample
	stosw
	loop	lff_5			
	jmp	short lff_8
lff_6:
	shr	ecx, 1 ; word count
lff_7:
	lodsw
	stosw	; left channel
	stosw	; right channel
	loop	lff_7
lff_8:
	; 27/11/2023
	clc
	; 14/12/2024
	;mov	ecx, ebp
	;jecxz	endLFF_retn
	or	edx, edx
	jz	short endLFF_retn
	
	; 14/12/2024
	mov	ecx, audio_buffer
	add	ecx, [buffersize]
	sub	ecx, edi

	; 14/12/2024
lff_10:
	xor	eax, eax ; silence
padfill:
	shr	ecx, 1 
	rep	stosw
lff_9:
        or	byte [flags], ENDOFFILE	; end of file flag
endLFF_retn:
        retn

lff_11:
	; 16 bit stereo
	; ecx = buffer size
	; eax = read count
	sub	ecx, eax
	jna	short endLFF_retn
	add	edi, eax  ; audio_buffer + eax
	jmp	short lff_10 ; padfill

error_exit_2:
	; 26/11/2023 - temporary
	;sys	_msg, test_2, 255, 0Ch

	jmp	error_exit
	
	; 26/11/2023 - temporary
;test_1:
;	db 13, 10, 'Test 1', 13,10, 0
;test_2:
;	db 13, 10, 'Test 2', 13,10, 0
	
PlayWav:
	; 26/11/2023
	; 18/08/2020 (27/07/2020, 'wavplay2.s')
	; 13/06/2017
	; Convert 8 bit samples to 16 bit samples
	; and convert mono samples to stereo samples

	; 26/11/2023
	; load 32768 bytes into audio buffer
	;mov	edi, audio_buffer
	;;mov	edx, BUFFERSIZE
	; 26/11/2023
	;mov	edx, [buffersize]
	;call	loadFromFile
	; 26/11/2023
	call	dword [loadfromwavfile]
	jc	short error_exit_2
	mov	byte [half_buff], 1 ; (DMA) Buffer 1

	; 18/08/2020 (27/07/2020, 'wavplay2.s')
	test    byte [flags], ENDOFFILE  ; end of file
	jnz	short _6 ; yes
			 ; bypass filling dma half buffer 2

	; bh = 16 : update (current, first) dma half buffer
	; bl = 0  : then switch to the next (second) half buffer
	sys	_audio, 1000h

	; 18/08/2020
	; [audio_flag] = 1 (in TRDOS 386 kernel)

	; audio_buffer must be filled again after above system call 
	; (Because audio interrupt will be generated by AC97 hardware
	; at the end of the first half of dma buffer.. so, 
	; the second half must be ready. 'sound_play' will use it.)

	; 26/11/2023
	;mov	edi, audio_buffer
	;;mov	edx, BUFFERSIZE
	; 26/11/2023
	;mov	edx, [buffersize]
	;call	loadFromFile
	; 26/11/2023
	call	dword [loadfromwavfile]
	;jc	short p_return
_6:
	; Set Master Volume Level (BL=0 or 80h)
	; 	for next playing (BL>=80h)
	;sys	_audio, 0B80h, 1D1Dh
	sys	_audio, 0B00h, 1D1Dh

	; 18/08/2020
	;mov	byte [volume_level], 1Dh
	mov	[volume_level], cl

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

	;mov	ebx, 0B8000h ; video display page address
	;mov	ah, 4Eh
	;mov	al, [half_buffer]
	;mov	[ebx], ax ; show playing buffer (1, 2)

	; 18/08/2020 (27/07/2020, 'wavplay2.s')
	; Here..
	; If byte [flags] <> ENDOFFILE ...
	; user's audio_buffer has been copied to dma half buffer 2

	; [audio_flag] = 0 (in TRDOS 386 kernel)

	; audio_buffer must be filled again after above system call 
	; (Because, audio interrupt will be generated by VT8237R
	; at the end of the first half of dma buffer.. so, 
	; the 2nd half of dma buffer is ready but the 1st half
	; must be filled again.)

; 14/12/2024
%if 0
	; 18/08/2020
	test    byte [flags], ENDOFFILE  ; end of file
	jnz	short p_loop ; yes

	; 18/08/2020
	; load 32768 bytes into audio buffer
	;; (for the second half of DMA buffer)
	; 27/11/2023
	; 20/05/2017
	;mov	edi, audio_buffer
	;mov	edx, BUFFERSIZE
	; 26/11/2023
	;mov	edx, [buffersize]
	;call	loadFromFile
	; 26/11/2023
	call	dword [loadfromwavfile]
	;jc	short p_return
	;mov	byte [half_buff], 2 ; (DMA) Buffer 2
%endif

	; we need to wait for 'SRB' (audio interrupt)
	; (we can not return from 'PlayWav' here 
	;  even if we have got an error from file reading)
	; ((!!current audio data must be played!!))

	; 18/08/2020
	;mov	byte [srb], 1

p_loop:
	;mov	ah, 1		; any key pressed?
	;int	32h		; no, Loop.
	;jz	short q_loop
	;
	;mov	ah, 0		; flush key buffer...
	;int	32h

	; 18/08/2020 (14/10/2017, 'wavplay2.s')
	cmp	byte [srb], 0
	jna	short q_loop
	mov	byte [srb], 0
	; 13/12/2024
	xor	byte [half_buff], 3 ; 2->1, 1->2

	; 27/11/2023
	;mov	edi, audio_buffer
	;mov	edx, BUFFERSIZE
	; 26/11/2023
	;mov	edx, [buffersize]
	;call	loadFromFile
	; 26/11/2023
	call	dword [loadfromwavfile]
	jc	short p_return

	; 14/12/2024
	;;;
	; bh = 16 : update (current, first) dma half buffer
	; bl = 0  : then switch to the other half buffer
	sys	_audio, 1000h
	;;;;

	; 13/12/2024
	call	tL0
q_loop:
	mov     ah, 1		; any key pressed?
	int     32h		; no, Loop.
	jz	short p_loop

	mov     ah, 0		; flush key buffer...
	int     32h
	
	cmp	al, '+' ; increase sound volume
	je	short inc_volume_level
	cmp	al, '-'
	je	short dec_volume_level

p_return:
	mov	byte [half_buff], 0
	; 13/12/2024
	;call	tL0
	;retn

	; 13/12/2024
tL0:
	mov	al, [half_buff]
	add	al, '0'
	mov	ah, 4Eh
	mov	ebx, 0B8000h	; video display page address
	mov	[ebx], ax	; show playing buffer (1, 2)
	retn

	; 18/08/2020 (14/10/2017, 'wavplay2.s')
inc_volume_level:
	mov	cl, [volume_level]
	cmp	cl, 1Fh ; 31
	jnb	short q_loop
	inc	cl
change_volume_level:
	mov	[volume_level], cl
	mov	ch, cl
	; Set Master Volume Level
	sys	_audio, 0B00h
	jmp	short p_loop
dec_volume_level:
	mov	cl, [volume_level]
	cmp	cl, 1 ; 1
	;jna	short p_loop
	; 14/12/2024
	jna	short q_loop
	dec	cl
	jmp	short change_volume_level

write_audio_dev_info:
	; EBX = Message address
	; ECX = Max. message length (or stop on ZERO character)
	;	(1 to 255)
	; DL  = Message color (07h = light gray, 0Fh = white) 
     	sys 	_msg, msgAudioCardInfo, 255, 0Fh
	retn

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

write_ac97_pci_dev_info:
	; 06/06/2017
	; 03/06/2017
	; BUS/DEV/FN
	;	00000000BBBBBBBBDDDDDFFF00000000
	; DEV/VENDOR
	;	DDDDDDDDDDDDDDDDVVVVVVVVVVVVVVVV

	mov	esi, [dev_vendor]
	mov	eax, esi
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

	mov	ax, [ac97_NamBar]
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

	mov	ax, [ac97_NabmBar]
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

	xor	ah, ah
	mov	al, [ac97_int_ln_reg]
	mov	cl, 10
	div	cl
	add	[msgIRQ], ax
	and	al, al
	jnz	short _w_ac97imsg_
	mov	al, [msgIRQ+1]
	mov	ah, ' '
	mov	[msgIRQ], ax
_w_ac97imsg_:
	sys	_msg, msgAC97Info, 255, 07h

        retn

write_VRA_info:
	; 25/11/2023
	sys	_msg, msgVRAheader, 255, 07h
	cmp	byte [VRA], 0
	jna	short _w_VRAi_no
_w_VRAi_yes:
	sys	_msg, msgVRAyes, 255, 07h
	retn
_w_VRAi_no:
	sys	_msg, msgVRAno, 255, 07h
	retn

	; 06/06/2024
write_codec_info:
	mov	edx, ebx
	and	ebx, 0Fh
	mov	al, [ebx+hex_chars]
	mov	[msgCodecId2+3], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [ebx+hex_chars]
	mov	[msgCodecId2+2], al
	mov	bl, dh
	and	bl, 0Fh
	mov	al, [ebx+hex_chars]
	mov	[msgCodecId2+1], al
	mov	bl, dh
	shr	bl, 4
	mov	al, [ebx+hex_chars]
	mov	[msgCodecId2], al
	shr	edx, 16
	mov	bl, dl
	and	bl, 0Fh
	mov	al, [ebx+hex_chars]
	mov	[msgCodecId1+3], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [ebx+hex_chars]
	mov	[msgCodecId1+2], al
	mov	bl, dh
	and	bl, 0Fh
	mov	al, [ebx+hex_chars]
	mov	[msgCodecId1+1], al
	mov	bl, dh
	shr	bl, 4
	mov	al, [ebx+hex_chars]
	mov	[msgCodecId1], al
	;
	sys	_msg, msgCodec, 255, 07h
	retn

; 02/02/2025
;
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
	; 02/02/2025
	; 15/11/2023
	; 14/11/2023
	; 13/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff8m_0		; no
	stc
	retn

lff8m_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jnc	short lff8m_6
	jmp	lff8m_5  ; error !

lff8m_6:
	mov	edi, audio_buffer
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
	; 02/02/2025
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
lff12_3:	; 02/02/2025
	; 08/12/2024 (BugFix)
	; 01/06/2024 (BugFix)
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
	; 01/06/2024 (BugFix)
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
lff12_eof:	; 02/02/2025
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
lff12_5:	; 02/02/2025
	mov	al, '!'  ; error
	call	tL0
	
	;jmp	short lff8m_3
	; 15/11/2023
	jmp	lff8_eof

	; --------------

load_8khz_stereo_8_bit:
	; 02/02/2025
	; 15/11/2023
	; 14/11/2023
	; 13/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff8s_0		; no
	stc
	retn

lff8s_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff8s_5 ; error !

	mov	edi, audio_buffer
	
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
	; 02/02/2025
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

load_8khz_mono_16_bit:
	; 02/02/2025
	; 13/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff8m2_0		; no
	stc
	retn

lff8m2_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	lff8m2_7 ; error !

	mov	edi, audio_buffer
	
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
	; 02/02/2025
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

load_8khz_stereo_16_bit:
	; 02/02/2025
	; 16/11/2023
	; 15/11/2023
	; 13/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff8s2_0		; no
	stc
	retn

lff8s2_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff8s2_7 ; error !

	mov	edi, audio_buffer
	
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
	; 02/02/2025
	mov	ax, [esi]
	mov	dx, [esi+2]
	; 16/11/2023
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

; .....................

load_16khz_mono_8_bit:
	; 02/02/2025
	; 14/11/2023
	; 13/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff16m_0		; no
	stc
	retn

lff16m_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff16m_7 ; error !

	mov	edi, audio_buffer
	
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
	; 02/02/2025
	mov	al, [esi]
	dec	ecx
	jnz	short lff16m_2
	; 14/11/2023
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

load_16khz_stereo_8_bit:
	; 02/02/2025
	; 14/11/2023
	; 13/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff16s_0		; no
	stc
	retn

lff16s_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff16s_7 ; error !

	mov	edi, audio_buffer
	
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
	; 02/02/2025
	mov	ax, [esi]
	dec	ecx
	jnz	short lff16s_2
		; convert 8 bit sample to 16 bit sample
	; 14/11/2023
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

load_16khz_mono_16_bit:
	; 02/02/2025
	; 15/11/2023
	; 13/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff16m2_0		; no
	stc
	retn

lff16m2_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff16m2_7 ; error !

	mov	edi, audio_buffer
	
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
	; 02/02/2025
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

load_16khz_stereo_16_bit:
	; 02/02/2025
	; 16/11/2023
	; 15/11/2023
	; 13/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff16s2_0		; no
	stc
	retn

lff16s2_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff16s2_7 ; error !

	mov	edi, audio_buffer
	
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
	; 02/02/2025
	mov	ax, [esi]
	mov	dx, [esi+2]
	; 16/11/2023
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

; .....................

load_24khz_mono_8_bit:
	; 02/02/2025
	; 15/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff24m_0		; no
	stc
	retn

lff24m_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff24m_7 ; error !

	mov	edi, audio_buffer
	
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
	; 02/02/2025
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

load_24khz_stereo_8_bit:
	; 02/02/2025
	; 15/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff24s_0		; no
	stc
	retn

lff24s_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff24s_7 ; error !

	mov	edi, audio_buffer

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
	; 02/02/2025
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

load_24khz_mono_16_bit:
	; 02/02/2025
	; 15/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff24m2_0		; no
	stc
	retn

lff24m2_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff24m2_7 ; error !

	mov	edi, audio_buffer
	
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
	; 02/02/2025
	mov	bx, [esi]
	dec	ecx
	jnz	short lff24m2_2
	;xor	eax, eax
	xor	ebx, ebx
lff24m2_2:
	; 02/02/2025
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

load_24khz_stereo_16_bit:
	; 02/02/2025
	; 16/11/2023
	; 15/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff24s2_0		; no
	stc
	retn

lff24s2_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff24s2_7 ; error !

	mov	edi, audio_buffer
	
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
	; 02/02/2025
	mov	ax, [esi]
	mov	dx, [esi+2]
	; 16/11/2023
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

; .....................

load_32khz_mono_8_bit:
	; 02/02/2025
	; 15/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff32m_0		; no
	stc
	retn

lff32m_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff32m_7 ; error !

	mov	edi, audio_buffer

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
	; 02/02/2025
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

load_32khz_stereo_8_bit:
	; 02/02/2025
	; 15/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff32s_0		; no
	stc
	retn

lff32s_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff32s_7 ; error !

	mov	edi, audio_buffer
	
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
	; 02/02/2025
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

load_32khz_mono_16_bit:
	; 02/02/2025
	; 15/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff32m2_0		; no
	stc
	retn

lff32m2_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff32m2_7 ; error !

	mov	edi, audio_buffer
	
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
	; 02/02/2025
	;mov	ax, [esi]
	mov	bx, [esi]
	dec	ecx
	jnz	short lff32m2_2
	xor	ebx, ebx
lff32m2_2:
	; 02/02/2025
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

load_32khz_stereo_16_bit:
	; 02/02/2025
	; 16/11/2023
	; 15/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff32s2_0		; no
	stc
	retn

lff32s2_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff32s2_7 ; error !

	mov	edi, audio_buffer
	
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
	; 02/02/2025
	mov	ax, [esi]
	mov	dx, [esi+2]
	; 16/11/2023
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

; .....................

load_22khz_mono_8_bit:
	; 02/02/2025
	; 16/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff22m_0		; no
	stc
	retn

lff22m_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff22m_7 ; error !

	mov	edi, audio_buffer
	
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
	; 02/02/2025
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
	; 02/02/2025
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

load_22khz_stereo_8_bit:
	; 02/02/2025
	; 16/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff22s_0		; no
	stc
	retn

lff22s_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff22s_7 ; error !

	mov	edi, audio_buffer

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
	; 02/02/2025
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
	; 02/02/2025
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

load_22khz_mono_16_bit:
	; 02/02/2025
	; 16/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff22m2_0		; no
	stc
	retn

lff22m2_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff22m2_7 ; error !

	mov	edi, audio_buffer
	
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
	; 02/02/2025
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
	; 02/02/2025
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

load_22khz_stereo_16_bit:
	; 16/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff22s2_0		; no
	stc
	retn

lff22s2_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff22s2_7 ; error !

	mov	edi, audio_buffer
	
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
	; 02/02/2025
	; 18/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff11m_0		; no
	stc
	retn

lff11m_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff11m_7 ; error !

	mov	edi, audio_buffer
	
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
	; 02/02/2025
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
	; 02/02/2025
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
	; 02/02/2025
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

load_11khz_stereo_8_bit:
	; 02/02/2025
	; 18/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff11s_0		; no
	stc
	retn

lff11s_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff11s_7 ; error !

	mov	edi, audio_buffer

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
	; 02/02/2025
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
	; 02/02/2025
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
	; 02/02/2025
	mov	dx, [esi]
	dec	ecx
	jnz	short lff11s_2_4
	mov	dx, 8080h
lff11s_2_4:
	call	interpolating_4_8bit_stereo
	jecxz	lff11s_3
	jmp	short lff11s_1

load_11khz_mono_16_bit:
	; 02/02/2025
	; 18/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff11m2_0		; no
	stc
	retn

lff11m2_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff11m2_7 ; error !

	mov	edi, audio_buffer
	
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
	; 02/02/2025
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
	; 02/02/2025
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
	; 02/02/2025
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

load_11khz_stereo_16_bit:
	; 17/01/2025
	; 18/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff11s2_0		; no
	stc
	retn

lff11s2_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff11s2_7 ; error !

	mov	edi, audio_buffer
	
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
	; 17/01/2025
	;mov	[next_val_l], edx
	; 26/11/2023
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
	;;;
	; 17/01/2025 (BugFix)
	mov	[next_val_l], edx
	;;;
	call	interpolating_5_16bit_stereo
	jecxz	lff11s2_3
lff11s2_2_2:
	lodsw
	mov	ebx, eax
	lodsw
	mov	edx, [esi]
	; 17/01/2025
	;mov	[next_val_l], dx
	; 26/11/2023
	;shr	edx, 16
	;mov	[next_val_r], dx
	dec	ecx
	jnz	short lff11s2_2_3
	xor	edx, edx ; 0
	;mov	[next_val_l], dx
	;mov	[next_val_r], dx
lff11s2_2_3:
	;;;
	; 17/01/2025 (BugFix)
	mov	[next_val_l], edx
	;;;
	call	interpolating_4_16bit_stereo
	jecxz	lff11s2_3
	
	dec	ebp
	jz	short lff11s2_9

	lodsw
	mov	ebx, eax
	lodsw
	mov	edx, [esi]
	; 17/01/2025
	;mov	[next_val_l], dx
	; 26/11/2023
	;shr	edx, 16
	;mov	[next_val_r], dx
	dec	ecx
	jnz	short lff11s2_2_4
	xor	edx, edx ; 0
	;mov	[next_val_l], dx
	;mov	[next_val_r], dx
lff11s2_2_4:
	;;;
	; 17/01/2025 (BugFix)
	mov	[next_val_l], edx
	;;;
 	call	interpolating_4_16bit_stereo
	jecxz	lff11s2_3
	jmp	short lff11s2_1

; .....................

load_44khz_mono_8_bit:
	; 02/02/2025
	; 18/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff44m_0		; no
	stc
	retn

lff44m_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff44m_7 ; error !

	mov	edi, audio_buffer

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
	; 02/02/2025
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

load_44khz_stereo_8_bit:
	; 02/02/2025
	; 16/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff44s_0		; no
	stc
	retn

lff44s_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff44s_7 ; error !

	mov	edi, audio_buffer

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
	; 02/02/2025
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

load_44khz_mono_16_bit:
	; 02/02/2025
	; 18/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff44m2_0		; no
	stc
	retn

lff44m2_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff44m2_7 ; error !

	mov	edi, audio_buffer
	
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
	; 02/02/2025
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

load_44khz_stereo_16_bit:
	; 18/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff44s2_0		; no
	stc
	retn

lff44s2_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff44s2_7 ; error !

	mov	edi, audio_buffer

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

	; 02/02/2025
load_12khz_mono_8_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff12m_0		; no
	stc
	retn

lff12m_0:
	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff12m_7 ; error !

	mov	edi, audio_buffer
	
	and	eax, eax
	jnz	short lff12m_8
	jmp	lff12_eof

lff12m_8:
	mov	ecx, eax	; byte count
lff12m_1:
	; original-interpolated-interpolated-interpolated
	lodsb
	; 02/02/2025
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

	; 02/02/2025
load_12khz_stereo_8_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff12s_0		; no
	stc
	retn

lff12s_0:
	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff12s_7 ; error !

	mov	edi, audio_buffer
	
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
	; 02/02/2025
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

	; 02/02/2025
load_12khz_mono_16_bit:
	test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff12m2_0		; no
	stc
	retn

lff12m2_0:
	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff12m2_7 ; error !

	mov	edi, audio_buffer
	
	shr	eax, 1
	jnz	short lff12m2_8
	jmp	lff12_eof

lff12m2_8:
	mov	ecx, eax	; word count
lff12m2_1:
	; original-interpolated-interpolated-interpolated
	lodsw
	; 02/02/2025
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

	; 02/02/2025
load_12khz_stereo_16_bit:
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff12s2_0		; no
	stc
	retn

lff12s2_0:
	mov	esi, temp_buffer ; temporary buffer for wav data

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff12s2_7 ; error !

	mov	edi, audio_buffer
	
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
	;mov	[next_val_l], dx
	;shr	edx, 16
	;mov	[next_val_r], dx
	; 02/02/2025
	mov	[next_val_l], edx

	; bx = [previous_val_l]
	; ax = [previous_val_r]
	; [next_val_l]
	; [next_val_r]
	call	interpolating_4_16bit_stereo
	jecxz	lff12s2_3
	jmp	short lff12s2_1

; .....................

interpolating_3_8bit_mono:
	; 02/02/2025
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
	; 02/02/2025
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 2 (L)
	stosw		; interpolated sample 2 (R)
	retn

interpolating_3_8bit_stereo:
	; 02/02/2025
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
	; 02/02/2025
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 2 (L)
	mov	al, bl
	add	al, dh	; [next_val_r]
	rcr	al, 1
	; 02/02/2025
	sub	al, 80h
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
	; 17/01/2025
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
	; 17/01/2025
	sub	ah, 80h	; -32768 to +32767 format again
	;push	eax ; *	; interpolated sample (R)
	; 17/01/2025
	shl	eax, 16
	mov	ax, [next_val_l]
	add	ah, 80h
	add	bh, 80h
	add	ax, bx	; [next_val_l] + [previous_val_l]
	rcr	ax, 1	; / 2
	sub	ah, 80h	; -32768 to +32767 format again
	; 17/01/2025
	;stosw 		; interpolated sample (L)
	;pop	eax ; *
	;sub	ah, 80h	; -32768 to +32767 format again
	;stosw 		; interpolated sample (R)
	; 17/01/2025
	stosd
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

; DATA

FileHandle:	
	dd	-1

Credits:
	db	'Tiny WAV Player for TRDOS 386 by Erdogan Tan. '
	;;;;;db	'August 2020.',10,13,0
	;;;;db	'November 2023.',10,13,0
	;;;db	'June 2024.', 10,13,0
	;;db	'December 2024.', 10,13,0
	;db	'January 2025.', 10,13,0
	db	'February 2025.', 10,13,0
	db	'17/06/2017', 10,13,0
	db	'18/08/2020', 10,13,0
	db	'27/11/2023', 10,13,0
	db	'01/06/2024', 10,13,0
	db	'06/06/2024', 10,13,0
	db	'08/12/2024', 10,13,0
	db	'14/12/2024', 10,13,0
	db	'17/01/2025', 10,13,0
	db	'02/02/2025', 10,13,0

msgAudioCardInfo:
	db 	'for Intel AC97 (ICH) Audio Controller.', 10,13,0

msg_usage:
	db	'usage: playwav6 filename.wav',10,13,0

noDevMsg:
	db	'Error: Unable to find AC97 audio device!'
	db	10,13,0

noFileErrMsg:
	db	'Error: file not found.',10,13,0

trdos386_err_msg:
	db	'TRDOS 386 System call error !',10,13,0

; 01/06/2024
msg_init_err:
	db	10,13
	db	"AC97 Controller/Codec initialization error !"
	db	10,13,0

; 25/11/2023
msg_no_vra:
	db	10,13
	db	"No VRA support ! Only 48 kHZ sample rate supported !"
	db	10,13,0

msgWavFileName:	db 0Dh, 0Ah, "WAV File Name: ",0
msgSampleRate:	db 0Dh, 0Ah, "Sample Rate: "
msgHertz:	db "00000 Hz, ", 0 
msg8Bits:	db "8 bits, ", 0 
msgMono:	db "Mono", 0Dh, 0Ah, 0
msg16Bits:	db "16 bits, ", 0 
msgStereo:	db "Stereo"
nextline:	db 0Dh, 0Ah, 0

; 03/06/2017
hex_chars	db "0123456789ABCDEF", 0
msgAC97Info	db 0Dh, 0Ah
		db "AC97 Audio Controller & Codec Info", 0Dh, 0Ah 
		db "Vendor ID: "
msgVendorId	db "0000h Device ID: "
msgDevId	db "0000h", 0Dh, 0Ah
		db "Bus: "
msgBusNo	db "00h Device: "
msgDevNo	db "00h Function: "
msgFncNo	db "00h"
		db 0Dh, 0Ah
		db "NAMBAR: "
msgNamBar	db "0000h  "
		db "NABMBAR: "
msgNabmBar	db "0000h  IRQ: "
msgIRQ		dw 3030h
		db 0Dh, 0Ah, 0
; 06/06/2024
msgCodec	db 0Dh, 0Ah
		db "CODEC "
		db 0Dh, 0Ah
		db "Vendor ID1: "
msgCodecId1	db "0000h  "
		db "Vendor ID2: "
msgCodecId2	db "0000h  "  
; 25/11/2023
		db 0Dh, 0Ah, 0
msgVRAheader:	db "VRA support: "
		db 0	
msgVRAyes:	db "YES", 0Dh, 0Ah, 0
msgVRAno:	db "NO ", 0Dh, 0Ah
		db "(Interpolated sample rate playing method)"
		db 0Dh, 0Ah, 0	
EOF: 

; BSS

bss_start:

ABSOLUTE bss_start

alignb 4

stmo:		resb 1 ; stereo or mono (1=stereo) 
bps:		resb 1 ; bits per sample (8,16)
sample_rate:	resw 1 ; Sample Frequency (Hz)

; 25/11/2023
bufferSize:	resd 1

flags:		resb 1
;cbs_busy:	resb 1 
half_buff:	resb 1
srb:		resb 1
; 18/08/2020
volume_level:	resb 1
; 25/11/2023
VRA:		resb 1	; Variable Rate Audio Support Status

smpRBuff:	resw 14 

wav_file_name:
		resb 80 ; wave file, path name (<= 80 bytes)

		resw 1
ac97_int_ln_reg: resb 1
fbs_shift:	resb 1 ; 26/11/2023
dev_vendor:	resd 1
bus_dev_fn:	resd 1
ac97_NamBar:	resw 1
ac97_NabmBar:	resw 1

bss_end:
alignb 4096
;audio_buffer:	resb BUFFERSIZE ; DMA Buffer Size / 2 (32768)
; 26/11/2023
audio_buffer:	resb 65536
; 13/06/2017
;temp_buffer:	resb BUFFERSIZE
; 26/11/2023
temp_buffer:	resb 65536
