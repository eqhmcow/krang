package PBMM::story_ocs;
use strict;
use warnings;
use Time::Piece;
use OCS::Exporter;

=head1 NAME

PBMM::story_ocs - pricing element to control OCS

=cut

use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;

   my @fixed = ( min => 1,
                 max => 1, 
                 allow_delete => 0, 
                 reorderable => 0);

   my %args = ( name         => 'story_ocs',
                display_name => 'Online Subscription Controls',                
                @fixed,
                children     => 
                [ 
                 Krang::ElementClass::CheckBox->new(name    => "protected",
                                                    @fixed,
                                                   ),
                 Krang::ElementClass::CheckBox->new(name    => "free",
                                                    @fixed,
                                                   ),
                 PBMM::ocs_default_price->new(name => 'default', 
                                              display_name => 'Default Price',
                                              @fixed),
                 PBMM::ocs_price->new(name    => "price",
                                      size    => 7,
                                      @fixed,
                                     ),
                 Krang::ElementClass::Text->new(name    => "free_days",
                                                size    => 4,
                                                @fixed,
                                               ),
                 Krang::ElementClass::Date->new(name    => "start_date", 
                                                default => undef,
                                                @fixed,
                                               ),
                 Krang::ElementClass::Date->new(name    => "end_date",
                                                default => undef,
                                                @fixed,
                                               ),
                 Krang::ElementClass::Text->new(name    => "duration",
                                                display_name => "Duration (days)",
                                                size    => 4,
                                                @fixed,
                                               ),
                 Krang::ElementClass::CheckBox->new(name    => "auto_renew", 
                                                    @fixed,
                                                   ),
                 'wall_page_contents',
                ],
                @_);
   return $pkg->SUPER::new(%args);
}

# make sure constraints on the group behavior are met
sub validate_children {
    my $self = shift;
    my %arg = @_;
    my $element = $arg{element};
    my $query   = $arg{query};

    # get values for children
    my %val;
    foreach my $kid ($element->children) {
        my @names = $kid->param_names;
        $val{$kid->name()} = join('', map { $query->param($_) } @names);
    }

    # combining protected off and anything else on is illegal
    if (not $val{protected}) {
        for my $name (grep { $val{$_} } (qw(free free_days default price start_date end_date duration auto_renew))) {
            return (0, "If protected is unchecked, all other fields must be empty.  " . $element->child($name)->display_name . " contains a value.");
        }
    }

    # combining free and price controls is illegal
    if ($val{free}) {
        for my $name (grep { $val{$_} } (qw(free_days default price duration auto_renew))) {
            return (0, "Cannot combine free setting with " . $element->child($name)->display_name . " setting.");
        }
    }


    return (1);
}

# on delete, remove from the OCS system
sub ocs_unexport_story {
    my $self = shift;
    my %arg = @_;
    my $element = $arg{element};
    my $story = $element->story;

    foreach my $url ($story->urls) {
        OCS::Exporter->remove_story(url => $url);
    }
}

# on publish, insert into OCS system
sub ocs_export_story {
    my $self = shift;
    my %arg = @_;
    my $element = $arg{element};
    my $story = $element->story;

    # build category and url structure used by OCS
    my @categories = $story->categories;
    my @urls       = $story->urls;
    my @cat;
    while(@categories and @urls) {
        my $category = shift(@categories);
        my $url      = shift(@urls);
        push(@cat,{ category_url => $category->url,
                    story_url    => $url });
    }

    # extract OCS settings
    my %ocs;
    for my $name (qw(price start_date end_date duration auto_renew 
                     free_days free)) {
        my ($e) = $element->match("${name}" . "[0]");
        if ($e) {
            $ocs{$name} = $e->data;
        } else {
            $ocs{$name} = undef;
        }
    }

    OCS::Exporter->export_story(
         categories   => \@cat,
         title        => $story->title,
         publish_date => ($story->publish_date || Time::Piece->new),
         %ocs,
    );
}

sub publish {
    my $self = shift;
    my %arg = @_;
    my $publisher = $arg{publisher};
    my $element = $arg{element};

    # export the story when publishing
    if ($publisher->is_publish) {
        $self->ocs_export_story(@_);
    }

    # run the wall page template
    my $template = $self->find_template(@_);

    # fill the template as from the root
    my $article = $element->parent;
    $article->class->fill_template(element   => $article,
                                   tmpl      => $template,
                                   publisher => $publisher);

    # add in the wall content
    my $wall_page_contents = $element->child('wall_page_contents')->data;

    if ($wall_page_contents->{which} eq 'paragraph') {
        my @para = $article->match('//paragraph');
        my $num = $wall_page_contents->{num} - 1;
        $num = $#para if $num > $#para;
        $template->param(wall_content_loop => 
                         [ map { {wall_content => $_} } 
                           map { $_->data } @para[0..$num] ]);
    } else {
        $template->param(wall_content_loop => 
                         [ { wall_content => $wall_page_contents->{abs} } ]);
    }

    return $template->output;
}

1;
