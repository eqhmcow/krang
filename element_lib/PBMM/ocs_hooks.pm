package PBMM::ocs_hooks;
use strict;
use warnings;

=head1 NAME

PBMM::ocs_hooks

=head1 DESCRIPTION

Provides the _publish() and delete_hook() methods needed to support OCS
in stories.

=cut

use base 'Exporter';
our @EXPORT_OK = qw(_publish delete_hook);

# publish story_ocs as wall.html
sub _publish {
    my $self = shift;
    my %arg = @_;
    my $publisher = $arg{publisher};
    my $element = $arg{element};
    my ($story_ocs) = $element->match('/story_ocs[0]');
    croak("Cannot find story_ocs child for article.")
      unless $story_ocs;

    my $wall_content = 
      $publisher->additional_content_block(filename     => 'wall.html',
                                           content      => 
                                           $story_ocs->publish(@_),
                                           use_category => 1);    
    
    return $wall_content;
}

# remove from exporter on delete
sub delete_hook {
    my $self = shift;
    my %arg = @_;
    my $element = $arg{element};
    my ($story_ocs) = $element->match('/story_ocs[0]');
    croak("Cannot find story_ocs child for article.")
      unless $story_ocs;
    $story_ocs->class->ocs_unexport_story(element => $story_ocs);   
}

1;
