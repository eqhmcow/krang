#!/usr/bin/perl -p

# process =item foo into =item *\nfoo, to make nicer looking ordered
# lists with less work.

s!=item\s+([^\*\d].*)$!=item *\n$1!g;
