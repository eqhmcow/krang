#!/usr/bin/perl -w
$in = shift;
$out = shift;
if (-e $out and -e $in and (stat($out))[9] >= ((stat($in))[9])) {
    print "Unchanged, skipping...\n";
    exit(0);
}
system("bin/items.pl < $in > tmp.pod");
system("pod2html --css docs.css --noindex tmp.pod " .
       "| bin/href.pl " .
       "| bin/merge_pre.pl ".
       "| bin/hr.pl ".
       "| bin/links.pl ".
       "> $out");
unlink("tmp.pod");
