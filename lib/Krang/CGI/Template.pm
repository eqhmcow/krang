package Krang::CGI::Template;

=head1 NAME

Krang::CGI::Template - Module what manages templates


=head1 SYNOPSIS

  use Krang::CGI::Template;
  my $app = Krang::CGI::Template->new();
  $app->run();


=head1 DESCRIPTION

This module provide the end-user interface to template objects.  Here, users
may search for, view, edit, and create templates.

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
use Krang::Template;
use Krang::Widget qw/category_chooser/;

# Persist data for return from view in "history_return_params"
our @history_param_list = ('rm',
                           'krang_pager_curr_page_num',
                           'krang_pager_show_big_view',
                           'krang_pager_sort_field',
                           'krang_pager_sort_order_desc',
                           'search_below_category_id',
                           'search_element',
                           'search_filename',
                           'search_filter',
                           'search_template_id',
                           'search_url',);

our @elements = Krang::ElementLibrary->element_names();

##############################
#####  OVERRIDE METHODS  #####
##############################

sub setup {
	my $self = shift;

	$self->start_mode('search');

	$self->run_modes([qw/
		add
		add_cancel
		add_save
		add_save_stay
		advanced_search
		cancel_add
		cancel_edit
		delete
		delete_selected
		edit
		edit_cancel
		edit_save
		edit_save_stay
		revert_version
		save_and_view_log
		search
		view
		view_edit
		view_version
	/]);

	$self->tmpl_path('Template/');

}


sub teardown {
	my $self = shift;
}


=head1 INTERFACE

=head2 RUN MODES

=over 4

##############################
#####  RUN-MODE METHODS  #####
##############################


=item add

This screen allows the end-user to add a new Template object.

=cut

sub add {
	my $self = shift;
        my %args = @_;
	my $q = $self->query();
        $q->param('add_mode', 1);

        my $template = Krang::Template->new();

        # add template to session
        $session{template} = $template;

        my $t = $self->load_tmpl('edit.tmpl',
                                 associate => $q,
                                 loop_context_vars => 1);

        $t->param($self->get_tmpl_params($template));

        $t->param(%args) if %args;

	return $t->output();
}



=item add_cancel

Cancels edit of template object on "Add" screen and returns to 'search' run
mode.

=cut


sub add_cancel {
	my $self = shift;

	my $q = $self->query();

        add_message('message_add_cancelled');

	return $self->search();
}



=item add_save

Description of run-mode add_save...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure

=cut


sub add_save {
	my $self = shift;

	my $q = $self->query();

	return $self->dump_html();
}



=item add_save_stay

Description of run-mode add_save_stay...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure

=cut


sub add_save_stay {
	my $self = shift;

	my $q = $self->query();

	return $self->dump_html();
}



=item advanced_search

The find mode allows the user to run an "advanced search" on
media objects, which will be listed on a paging view.

From this paging view the user may choose to edit or view
an object, or select a set of objects to be deleted.

=cut

sub advanced_search {
    my $self = shift;

    my $q = $self->query();
    my $t = $self->load_tmpl('list_view.tmpl', associate=>$q);
    $t->param(do_advanced_search=>1);
    $t->param(history_return_params =>
              $self->make_history_return_params(@history_param_list));

    my $persist_vars = { rm => 'advanced_find' };
    my $find_params = {};

    # Build find params
    my $search_below_category_id = $q->param('search_below_category_id');
    if ($search_below_category_id) {
        $persist_vars->{search_below_category_id} = $search_below_category_id;
        $find_params->{below_category_id} = $search_below_category_id;
    }

    # search_element
    my $search_element = $q->param('search_element') || '';
    if ($search_element) {
        $find_params->{element_class_name_like} = "\%$search_element\%";
        $persist_vars->{search_element} = $search_element;
    }

    # search_template_id
    my $search_template_id = $q->param('search_template_id');
    if ($search_template_id) {
        $find_params->{template_id} = $search_template_id;
        $persist_vars->{search_template_id} = $search_template_id;
    }

    # search_url
    my $search_url = $q->param('search_url');
    if ($search_url) {
        $search_url =~ s/\W+/\%/g;
        $find_params->{url_like} = "\%$search_url\%";
        $persist_vars->{search_url} = $search_url;
    }

    # Run pager
    my $pager = $self->make_pager($persist_vars, $find_params);
    $t->param(pager_html => $pager->output());
    $t->param(row_count => $pager->row_count());

    # Set up element select
    my @element_loop;
    for (@elements) {
        my $selected = $search_element eq $_ ? 1 : 0;
        push @element_loop, {name => $_, selected => $selected, value => $_};
    }
    $t->param(element_loop => \@element_loop);

    # Set up advanced search form
    $t->param(category_chooser => category_chooser(query => $q,
                                                   name =>
                                                   'search_below_category_id',
                                                   formname => 'search_form'));
    return $t->output();
}



=item delete

Deletes a template object from the 'Edit' screen.

The mode expects the query parameter 'template_id'.

=cut

sub delete {
	my $self = shift;
	my $q = $self->query();
        my $template_id = $q->param('template_id');

        eval {Krang::Template->delete($template_id)};
        if ($@){
            if (ref $@ && $@->isa('Krang::Template::Checkout')) {
                critical("Unable to delete template id '$template_id': $@");
                add_message('error_deletion_failure',
                            template_id => 'template_id');
            } else {
                croak($@);
            }
        } else {
            add_message('message_deleted');
        }

	return $self->search();
}



=item delete_selected

Deletes template objects selected from the 'search' screen and returns to
'search'.  If the object associated with a particular template_id cannot be
deleted, the user is returned to 'search' screen with an error message.

This mode expects the 'krang_pager_rows_checked' query param to contain the ids
of the objects to be deleted.  If none are passed, the user is returned to
the 'search' screen.

=cut

sub delete_selected {
	my $self = shift;
	my $q = $self->query();

        my @template_ids = $q->param('krang_pager_rows_checked');

        return $self->search unless @template_ids;

        my @bad_ids;
        for my $t(@template_ids) {
            debug(__PACKAGE__ . ": attempting to delete template id '$t'.");
            eval {Krang::Template->delete($t);};
            if ($@) {
                if (ref $@ && $@->isa('Krang::Template::Checkout')) {
                    critical("Unable to delete template id '$t': $@");
                    push @bad_ids, $t;
                } else {
                    croak($@)
                }
            }
        }

        if (@bad_ids) {
            add_message('error_deletion_failure',
                        template_id => join(", ", @bad_ids));
        } else {
            add_message('message_selected_deleted');
        }
        return $self->search;
}



=item edit

Displays the properties of a template object and allows the user to modify the
writable fields of the object.

This runmode expects the query parameter 'template_id'.

=cut

sub edit {
	my $self = shift;
        my %args = @_;
	my $q = $self->query();
        my $template_id = $q->param('template_id');
        my $template = $session{template};

        if ($template_id &&
            (not(ref($template)) ||
             $template->template_id != $template_id)) {
            ($template) = Krang::Template->find(template_id => $template_id);
            $session{template} = $template;
        }
        croak("No template object.") unless ref $template;

        my $t = $self->load_tmpl("edit.tmpl",
                                 associate => $q,);

        $t->param(%args) if %args;

        $t->param($self->get_tmpl_params($template));

        return $t->output();
}



=item edit_cancel

Cancels edit of template object on "Edit" screen and returns to 'search' run
mode.

=cut


sub edit_cancel {
	my $self = shift;

	my $q = $self->query();

        add_message('message_edit_cancelled');

	return $self->search();
}



=item edit_save

Saves changes to the template object the end-user enacted on the 'Edit' screen.
The user is sent to 'search' if save succeeds and back to the 'Edit' screen if
it fails.

=cut


sub edit_save {
	my $self = shift;
	my $q = $self->query();
        my $template = $session{template};
        croak("No object in session") unless ref $template;

        # update template with CGI values
        $self->update_template($template);

        # validate
        my %errors = $self->validate($template);
        return $self->edit(%errors) if %errors;

        # save
        %errors = $self->_save($template);
        return $self->edit(%errors) if %errors;

        add_message('message_saved');

	return $self->search();
}



=item edit_save_stay

Validates changes to the template from the 'Edit' screen, saves the updated
object to the database, and returns to the 'Edit' screen.

=cut

sub edit_save_stay {
    my $self = shift;
    my $q = $self->query();
    my $template = $session{template};
    croak("No object in session") unless ref $template;

    # update template with CGI values
    $self->update_template($template);

    # validate
    my %errors = $self->validate($template);
    return $self->edit(%errors) if %errors;

    # save
    %errors = $self->_save($template);
    return $self->edit(%errors) if %errors;

    add_message('message_saved');

    return $self->edit();
}



=item revert_version

Reverts the template to a prior incarnation.

=cut

sub revert_version {
    my $self = shift;
    my $q = $self->query();
    my $selected_version = $q->param('selected_version');

    croak("Invalid selected version '$selected_version'")
      unless ($selected_version and $selected_version =~ /^\d+$/);

    # Perform revert
    my $template = $session{template};
    $template->revert($selected_version);

    # Inform user
    add_message("message_revert_version",
                version => $selected_version);

    return $self->edit();
}



=item save_and_view_log

The purpose of this mode is to hand the user off to the log viewng
screen.  This mode writes changes back to the media object without
calling save().  When done, it performs an HTTP redirect to
history.pl.

=cut

sub save_and_view_log {
    my $self = shift;

    my $q = $self->query();

    # Update media object
    my $template = $session{template};
    $self->update_template($template);

    my $template_id = $template->template_id;

    # Redirect to associate screen
    my $url = "history.pl?history_return_script=template.pl&history_return_params=rm&history_return_params=edit&history_return_params=template_id&history_return_params=$template_id&template_id=$template_id";
    $self->header_props(-uri=>$url);
    $self->header_type('redirect');

    return "Redirect: <a href=\"$url\">$url</a>";
}



=item search

Displays a list of Template objects based on the passed search criteria.  If no
criteria are passed, a list of all templates on the system are returned.  As a
simple search, the 'element', 'site', and 'url' fields are searched.

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

        my $search_filter = $q->param('search_filter') || '';
        my $find_params = {simple_search => $search_filter};
        my $persist_vars = {rm => 'search',
                            search_filter => $search_filter};

        # setup pager
        my $pager = $self->make_pager($persist_vars, $find_params);

        # get pager output
        $t->param(pager_html => $pager->output());

        # get counter params
        $t->param(row_count => $pager->row_count());

        return $t->output();
}



=item view

View the attributes of the template object.

=cut

sub view {
	my $self = shift;
        my $version = shift;
	my $q = $self->query();
        my $t = $self->load_tmpl('view.tmpl');
        my $template_id = $q->param('template_id') ||
          croak("No 'template_id' specified.");
        my %find;

        $find{template_id} = $template_id;

        if ($version) {
            $find{version} = $version;
            $t->param(is_old_version => 1);
        }
        my ($template) = Krang::Template->find(%find);
        croak("Can't find template with template_id '$template_id'.")
          unless ref $template;

        $t->param($self->get_tmpl_params($template));

	return $t->output();
}



=item view_version

Display the specified version of the template object in a view form.

=cut

sub view_version {
    my $self = shift;
    my $q = $self->query();
    my $selected_version = $q->param('selected_version');

    die ("Invalid selected version '$selected_version'")
      unless ($selected_version and $selected_version =~ /^\d+$/);

    # Update media object
    my $template = $session{template};
    $self->update_template($template);

    # Return view mode with version
    return $self->view($selected_version);
}



#############################
#####  PRIVATE METHODS  #####
#############################

# Construct param hashref to be used for edit template output
sub get_tmpl_params {
    my $self = shift;
    my $template = shift;
    my $q = $self->query();
    my @fields = qw/content element_class_name template_id url version/;
    my $rm = $q->param('rm');
    my (%tmpl_params, $version);

    # loop through template fields
    if ($q->param('errors')) {
        $tmpl_params{$_} = $q->param($_) for @fields;
        $version = $q->param('version');
    } else {
        $tmpl_params{$_} = $template->$_ for @fields;
        $version = $template->version;
    }

    if ($q->param('add_mode')) {
        my @values = ('', Krang::ElementLibrary->element_names);
        my %labels = map {$_, $_} Krang::ElementLibrary->element_names;
        $tmpl_params{element_chooser} = $q->popup_menu(-name =>
                                                       'element_class_name',
                                                       -values => \@values,
                                                       -labels => \%labels);
    }

    unless ($rm =~ /^view/) {
        $tmpl_params{category_chooser} =
          category_chooser(query => $q,
                           name => 'category_id',
                           formname => 'edit_template_form');
        $tmpl_params{upload_chooser} = $q->filefield(-name => 'template_file',
                                                     -size => 32);
        $tmpl_params{version_chooser} =
          $q->popup_menu(-name => 'selected_version',
                         -values => [1..$version],
                         -default => $version,
                         -override => 1);
        $tmpl_params{history_return_params} =
          $self->make_history_return_params('rm');
    } else {
        my %history_hash = $q->param('history_return_params');
        my @history_params;
        while (my($k,$v) = each %history_hash) {
            push @history_params, $q->hidden(-name => $k,
                                             -value => $v,
                                             -override => 1);
        }
        $tmpl_params{history_return_params} = join("\n", @history_params);
    }

    return \%tmpl_params;
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


# Given a persist_vars and find_params, return the pager object
sub make_pager {
    my $self = shift;
    my ($persist_vars, $find_params) = @_;

    my @columns = qw(deployed
                     template_id
		     element_class_name
                     url
                     command_column
                     checkbox_column
                    );

    my %column_labels = (deployed => '',
                         template_id => 'ID',
                         element_class_name => 'Element',
                         url => 'URL',
                        );

    my $q = $self->query();
    my $pager = Krang::HTMLPager->new(
                                      cgi_query => $q,
                                      persist_vars => $persist_vars,
                                      use_module => 'Krang::Template',
                                      find_params => $find_params,
                                      columns => \@columns,
                                      column_labels => \%column_labels,
                                      columns_sortable =>
                                      ['template_id',
                                       'element_class_name',
                                       'url',],
                                      command_column_commands =>
                                      [qw(edit_template view_template)],
                                      command_column_labels =>
                                      {edit_template => 'Edit',
                                       view_template => 'View',},
                                      row_handler => \&search_row_handler,
                                      id_handler =>
                                      sub {return $_[0]->template_id},
                                     );

    return $pager;
}


# Handles rows for search run mode
sub search_row_handler {
    my ($row, $template) = @_;
    $row->{element_class_name} = $template->element_class_name;
    $row->{template_id} = $template->template_id;
    $row->{url} = $template->url;
}


# Updates object with CGI param values
sub update_template {
    my $self = shift;
    my $template = shift;
    my $q = $self->query();

    for (qw/category_id content testing/) {
        my $val = $q->param($_) || '';
        if ($_ eq 'content' && $val) {
            if (my $fh = $q->upload('template_file')) {
                my ($buffer, $content);
                $content .= $buffer while (read($fh, $buffer, 10240));
                $template->$_($content);
                $q->delete('template_file');
            } else {
                $template->$_($val);
            }
        } elsif ($_ eq 'category_id') {
            $template->$_($val) if $val ne '';
        } elsif ($_ eq 'testing') {
            $template->mark_for_testing;
        } else {
            $template->$_($val);
        }
        $q->delete($_);
    }
}


# Validates input from the CGI
sub validate {
    my ($self, $template) = @_;
    my %errors;

    # validate element
    my $element = $template->element_class_name || '';
    $errors{error_element} = 1
      unless ($element || grep {$_ eq $element} @elements);

    return %errors;;
}


# does the actual saving of the object to the DB
sub _save {
    my ($self, $template) = @_;

    eval {$template->save};

    if ($@) {
        if (ref $@ && $@->isa('Krang::Template::DuplicateURL')) {
            add_message('duplicate_url');
            return (duplicate_url => 1);
        } else {
            croak($@);
        }
    }

    return ();
}


=back

=head1 AUTHOR

Author of Module <author@module>

=head1 SEE ALSO

L<Carp>, L<Krang::History>, L<Krang::HTMLPager>, L<Krang::Log>, L<Krang::Message>, L<Krang::Pref>, L<Krang::Session>, L<Krang::Template>, L<Krang::CGI>

=cut


my $quip = <<QUIP;
1
QUIP
