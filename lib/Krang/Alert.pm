package Krang::Alert;
use strict;
use warnings;
use Krang::DB qw(dbh);
use Krang::Session qw(%session);
use Krang::Log qw( debug info );
use Krang::Schedule;
use Krang::User;
use Krang::Story;
use Krang::Category;
use Krang::Conf qw(SMTPServer FromAddress KrangRoot);
use Carp qw(croak);
use Time::Piece;
use Time::Piece::MySQL;
use Mail::Sender;
use HTML::Template;
use File::Spec::Functions qw(catfile);

# constants 
use constant FIELDS => qw( alert_id user_id action desk_id category_id );
use constant ACTIONS => qw( new save checkin checkout publish move );

=head1 NAME

    Krang::Alert -  interface to specify Krang::Story events to alert upon, 
                    schedule alerts, and mail out alerts.

=head1 SYNOPSIS

    use Krang::Alert;
    
    # add new alert scenario - user 1 will be notified when any new stary is 
    # created in category 3 (or its descendants)
    my $alert = Krang::Alert->new(  user_id => '1',
                                    action => 'new',
                                    category_id => '3' ); 

    # save the alert
    $alert->save;

    # add new alert scenario - user 1 will be notified when any story is
    # moved to desk 4
    my $alert2 = Krang::Alert->new( user_id => '1',
                                    action => 'move',
                                    desk_id => '4' );

    # save the alert
    $alert2->save;

    # Let's pretend that category 5 is a decendant of category 3.
    # This find should return the $alert object from the above example. 
    my @found = Krang::Alert->find( user_id => '1',
                                    action => 'new',
                                    category_id => '5' ); 

    # check to see if history event should trigger an alert
    # for specified object.  If a match is found, an alert 
    # will be scheduled to be mailed with Krang::Schedule
    # This is a convenience method that uses Krang::Alert->find() 
    # and Krang::Schedule->new()
    Krang::Alert->check_alert(  history_object => $history_object,  
                                story_object => $story_object );
    
    # delete alert scenario
    $alert->delete();

=head1 DESCRIPTION

This class handles the storage of Krang::Story events to alert upon. It also checks Krang::History objects to see if an alert is matched.  If so, an alert mailing ( Krang::Alert->send() ) will be scheduled in Krang::Schedule. 

=head1 INTERFACE

=head2 METHODS

=over 

=item new()

This adds a new scenario to alert upon.  

Supports the following name-value pairs:

=over

=item * 

user_id

=item * 

action - one of ( new save checkin checkout publish move )

=item *

category_id

=item * 

desk_id

=back

=cut

use Krang::MethodMaker
    new_with_init => 'new',
    new_hash_init => 'hash_init',
    get_set       => [ FIELDS ];

sub init {
    my $self = shift;
    my %args = @_;

    # finish the object
    $self->hash_init(%args);

    return $self;
}

=item save()

Saves (inserts) alert scenario to the database, or updates scenario if already exists.

=cut

sub save {
    my $self = shift;
    my $dbh = dbh;
    my $alert_id;

    # if this is not a new alert
    if (defined $self->{alert_id}) {
        $alert_id = $self->{alert_id};
        
        # get rid of alert_id 
        my @save_fields = grep {$_ ne 'alert_id'} FIELDS;

        my $sql = 'UPDATE alert set '.join(', ',map { "$_ = ?" } @save_fields).' WHERE alert_id = = ?';
        $dbh->do($sql, undef, (map { $self->{$_} } @save_fields),$alert_id);

    } else {
        my $sql = 'INSERT INTO alert ('.join(',', FIELDS).') VALUES (?'.",?" x (scalar FIELDS - 1).")";
        debug(__PACKAGE__."->save() - $sql");
        
        $dbh->do($sql, undef, map { $self->{$_} } FIELDS);
        
        $self->{alert_id} = $dbh->{mysql_insertid};
    }
}

=item find()

Find and return alert objects with parameters specified.

Supported keys:

=over 4

=item *

alert_id

=item *

user_id

=item *

action

=item *

desk_id

=item *

category_id - will traverse the tree looking and also look for parent categories. an arrayref of category ids can be passed in as well.

=item *

order_by - field to order search by, defaults to alert_id

=item *

order_desc - results will be in ascending order unless this is set to 1 (making them descending).

=item *

limit - limits result to number passed in here, else no limit.

=item *

offset - offset results by this number, else no offset.

=item *

count - return only a count if this is set to true.

=item *

ids_only - return only alert_ids, not objects if this is set true.

=back

=cut

sub find {
    my $self = shift;
    my %args = @_;
    my $dbh = dbh;

    my @where;
    my @alert_object;

    my %valid_params = ( alert_id => 1,
                         user_id => 1,
                         action => 1,
                         desk_id => 1,
                         category_id => 1,
                         order_by => 1,
                         order_desc => 1,
                         limit => 1,
                         offset => 1,
                         count => 1,
                         ids_only => 1 );

    # check for invalid params and croak if one is found
    foreach my $param (keys %args) {
        croak (__PACKAGE__."->find() - Invalid parameter '$param' called.") if
not $valid_params{$param};
    }

    # check for invalid argument sets
    croak(__PACKAGE__ . "->find(): 'count' and 'ids_only' were supplied. " .
          "Only one can be present.")
      if $args{count} and $args{ids_only};

    # set defaults if need be
    my $order_by =  $args{'order_by'} ? $args{'order_by'} : 'alert_id';
    my $order_desc = $args{'order_desc'} ? 'desc' : 'asc';
    my $limit = $args{'limit'} ? $args{'limit'} : undef;
    my $offset = $args{'offset'} ? $args{'offset'} : 0;
    
    # set simple keys
    foreach my $key (keys %args) {
        if ( ($key eq 'alert_id') || ($key eq 'user_id') || ($key eq 'action') || ($key eq 'desk_id') ) {   
            push @where, $key;
        }
    }

    my $where_string = join ' and ', (map { "$_ = ? " } @where);

    if ($args{'category_id'}) {

        if (ref($args{'category_id'}) eq 'ARRAY') {
            my @all_cat_ids;
            my $cat_ids = $args{'category_id'};
            foreach my $cat_id ( @$cat_ids ) {
                my @cat = Krang::Category->find( category_id => $cat_id);
                my @ancestors = $cat[0]->ancestors( ids_only => 1 );
                
                push @all_cat_ids, @ancestors;
            }
            
            push @all_cat_ids, @$cat_ids;

            $where_string ? ($where_string .= 'AND ('.(join ' OR ', (map { "category_id = $_"} @all_cat_ids)).')') : ($where_string = '('.(join ' OR ', (map { "category_id = $_"} @all_cat_ids)).')');
        } else {
            $where_string ? ($where_string .= 'AND category_id = '.$args{'category_id'}) : ($where_string = 'category_id = '.$args{'category_id'});
        }
    }

    my $select_string;
    if ($args{'count'}) {
        $select_string = 'count(*) as count';
    } elsif ($args{'ids_only'}) {
        $select_string = 'alert_id';
    } else {
        $select_string = join(',', FIELDS);
    }

    my $sql = "select $select_string from alert";
    $sql .= " where ".$where_string if $where_string;
    $sql .= " order by $order_by $order_desc";

    # add limit and/or offset if defined 
    if ($limit) {
       $sql .= " limit $offset, $limit";
    } elsif ($offset) {
        $sql .= " limit $offset, -1";
    }

    debug(__PACKAGE__ . "->find() SQL: " . $sql);
    debug(__PACKAGE__ . "->find() SQL ARGS: " . join(', ', map { defined $args{$_} ? $args{$_} : 'undef' } @where));

    my $sth = $dbh->prepare($sql);
    $sth->execute(map { $args{$_} } @where) || croak("Unable to execute statement $sql");

    while (my $row = $sth->fetchrow_hashref()) {
        my $obj;
        if ($args{'count'}) {
            return $row->{count};
        } elsif ($args{'ids_only'}) {
            $obj = $row->{alert_id};
            push (@alert_object,$obj);
        } else {
            $obj = bless {%$row}, $self;

            push (@alert_object,$obj);
        }
    }
    $sth->finish();
    return @alert_object;

}

=item check_alert()

Check to see if given criteria matches a set user alert.

This method takes two arguments, a Krang::History object and a Krang::Story object. 

=cut 

sub check_alert {
    my $self = shift;

    my %args = @_;

    my $history = $args{history};
    my $action = $history->action;
    my $story = $args{story};

    my @cat_objects = $story->categories;
    my @category_ids = map { $_->category_id } @cat_objects;

    croak(__PACKAGE__."->check_alert requires a valid Krang::History object.") if (ref $history ne 'Krang::History');

    croak(__PACKAGE__."->check_alert requires a valid Krang::Story object.") if (ref $story ne 'Krang::Story');

    debug(__PACKAGE__."->check_alert() - checking for any alerts on action $action in categories @category_ids");
 
    my @matched_alerts = Krang::Alert->find( ids_only => 1, action => $action, category_id => \@category_ids );  

    debug(__PACKAGE__."->check_alert() - found alert_ids @matched_alerts for criteria (action $action in categories @category_ids).") if @matched_alerts;

    foreach my $alert_id ( @matched_alerts ) {
        my $time = localtime;
        my $schedule = Krang::Schedule->new(    object_type => 'alert',
                                                object_id => $alert_id,
                                                action => 'send',
                                                date => $time,
                                                repeat      => 'never',
                                                context     => [ user_id => $history->user_id, story_id => $story->story_id ]
                                            );   
        $schedule->save(); 
    }
}

=item Krang::Alert->send( alert_id => $alert_id, user_id => $user_id, story_id => $story_id )

Sends an alert to email address.  Message sent is formatted by template at KrangRoot/templates/Alert/message.tmpl

=cut 

sub send {
    my $self = shift;
    my %args = @_;
    
    my $alert_id = $args{alert_id} || croak(__PACKAGE__."->send() - you must specify an alert_id");
    my $user_id = $args{user_id} || croak(__PACKAGE__."->send() - you must specify a user_id");
    my $story_id = $args{story_id} || croak(__PACKAGE__."->send() - you must specify a story_id");

    my $alert = (Krang::Alert->find(alert_id => $alert_id))[0];
    
    croak("No valid Krang::Alert object found with id $alert_id") if not ( ref $alert eq 'Krang::Alert');

    my $to_user = (Krang::User->find( user_id => $alert->user_id ))[0];

    croak("No valid Krang::User object found with id ".$alert->user_id) if not ( ref $to_user eq 'Krang::User');

    my $user = (Krang::User->find( user_id => $user_id ))[0];

    croak("No valid Krang::User object found with id $user_id") if not ( ref $user eq 'Krang::User');

    my $story = (Krang::Story->find(story_id => $story_id))[0];

    croak("No valid Krang::Story object found with id $story_id") if not ( ref $story eq 'Krang::Story');

    my $template = HTML::Template->new(filename => catfile(KrangRoot, 'templates', 'Alert', 'message.tmpl'));

    $template->param(   story_id => $story_id, 
                        story_title => $story->title,
                        first_name => $user->first_name,
                        last_name => $user->last_name,
                        action => $alert->action );

    $template->param( category => (Krang::Category->find(category_id => $alert->category_id))[0]->url ) if $alert->category_id;

    $template->param( desk => (Krang::Desk->find(desk_id => $alert->desk_id))[0]->name ) if $alert->desk_id; 

    # mail only if user has email address defined or being tested
    my $email_to = $ENV{KRANG_TEST_EMAIL} || $to_user->email;
    if ($email_to) { 
        debug(__PACKAGE__."->send() - sending email to ".$email_to.": ".$template->output);
        my $sender = new Mail::Sender {smtp => SMTPServer, from => FromAddress};

        $sender->MailMsg({  to => $email_to, 
                            subject => "Krang alert for action '".$alert->action."'",
                            msg => $template->output,
                        }); 
    } else {
        info(__PACKAGE__."->send() - no email address found for user: alert not sent: ".$template->output);        
    }
    
}

=item delete()

=item Krang::Alert->delete( alert_id => $alert_id)

Deletes alert or alert with specified id.

=cut

sub delete {
    my $self = shift;
    my $alert_id = shift;
    my $dbh = dbh;

    $alert_id = $self->{alert_id} if (not $alert_id);

    croak("No alert_id specified for delete!") if not $alert_id;

    $dbh->do('DELETE from alert where alert_id = ?', undef, $alert_id);

    # delete schedule objects for this alert also
    $dbh->do('DELETE from schedule where object_type = ? and object_id = ?', undef, 'alert', $alert_id);

}

=back 

=cut

1;
 
