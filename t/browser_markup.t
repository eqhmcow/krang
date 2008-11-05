use Krang::ClassFactory qw(pkg);
use Test::More qw(no_plan);

use strict;
use warnings;

my @mappings = (
    {
        tag    => 'strong',
        db     => 'This is <strong>bold</strong> text.',
        ie     => 'This is <strong>bold</strong> text.',
        gecko  => 'This is <b>bold</b> text.',
        webkit => 'This is <span style="font-weight: bold">bold</span> text.'
    },
    {
        tag    => 'emphasize',
        db     => 'This is <em>italic</em> text.',
        ie     => 'This is <em>italic</em> text.',
        gecko  => 'This is <i>italic</i> text.',
        webkit => 'This is <span style="font-style: italic">italic</span> text.'
    },
    {
        tag    => 'underline',
        db     => 'This is <u>underlined</u> text.',
        ie     => 'This is <u>underlined</u> text.',
        gecko  => 'This is <u>underlined</u> text.',
        webkit => 'This is <span style="text-decoration: underline">underlined</span> text.'
    },
    {
        tag    => 'strike through',
        db     => 'This is <strike>strike-through</strike> text.',
        ie     => 'This is <strike>strike-through</strike> text.',
        gecko  => 'This is <strike>strike-through</strike> text.',
        webkit => 'This is <span style="text-decoration: line-through">strike-through</span> text.'
    },
    {
        tag    => 'subscript',
        db     => 'This is <sub>subscript</sub> text.',
        ie     => 'This is <sub>subscript</sub> text.',
        gecko  => 'This is <sub>subscript</sub> text.',
        webkit => 'This is <span style="vertical-align: sub">subscript</span> text.'
    },
    {
        tag    => 'superscript',
        db     => 'This is <sup>superscript</sup> text.',
        ie     => 'This is <sup>superscript</sup> text.',
        gecko  => 'This is <sup>superscript</sup> text.',
        webkit => 'This is <span style="vertical-align: super">superscript</span> text.'
    },
    {
        tag   => 'nested markup',
        db    => 'This is <em><strong><u>bold italic underlined</u></strong></em> text.',
        ie    => 'This is <em><strong><u>bold italic underlined</u></strong></em> text.',
        gecko => 'This is <i><b><u>bold italic underlined</u></b></i> text.',
        webkit =>
          'This is <span style="font-style: italic; font-weight: bold; text-decoration: underline">bold italic underlined</span> text.'
    },
);

my @more_webkit = (
    {
        tag => 'Crazy nesting 1',
        webkit =>
          'normal<span style="text-decoration: underline"> underline </span><span style="font-style: italic; font-weight: bold; text-decoration: underline">unde</span><span style="font-style: italic; text-decoration: underline">rline</span><span style="font-style: italic; font-weight: bold; text-decoration: underline">bolditalic</span><span style="text-decoration: underline"> </span>normal<span style="text-decoration: underline"> </span><span style="font-weight: bold; text-decoration: underline">boldunderline </span><span style="font-style: italic">italic</span><span style="font-style: italic; font-weight: bold; text-decoration: underline"> </span>normal',
        db =>
          'normal<u> underline </u><em><strong><u>unde</u></strong><u>rline</u><strong><u>bolditalic</u></strong></em><u> </u>normal<u> </u><strong><u>boldunderline </u></strong><em>italic<strong><u> </u></strong></em>normal'
    },
    {
        tag => 'Crazy nesting 2',
        webkit =>
          '<span style="font-style: italic; font-weight: bold">bolditalic</span><span style="font-style: italic; font-weight: bold; text-decoration: underline"> </span><span style="vertical-align: sub">normalsubscript</span><span style="font-style: italic; font-weight: bold; text-decoration: underline"> </span><span style="font-style: italic; text-decoration: underline">underlineitalic </span><span style="text-decoration: underline; vertical-align: sub">underlinesubscript</span><span style="font-style: italic; text-decoration: underline"> </span>normal<span style="font-style: italic; text-decoration: underline"> </span><span style="font-style: italic; font-weight: bold; vertical-align: super">boldsuperscript</span><span style="font-style: italic; text-decoration: underline"> </span><span style="font-weight: bold; text-decoration: underline">boldunderline</span><span style="font-style: italic; text-decoration: underline"> </span>normal<span style="font-weight: bold"> bold</span>',
        db =>
          '<em><strong>bolditalic<u> </u></strong></em><sub>normalsubscript</sub><em><strong><u> </u></strong><u>underlineitalic </u></em><u><sub>underlinesubscript</sub></u><em><u> </u></em>normal<em><u> </u><strong><sup>boldsuperscript</sup></strong><u> </u></em><strong><u>boldunderline</u></strong><em><u> </u></em>normal<strong> bold</strong>',
    },
);

BEGIN {
    use_ok(pkg('Markup::IE'));
    use_ok(pkg('Markup::Gecko'));
    use_ok(pkg('Markup::WebKit'));
}

for my $mapping (@mappings) {

    # IE
    is(pkg('Markup::IE')->db2browser(html => $mapping->{db}),
        $mapping->{ie}, "DB -> IE ($mapping->{tag})");
    is(pkg('Markup::IE')->browser2db(html => $mapping->{ie}),
        $mapping->{db}, "IE -> DB ($mapping->{tag})");

    # Gecko
    is(pkg('Markup::Gecko')->db2browser(html => $mapping->{db}),
        $mapping->{gecko}, "DB -> Gecko ($mapping->{tag})");
    is(pkg('Markup::Gecko')->browser2db(html => $mapping->{gecko}),
        $mapping->{db}, "Gecko -> DB ($mapping->{tag})");

    # WebKit
    is(pkg('Markup::WebKit')->db2browser(html => $mapping->{db}),
        $mapping->{webkit}, "DB -> WebKit ($mapping->{tag})");
    is(pkg('Markup::WebKit')->browser2db(html => $mapping->{webkit}),
        $mapping->{db}, "WebKit -> DB ($mapping->{tag})");
}

for my $mapping (@more_webkit) {
    is(pkg('Markup::WebKit')->browser2db(html => $mapping->{webkit}),
        $mapping->{db}, "WebKit -> DB ($mapping->{tag})");
    is(pkg('Markup::WebKit')->db2browser(html => $mapping->{db}),
        $mapping->{webkit}, "DB -> WebKit ($mapping->{tag})");
}
