use Test::More qw(no_plan);
use strict;
use warnings;
use Krang::Script;
BEGIN { use_ok('Krang::XML') }

# make sure XML::Writer is working
my $string;
my $writer = Krang::XML->writer(string => \$string);
isa_ok($writer, 'XML::Writer');
$writer->startTag('foo');
$writer->startTag('bar');
$writer->characters('baz');
$writer->endTag('bar');
$writer->endTag('foo');
$writer->end();
like($string, qr!<foo>.*?<bar>baz</bar>.*?</foo>!s);
