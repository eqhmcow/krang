package TestSet1::poortext_xinha;
use strict;
use warnings;
use Krang::ClassFactory qw(pkg);

=head1 NAME

TestSet1::article

=head1 DESCRIPTION

Example article element class for Krang.  This article element
contains a single 'deck', a single 'fancy_keyword', zero or more
blurbs and one or more pages.

=cut

use Krang::ClassLoader base => 'ElementClass';
use Krang::ElementClass::CheckBoxGroup;

sub new {
    my $pkg  = shift;
    my %args = (
        name     => 'poortext_xinha',
        children => [

            pkg('ElementClass::PoorText')->new(
                name               => 'poortext_header',
                type               => 'text',
                commands           => 'basic_with_special_chars',
                command_button_bar => 1,
                special_char_bar   => 0,
                bulk_edit          => 'xinha',
                bulk_edit_tag      => 'h1',
            ),
            pkg('ElementClass::PoorText')->new(
                name               => 'poortext_paragraph',
                type               => 'textarea',
                commands           => 'all_xinha',
                required           => 1,
                command_button_bar => 1,
                special_char_bar   => 0,
                bulk_edit          => 'xinha',
                bulk_edit_tag      => 'p',
                find               => {}
            ),

        ],
        @_
    );
    return $pkg->SUPER::new(%args);
}

1;
