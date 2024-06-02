; ****************************************************************************
; wavplay.s (for TRDOS 386)
; ----------------------------------------------------------------------------
; WAVPLAY.PRG ! VIA VT8237R (VT8233) .WAV PLAYER program by Erdogan TAN
;
; 17/03/2017
;
; [ Last Modification: 25/08/2020 ]
;
; Modified from PLAYWAV.PRG .wav player program by Erdogan Tan, 10/03/2017 
;
; Derived from source code of 'PLAYER.COM' ('PLAYER.ASM') by Erdogan Tan
;	      (18/02/2017) 
; Assembler: NASM version 2.11
;	     nasm wavplay.asm -l wavplay.txt -o WAVPLAY.PRG	
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

	call    DetectVT8233	; Detect the VT8233 Audio Device
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

	or	ah, ah		 ; if period NOT found,
	jnz	short init_codec ; then add a .WAV extension.
SetExt:
	dec	edi
	mov	dword [edi], '.WAV'
	mov	byte [edi+4], 0

init_codec:
	; init AC97 codec

	; 19/06/2017
	; 05/06/2017
	; 19/03/2017
	mov	eax, [bus_dev_fn]
	mov	al, VIA_ACLINK_CTRL  ; AC link interface control (41h)
	call	pciRegRead8

	;mov	eax, [bus_dev_fn]
	mov	al, VIA_ACLINK_STAT  ; AC Link interface status (40h)
	call	pciRegRead8
	
	movzx	eax, dl
	and	al, VIA_ACLINK_C00_READY  ; 1 ; primary codec ready ?
	jnz	short a_2

	call	reset_codec
	jnc	short a_2 ; EAX = 1

	;test	al, VIA_ACLINK_C00_READY 	
        ;jnz     short a_2

_codec_err:
	sys	_msg, CodecErrMsg, 255, 0Fh
        jmp     Exit

a_2:
	; eax = 1
	call	codec_io_w16 ; w32
	
	;call	detect_codec

	call	channel_reset

	call	write_ac97_dev_info 

a_3:
	; 03/08/2020
	; 14/10/2017
	; SETUP INTERRUPT CALLBACK SERVICE
	; 05/03/2017
	;mov	bl, [ac97_int_ln_reg] ; IRQ number
	;mov	bh, 2 ; Link IRQ to user for callback service
	;mov	edx, ac97_int_handler
	;;xor	ecx, ecx
	;sys	_calbac
	;jc	error_exit

	; 03/08/2020
	; 24/06/2017
	;; 23/06/2017
	mov	bl, [ac97_int_ln_reg] ; IRQ number
	mov	bh, 1 ; Link IRQ to user for signal response byte
	mov	cl, bh ; 1
	mov	edx, srb
	sys	_calbac
	jc	error_exit ; 03/08/2020

	; DIRECT CGA (TEXT MODE) MEMORY ACCESS
	; bl = 0, bh = 04h
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

	mov	[sample_rate], ax
	mov	[stmo], cl
	mov	[bps], dl

	; 24/06/2017
; setup the Codec (actually mixer registers) 
        call    codecConfig            ; unmute codec, set rates.
	;jc	_codec_err

PlayNow: 
	; DIRECT MEMORY ACCESS (for Audio Controller)
	; ebx = BDL buffer address (virtual, user)
	; ecx = buffer size (in bytes)
	; edx = upper limit = 0 = no limit

	sys	_alloc, BdlBuffer, 4096, 0 
	jc	error_exit

	mov	[BDL_phy_buff], eax	; physical address
					; of the buffer
					; (which is needed
					; for Audio controller)

	; DIRECT MEMORY ACCESS (for Audio Controller)
	; ebx = DMA buffer address (virtual, user)
	; ecx = buffer size (in bytes)
	; edx = upper limit = 0 = no limit

	sys	_alloc, DmaBuffer, 65536, 0 
	jc	short error_exit

	mov	[DMA_phy_buff], eax	; physical address
					; of the buffer
					; (which is needed
					; for Audio controller)
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

; 14/10/2017

; play the .wav file.  Most of the good stuff is in here.

        call    PlayWav

; close the .wav file and exit.

        call    closeFile

StopPlaying:
	; 14/10/2017
	; 24/06/2017
	mov	bl, [ac97_int_ln_reg] ; Audio IRQ number
	sub	bh, bh ; 0 = Unlink IRQ from user
	sys	_calbac 

	; Deallocate BDL buffer (not necessary just before exit!)
	sys	_dalloc, BdlBuffer, 4096
	; Deallocate DMA buffer (not necessary just before exit!)
	sys	_dalloc, DmaBuffer, 65536  ; 14/03/2017
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

DetectVT8233:
	mov     eax, (VT8233_DID << 16) + VIA_VID
        call    pciFindDevice
        jnc     short _1

; couldn't find the audio device!
	sys	_msg, noDevMsg, 255, 0Fh
        jmp     short Exit

_1:
	; 19/06/2017
	; 05/03/2017 (TRDOS 386)
	; 12/11/2016
	; Erdogan Tan - 8/11/2016
	; References: Kolibrios - vt823x.asm (2016)
	;	      VIA VT8235 V-Link South Bridge (VT8235-VIA.PDF)(2002)
	;	      lowlevel.eu - AC97 (2016)
	;	      .wav player for DOS by Jeff Leyda (2002) -this file-
	;	      Linux kernel - via82xx.c (2016)

	; eax = BUS/DEV/FN
	;	00000000BBBBBBBBDDDDDFFF00000000
	; edx = DEV/VENDOR
	;	DDDDDDDDDDDDDDDDVVVVVVVVVVVVVVVV

	mov	[bus_dev_fn], eax
	mov	[dev_vendor], edx

	; init controller
	mov	al, PCI_CMD_REG ; command register (04h)
	call	pciRegRead32

	; eax = BUS/DEV/FN/REG
	; edx = STATUS/COMMAND
	; 	SSSSSSSSSSSSSSSSCCCCCCCCCCCCCCCC
	mov	[stats_cmd], edx

	mov	al, PCI_IO_BASE ; IO base address register (10h)
	call	pciRegRead32

	and     dx, 0FFC0h	; IO_ADDR_MASK (0FFFE) ?
        mov     [ac97_io_base], dx

	mov	al, AC97_INT_LINE ; Interrupt line register (3Ch)
	;call	pciRegRead32
	call	pciRegRead8

	;and 	edx, 0FFh
	and	dx, 0FFh
  	mov     [ac97_int_ln_reg], dl

	retn

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

	; 25/08/2020
;ac97_int_handler:
;	; 03/08/2020
;	; 30/07/2020
;	; Interrupt Handler for VIA VT8237R Audio Controller
;	;(Derived from TRDOS 386 kernel, 'audio.s', 14/10/2017)
;	; 29/07/2020
;	; 15/10/2017
;	; 14/10/2017 
;	; 09/10/2017, 10/10/2017, 12/10/2017
;	; 13/06/2017
;	; 21/04/2017 (TRDOS 386 kernel, 'audio.s')
;	; 24/03/2017 - 'PLAYER.COM' ('player.asm') 
;
;	; 30/07/2020
;	; we are in CALLBACK service
;	; (So, we can not use direct I/O interrupt)
;	; (We can set sometings without using direct I/O, int 34h)
;
;	; 15/10/2017
;	mov	byte [srb], 1
;
;	; 03/08/2020
;	mov 	al, [audio_flag]
;	add	al, '1'
;	mov	ah, 4Eh
;	mov 	[0B8000h], ax ; Display current buffer number
;
;	; 03/08/2020
;	xor	byte [audio_flag], 1
;
;	sys	_rele ; return from callback service 
;	; we must not come here !
;	sys	_exit

;=============================================================================
;               PCI.ASM
;=============================================================================

; EQUATES

;constants of stuff that seem hard to remember at times.

TRUE  EQU 1
FALSE EQU 0

ENABLED  EQU 1
DISABLED EQU 0

BIT0  EQU 1
BIT1  EQU 2
BIT2  EQU 4
BIT3  EQU 8
BIT4  EQU 10h
BIT5  EQU 20h
BIT6  EQU 40h
BIT7  EQU 80h
BIT8  EQU 100h
BIT9  EQU 200h
BIT10 EQU 400h
BIT11 EQU 800h
BIT12 EQU 1000h
BIT13 EQU 2000h
BIT14 EQU 4000h
BIT15 EQU 8000h
BIT16 EQU 10000h
BIT17 EQU 20000h
BIT18 EQU 40000h
BIT19 EQU 80000h
BIT20 EQU 100000h
BIT21 EQU 200000h
BIT22 EQU 400000h
BIT23 EQU 800000h
BIT24 EQU 1000000h
BIT25 EQU 2000000h
BIT26 EQU 4000000h
BIT27 EQU 8000000h
BIT28 EQU 10000000h
BIT29 EQU 20000000h
BIT30 EQU 40000000h
BIT31 EQU 80000000h
NOT_BIT31 EQU 7FFFFFFFh ; 19/03/2017

;special characters
NUL     EQU 0
NULL    EQU 0
BELL    EQU 07
BS      EQU 08
TAB     EQU 09
LF      EQU 10
CR      EQU 13
ESCAPE  EQU 27           ;ESC is a reserved word....

; PCI equates
; PCI function address (PFA)
; bit 31 = 1
; bit 23:16 = bus number     (0-255)
; bit 15:11 = device number  (0-31)
; bit 10:8 = function number (0-7)
; bit 7:0 = register number  (0-255)

IO_ADDR_MASK    EQU     0FFFEh	; mask off bit 0 for reading BARs
PCI_INDEX_PORT  EQU     0CF8h
PCI_DATA_PORT   EQU     0CFCh
PCI32           EQU     BIT31	; bitflag to signal 32bit access
PCI16           EQU     BIT30	; bitflag for 16bit access
NOT_PCI32_PCI16	EQU	03FFFFFFFh ; NOT BIT31+BIT30 ; 19/03/2017

PCI_FN0         EQU     0 << 8
PCI_FN1         EQU     1 << 8
PCI_FN2         EQU     2 << 8
PCI_FN3         EQU     3 << 8
PCI_FN4         EQU     4 << 8
PCI_FN5         EQU     5 << 8
PCI_FN6         EQU     6 << 8
PCI_FN7         EQU     7 << 8

PCI_CMD_REG	EQU	04h	; reg 04, command reg
 IO_ENA		EQU	BIT0	; i/o decode enable
 MEM_ENA	EQU	BIT1	; memory decode enable
 BM_ENA		EQU     BIT2	; bus master enable

; CODE

; PCI device register reader/writers.

; 19/03/2017
; 05/03/2017 (TRDOS 386, INT 34h, IOCTL interrupt modifications)
; NASM version: Erdogan Tan (29/11/2016)

;===============================================================
; 8/16/32bit PCI reader
;
; Entry: EAX=PCI Bus/Device/fn/register number
;           BIT30 set if 32 bit access requested
;           BIT29 set if 16 bit access requested
;           otherwise defaults to 8bit read
;
; Exit:  DL,DX,EDX register data depending on requested read size
;
; Note: this routine is meant to be called via pciRegRead8, pciRegread16,
;	or pciRegRead32, listed below.
;
; Note2: don't attempt to read 32bits of data from a non dword aligned reg
;	 number.  Likewise, don't do 16bit reads from non word aligned reg #
; 
pciRegRead:
	push	ebx
	push	ecx
        mov     ebx, eax		; save eax, dh
        mov     cl, dh

        and     eax, NOT_PCI32_PCI16	; clear out data size request
        or      eax, BIT31		; make a PCI access request
        and     al, ~3 ; NOT 3		; force index to be dword

        mov     dx, PCI_INDEX_PORT
        ;out	dx, eax			; write PCI selector
	push	ebx
	mov	ebx, eax ; Data dword		
	mov	ah, 5	; outd (32 bit write)
	int	34h	
	pop	ebx

        mov     dx, PCI_DATA_PORT
        mov     al, bl
        and     al, 3			; figure out which port to
        add     dl, al			; read to

	; 19/03/2017
	mov	ah, 4  ; ind
	test    ebx, PCI32
        jnz     short _pregr0
	shr	ah, 1  ; ah = 2 ; inw
	test    ebx, PCI16
        jnz     short _pregr0
	sub	ah, ah ; ah = 0 ; inb
_pregr0:	
	int	34h

	test    ebx, PCI32
        jz      short _pregr1

        mov     edx, eax		; return 32bits of data
	jmp	short _pregr2
_pregr1:
	mov	dx, ax			; return 16bits of data
        test    ebx, PCI16
        jnz     short _pregr2
        mov     dh, cl			; restore dh for 8 bit read
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


; 23/03/2017
; 19/03/2017
;===============================================================
; 8/16/32bit PCI writer
;
; Entry: EAX=PCI Bus/Device/fn/register number
;           BIT31 set if 32 bit access requested
;           BIT30 set if 16 bit access requested
;           otherwise defaults to 8bit read
;        DL/DX/EDX data to write depending on size
;
;
; note: this routine is meant to be called via pciRegWrite8, pciRegWrite16,
; 	or pciRegWrite32 as detailed below.
;
; Note2: don't attempt to write 32bits of data from a non dword aligned reg
;	 number.  Likewise, don't do 16bit writes from non word aligned reg #
;
pciRegWrite:
	push	ebx
	push	ecx
        mov     ebx, eax		; save eax, edx
        mov     ecx, edx
	and     eax, NOT_PCI32_PCI16	; clear out data size request
        or      eax, BIT31		; make a PCI access request
        and     al, ~3 ; NOT 3		; force index to be dword

        mov     dx, PCI_INDEX_PORT
        ;out	dx, eax			; write PCI selector
	push	ebx
	mov	ebx, eax ; Data dword		
	mov	ah, 5	; outd (32 bit write)
	int	34h	
	mov	ebx, [esp]

        mov     dx, PCI_DATA_PORT
        mov     al, bl
        and     al, 3			; figure out which port to
        add     dl, al			; write to

	; 19/03/2017
	test    ebx, PCI32+PCI16
        jnz     short _pregw0
	mov	ah, 1
	mov	al, cl 			; put data into al
	;int	34h
	jmp	short _pregw2
_pregw0:
	;mov	ah, 5  ; outd
	test    ebx, PCI32
        jnz     short _pregw1
	mov	ah, 3
_pregw1:
	mov	ebx, ecx		; put data into ebx 		
_pregw2:
	int	34h
	;
	pop	ebx
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

;===============================================================
; PCIFindDevice: scan through PCI space looking for a device+vendor ID
;
; Entry: EAX=Device+Vendor ID
;
;  Exit: EAX=PCI address if device found
;	 EDX=Device+Vendor ID
;        CY clear if found, set if not found. EAX invalid if CY set.
;
; [old stackless] Destroys: ebx, esi, edi, cl
;
pciFindDevice:
	;push	ecx
	push	eax
	;push	esi
	;push	edi

        mov     esi, eax                ; save off vend+device ID
        mov     edi, (80000000h - 100h) ; start with bus 0, dev 0 func 0

nextPCIdevice:
        add     edi, 100h
        cmp     edi, 80FFF800h		; scanned all devices?
        stc
        je      short PCIScanExit       ; not found

        mov     eax, edi                ; read PCI registers
        call    pciRegRead32
        cmp     edx, esi                ; found device?
        jne     short nextPCIdevice
        clc

PCIScanExit:
	pushf
	mov	eax, NOT_BIT31 	; 19/03/2017
	and	eax, edi	; return only bus/dev/fn #
	popf

	;pop	edi
	;pop	esi
	pop	edx
	;pop	ecx
	retn

;=============================================================================
;               CODEC.ASM
;=============================================================================

; EQUATES

;Codec registers.
;
;Not all codecs are created equal. Refer to the spec for your specific codec.
;
;All registers are 16bits wide.  Access to codec registers over the AC97 link
;is defined by the OEM.  
;
;Secondary codec's are accessed by ORing in BIT7 of all register accesses.
;

; each codec/mixer register is 16bits

CODEC_RESET_REG                 equ     00      ; reset codec
CODEC_MASTER_VOL_REG            equ     02      ; master volume
CODEC_HP_VOL_REG                equ     04      ; headphone volume
CODEC_MASTER_MONO_VOL_REG       equ     06      ; master mono volume
CODEC_MASTER_TONE_REG           equ     08      ; master tone (R+L)
CODEC_PCBEEP_VOL_REG            equ     0ah     ; PC beep volume
CODEC_PHONE_VOL_REG             equ     0bh     ; phone volume
CODEC_MIC_VOL_REG               equ     0eh     ; MIC volume
CODEC_LINE_IN_VOL_REG           equ     10h     ; line input volume
CODEC_CD_VOL_REG                equ     12h     ; CD volume
CODEC_VID_VOL_REG               equ     14h     ; video volume
CODEC_AUX_VOL_REG               equ     16h     ; aux volume
CODEC_PCM_OUT_REG               equ     18h     ; PCM output volume
CODEC_RECORD_SELECT_REG         equ     1ah     ; record select input
CODEC_RECORD_VOL_REG            equ     1ch     ; record volume
CODEC_RECORD_MIC_VOL_REG        equ     1eh     ; record mic volume
CODEC_GP_REG                    equ     20h     ; general purpose
CODEC_3D_CONTROL_REG            equ     22h     ; 3D control
; 24h is reserved
CODEC_POWER_CTRL_REG            equ     26h     ; powerdown control
CODEC_EXT_AUDIO_REG             equ     28h     ; extended audio
CODEC_EXT_AUDIO_CTRL_REG        equ     2ah     ; extended audio control
CODEC_PCM_FRONT_DACRATE_REG     equ     2ch     ; PCM out sample rate
CODEC_PCM_SURND_DACRATE_REG     equ     2eh     ; surround sound sample rate
CODEC_PCM_LFE_DACRATE_REG       equ     30h     ; LFE sample rate
CODEC_LR_ADCRATE_REG            equ     32h     ; PCM in sample rate
CODEC_MIC_ADCRATE_REG           equ     34h     ; mic in sample rate

; 30/07/2020
CODEC_MISC_CRTL_BITS_REG	equ	76h	; misc control bits ; AD1980
;	
CODEC_VENDOR_ID1		equ	7Ch	; REALTEK: 414Ch, ADI: 4144h	
CODEC_VENDOR_ID2		equ	7Eh	; REALTEK: 4760h, ADI: 5370h


; Mixer registers 0 through 51h reside in the ICH and are not forwarded over
; the AC97 link to the codec, which I think is a little weird.  Looks like
; the ICH makes it so you don't need a fully functional codec to play audio?
;
; whenever 2 codecs are present in the system, use BIT7 to access the 2nd
; set of registers, ie 80h-feh

PRIMARY_CODEC		equ     0       ; 0-7F for primary codec
SECONDARY_CODEC		equ     BIT7    ; 80-8f registers for 2ndary

SAMPLE_RATE_441khz	equ     44100   ; 44.1Khz (cd quality) rate

; each buffer descriptor BAR holds a pointer which has entries to the buffer
; contents of the .WAV file we're going to play.  Each entry is 8 bytes long
; (more on that later) and can contain 32 entries total, so each BAR is
; 256 bytes in length, thus:

BDL_SIZE                equ     32*8    ; Buffer Descriptor List size
INDEX_MASK              equ     31      ; indexes must be 0-31

;
; Buffer Descriptors List
; As stated earlier, each buffer descriptor list is a set of (up to) 32 
; descriptors, each 8 bytes in length.  Bytes 0-3 of a descriptor entry point
; to a chunk of memory to either play from or record to.  Bytes 4-7 of an
; entry describe various control things detailed below.
; 
; Buffer pointers must always be aligned on a Dword boundry.
;
;

IOC                     equ     BIT31	; Fire an interrupt whenever this
                                        ; buffer is complete.

BUP                     equ     BIT30	; Buffer Underrun Policy.
                                        ; if this buffer is the last buffer
                                        ; in a playback, fill the remaining
                                        ; samples with 0 (silence) or not.
                                        ; It's a good idea to set this to 1
                                        ; for the last buffer in playback,
                                        ; otherwise you're likely to get a lot
                                        ; of noise at the end of the sound.

;
; Bits 15:0 contain the length of the buffer, in number of samples, which
; are 16 bits each, coupled in left and right pairs, or 32bits each.
; Luckily for us, that's the same format as .wav files.
;
; A value of FFFF is 65536 samples.  Running at 44.1Khz, that's just about
; 1.5 seconds of sample time.  FFFF * 32bits is 1FFFFh bytes or 128k of data.
;
; A value of 0 in these bits means play no samples.
;

;VIA VT8233 (VT8235) AC97 Codec equates 
;(edited by Erdogan Tan, 7/11/2016)

; PCI stuff

VIA_VID		equ 1106h	; VIA's PCI vendor ID
VT8233_DID      equ 3059h	; VT8233 (VT8235) device ID
		
PCI_IO_BASE          equ 10h
AC97_INT_LINE        equ 3Ch
VIA_ACLINK_CTRL      equ 41h
VIA_ACLINK_STAT      equ 40h
VIA_ACLINK_C00_READY equ 01h ; primary codec ready
	
VIA_REG_AC97	     equ 80h ; dword

VIA_ACLINK_CTRL_ENABLE	equ   80h ; 0: disable, 1: enable
VIA_ACLINK_CTRL_RESET	equ   40h ; 0: assert, 1: de-assert
VIA_ACLINK_CTRL_SYNC	equ   20h ; 0: release SYNC, 1: force SYNC hi
VIA_ACLINK_CTRL_VRA	equ   08h ; 0: disable VRA, 1: enable VRA
VIA_ACLINK_CTRL_PCM	equ   04h ; 0: disable PCM, 1: enable PCM
VIA_ACLINK_CTRL_INIT	equ  (VIA_ACLINK_CTRL_ENABLE + \
                              VIA_ACLINK_CTRL_RESET + \
                              VIA_ACLINK_CTRL_PCM + \
                              VIA_ACLINK_CTRL_VRA)

CODEC_AUX_VOL		equ   04h
VIA_REG_AC97_BUSY	equ   01000000h ;(1<<24) 
VIA_REG_AC97_CMD_SHIFT	equ   10h ; 16
VIA_REG_AC97_PRIMARY_VALID equ 02000000h ;(1<<25)
VIA_REG_AC97_READ	equ   00800000h ;(1<<23)
VIA_REG_AC97_CODEC_ID_SHIFT   equ  1Eh ; 30
VIA_REG_AC97_CODEC_ID_PRIMARY equ  0
VIA_REG_AC97_DATA_SHIFT equ   0
VIADEV_PLAYBACK         equ   0
VIA_REG_OFFSET_STATUS   equ   0    ;; byte - channel status
VIA_REG_OFFSET_CONTROL  equ   01h  ;; byte - channel control
VIA_REG_CTRL_START	equ   80h  ;; WO
VIA_REG_CTRL_TERMINATE  equ   40h  ;; WO
VIA_REG_CTRL_PAUSE      equ   08h  ;; RW
VIA_REG_CTRL_RESET      equ   01h  ;; RW - probably reset? undocumented
VIA_REG_OFFSET_STOP_IDX equ   08h  ;; dword - stop index, channel type, sample rate
VIA8233_REG_TYPE_16BIT  equ   200000h ;; RW
VIA8233_REG_TYPE_STEREO equ   100000h ;; RW
VIA_REG_OFFSET_CURR_INDEX equ 0Fh ;; byte - channel current index (for via8233 only)
VIA_REG_OFFSET_TABLE_PTR equ  04h  ;; dword - channel table pointer
VIA_REG_OFFSET_CURR_PTR equ   04h  ;; dword - channel current pointer
VIA_REG_OFS_PLAYBACK_VOLUME_L equ  02h ;; byte
VIA_REG_OFS_PLAYBACK_VOLUME_R equ  03h ;; byte
VIA_REG_CTRL_AUTOSTART	equ   20h
VIA_REG_CTRL_INT_EOL	equ   02h
VIA_REG_CTRL_INT_FLAG	equ   01h
VIA_REG_CTRL_INT	equ  (VIA_REG_CTRL_INT_FLAG + \
                              VIA_REG_CTRL_INT_EOL + \
                              VIA_REG_CTRL_AUTOSTART)

VIA_REG_STAT_STOP_IDX	equ   10h    ;; RO ; 30/07/2020
				     ; current index = stop index
; 24/11/2016
VIA_REG_STAT_STOPPED	equ   04h    ;; RWC
VIA_REG_STAT_EOL	equ   02h    ;; RWC
VIA_REG_STAT_FLAG	equ   01h    ;; RWC
VIA_REG_STAT_ACTIVE	equ   80h    ;; RO
; 28/11/2016
VIA_REG_STAT_LAST	equ   40h    ;; RO
VIA_REG_STAT_TRIGGER_QUEUED equ 08h  ;; RO
VIA_REF_CTRL_INT_STOP	equ   04h  ; Interrupt on Current Index = Stop Index
		   ; and End of Block

; 14/03/2017
VIA_REG_OFFSET_CURR_COUNT equ 0Ch ;; dword - channel current count, index

; CODE

; codec configuration code. Not much here really.
; NASM version: Erdogan Tan (29/11/2016)

; enable codec, unmute stuff, set output rate to 44.1
; entry: ax = desired sample rate
;
codecConfig:
	; 14/10/2017
	; 24/06/2017
	; 19/06/2017, 23/06/2017
	; 14/11/2016, 15/11/2016
	; 12/11/2016 - Erdogan Tan (Ref: KolibriOS, 'setup_codec', codec.inc)

	;mov	eax, 0202h
	mov	eax, 0404h ; 23/06/2017
	;mov	[audio_master_volume], ax ; 14/10/2017
	mov	[audio_master_volume], al ; 14/10/2017
	mov	edx, CODEC_MASTER_VOL_REG ; 02h ; Line Out
	call	codec_write
	;jc	cconfig_error

	mov     eax, 0202h
	mov	edx, CODEC_PCM_OUT_REG ; 18h ; Wave Output (Stereo)
	call	codec_write
	;jc	cconfig_error
      
	mov	eax, 0202h
	mov	edx, CODEC_AUX_VOL ; 04h ; CODEC_HP_VOL_REG ; HeadPhone
	call	codec_write
	;jc	cconfig_error

        mov     eax, 8008h ; Mute
        mov	edx, 0Ch  ; AC97_PHONE_VOL ; TAD Input (Mono)
	call	codec_write
	;jc	short cconfig_error

        mov     eax, 0808h
        mov	edx, CODEC_LINE_IN_VOL_REG ; 10h ; Line Input (Stereo)	
	call	codec_write
	;jc	short cconfig_error

	mov     eax, 0808h
        mov	edx, CODEC_CD_VOL_REG ; 12h ; CR Input (Stereo)
	call	codec_write
	;jc	short cconfig_error

	mov     eax, 0808h
        mov	edx, CODEC_AUX_VOL_REG ; 16h ; Aux Input (Stereo)
;	call	codec_write
;	;jc	short cconfig_error

;	; Extended Audio Status (2Ah)
;	mov	eax, CODEC_EXT_AUDIO_CTRL_REG ; 2Ah 
;	call	codec_read
;       and     eax, 0FFFFh - 2 ; clear DRA (BIT1)
;       ;or     eax, 1		; set VRA (BIT0)
;	or	eax, 5  	; VRA (BIT0) & S/PDIF (BIT2) ; 14/11/2016
;	mov	edx, CODEC_EXT_AUDIO_CTRL_REG
;	call	codec_write
;	;jc	short cconfig_error
;
;	; 24/06/2017
;set_sample_rate:
;       movzx	eax, word [sample_rate]
;	mov	edx, CODEC_PCM_FRONT_DACRATE_REG ; 2Ch ; PCM Front DAC Rate
;       ;call	codec_write
;	;retn
	jmp	codec_write

;cconfig_error:
;	retn

reset_codec:
	; 23/03/2017
	; 12/11/2016 - Erdogan Tan (Ref: KolibriOS, vt823x.asm)
	mov	eax, [bus_dev_fn]
 	mov	al, VIA_ACLINK_CTRL
       	mov	dl, VIA_ACLINK_CTRL_ENABLE + VIA_ACLINK_CTRL_RESET + VIA_ACLINK_CTRL_SYNC
	call	pciRegWrite8

	call	delay_100ms 	; wait 100 ms
_rc_cold:
        call    cold_reset
        jnc     short _reset_codec_ok

        xor     eax, eax         ; timeout error
        retn

_reset_codec_ok:
	; 30/07/2020
	; also reset codec by using index control register 0 of AD1980 or ALC655
	; (to fix line out -2 channels audio playing- problem on AD1980 codec)  

	sub	eax, eax
	mov	edx, CODEC_RESET_REG ; 00h ; Reset register
	call	codec_write

	sub	eax, eax
	mov	edx, CODEC_MISC_CRTL_BITS_REG ; 76h ; Misc Ctrl Bits ; AD1980
	call	codec_write
	;

        xor     eax, eax
        ;mov	al, VIA_ACLINK_C00_READY ; 1
        inc	al
	retn

cold_reset:
	; 23/03/2017
	; 12/11/2016 - Erdogan Tan (Ref: KolibriOS, vt823x.asm)
	;mov	eax, [bus_dev_fn]
	;mov	al, VIA_ACLINK_CTRL
	xor	dl, dl ; 0
	call	pciRegWrite8

	call	delay_100ms 	; wait 100 ms

	;; ACLink on, deassert ACLink reset, VSR, SGD data out
        ;; note - FM data out has trouble with non VRA codecs !!
        
	;mov	eax, [bus_dev_fn]
	;mov	al, VIA_ACLINK_CTRL
	mov	dl, VIA_ACLINK_CTRL_INIT
	call	pciRegWrite8

	mov	ecx, 16	; total 2s

_crst_wait:
	;mov	eax, [bus_dev_fn]
	mov	al, VIA_ACLINK_STAT
	call	pciRegRead8	

        test    dl, VIA_ACLINK_C00_READY
        jnz     short _crst_ok

	push	ecx
	call	delay_100ms
	pop	ecx

        dec     ecx
        jnz     short _crst_wait

_crst_fail:
        stc
_crst_ok:
	retn

codec_io_w16: ;w32
        mov	dx, [ac97_io_base]
        add     dx, VIA_REG_AC97
	;out	dx, eax
	; 05/03/2017
	push	ebx
	mov	ebx, eax
	mov	ah, 5 ; outd
	int	34h
	pop	ebx
        retn

codec_io_r16: ;r32
        mov     dx, [ac97_io_base]
        add     dx, VIA_REG_AC97
        ;in	eax, dx
	; 05/03/2017
	mov	ah, 4 ; ind
	int	34h
        retn

ctrl_io_w8:
        add     dx, [ac97_io_base]
        ;out	dx, al
	; 05/03/2017
	mov	ah, 1 ; outb
	int	34h
        retn

ctrl_io_r8:
        add     dx, [ac97_io_base]
        ;in	al, dx
	; 05/03/2017
	mov	ah, 0 ; inb
	int	34h
        retn

ctrl_io_w32:
        add     dx, [ac97_io_base]
        ;out	dx, eax
	; 05/03/2017
	push	ebx
	mov	ebx, eax
	mov	ah, 5 ; outd
	int	34h
	pop	ebx
        retn

ctrl_io_r32:
        add	dx, [ac97_io_base]
	;in	eax, dx
	; 05/03/2017
	mov	ah, 4 ; ind
	int	34h
        retn

codec_read:
	; 12/11/2016 - Erdogan Tan (Ref: KolibriOS, vt823x.asm)
        ; Use only primary codec.
        ; eax = register
        shl     eax, VIA_REG_AC97_CMD_SHIFT
        or      eax, VIA_REG_AC97_PRIMARY_VALID + VIA_REG_AC97_READ

	call    codec_io_w16

      	; codec_valid
	call	codec_check_ready
        jnc	short _cr_ok

	retn

_cr_ok:
	; wait 25 ms
	mov	ecx, 80
_cr_wloop:
	call	delay1_4ms
	loop	_cr_wloop

        call    codec_io_r16
        and     eax, 0FFFFh
        retn

codec_write:
	; 12/11/2016 - Erdogan Tan (Ref: KolibriOS, vt823x.asm)
        ; Use only primary codec.
        
	; eax = data (volume)
	; edx = register (mixer register)
	
	shl     edx, VIA_REG_AC97_CMD_SHIFT

        shl     eax, VIA_REG_AC97_DATA_SHIFT ; shl eax, 0
        or      edx, eax

        mov     eax, VIA_REG_AC97_CODEC_ID_PRIMARY
        shl     eax, VIA_REG_AC97_CODEC_ID_SHIFT
        or      eax, edx

        call    codec_io_w16
        ;mov    [codec.regs+esi], ax

        ;call	codec_check_ready
       	;retn
	;jmp	short _codec_check_ready	

codec_check_ready:
	; 12/11/2016 - Erdogan Tan (Ref: KolibriOS, vt823x.asm)

_codec_check_ready:
	mov	ecx, 20	; total 2s
_ccr_wait:
	push	ecx

        call    codec_io_r16
        test    eax, VIA_REG_AC97_BUSY
        jz      short _ccr_ok

	call	delay_100ms

	pop	ecx

	dec     ecx
        jnz     short _ccr_wait

        stc
        retn

_ccr_ok:
	pop	ecx
	and     eax, 0FFFFh
        retn

channel_reset:
	; 24/06/2017
	; 29/05/2017
	; 23/03/2017
	; 14/11/2016 - Erdogan Tan
	; 12/11/2016 - Erdogan Tan (Ref: KolibriOS, vt823x.asm)
        mov	edx, VIA_REG_OFFSET_CONTROL
        ;mov	eax, VIA_REG_CTRL_PAUSE + VIA_REG_CTRL_TERMINATE + VIA_REG_CTRL_RESET
        mov	eax, VIA_REG_CTRL_PAUSE + VIA_REG_CTRL_TERMINATE ; 24/06/2017        
	call    ctrl_io_w8

        ;mov	edx, VIA_REG_OFFSET_CONTROL
        ;call   ctrl_io_r8

	mov	ecx, 160 ; 200 (50 ms)	
_ch_rst_wait:
	call	delay1_4ms
	dec	ecx
	jnz	short _ch_rst_wait     

        ; disable interrupts
        mov	edx, VIA_REG_OFFSET_CONTROL
        xor     eax, eax
        call    ctrl_io_w8

        ; clear interrupts
        mov	edx, VIA_REG_OFFSET_STATUS
	mov	eax, 3
        call	ctrl_io_w8

	;mov	edx, VIA_REG_OFFSET_CURR_PTR
	;xor	eax, eax
	;call	ctrl_io_w32

        retn

loadFromFile:
	; 17/03/2017
	; edi = buffer address
	; edx = buffer size
	; 10/03/2017
        ;push	eax
        ;push	ecx
        ;push	edx
	;push	ebx
        test    byte [eof_flag], ENDOFFILE	; have we already read the
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
	je	short _7
	; Minimum Value = 0
        xor     al, al
	rep	stosb
_6:
        ;clc			; don't exit with CY yet.
        or	byte [eof_flag], ENDOFFILE	; end of file flag
endLFF:
	;pop	ebx
	;pop	edx
        ;pop	ecx
        ;pop	eax
        retn
_7:
	; Minimum value = 8000h (-32768)
	shr	ecx, 1 
	mov	ax, 8000h ; -32768
	rep	stosw
	jmp	short _6

;=============================================================================
;               VIA_WAV.ASM
;=============================================================================

; DOS based .WAV player using AC'97 and codec interface.
; ---------------------------------------------------------------
; VIA VT8233 Modification & NASM version: Erdogan Tan (29/11/2016)
; Last Update: 08/12/2016 (by Erdogan Tan)

; player internal variables and other equates.
BUFFERSIZE      equ     32768	; 32K half buffer size. ; 14/03/2017
ENDOFFILE       equ     BIT0	; flag for knowing end of file

;===========================================================================
; entry: none.  File is already open and [filehandle] filled.
; exit:  not until the song is finished or the user aborts.
;
	; 14/10/2017
	; 17/03/2017
PlayWav:
       ; load 32768 bytes into half buffer 1

	mov     edi, DmaBuffer
	mov	edx, BUFFERSIZE
	call	loadFromFile

	; 30/07/2020
	test    byte [eof_flag], ENDOFFILE  ; end of file
	jnz	short _8 ; yes
			 ; bypass filling dma half buffer 2

	mov	byte [audio_flag], 1

	; load 32768 bytes into half buffer 2

	mov	edi, DmaBuffer
	mov	edx, BUFFERSIZE
	add	edi, edx
	call	loadFromFile

_8:

; write last valid index to 31 to start with.
; The Last Valid Index register tells the DMA engine when to stop playing.
; 
; As we progress through the song we change the last valid index to always be
; something other than the index we're currently playing.  
;
        ;;mov   al, 1
        ;mov	al, 31
	;call   setLastValidIndex

; create Buffer Descriptor List
;
; A buffer descriptor list is a list of pointers and control bits that the
; DMA engine uses to know where to get the .wav data and how to play it.
;
; I set it up to use only 2 buffers of .wav data, and whenever 1 buffer is
; playing, I refresh the other one with good data.
;
;
; For the control bits, you can specify that the DMA engine fire an interrupt
; after a buffer has been processed, but I poll the current index register
; to know when it's safe to update the other buffer.
;
; I set the BUP bit, which tells the DMA engine to just play 0's (silence)
; if it ever runs out of data to play.  Good for safety.
;
	; 05/03/2017 (32 bit buffer addresses)

	; 14/02/2017
        mov     edi, BdlBuffer		; get BDL address
	; ecx <= 32768 ; 29/07/2020
        mov     cx, 32 / 2		; make 32 entries in BDL
_0:

; set buffer descriptor 0 to start of data file in memory

        mov	eax, [DMA_phy_buff]	; Physical address of DMA buffer
        stosd				; store dmabuffer1 address

	mov	edx, eax ; 05/03/2017

;
; set length to 32k samples. 1 sample is 16bits or 2bytes.
; Set control (bits 31:16) to BUP, bits 15:0=number of samples.
; 

; VIA VT8235.PDF: (Page 110) (Erdogan Tan, 29/11/2016)
	;
	; 	Audio SGD Table Format
	;	-------------------------------
	;	63   62    61-56    55-32  31-0
	;	--   --   --------  -----  ----
	;	EOL FLAG -reserved- Base   Base
	;		    	    Count  Address
	;		            [23:0] [31:0]
	;	EOL: End Of Link. 
	;	     1 indicates this block is the last of the link.
	;	     If the channel “Interrupt on EOL” bit is set, then
	;	     an interrupt is generated at the end of the transfer.
	;
	;	FLAG: Block Flag. If set, transfer pauses at the end of this
	;	      block. If the channel “Interrupt on FLAG” bit is set,
	;	      then an interrupt is generated at the end of this block.

	FLAG	EQU BIT30
	EOL	EQU BIT31

	; 08/12/2016 - Erdogan Tan
	mov	eax, BUFFERSIZE ; DMA half buffer size ; 30/07/2020
	add	edx, eax ; 05/03/2017
	or	eax, FLAG
	;or	eax, EOL
	stosd

; 2nd buffer:

        mov	eax, edx ; Physical address of the 2nd half of DMA buffer	
	stosd		 ; store dmabuffer2 address

; set length to 64k (32k of two 16 bit samples)
; Set control (bits 31:16) to BUP, bits 15:0=number of samples
; 
	; 08/12/2016 - Erdogan Tan
	;mov	eax, BUFFERSIZE
	;or	eax, EOL
	; 29/07/2020
	;or	eax, FLAG
	mov	eax, BUFFERSIZE | FLAG
	stosd

        loop    _0

	; 30/07/2020
	or	dword [edi-4], EOL

;
; tell the DMA engine where to find our list of Buffer Descriptors.
; this 32bit value is a flat mode memory offset (ie no segment:offset)
;
; write buffer descriptor list address
;
	; Extended Audio Status (2Ah)
	mov	eax, CODEC_EXT_AUDIO_CTRL_REG ; 2Ah 
	call	codec_read
	;and     eax, 0FFFFh - 2	; clear DRA (BIT1)
	; 03/08/2020
	and	eax, ~3802h  ; modification for AD1980 
	;;or	eax, 1		; set VRA (BIT0)
	;or	eax, 5  	; VRA (BIT0) & S/PDIF (BIT2) ; 14/11/2016
	or	al, 5 ; 03/08/2020
	mov	edx, CODEC_EXT_AUDIO_CTRL_REG
	call	codec_write
	;jc	short cconfig_error

set_sample_rate:
	;movzx	eax, word [audio_freq]
	mov	ax, [audio_freq]
	mov	edx, CODEC_PCM_FRONT_DACRATE_REG ; 2Ch ; PCM Front DAC Rate
	call	codec_write

	; 14/10/2017
        mov	eax, [BDL_phy_buff] ; Physical address of the BDL
	  
	; 12/11/2016 - Erdogan Tan 
	; (Ref: KolibriOS, vt823x.asm, 'create_primary_buff')
	mov	edx, VIADEV_PLAYBACK + VIA_REG_OFFSET_TABLE_PTR
        call	ctrl_io_w32

	;call	codec_check_ready

  	mov	dx, VIADEV_PLAYBACK + VIA_REG_OFS_PLAYBACK_VOLUME_L
        ;mov	eax, 2	; 31
	; 30/07/2020
	;mov	al, 31
        ;sub	al, [audio_master_volume_l]
	mov	al, [audio_master_volume]  ; 14/10/2017
	call	ctrl_io_w8

	;call	codec_check_ready

        mov     dx, VIADEV_PLAYBACK + VIA_REG_OFS_PLAYBACK_VOLUME_R
        ;mov	ax, 2	; 31
	; 30/07/2020
	;mov	al, 31
        ;sub	al, [audio_master_volume_r]
	mov	al, [audio_master_volume]  ;14/10/2017
	call    ctrl_io_w8

	;call	codec_check_ready
;
;
; All set. Let's play some music.
;
;
       	;mov    dx, VIADEV_PLAYBACK + VIA_REG_OFFSET_STOP_IDX
        ;mov    ax, VIA8233_REG_TYPE_16BIT or VIA8233_REG_TYPE_STEREO or 0xfffff or 0xff000000
        ;call   ctrl_io_w32

	;call	codec_check_ready

	; 08/12/2016
	; 07/10/2016
        ;mov    al, 1	
	; 29/07/2020
	;mov	al, 31
	mov	al, 0FFh
	call    set_VT8233_LastValidIndex

	; 25/08/2020
	;mov	byte [audio_play_cmd], 1 ; play command (do not stop) !
	
	; 14/10/2017
	mov 	al, [audio_flag]
	add	al, '1'
	mov	ah, 4Eh
	mov 	[0B8000h], ax ; Display current buffer number

vt8233_play: ; continue to play
	; 22/04/2017
        ;mov	al, VIA_REG_CTRL_INT
       	;or	al, VIA_REG_CTRL_START
        ;;mov	al, VIA_REG_CTRL_AUTOSTART + VIA_REG_CTRL_START
	; 29/07/2020
	mov	al, VIA_REG_CTRL_AUTOSTART + VIA_REG_CTRL_START + VIA_REG_CTRL_INT_FLAG
	mov     dx, VIADEV_PLAYBACK + VIA_REG_OFFSET_CONTROL
        call    ctrl_io_w8
	;call	codec_check_ready
	;retn
	;jmp	codec_check_ready

	; 14/10/2017
	mov	byte [volume_level], 1Fh-04h ; initial value

	jmp	short p_loop ; 14/10/2017

;input AL = index # to stop on
set_VT8233_LastValidIndex:
	; 29/07/2020
	; 10/06/2017
	; 21/04/2017 (TRDOS 386 kernel, 'audio.s')
	; 24/03/2017 - 'PLAYER.COM' ('via_wav.asm' - 29/11/2016) 
	; 19/11/2016
	; 14/11/2016 - Erdogan Tan (Ref: VIA VT8235.PDF, Page 110)
	; 12/11/2016 - Erdogan Tan
	; (Ref: KolibriOS, vt823x.asm, 'create_primary_buff')
	;push	edx
	;push	ax
	push	eax ; 29/07/2020
	;push	ecx
	movzx	eax, word [audio_freq] ; Hertz
	mov	edx, 100000h ; 2^20 = 1048576
	mul	edx
	mov	ecx, 48000	
	div	ecx
	;and	eax, 0FFFFFh
	;pop	ecx
	;pop	dx 
	pop	edx ; 29/07/2020
	shl	edx, 24  ; STOP Index Setting: Bit 24 to 31
	or	eax, edx
	; 19/11/2016
	cmp	byte [audio_bps], 16
	jne	short sLVI_1
	or	eax, VIA8233_REG_TYPE_16BIT
sLVI_1:
	cmp	byte [audio_stmo], 2
	jne	short sLVI_2
	or	eax, VIA8233_REG_TYPE_STEREO
sLVI_2:
	mov     edx, VIADEV_PLAYBACK + VIA_REG_OFFSET_STOP_IDX
        call    ctrl_io_w32
	;call	codec_check_ready
	;pop	edx
	retn

	; 03/08/2020
	; 30/07/2020
	; 15/10/2017
	; 14/10/2017
	; 21/04/2017
	; 17/03/2017
	; 05/03/2017 (TRDOS 386)
	; 14/02/2017
	; 13/02/2017
	; 08/12/2016
	; 28/11/2016
p_loop:
	; 15/10/2017
	cmp	byte [srb], 0
	jna	short q_loop

	mov	byte [srb], 0

	; 03/08/2020
	;; 01/08/2020
	;mov	al, '0'
	;mov	ah, 4Eh
	;mov 	[0B8000h], ax ; Display current buffer number

	; 30/07/2020
	call	ac97_int_ack
	
	mov	edi, DmaBuffer
	mov	edx, BUFFERSIZE ; DMA half buffer size

	cmp	byte [audio_flag], 0
	jna	short p_load_buffer

	add	edi, edx  ; 2nd half of DMA buffer

p_load_buffer:
	call	loadFromFile
	jc	short p_return  ; EOF or read error. 

q_loop:
	; 15/10/2017
	mov     ah, 1		; any key pressed?
	int     32h		; no, Loop.
	jz	short r_loop

	mov     ah, 0		; flush key buffer...
	int     32h

	; 14/10/2017
	; 09/10/2017 (playmod5.s)
	cmp	al, '+' ; increase sound volume
	je	short inc_volume_level
	cmp	al, '-'
	je	short dec_volume_level

p_return:
	; 25/08/2020
	;mov	byte [audio_play_cmd], 0

	; 23/06/2017
_exit_:
	; 24/06/2017
	; finished with song, stop everything
	;mov	al, VIA_REG_CTRL_INT
	;or	al, VIA_REG_CTRL_TERMINATE
	;mov	dx, VIADEV_PLAYBACK + VIA_REG_OFFSET_CONTROL
	;call	ctrl_io_w8

	jmp	channel_reset

r_loop:
	; 30/07/2020
	dec	word [counter]
	mov	ax, [counter]
	cmp	ax, 32767
	ja	short t_loop
	or	ax, ax
	jz	short s_loop
	jmp	p_loop
s_loop:
	mov	al, ' '
	jmp	short v_loop
t_loop:
	cmp	ax, 65535
	je	short u_loop
	jmp	p_loop
u_loop:
	mov	al, '.'
v_loop:
	mov	ah, 0Eh
	mov	[0B8002h], ax
	jmp	p_loop
	
	; 09/10/2017 (playmod5.s)
	; 24/06/2017 (wavplay2.s)
inc_volume_level:
	mov	cl, [volume_level]
	cmp	cl, 1Fh ; 31
	;jnb	short p_loop ; 15/10/2017
	jnb	p_loop ; 30/07/2020
	inc	cl
change_volume_level:
	mov	[volume_level], cl
	; 30/07/2020
	mov	ch, cl ; same volume level for L & R
	; Set Master Volume Level
	call	set_master_volume_level ; 14/10/2017
	jmp	p_loop ; 15/10/2017
dec_volume_level:
	mov	cl, [volume_level]
	cmp	cl, 1 ; 1
	jna	p_loop ; 15/10/2017
	dec	cl
	jmp	short change_volume_level

set_master_volume_level:
vt8233_volume:
	; 30/07/2020
	; 14/10/2017
	; set VT8237R (vt8233) sound volume level
	; 24/04/2017 (TRDOS 386 kernel, 'audio.s')
	; 22/04/2017
	; bl = component (0 = master/playback/lineout volume)
	; cl = left channel volume level (0 to 31)
	; ch = right channel volume level (0 to 31)

	;or	bl, bl
	;jnz	short vt8233_vol_1 ; temporary !
	mov	ax, 1F1Fh ; 31,31
	;cmp	cl, al
	;ja	short vt8233_vol_1 ; temporary !
	;cmp	ch, ah
	;ja	short vt8233_vol_1 ; temporary !
	;mov	[audio_master_volume], cx

	; 30/07/2020
	sub	ax, cx
	mov	[audio_master_volume], ax
	;
	mov	edx, CODEC_MASTER_VOL_REG ; 02h ; Line Out
	call	codec_write
vt8233_vol_1:
	retn

delay_100ms:
	; wait 100 ms
	;mov	ecx, 400  ; 400*0.25ms  ; 29/05/2017
	mov	ecx, 100  ; 23/06/2017
_delay_x_ms:
	call	delay1_4ms
        loop	_delay_x_ms
	retn

;       delay1_4ms - Delay for 1/4 millisecond.
;	    1mS = 1000us
;       Entry:
;         None
;       Exit:
;	  None
;
;       Modified:
;         None
;
PORTB		EQU	061h
REFRESH_STATUS	EQU	010h	; Refresh signal status

	; 29/05/2017
	; 05/03/2017 (TRDOS 386)
delay1_4ms:
        push    eax 
        push    ecx
        ;mov	cl, 16		; close enough.
	mov	cl, 12 ; + INT 34h delay	

	;in	al, PORTB
	
	mov	dx, PORTB
	sub	ah, ah ; 0 ; inb
	int	34h
	
	and	al, REFRESH_STATUS
	mov	ch, al		; Start toggle state
_d4ms1:	
	;in	al, PORTB	; Read system control port
	
	;mov	ah, 0 ; inb
	;mov	dx, PORTB
	int	34h
	
	and	al, REFRESH_STATUS ; Refresh toggles 15.085 microseconds
	cmp	ch, al
	je	short _d4ms1	; Wait for state change

	mov	ch, al		; Update with new state
	dec	cl
	jnz	short _d4ms1

        pop     ecx
        pop     eax
        retn

ac97_int_ack:
	; 30/07/2020
	; Interrupt Handler for VIA VT8237R Audio Controller
	;(Derived from TRDOS 386 kernel, 'audio.s', 14/10/2017)
	; Note: I have moved following code here because
	; callback service can not use int 35h (direct I/O) interrupt
	; (we must check VT8233 interrupt status and
	; clear/ack interrupt after callback service while [srb] = 1)

	; 30/07/2020
	; mov	byte [srb], 1

	; [srb] = 1

	; 29/07/2020
	; 15/10/2017
	; 14/10/2017 
	; 09/10/2017, 10/10/2017, 12/10/2017
	; 13/06/2017
	; 21/04/2017 (TRDOS 386 kernel, 'audio.s')
	; 24/03/2017 - 'PLAYER.COM' ('player.asm') 

	;push	eax ; * must be saved !
	;push	edx
	;push	ecx
	;push	ebx ; * must be saved !
	;push	esi
	;push	edi

	; 14/10/2017
	;mov	byte [srb], 1	

	;cmp	byte [audio_busy], 1
	;jnb	short _ih0 ; 09/10/2017

	;mov	byte [audio_flag_eol], 0

	; 25/08/2020
	;mov	dx, VIADEV_PLAYBACK + VIA_REG_OFFSET_STATUS
        ;call	ctrl_io_r8
	;
	;test	al, VIA_REG_STAT_ACTIVE
        ;;jz	short _ih0 ; 09/10/2017
	;jz	short _ih1 ; 25/08/2020
	;
        ;and	al, VIA_REG_STAT_EOL + VIA_REG_STAT_FLAG + VIA_REG_STAT_STOPPED
	;mov	[audio_flag_eol], al
        ;;jz	short _ih0 ; 09/10/2017
	;jz	short _ih1 ; 25/08/2020

	; 09/10/2017
	;mov	byte [audio_busy], 1

	;cmp	byte [audio_play_cmd], 1
	;jnb	short _ih1 ; 10/10/2017
	;
	;call	channel_reset

	; 25/08/2020
_ih0:
	; 09/10/2017
	;mov	al, [audio_flag_eol]   ;; ack ;;
	mov	al, 7 ; 25/08/2020
	mov     dx, VIADEV_PLAYBACK + VIA_REG_OFFSET_STATUS
	call    ctrl_io_w8
	;jmp	short _ih3

	;; 25/08/2020
	;cmp	byte [audio_play_cmd], 1
	;jnb	short _ih1
	;
	;call	channel reset
	;
	;stc
	;retn

_ih1:
;vt8233_tuneLoop:
;	;mov	al, [audio_flag_eol]   ;; ack ;;
;	mov	al, 7 ; 25/08/2020
;	mov     dx, VIADEV_PLAYBACK + VIA_REG_OFFSET_STATUS
;	call    ctrl_io_w8

	; 29/07/2020
	; 12/10/2017
	;mov	byte [audio_flag], 0 ; Reset

	; 10/10/2017
	; 09/10/2017
	;test	byte [audio_flag_eol], VIA_REG_STAT_FLAG
	;jz	short _ih2 ; EOL

	; 29/07/2020
	; 14/10/2017
	;test	byte [audio_flag_eol], VIA_REG_STAT_EOL
	;jnz	short _ih2 ; EOL
	;		   ; (Half Buffer 2 has been completed 
	;		   ; and Half Buffer 1 will be played.)
	
	; FLAG  
	; (Half Buffer 1 has been completed 
	;  and Half Buffer 2 will be played.)

	; 14/10/2017
	;; (Continue to play.)
	;mov	al, VIA_REG_CTRL_INT
       	;or	al, VIA_REG_CTRL_START
       	;mov	dx, VIADEV_PLAYBACK + VIA_REG_OFFSET_CONTROL
        ;call	ctrl_io_w8
	; 12/10/2017
	;mov	byte [audio_flag], 1 
	; 29/07/2020
	;inc	byte [audio_flag] ; = 1
_ih2: 
	; Update half buffer 2 while playing half buffer 1 (FLAG)
	; Update half buffer 1 while playing half buffer 2 (EOL)
	
	; 30/07/2020
	;mov 	al, [audio_flag]
	;add	al, '1'
	;mov	ah, 4Eh
	;mov 	[0B8000h], ax ; Display current buffer number

	; 25/08/2020
	; switch flag value ;
	xor	byte [audio_flag], 1 ; 10/10/2017 

	; 12/10/2017
	; [audio_flag] = 0 : Playing dma half buffer 2 (just after FLAG)
			   ; Next buffer (to update) is dma half buff 1
	; 	       = 1 : Playing dma half buffer 1 (just after EOL)
			   ; Next buffer (to update) is dma half buff 2
	; 30/07/2020
	; 15/10/2017
	;mov	byte [srb], 1
_ih3:	
	; 28/05/2017
	;mov	byte [audio_busy], 0 ; 09/10/2017
	;
	;pop	edi
	;pop	esi
	;pop	ebx ; * must be restored !
	;pop	ecx
	;pop	edx
	;pop	eax ; * must be restored !

_ih4:	; 14/10/2017
	;sys	_rele ; return from callback service 
	;; we must not come here !
	;sys	_exit

	; 30/07/2020
	retn

; ---------------------------------------------------------------------

	; 05/03/2017 (TRDOS 386)
	; 13/11/2016 - Erdogan Tan
write_ac97_dev_info:
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
	jnz	short _pmi
	mov	al, [msgIRQ+1]
	mov	ah, ' '
	mov	[msgIRQ], ax
_pmi:
	; EBX = Message address
	; ECX = Max. message length (or stop on ZERO character)
	;	(1 to 255)
	; DL  = Message color (07h = light gray, 0Fh = white) 
     	sys 	_msg, msgAC97Info, 255, 07h
        retn

;=============================================================================
;               preinitialized data
;=============================================================================

noDevMsg:
	db "Error: Unable to find VIA VT8233 based audio device!",CR,LF,0

CodecErrMsg:
	db	"Codec Error !", CR,LF,0

msg_usage:
	db	'usage: wavplay filename.wav',10,13,0
Credits:
	db	'Tiny WAV Player for TRDOS 386 by Erdogan Tan. '
	db	'August 2020.',10,13,0
	db	'15/10/2017', 10,13,0
	db	'25/08/2020', 10,13,0 

noFileErrMsg:
	db	'Error: file not found.',10,13,0

trdos386_err_msg:
	db	'TRDOS 386 System call error !',10,13,0

FileHandle:	
	dd	-1

; 13/11/2016
hex_chars:	db "0123456789ABCDEF", 0
msgAC97Info:	db "AC97 Audio Controller & Codec Info", 0Dh, 0Ah 
		db "Vendor ID: "
msgVendorId:	db "0000h Device ID: "
msgDevId:	db "0000h", 0Dh, 0Ah
		db "Bus: "
msgBusNo:	db "00h Device: "
msgDevNo:	db "00h Function: "
msgFncNo:	db "00h"
		db 0Dh, 0Ah
		db "I/O Base Address: "
msgIOBaseAddr:	db "0000h IRQ: "
msgIRQ:		dw 3030h
		db 0Dh, 0Ah, 0
msgSampleRate:	db "Sample Rate: "
msgHertz:	db "00000 Hz ", 0
msg8Bits:	db "8 bits ", 0
msgMono:	db "Mono", 0Dh, 0Ah, 0
msg16Bits:	db "16 bits ", "$" 
msgStereo:	db "Stereo", 0Dh, 0Ah, 0

;; 13/11/2016 - Erdogan Tan (Ref: KolibriOS, codec.inc)
;codec_id:	   dd 0
;codec_chip_id:	   dd 0
;codec_vendor_ids: dw 0
;codec_chip_ids:   dw 0

;dword_str:	dd 30303030h, 30303030h
;	 	db 'h', 0Dh, 0Ah, 0

;=============================================================================
;        	uninitialized data
;=============================================================================

bss_start:

ABSOLUTE bss_start

alignb 4

eof_flag:	resb 1
srb:		resb 1
audio_busy:	resb 1
; 25/08/2020 
;audio_play_cmd: resb 1

audio_flag_eol:	resb 1
audio_flag:	resb 1

ac97_int_ln_reg: resb 1 
ac97_io_base:	resw 1

bus_dev_fn:	resd 1
dev_vendor:	resd 1
stats_cmd:	resd 1

; 14/10/2017 (audio_stmo, audio_bps, audio_freq)
stmo:
audio_stmo: 	resb 1 ; stereo or mono  
bps:
audio_bps: 	resb 1 ; bits per sample (16)
sample_rate:
audio_freq:	resw 1

smpRBuff:	resw 14 

wav_file_name:
		resb 80
alignb 4

BDL_phy_buff:	resd 1
DMA_phy_buff:	resd 1

; 14/10/2017
audio_master_volume:
;audio_master_volume_l: resb 1 ; sound volume (lineout) left channel
;audio_master_volume_r: resb 1 ; sound volume (lineout) right channel
		resb 1
volume_level:
		resb 1
; 30/07/2020
counter:	resw 1

alignb 4096

BdlBuffer:	resb 4096 ; BDL_SIZE (round up to 1 page)

alignb 65536
DmaBuffer:	resb 65536 ; 2 * BUFFERSIZE
EOF: