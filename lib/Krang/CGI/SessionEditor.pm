package Krang::CGI::SessionEditor;
use strict;
use warnings;
use Krang::ClassLoader base => 'CGI';
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader Log     => qw(critical info debug);
use Krang::ClassLoader Session => qw/%session/;
use Krang::ClassLoader 'UUID';
use Carp qw(croak);
use File::Spec::Functions qw(catdir rel2abs);

=head1 NAME

Krang::CGI::SessionEditor - Krang base class for CGI modules that edit objects in the session

=head1 SYNOPSIS

    package Krang::CGI::Template;
    use Krang::ClassLoader base => 'CGI::SessionEditor';
    use Krang::ClassFactory qw(pkg);

    sub edit_object_package { pkg('Template') }

    my $obj = $self->get_edit_object();
    $self->set_edit_object($obj);
    $self->clear_edit_object();

=cut

sub edit_object_package {
    my $pkg = shift;
    croak("You must implement edit_object_package in your class $pkg!");
}

=head1 DESCRIPTION

Krang::CGI is a subclass of L<CGI::Application>.  All the usual
CGI::Application features are available.

=head1 INTERFACE

=head2 REQUIRED METHODS

=head3 edit_object_package

This method returns the name of the package that is used to pull the
object from the database. This package must have a Krang compatible
C<find()> and C<id_meth()> method.

=head2 METHODS

This is a subclass of L<Krang::CGI> so it inherits all of those methods
and provides the following additional methods:

=head3 get_edit_object

This method will get the object in question from either the session or the
database, depending on whether or not it exists. The following named parameters
can alter the default behavior:

=over

=item * force_session

Don't use the query's id value (which is then used to pull the object
from the database) but just look for the object in the session. Dies if
the object is not in the session.

=item * force_query

Don't use the object in the session, but instead use the query's id
value and pull the object from the database. Dies if there is no query
id or the object doesn't exist in the database.

=item * no_save

If we need to pull the item from the database, don't then save it to
the session just return the object.

=back

=cut 

sub get_edit_object {
    my ($self, %options) = @_;
    my $pkg     = $self->edit_object_package;
    my $id_meth = $pkg->id_meth;

    # is the request asking for a specific object by id? If not, get whats in the session
    if ((my $id = $self->query->param($id_meth)) && !$options{force_session}) {
        debug("Pulling object from query $id_meth $id");
        my ($obj) = $pkg->find($id_meth => $id);
        if ($obj) {
            unless ($options{no_save}) {
                # now save this obj to the session
                my $new_edit_uuid = pkg('UUID')->new();
                $self->edit_uuid($new_edit_uuid);
                $session{$pkg}{$new_edit_uuid} = $obj;
            }
            return $obj;
        } else {
            croak("No $pkg object found in DB with $id_meth $id!");
        }
    } else {
        # we just want something from the query, not the session
        return if $options{force_query};
        if (my $edit_uuid = $self->edit_uuid) {
            debug("Pulling $pkg obj from session edit_uuid $edit_uuid");
            my $obj = $session{$pkg}{$edit_uuid};
            if ($obj) {
                return $obj;
            } else {
                croak("Could not load $pkg obj with edit_uuid $edit_uuid from session!");
            }
        } else {
            croak("No edit_uuid provided!");
        }
    }
}

=head3 set_edit_object

=cut

sub set_edit_object {
    my ($self, $obj) = @_;
    my $pkg       = $self->edit_object_package;
    my $edit_uuid = pkg('UUID')->new;
    $self->edit_uuid($edit_uuid);
    $session{$pkg}{$edit_uuid} = $obj;
}

=head3 clear_edit_object

=cut

sub clear_edit_object {
    my $self    = shift;
    my $pkg     = $self->edit_object_package;
    my $id_meth = $pkg->id_meth;

    # remove it from the session
    if (my $edit_uuid = $self->edit_uuid) {
        delete $session{$pkg}{$edit_uuid};
    }

    # and the query object
    $self->query->delete($id_meth);
}

=head3 edit_object_id

Get the id of the object being editted. This is useful when you just
need the id but don't want to create a full blown object just to get it.

=cut

sub edit_object_id {
    my $self    = shift;
    my $pkg     = $self->edit_object_package;
    my $id_meth = $pkg->id_meth;

    # If the query has an id use that first
    if (my $id = $self->query->param($id_meth)) {
        return $id;
    } else {
        if (my $edit_uuid = $self->edit_uuid) {
            my $obj = $session{$pkg}{$edit_uuid};
            if ($obj) {
                return $obj->$id_meth;
            } else {
                croak("Could not load $pkg object with edit_uuid $edit_uuid from session!");
            }
        } else {
            croak("No edit_uuid provided!");
        }
    }
}

=head3 edit_uuid

Get or set the UUID for the current edit. This is how we track which
object we are currently editting. Each incoming request that needs to
edit the object must pass the C<edit_uuid> value in the query string.

=cut

sub edit_uuid {
    my $self = shift;
    if ($_[0]) {
        # we are setting the edit_uuid
        $self->param(__edit_uuid => $_[0]);
        return $_[0];
    } else {
        if ($self->param('__edit_uuid')) {
            return $self->param('__edit_uuid');
        } else {
            my $edit_uuid = $self->query->param('edit_uuid');
            $self->param(__edit_uuid => $edit_uuid);
            return $edit_uuid;
        }
    }
}

=head2 OVERRIDES

In addition to the methods above we override the following methods:

=head3 load_tmpl

We overload C<load_tmpl()> so that C<edit_uuid> is always set if it
exists in the template.

=cut

sub load_tmpl {
    my $self = shift;
    my $tmpl = $self->SUPER::load_tmpl(@_);
    if (my $edit_uuid = $self->edit_uuid) {
        $tmpl->param(edit_uuid => $edit_uuid) if $tmpl->query(name => 'edit_uuid');
    }
    return $tmpl;
}

1;
