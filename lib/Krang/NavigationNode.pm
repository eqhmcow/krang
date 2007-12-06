package Krang::NavigationNode;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use base 'Tree::DAG_Node';
use Krang::ClassLoader MethodMaker => get_set => [ qw(link condition) ];
use Krang::ClassLoader Localization => qw(localize);

=head1 NAME

Krang::NavigationNode - a node in the left-navigation menu

=head1 SYNOPSIS

  # add a new node to the tree
  my $node = $parent->add_daughter;
  $node->name('Good Stories');

  # add a link under the new node
  my $link1 = $node->add_daughter();
  $link1->name('Find Good Stories');
  $link1->link('good_stories.pl?rm=find');
  
  # make a node's appearance conditional
  $link1->condition(sub { shift->{asset_perms}{asset_story} ne 'hide' });

=head1 DESCRIPTION

Objects of this class represent nodes in the left-navigation menu.
L<Krang::Navigation> uses a tree of these nodes to generate the
left-nav at run-time.  The default tree is setup in Krang::Navigation.

This class is a sub-class of L<Tree::DAG_Node> which provides basic
node functionality (add_daughter(), mother(), etc.).

=head1 INTERFACE

Aside from the inherited L<Tree::DAG_Node> methods the following are
methods available:

=head2 name()

Get/set the name of the node.  This is the textual value displayed in
the left-nav.

=cut

sub name {
    my $self = shift;

    $self->{name} = $_[0] if @_;

    return localize($self->{name});
}

=head2 link()

Get/set the link for the node.  Set this to a code-ref for dynamic
links.

=head2 condition()

Set this to a code-ref to control when the node will be shown to
users.  The code-ref should return 1 if the node is to be shown and 0
otherwise.  If a node's condition returns 0 then its children will be
hidden as well.

The subroutine will receive the following structure as a single
argument:

    { desk  => { pkg('Group')->user_desk_permissions()  },
      asset => { pkg('Group')->user_asset_permissions() },
      admin => { pkg('Group')->user_admin_permissions() },
    }

For too many examples see the default node tree in
L<Krang::Navigation>.

=cut

1;
