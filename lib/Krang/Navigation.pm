package Krang::Navigation;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader 'Desk';
use Krang::ClassLoader Conf => qw(FTPHostName FTPPort EnableBugzilla);
use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader 'NavigationNode';
use Krang::ClassLoader Log => qw(debug info critical);
use Carp qw(croak);

=head1 NAME

Krang::Navigation - Krang module to manage UI navbar

=head1 SYNOPSIS

  use Krang::ClassLoader 'Navigation';

  pkg('Navigation')->fill_template(template => $template);

=head1 DESCRIPTION

This module manages the navigation for the Krang UI.

=head1 INTERFACE

=over

=item C<< Krang::Navigation->fill_template(template => $template) >>

This call fills the navigation variables in the supplied template.
All navigation vars and loops start with "nav_".  If the template does
not include the standard header.tmpl then this call with do nothing.

=back

=cut

our %TREE;

sub fill_template {
    my ($pkg, %arg) = @_;
    my $template = $arg{template};
    return unless $template->query(name => 'nav_content');

    my $instance = pkg('Conf')->instance;

    $TREE{$instance} = $pkg->initialize_tree($instance) 
      unless $TREE{$instance};
    
    my %perms = ( desk  => { pkg('Group')->user_desk_permissions()  },
                  asset => { pkg('Group')->user_asset_permissions() },
                  admin => { pkg('Group')->user_admin_permissions() },
                );

    $template->param(nav_content => $pkg->render($TREE{$instance}, \%perms));

    # set global admin if all admin perms are on
    $template->param(nav_global_admin => 1) 
      unless grep { not $perms{admin}{$_} } 
             grep { $_ ne 'admin_users_limited' } 
             keys %{$perms{admin}};
}

# render the navigation menu held in the navigation tree
sub render {
    my ($pkg, $node, $perms, $depth, $index) = @_;
    $depth ||= 0;
    $index ||= 0;

    # stop here if condition set and returns false
    my $condition = $node->condition;
    return if $condition and not $condition->($perms);

    # handle root
    return join('', map { $pkg->render($_, $perms, $depth+1, ++$index) } 
                      $node->daughters)
      unless $node->mother;
    
    # recurse and build up kids
    my $i = 1;
    my $kids = 
      join("<br>", grep { defined }
                   map { $pkg->render($_, $perms, $depth+1, $index + $i++) } 
                         $node->daughters);

    # get link for node
    my $link = $node->link;
    $link = $link->() if ref $link;

    # format name with link
    my $name =
      ($link ? 
       qq{<a href="javascript:nav_goto('} . $link . qq{')">} : "") .
      $node->name .
      ($link ? qq{</a>} : '');

    # setup blocks as needed
    my ($pre, $post) = ("", "");

    if ($index == 1) {
        # the first block is funny-looking
        $pre = qq{<div class="dark-bar">$name</div><div class="plain-cell">};
        $post = '</div>';

    } elsif ($depth == 1) {
        # blocks get funky little arrows
        $pre = qq{<div class="light-bar-nav"><img src="/images/arrow.gif" height="10" width="10" alt="arrow" border="0">$name</div><div class="form-cell-nav">};
        $post = '</div>';
    } elsif ($depth == 2) {
        $pre = $name . 
          ($kids ? qq{<div style="margin-left: 5px;">} : '');
        $post = '</div>' if $kids;
   } else {
       $pre = $name;
    }

    # all done, paste it together
    return $pre . $kids . $post;
}

# initialize navigation tree
sub initialize_tree {
    my $pkg = shift;
    my $tree = $pkg->default_tree();

    pkg('AddOn')->call_handler(NavigationHandler => $tree);

    return $tree;
}

sub default_tree {
    my ($root, $node, $sub, $sub2);
    $root = pkg('NavigationNode')->new();
    $root->name('Root');

    # My Workspace block
    $node = $root->new_daughter();
    $node->name('My Workspace');
    $node->link('workspace.pl');

    $sub  = $node->new_daughter();
    $sub->name('My Preferences');
    $sub->link('my_pref.pl');

    $sub  = $node->new_daughter();
    $sub->name('My Alerts');
    $sub->link('my_alerts.pl');

    # Story block
    $node = $root->new_daughter();
    $node->name('Story');
    $node->condition(sub { shift->{asset}{story} ne 'hide' });

    $sub  = $node->new_daughter();
    $sub->name('New Story');
    $sub->link('story.pl');
    $sub->condition(sub { shift->{asset}{story} ne 'read-only' });

    $sub  = $node->new_daughter();
    $sub->name('Find Stories');
    $sub->link('story.pl?rm=find');

    $sub  = $node->new_daughter();
    $sub->name('Active Stories');
    $sub->link('story.pl?rm=list_active');

    $sub = $node->new_daughter();
    $sub->name('Desks');
    
    foreach my $desk (pkg('Desk')->find(order_by => 'order')) {
        my $desk_id = $desk->desk_id;
        $sub2 = $sub->new_daughter();
        $sub2->name($desk->name);
        $sub2->link("desk.pl?desk_id=" . $desk_id);
        $sub2->condition(sub { (shift->{desk}{$desk_id} || "") ne "hide" });
    }

    # media block
    $node = $root->new_daughter();
    $node->name('Media');
    $node->condition(sub { shift->{asset}{media} ne 'hide' });

    $sub  = $node->new_daughter();
    $sub->name('New Media');
    $sub->link('media.pl?rm=add');
    $sub->condition(sub { shift->{asset}{media} ne 'read-only' });

    $sub  = $node->new_daughter();
    $sub->name('Find Media');
    $sub->link('media.pl');

    $sub  = $node->new_daughter();
    $sub->name('Active Media');
    $sub->link('media.pl?rm=list_active');    

    $sub  = $node->new_daughter();
    $sub->name('Bulk Upload');
    $sub->link('media_bulk_upload.pl');
    $sub->condition(sub { shift->{asset}{media} ne 'read-only' });

    # template block
    $node = $root->new_daughter();
    $node->name('Template');
    $node->condition(sub { shift->{asset}{template} ne 'hide' });

    $sub  = $node->new_daughter();
    $sub->name('New Template');
    $sub->link('template.pl?rm=add');
    $sub->condition(sub { shift->{asset}{template} ne 'read-only' });

    $sub  = $node->new_daughter();
    $sub->name('Find Templates');
    $sub->link('template.pl');

    $sub  = $node->new_daughter();
    $sub->name('Active Templates');
    $sub->link('template.pl?rm=list_active');

    # setup template FTP link, which is dynamic
    $sub  = $node->new_daughter();
    $sub->name('FTP');
    $sub->link(
       sub {
           my ($user) = pkg('User')->find(user_id => $ENV{REMOTE_USER});
           return "ftp://" . $user->login . '@' . 
                   FTPHostName . ':' . FTPPort .  '/' . $ENV{KRANG_INSTANCE} .
                   '/template';
       });
    $sub->condition(sub { shift->{asset}{template} ne 'read-only' });

    # admin block
    my $admin_node = $root->new_daughter();
    $admin_node->name('Admin');
    $admin_node->condition(sub { grep { !$_->condition or 
                                        $_->condition->(@_) } 
                                   $admin_node->daughters() });

    $node = $admin_node;
    $sub  = $node->new_daughter();
    $sub->name('Users');
    $sub->link('user.pl');
    $sub->condition(sub { shift->{admin}{admin_users} });

    $sub  = $node->new_daughter();
    $sub->name('Groups');
    $sub->link('group.pl');
    $sub->condition(sub { shift->{admin}{admin_groups} });

    $sub  = $node->new_daughter();
    $sub->name('Desks');
    $sub->link('desk_admin.pl');
    $sub->condition(sub { shift->{admin}{admin_desks} });

    $sub  = $node->new_daughter();
    $sub->name('Contributors');
    $sub->link('contributor.pl');
    $sub->condition(sub { shift->{admin}{admin_contribs} });

    $sub  = $node->new_daughter();
    $sub->name('Sites');
    $sub->link('site.pl');
    $sub->condition(sub { shift->{admin}{admin_sites} });

    $sub  = $node->new_daughter();
    $sub->name('Categories');
    $sub->link('category.pl');
    $sub->condition(sub { shift->{admin}{admin_categories} });

    $sub  = $node->new_daughter();
    $sub->name('Lists');
    $sub->link('list_group.pl');
    $sub->condition(sub { shift->{admin}{admin_lists} });

    $sub  = $node->new_daughter();
    $sub->name('Jobs');
    $sub->link('schedule.pl?rm=list_all');
    $sub->condition(sub { shift->{admin}{admin_jobs} });

    $sub  = $node->new_daughter();
    $sub->name('Submit a Bug');
    $sub->link('bug.cgi');
    $sub->condition(sub { EnableBugzilla });

    $sub = $node->new_daughter();
    $sub->name('Scheduler');
    $sub->link('schedule.pl?advanced_schedule=1&rm=edit_admin');
    $sub->condition(
        sub { 
            shift->{admin}{admin_scheduler} 
                && pkg('AddOn')->find(condition => 'EnableAdminSchedulerActions')
        }
    );
    

    return $root;
}

1;

