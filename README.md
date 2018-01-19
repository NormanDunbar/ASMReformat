# ASMReformat
Reformats an MC68000 (Sinclair QL etc) assembly source file to match my own preferred standards - which I often ignore and have to manually do it - no longer!

It works as a QDOSMSQ filter where the input and output file names are passed as parameters:

```
ex ASMReformat_bin, input_filename, output_filename
```

The input file is read only. *Do not* use the same name for both files - that way lies much grief, wailing and gnashing of teeth - I suspect. Either that or errors.

The rows in the input file will be processed as follows:

* If this line is a continuation of a previous line's *operand* then process this line for operand and comments only. Write the line out according to the formatting requirements of a line - see below for details.

* Comment lines with an '*' or a ';' in column 0 (or 1 depending on your editor) will be written out unchanged.

* Blank lines and lines with no actual content are also written out unchanged.

* Remaining lines are split into one or more of the following:

    * Label
    * Opcode
    * Operand
    * Comment

* If a label was extracted, it is written out to a line by itself, followed by a single linefeed.
* If an opcode was extracted, it is copied to a given position, default 12, in an output buffer.
* If the opcode has an operand, then the operand is copied to the buffer at position 20.
* Any comments are copied to position 40 in the output buffer.
* If there is anything to print, the output buffer is written to the output file, followed byba single linefeed.

## Continuations

As mentioned above, operands can be continued over a number of lines. When extracting an operand, if the last character is a comma, then a flag is set and the following line is assumed to be the continuation of the operand.

Comments on operands split in this way are allowed, and are processed correctly.

For example:

```
lowCase dc.b 'abcdefghijklmn',  ; Continues ...
             'opqrstuvwxyz'
```

Many lines on continuation are permitted.

When a continuation line is read, the flag is cleared and the line is split into the operand and any optional comments, then copied to the output buffer in the normal manner.

Have fun.