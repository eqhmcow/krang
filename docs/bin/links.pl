#!/usr/bin/perl -p

# fixup links to modules
s!<A[^>]+>\s*the\s+(\S+)\s+manpage\s*</A>!find_link($1)!ige;

sub find_link {
    my $mod = shift;

    if ($mod =~ /^Krang::/) {
        my $fname = lc($mod);
        $fname =~ s/::/_/g;
        return qq{<a href="$fname.html">$mod</a>};
    } else {
        return qq{<a href="http://search.cpan.org/perldoc?$mod">$mod</a>};
    }
}
