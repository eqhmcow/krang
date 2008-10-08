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
                 tag    => 'nested markup',
                 db     => 'This is <u><strong><em>bold italic underlined</em></strong></u> text.',
                 ie     => 'This is <u><strong><em>bold italic underlined</em></strong></u> text.',
                 gecko  => 'This is <u><b><i>bold italic underlined</i></b></u> text.',
                 webkit => 'This is <span style="text-decoration: underline; font-weight: bold; font-style: italic">bold italic underlined</span> text.'
                },
);

BEGIN {
    use_ok(pkg('Markup::IE'));
    use_ok(pkg('Markup::Gecko'));
    use_ok(pkg('Markup::WebKit'));
}

for my $mapping (@mappings) {
    # IE
    is(pkg('Markup::IE')->db2browser(html => $mapping->{db}), $mapping->{ie}, "DB -> IE ($mapping->{tag})");
    is(pkg('Markup::IE')->browser2db(html => $mapping->{ie}), $mapping->{db}, "IE -> DB ($mapping->{tag})");

    # Gecko
    is(pkg('Markup::Gecko')->db2browser(html => $mapping->{db}), $mapping->{gecko}, "DB -> Gecko ($mapping->{tag})");
    is(pkg('Markup::Gecko')->browser2db(html => $mapping->{gecko}), $mapping->{db}, "Gecko -> DB ($mapping->{tag})");

    # WebKit
    is(pkg('Markup::WebKit')->db2browser(html => $mapping->{db}), $mapping->{webkit}, "DB -> WebKit ($mapping->{tag})");
    is(pkg('Markup::WebKit')->browser2db(html => $mapping->{webkit}), $mapping->{db}, "WebKit -> DB ($mapping->{tag})");

}
