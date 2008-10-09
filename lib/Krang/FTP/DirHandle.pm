package Krang::FTP::DirHandle;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;
use Krang::ClassLoader DB => qw(dbh);
use Krang::ClassLoader 'Conf';
use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader 'Category';
use Krang::ClassLoader 'Template';
use Krang::ClassLoader 'Media';
use Krang::ClassLoader Log => qw(debug info critical);
use Net::FTPServer::DirHandle;
use Krang::ClassLoader 'FTP::FileHandle';
use Krang::ClassLoader 'Pref';
use Krang::ClassLoader 'Group';
use Krang::ClassLoader 'User';

# Inheritance
our @ISA = qw(Net::FTPServer::DirHandle);

=head1 NAME

    pkg('FTP::DirHandle') - Virtual FTP Server DirHandle

=head1 SYNOPSIS

=head1 DESCRIPTION

This module provides a directory handle object for use by
Krang::FTP::Server.

=head1 INTERFACE

This module inherits from Net::FTPServer::DirHandle and overrides the
required methods.  This class is used internally by Krang::FTP::Server.

=head2 METHODS

=over

=item Krang::FTP::DirHandle->new($ftps, [$pathname, $instance, $type, $category_id])

Creates a new Krang::FTP::DirHandle object.  Requires a Krang::FTP::Server
object as its first parameter.  Optionally takes a pathname, instance, type,  
and category_id. Type must correspond with media or template. If not supplied the pathname defaults to "/".

=cut

sub new {
    my $class       = shift;
    my $ftps        = shift;          # FTP server object.
    my $pathname    = shift || "/";
    my $instance    = shift;
    my $type        = shift;
    my $category_id = shift;

    # create object
    my $self = Net::FTPServer::DirHandle->new($ftps, $pathname);
    bless $self, $class;

    # set category id, default to dummy value.
    $self->{category_id} = $category_id;

    # set instance
    $self->{instance} = $instance;

    # set type
    $self->{type} = $type;

    return $self;
}

=item $dirhandle->get($filename)

The get() method is used to do a lookup on a specific filename.  If a
template or media object called $filename exists in this category then 
get() will call Krang::FTP::FileHandle->new() and return the object. 
If a category exists underneath this category called $filename then new()
will be called and the directory handle will be returned.  Failing
that, undef is returned.

=cut

sub get {
    my $self        = shift;
    my $filename    = shift;
    my $category_id = $self->{category_id};
    my $type        = $self->{type} || '';
    my $instance    = $self->{instance};

    if (not $instance) {
        foreach my $inst (@{$self->{ftps}{auth_instances}}) {
            if ($filename eq $inst) {
                pkg('Conf')->instance($inst);
                my $session_id = pkg('Session')->create();
                my $user_id    = ${$self->{ftps}{user_objects}}{$inst}->user_id;
                $self->{ftps}{user_obj} = ${$self->{ftps}{user_objects}}{$inst};
                $ENV{REMOTE_USER} = $user_id;

                # arrange for it to be deleted at process end
                eval "END { pkg('Session')->delete() }";

                return pkg('FTP::DirHandle')
                  ->new($self->{ftps}, $self->pathname . $filename . "/", $filename);
            }
        }

        # return undef if filname doesn't match a authorized instance
        return undef;

    } elsif ($type) {
        if ($type eq 'media') {

            # look for media with name = $filename in spec'd cat
            my @media = pkg('Media')->find(
                filename    => $filename,
                category_id => $category_id,
                may_see     => 1
            );

            if (@media) {
                return pkg('FTP::FileHandle')->new($self->{ftps}, $media[0], $type, $category_id);
            }
        } elsif ($type eq 'template') {

            # look for template with name = $filename in spec'd cat
            my $cid = $category_id || undef;
            my @template = pkg('Template')->find(
                filename    => $filename,
                category_id => $cid,
                may_see     => 1
            );

            if (@template) {
                return pkg('FTP::FileHandle')
                  ->new($self->{ftps}, $template[0], $type, $category_id);
            }
        }
    } elsif ((not $type) && (($filename eq 'template') || ($filename eq 'media'))) {

        # $type is not defined, and they are asking for template or media
        # they want to see sites (top level cats) under template or media
        $type = $filename;
        return pkg('FTP::DirHandle')
          ->new($self->{ftps}, $self->pathname . $filename . "/", $instance, $type, $category_id);
    }

    if (not $category_id) {
        my @categories = pkg('Category')->find(
            url     => $filename . '/',
            may_see => 1
        );

        return pkg('FTP::DirHandle')->new(
            $self->{ftps}, $self->pathname . $filename . "/",
            $instance, $type, $categories[0]->category_id,
        ) if $categories[0];
    } else {
        my @categories = pkg('Category')->find(
            dir       => $filename,
            parent_id => $category_id,
            may_see   => 1
        );
        return pkg('FTP::DirHandle')->new(
            $self->{ftps}, $self->pathname . $filename . "/",
            $instance, $type, $categories[0]->category_id,
        ) if $categories[0];
    }

    # if no matching media/template or dir
    return undef;
}

=item open($filename, $mode)

This method is called to open a file in the current directory.  
The possible modes are 'r', 'w' and 'a'. Same as get since we are 
not supporting new files here.
The method returns a Krang::FTP::FileHandle or undef on failure.

=cut

sub open {
    my $self        = shift;
    my $filename    = shift;
    my $mode        = shift;
    my $category_id = $self->{category_id};
    my $type        = $self->{type};
    my $instance    = $self->{instance};

    # get file extension
    my ($name, $file_type) = split(/\./, $filename);

    debug(__PACKAGE__ . "::open($filename, $mode)\n");

    if ((not $instance) || (($type eq 'media') and (not $category_id))) {
        return undef;
    }

    if ($type eq 'media') {

        # look for media with name = $filename in spec'd cat
        my @media = pkg('Media')->find(
            filename    => $filename,
            category_id => $category_id,
        );

        if ($media[0]) {
            return undef if not $media[0]->may_edit;

            return pkg('FTP::FileHandle')->new($self->{ftps}, $media[0], $type, $category_id)
              ->open($mode);
        } else {
            my %media_type = pkg('Pref')->get('media_type');
            my @media_type = keys %media_type;

            my $new_m = pkg('Media')->new(
                filename      => $filename,
                title         => $filename,
                category_id   => $category_id,
                media_type_id => $media_type[0]
            );

            return pkg('FTP::FileHandle')->new($self->{ftps}, $new_m, $type, $category_id)
              ->open($mode);
        }
    } elsif ($type eq 'template') {
        if ($file_type eq 'tmpl') {

            # look for template with name = $filename in spec'd cat
            my @template = pkg('Template')->find(
                filename    => $filename,
                category_id => $category_id,
            );

            if ($template[0]) {
                return undef if not $template[0]->may_edit;

                return pkg('FTP::FileHandle')->new($self->{ftps}, $template[0], $type, $category_id)
                  ->open($mode);
            } else {    # else this must be a new template, create it
                my $new_t = pkg('Template')->new(
                    category_id => $category_id,
                    filename    => $filename,
                    content     => '',
                );

                return pkg('FTP::FileHandle')->new($self->{ftps}, $new_t, $type, $category_id)
                  ->open($mode);
            }
        }
    }

    return undef;
}

=item list($wildcard)

The list() method is called to do a wildcard search inside a
directory.  The method performs a search for categories and media/templates
matching the specified wildcard.  The return value is a reference to
an array of two-element arrays - the first element is the name and the
second is the corresponding FileHandle or DirHandle object.  The
results are sorted by names before being returned.  If nothing matches
the wildcard then a reference to an empty array is returned.

=cut

sub list {
    my $self        = shift;
    my $wildcard    = shift;
    my $category_id = $self->{category_id};
    my $instance    = $self->{instance};
    my $type        = $self->{type};
    my $ftps        = $self->{ftps};

    my @results;

    # translate wildcard to like
    my $like;
    if ($wildcard and $wildcard ne '*') {
        $like = $ftps->wildcard_to_sql_like($wildcard);
    }
    $like = '%' if not $like;

    if (not $instance) {

        foreach my $inst (@{$self->{ftps}{auth_instances}}) {
            push @results, [$inst, pkg('FTP::DirHandle')->new($self->{ftps}, "/$inst", $inst)];
        }
        return \@results;

    } elsif (not $type) {    # if no $type, return 'media' and 'template'
        my %asset_perms = pkg('Group')->user_asset_permissions();
        push(@results,
            ['media', pkg('FTP::DirHandle')->new($self->{ftps}, "/$instance/media", 'media')])
          if ($asset_perms{media} ne 'hide');
        push(
            @results,
            [
                'template',
                pkg('FTP::DirHandle')->new($self->{ftps}, "/$instance/template", 'template')
            ]
        ) if ($asset_perms{template} ne 'hide');
        return \@results;

    } elsif (not $category_id) {    # if category not defined, return top level cats
        my @categories =
          pkg('Category')
          ->find(url_like => $like, order_by => 'url', parent_id => undef, may_see => 1);

        foreach my $cat (@categories) {
            my $dirh = pkg('FTP::DirHandle')->new($self->{ftps}, "/$instance/$type/" . $cat->url(),
                $instance, $type, $cat->category_id());
            my $url = $cat->url;
            chop $url;
            push @results, [$url, $dirh];
        }

        if ($type eq 'template') {
            my %asset_perms = pkg('Group')->user_asset_permissions();

            unless ($asset_perms{template} eq 'hide') {
                my @template = pkg('Template')->find(
                    filename_like => $like,
                    category_id   => undef,
                    may_see       => 1,
                    order_by      => 'filename',
                );
                foreach my $template (@template) {
                    my $fileh =
                      pkg('FTP::FileHandle')->new($self->{ftps}, $template, $type, $category_id);
                    push @results, [$template->filename, $fileh];
                }
            }
        }

        return \@results;
    }

    # get subdirectories.
    my @categories = pkg('Category')->find(parent_id => $category_id, may_see => 1);

    # create dirhandles
    foreach my $cat (@categories) {
        my $dirh = pkg('FTP::DirHandle')->new($self->{ftps}, $self->pathname . "/" . $cat->dir,
            $instance, $type, $cat->category_id);
        push @results, [$cat->dir, $dirh];
    }

    if ($category_id) {

        # get templates or media
        if ($type eq 'media') {
            my @media = pkg('Media')->find(
                filename_like => $like,
                category_id   => $category_id,
                may_see       => 1
            );
            foreach my $media (@media) {
                my $fileh = pkg('FTP::FileHandle')->new($self->{ftps}, $media, $type, $category_id);
                push @results, [$media->filename, $fileh];
            }
        } else {
            my @template = pkg('Template')->find(
                filename_like => $like,
                category_id   => $category_id,
                may_see       => 1
            );
            foreach my $template (@template) {
                my $fileh =
                  pkg('FTP::FileHandle')->new($self->{ftps}, $template, $type, $category_id);
                push @results, [$template->filename, $fileh];
            }
        }
    }

    return \@results;
}

=item list_status($wildcard)

This method performs the same as list() but also adds a third element
to each returned array - the results of calling the status() method on
the object.  See the status() method below for details.

=cut

sub list_status {
    my $self     = shift;
    my $wildcard = shift;

    my $list = $self->list($wildcard);
    foreach my $row (@$list) {
        $row->[3] = [$row->[1]->status];
    }

    return $list;
}

=item parent()

Returns the Krang::FTP::DirHandle object for the parent of this directory.
For the root dir it returns itself.

=cut

sub parent {
    my $self        = shift;
    my $category_id = $self->{category_id};
    my $type        = $self->{type};
    my $instance    = $self->{instance};
    my $dirh;

    return $self if $self->is_root;

    $dirh = $self->SUPER::parent;

    if ($category_id) {

        $dirh->{type}     = $type;
        $dirh->{instance} = $instance;

        # get parent category_id for category
        my @cats;
        @cats = pkg('Category')->find(category_id => $category_id, may_see => 1);

        if ($cats[0]) {
            if (my $parent_cat = $cats[0]->parent) {

                # get a new directory handle and change category_id to parent's
                $dirh->{category_id} = $parent_cat->category_id();
            } else {
                $dirh->{category_id} = undef;
            }
        }
    } elsif ($type) {
        $dirh->{type}     = '';
        $dirh->{instance} = $instance;
    }

    return bless $dirh, ref $self;
}

=item status()

This method returns information about the object.  The return value is
a list with seven elements - ($mode, $perms, $nlink, $user, $group,
$size, $time).  To quote the good book (Net::FTPServer::Handle):

          $mode     Mode        'd' = directory,
                                'f' = file,
                                and others as with
                                the find(1) -type option.
          $perms    Permissions Permissions in normal octal numeric format.
          $nlink    Link count
          $user     Username    In printable format.
          $group    Group name  In printable format.
          $size     Size        File size in bytes.
          $time     Time        Time (usually mtime) in Unix time_t format.

In this case all of these values are fixed for all categories: ( 'd',
0777, 1, "nobody", "", 0, 0 ).

=cut

sub status {
    my $self        = shift;
    my $category_id = $self->{category_id} || '';
    my $type        = $self->{type} || '';
    my $instance    = $self->{instance} || '';

    debug(__PACKAGE__
          . "::status() : instance = $instance  : type = $type : category = $category_id \n");

    return ('d', 0777, 2, "nobody", "nobody", 0, 0);
}

=item move()

Renames a category (the analog of a directory). This method will fail
and return -1 if the user doesn't have admin permission to manage 
categories via FTP, or if a category with the same name already exists.

=cut

sub move {
    my ($self, $dirh, $new_dir) = @_;

    # Get user login for logging purposes
    my ($user) = pkg('User')->find(user_id => $ENV{REMOTE_USER});
    my $login = $user->login;

    # Die if user doesn't have permission
    if (!$self->_can_manage_categories_via_ftp()) {
        $self->{error} =
          "User $login does not have admin permission to managed categories via FTP.";
        warn(__PACKAGE__ . "::move() - ERROR: " . $self->{error});
        return -1;
    }

    # Get current category object so we can modify it
    my $category_id = $self->{category_id};
    my ($curr_category) = Krang::Category->find(category_id => $category_id);

    # Create new url from current one.
    # Replace bar in /foo/bar/ with new_dir to get /foo/new_dir/.
    my $new_url = $curr_category->url;
    $new_url =~ s/[^\/]+\/$//;
    $new_url .= $new_dir . '/';

    # Find dupes
    my $dup_category;
    if (($dup_category) = Krang::Category->find(url => $new_url)) {
        $self->{error} =
            "User $login failed to rename category '"
          . $curr_category->url
          . "' to duplicate category '$new_url'";
        warn(__PACKAGE__ . "::move() - ERROR: " . $self->{error});
        return -1;
    }

    # Set current category's dir property to new directory name
    my $old_cat = $curr_category->url;    # save for logging
    $curr_category->{dir} = $new_dir;

    # Try to save current category and bomb on failure
    eval { $curr_category->save() };
    if ($@) {

        # bomb on any exceptions
        warn(__PACKAGE__ . "::move() - ERROR: $@");
        $self->{error} = $@;
        return -1;
    }

    info(   __PACKAGE__
          . "::move() - User $login renamed category '$old_cat' to '"
          . $curr_category->url
          . "'");
    return 1;
}

=item delete()

Deletes a category (the analog of a directory). Will fail and return -1 
if the user does not have admin privileges for category management via 
FTP, or if the category deletion or save throws an exception.

=cut

sub delete {
    my $self = shift;

    # Get user login for logging purposes
    my ($user) = pkg('User')->find(user_id => $ENV{REMOTE_USER});
    my $login = $user->login;

    # Die if user doesn't have permission
    if (!$self->_can_manage_categories_via_ftp()) {
        $self->{error} =
          "User $login does not have admin permission to managed categories via FTP.";
        warn(__PACKAGE__ . "::delete() - ERROR: " . $self->{error});
        return -1;
    }

    my $category_id = $self->{category_id};    # Get category object to delete it

    # We need this category object to log deletes
    my ($curr_category) = Krang::Category->find(category_id => $category_id);

    # Attempt to delete category, catch exceptions
    eval { $curr_category->delete() };

    # User can't delete root categories via FTP
    if ($@ and ref $@ and $@->isa('Krang::Category::RootDeletion')) {
        $self->{error} =
            "User $login failed to delete category "
          . $curr_category->url
          . " because it's a root category. Root categories cannot be deleted via FTP.";
        warn(__PACKAGE__ . "::delete() - ERROR: " . $self->{error});
        return -1;
    }

    # This category has dependents and can't be deleted
    elsif ($@ and ref $@ and $@->isa('Krang::Category::Dependent')) {
        my $dep = $@->dependents;
        $self->{error} =
            "User $login failed to delete category "
          . $curr_category->url
          . " because it has dependents. .";
        warn(__PACKAGE__ . "::delete() - ERROR: " . $self->{error});
        return -1;
    }

    # Unknown exception. Fatal.
    elsif ($@) {
        $self->{error} = "Unknown exception '$@' while attempting to delete category '"
          . $curr_category->url . "': $@";
        warn(__PACKAGE__ . "::delete() - ERROR: " . $self->{error});
        return -1;
    }

    info(__PACKAGE__ . "::delete() - User $login deleted category '" . $curr_category->url . "'");

    return 1;
}

=item mkdir()

Creates a category (the analog of a directory) within the current 
category. Will fail and return -1 if the user does not have admin 
privileges for category management via FTP, or if the category 
creation or save fails.

=cut

sub mkdir {
    my ($self, $dirname) = @_;

    # Get user login for logging purposes
    my ($user) = pkg('User')->find(user_id => $ENV{REMOTE_USER});
    my $login = $user->login;

    # Die if user doesn't have permission
    if (!$self->_can_manage_categories_via_ftp()) {
        $self->{error} =
          "User $login does not have admin permission to managed categories via FTP.";
        warn(__PACKAGE__ . "::mkdir() - ERROR: " . $self->{error});
        return -1;
    }

    my $category_id = $self->{category_id};    # We'll need this to create a child cat

    # We need this category object to log duplicates and creates
    my ($curr_category) = Krang::Category->find(category_id => $category_id);

    # Create new category and bomb if that fails.
    my $new_category;
    eval { $new_category = Krang::Category->new(parent_id => $category_id, dir => $dirname) };

    if ($@ and ref($@) and $@->isa('Krang::Category::NoEditAccess')) {
        warn(__PACKAGE__
              . "::mkdir - ERROR: User $login not allowed to add category to category '$category_id'"
        );
        $self->{error} = $@;
        return -1;
    } elsif ($@) {
        warn(__PACKAGE__ . "::mkdir() - ERROR: $@");
        $self->{error} = $@;
        return -1;
    }    # bomb on any exceptions

    # Save the new category and bomb if that fails.
    eval { $new_category->save(); };

    if ($@ and ref($@) and $@->isa('Krang::Category::DuplicateURL')) {
        warn(__PACKAGE__ . "::mkdir() - ERROR: Duplicate url '" . $curr_category->url . "'");
        $self->{error} = $@;
        return -1;
    } elsif ($@) {
        warn(__PACKAGE__ . "::mkdir() - ERROR: $@");
        $self->{error} = $@;
        return -1;
    }    # bomb on any exceptions

    info(__PACKAGE__ . "::mkdir() - User $login created category '" . $new_category->url . "'");

    return 1;
}

=item can_*()

Returns permissions information for various activites.  can_write(),
can_enter() and can_list() all return true since these operations are
supported on all categories.  can_delete, can_rename() and can_mkdir() 
return true, and are supported, but return -1 if access is denied or if the 
operation fails.

=cut

sub can_write  { 1; }
sub can_delete { 1; }
sub can_enter  { 1; }
sub can_list   { 1; }
sub can_rename { 1; }
sub can_mkdir  { 1; }

=item _can_manage_categories_via_ftp()

Returns true if user has admin permissions to manage categories via 
FTP.  This permission applies to the mkdir() and move() operations.

=cut

sub _can_manage_categories_via_ftp {
    my $self                     = shift;
    my %admin_perms              = pkg('Group')->user_admin_permissions();
    my $can_admin_categories     = $admin_perms{'admin_categories'} || 0;
    my $can_admin_categories_ftp = $admin_perms{'admin_categories_ftp'} || 0;
    return ($can_admin_categories && $can_admin_categories_ftp);
}

=back

=head1 SEE ALSO

Net:FTPServer::DirHandle

L<Krang::FTP::Server>

L<Krang::FTP::FileHandle>

=cut 

sub dir { return shift }

1;
