#!/usr/bin/perl -w
use strict;

use File::Find qw(find);

open MOD, ">modules.pod" or die $!;
print MOD <<END;
=head1 Krang Modules

END


find({ wanted => \&process,
       preprocess => sub { sort { $a cmp $b } @_ },
       no_chdir => 1 }, '../lib/Krang');

sub process {
    return unless /.pm$/;
    return if /#/; # ignore emacs droppings

    my ($name) = /lib\/(.*?)\.pm/;
    my $fname = lc($name);
    $fname =~ s!/!_!g;
    my $mname = $name;
    $mname =~ s!/!::!g;

    # get short desc line from POD
    my $desc = "";
    open(PM, $_) or die "Can't open $_: $!";
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
            

    # reference in modules.html
    print MOD "HREF[$mname|$fname.html] - $desc\n\n";

    # make um
    print "bin/pod2html.pl $_ $fname.html\n";
    system("bin/pod2html.pl $_ $fname.html");
}

close MOD;



