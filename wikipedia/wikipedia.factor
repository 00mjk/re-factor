! Copyright (C) 2012 John Benediktsson
! See http://factorcode.org/license.txt for BSD license

USING: accessors assocs calendar colors.constants formatting
http.client io io.styles kernel make sequences urls xml
xml.data xml.traversal ;

IN: wikipedia

<PRIVATE

: header. ( string -- )
    H{ { font-size 20 } { font-style bold } } format nl ;

: link. ( tag -- )
    "a" assure-name over tag-named? [ "a" tag-named ] unless
    [ deep-children>string ] [ attrs>> "href" swap at ] bi
    "http://en.wikipedia.org/" prepend >url H{
        { font-name "monospace" }
        { foreground COLOR: blue }
    } [ write-object ] with-style ;

: item. ( tag -- )
    children>> [
        dup tag? [ link. ] [ [ write ] unless-empty ] if
    ] each nl ;

: items. ( seq -- )
    children-tags [ item. ] each nl ;

: (historical-events) ( timestamp -- seq )
    [ month-name ] [ day>> ] bi
    "http://en.wikipedia.org/wiki/%s_%s" sprintf
    http-get nip string>xml "ul" deep-tags-named ;

: items>sequence ( tag -- seq )
    children-tags [ deep-children>string ] map ;

PRIVATE>

: historical-events ( timestamp -- events )
    (historical-events) second items>sequence ;

: historical-events. ( timestamp -- )
    (historical-events) "Events" header. second items. ;

: historical-births ( timestamp -- births )
    (historical-events) third items>sequence ;

: historical-births. ( timestamp -- )
    (historical-events) "Births" header. third items. ;

: historical-deaths ( timestamp -- births )
    (historical-events) fourth items>sequence ;

: historical-deaths. ( timestamp -- )
    (historical-events) "Deaths" header. fourth items. ;
