package Krang::CGI::Site;

=head1 NAME

Krang::CGI::Site - Abstract of web application....


=head1 SYNOPSIS

  use Krang::CGI::Site;
  my $app = Krang::CGI::Site->new();
  $app->run();


=head1 DESCRIPTION

Overview of functionality and purpose of web application module
Krang::CGI::Site...

=cut


use strict;
use warnings;

use base qw/Krang::CGI/;

use Carp qw(verbose croak);
use Krang::History;
use Krang::HTMLPager;
use Krang::Log qw/critical debug info/;
use Krang::Message qw/add_message/;
use Krang::Pref;
use Krang::Session qw/%session/;
use Krang::Site;

our @history_param_list = ('rm',
                           'krang_pager_curr_page_num',
                           'krang_pager_show_big_view',
                           'krang_pager_sort_field',
                           'krang_pager_sort_order_desc',);
our @obj_fields = ('url', 'preview_url', 'publish_path', 'preview_path');


##############################
#####  OVERRIDE METHODS  #####
##############################

sub setup {
    my $self = shift;

    $self->start_mode('search');

    $self->run_modes([qw/add
			add_cancel
			add_save
			add_save_stay
			delete
			delete_selected
			edit
			edit_cancel
			edit_save
			edit_save_stay
			search
			view
			view_edit
			view_return
			/]);

    $self->tmpl_path('Site/');
}


sub teardown {
    my $self = shift;
}


=head1 INTERFACE

=head2 RUN MODES

##############################
#####  RUN-MODE METHODS  #####
##############################

=over 4

=item add

This screen allows the end-user to add a new Site object.

=cut

sub add {
    my $self = shift;
    my $q = $self->query();
    my %args = @_;
    my $site;

    $q->param('add_mode', 1);

    if ($q->param('errors')) {
        $site = $session{site};
    } else {
        $site = Krang::Site->new(url => undef,
                                 preview_url => undef,
                                 preview_path => undef,
                                 publish_path => undef);
    }

    # add site to session
    $session{site} = $site;

    my $t = $self->load_tmpl('edit.tmpl',
                             associate => $q,
                             loop_context_vars => 1);

    $t->param($self->get_tmpl_params($site));

    $t->param(%args) if %args;

    return $t->output();
}



=item add_cancel

Cancels edit of site object on "Add" screen and returns to 'search' run mode.

=cut

sub add_cancel {
    my $self = shift;
    my $q = $self->query();
    add_message('message_add_cancelled');
    return $self->search();
}



=item add_save

Saves changes to the save object the end-user enacted on the 'Add' screen. The
user is sent to 'search' if save succeeds and back to the 'Add' screen if it
fails.

=cut

sub add_save {
    my $self = shift;
    my $q = $self->query();
    my $site = $session{site};
    croak("No object in session") unless ref $site;

    # update site with CGI values
    $self->update_site($site);

    # validate
    my %errors = $self->validate($site);
    return $self->add(%errors) if %errors;

    # save
    %errors = $self->_save($site);
    return $self->add(%errors) if %errors;

    add_message('message_saved');

    return $self->search();
}



=item add_save_stay

Validates changes to the site from the 'Add' screen, saves the updated object
to the database, and returns to the 'Edit' screen.

=cut

sub add_save_stay {
    my $self = shift;
    my $q = $self->query();
    my $site = $session{site};
    croak("No object in session") unless ref $site;

    # update site with CGI values
    $self->update_site($site);

    # validate
    my %errors = $self->validate($site);
    return $self->add(%errors) if %errors;

    # save
    %errors = $self->_save($site);
    return $self->add(%errors) if %errors;

    add_message('message_saved');

    return $self->edit();
}



=item delete

Deletes the user from 'Edit' screen and redirects to 'search' run mode.

It expects a 'site_id' query param.

=cut

sub delete {
    my $self = shift;

    my $q = $self->query();
    my $site_id = $q->param('site_id');
    return $self->search() unless $site_id;
    my ($site) = Krang::Site->find(site_id => $site_id);
    eval {$site->delete();};
    if ($@) {
        if (ref $@ && $@->isa('Krang::Site::Dependency')) {
            my $url = $site->url;
            info("Unable to delete site id '$site_id': $url\n$@");
            add_message('error_deletion_failure',
                        urls => $url,);
            return $self->search();
        } else {
            croak($@);
        }
    }

    add_message('message_deleted', url => $site->url);

    return $self->search();
}



=item delete_selected

Deletes Site objects selected from the 'Search' screen.  Returns to 'Search'
afterwards.

This mode expects the 'krang_pager_rows_checked' param which should contain an
array of 'site_id's signifying the user objects to be deleted.

=cut

sub delete_selected {
    my $self = shift;

    my $q = $self->query();
    my @site_delete_list = ($q->param('krang_pager_rows_checked'));
    $q->delete('krang_pager_rows_checked');

    # return to search if no ids were passed
    return $self->search() unless @site_delete_list;

    # destroy sites
    my (@bad_sites, @good_sites);
    my (@sites) = Krang::Site->find(site_id => [@site_delete_list]);
    for (@sites) {
        eval {$_->delete();};
        if ($@) {
            if (ref $@ && $@->isa('Krang::Site::Dependency')) {
                push @bad_sites, $_->url;
            } else {
                croak($@);
            }
        } else {
            push @good_sites, $_->url;
        }
    }

    if (@bad_sites) {
        info("Failed attempt to delete site(s): " . join(", ", @bad_sites));
        add_message('error_deletion_failure',
                    urls => join(", ", @bad_sites));
    } else {
        add_message('message_selected_deleted',
                    urls => join(", ", @good_sites));
    }

    return $self->search();
}



=item edit

Display a screen allowing the end-user to edit the Site object selected from
the 'search' screen.

This run mode expects a 'site_id' query param and it will croak if it's missing
or invalid.

N.B - propagate query params supercede object field values in populating form
fields, so errant values are preserved for correction.

=cut

sub edit {
    my $self = shift;
    my %args = @_;
    my $q = $self->query();
    my $site_id = $q->param('site_id') || '';
    my $site = $session{site};

    if ($site_id) {
        ($site) = Krang::Site->find(site_id => $site_id);
        $session{site} = $site;
    }
    croak("No Krang::Site object found matching site_id '$site_id'")
      unless defined $site;

    my $t = $self->load_tmpl("edit.tmpl",
                             associate => $q);

    $t->param(%args) if %args;

    $t->param($self->get_tmpl_params($site));

    return $t->output();
}



=item edit_cancel

Cancels edit of site object on "Edit" screen and returns to 'search' run
mode.

=cut

sub edit_cancel {
    my $self = shift;
    my $q = $self->query();
    add_message('message_edit_cancelled');
    return $self->search();
}



=item edit_save

Saves changes to the site object the end-user enacted on the 'Edit' screen.
The user is sent to 'search' if save succeeds and back to the 'Edit' screen if
it fails.

=cut

sub edit_save {
    my $self = shift;
    my $q = $self->query();
    my $site = $session{site};
    croak("No object in session") unless ref $site;

    # update site with CGI values
    $self->update_site($site);

    # validate
    my %errors = $self->validate($site);
    return $self->edit(%errors) if %errors;

    # save
    %errors = $self->_save($site);
    return $self->edit(%errors) if %errors;

    # update site in session
    $session{site} = $site;

    add_message('message_saved');

    return $self->search();
}



=item edit_save_stay

Validates changes to the site from the 'Edit' screen, saves the updated object
to the database, and returns to the 'Edit' screen.

=cut

sub edit_save_stay {
    my $self = shift;
    my $q = $self->query();
    my $site = $session{site};
    croak("No object in session") unless ref $site;

    # update site with CGI values
    $self->update_site($site);

    # validate
    my %errors = $self->validate($site);
    return $self->edit(%errors) if %errors;

    # save
    %errors = $self->_save($site);
    return $self->edit(%errors) if %errors;

    # update site in session
    $session{site} = $site;

    add_message('message_saved');

    return $self->edit();
}



=item search

Displays a list of Site objects based on the passed search criteria.  If no
criteria are passed, a list of all sites on the system are returned.  As a
simple search, the 'preview_path', 'preview_url', 'publish_path', 'site_id',
and 'url' fields are searched.

The run mode accepts the parameter "search_filter" which is used to perform
simple searches.

=cut

sub search {
    my $self = shift;
    my $q = $self->query();
    my $t = $self->load_tmpl("list_view.tmpl",
                             associate => $q,
                             loop_context_vars => 1);

    $t->param(history_return_params =>
              $self->make_history_return_params(@history_param_list));

    # simple search
    my $search_filter = $q->param('search_filter') || '';

    # setup pager
    my $pager = Krang::HTMLPager->new(cgi_query => $q,
                                      persist_vars => {
                                                       rm => 'search',
                                                       search_filter =>
                                                       $search_filter,
                                                      },
                                      use_module => 'Krang::Site',
                                      find_params =>
                                      {simple_search => $search_filter},
                                      columns => [
                                                  'url',
                                                  'preview_url',
                                                  'command_column',
                                                  'checkbox_column',
                                                 ],
                                      column_labels => {
                                                        url => 'URL',
                                                        preview_url =>
                                                        'Preview URL',
                                                       },
                                      columns_sortable =>
                                      [qw(url preview_url)],
                                      columns_sort_map => {},
                                      command_column_commands =>
                                      [qw(edit_site view_site)],
                                      command_column_labels =>
                                      {
                                       edit_site => 'Edit',
                                       view_site => 'View',
                                      },
                                      row_handler => \&search_row_handler,
                                      id_handler =>
                                      sub {return $_[0]->site_id},
                                     );

    # get pager output
    $t->param(pager_html => $pager->output());

    # get counter params
    $t->param(row_count => $pager->row_count());

    return $t->output();
}



=item view

View the attributes of the site object.

=cut

sub view {
    my $self = shift;
    my $q = $self->query();
    my $t = $self->load_tmpl('view.tmpl');
    my $site_id = $q->param('site_id');
    my ($site) = Krang::Site->find(site_id => $site_id);
    croak("No Krang::Site object found matching site_id '$site_id'")
      unless ref $site;

    $t->param($self->get_tmpl_params($site));
    $t->param(site_id => $site_id);

    return $t->output();
}



#############################
#####  PRIVATE METHODS  #####
#############################

# Get fields for Site object
sub get_tmpl_params {
    my ($self, $site) = @_;
    my $q = $self->query();
    my %site_tmpl;

    $site_tmpl{$_} = $site->$_ for @obj_fields;

    return \%site_tmpl;
}


# Given an array of parameter names, return HTML hidden
# input fields suitible for setting up a return link
sub make_history_return_params {
    my $self = shift;
    my @history_return_param_list = ( @_ );

    my $q = $self->query();

    my @history_return_params_hidden = ();
    foreach my $hrp (@history_return_param_list) {
        # Store param name
        push(@history_return_params_hidden,
             $q->hidden(-name => 'history_return_params',
                        -value => $hrp,
                        -override => 1));

        # Store param value
        my $pval = $q->param($hrp);
        $pval = '' unless (defined($pval));
        push(@history_return_params_hidden,
             $q->hidden(-name => 'history_return_params',
                        -value => $pval,
                        -override => 1));
    }

    my $history_return_params = join("\n", @history_return_params_hidden);
    return $history_return_params;
}


# Handles rows for search run mode
sub search_row_handler {
    my ($row, $site) = @_;
    $row->{url} = $site->url();
    $row->{preview_url} = $site->preview_url();
}


# validate
sub validate {
    my ($self, $site) = @_;

    my %errors;

    # check all fields
    for my $name (@obj_fields) {    
        my $val = $site->{$name};
        if (not length $val) {
            add_message("error_invalid_$name");
            $errors{"error_invalid_$name"} = 1;
            next;
        }

        if ($name eq 'url' or $name eq 'preview_url') {            
            # check for http://
            if ($val =~ m!https?://!) {
                add_message("error_${name}_has_http");
                $errors{"error_invalid_$name"} = 1;
            } 

            # check for /s
            if ($val =~ m!/!) {
                add_message("error_${name}_has_path");
                $errors{"error_invalid_$name"} = 1;
            }

            # check for other bad chars
            if ($val !~ m!^[-\w.:]+$!) {
                add_message("error_${name}_has_bad_chars");
                $errors{"error_invalid_$name"} = 1;
            }
        }

        if ($name eq 'publish_path' or $name eq 'preview_path') {
            # must be an absolute UNIX path
            if ($val !~ m!^/!) {
                add_message("error_${name}_not_absolute");
                $errors{"error_invalid_$name"} = 1;
            }
        }


    }

    $self->query->param('errors', 1) if keys %errors;
    return %errors;
}


# update site object
sub update_site {
    my ($self, $site) = @_;
    my $q = $self->query();

    for (@obj_fields) {
        $site->$_($q->param($_));
        $q->delete($_);
    }
}


# does the actual saving of the object to the DB
sub _save {
    my ($self, $site) = @_;
    my $q = $self->query();
    my %errors;

    eval {$site->save};

    if ($@) {
        if (ref $@ && $@->isa('Krang::Site::Duplicate')) {
            my %dups = %{$@->duplicates};
            while (my ($site_id, $field) = each %dups) {
                for (@$field) {
                    my $msg = "duplicate_$_";
                    $errors{$msg} = 1;
                    add_message($msg);
                }
            }
            $q->param('errors', 1);
            return %errors;
        } else {
            croak($@);
        }
    }

    return ();
}



=back

=cut


my $quip = <<QUIP;
1
QUIP
