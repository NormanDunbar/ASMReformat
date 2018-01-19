;--------------------------------------------------------------------
; ASMReformat:
;
; A filter program using an input and output channel, passed on
; the stack for its files.
; 
; EX ASMReformat_bin, input_file, output_file_or_channel
;
;--------------------------------------------------------------------
; 29/12/2017 NDunbar Created for QDOSMSQ Assembly Mailing List
;--------------------------------------------------------------------
; (c) Norman Dunbar, 2017. Permission granted for unlimited use
; or abuse, without attribution being required. Just enjoy!
;--------------------------------------------------------------------

me
           equ     -1                  ; This job
infinite
           equ     -1                  ; For timeouts
err_bp
           equ     -15                 ; Bad parameter error
err_ef
           equ     -10                 ; End of file


; Flag bits in D5.B:
inComment
           equ     0                   ; No comments on this line
noOperand
           equ     1                   ; This opcode has no operands
continue
           equ     2                   ; Operand continues on next line
lfRequired
           equ     3                   ; Do I need to print a linefeed?

flagMask
           equ     %11110100           ; Reset incomment, noOperand, lfRequired
lowerCase2
           equ     $2020               ; Mask to lowercase 2 characters
lowerCase1
           equ     $20                 ; Mask to lowercase 1 characters


; Various character constants.
linefeed
           equ     $0A                 ; You can probably guess these!
space
           equ     $20
comma
           equ     ','
tab
           equ     $09
semiColon
           equ     ';'
asterisk
           equ     '*'
dQuote
           equ     '"'
sQuote
           equ     "'"

; Where the text goes on the output line(s). We need to offset
; these by -1 as we count from zero in the buffers.
labelPos
           equ     1-1                 ; Labels in column 1
opcodePos
           equ     12-1                ; Opcodes in column 12
operandPos
           equ     20-1                ; Operands in column 20
commentPos
           equ     40-1                ; Comments in column 40


; Stack stuff.
sourceId
           equ     $02                 ; Offset(A7) to input file id
destId
           equ     $06                 ; Offset(A7) to output file id
paramSize
           equ     $0A                 ; Offset(A7) to command string size
paramStr
           equ     $0C                 ; Offset(A7) to command bytes

;====================================================================
; Here begins the code.
;--------------------------------------------------------------------
; Stack on entry:
;
; $0c(a7) = bytes of parameter + padding, if odd length.
; $0a(a7) = Parameter size word.
; $06(a7) = Output file channel id.
; $02(a7) = Source file channel id.
; $00(a7) = How many channels? Should be $02.
;====================================================================
start
           bra.s   checkStack
           dc.l    $00
           dc.w    $4afb
name
           dc.w    name_end-name-2
           dc.b    'ASMReformat'
name_end
           equ     *

version
           dc.w    vers_end-version-2
           dc.b    'Version 1.00'
vers_end
           equ     *


bad_parameter
           moveq   #err_bp,d0          ; Guess!
           bra     errorExit           ; Die horribly

clearBuffers
           lea     labelBuffer,a0
           clr.w   (a0)                ; Nothing in labelBuffer
           lea     opcodeBuffer,a0
           clr.w   (a0)                ; Nothing in opcodeBuffer
           lea     operandBuffer,a0
           clr.w   (a0)                ; Nothing in operandBuffer
           lea     commentBuffer,a0
           clr.w   (a0)                ; Nothing in commentBuffer
           rts

;--------------------------------------------------------------------
; Check the stack on entry. We only require two channels and if a 
; command string is passed, we simply ignore it - for now anyway!
; We initialise the flags in D5.B to all off.
;--------------------------------------------------------------------
checkStack
           cmpi.w  #$02,(a7)           ; Two channels is a must
           bne.s   bad_parameter       ; Oops
           moveq   #0,d5               ; Clear all flags 

startLoop
           moveq   #infinite,d3        ; Timeout - preserved throughout

;--------------------------------------------------------------------
; Clear all the buffers and set up for the next read of the input
; file. On EOF, we are done here, on error, we exit. This will return
; the error code to SuperBASIC only if we EXEC_W/EW the program, EX
; will never show the error.
;--------------------------------------------------------------------
readLoop
           andi.b  #flagMask,d5        ; Reset noOpcode & inComment flags
           bsr.s   clearBuffers        ; Clear all buffers
           move.l  sourceId(a7),a0     ; Input channel id
           lea     inputBuffer+2,a1    ; Buffer for read to use
           move.l  a1,a4               ; inputPointer for later
           moveq   #io_fline,d0        ; Fetch a line and LF
           move.w  #1024,d2            ; Maximum buffer size = 1024 inc l/f
           trap    #3                  ; Read next line
           tst.l   d0                  ; Did it work?
           beq.s   checkContinue       ; Not EOF yet, carry on
           cmpi.l  #err_ef,d0          ; EOF?
           beq     allDone             ; No, exit the main loop
           bra     errorExit           ; Something bad happened then

;--------------------------------------------------------------------
; The read was ok, so we need to check if this line is a continuation
; of the operand from the previous line. We also store the word count
; of the string just read at the start of the input buffer.
;--------------------------------------------------------------------
checkContinue
           move.w  d1,-2(a4)           ; Save the string size	
           btst    #continue,d5        ; Continuation set?
           beq.s   checkAllComment     ; No, skip

;--------------------------------------------------------------------
; We are on a continuation line, so extract the operand and that will
; also reset/set the continuation flag if necessary for a further
; continuation of the operand.
;--------------------------------------------------------------------
doContinue
           bclr    #lfRequired,d5      ; Nothing printed yet
           bsr     extractOperand      ; Extract operand and set continue
           bsr     extractComment      ; Grab any comments as well
           bsr     clearBuffer         ; We always do this here
           move.l  destID(a7),a0       ; Output channel Id
           bra     doOperand           ; And continue from there

;--------------------------------------------------------------------
; Is this line completely a comment line - in other words, is the 
; first character a '*' or a ';' which indicates that it is a comment
; line. Write it to the output, unchanged, if so, then read the next
; line.
;--------------------------------------------------------------------
checkAllComment
           cmpi.b  #semiColon,(a4)     ; Current character a comment flag?
           beq.s   doWriteComment      ; Yes
           cmpi.b  #asterisk,(a4)      ; Or a comment flag?
           bne.s   checkBlank          ; Not this kind, no.

doWriteComment
           move.l  destID(a7),a0       ; Output channel Id
           lea     inputBuffer,a1      ; Buffer to write
           bsr     doWrite             ; Write out a line
           bra.s   readLoop            ; And go around again

;--------------------------------------------------------------------
; If D1.W = 1 we must assume it is a linefeed only, so this line is
; blank. In this case we simply write it out.
;--------------------------------------------------------------------
checkBlank
           cmpi.w  #1,d1               ; Linefeed only read in?
           beq.s   doWriteComment      ; Print out blank line.

;--------------------------------------------------------------------
; Does the line actually have any content, if not just a linefeed?
; Can you tell I got trapped in this? A4 = first character of the 
; input buffer, just after the word count.
; Calling scanForward adjusts A4 to the first non tab/space character
; in the input buffer. If A4 points at a linefeed, the line is blank.
;--------------------------------------------------------------------
checkContent
           bsr     scanForward         ; Return A4 at first real character
           cmpi.b  #linefeed,(a4)      ; Is line blank?
           bne.s   gotContent          ; We have content - extract it

;--------------------------------------------------------------------
; We have hit the linefeed, so there's no actual content on this line
; only tabs and/or spaces. Print a blank line to the output.
;--------------------------------------------------------------------
gotNoContent
           move.l  destId(a7),a0       ; Output channel ID
           bsr     doLineFeed          ; Print a linefeed
           bra     readLoop            ; Go around

;--------------------------------------------------------------------
; We do have content, so go process it.
;--------------------------------------------------------------------
gotContent
           lea     inputBuffer+2,a4    ; Reset input pointer
           bra     extractData         ; No, do the necessary

;--------------------------------------------------------------------
; Copy any label from the inputBuffer to the labelBuffer. A4 is the
; input buffer and we should be sitting at the start.
; We assume there will be no label - most assembly lines have no
; label - and check from there. A label has a non-space/tab/newline
; in the first character, anything else is assumed to be a label. As
; all those non-label characters are less than a space (ASCII) then
; a simple test for anything lower or eqal to a space is done.
;--------------------------------------------------------------------
extractLabel
           cmpi.b  #space,(a4)         ; First character a space?
           bls.s   extractLabelDone    ; Yes, exit - no label

;--------------------------------------------------------------------
; We have a label, copy it to the labelBuffer. Keep a count of chars
; copied in D0.
;--------------------------------------------------------------------
           lea     labelBuffer+2,a5    ; Our output buffer

doCopyText
           move.l  a5,a1               ; Save buffer
           bsr     copyText            ; Go copy it

extractLabelDone
           rts

;--------------------------------------------------------------------
; Copy any opcode from the inputBuffer to the labelBuffer. A4 should
; be the first character in the inputBuffer. If the extracted opCode
; doesn't need an operand, we set that flag accordingly.
;
; This routine leaves A5 1 byte past the last character read if the
; opcode is NOT 3 or 5 in size - otherwise it will be the address of
; the 1st or 3rd character read, depending on the opcode. See below.
;--------------------------------------------------------------------
extractOpcode
           lea     opcodeBuffer+2,a5   ; Output buffer
           bsr.s   doCopyText          ; Extract & copy opcode

;--------------------------------------------------------------------
; A5 now points one past the last character copied. A1 is still 
; pointing at the first character read. D0 is the size of the opcode.
; If the opcode is not 3 or 5 in size, it needs an operand.
; The noOperand flag is currently reset as per the start of readLoop.
;--------------------------------------------------------------------
checkThree
           cmpi.w  #3,d0               ; Did we get three characters?
           beq.s   doThreeFive         ; Yes, skip

checkFive
           cmpi.w  #5,d0               ; Did we get 5 characters?
           beq.s   doThreeFive         ; Yes, skip

notThreeFive
           rts                         ; We need an operand

;--------------------------------------------------------------------
; We get here if the opcode is 3 or 5 characters, now, is it one of
; the ones we want?
; We check the first 2 characters for 'no', 'rt', 're' or 'tr' and if
; found we have to check the remainder of the opcode to see if it is
; one which doesn't require an operand.
;
; These are: nop, reset, rte, rtr, rts, trapv.
;
; Reset and trapv are easy as they are the only 5 character opcodes
; starting with 're' or 'tr' and they both do not take operands.
;--------------------------------------------------------------------
doThreeFive
           move.l  a1,a5               ; Save first character start
           move.w  (a1),d1             ; Get first 2 characters
           ori.w   #lowerCase2,d1      ; Make lower case
           cmpi.w  #'no',d1            ; NO for NOP
           beq.s   doNO                ; Yes, skip
           cmpi.w  #'rt',d1            ; RT for RTE, RTR, RTS
           beq.s   doTRRE              ; Yes, skip
           cmpi.w  #'re',d1            ; RE for RESET
           beq.s   doTRRE              ; Yes, skip
           cmpi.w  #'tr',d1            ; TR for TRAPV
           bne.s   notThreeFive        ; No, exit

;--------------------------------------------------------------------
; This could be trapv or reset ... which as they are the only 5 
; character opcodes that starts with 'tr' or 're' we must have a hit.
; Exit with A5 pointing at the 1st character of the opcode.
;--------------------------------------------------------------------
doTRRE
           bset    #noOperand,d5       ; There is no operand
           rts                         ; Done

;--------------------------------------------------------------------
; This could be rte, rtr, rts ...
; Exit with A5 pointing at the third character of the opcode.
;--------------------------------------------------------------------
doRT
           addq.l  #2,a5               ; Next two characters
           move.b  (a5),d1             ; Only need 1 character
           ori.b   #lowerCase1,d1      ; Make lower case
           cmpi.b  #'e',d1             ; RTE?
           beq.s   doTRRE              ; Yes
           cmpi.b  #'r',d1             ; RTR?
           beq.s   doTRRE              ; Yes
           cmpi.b  #'s',d1             ; RTS?
           beq.s   doTRRE              ; Yes
           rts                         ; It's not one of the above

;--------------------------------------------------------------------
; This could be nop ...
; Exit with A5 pointing at the third character of the opcode.
;--------------------------------------------------------------------
doNO
           addq.l  #2,a5               ; Next two characters
           move.b  (a5),d1             ; Only need 1 character
           ori.b   #lowerCase1,d1      ; Make lower case
           cmpi.b  #'p',d1             ; NOP?
           beq.s   doTRRE              ; Yes
           rts                         ; It's not NOP           

;--------------------------------------------------------------------
; Copy any operand from the inputBuffer to the operandBuffer. If this
; opcode has no operands, do nothing, otherwise extract the operand
; into the buffer. A4 is the input buffer pointer.
; If the operand ends with a comma, then we need to set the continue
; flag for the next line to continue the operand.
;--------------------------------------------------------------------
extractOperand
           btst    #noOperand,d5       ; Do we need to do anything?
           bne.s   extractOperandDone  ; No, skip

;--------------------------------------------------------------------
; We have an operand, copy it to the operandBuffer. Keep a count of 
; chars copied in D0.
;--------------------------------------------------------------------
           bclr    #continue,d5        ; Assume no continuation
           lea     operandBuffer+2,a5  ; Our output buffer
           bsr     doCopyText          ; Copy operand
           cmpi.b  #comma,-1(a5)       ; Last character a comma?
           bne.s   extractOperandDone  ; No, skip
           bset    #continue,d5        ; We have a continuation

extractOperandDone
           rts

;--------------------------------------------------------------------
; Copy any comment from the inputBuffer to the commentBuffer. A4 is 
; the input buffer pointer. Returns with A5 one past the last char.
; Never returns here though.
;--------------------------------------------------------------------
extractComment
           bset    #inComment,d5       ; We are doing comments
           lea     commentBuffer+2,a5  ; Our output buffer
           bra     doCopyText          ; Copy comment

;--------------------------------------------------------------------
; Copy text from the input buffer (A4) to the output buffer (A5) and
; keep a count in D0. Scan forward in the input until we hit a non-
; space/tab character. Newline indicates the buffer end.
; A1 is a pointer to the start of the output buffer on entry and will
; be used to save the word count on completion.
; Watch out for quotes!
; If we are in a comment, then simply scan until the end.
;--------------------------------------------------------------------
copyText
           bsr.s   scanForward         ; Locate next valid character
           moveq   #0,d0               ; Counter

copyLoop
           cmpi.b  #linefeed,(a4)      ; Done yet?
           beq.s   copyTextDone        ; Yes, return
           btst    #inComment,d5       ; Are we in a comment?
           bne.s   copyComment         ; Yes, skip

;--------------------------------------------------------------------
; We are not in a comment, so check for quotes. If we find one we 
; must copy all characters until we get to the end quote. Otherwise
; any space/tab/newline character will end this copy.
;--------------------------------------------------------------------
           cmpi.b  #sQuote,(a4)        ; Single quote?
           beq.s   copyString          ; Yes, skip
           cmpi.b  #dQuote,(a4)        ; Double quote?
           beq.s   copyString          ; Yes, skip

;--------------------------------------------------------------------
; Not in a quoted string, are we done yet? If not, copy the current
; character and go around again.
;--------------------------------------------------------------------
           cmpi.b  #space,(a4)         ; Done yet?
           bls.s   copyTextDone        ; Yes, return 
           bra.s   copyComment         ; Copy one character 

;--------------------------------------------------------------------
; We have found a quote, grab it, then copy & scan to the end quote.
;--------------------------------------------------------------------
copyString
           move.b  (a4)+,d1            ; Grab opening quote
           move.b  d1,(a5)+            ; Save opening quote
           addq.w  #1,d0               ; Update counter

;--------------------------------------------------------------------
; We have copied the start quote and incremented counters & pointers
; so we are now ready to copy the remaining characters in the quoted
; string.
;--------------------------------------------------------------------
copyCharLoop
           move.b  (a4)+,(a5)          ; Copy current character
           addq.w  #1,d0               ; Update counter
           cmp.b   (a5),d1             ; Copied closing quote?
           addq.l  #1,a5               ; Update destination, Z flag unchanged
           bne.s   copyCharLoop        ; No, keep copying
           bra.s   copyLoop            ; String done, carry on	

;--------------------------------------------------------------------
; If we are in a comment, we don't care what characters we read as 
; all are required up to the terminating linefeed.
;--------------------------------------------------------------------
copyComment
           move.b  (a4)+,(a5)+         ; Copy character
           addq.w  #1,d0               ; Increment counter
           bra.s   copyLoop            ; Do some more

;--------------------------------------------------------------------
; At the end, store the word count at the start of this buffer.
;--------------------------------------------------------------------
copyTextDone
           move.w  d0,-2(a1)           ; Save text length
           rts

;--------------------------------------------------------------------
; Scan forward to the next non space/tab character. A newline is the
; end of the line and that will cause a return. Actually, we simply
; test for anything less than of equal to a space, other than a
; linefeed and keep incrementing until we get something else.
;
; Expects A4 to point into the current inputBuffer and exits with A4
; pointing at the next non-space/tab character, which might be a line
; feed.
;--------------------------------------------------------------------
scanForward
           cmpi.b  #linefeed,(a4)      ; Newline?
           beq.s   scanDone            ; Yes, done

           cmpi.b  #space,(a4)         ; Space (or less)?
           bhi.s   scanDone            ; No, done

           addq.l  #1,a4               ; Increment currentPointer
           bra.s   scanForward         ; Keep scanning

scanDone
           rts                         ; Done. (A4) is the next character

;--------------------------------------------------------------------
; We don't have a comment or blank, nor do we have an operand that has
; been continued over two (or more) lines, so we need to extract all
; the data from the input line.
;--------------------------------------------------------------------
extractData
           bsr     extractLabel        ; Get any label
           bsr     extractOpcode       ; Get opcode - sets noOperand
           bsr     extractOperand      ; get Operand - sets continue
           bsr.s   extractComment      ; Get comments - sets inComment
           bra.s   doLabel             ; Go do label processing

;--------------------------------------------------------------------
; Some code to write out some text at the current position in the
; output file. On error, will exit via errorExit and never return.
; Assumes A0 has the correct channel ID and that A1 points to a QDOS
; string ready to be printed.
; If entry is at doWriteA0A1 then this is writing a whole line
; comment and we need to set A0 and A1 first.
;--------------------------------------------------------------------
doWrite
           moveq   #io_sstrg,d0        ; Trap code
           move.w  (a1)+,d2            ; Word count

;--------------------------------------------------------------------
; Do a trap #3 and only return to the caller if it worked. Otherwise
; exit back to SuperBASIC with the error code.
;--------------------------------------------------------------------
doTrap3
           trap    #3                  ; Write the line/byte
           tst.l   d0                  ; Ok?
           bne     errorExit           ; No, bad stuff happened.
           rts                         ; Back to caller

doLineFeed
           moveq   #io_sbyte,d0        ; Send a single byte
           moveq   #linefeed,d1        ; Byte to send
           bra.s   doTrap3             ; Do it

;--------------------------------------------------------------------
; Copy a buffer from the word count at (A1) to the byte space at (A5)
; this is used when we copy the various buffers to the inputBuffer
; which we are using as an output Buffer now!
;
; Uses A1 as the source, A5 as the dest and D0.W as a counter.
; Corrupts A1 and D0.W. A5 exits as the next free byte in the buffer.
;--------------------------------------------------------------------
copyBuffer
           move.w  (a1)+,d0            ; Counter
           beq.s   copyBufferDone      ; Nothing to do, return
           subq.w  #1,d0               ; Adjust for dbra

copyBufferByte
           move.b  (a1)+,(a5)+         ; Copy a byte
           dbra    d0,copyBufferByte   ; And the rest

copyBufferDone
           rts                         ; Back to caller

;--------------------------------------------------------------------
; Space fill the inputBuffer prior to using it as the outputBuffer to
; write the reformatted line to the output file.
;--------------------------------------------------------------------
clearBuffer
           move.w  #255,d0             ; Counter for 256 longs
           lea     inputBuffer,a0      ; Guess!
           move.w  #0,(a0)             ; No string in buffer

clearBufferLong
           move.l  #$20202020,(a0)+    ; Clear one long
           dbra    d0,clearBufferLong  ; Do the rest 
           rts

;--------------------------------------------------------------------
; Labels get a line of their own, so we will write out the label by
; itself before looking at the rest of the stuff on the line.
;--------------------------------------------------------------------
doLabel
           lea     labelBuffer,a1      ; Label word count
           tst.w   (a1)                ; Any label?
           beq.s   doOpcode            ; No, skip
           move.l  destId(a7),a0       ; Destination channel id
           bsr.s   doWrite             ; Print out the label by itself
           bsr.s   doLineFeed          ; And a linefeed

;--------------------------------------------------------------------
; If we have an opcode, and normally we should have one, tab to the
; desired position and write it out. It is not normal for an opcode
; to exceed the space allocated, so no checks are done here.
; We always clear the inputBuffer at this point.
; We use D7 from here on to show if we printed anything and if so, we
; will need a linefeed afterwards, otherwise, no linefeed is needed.
;--------------------------------------------------------------------
doOpcode
           bsr.s   clearBuffer         ; We always do this here
           bclr    #lfRequired,d5      ; Nothing printed so far
           lea     opcodeBuffer,a1     ; Source word count
           tst.w   (a1)                ; Got an opcode?
           beq.s   doComment           ; No opcode, no operand
           bset    #lfRequired,d5      ; Flag something (to be) printed
           lea     inputBuffer+opcodePos+2,a5  ; Dest byte area
           bsr.s   copyBuffer          ; Copy the opCode

;--------------------------------------------------------------------
; Write out an operand. This may be a new one, or a continuation. If
; the operand exceeds commentPos-2 then add a couple of spaces to the
; output line before the comment gets printed. We use D6.W to hold
; any extra bytes used for use below.
;
; If commentPos = 40 and operandPos = 20 then max operand size is
; 40 - 20 - 1 = 19 before we have to extend the comment position.
;--------------------------------------------------------------------
doOperand
           moveq   #0,d6               ; Extra byte counter
           lea     operandBuffer,a1    ; Operand word count
           tst.w   (a1)                ; Do we have an operand?
           beq.s   doComment           ; No, skip
           bset    #lfRequired,d5      ; Something printed
           move.l  a1,a4               ; Save buffer address
           lea     inputBuffer+operandPos+2,a5  
           bsr.s   copyBuffer          ; Copy operand
           move.w  (a4),d0             ; Operand size
           cmpi.w  #commentPos-operandPos-1,d0  ; Check width
           bls.s   doComment           ; Narrow operand

doWideOperand
           addq.l  #2,a5               ; Adjust A5
           moveq   #2,d6               ; Two extra bytes now

;--------------------------------------------------------------------
; If we have a comment then print it at the desired position. If the
; operand took too much space (above) then offset the comment by a
; couple of extra spaces - as per D6.W.
; If there is no comment, then simply print a linefeed, if required.
;--------------------------------------------------------------------
doComment
           lea     commentBuffer,a1    ; Comment word count
           tst.w   (a1)                ; Do we have a comment?
           beq.s   addLineFeed         ; No, skip
           bset    #lfRequired,d5      ; Something printed

;--------------------------------------------------------------------
; If D6 is non-zero, then A5 is set to the correct output byte,
; otherwise, set A5 to the normal comment position in the buffer.
;--------------------------------------------------------------------

           tst.w   d6                  ; Zero is normal comment position
           bne.s   commentPositionSet  ; Non-zero = A5 is set correctly

setNormalOperandComment
           lea     inputBuffer+commentPos+2,a5  ; Destination

commentPositionSet
           bsr     copyBuffer          ; Copy the comment

addLineFeed
           btst    #lfRequired,d5      ; Anything printed?
           beq     readLoop            ; No, read next input line
           move.b  #linefeed,(a5)      ; Tag on a linefeed

;--------------------------------------------------------------------
; By here A5 is the linefeed charater written to the buffer so we 
; can get the size of the text now, quite easily. The word count is
; the lastCharacter (in A5) minus the bufferStart (in A1) minus 1.
;
; For example: 
;
;    A1---> 012345
;	    __NOPx <---A5
;
; x = LineFeed.
; _ = Unknown/don't care.
; 
; We need to print 4 characters 'NOP' plus linefeed, so 5-0-1 = 4.
;--------------------------------------------------------------------
           lea     inputBuffer,a1      ; Buffer word count
           move.l  a5,d0               ; Copy 
           subq.l  #1,d0               ; Minus 1
           sub.l   a1,d0               ; Offset into buffer
           move.w  d0,(a1)             ; Store in buffer

;--------------------------------------------------------------------
; Write the reformatted line to the output channel using the code in
; doWriteComment above. This also returns to the start of readLoop.
;--------------------------------------------------------------------
doWriteLine
           bra     doWriteComment      ; Print the line & loop around

;--------------------------------------------------------------------
; We have hit an error so we copy the code to D3 then exit via a
; forcible removal of this job. EXEC_W/EW will display the error in
; SuperBASIC, but EXEC/EX will not.
;--------------------------------------------------------------------
allDone
           moveq   #0,d0

errorExit
           move.l  d0,d3               ; Error code we want to return

;--------------------------------------------------------------------
; Kill myself when an error was detected, or at EOF.
;--------------------------------------------------------------------
suicide
           moveq   #mt_frjob,d0        ; This job will die soon
           moveq   #me,d1
           trap    #1

;--------------------------------------------------------------------
; Various buffers. Having them here keeps them separate from code and
; makes it easier for disassemblers to decode the code without having
; to worry about embedded data!
;--------------------------------------------------------------------

inputBuffer
           ds.w    512+1               ; Input buffer 1024 bytes + word count

labelBuffer
           ds.w    128+1               ; Label buffer 256 bytes + word count

opcodeBuffer
           ds.w    10+1                ; Opcode buffer 20 bytes + word count

operandBuffer
           ds.w    128+1               ; Operand buffer 256 bytes + word count

commentBuffer
           ds.w    246+1               ; Comment buffer 492 bytes + word count

