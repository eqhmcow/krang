package Krang::Workspace;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader DB      => qw(dbh);
use Krang::ClassLoader Log     => qw(debug);
use Krang::ClassLoader 'Story';
use Krang::ClassLoader 'Media';
use Krang::ClassLoader 'Template';

=head1 NAME

Krang::Workspace - data broker for My Workspace CGI

=head1 SYNOPSIS

  use Krang::ClassLoader 'Workspace';

  # get a list of objects on the current user's workspace
  @objects = pkg('Workspace')->find();

  # get just the first 10, sorting by url:
  @objects = pkg('Workspace')->find(limit    => 10,
                                    offset   => 0,
                                    order_by => 'url');

=head1 DESCRIPTION

This module provides a find() method which returns all objects
checked-out to a particular user.

=head1 INTERFACE

=over

=item C<< @objects = Krang::Workspace->find() >>

=item C<< $count = Krang::Workspace->find(count => 1) >>

Finds stories, media and templates checked out to a particular user
(the currently logged in user by default).  The returned array will
contain Krang::Story, Krang::Media and Krang::Template objects.

Since the returned objects do not share single ID-space, the standard
C<ids_only> mode is not supported.

Available search options are:

=over

=item user_id

Find items on a particular user's workspace.  This defaults to the
currently logged in user if not set.

=back

Options affecting the search and the results returned:

=over

=item count

Return just a count of the results for this query.

=item limit

Return no more than this many results.

=item offset

Start return results at this offset into the result set.

=item order_by

Output field to sort by.  Defaults to 'type' which sorts stories
first, then media and finally templates.  Other available settings are
'date', 'title', 'url' and 'id'.

=item order_desc

Results will be in sorted in ascending order unless this is set to 1
(making them descending).

=back

=cut

sub find {
    my $pkg  = shift;
    my %args = @_;
    my $dbh  = dbh();

    # get search parameters out of args, leaving just field specifiers
    my $order_by   = delete $args{order_by}   || 'type';
    my $order_desc = delete $args{order_desc} || 0;
    my $limit      = delete $args{limit}      || 0;
    my $offset     = delete $args{offset}     || 0;
    my $count      = delete $args{count}      || 0;

    # an order_by of type really means type,class,id.  Go figure.
    $order_by = 'type,class,id' if $order_by eq 'type';

    # default secondary order_by to ID
    $order_by .= ",id" unless $order_by eq 'id' or $order_by =~ /,/;

    # use logged in user_id unless user_id passed in
    my $user_id = $args{user_id} ? $args{user_id} : $ENV{REMOTE_USER};
    my @param = ($user_id) x 3;

    # FIX: this code could be smarter about which fields to SELECT
    # based on the needed order_by

    # construct query
    my $query = <<SQL;
(SELECT s.story_id AS id,
        1 AS type,
        sc.url, 
        s.cover_date as date,
        s.title AS title,
        class
 FROM story AS s LEFT JOIN story_category AS sc USING (story_id) 
 WHERE s.checked_out_by = ? AND sc.ord = 0 AND s.retired = 0 AND s.trashed = 0)

UNION 

(SELECT media_id AS id, 
        2 AS type,
        url, 
        creation_date AS date, 
        title,
        '' as class
 FROM media AS m
 WHERE checked_out_by = ? AND m.retired = 0 AND m.trashed = 0)

UNION 

(SELECT template_id AS id, 
        3 as type,
        url,
        creation_date AS date,
        filename AS title,
        '' as class
 FROM template
 WHERE checked_out_by = ?)
SQL

    # mix in order_by
    $query .= " ORDER BY $order_by " if $order_by && !$count;

    # add LIMIT clause, if any
    if ($limit) {
        $query .= $offset ? " LIMIT $offset, $limit" : " LIMIT $limit";
    } elsif ($offset) {
        $query .= " LIMIT $offset, 18446744073709551615";
    }

    debug(__PACKAGE__ . "::find() SQL: " . $query);
    debug(__PACKAGE__ . "::find() SQL ARGS: " . join(', ', @param));

    # execute the search
    my $sth = $dbh->prepare($query);
    $sth->execute(@param);

    # return just a count if requested
    if ($count) {
        my $results = $sth->fetchall_arrayref;
        $sth->finish;
        return scalar @$results;
    }

    # get results
    my $results = $sth->fetchall_arrayref();
    $sth->finish;

    # build lists of IDs for each class to load
    my (@story_ids, @media_ids, @template_ids);
    foreach my $row (@$results) {
        my ($id, $type) = @$row;
        if ($type == 1) {
            push @story_ids, $id;
        } elsif ($type == 2) {
            push @media_ids, $id;
        } else {
            push @template_ids, $id;
        }
    }

    # load stories
    my %stories;
    if (@story_ids) {
        %stories = map { ($_->story_id, $_) } pkg('Story')->find(story_id => \@story_ids);
    }

    # load media
    my %media;
    if (@media_ids) {
        %media = map { ($_->media_id, $_) } pkg('Media')->find(media_id => \@media_ids);
    }

    # load template
    my %templates;
    if (@template_ids) {
        %templates =
          map { ($_->template_id, $_) } pkg('Template')->find(template_id => \@template_ids);
    }

    # collate results in order
    my @objects;
    foreach my $row (@$results) {
        my ($id, $type) = @$row;
        if ($type == 1) {
            push @objects, $stories{$id};
        } elsif ($type == 2) {
            push @objects, $media{$id};
        } else {
            push @objects, $templates{$id};
        }
    }

    return $order_desc ? reverse @objects : @objects;
}

1;

=back

=cut 

