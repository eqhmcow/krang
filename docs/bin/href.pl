#!/usr/bin/perl -p 

# translate HREF(foo|bar) into <a href="bar">foo</a>.  pod2html should
# provide this, but it doesn't unless you want to use a full URL.

s/HREF\[(.+?)\|(.+?)\]/<a href="$2">$1<\/a>/g;
