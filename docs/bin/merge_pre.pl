#!/usr/bin/perl -w

# merge adjacent <pre> blocks so that code with blank lines looks right

for(join('',<>)) {
    s!</PRE>\s*<PRE>!\n!gs;
    print;
}


