package TestSet1::article;
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

use Krang::ClassLoader base => 'ElementClass::TopLevel';
use Krang::ElementClass::CheckBoxGroup;

sub new {
    my $pkg  = shift;
    my %args = (
        name     => 'article',
        children => [
            pkg('ElementClass::Date')->new(
                name         => 'issue_date',
                min          => 1,
                max          => 1,
                reorderable  => 0,
                allow_delete => 0
            ),
            pkg('ElementClass::Textarea')->new(
                name         => 'deck',
                min          => 1,
                max          => 1,
                reorderable  => 0,
                allow_delete => 0,
                indexed      => 1,
            ),
            pkg('ElementClass::CheckBoxGroup')->new(
                name         => 'cbg_values',
                values       => [map { "option\_$_" } ('a' .. 'z')],
                defaults     => [qw(option_c option_e)],
                columns      => 4,
                min          => 1,
                max          => 1,
                allow_delete => 1,
                reorderable  => 1
            ),
            pkg('ElementClass::ListGroup')->new(
                name         => 'cbg_listgroup',
                list_group   => "Cost",
                size         => 1,
                min          => 1,
                max          => 1,
                allow_delete => 1,
                reorderable  => 1
            ),
            pkg('ElementClass::ListGroup')->new(
                name         => 'cbg_listgroup_2',
                list_group   => "Make/Model/Year",
                min          => 1,
                size         => 1,
                max          => 1,
                allow_delete => 1,
                reorderable  => 1
            ),
            pkg('ElementClass::ListGroup')->new(
                name         => 'auto_segments',
                list_group   => 'Segments',
                multiple     => 1,
                min          => 1,
                max          => 1,
                allow_delete => 1,
                reorderable  => 1
            ),
            TestSet1::fancy_keyword->new(
                min          => 1,
                max          => 1,
                reorderable  => 0,
                allow_delete => 0,
                indexed      => 1,
            ),
            pkg('ElementClass::Textarea')->new(
                name      => 'blurb',
                bulk_edit => 1
            ),

            pkg('ElementClass::RadioGroup')->new(
                name   => 'mood',
                values => [qw/happy sad confused manic depressive cynical/],
                labels => {
                    happy      => "Happy",
                    sad        => "Sad",
                    confused   => "Confused",
                    manic      => "Manic",
                    depressive => "Depressive",
                    cynical    => "Cynical"
                },
                columns => 2
            ),

            pkg('ElementClass::RadioGroup')->new(
                name       => 'radio_cost',
                min        => 1,
                max        => 1,
                list_group => 'Cost',
                columns    => 2
            ),

            'page',

            'poortext_xinha',

             pkg('ElementClass::CategoryLink')->new(
                 name => "story_in_cat",
                 publish_if_modified_story_in_cat => 1
             ),

             pkg('ElementClass::CategoryLink')->new(
                 name => "story_below_cat",
                 publish_if_modified_story_below_cat => 1
             ),

             pkg('ElementClass::CategoryLink')->new(
                 name => "media_in_cat",
                 publish_if_modified_media_in_cat => 1
             ),

             pkg('ElementClass::CategoryLink')->new(
                 name => "media_below_cat",
                 publish_if_modified_media_below_cat => 1
             ),
        ],
        @_
    );
    return $pkg->SUPER::new(%args);
}

# test delete_hook
our $DELETE_COUNT = 0;
sub delete_hook { $DELETE_COUNT++ }

1;
