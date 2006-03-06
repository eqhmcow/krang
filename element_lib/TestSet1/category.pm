package TestSet1::category;
use strict;
use warnings;
use Krang::ClassFactory qw(pkg);

=head1 NAME

TestSet1::category

=head1 DESCRIPTION

Example category element class for Krang.  It has no subelements at the
moment.

=cut


use Krang::ClassLoader base => 'ElementClass::TopLevel';

sub new {
   my $pkg = shift;
   my %args = ( name => 'category',
                children => [
                             pkg('ElementClass::Text')->new(name => 'display_name',
                                                            allow_delete => 0,
                                                            min => 1,
                                                            max => 1,
                                                            reorderable => 0,
                                                            required => 1),
                             pkg('ElementClass::Text')->new(name => 'header',
                                                            allow_delete => 1,
                                                            min => 0,
                                                            max => 1,
                                                            reorderable => 1,
                                                            required => 1),
                             pkg('ElementClass::Textarea')->new(name => 'paragraph',
                                                            allow_delete => 1,
                                                            min => 0,
                                                            max => 0,
                                                            bulk_edit => 1,
                                                            reorderable => 1,
                                                            required => 0),
                             pkg('ElementClass::MediaLink')->new(name => "photo"),
                             pkg('ElementClass::StoryLink')->new(name => "leadin"),
                             pkg('ElementClass::CategoryLink')->new(name => "leftnav_link"),

                            ],
                @_);
   return $pkg->SUPER::new(%args);
}

sub fill_template {
    my ($self, %args) = @_;

    my $story = $args{publisher}->story;
    my $tmpl  = $args{tmpl};

    # add page info from publish tests if its in there.
    if ($args{fill_template_args}) {
        my $params = $args{fill_template_args};

        if (defined($params->{page_index}) && $tmpl->query(name => 'page_number')) {
            $tmpl->param(page_number => ($params->{page_index} + 1));
        }

        if (defined($params->{last_page_index}) && $tmpl->query(name => 'total_pages')) {
            $tmpl->param(total_pages => ($params->{last_page_index} + 1));
        }

        delete $args{fill_template_args};
    }

    $self->SUPER::fill_template( %args ); 

}

1;

   
