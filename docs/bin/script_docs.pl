#!/usr/bin/perl -w
use strict;

open POD, ">scripts.pod" or die $!;
print POD <<END;
=head1 Krang Scripts

END

opendir(DIR, "../bin") or die "Can't open ../bin: $!";
my @scripts = sort grep { /^krang_/ } readdir(DIR);

foreach my $script (@scripts) {
    next if ($script =~ /#/ || $script =~ /~/); # ignore emacs droppings

    # get short desc line from POD
    my $desc = "";
    open(PM, "../bin/$script") or die "Can't open ../bin/$script: $!";
    while(my $line = <PM>) {
        next unless $line =~ /^=head1 NAME/;        
        last;
    }
    while(my $line = <PM>) {
        next if $line =~ /^\s*$/;
        ($desc) = $line =~ /\-\s+(.*)$/;
        last;
    }
    close(PM);

    my $fname = "script_$script";

    # reference in modules.html
    print POD "HREF[$script|$fname.html] ". ($desc ? " - $desc" : "") . "\n\n";

    # make um
    print "bin/pod2html.pl ../bin/$script $fname.html\n";
    system("bin/pod2html.pl ../bin/$script $fname.html");
}

close POD;



