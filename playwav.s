; ****************************************************************************
; playwav.s (for TRDOS 386)
; ----------------------------------------------------------------------------
; PLAYWAV.PRG ! Sound Blaster 16 .wav player program by Erdogan TAN
;
; 07/03/2017
;
; [ Last Modification: 10/02/2025 ] (previous modification: 20/10/2017)
;
; Modified from TINYPLAY.PRG .mod player program by Erdogan Tan, 04/03/2017 
;
; Derived from source code of 'PLAYWAV.COM' ('PLAYWAV.ASM') by Erdogan Tan
;	      (17/02/2017) 
; Assembler: NASM version 2.11 (2.16, 2025)
;	     nasm playwav.s -l playwav.txt -o PLAYWAV.PRG	
; ----------------------------------------------------------------------------
; Derived from '.wav file player for DOS' Jeff Leyda, Sep 02, 2002


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


[BITS 32]

[ORG 0] 

_STARTUP:
	; Prints the Credits Text.
	sys	_msg, Credits, 255, 0Bh

	; clear bss
	mov	ecx, EOF
	mov	edi, bss_start
	sub	ecx, edi
	shr	ecx, 1
	xor	eax, eax
	rep	stosw

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
	jnz	short a_2	; then add a .WAV extension.
SetExt:
	dec	edi
	mov	dword [edi], '.WAV'
	mov	byte [edi+4], 0
a_2:      
	call    DetectSb	; Detect the SB Addr, Irq.

	; DIRECT CGA (TEXT MODE) MEMORY ACCESS
	; bl = 0, bh = 4
	; Direct access/map to CGA (Text) memory (0B8000h)

	sys	_video, 0400h
	cmp	eax, 0B8000h
	jne	error_exit

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

	mov	[sampling_rate], ax
	mov	[stmo], cl
	mov	[bps], dl
	
PlayNow: 
	; DIRECT MEMORY ACCESS (for Audio DMA)
	; ebx = DMA buffer address (virtual, user)
	; ecx = buffer size (in bytes)
	; edx = upper limit = 16MB

	_16MB	equ 1024*1024*16	

	sys	_alloc, DmaBuffer, DmaBufSize, _16MB 
	jc	short error_exit

	mov	[DMA_phy_buff], eax	; physical address
	     				; of the buffer
					; (which is needed
					; for DMA controller)
	call    SbInit
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

; play the .wav file.  Most of the good stuff is in here.

        call    PlayWav

; close the .wav file and exit.

        call    closeFile

	call	SbDone

	; Deallocate DMA buffer (not necessary just before exit!)
	sys	_dalloc, DmaBuffer, DmaBufSize
	;jc	error_exit
Exit:           
	sys	_exit	; Bye!

here:
	jmp	short here

pmsg_usage:
	sys	_msg, msg_usage, 255, 0Bh
	jmp	short Exit

error_exit:
	sys	_msg, trdos386_err_msg, 255, 0Eh
	jmp	short Exit

DetectSb:
	; 10/02/2025
	;pushad
ScanPort:
	mov     bx, 210h	; start scanning ports
		; 210h, 220h, .. 260h
ResetDSP:       
	mov     dx, bx	; try to reset the DSP.
	add     dx, 06h
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

	add     dx, 08h
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
	sub     dx, 04h
	;in	al, dx
	int	34h  ;ah = 0 ; inb
	cmp     al, 0AAh
	je      short Found
	add     dx, 04h
	loop    WaitID
NextPort:
	add     bx, 10h	; if not response,
	cmp     bx, 260h	; try the next port.
	jbe     short ResetDSP
	jmp     Fail
Found:
	mov     [SbAddr], bx	; SB Port Address Found!
ScanIRQ:
SetIrqs:
	; LINK SIGNAL RESPONSE/RETURN BYTE TO REQUESTED IRQ
	sys	_calbac, 102h, 2, SbIrq ; IRQ 2
		; Signal Response Byte
	;jc	short error_exit

	sys	_calbac, 103h, 3, SbIrq ; IRQ 3
		; Signal Response Byte 
	;jc	short error_exit

	sys	_calbac, 104h, 4, SbIrq ; IRQ 4
		; Signal Response Byte 
	;jc	short error_exit

	sys	_calbac, 105h, 5, SbIrq ; IRQ 5
		; Signal Response Byte 
	;jc	short error_exit

	sys	_calbac, 107h, 7, SbIrq ; IRQ 7
		; Signal Response Byte 
	;jc	short error_exit

	mov     byte [SbIrq], 0	; clear the IRQ level.

	mov     dx, [SbAddr]	; tells to the SB to
	add     dx, 0Ch	; generate a IRQ!
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

	xor     ecx, ecx	; wait until IRQ level
WaitIRQ:        
	cmp     byte [SbIrq], 0	; is changed or timeout.
	jne     short IrqOk
	dec 	cx
	jnz	short WaitIRQ
	jmp	short RestoreIrqs
IrqOk:
	mov     dx, [SbAddr]
	add     dx, 0Eh
	;in	al, dx	; SB acknowledge.
	mov	ah, 0 ; inb
	int	34h
	;mov	al, 20h
	;;out	20h, al	; Hardware acknowledge.
	;mov	ah,1  ; outb
	;int	34h

RestoreIrqs:
	; UNLINK SIGNAL RESPONSE/RETURN BYTE FROM REQUESTED IRQ
	sys	_calbac, 2	; unlink IRQ 2
		; Signal Response Byte
	sys	_calbac, 3	; unlink IRQ 3
		; Signal Response Byte 
	sys	_calbac, 4	; unlink IRQ 4
		; Signal Response Byte 
	sys	_calbac, 5	; unlink IRQ 5
		; Signal Response Byte
	sys	_calbac, 7	; unlink IRQ 7
		; Signal Response Byte 

	cmp     byte [SbIrq], 0	; IRQ level was changed?
	je      short Fail	; no, fail.
Success:        
	mov     dx, [SbAddr]	; Print Sucessful message.
	mov     cl, [SbIrq]
	shr     dl, 4
	add     dl, '0'
	mov     [PortText], dl
	add     cl, '0'
	mov     [IrqText], cl

	sys	_msg, MsgFound, 255, 0Fh

	;popad	; Return to caller.
	retn

Fail:  
	; Print Failed Message,
	; and exit to MainProg.

	sys	_msg, MsgNotFound, 255, 0Fh

	sys 	_exit

	jmp	here

;open or create file
;
;input: ds:dx-->filename (asciiz)
;       al=file Mode (create or open)
;output: none  cs:[FileHandle] filled
;
openFile:
	;;push	eax
	;;push	ecx
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
	;;pop	ecx
	;;pop	eax
	retn

; close the currently open file
; input: none, uses cs:[FileHandle]
closeFile:
	;push	eax
	;push	ebx
	cmp	dword [FileHandle], -1
	je	short _cf1
	;mov    bx, [FileHandle]  
	;mov    ax, 3E00h
        ;int    21h              ;close file

	sys	_close, [FileHandle]
_cf1:
	;pop	ebx
	;pop	eax
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

DmaBufSize	equ     65536		; 64K file buffer size.
ENDOFFILE       equ     1		; flag for knowing end of file

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

SbInit:
	;pushad

SetBuffer:
	;mov	byte [DmaFlag], 0
	; 10/03/2017
	mov	ebx, [DMA_phy_buff] ; physical addr of DMA buff
	mov     ecx, DmaBufSize

	; 10/02/2025
	mov     edi, DmaBuffer  ; virtual addr of DMA buff

	cmp	byte [bps], 16
	jne	short _0 ; set 8 bit DMA buffer
	
	; 20/10/2017
	; 06/10/2017 (TRDOS 386 kernel, 'audio.s', 'SbInit_play')
	
	; 16 bit DMA buffer setting (DMA channel 5)

	; 09/08/2017
	; convert byte count to word count
	shr	ecx, 1
	dec	ecx ; word count - 1
	; convert byte offset to word offset
	shr	ebx, 1

	; 16 bit DMA buffer setting (DMA channel 5)
	mov     al, 05h ; set mask bit for channel 5  (4+1)
	;out	0D4h, al
	mov	dx, 0D4h ; DMA mask register
	mov	ah, 1  ;outb
	int	34h

	xor     al, al ; stops all DMA processes on selected channel
	;out	0D8h, al
	mov	dl, 0D8h  ; clear selected channel register
	;mov	ah, 1  ;outb
	int	34h

	mov     al, bl	; byte 0 of DMA buffer address (physical)   
	;out	0C4, al
	mov	dl, 0C4h ; DMA channel 5 port number
	;mov	ah, 1  ;outb
	int	34h

	mov     al, bh  ; byte 1 of DMA buffer address (physical)   
	;out	0C4h, al
	;mov	dl, 0C4h ; DMA channel 5 port number
	;mov	ah, 1  ;outb
	int	34h

	; 09/08/2017 (TRDOS 386, 'audio.s')
	shr	ebx, 15	 ; complete 16 bit shift
	and	bl, 0FEh ; clear bit 0 (not necessary, it will be ignored)

	; 13/07/2017 (89h -> 8Bh)
	mov     al, bl ; byte 2 of DMA buffer address (physical)   
	;out	8Bh, al
	mov	dl, 8Bh ; page register port addr for channel 5
	;mov	ah, 1  ;outb
	int	34h

	mov     al, cl ; low byte of DMA count - 1
	;out	0C6h, al
	mov	dl, 0C6h ; count register port addr for channel 1
	;mov	ah, 1  ;outb
	int	34h

	mov     al, ch ; high byte of DMA count - 1
	;out	0C6h, al
	;mov	dl, 0C6h ; count register port addr for channel 1
	;mov	ah, 1  ;outb
	int	34h

	; channel 5, read, autoinitialized, single mode
	;mov	al, 49h
	mov	al, 59h  ; 06/10/2017 
	;out	0D6h, al
	mov	dl, 0D6h ; DMA mode register port address
	;mov	ah, 1  ;outb
	int	34h

	mov     al, 01h ; clear mask bit for channel 1
	;out	0D4h, al
	mov	dl, 0D4h ; DMA mask register port address
	;mov	ah, 1  ;outb
	int	34h

	;jmp	short ClearBuffer

	; 10/02/2025 (16bit audio data)
	;mov	edi, DmaBuffer
	inc	ecx
	xor	eax, eax ; 0
	;cld
	rep	stosw
	jmp	short SetIrq

_0:  
	dec     ecx ; 20/10/2017
  
	; 8 bit DMA buffer setting (DMA channel 1)
	mov     al, 05h ; set mask bit for channel 1  (4+1)
	;out	0Ah, al
	mov	dx, 0Ah ; DMA mask register
	mov	ah, 1  ;outb
	int	34h

	xor     al, al ; stops all DMA processes on selected channel
	;out	0Ch, al
	mov	dl, 0Ch  ; clear selected channel register
	;mov	ah, 1  ;outb
	int	34h

	mov     al, bl	; byte 0 of DMA buffer address (physical)   
	;out	02h, al
	mov	dl, 02h	; DMA channel 1 port number
	;mov	ah, 1  ;outb
	int	34h

	mov     al, bh  ; byte 1 of DMA buffer address (physical)   
	;out	02h, al
	;mov	dl, 02h ; DMA channel 1 port number
	;mov	ah, 1  ;outb
	int	34h

	shr	ebx, 16

	mov     al, bl ; byte 2 of DMA buffer address (physical)   
	;out	83h, al
	mov	dl, 83h ; page register port addr for channel 1
	;mov	ah, 1  ;outb
	int	34h

	mov     al, cl ; low byte of DMA count - 1
	;out	03h, al
	mov	dl, 03h ; count register port addr for channel 1
	;mov	ah, 1  ;outb
	int	34h

	mov     al, ch ; high byte of DMA count - 1
	;out	03h, al
	;mov	dl, 03h ; count register port addr for channel 1
	;mov	ah, 1  ;outb
	int	34h

	; channel 1, read, autoinitialized, single mode
	;mov	al, 49h
	mov	al, 59h  ; 06/10/2017 
	;out	0Bh, al
	mov	dl, 0Bh ; DMA mode register port address
	;mov	ah, 1  ;outb
	int	34h

	mov     al, 01h ; clear mask bit for channel 1
	;out	0Ah, al
	mov	dl, 0Ah ; DMA mask register port address
	;mov	ah, 1  ;outb
	int	34h

	; 10/02/2025 (8bit audio data)
ClearBuffer:
	mov     edi, DmaBuffer  ; virtual addr of DMA buff
	;mov	ecx, DmaBufSize
	inc	ecx
	mov     al, 80h
	;cld
	rep     stosb

SetIrq:
	; CALLBACK method
	mov	bl, [SbIrq] ; IRQ number
	mov	bh, 2 ; Link IRQ to user for callback service
	mov	edx, SbIrqHandler
	sys	_calbac 
	; SIGNAL RESPONSE BYTE method ; 04/03/2017
	;mov	bl, [SbIrq]
	;mov	bh, 1 ; Signal Response Byte method
	;movzx	ecx, bl ; S.R.B. value = IRQ Number 
	;mov	edx, SbSrb ; S.R.B. address
	;sys	_calbac
ResetDsp:
	mov     dx, [SbAddr]
	add     dx, 06h
	mov     al, 1
	;out	dx, al
	mov	ah, 1  ;outb
	int	34h

	;in	al, dx
	;in	al, dx
	;in	al, dx
	;in	al, dx

	dec	ah ; ah = 0 ; inb
	int	34h	
	;mov	ah, 0
	int	34h

	xor     al, al
	;out	dx, al
	inc	ah ; ah = 1 ;outb
	int	34h

	;mov	cx, 100
	; 10/02/2025
	mov	cl, 100
	 ;ecx = 100
	sub	ah, ah ; 0
WaitId:         
	mov     dx, [SbAddr]
	add     dx, 0Eh
	;in	al, dx
	;mov	ah, 0  ;inb
	int	34h
	or      al, al
	js      short sb_GetId
	loop    WaitId
	;jmp	sb_Exit
	; 10/02/2025
	retn
sb_GetId:
	mov     dx, [SbAddr]
	add     dx, 0Ah
	;in	al, dx
	;mov	ah, 0  ;inb
	int	34h
	cmp     al, 0AAh
	je      short SbOk
	loop    WaitId
	;jmp	sb_Exit
	; 10/02/2025
	retn
SbOk:
	mov     dx, [SbAddr]
	add     dx, 0Ch
	SbOut   0D1h ; Turn on speaker
	; 10/03/2017
	SbOut   41h ; 8 bit or 16 bit transfer
	mov	bx, [sampling_rate]
	SbOut	bh ; sampling rate high byte
	SbOut	bl ; sampling rate low byte
	; 22/04/2017
	;mov	ah, 1
	;mov	dx, [SbAddr]
	;add	dx, 4 ; Mixer chip address port
	sub	dx, 0Ch-04h
	mov	al, 22h ; master volume
	int	34h
	inc	edx ; 10/02/2025	
	mov	al, 0FFh ; maximum volume level
	int	34h
	add	dx, 0Ch-05h
StartDma:  
	; autoinitialized mode
	cmp	byte [bps], 16 ; 16 bit samples
	je	short _1
	; 8 bit samples
	mov	bx, 0C6h ; 8 bit output (0C6h)
	cmp	byte [stmo], 2 ; 1 = mono, 2 = stereo
	jb	short _2
	mov	bh, 20h	; 8 bit stereo (20h)
	jmp	short _2
_1:
	mov	cx, DmaBufSize / 2 ; 20/10/2017
	; 16 bit samples
	mov	bx, 10B6h ; 16 bit output (0B6h)
	cmp	byte [stmo], 2 ; 1 = mono, 2 = stereo
	jb	short _2
	add	bh, 20h	; 16 bit stereo (30h)
	; 20/10/2017
	; 10/02/2025
	shr	ecx, 1 ; byte count -> word count
_2:     
	; PCM output (8/16 bit mono autoinitialized transfer)
	SbOut   bl ; bCommand
	SbOut	bh ; bMode
	; 20/10/2017
	;mov	bx, DmaBufSize / 2
	;dec	bx  ; wBlkSize is one less than the actual size 
	;SbOut	bl
	;SbOut	bh
	dec	ecx ; 10/02/2025
	SbOut	cl
	SbOut	ch	

	;; Set Voice and master volumes
	;mov	dx, [SbAddr]
	;add	dl, 4 ; Mixer chip Register Address Port
	;SbOut	30h   ; select Master Volume Register (L)
	;inc	dl    ; Mixer chip Register Data Port
	;SbOut	0F8h  ; Max. volume value is 31 (31*8)
	;dec	dl
	;SbOut	31h   ; select Master Volume Register (R)
	;inc	dl
	;SbOut	0F8h  ; Max. volume value is 31 (31*8)
	;dec	dl
	;SbOut	32h   ; select Voice Volume Register (L)
	;inc	dl
	;SbOut	0F8h  ; Max. volume value is 31 (31*8)
	;dec	dl
	;SbOut	33h   ; select Voice Volume Register (R)
	;inc	dl
	;SbOut	0F8h  ; Max. volume value is 31 (31*8)	
	;;
	;dec	dl
	;SbOut	44h   ; select Treble Register (L)
	;inc	dl
	;SbOut	0F0h  ; Max. Treble value is 15 (15*16)
	;dec	dl
	;SbOut	45h   ; select Treble Register (R)
	;inc	dl
	;SbOut	0F0h  ; Max. Treble value is 15 (15*16)
	;dec	dl
	;SbOut	46h   ; select Bass Register (L)
	;inc	dl
	;SbOut	0F0h  ; Max. Bass value is 15 (15*16)
	;dec	dl
	;SbOut	47h   ; select Bass Register (R)
	;inc	dl
	;SbOut	0F0h  ; Max. Bass value is 15 (15*16)	

sb_Exit:           
	;popad
	retn

SbIrqHandler:  ; SoundBlaster IRQ Callback service for TRDOS 386
	; 20/10/2017
	; 10/03/2017
	mov     dx, [SbAddr]
	sub	ah, ah

	cmp	byte [bps], 16 ; 16 bit samples
	je	short _3

	; DSP 8-bit interrupt interrupt acknowledge

	add	dl, 0Eh	

	;in	al, dx
	;mov	ah, 0
	;sub	ah, ah
	int	34h

	test	byte [flags], ENDOFFILE	; end of file flag
	jz	short _5

	inc	dl

	mov	bl, 0DAh ; exit auto-initialize 8 bit transfer

	jmp	short _4

_3:
	; DSP 16-bit interrupt interrupt acknowledge

	add	dl, 0Fh	

	;in	al, dx
	;mov	ah, 0
	;sub	ah, ah
	int	34h

	test	byte [flags], ENDOFFILE	; end of file flag
	jz	short _5

	mov	bl, 0D9h ; exit auto-initialize 16 bit transfer
_4:
	sub     dl, 3 ; [SbAddr] + 0Ch

	SbOut	bl ; exit auto-initialize transfer command

	jmp	short SbIrqHandler_release ; 20/10/2017

_5:
	; 09/03/2017
	xor	al, al ; 0
	mov	[iStatus], al ; 10/03/2017
	cmp 	[DmaFlag], al ; 0
	ja	short SbIrq_iret
	inc	al
SbIrq_iret:
	mov 	[DmaFlag], al ; 
SbIrqHandler_release:
	sys	_rele ; return from callback service

SbPoll:	;  Sound Blaster Polling.
	; 10/02/2025
	;pushad

	; 10/03/2017
	cmp	byte [iStatus], 0
	ja	short Bye

	mov	byte [iStatus], 1 ; 1 = set before interrupt
			     ; (for preventing data load
			     ; without an interrupt)		

	test	byte [flags], ENDOFFILE
	jnz	short sbPoll_stop
	
	mov     eax, DmaBuffer
	mov     edx, DmaBufSize/2

	test	byte [DmaFlag], 1
	jz     short FirstHalf
SecondHalf: ; write to the second half    
	add     eax, edx
FirstHalf: ; write to the first half
	call    loadFromFile
	jc	short sbPoll_stop
Bye:
	;popad
	retn

sbPoll_stop:
	; 24/04/2017
	mov     dx, [SbAddr]
	add     dx, 0Ch
	;
	mov	bl, 0D9h ; exit auto-initialize 16 bit transfer
	; stop  autoinitialized DMA transfer mode 
	cmp	byte [bps], 16 ; 16 bit samples
	je	short _6
	;mov	bl, 0DAh ; exit auto-initialize 8 bit transfer
	inc	bl
_6:
	SbOut	bl ; exit auto-initialize transfer command

	mov	byte [tLoop], 0
	;jmp	short Bye
	; 10/02/2025
	retn

SbDone:
	; 10/02/2025
	;pushad

	mov     bl, [SbIrq] ; IRQ number
	sub	bh, bh ; 0 = Unlink IRQ from user
	sys	_calbac 

	mov     dx, [SbAddr]
	add     dx, 0Ch
	SbOut   0D0h
	SbOut   0D3h

	;popad
	retn

loadFromFile:
	; 10/03/2017
        ;push	eax
        ;push	ecx
        ;push	edx
	;push	ebx
        test    byte [flags], ENDOFFILE	; have we already read the
        stc			; last of the file?
        jnz     short endLFF
	mov	edi, eax ; buffer address
	;mov	edx, (DmaBufSize/2)
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
	je	short _8
	; Minimum Value = 0
	;xor     al, al
	; 10/02/2025 
	mov	al, 80h ; silence, middle point
	rep	stosb
_7:
        ;clc			; don't exit with CY yet.
        or	byte [flags], ENDOFFILE	; end of file flag
endLFF:
	;pop	ebx
	;pop	edx
        ;pop	ecx
        ;pop	eax
        retn
_8:
	; Minimum value = 8000h (-32768)
	shr	ecx, 1 
	;mov	ax, 8000h ; -32768
	; 10/02/2025 
	xor	eax, eax ; 0 ; silence, middle point
	rep	stosw
	jmp	short _7

PlayWav:
	mov	byte [tLoop], 1
tuneLoop:
	call	SbPoll
	
	cmp	byte [tLoop], 1
	jb	short StopPlaying

	mov	esi, 0B8000h
	mov	al, [DmaFlag]
	mov	ah, 4Eh
	; 10/02/2025
	;and	al, 1
	add	al, '1'
	mov	[esi], ax ; show current play buffer (1, 2)
	
	mov     ah, 1			; any key pressed?
	int     32h			; no, Loop.
	jz	short tuneLoop

	mov     ah, 0			; flush key buffer...
	int     32h

	;mov	byte [tLoop], 0

StopPlaying:
	; stop DMA process
	xor     al, al
	cmp	byte [bps], 16
	je	short _9

	; Stop 8 bit (autoinitialized) DMA process	
	;out	0Ch, al
	;retn
	mov	dx, 0Ch
	jmp	short _10
_9:	
	; Stop 16 bit (autoinitialized) DMA process
	;out	0D8h, al
	mov	dx, 0D8h	
_10:
	mov	ah, 1 ;outb
	int	34h

	retn

_DATA:

SbAddr:
	dw      220h
SbIrq:
	dw      7

msg_usage:
	db	'usage: playwav filename.wav',10,13,0
	db	'20/10/2017',0
	db	'10/02/2025',0

Credits:
	db	'Tiny WAV Player by Erdogan Tan. '
	;db 	'October 2017.'
	db	'February 2025.'
	db	10,13,0
noFileErrMsg:
	db	'Error: file not found.',10,13,0
MsgNotFound:
	db	'Sound Blaster not found or IRQ error.',10,13,0
MsgFound:
	db	'Sound Blaster found at Address 2'
PortText:
	db	'x0h, IRQ '
IrqText:
	db	'x.',10,13,0

trdos386_err_msg:
	db	'TRDOS 386 System call error !', 10, 13,0

FileHandle:	
	dd	-1

bss_start:

ABSOLUTE bss_start

alignb 4

; 28/11/2016

smpRBuff:	resw 14 

sampling_rate:
		resw 1
stmo:	
		resw 1 
bps:	
		resw 1
DmaFlag: 
		resb 1
tLoop:	
		resb 1	
flags:	
		resb 1
iStatus:
		resb 1
wav_file_name:
		resb 16

DMA_phy_buff:
		resd 1
alignb 65536
DmaBuffer:	resb 65536 ; 2 * 32K half buffer
EOF: