package Krang::CGI::Media;
use base qw(Krang::CGI);
use strict;
use warnings;




=head1 NAME

Krang::CGI::Media - web interface to manage media


=head1 SYNOPSIS

  use Krang::CGI::Media;
  my $app = Krang::CGI::Media->new();
  $app->run();


=head1 DESCRIPTION

Krang::CGI::Media provides a web-based system
through which users can add, modify, delete, 
check out, or publish media.


=head1 INTERFACE

Following are descriptions of all the run-modes
provided by Krang::CGI::Media.

The default run-mode (start_mode) for Krang::CGI::Media
is 'add'.

=head2 Run-Modes

=over 4

=cut


use Krang::Media;
use Krang::Widget qw(category_chooser date_chooser decode_date);
use Krang::Message qw(add_message);
use Krang::HTMLPager;
use Krang::Pref;
use Krang::Session qw(%session);
use Carp qw(croak);



##############################
#####  OVERRIDE METHODS  #####
##############################

sub setup {
    my $self = shift;

    $self->start_mode('add');

    $self->run_modes([qw(
                         find
                         advanced_find
                         add
                         save_add
                         cancel_add
                         save_stay_add
                         edit
                         save_edit
                         cancel_edit
                         save_stay_edit
                         delete
                         delete_selected
                         view
                        )]);

    $self->tmpl_path('Media/');
}




##############################
#####  RUN-MODE METHODS  #####
##############################




=item find

The find mode allows the user to run a "simple search" on 
media objects, which will be listed on a paging view.

From this paging view the user may choose to edit or view
an object, or select a set of objects to be deleted.

=cut


sub find {
    my $self = shift;

    my $q = $self->query();
    my $t = $self->load_tmpl('list_view.tmpl', associate=>$q);

    my $search_filter = $q->param('search_filter');
    my $show_thumbnails = $q->param('show_thumbnails');
    unless (defined($search_filter)) {
        # Define search_filter
        $search_filter = '';

        # Undefined search_filter probably means it's the first time we're here.
        # Set show_thumbnails to '1' by default
        $show_thumbnails = 1;
    } else {
        # If search_filter is defined, but not show_thumbnails, assume show_thumbnails is false
        $show_thumbnails = 0 unless (defined($show_thumbnails));
    }

    my $persist_vars = {
                        rm => 'find',
                        search_filter => $search_filter,
                        show_thumbnails => $show_thumbnails,
                       };

    my $find_params = { simple_search => $search_filter };

    my $pager = $self->make_pager($persist_vars, $find_params, $show_thumbnails);

    # Run pager
    $t->param(pager_html => $pager->output());
    $t->param(row_count => $pager->row_count());
    $t->param(show_thumbnails => $show_thumbnails);

    return $t->output();
}





=item advanced_find

The find mode allows the user to run an "advanced search" on 
media objects, which will be listed on a paging view.

From this paging view the user may choose to edit or view
an object, or select a set of objects to be deleted.

=cut


sub advanced_find {
    my $self = shift;

    my $q = $self->query();
    my $t = $self->load_tmpl('list_view.tmpl', associate=>$q);
    $t->param(do_advanced_search=>1);

    my $persist_vars = { rm => 'advanced_find' };
    my $find_params = {};

    my $show_thumbnails = $q->param('show_thumbnails');
    $show_thumbnails = 0 unless (defined($show_thumbnails));
    $persist_vars->{show_thumbnails} = $show_thumbnails;

    # Set up advanced search form
    $t->param(category_chooser => category_chooser(
                                                 query => $q,
                                                 name => 'search_below_category_id',
                                                 formname => 'search_form',
                                                ));
    $t->param(date_chooser => date_chooser(
                                           query => $q,
                                           name => 'search_creation_date',
                                           nochoice =>1,
                                          ));

    # Build find params
    my $search_below_category_id = $q->param('search_below_category_id');
    $persist_vars->{search_below_category_id} = $search_below_category_id;

    my $search_creation_date = decode_date(
                                           query => $q,
                                           name => 'search_below_category_id',
                                          );
    if ($search_creation_date) {
        $find_params->{creation_date} = $search_creation_date;
        $persist_vars->{search_creation_date_day}   = $q->param('search_creation_date_day');
        $persist_vars->{search_creation_date_month} = $q->param('search_creation_date_month');
        $persist_vars->{search_creation_date_year}  = $q->param('search_creation_date_year');
    }

    # search_filename
    my $search_filename = $q->param('search_filename');
    if ($search_filename) {
        $search_filename =~ s/\W+/\%/g;
        $find_params->{filename_like} = "\%$search_filename\%";
        $persist_vars->{search_filename} = $search_filename;
    }

    # search_title
    my $search_title = $q->param('search_title');
    if ($search_title) {
        $search_title =~ s/\W+/\%/g;
        $find_params->{title_like} = "\%$search_title\%";
        $persist_vars->{search_title} = $search_title;
    }

    # search_media_id
    my $search_media_id = $q->param('search_media_id');
    if ($search_media_id) {
        $find_params->{media_id} = $search_media_id;
        $persist_vars->{search_media_id} = $search_media_id;
    }

    # search_has_attributes
    my $search_has_attributes = $q->param('search_has_attributes');
    if ($search_has_attributes) {
        $find_params->{has_attributes} = $search_has_attributes;
        $persist_vars->{search_has_attributes} = $search_has_attributes;
    }

    # Run pager
    my $pager = $self->make_pager($persist_vars, $find_params, $show_thumbnails);
    $t->param(pager_html => $pager->output());
    $t->param(row_count => $pager->row_count());

    return $t->output();
}





=item add

Description of run-mode 'add'...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure


=cut


sub add {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
}





=item save_add

Description of run-mode 'save_add'...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure


=cut


sub save_add {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
}





=item cancel_add

Description of run-mode 'cancel_add'...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure


=cut


sub cancel_add {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
}





=item save_stay_add

Description of run-mode 'save_stay_add'...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure


=cut


sub save_stay_add {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
}





=item edit

Description of run-mode 'edit'...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure


=cut


sub edit {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
}





=item save_edit

Description of run-mode 'save_edit'...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure


=cut


sub save_edit {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
}





=item cancel_edit

Description of run-mode 'cancel_edit'...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure


=cut


sub cancel_edit {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
}





=item save_stay_edit

Description of run-mode 'save_stay_edit'...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure


=cut


sub save_stay_edit {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
}





=item delete

Description of run-mode 'delete'...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure


=cut


sub delete {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
}





=item delete_selected

Description of run-mode 'delete_selected'...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure


=cut


sub delete_selected {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
}





=item view

Description of run-mode 'view'...

  * Purpose
  * Expected parameters
  * Function on success
  * Function on failure


=cut


sub view {
    my $self = shift;

    my $q = $self->query();

    return $self->dump_html();
}







#############################
#####  PRIVATE METHODS  #####
#############################

# Given a persist_vars and find_params, return the pager object
sub make_pager {
    my $self = shift;
    my ($persist_vars, $find_params, $show_thumbnails) = @_;

    my @columns = qw(
                     pub_status 
                     media_id 
                     thumbnail
                     url
                     title 
                     creation_date
                     command_column 
                     checkbox_column
                    );

    my %column_labels = ( 
                         pub_status => '',
                         media_id => 'ID',
                         thumbnail => 'Thumbnail',
                         url => 'URL',
                         title => 'Title',
                         creation_date => 'Date',
                        );

    # Hide thumbnails
    unless ($show_thumbnails) {
        splice(@columns, 2, 1);
        delete($column_labels{thumbnail});
    }

    my $q = $self->query();
    my $pager = Krang::HTMLPager->new(
                                      cgi_query => $q,
                                      persist_vars => $persist_vars,
                                      use_module => 'Krang::Media',
                                      find_params => $find_params,
                                      columns => \@columns,
                                      column_labels => \%column_labels,
                                      columns_sortable => [qw( media_id url title creation_date )],
                                      command_column_commands => [qw( edit_media view_media )],
                                      command_column_labels => {
                                                                edit_media     => 'Edit',
                                                                view_media     => 'View',
                                                               },
                                      row_handler => sub { $self->find_media_row_handler($show_thumbnails, @_); },
                                      id_handler => sub { return $_[0]->media_id },
                                     );

    return $pager;
}


# Pager row handler for media find run-modes
sub find_media_row_handler {
    my $self = shift;
    my ($show_thumbnails, $row, $media) = @_;

    # media_id
    $row->{media_id} = $media->media_id();

    # format url to fit on the screen and to link to preview
    my $url = $media->url();
    my @parts = split('/', $url);
    my @url_lines = (shift(@parts), "");
    for(@parts) {
        if ((length($url_lines[-1]) + length($_)) > 15) {
            push(@url_lines, "");
        }
        $url_lines[-1] .= "/" . $_;
    }
    $row->{url} = join('<br>', 
                       map { qq{<a href="javascript:preview_media($row->{media_id})">$_</a>} } @url_lines);

    # title
    $row->{title} = $media->title();

    # thumbnail
    if ($show_thumbnails) {
        my $thumbnail_path = $media->thumbnail_path(relative => 1);
        $row->{thumbnail} = "<img src=\"$thumbnail_path\">";
    }

    # creation_date
    my $tp = $media->creation_date();
    $row->{creation_date} = (ref($tp)) ? $tp->mdy('/') : '[n/a]';

    # pub_status  -- NOT YET IMPLEMENTED
    $row->{pub_status} = '&nbsp;<b>P</b>&nbsp;';

}




1;


=back


=head1 AUTHOR

Author of Module <author@module>


=head1 SEE ALSO

L<Krang::Media>, L<Krang::Widget>, L<Krang::Message>, L<Krang::HTMLPager>, L<Krang::Pref>, L<Krang::Session>, L<Carp>, L<Krang::CGI>

=cut



####  Created by:  ######################################
#
#
# use CGI::Application::Generator;
# my $c = CGI::Application::Generator->new();
# $c->app_module_tmpl($ENV{HOME}.'/krang/templates/krang_cgi_app.tmpl');
# $c->package_name('Krang::CGI::Media');
# $c->base_module('Krang::CGI');
# $c->start_mode('add');
# $c->run_modes(qw(
#                  find
#                  advanced_find
#                  add
#                  save_add
#                  cancel_add
#                  save_stay_add
#                  edit
#                  save_edit
#                  cancel_edit
#                  save_stay_edit
#                  delete
#                  delete_selected
#                  view
#                 ));
# $c->use_modules(qw/Krang::Media Krang::Widget Krang::Message Krang::HTMLPager Krang::Pref Krang::Session Carp/);
# $c->tmpl_path('Media/');
# print $c->output_app_module();
