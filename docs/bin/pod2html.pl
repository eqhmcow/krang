#!/usr/bin/perl -w
$in = shift;
$out = shift;
system("bin/items.pl < $in > tmp.pod");
system("pod2html --css docs.css --noindex tmp.pod " .
       "| bin/href.pl " .
       "| bin/merge_pre.pl ".
       "| bin/hr.pl ".
       "| bin/links.pl ".
       "> $out");
unlink("tmp.pod");
