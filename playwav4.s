; ****************************************************************************
; playwav4.s (for TRDOS 386)
; ----------------------------------------------------------------------------
; PLAYWAV4.PRG ! Sound Blaster 16 .WAV PLAYER program by Erdogan TAN
;
; 24/04/2017
;
; [ Last Modification: 18/08/2020 ]
;
; Modified from WAVPLAY2.PRG .wav player program by Erdogan Tan, 23/04/2017
; Modified from PLAYWAV.PRG .wav player program by Erdogan Tan, 10/03/2017  
;
; Derived from source code of 'PLAYER.COM' ('PLAYER.ASM') by Erdogan Tan
;	      (18/02/2017) 
; Assembler: NASM version 2.14
;	     nasm playwav.asm -l playwav.txt -o PLAYWAV.PRG	
; ----------------------------------------------------------------------------
; Derived from '.wav file player for DOS' Jeff Leyda, Sep 02, 2002

; previous version: playwav2.s (27/05/2017)

; CODE

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

BUFFERSIZE      equ     32768	; audio buffer size 
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

	; Detect (& Enable) Sound Blaster 16 Audio Device
	call    DetectSB
	jnc     short GetFileName

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
	; Allocate Audio Buffer (for user)
	sys	_audio, 0200h, BUFFERSIZE, audio_buffer
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
	sys	_audio, 301h, 0, audio_int_handler 
	jc	short error_exit
_3:
	call	write_audio_dev_info 

; open the file
        ; open existing file
        call    openFile ; no error? ok.
        jnc     short _gsr

; file not found!
	sys	_msg, noFileErrMsg, 255, 0Fh
        jmp     Exit

_gsr:  
       	call    getSampleRate		; read the sample rate
                                        ; pass it onto codec.
	jc	Exit

	mov	[sample_rate], ax
	mov	[stmo], cl
	mov	[bps], dl

	call	write_wav_file_info ; 01/5/2017
	
PlayNow: 
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

; play the .wav file.  Most of the good stuff is in here.

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

DetectSB:
	; Detect (BH=1) SB16 (BL=1) Audio Card (or Emulator)
        sys	_audio, 101h
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

audio_int_handler:
	; 18/08/2020
	;mov	byte [srb], 1 ; interrupt (or signal response byte)

	;cmp	byte [cbs_busy], 1
	;jnb	short _callback_bsy_retn

	;mov	byte [cbs_busy], 1

	mov	al, [half_buff]

	cmp	al, 1
	jb	short _callback_retn

	; 18/08/2020
	mov	byte [srb], 1

	xor	byte [half_buff], 3 ; 2->1, 1->2

	mov	ebx, 0B8000h ; video display page address
	mov	ah, 4Eh
	add	al, '0'
	mov	[ebx], ax ; show playing buffer (1, 2)
_callback_retn:
	;mov	byte [cbs_busy], 0
_callback_bsy_retn:
	sys	_rele ; return from callback service 
	; we must not come here !
	sys	_exit
	
loadFromFile:
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
	je	short _5
	; Minimum Value = 0
        xor     al, al
	rep	stosb
_4:
        ;clc			; don't exit with CY yet.
        or	byte [flags], ENDOFFILE	; end of file flag
endLFF:
	;pop	ebx
	;pop	edx
        ;pop	ecx
        ;pop	eax
        retn
_5:
	; Minimum value = 8000h (-32768)
	shr	ecx, 1 
	mov	ax, 8000h ; -32768
	rep	stosw
	jmp	short _4

PlayWav:
	; load 32768 bytes into audio buffer
	; (for the first half of DMA buffer)
	mov     edi, audio_buffer
	mov	edx, BUFFERSIZE
	call	loadFromFile
	jc	error_exit
	mov	byte [half_buff], 1 ; (DMA) Buffer 1

	; 18/08/2020 (27/07/2020, "wavplay2.s")
	test    byte [flags], ENDOFFILE  ; end of file
	jnz	short _6 ; yes
			 ; bypass filling dma half buffer 2

	; bh = 16 : update (current, first) dma half buffer
	; bl = 0  : then switch to the next (second) half buffer
	sys	_audio, 1000h

	; [audio_flag] = 1  (in TRDOS 386 kernel)

	; audio_buffer must be filled again after above system call 
	; (Because audio interrupt will be generated by sound hardware
	; at the end of the first half of dma buffer.. so, 
	; the second half must be ready. 'sound_play' will use it.)

	mov     edi, audio_buffer
	mov	edx, BUFFERSIZE
	call    loadFromFile
	;jc	short p_return
_6:
	; Set Master Volume Level (BL=0 or 80h)
	; 	for next playing (BL>=80h)
	;sys	_audio, 0B80h, 1D1Dh
	sys	_audio, 0B00h, 1D1Dh

	; 18/08/2020
	;mov	byte [volume_level], 1Dh
	mov	[volume_level], cl

	; 18/08/2020
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

	;mov	ebx, 0B8000h ; video display page address
	;mov	ah, 4Eh
	;mov	al, '1'
	;mov	[ebx], ax ; show playing buffer (1, 2)

	; 18/08/2020 (27/07/2020, "wavplay2.s")
	; Here..
	; If byte [flags] <> ENDOFFILE ...
	; user's audio_buffer has been copied to dma half buffer 2

	; [audio_flag] = 0  (in TRDOS 386 kernel)

	; audio_buffer must be filled again after above system call 
	; (Because, audio interrupt will be generated by VT8237R
	; at the end of the first half of dma buffer.. so, 
	; the 2nd half of dma buffer is ready but the 1st half
	; must be filled again.)

	; 18/08/2020
	test    byte [flags], ENDOFFILE  ; end of file
	jnz	short p_loop ; yes

	; 18/08/2020
	; 20/05/2017
	; load 32768 bytes into audio buffer
	;; (for the second half of DMA buffer)
	mov     edi, audio_buffer
	mov	edx, BUFFERSIZE
	call	loadFromFile
	;jc	short p_return

	;mov	byte [half_buff], 2 ; (DMA) Buffer 2

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
	;
	;mov	ah, 0		; flush key buffer...
	;int	32h

	; 18/08/2020 (14/10/2017, 'wavplay2.s')
	cmp	byte [srb], 0
	jna	short q_loop
	mov	byte [srb], 0
	mov     edi, audio_buffer
	mov	edx, BUFFERSIZE
	call    loadFromFile
	jc	short p_return
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
	retn

;q_loop:
	;cmp	byte [srb], 0
	;jna	short p_loop
	;mov	byte [srb], 0
	;mov     edi, audio_buffer
	;mov	edx, BUFFERSIZE
	;call    loadFromFile
	;jc	short p_return
	;;mov	byte [srb], 0
	;jmp	short p_loop

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
	jna	short p_loop
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

; DATA

FileHandle:	
	dd	-1

Credits:
	db	'Tiny WAV Player for TRDOS 386 by Erdogan Tan. '
	db	'August 2020.',10,13,0
	db	'27/05/2017', 10,13,0
	db	'18/08/2020', 10,13,0 

msgAudioCardInfo:
	db 	'for Sound Blaster 16.', 10,13,0

msg_usage:
	db	'usage: playwav filename.wav',10,13,0

noDevMsg:
	db	'Error: Unable to find Sound Blaster 16 audio device!'
	db	10,13,0

noFileErrMsg:
	db	'Error: file not found.',10,13,0

trdos386_err_msg:
	db	'TRDOS 386 System call error !',10,13,0

msgWavFileName:	db 0Dh, 0Ah, "WAV File Name: ",0
msgSampleRate:	db 0Dh, 0Ah, "Sample Rate: "
msgHertz:	db "00000 Hz, ", 0 
msg8Bits:	db "8 bits, ", 0 
msgMono:	db "Mono", 0Dh, 0Ah, 0
msg16Bits:	db "16 bits, ", 0 
msgStereo:	db "Stereo"
nextline:	db 0Dh, 0Ah, 0

EOF: 

; BSS

bss_start:

ABSOLUTE bss_start

alignb 4

stmo:		resb 1 ; stereo or mono (1=stereo) 
bps:		resb 1 ; bits per sample (8,16)
sample_rate:	resw 1 ; Sample Frequency (Hz)

flags:		resb 1
;cbs_busy:	resb 1 ; 18/08/2020
half_buff:	resb 1
srb:		resb 1
; 18/08/2020
volume_level:	resb 1

smpRBuff:	resw 14 

wav_file_name:
		resb 80 ; wave file, path name (<= 80 bytes)
bss_end:
alignb 4096
audio_buffer:	resb BUFFERSIZE ; DMA Buffer Size / 2 (32768)
