package Krang::CGI::Group;
use base qw(Krang::CGI);
use strict;
use warnings;




=head1 NAME

Krang::CGI::Group - web interface to manage permission groups


=head1 SYNOPSIS

  use Krang::CGI::Group;
  my $app = Krang::CGI::Group->new();
  $app->run();


=head1 DESCRIPTION

Krang::CGI::Group provides a web-based system through which users can
add, modify or delete permission groups from a Krang instance.


=head1 INTERFACE

Following are descriptions of all the run-modes
provided by Krang::CGI::Group.

The default run-mode (start_mode) for Krang::CGI::Group
is 'search'.

=head2 Run-Modes

=over 4

=cut


use Krang::Group;
use Krang::Widget;
use Krang::Message qw(add_message);
use Krang::HTMLPager;
use Krang::Pref;
use Krang::Session qw(%session);
use Krang::Category;
use Krang::Widget qw(category_chooser format_url);
use Krang::Desk;
use Krang::Log qw(debug info critical);
use Carp;


# Fields in a group object
use constant GROUP_PROTOTYPE => {
                                 group_id            => '',
                                 name                => '',
                                 categories          => {},
                                 desks               => {},
                                 may_publish         => 1,
                                 admin_users         => 1,
                                 admin_users_limited => 1,
                                 admin_groups        => 1,
                                 admin_contribs      => 1,
                                 admin_sites         => 1,
                                 admin_categories    => 1,
                                 admin_jobs          => 1,
                                 admin_desks         => 1,
                                 asset_story         => 'edit',
                                 asset_media         => 'edit',
                                 asset_template      => 'edit'
                                };



##############################
#####  OVERRIDE METHODS  #####
##############################

sub setup {
    my $self = shift;

    $self->start_mode('search');

    $self->run_modes([qw(
                         search
                         add
                         edit
                         save
                         save_stay
                         cancel
                         delete
                         delete_selected
                         save_and_edit_categories
                         edit_categories
                         add_category
                         delete_category
                         edit_categories_return
                        )]);

    $self->tmpl_path('Group/');
}




##############################
#####  RUN-MODE METHODS  #####
##############################




=item search

This run-mode lists all groups and allows users to search for groups
based on the group name.

From this mode users may edit a group, add a new group, or delete a set of groups.

This run-mode expects an optional parameters "search_filter"
which is expected to contain the text string which is used to 
query groups.

=cut


sub search {
    my $self = shift;

    my $q = $self->query();

    my $t = $self->load_tmpl("list_view.tmpl", associate=>$q, loop_context_vars=>1);

    # Do simple search based on search field
    my $search_filter = $q->param('search_filter') || '';

    # Configure pager
    my $pager = Krang::HTMLPager->new(
                                      cgi_query => $q,
                                      persist_vars => {
                                                       rm => 'search',
                                                       search_filter => $search_filter,
                                                      },
                                      use_module => 'Krang::Group',
                                      find_params => { simple_search => $search_filter },
                                      columns => [qw(name may_publish command_column checkbox_column)],
                                      column_labels => {
                                                        name => 'Group Name',
                                                        may_publish => 'Publish?',
                                                       },
                                      columns_sortable => [qw( name may_publish )],
                                      command_column_commands => [qw( edit_group )],
                                      command_column_labels => {edit_group => 'Edit'},
                                      row_handler => sub {
                                          $_[0]->{name} = $_[1]->name();
                                          $_[0]->{may_publish} = $_[1]->may_publish() ? 'Yes' : 'No';
                                      },
                                      id_handler => sub { return $_[0]->group_id },
                                     );

    # Run pager
    $t->param(pager_html =>  $pager->output());

    # Propagate other params
    $t->param(row_count => $pager->row_count());

    return $t->output();
}



=item add

Display "add group" screen through which new groups may be added.

=cut


sub add {
    my $self = shift;

    # Make new Group, but don't save it
    my $g = Krang::Group->new();

    # Stash it in the session for later
    $session{EDIT_GROUP} = $g;

    # Show edit form
    return $self->_edit();
}



=item edit

Display "edit group" screen through which new groups may be added.


=cut


sub edit {
    my $self = shift;

    my $q = $self->query();
    my $group_id = $q->param('group_id');
    my ( $g ) = Krang::Group->find( group_id => $group_id );

    # Did we get our group?  Presumbably, users get here from a list.  IOW, there is 
    # no valid (non-fatal) case where a user would be here with an invalid group_id
    die ("No such group_id '$group_id'") unless (defined($g));

    # Stash it in the session for later
    $session{EDIT_GROUP} = $g;

    # Show edit form
    return $self->_edit();
}



=item save

Save a group object.  In the case of "add", this will insert a new
group into the system.  In the case of "edit", this will update an
existing group.

=cut


sub save {
    my $self = shift;

    my $q = $self->query();

    my %errors = ( $self->validate_group() );

    # Return to add or edit screen if we have errors
    return $self->_edit( %errors ) if (%errors);

    # Retrieve working group object from session
    my $g = $session{EDIT_GROUP};
    die("Can't retrieve EDIT_GROUP from session") unless ($g && ref($g));

    # If we don't have an ID, we're in add mode
    my $add_mode = not($g->group_id);

    my %save_errors = ( $self->do_update_group($g) );
    return $self->_edit(%save_errors) if (%save_errors);

    # Delete group object from session
    $session{EDIT_GROUP} = 0;

    if ($add_mode) {
        add_message('message_group_added');
    } else {
        add_message('message_group_saved');
    }

    return $self->search();
}





=item save_stay

Same as mode "save", except user is returned to the edit screen.

=cut


sub save_stay {
    my $self = shift;

    my $q = $self->query();

    my %errors = ( $self->validate_group() );

    # Return to add or edit screen if we have errors
    return $self->_edit( %errors ) if (%errors);

    # Retrieve working group object from session
    my $g = $session{EDIT_GROUP};
    die("Can't retrieve EDIT_GROUP from session") unless ($g && ref($g));

    # If we don't have an ID, we're in add mode
    my $add_mode = not($g->group_id);

    my %save_errors = ( $self->do_update_group($g) );
    return $self->_edit(%save_errors) if (%save_errors);

    # Delete group object from session
    $session{EDIT_GROUP} = 0;

    if ($add_mode) {
        add_message('message_group_added');
    } else {
        add_message('message_group_saved');
    }

    # Clear out group properties from CGI form
    $q->delete( keys(%{&GROUP_PROTOTYPE}) );

    # Set up query data for edit mode
    my $group_id = $g->group_id();
    $q->param(group_id => $group_id);

    # Return to edit mode
    return $self->edit();
}





=item cancel

Cancel editing (or adding) a group.  Abandon changes and 
return to search screen.

=cut


sub cancel {
    my $self = shift;

    my $q = $self->query();

    # Retrieve working group object from session
    my $g = $session{EDIT_GROUP};
    die("Can't retrieve EDIT_GROUP from session") unless ($g && ref($g));

    # If we don't have an ID, we're in add mode
    my $add_mode = not($g->group_id);

    # Delete group object from session
    $session{EDIT_GROUP} = 0;

    if ($add_mode) {
        add_message('message_add_cancelled');
    } else {
        add_message('message_save_cancelled');
    }

    return $self->search();
}





=item delete

Delete the current group object and return to the search screen.

=cut


sub delete {
    my $self = shift;

    my $q = $self->query();

    # Retrieve working group object from session
    my $g = $session{EDIT_GROUP};
    die("Can't retrieve EDIT_GROUP from session") unless ($g && ref($g));

    # If we don't have an ID, we're in add mode -- impossible!
    croak ("Attempt to delete un-saved group") unless ($g->group_id);

    # Delete group object from session
    $session{EDIT_GROUP} = 0;

    # Do the delete
    $g->delete();

    add_message('message_group_deleted');

    return $self->search();
}





=item delete_selected

Delete a set of groups, specified by check-mark
on the "Group List" screen provided by the "search" 
run-mode.  Return to the "search" run-mode.

This mode expects the query param "krang_pager_rows_checked"
to contain an array of group_id values which correspond
to group records to be deleted.


=cut


sub delete_selected {
    my $self = shift;

    my $q = $self->query();
    my @group_delete_list = ( $q->param('krang_pager_rows_checked') );
    $q->delete('krang_pager_rows_checked');

    # No selected groups?  Just return to list view without any message
    return $self->search() unless (@group_delete_list);

    foreach my $id (@group_delete_list) {
        my ($g) = Krang::Group->find(group_id=>$id);
        $g->delete($id) if ($g);
    }

    add_message('message_selected_deleted');
    return $self->search();
}




=item save_and_edit_categories

Save the CGI query params to the group and redirect the user 
to the edit category permissions screen.

=cut


sub save_and_edit_categories {
    my $self = shift;

    # Retrieve working group object from session
    my $g = $session{EDIT_GROUP};
    die("Can't retrieve EDIT_GROUP from session") unless ($g && ref($g));

    # Save CGI query to group
    $self->update_group_from_query($g);

    return $self->edit_categories();
}





=item edit_categories

Present a list of categories and assigned permissions.
Allow the user to edit permissions for categories, 
add, and remove categories.


=cut


sub edit_categories {
    my $self = shift;

    # Retrieve working group object from session
    my $g = $session{EDIT_GROUP};
    die("Can't retrieve EDIT_GROUP from session") unless ($g && ref($g));

    # Get permission categories
    my %categories = $g->categories();

    my $q = $self->query();
    my $t = $self->load_tmpl('edit_categories.tmpl', associate=>$q);

    my $category_id = $q->param('category_id');
    croak ("No category ID specified") unless ($category_id);

    my $root_category_permissions = $categories{$category_id};

    my ($root_category) = Krang::Category->find(category_id=>$category_id);
    croak ("Can't retrieve root category ID '$category_id'") unless ($root_category);
    my @descendant_category_ids = ( $root_category->descendants(ids_only=>1) );

    # Extract IDs of descendant categories for which permissions have been set
    my @perm_categories = ( grep { exists($categories{$_}) } @descendant_category_ids );

    # Build up tmpl loop
    #
    # <tmpl_loop categories><tr>
    #     <td class="form-cell"><tmpl_var category_url></td>
    #     <tmpl_loop permission_radio><td class="form-cell" align="center"><tmpl_var radio_select></td></tmpl_loop>
    #     <td class="form-cell" align="center"><tmpl_unless is_root><a href="javascript:delete_category('<tmpl_var category_id>')">Delete</a></tmpl_unless></td>
    # </tr></tmpl_loop>
    my @categories = ( {
                        category_url => $root_category->url(),
                        permission_radio => $self->make_permissions_radio("category_".$category_id),
                        is_root => 1,
                        category_id => $category_id,
                       } );
    foreach my $cid (@perm_categories) {
        my ($c) = Krang::Category->find( category_id=>$cid );
        my $param_name = "category_".$cid;
        my $row = {
                   category_url => format_url(url=>$c->url(), length=>30) ,
                   permission_radio => $self->make_permissions_radio($param_name),
                   category_id => $cid,
                  };
        push(@categories, $row);
    }

    $t->param(categories => \@categories);
    $t->param(category_chooser => category_chooser(
                                                   query => $q,
                                                   name => "add_category_id",
                                                   site_id => $root_category->site_id,
                                                  ));

    return $t->output();
}





=item add_category

Add category to group permissions.


=cut


sub add_category {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
}





=item delete_category

Remove category from group permissions.


=cut


sub delete_category {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
}




=item edit_categories_return

Save category permissions to group object in session and return to 
edit group mode.


=cut


sub edit_categories_return {
    my $self = shift;

    my $q = $self->query();

    add_message("category_perms_updated");

    return $self->_edit();
}





#############################
#####  PRIVATE METHODS  #####
#############################

# Show edit form.  Used for "add" and "edit" run-mode.
# Add mode is differentiated from "edit" mode by testing
# if there is a group_id.
# The group object MUST be stored in the session before
# calling this method.
sub _edit {
    my $self = shift;
    my %ui_messages = ( @_ );

    my $g = $session{EDIT_GROUP};
    croak("Can't retrieve group object") unless ($g and ref($g));

    my $q = $self->query();
    my $t = $self->load_tmpl("edit_view.tmpl", associate=>$q);
    $t->param(add_mode => 1) unless ($g->group_id);
    $t->param(%ui_messages) if (%ui_messages);

    # Convert Krang::Contrib object to tmpl data
    my $group_tmpl = $self->get_group_tmpl($g);

    # Propagate to template
    $t->param($group_tmpl);

    return $t->output();
}


# Examine the query data to validate that the submitted
# group is valid.  Return hash-errors, if any.
sub validate_group {
    my $self = shift;

    my $q = $self->query();

    my %errors = ();

    # Validate group name
    my $name = $q->param('name');
    $errors{error_invalid_name} = 1
      unless (defined($name) && ($name =~ /\S+/));

    # Add messages
    foreach my $error (keys(%errors)) {
        add_message($error);
    }

    return %errors;
}


# Updated the provided group object with data
# from the CGI query and attempt to save.
sub do_update_group {
    my $self = shift;
    my $group = shift;

    # Update group from CGI query
    $self->update_group_from_query($group);

    # Attempt to write back to database
    eval { $group->save() };

    # Is it a dup?
    if ($@) {
        if (ref($@) and $@->isa('Krang::Group::DuplicateName')) {
            add_message('duplicate_name');
            return (duplicate_name=>1);
        } else {
            # Not our error!
            die($@);
        }
    }

    return ();
}


# Given a particular group object, update it with parameters from
# the CGI query object
sub update_group_from_query {
    my $self = shift;
    my $group = shift;

    croak ("No group specified") unless ($group and ref($group));

    # Get prototype for the purpose of update
    my %group_prototype = ( %{&GROUP_PROTOTYPE} );

    # We can't update group_id
    delete($group_prototype{group_id});

    # Get CGI query params
    my $q = $self->query();
    my @query_params = $q->param();

    # Handle desk and category permissions
    foreach my $qp (@query_params) {
        my $value = $q->param($qp);

        # Process category permissions
        if ($qp =~ /^category\_(\d+)$/) {
            my $category_id = $1;
            $group->categories($category_id=>$value);
            next;
        }

        # Process desk perms
        if ($qp =~ /^desk\_(\d+)$/) {
            my $desk_id = $1;
            $group->desks($desk_id=>$value);
            next;
        }
    }
    delete($group_prototype{categories});
    delete($group_prototype{desks});

    # Grab each CGI query param and set the corresponding Krang::Group property
    foreach my $gk (keys(%group_prototype)) {
        # Presumably, query data is already validated and un-tainted
        $group->$gk($q->param($gk));
    }
}


# Given a param name, return an html-tmpl style arrayref
# containing HTML inputs for permissions
sub make_permissions_radio {
    my $self = shift;
    my ($param_name) = @_;

    # Specify all security levels
    my @security_levels = qw(edit read-only hide);

    # Get default value from object
    my $group = $session{EDIT_GROUP};
    croak("No group available") unless ($group);

    my $default = "[N/A]";
    if ($param_name =~ /^desk\_(\d+)$/) {
        # Got desk
        my $desk_id = $1;
        $default = $group->desks($desk_id);

    } elsif ($param_name =~ /^category\_(\d+)$/) {
        # Got category
        my $category_id = $1;
        $default = $group->categories($category_id);

    } elsif (grep {$_ eq $param_name} qw(asset_story asset_media asset_template)) {
        # Got asset
        $default = $group->$param_name;

    } else {
        # Unknown param -- possible tainted data?
        croak("Unknown permission radio group '$param_name'");

    }

    # Set back to "edit" unless security level makes sense
    $default = "edit" unless ( $default && (grep { $default eq $_ } @security_levels) );

    my $q = $self->query();
    my @html_radio_inputs = $q->radio_group(
                                            -name => $param_name,
                                            -values => \@security_levels,
                                            -labels => { map { $_=>"" } @security_levels },
                                            -default => $default,
                                           );
    my @tmpl_radio_inputs = map {  {radio_select=>$_}  } @html_radio_inputs;

    return \@tmpl_radio_inputs;
}


# Given a $group object, return a hashref based on group properties, suitible
# to be passed to an HTML::Template edit/add screen.
sub get_group_tmpl {
    my $self = shift;
    my $g = shift;

    croak ("No group object specified") unless ($g and ref($g));

    my $q = $self->query();

    my %group_tmpl = ( %{&GROUP_PROTOTYPE} );
    my @root_categories = Krang::Category->find(parent_id=>undef, order_by=>'url');
    my @desks = Krang::Desk->find();

    # For each group prop, convert to HTML::Template compatible data
    foreach my $gf (keys(%group_tmpl)) {
        # Handle radio groups
        if (grep { $gf eq $_ } qw(asset_story asset_media asset_template)) {
            $group_tmpl{$gf} = $self->make_permissions_radio($gf);
            next;
        }

        # Handle desks
        if ($gf eq "desks") {
            my @desks_tmpl = ();

            # Build radio select for each desk
            foreach my $desk (@desks) {
                my $param_name = "desk_".$desk->desk_id();
                my %desk_row = (
                                desk_name => $desk->name(),
                                permission_radio => $self->make_permissions_radio($param_name),
                               );
                push(@desks_tmpl, \%desk_row);
            }

            $group_tmpl{desks} = \@desks_tmpl;

            next;
        }

        # Handle sites/categories
        if ($gf eq "categories") {
            my @categories_tmpl = ();

            # Build radio select for each category
            foreach my $category (@root_categories) {
                
                my $param_name = "category_".$category->category_id();
                my %category_row = (
                                    category_url => $category->url(),
                                    category_id => $category->category_id(),
                                    permission_radio => $self->make_permissions_radio($param_name),
                                   );
                push(@categories_tmpl, \%category_row);
            }

            $group_tmpl{categories} = \@categories_tmpl;
            next;
        }

        if (grep { $gf eq $_} qw( may_publish
                        admin_users
                        admin_users_limited
                        admin_groups
                        admin_contribs
                        admin_sites
                        admin_categories
                        admin_jobs
                        admin_desks )) {
            my $default = $g->$gf();
            $group_tmpl{$gf} = $q->checkbox( -name => $gf, 
                                             -value => "1",
                                             -checked => $default,
                                             -label => "" );
            next;
        }

        # Handle simple (text) fields
        my $query_val = $q->param($gf);
        if (defined($query_val)) {
            # Overlay query params
            $group_tmpl{$gf} = $query_val;
        } else {
            $group_tmpl{$gf} = $g->$gf if (ref($g));
        }
    }

    # Return a reference to the tmpl-compat data
    return \%group_tmpl;
}




1;


=back


=head1 SEE ALSO

L<Krang::Group>, L<Krang::Widget>, L<Krang::Message>, L<Krang::HTMLPager>, L<Krang::Pref>, L<Krang::Session>, L<Krang::Category>, L<Krang::Desk>, L<Krang::Log>, L<Carp>, L<Krang::CGI>

=cut


####  CREATED VIA:
#
#
#
# use CGI::Application::Generator;
# my $c = CGI::Application::Generator->new();
# $c->app_module_tmpl($ENV{HOME}.'/krang/templates/krang_cgi_app.tmpl');
# $c->package_name('Krang::CGI::Group');
# $c->base_module('Krang::CGI');
# $c->start_mode('search');
# $c->run_modes(qw(
#                  search
#                  add
#                  edit
#                  save
#                  save_stay
#                  cancel
#                  delete
#                  delete_selected
#                  edit_categories
#                  add_category
#                  delete_category
#                 ));
# $c->use_modules(qw/Krang::Group Krang::Widget Krang::Message Krang::HTMLPager Krang::Pref Krang::Session Krang::Category Krang::Desk Krang::Log Carp/);
# $c->tmpl_path('Group/');

# print $c->output_app_module();
