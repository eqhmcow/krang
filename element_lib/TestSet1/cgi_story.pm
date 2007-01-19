package TestSet1::cgi_story;
use strict;
use warnings;
use Krang::ClassFactory qw(pkg);

=head1 NAME

TestSet1::cgi_story

=head1 DESCRIPTION

Example story which publishes a CGI and templates.

This is mostly a copy of Article, because we want to test publishing
a complex element set.

=cut


use Krang::ClassLoader base => 'ElementClass::TopLevel';
use Krang::ElementClass::CheckBoxGroup;

sub new {
   my $pkg = shift;
   my %args = ( name => 'cgi_story',
                children => 
                 [

                  pkg('ElementClass::Textarea')->new(name => 'dyn_vars_block',
                                                     min=>1, max=>1, allow_delete=>0, reorderable=>0),

                  pkg('ElementClass::Date')->new(name => 'issue_date',
                                                 min  => 1,
                                                 max  => 1,
                                                 reorderable => 0,
                                                 allow_delete => 0),
                  pkg('ElementClass::Textarea')->new(name => 'deck', 
                                                     min => 1, 
                                                     max => 1,
                                                     reorderable => 0,
                                                     allow_delete => 0,
                                                     indexed => 1,
                                                    ),
                  pkg('ElementClass::CheckBoxGroup')->new( name => 'cbg_values',
                                                           values => [map { "option\_$_" } ('a'..'z')],
                                                           defaults => [qw(option_c option_e)],
                                                           columns => 4,
                                                           min => 1,
                                                           max => 1,
                                                           allow_delete => 1,
                                                           reorderable => 1 ),
                  pkg('ElementClass::ListGroup')->new( name => 'cbg_listgroup',
                                                           list_group => "Cost",
                                                       size=>1,
                                                           min => 1,
                                                           max => 1,
                                                           allow_delete => 1,
                                                           reorderable => 1 ),
                  pkg('ElementClass::ListGroup')->new( name => 'cbg_listgroup_2',
                                                           list_group => "Make/Model/Year",
                                                           min => 1,
                                                       size=>1,
                                                           max => 1,
                                                           allow_delete => 1,
                                                           reorderable => 1 ),
                  pkg('ElementClass::ListGroup')->new(  name => 'auto_segments',
                                                        list_group => 'Segments',
                                                        multiple => 1,
                                                        min => 1,
                                                        max => 1,
                                                        allow_delete => 1,
                                                        reorderable => 1 ),
                  TestSet1::fancy_keyword->new(min          => 1,
                                               max          => 1,
                                               reorderable  => 0,
                                               allow_delete => 0,
                                               indexed => 1,
                                              ),
                  pkg('ElementClass::Textarea')->new(name => 'blurb',
                                                     bulk_edit => 1),

                  pkg('ElementClass::RadioGroup')->new(name => 'mood',
                                                       values => [qw/happy sad confused manic depressive cynical/],
                                                       labels => { happy      => "Happy",
                                                                   sad        => "Sad",
                                                                   confused   => "Confused",
                                                                   manic      => "Manic",
                                                                   depressive => "Depressive",
                                                                   cynical    => "Cynical" },
                                                       columns => 2 ),

                  pkg('ElementClass::RadioGroup')->new(name => 'radio_cost',
                                                       min          => 1,
                                                       max          => 1,
                                                       list_group => 'Cost',
                                                       columns => 2 ),

                  'page',

                ],
                @_);

   return $pkg->SUPER::new(%args);
}


sub publish {
    my $self = shift;
    my %args = @_;

    my $publisher = $args{publisher};
    my $element = $args{element};

    # Publish templates
    $self->publish_frontend_app_template
      ( publisher => $publisher,
        fill_with_element => $element,
        filename => "cgi_story.tmpl",
        use_category => 1,
        tmpl_data => {Foo => 123, Bar => 456},
      );

    # Publish cgi stub
    $self->publish_frontend_app_stub
      ( publisher => $publisher,
        filename => "cgi_story.cgi",
        app_module => 'CGI::Application',
        app_params => {Foo => 123, Bar => 456},
      );

    return $self->SUPER::publish(%args);
}


# test delete_hook
our $DELETE_COUNT = 0;
sub delete_hook { $DELETE_COUNT++ };

1;
