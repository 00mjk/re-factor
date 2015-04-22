! Copyright (C) 2015 John Benediktsson
! See http://factorcode.org/license.txt for BSD license

USING: accessors assocs byte-arrays combinators fry io io.binary
io.encodings.binary io.encodings.string io.encodings.utf8
io.files io.streams.byte-array io.streams.peek kernel literals
make math sequences sequences.generalizations ;

IN: midi

! TODO: sometimes track length not specified
! TODO: parse division
! TODO: key-signature-decode
! TODO: running status in write-event

TUPLE: midi header chunks ;

C: <midi> midi

TUPLE: midi-chunk raw type ;

C: <midi-chunk> midi-chunk

TUPLE: midi-header format #chunks division ;

TUPLE: midi-track events ;

TUPLE: meta-event delta name value ;

C: <meta-event> meta-event

TUPLE: sysex-event delta type raw ;

C: <sysex-event> sysex-event

TUPLE: midi-event delta name value ;

C: <midi-event> midi-event

CONSTANT: formats H{
    { 0 "the file contains a single multi-channel track" }
    { 1 "the file contains one or more simultaneous tracks (or MIDI outputs) of a sequence" }
    { 2 "the file contains one or more sequentially independant single-track patterns" }
}

CONSTANT: min-pitchwheel -8192
CONSTANT: max-pitchwheel 8191

CONSTANT: min-songpos 0
CONSTANT: max-songpos 16383

CONSTANT: key-signatures H{
    { B{ -7 0 } "Cb" }
    { B{ -6 0 } "Gb" }
    { B{ -5 0 } "Db" }
    { B{ -4 0 } "Ab" }
    { B{ -3 0 } "Eb" }
    { B{ -2 0 } "Bb" }
    { B{ -1 0 } "F" }
    { B{ 0 0 } "C" }
    { B{ 1 0 } "G" }
    { B{ 2 0 } "D" }
    { B{ 3 0 } "A" }
    { B{ 4 0 } "E" }
    { B{ 5 0 } "B" }
    { B{ 6 0 } "F#" }
    { B{ 7 0 } "C#" }
    { B{ -7 1 } "Abm" }
    { B{ -6 1 } "Ebm" }
    { B{ -5 1 } "Bbm" }
    { B{ -4 1 } "Fm" }
    { B{ -3 1 } "Cm" }
    { B{ -2 1 } "Gm" }
    { B{ -1 1 } "Dm" }
    { B{ 0 1 } "Am" }
    { B{ 1 1 } "Em" }
    { B{ 2 1 } "Bm" }
    { B{ 3 1 } "F#m" }
    { B{ 4 1 } "C#m" }
    { B{ 5 1 } "G#m" }
    { B{ 6 1 } "D#m" }
    { B{ 7 1 } "A#m" }
}

CONSTANT: smpte-framerate H{
    { 0 24 }
    { 1 25 }
    { 2 29.97 }
    { 3 30 }
}

<PRIVATE

: read-number ( -- number )
    0 [ 7 bit? ] [
        7 shift read1 [ 0x7f bitand + ] keep
    ] do while ;

: parse-meta ( type raw -- name value )
    swap {
        { 0x00 [ 2 head be> "sequence-number" ] }
        { 0x01 [ utf8 decode "text" ] }
        { 0x02 [ utf8 decode "copyright" ] }
        { 0x03 [ utf8 decode "track-name" ] }
        { 0x04 [ utf8 decode "instrument-name" ] }
        { 0x05 [ utf8 decode "lyrics" ] }
        { 0x06 [ utf8 decode "marker" ] }
        { 0x07 [ utf8 decode "cue-point" ] }
        { 0x09 [ utf8 decode "device-name" ] }
        { 0x20 [ first "channel-prefix" ] }
        { 0x21 [ first "midi-port" ] }
        { 0x2f [ drop t "end-of-track" ] }
        { 0x51 [ 3 head be> "set-tempo" ] }
        { 0x54 [
            [
                5 firstn {
                    [
                        [ -6 shift "frame-rate" ,, ]
                        [ 0x3f bitand "hours" ,, ] bi
                    ]
                    [ "minutes" ,, ]
                    [ "seconds" ,, ]
                    [ "frames" ,, ]
                    [ "subframes" ,, ]
                } spread
            ] H{ } make "smpte-offset" ] }
        { 0x58 [
            [
                first4 {
                    [ "numerator" ,, ]
                    [ 2 * "denominator" ,, ]
                    [ "clocks-per-tick" ,, ]
                    [ "notated-32nd-notes-per-beat" ,, ]
                } spread
            ] H{ } make "time-signature" ] }
        { 0x59 [ key-signatures at "key-signature" ] }
        { 0x7f [ "sequencer-specific" ] }
    } case swap ;

: read-meta ( delta -- event )
    read1 read-number read parse-meta <meta-event> ;

: read-sysex ( delta type -- event )
    read-number read <sysex-event> ;

: read-channel ( type quot -- type data )
    '[ 0x0f bitand "channel" ,, @ ] H{ } make ; inline

: read-message ( delta type -- message )
    dup
    dup 0xf0 < [ 0xf0 bitand ] when
    {
        { 0x80 [
            [
                read1 "note" ,, read1 "velocity" ,,
            ] read-channel "note-off" ] }
        { 0x90 [
            [
                read1 "note" ,, read1 "velocity" ,,
            ] read-channel "note-on" ] }
        { 0xa0 [
            [
                read1 "note" ,, read1 "value" ,,
            ] read-channel "polytouch" ] }
        { 0xb0 [
            [
                read1 "control" ,, read1 "value" ,,
            ] read-channel "control-change" ] }

        { 0xc0 [
            [
                read1 "program" ,,
            ] read-channel "program-change" ] }
        { 0xd0 [
            [
                read1 "value" ,,
            ] read-channel "aftertouch" ] }
        { 0xe0 [
            [
                read1 read1 7 shift + min-pitchwheel + "pitch" ,,
            ] read-channel "pitchwheel" ] }

        ! system common messages
        { 0xf0 [ drop { 0xf7 } read-until drop "sysex" ] }
        { 0xf1 [
            drop [
                read1
                [ -4 shift "frame-type" ,, ]
                [ 0x0f bitand "frame-value" ,, ] bi
            ] H{ } make "quarter-made" ] }
        { 0xf2 [ drop read1 read1 7 shift + "songpos" ] }
        { 0xf3 [ drop read1 "song-select" ] }
        { 0xf6 [ drop f "tune-request" ] }

        ! real-time messages
        { 0xf8 [ drop f "clock" ] }
        { 0xfa [ drop f "start" ] }
        { 0xfb [ drop f "continue" ] }
        { 0xfc [ drop f "stop" ] }
        { 0xfe [ drop f "active-sensing" ] }
        { 0xff [ drop f "reset" ] }
    } case swap <midi-event> ;

: read-event ( delta type -- event )
    {
        { 0xf0 [ 0xf0 read-sysex ] }
        { 0xf7 [ 0xf7 read-sysex ] }
        { 0xff [ read-meta ] }
        [ read-message ]
    } case ;

: read-status ( prev-status -- prev-status' status )
    peek1 dup 0x80 < [
        drop dup
    ] [
        drop read1 dup 0xff = [
            nip dup
        ] unless
    ] if ;

: read-event-header ( prev-status -- prev-status' delta status )
    [ read-number ] dip read-status swapd ;

: parse-events ( data -- events )
    binary <byte-reader> <peek-stream> [
        f [
            peek1 [ read-event-header ] [ f f ] if dup
        ] [ read-event ] produce 2nip nip
    ] with-input-stream ;

: <midi-header> ( raw -- header )
    2 cut 2 cut [ be> ] tri@ midi-header boa ;

: <midi-track> ( raw -- track )
    parse-events midi-track boa ;

: read-chunk ( -- chunk )
    4 read 4 read be> read swap {
        { $[ "MThd" >byte-array ] [ <midi-header> ] }
        { $[ "MTrk" >byte-array ] [ <midi-track> ] }
        [ <midi-chunk> ]
    } case ;

: read-header ( -- header )
    read-chunk dup midi-header? t assert= ;

: read-chunks ( header -- chunks )
    #chunks>> [ read-chunk ] replicate ;

PRIVATE>

: read-midi ( -- midi )
    read-header dup read-chunks <midi> ;

: >midi ( byte-array -- midi )
    binary [ read-midi ] with-byte-reader ;

: file>midi ( path -- midi )
    binary [ read-midi ] with-file-reader ;

<PRIVATE

: write-number ( n -- )
    [ 0x7f bitand ] keep

    [ -7 shift dup 0 > ] [
        [ 8 shift 0x80 bitor ]
        [ [ 0x7f bitand + ] keep ] bi*
    ] while drop

    [ [ -8 shift ] [ 0x80 bitand 0 > ] bi ]
    [ dup 0xff bitand write1 ] do while drop ;

: write-string ( str -- )
    utf8 encode [ length write-number ] [ write ] bi ;

GENERIC: write-event ( event -- )

M: meta-event write-event
    [ delta>> write-number 0xff write1 ] [ value>> ] [ name>> ] tri {
        { "sequence-number" [ B{ 0x00 0x02 } write 2 >be write ] }
        { "text" [ 0x01 write1 write-string ] }
        { "copyright" [ 0x02 write1 write-string ] }
        { "track-name" [ 0x03 write1 write-string ] }
        { "instrument-name" [ 0x04 write1 write-string ] }
        { "lyrics" [ 0x05 write1 write-string ] }
        { "marker" [ 0x06 write1 write-string ] }
        { "cue-point" [ 0x07 write1 write-string ] }
        { "device-name" [ 0x09 write1 write-string ] }
        { "channel-prefix" [ B{ 0x20 0x01 } write write1 ] }
        { "midi-port" [ B{ 0x21 0x01 } write write1 ] }
        { "end-of-track" [ B{ 0x2f 0x00 } write drop ] }
        { "set-tempo" [ B{ 0x51 0x03 } write 3 >be write ] }
        { "smpte-offset" [
            B{ 0x54 0x05 } write {
                [ "frame-rate" of 6 shift ]
                [ "hours" of + write1 ]
                [ "minutes" of write1 ]
                [ "seconds" of write1 ]
                [ "frames" of write1 ]
                [ "subframes" of write1 ]
            } cleave ] }
        { "time-signature" [
            B{ 0x58 0x04 } write {
                [ "numerator" of write1 ]
                [ "denominator" of 2 /i write1 ]
                [ "clocks-per-tick" of write1 ]
                [ "notated-32nd-notes-per-beat" of write1 ]
            } cleave ] }
        { "key-signature" [
            B{ 0x59 0x02 } write
            key-signatures value-at write ] }
        { "sequencer-specific" [
            0x7f write1
            [ length write-number ] [ write ] bi ] }
    } case ;

M: sysex-event write-event
    [ delta>> write-number ]
    [ type>> write1 ]
    [ raw>> write ] tri ;

: write-channel ( value type quot -- )
    [ swap [ "channel" of + write1 ] keep ] dip call ; inline

M: midi-event write-event
    [ delta>> write-number ] [ value>> ] [ name>> ] tri {

        { "note-off" [
            0x80 [
                [ "note" of write1 ]
                [ "velocity" of write1 ] bi
            ] write-channel ] }
        { "note-on" [
            0x90 [
                [ "note" of write1 ]
                [ "velocity" of write1 ] bi
            ] write-channel ] }
        { "polytouch" [
            0xa0 [
                [ "note" of write1 ]
                [ "value" of write1 ] bi
            ] write-channel ] }
        { "control-change" [
            0xb0 [
                [ "control" of write1 ]
                [ "value" of write1 ] bi
            ] write-channel ] }
        { "program-change" [
            0xc0 [ "program" of write1 ] write-channel ] }
        { "aftertouch" [
            0xd0 [ "value" of write1 ] write-channel ] }
        { "pitchwheel" [
            0xe0 [
                "pitch" of min-pitchwheel -
                [ 0x7f bitand write1 ]
                [ -7 shift write1 ] bi
            ] write-channel ] }

        ! system common messages
        { "sysex" [ 0xf0 write1 write 0xf7 write1 ] }
        { "quarter-made" [
            0xf1 write1
            [ "frame-type" of 4 shift ]
            [ "frame-value" of + ] bi write1 ] }
        { "songpos" [
            0xf2 write1
            [ 0x7f bitand write1 ]
            [ -7 shift write1 ] bi ] }
        { "song-select" [ 0xf3 write1 write1 ] }
        { "tune-request" [ drop 0xf6 write1 ] }

        ! real-time messages
        { "clock" [ drop 0xf8 write1 ] }
        { "start" [ drop 0xfa write1 ] }
        { "continue" [ drop 0xfb write1 ] }
        { "stop" [ drop 0xfc write1 ] }
        { "active-sensing" [ drop 0xfe write1 ] }
        { "reset" [ drop 0xff write1 ] }
    } case ;

: write-header ( header -- )
    $[ "MThd" >byte-array ] write
    $[ 6 4 >be ] write
    [ format>> ] [ #chunks>> ] [ division>> ] tri
    [ 2 >be write ] tri@ ;

: write-track ( track -- )
    $[ "MTrk" >byte-array ] write
    binary [ events>> [ write-event ] each ] with-byte-writer
    [ length 4 >be write ] [ write ] bi ;

: write-chunk ( chunks -- )
    {
        { [ dup midi-header? ] [ write-header ] }
        { [ dup midi-track? ] [ write-track ] }
        [
            [ type>> write ]
            [ raw>> [ length 4 >be write ] [ write ] bi ] bi
        ]
    } cond ;

PRIVATE>

: write-midi ( midi -- )
    [ header>> write-header ]
    [ chunks>> [ write-chunk ] each ] bi ;

: midi> ( midi -- byte-array )
    binary [ write-midi ] with-byte-writer ;

: midi>file ( midi path -- )
    binary [ write-midi ] with-file-writer ;
