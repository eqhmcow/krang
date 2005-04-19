use Krang::ClassFactory qw(pkg);
use Test::More qw(no_plan);
use strict;
use warnings;
use Krang::ClassLoader 'Script';
BEGIN { use_ok(pkg('XML')) }

# make sure XML::Writer is working
my $string;
my $writer = pkg('XML')->writer(string => \$string);
isa_ok($writer, 'XML::Writer');
$writer->startTag('foo');
$writer->startTag('bar');
$writer->characters('baz');
$writer->endTag('bar');
$writer->endTag('foo');
$writer->end();
like($string, qr!<foo>.*?<bar>baz</bar>.*?</foo>!s);
