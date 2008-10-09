package Krang::CGI::Trash;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

=head1 NAME

Krang::CGI::Trash - the trashbin controller

=head1 SYNOPSIS

None.

=head1 DESCRIPTION

This application manages Krang's trashbin.

=head1 INTERFACE

=head2 Run-Modes

=over 4

=cut

use Krang::ClassLoader 'HTMLPager';
use Krang::ClassLoader Localization => qw(localize);
use Krang::ClassLoader Log          => qw(debug);
use Krang::ClassLoader Message      => qw(add_message add_alert);
use Krang::ClassLoader Widget       => qw(format_url);

use UNIVERSAL::moniker;
use Carp qw(croak);

use Krang::ClassLoader base => 'CGI';

sub setup {
    my $self = shift;
    $self->start_mode('find');
    $self->mode_param('rm');
    $self->tmpl_path('Trash/');
    $self->run_modes(
        [
            qw(
              find
              goto_view
              delete_checked
              restore_checked
              restore_object
              )
        ]
    );
}

=item find

Find assets living in the trashbin. This is the default runmode and it
requires no parameters.

=cut

sub find {
    my $self     = shift;
    my $query    = $self->query;
    my $template = $self->load_tmpl(
        "trash.tmpl",
        associate         => $query,
        die_on_bad_params => 0,
        loop_context_vars => 1,
        global_vars       => 1
    );

    # admin delete permission
    $template->param(admin_may_delete => pkg('Group')->user_admin_permissions('admin_delete'));

    my %col_labels = (
        id    => 'ID',
        type  => 'Type',
        title => 'Title',
        url   => 'URL',
        date  => 'Date',
    );

    # setup paging list of objects
    my $pager = pkg('HTMLPager')->new(
        cgi_query        => $query,
        use_module       => pkg('Trash'),
        columns          => ['id', 'type', 'title', 'url', 'date', 'thumbnail', 'checkbox_column'],
        column_labels    => \%col_labels,
        columns_sortable => [qw(id type title url date)],
        columns_hidden   => ['checkbox_column'],
        id_handler  => sub { $self->_id_handler(@_) },
        row_handler => sub { $self->_row_handler(@_) },
    );

    # Run the pager
    $pager->fill_template($template);
    return $template->output;
}

sub _id_handler { return $_[1]->{type} . '_' . $_[1]->{id} }

sub _row_handler {
    my ($self, $row, $obj, $pager) = @_;

    # do the clone
    $row->{$_} = $obj->{$_} for keys %$obj;

    # fix problem with root level templates:
    # SQL query will return NULL for may_edit but these assets at the root
    # will only be subject to asset-level permissions, not category-level
    # ones. Category-level will set may_edit == 0 if not allowed.

    if (($row->{type} eq 'template') && (!defined $row->{may_edit})) {
        if (index($row->{url}, '/') == 0) {
            $row->{may_edit} = 1;
        }
    }

    # Uppercase story type
    $row->{class} = ucfirst($row->{class});

    # maybe show list controls
    if ($row->{may_edit}) {
        $pager->column_display('checkbox_column' => 1);
    }

    # format date
    my $date = $obj->{date};
    if ($date and $date ne '0000-00-00 00:00:00') {
        $date = Time::Piece->from_mysql_datetime($date);
        $row->{date} = $date->strftime('%m/%d/%Y %I:%M %p');
    } else {
        $row->{date} = '[n/a]';
    }

    # format URL
    if ($obj->{linkto}) {
        $row->{url} = format_url(
            url    => $obj->{url},
            linkto => "javascript:Krang.preview('$obj->{type}'," . $obj->{id} . ")",
            length => 50
        );
    } else {
        $row->{url} = format_url(
            url    => $obj->{url},
            length => 50
        );
    }

    # finally the asset type
    $row->{asset_type} = ucfirst($obj->{type});
}

=item goto_view

Redirects to the view detail screen for this object.

=cut

sub goto_view {
    my $self  = shift;
    my $query = $self->query;

    my $id      = $query->param('id');
    my $type    = $query->param('type');
    my $script  = $type . '.pl';
    my $type_id = $type . '_id';

    my $uri = "$script?rm=view&$type_id=$id&return_script=trash.pl";

    # mix in pager params for return
    foreach my $name (grep { /^krang_pager/ } $query->param) {
        $uri .= "&return_params=${name}&return_params=" . $query->param($name);
    }

    $self->header_props(-uri => $uri);
    $self->header_type('redirect');
    return "";
}

=item delete_checked

Deletes a list of checked objects.  Requires the param
krang_pager_rows_checked to be set to a list of values of the form
'type_id'.

=cut

sub delete_checked {
    my $self  = shift;
    my $query = $self->query;

    my @alerts = ();

    # try to delete
    foreach my $object (map { $self->_id2obj($_) } $query->param('krang_pager_rows_checked')) {

        eval { pkg('Trash')->delete(object => $object) };

        if ($@ and ref($@) and $@->moniker eq 'nodeleteaccess') {
            my $id_meth = $object->id_meth;
            push @alerts, ucfirst($object->moniker) . ' ' . $object->$id_meth . ': ' . $object->url;
        }
    }

    # inform user of what happened
    if (@alerts) {
        add_alert(
            'no_delete_permission',
            s => (scalar(@alerts) > 1 ? 's' : ''),
            item_list => join '<br/>',
            @alerts
        );
    } else {
        add_message('deleted_checked');
    }

    return $self->find;
}

=item restore_checked

Restore a list of checked ojects, bringing them back to Live or to
Retired.  Requires a 'krang_pager_rows_checked' param.

=cut

sub restore_checked {
    my $self  = shift;
    my $query = $self->query;

    my @restored = ();
    my @failed   = ();

    # try to restore
    foreach my $object (map { $self->_id2obj($_) } $query->param('krang_pager_rows_checked')) {

        eval { pkg('Trash')->restore(object => $object) };

        if ($@ and ref($@)) {
            my $exception = $@;    # save it away
            push @failed, $self->_format_msg(object => $object, exception => $exception);
        } else {
            push @restored, $self->_format_msg(object => $object);
        }
    }

    # inform user of what happened
    $self->_register_msg(\@restored, \@failed);

    return $self->find;
}

=item restore_object

Restore one object, bringing it back to Live or to Retired.  Requires
an 'type_id' param.

=cut

sub restore_object {
    my $self  = shift;
    my $query = $self->query;
    $query->param(krang_pager_rows_checked => $query->param('type_id'));
    return $self->restore_checked;
}

#
# Utility functions
#

# pass the messages to add_message() or add_alert()
sub _register_msg {
    my ($self, $restored, $failed) = @_;

    my @restored = @$restored;
    my @failed   = @$failed;

    my $func = 'add_message';

    if (@failed) {
        if (@failed == 1) {
            add_alert('not_restored_item', item => $failed[0]);
        } else {
            add_alert('not_restored_items', items => join('<br/>', @failed));
        }
        $func = 'add_alert';
    }

    if (@restored) {
        no strict 'refs';
        if (@restored == 1) {
            $func->('restored_item', item => $restored[0]);
        } else {
            $func->('restored_items', items => join('<br/>', @restored));
        }
        use strict 'refs';
    }
}

# format a message/alert
sub _format_msg {
    my ($self, %args) = @_;

    my $ex      = $args{exception};    # in case of conflict
    my $object  = $args{object};
    my $type    = $object->moniker;
    my $id_meth = $object->id_meth;
    my $id      = $object->$id_meth;
    my $msg     = ucfirst($type) . ' ' . $id . ' &ndash; ' . $object->url;

    # Success
    unless ($ex) {
        $msg .= ' (retired)' if $object->retired;
        return $msg;
    }

    my $ex_type = $ex->moniker;

    # No restore permission
    return "$msg  " . localize('(no restore permission)')
      if $ex_type eq 'norestoreaccess';

    # URL conflict
    if ($ex_type eq 'duplicateurl') {
        if ($ex->can('categories') and $ex->categories) {
            my @cats = @{$ex->categories};
            return $msg
              . '<br/>('
              . localize('Reason: URL conflict with Category ')
              . join(', ', map { $_->{id} } @cats) . ' )';
        } elsif ($ex->can('stories') and $ex->stories) {
            my @stories = @{$ex->stories};
            return $msg
              . '<br/>('
              . localize('Reason: URL conflict with Story ')
              . join(', ', map { $_->{id} } @stories) . ' )';
        } elsif (my $id = $ex->$id_meth) {
            return $msg
              . '<br/>('
              . localize('Reason: URL conflict with') . ' '
              . localize(ucfirst($type)) . ' '
              . $id . ')';
        } else {
            return $msg . '<br/>(' . localize('Reason: URL conflict - no further information)');
        }
    }

    return "$msg " . localize('(unknown reason)');
}

# transform type_id into an object
sub _id2obj {
    my $self = shift;

    my ($type, $id) = $_[0] =~ /^([^_]+)_(.*)$/;
    croak("Unable to find type and id in '$_[0]'")
      unless $type and $id;

    # get package to handle type
    my $pkg = pkg(ucfirst($type));

    croak("No Krang package for type '$type' found")
      unless $pkg;

    # get object with this id
    my ($obj) = $pkg->find($pkg->id_meth => $id);

    croak("Unable to load $type $id")
      unless $obj;

    return $obj;
}

1;

=back

=cut
