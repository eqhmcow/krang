package PBMM::category_ocs;
use strict;
use warnings;
use Time::Piece;

use OCS::Exporter;

=head1 NAME

PBMM::story_ocs - pricing element to control OCS for categories

=cut

use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;

   my @fixed = ( min => 1,
                 max => 1, 
                 allow_delete => 0, 
                 reorderable => 0);

   my %args = ( name         => 'category_ocs',
                display_name => 'Online Subscription Controls',                
                @fixed,
                children     => 
                [ 
                 Krang::ElementClass::CheckBox->new(name    => "protected",
                                                    @fixed,
                                                   ),
                 PBMM::money->new(name    => "price",
                                                size    => 7,
                                                @fixed,
                                               ),
                 PBMM::money->new(name    => "default_price",
                                  display_name => "Default Story Price",
                                  size => 7,
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
                 Krang::ElementClass::Textarea->new(name    => "description",
                                                display_name => "Offer Description",
                                                rows    => 2,
                                                @fixed,
                                               ),
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
        for my $name (grep { $val{$_} } (qw(price start_date end_date duration auto_renew))) {
            return (0, "If protected is unchecked, all other fields must be empty.  " . $element->child($name)->display_name . " contains a value.");
        }
    }

    # protected categories must have a price
    if ($val{protected} and not $val{price}) {
        return (0, "Protected categories must have a Price set.");
    }

    return (1);
}

# on delete, remove from the OCS system
sub ocs_unexport_category {
    my $self = shift;
    my %arg = @_;
    my $element = $arg{element};
    my $category = $element->category;

    OCS::Exporter->remove_category(url => $category->url);
}

# on publish, insert into OCS system
sub ocs_export_category {
    my $self = shift;
    my %arg = @_;
    my $element = $arg{element};
    my $category = $element->category;


    # extract OCS settings
    my %ocs;
    for my $name (qw(price start_date end_date duration auto_renew 
                     description)) {
        my ($e) = $element->match("${name}" . "[0]");
        if ($e) {
            $ocs{$name} = $e->data;
        } else {
            $ocs{$name} = undef;
        }
    }


    # export the category
    OCS::Exporter->export_category(
         url => $category->url,
         ($category->parent ? (parent_url => $category->parent->url) : ()),
         title => ($element->match('/display_name[0]'))[0]->data,
         %ocs,
    );
}

1;
