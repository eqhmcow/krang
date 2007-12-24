package Krang::CGI::Story;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader 'Story';
use Krang::ClassLoader 'ElementLibrary';
use Krang::ClassLoader Log => qw(debug assert ASSERT info);
use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader Message => qw(add_message add_alert clear_messages clear_alerts);
use Krang::ClassLoader Widget => qw(category_chooser datetime_chooser decode_datetime format_url autocomplete_values);
use Krang::ClassLoader 'CGI::Workspace';
use Carp qw(croak);
use Krang::ClassLoader 'Pref';
use Krang::ClassLoader 'HTMLPager';
use Krang::ClassLoader 'Group';
use Krang::ClassLoader Conf => qw(Charset);
use Krang::ClassLoader Localization => qw(localize);

use Krang::ClassLoader base => 'CGI::ElementEditor';

sub _get_element     { $session{story}->element; }
sub _get_script_name { "story.pl"; }

=head1 NAME

Krang::CGI::Story - web interface to manage stories

=head1 SYNOPSIS

  use Krang::ClassLoader 'CGI::Story';
  pkg('CGI::Story')->new()->run();

=head1 DESCRIPTION

=head1 INTERFACE

Following are descriptions of all the run-modes
provided by Krang::CGI::Story.

=head2 Run-Modes

=over 4

=cut

sub setup {
    my $self = shift;
    $self->SUPER::setup();
    $self->mode_param('rm');
    $self->start_mode('new_story');

    # add story specific modes to existing set
    $self->run_modes(
        new_story                     => 'new_story',
        create                        => 'create',
        edit                          => 'edit',
        checkout_and_edit             => 'checkout_and_edit',
        check_in_and_save             => 'check_in_and_save',
        view                          => 'view',
        revert                        => 'revert',
        find                          => 'find',
        list_active                   => 'list_active',
        cancel_create                 => 'cancel_create',
        cancel_edit                   => 'cancel_edit',
        delete                        => 'delete',
        delete_selected               => 'delete_selected',
        checkout_selected             => 'checkout_selected',
        checkin_selected              => 'checkin_selected',
        steal_selected                => 'steal_selected',
        delete_categories             => 'delete_categories',
        add_category                  => 'add_category',
        replace_category              => 'replace_category',
        set_primary_category          => 'set_primary_category',
        copy                          => 'copy',
        replace_dupes                 => 'replace_dupes',
        db_save                       => 'db_save',
        db_save_and_stay              => 'db_save_and_stay',
	preview_and_stay              => 'preview_and_stay',
        save_and_jump                 => 'save_and_jump',
        save_and_add                  => 'save_and_add',
        save_and_publish              => 'save_and_publish',
        save_and_view                 => 'save_and_view',
        save_and_view_log             => 'save_and_view_log',
        save_and_edit_contribs        => 'save_and_edit_contribs',
        save_and_edit_schedule        => 'save_and_edit_schedule',
        save_and_go_up                => 'save_and_go_up',
        save_and_bulk_edit            => 'save_and_bulk_edit',
        save_and_leave_bulk_edit      => 'save_and_leave_bulk_edit',
        save_and_change_bulk_edit_sep => 'save_and_change_bulk_edit_sep',
        save_and_find_story_link      => 'save_and_find_story_link',
        save_and_find_media_link      => 'save_and_find_media_link',
        autocomplete                  => 'autocomplete',
    );

    $self->tmpl_path('Story/');
}

=item new_story (default)

Allows the user to create a new story.  Users choose the type, title,
slug, site/category and cover date on this screen.  Requires no
parameters.  Produces a form which is submitted to the create runmode.

=cut

sub new_story {
    my $self = shift;
    my $query = $self->query;
    my $template = $self->load_tmpl('new.tmpl', associate => $query);
    my %args = @_;

    # setup error message if passed in
    if ($args{bad}) {
        $template->param("bad_$_" => 1) for @{$args{bad}}
    }


    # setup the type selector
    my @types = grep { $_ ne 'category' } pkg('ElementLibrary')->top_levels;
    # sort the type by their display name, not their real name
    @types = sort {
        lc pkg('ElementLibrary')->top_level( name => $a )->display_name
        cmp 
        lc pkg('ElementLibrary')->top_level( name => $b )->display_name
    } @types;

    my %type_labels = 
      map { ($_, pkg('ElementLibrary')->top_level(name => $_)->display_name) }
        @types;
    $template->param(type_selector => scalar
                     $query->popup_menu(-name      => 'type',
                                        -default   => '',
                                        -values    => [ ('', @types) ],
                                        -labels    => \%type_labels,
					-onkeyup   => 'javascript:show_slug_and_cat_by_type()',
					-onchange  => 'javascript:show_slug_and_cat_by_type()'));

    $template->param(category_chooser => scalar
                     category_chooser(name => 'category_id',
                                      formname => 'new_story',
                                      query => $query,
                                      may_edit => 1,
                                      persistkey => 'NEW_STORY_DIALOGUE'
                                     ));

    # setup date selector
    $template->param(cover_date_selector => datetime_chooser(name=>'cover_date', query=>$query));
    
    # pass template a loop of types and how they should affect display of slug/category input
    my $selected_type = $query->param('type') || ''; 
    my @slug_and_cat_entry_by_type;
    my ($slug_entry_for_selected_type, $cat_entry_for_selected_type);
    foreach my $story_type (@types) {

        my $class      = pkg('ElementLibrary')->top_level(name => $story_type);
	my $slug_entry = $class->slug_use(); 
        my $cat_entry  = $class->category_input();

        die ("Invalid slug_use() returned by class '$story_type': must be 'require', 'encourage', 'discourage', or 'prohibit'")
          unless ($slug_entry eq 'require' || $slug_entry eq 'encourage' || $slug_entry eq 'discourage' || $slug_entry eq 'prohibit');
        die ("Invalid cat_entry() returned by class '$story_type': must be 'require', 'optional', 'prohibit'")
          unless ($cat_entry eq 'require' || $cat_entry eq 'optional' || $cat_entry eq 'prohibit');

        if ($story_type eq $selected_type) {
	    $slug_entry_for_selected_type = $slug_entry;
	    $cat_entry_for_selected_type = $cat_entry;
        }

        push @slug_and_cat_entry_by_type, { story_type => $story_type,
                                            slug_entry => $slug_entry,
                                            cat_entry  => $cat_entry};
    }
    $template->param(slug_and_cat_entry_by_type_loop => \@slug_and_cat_entry_by_type);

    # pass in any class-specific slug-to-title javascript functions
    my @title_to_slug_loop;
    for my $type (@types) {
	if (my $js = pkg('ElementLibrary')->top_level(name => $type)->title_to_slug) {
	    push @title_to_slug_loop, { type => $type, function => $js };
	}
    }
    $template->param("title_to_slug_function_loop" => \@title_to_slug_loop);

    # remember user's manual selections (in case we're returning to screen with an error)
    for ('manual_slug', 'usr_checked_cat_idx', 'usr_unchecked_cat_idx') {
	$template->param($_ => $query->param($_) || ''); 
    }

    # set initial slug-display information (in case a type has already been selected)
    if ($selected_type) {
	$template->param('show_slug'    => 1) unless ($slug_entry_for_selected_type eq 'prohibit');
	$template->param('require_slug' => 1) if ($slug_entry_for_selected_type eq 'require');
	$template->param('show_cat'     => 1) unless ($cat_entry_for_selected_type eq 'prohibit');
	$template->param('require_cat'  => 1) if ($cat_entry_for_selected_type eq 'require');
    }

    return $template->output();
}

=item cancel

Returns to Workspace without creating a new story.

=cut

sub cancel_create {
    my $self = shift;
    add_message('cancel_new_story');
    $self->redirect_to_workspace;
}

=item cancel_edit

Returns Story to the state it was in previous to Edit (though a new 
version may have been written to disk via Save Story & Stay)

=cut

sub cancel_edit {
    my $self         = shift;
    my $q            = $self->query;
    my $this_user_id = $ENV{REMOTE_USER};
    my $story        = delete $session{story};

    # if it's a new story that hasn't yet been saved, delete it
    if ($self->_is_newly_created($story)) {
        $story->checkin;
        $story->delete;
    } 
    
    # regardless, grab previous URL and check-out status
    my $prev_url     = delete $session{KRANG_PERSIST}{pkg('Story')}{'PREV_URL'};
    my $prev_user_id = delete $session{KRANG_PERSIST}{pkg('Story')}{'PREV_CHECKED_OUT_BY'};

    # if it's a story we opened from workspace, we'll leave it there, otherwise...
    unless ($prev_url eq 'workspace.pl') {
        if (!$prev_user_id) {
            # if story wasn't checked out to anyone prior to our edit, check it in...
            $story->checkin;
            if (my $prev_desk_id = $story->last_desk_id) {
                # and, if it was on a desk, return it to that desk 
                $story->move_to_desk($prev_desk_id);
            }
        } elsif ($prev_user_id != $this_user_id) {
            # if story was checked out to a different user, we must have stolen it..
            $story->checkin;
            $ENV{REMOTE_USER} = $prev_user_id; # this hack returns the story to 
            $story->checkout;                  # the user from whom we stole it
            $ENV{REMOTE_USER} = $this_user_id;
        }
    }
    $self->header_props(uri => $prev_url);
    $self->header_type('redirect');
    return ""; 
}

sub _cancel_edit_goes_to {
    my ($self, $url_where_story_was_opened, $user_who_had_it_checked_out) = @_;
    $session{KRANG_PERSIST}{pkg('Story')}{'PREV_URL'} = $url_where_story_was_opened;
    $session{KRANG_PERSIST}{pkg('Story')}{'PREV_CHECKED_OUT_BY'} = $user_who_had_it_checked_out;
}

sub _is_newly_created {
    my ($self, $story) = @_;
    return ($story->version == 1 && $session{KRANG_PERSIST}{pkg('Story')}{'PREV_URL'} =~ /new_story$/);
}
    

=item create

Creates a new story object and proceeds to edit_story.  Expects the
form parameters from new_story.  Upon error, returns to new_story with
an error message.  Upon success, goes to edit_story.

=cut

sub create {
    my $self = shift;
    my $query = $self->query;

    my $type = $query->param('type');
    my $title = $query->param('title');
    my $slug = $query->param('slug') || '';
    my $cat_idx = $query->param('cat_idx') || 0;
    my $category_id = $query->param('category_id');
    $session{KRANG_PERSIST}{NEW_STORY_DIALOGUE}{ cat_chooser_id_new_story_category_id } = $category_id;

    my $cover_date = decode_datetime(name=>'cover_date', query=>$query);
    my @category_ids = ($category_id);

    # detect bad fields
    my @bad;
    push(@bad, 'type'),         add_alert('missing_type') unless $type;
    push(@bad, 'title'),        add_alert('missing_title') unless $title;
    push(@bad, 'cover_date'),   add_alert('missing_cover_date') unless $cover_date;

    if ($type) {
        push(@bad, 'slug') 
          unless $self->process_slug_input
            (slug => $slug, 
             type => $type, 
             cat_idx => $cat_idx);
        
        push(@bad, 'category_id') 
          unless @category_ids = $self->process_category_input
            (category_id => $category_id,
             type        => $type,
             slug        => $slug,
             cover_date  => $cover_date);
    }
    
    return $self->new_story(bad => \@bad) if @bad;

    # create the object
    my $story;
    eval {
        $story = pkg('Story')->new(class => $type,
                                   title => $title,
                                   slug  => $slug,
                                   categories => [ @category_ids ],
                                   cover_date => $cover_date);   
    };

    # is it a dup?
    if ($@ and ref($@) and $@->isa('Krang::Story::DuplicateURL')) {
      
      my $class = pkg('ElementLibrary')->top_level(name => $type);
      $self->alert_duplicate_url(error => $@, class => $class);
      return $self->new_story(bad => ['category_id',$class->url_attributes]);
      
    } elsif ($@) {
      # rethrow
      die($@);
    }

    # save it
    $story->save();

    # store in session for edit
    $session{story} = $story;

    # toss to edit
    $self->_cancel_edit_goes_to('story.pl?rm=new_story', $ENV{REMOTE_USER});
    return $self->edit;
}

=item check_in_and_save

Save, Check-In story to a particular desk and redirects to that desk.

=cut

sub check_in_and_save {
    my $self = shift;
    $self->make_sure_story_is_still_ours() || return '';

    my $query   = $self->query;
    my $desk_id = $query->param('checkin_to');

    # check if user may move object to desired desk
    return $self->access_forbidden()
      unless pkg('Group')->may_move_story_to_desk($desk_id);

    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    my $story;
    if ($query->param('story_id')) {
        # load story from DB
        ($story) = pkg('Story')->find(story_id => $query->param('story_id'));
        croak("Unable to load story '" . $query->param('story_id') . "'.")
          unless $story;

        $query->delete('story_id');
        $session{story} = $story;
    } else {
        $story = $session{story};
        croak("Unable to load story from session!")
          unless $story;
    }

    eval { $story->save() };

    # is it a dup?
    if ($@ and ref($@) and $@->isa('Krang::Story::DuplicateURL')) {
        $self->alert_duplicate_url(error => $@, class => $story->class);
        return $self->edit;
    } elsif ($@ and ref($@) and $@->isa('Krang::Story::MissingCategory')) {
        add_alert('missing_category_on_save');
        return $self->edit;
    } elsif ($@) {
        # rethrow
        die($@);
    }
                                                                                                       
    add_message('story_save', story_id => $story->story_id,
                url      => $story->url,
                version  => $story->version);
                                                                                                       
    # check it in
    $story->checkin();

    # move story to desk
    eval { $story->move_to_desk($desk_id); };

    if($@ and ref($@)) {
        if($@->isa('Krang::Story::CheckedOut')) {
            add_alert(
                'story_cant_move_checked_out',
                id   => $story->story_id,
                desk => (pkg('Desk')->find(desk_id => $query->param('checkin_to')))[0]->name
            );
        } elsif($@->isa('Krang::Story::NoDesk')) {
            add_alert(
                'story_cant_move_no_desk',
                story_id => $story->story_id,
                desk_id  => $desk_id
            );
        } else {
            $@->rethrow;
        }
        return $self->edit;
    }

    # remove story from session
    delete $session{story};
 
    add_message(
        "moved_story",
        id   => $story->story_id, 
        desk => (pkg('Desk')->find(desk_id => $query->param('checkin_to')))[0]->name
    );
 
    # redirect to that desk 
    $self->header_props(-uri => 'desk.pl?desk_id='.$query->param('checkin_to'));
    $self->header_type('redirect');
    return ""; 
}

=item checkout_and_edit

Checkout story and then call story editing interface.

=cut

sub checkout_and_edit {
    my $self = shift;
    my $query = $self->query;

    my $story;
    if ($query->param('story_id')) {
        # load story from DB
        ($story) = pkg('Story')->find(story_id => $query->param('story_id'));
        croak("Unable to load story '" . $query->param('story_id') . "'.")
          unless $story;

        $query->delete('story_id');
        $session{story} = $story;
        
        # this hack catches Edit -> View -> Edit (!) cases so they don't overwrite cancel info
        unless ($query->param('version') && $query->param('return_params') eq 'rm') {
            $self->_cancel_edit_goes_to('story.pl?rm=find', $story->checked_out_by);
        }
    } else {
        $story = $session{story};
        croak("Unable to load story from session!")
          unless $story;
    }

    $story->checkout;

    return $self->edit();
}

=item edit

The story editing interface.  

=cut

sub edit {    
    my $self = shift;
    my $query = $self->query;
    my $template = $self->load_tmpl('edit.tmpl', associate => $query, die_on_bad_params => 0, loop_context_vars => 1);
    my %args = @_;

    my $story;
    if ($query->param('story_id')) {
        ($story) = pkg('Story')->find(story_id => $query->param('story_id'));
        croak("Unable to load story '" . $query->param('story_id') . "'.")
          unless $story;
	
        $query->delete('story_id');
        $session{story} = $story;
    } else {
	$self->make_sure_story_is_still_ours() || return '';
	$story = $session{story};
    }

    # run the element editor edit
    $self->element_edit(template => $template, 
                        element => $story->element);
    
    # set fields shown everywhere
    $template->param(story_id          => $story->story_id || localize("n/a"),
                     type              => $story->element->display_name,
                     url               => $story->url ? 
                                            format_url(
                                                       url => $story->url,
                                                       linkto => "javascript:preview_and_stay()",
                                                       length => 50,
                                                      ) : "");

    # set fields for top-level
    my $path  = $query->param('path') || '/';
    if ($path eq '/' and not $query->param('bulk_edit')) {

        # if we got here from a top-level edit...
        if ($query->param('returning_from_root')) {
	  # maintain query's title & slug, even if empty
	  $template->param(title   => $query->param('title')   || '',
			   slug    => $query->param('slug')    || '');
	} else {
 	  # otherwise grab them from the session
	  $template->param(title   => $story->title || '',
			   slug    => $story->slug  || '');
        }

	# set other basic vars
	$template->param(is_root           => 1,
			 show_slug         => ($story->class->slug_use ne 'prohibit'),
			 require_slug      => ($story->class->slug_use eq 'require'),
                         auto_category     => ($story->class->category_input eq 'prohibit'),
			 version           => $story->version,
			 published_version => $story->published_version);

        # build select boxes
        $template->param(cover_date_selector =>
                         datetime_chooser(name=>'cover_date', date=>$story->cover_date, query=>$query));
        
        my @contribs_loop;
        my %contrib_types = pkg('Pref')->get('contrib_type');
        foreach my $contrib ($story->contribs) {
            push(@contribs_loop, { first_name => $contrib->first,
                                   last_name  => $contrib->last,
                                   type       => localize($contrib_types{$contrib->selected_contrib_type})});
        }
        $template->param(contribs_loop => \@contribs_loop);

        # figure out where to position 'replace' radio-button (use primary cat unless user selected something else)
        my @categories = $story->categories;
	my $selected_for_replace_id = ($query->param('category_to_replace_id') || (@categories && $categories[0]->category_id));

	# store basic URL for story and primary category as text
	$template->param(story_url_no_link => $story->url);
        $template->param(primary_cat_url_no_link => @categories && $categories[0]->url);

	# build category choosers
        my @category_loop;
        foreach my $cat (@categories) {
            my $url = $cat->url;
            my ($site, $dir) = split('/', $url, 2);
            $dir = "/" . $dir;

            push(@category_loop, {auto_category        => $template->param('auto_category'), # so it's usable within loop
                                  site                 => $site,
                                  category             => $dir,
                                  category_id          => $cat->category_id,
                                  selected_for_replace => ($cat->category_id == $selected_for_replace_id)});
            

        }
        $template->param(category_loop => \@category_loop);

	my ($add_button, $add_chooser)
	  = category_chooser(name        => 'add_category_id',
			     query       => $query,
			     label       => localize('Add Site/Category'),
			     display     => 0,
			     onchange    => 'add_category',
			     may_edit    => 1,
			     allow_clear => 0,
			    );
        $template->param(add_category_chooser => $add_chooser,
                         add_category_button  => $add_button);

	my ($replace_button, $replace_chooser)
	  = category_chooser(name        => 'category_replacement_id',
			     query       => $query,
			     label       => localize('Replace This Category'),
			     display     => 0,
			     onchange    => 'replace_category',
			     may_edit    => 1,
			     allow_clear => 0,
			    );
        $template->param(replace_category_chooser => $replace_chooser,
                         replace_category_button  => $replace_button);

        $template->param(version_selector => scalar
                         $query->popup_menu(-name    => 'version',
                                            -values  => [1 .. $story->version],
                                            -default => $story->version,
                                            -override => 1));

        # permissions
        my %admin_perms = pkg('Group')->user_admin_permissions();
        $template->param(may_publish => $admin_perms{may_publish});

    }

    # get desks for checkin selector
    my $last_desk_id = $story->last_desk_id;
    my ($last_desk) = $last_desk_id ? pkg('Desk')->find( desk_id => $last_desk_id ) : ();

    my @found_desks = pkg('Desk')->find();
    my @desk_loop;
    my $is_selected;

    foreach my $found_desk (@found_desks) {
	next unless pkg('Group')->may_move_story_to_desk($found_desk->desk_id);

	if ($last_desk) {
	    $is_selected = ($found_desk->order eq ($last_desk->order + 1)) ? 1 : 0;
	}

        push (@desk_loop, { choice_desk_id   => $found_desk->desk_id,
                            choice_desk_name => $found_desk->name,
                            is_selected      => $is_selected });
    }

    $template->param(desk_loop => \@desk_loop);

    $template->param(newly_created => $self->_is_newly_created($story)); # affects Cancel message

    return $template->output();
}


=item view

The story viewing interface.  Requires a return_script parameter with
the name of the script to return to and a list of return_params
parameters containing key/value pairs for the return request.
Optionally, a story_id and a version may be passed.  If a story_id is
not present then a story must be available in the session.

=cut

sub view {    
    my $self = shift;
    my $query = $self->query;
    my $template = $self->load_tmpl('view.tmpl',
                                    associate         => $query,
                                    die_on_bad_params => 0,
                                    loop_context_vars => 1);
    my %args = @_;

    # get story_id from params or from the story in the session
    my $story_id = $query->param('story_id') ? $query->param('story_id')
                                             : $session{story}->story_id;

    croak("Unable to get story_id!") unless $story_id;

    # load story from DB
    my $version = $query->param('version');
    my ($story) = pkg('Story')->find(story_id => $story_id,
                                     ($version && length($version) ?
                                      (version => $version) : ()),
                                    );
    croak("Unable to load story '" . $query->param('story_id') . "'" .
          (defined $version ? ", version '$version'." : "."))
      unless $story;

    # run the element editor edit
    $self->element_view(template => $template, 
                        element  => $story->element);

    # static data
    $template->param(story_id => $story->story_id,
                     type     => $story->element->display_name,
                     url      => format_url(
					    url => $story->url,
					    linkto => "javascript:Krang.preview('story','" . $story->story_id() . "')",
					    length => 50,
					   ),
                     version  => $story->version);

    if (not $query->param('path') or $query->param('path') eq '/') {
        # fields for top-level
        $template->param(is_root           => 1,
                         title             => $story->title,
                         slug              => $story->slug,
                         published_version => $story->published_version,
                        );

        $template->param(cover_date => $story->cover_date->strftime(localize('%m/%d/%Y %I:%M %p')))
          if $story->cover_date;

        my @contribs_loop;
        my %contrib_types = pkg('Pref')->get('contrib_type');
        foreach my $contrib ($story->contribs) {
            push(@contribs_loop, { first_name => $contrib->first,
                                   last_name  => $contrib->last,
                                   type       => localize($contrib_types{$contrib->selected_contrib_type})});
        }
        $template->param(contribs_loop => \@contribs_loop);

        $template->param(category_loop => [ map { { url => $_->url } } $story->categories ]);
    }

    # setup return form
    croak("Missing return_script and return_params!") 
      unless $query->param('return_params') and $query->param('return_script');
    my %return_params = $query->param('return_params');
    $template->param(return_script => $query->param('return_script'),
                     return_params_loop => 
                     [ map { { name => $_, value => $return_params{$_} } } keys %return_params ]);
    $template->param( was_edit => 1 ) if ($return_params{rm} eq 'edit');
    $template->param( can_edit => 1 ) 
      unless ( $story->checked_out and 
               ($story->checked_out_by ne $ENV{REMOTE_USER})) or 
                 not $story->may_edit;

    return $template->output();
}

=item revert

Revert contents of a story to that of an older version.  Expects a
story in the session and 'version' parameter.  Returns to edit mode
after C<< $story->revert() >>.

=cut

sub revert {
    my $self = shift;
    $self->make_sure_story_is_still_ours() || return '';

    my $query = $self->query;
    my $version = $query->param('version');
    my $story = $session{story};
    croak("Unable to load story from session!")
      unless $story;

    $story->revert($version);
    add_message('reverted_story', version => $version);

    $query->delete_all();
    return $self->edit();
}

=item copy

Creates a clone of the current story identified by the passed story_id
and redirects to edit mode.  The story is not saved.

=cut

sub copy {
    my $self = shift;
    my $query = $self->query;

    # load story from DB
    my ($story) = pkg('Story')->find(story_id => $query->param('story_id'));
    croak("Unable to load story '" . $query->param('story_id') . "'.")
      unless $story;

    # make a copy and store it in the session
    my $clone = $session{story} = $story->clone();
    
    # make sure it's checked out in case we want to save it later
    unless( $clone->{checked_out} ) {
        $clone->{checked_out}    = 1;
        $clone->{checked_out_by} = $ENV{REMOTE_USER};
    }

    # talk about it, get it all out
    if ($clone->categories) {
        add_message('copied_story',
                    id    => $story->story_id,
                    title => $clone->title,
                    slug  => $clone->slug,
                   );
    } else {
        add_alert('copied_story_no_cats',
                    id    => $story->story_id,
                    title => $clone->title);
    }                    


    # delete query...
    $query->delete_all;

    # go edit the copy
    return $self->edit();
}



=item replace_dupes

This mode gathers a list of stories whose URLs duplicate the current story's
and either removes them from the conflicting locations, or - if all their
locations conflict - deletes them entirely. 

=cut

sub replace_dupes {
  my $self = shift;
  my $query = $self->query;
  my $story = $session{story};

  # grab list of dupes from session
  my @dupes = @{$session{KRANG_PERSIST}{DUPE_STORIES}->{DUPES}};

  # turn them into a hash of arrayrefs like ( ID1 => [url1, url2, ..] )
  my %dupes;
  foreach (@dupes) { push @{$dupes{$_->{id}}}, $_->{url}; }

  # build array of actual story objects, and hash of original locations
  my @dupe_stories;
  my %dupe_stories_original_home; # we'll use -1 to mean 'not ours, but not on a desk'
  my %admin_perms = pkg('Group')->user_admin_permissions();
  my $may_checkin_all = $admin_perms{may_checkin_all};

  foreach my $id (keys %dupes) {
    my ($dupe_story) = Krang::Story->find(story_id => $id);
    if ($dupe_story->checked_out) {
      # if story is checked out to us, do nothing; otherwise...
      if ($dupe_story->checked_out_by ne $ENV{REMOTE_USER}) {
	if ($may_checkin_all && $dupe_story->may_edit) {
	  # if we can, force-check-in and take ownership
	  $dupe_stories_original_home{$id} = $dupe_story->desk_id || -1;
	  $dupe_story->checkin;
	  $dupe_story->checkout;
	} else {
	  # we hit a roadblack... undo our changes and alert the user
	  foreach (@dupe_stories) {
	    # stories we hashed in original_home were not previously checked out to us
	    if (my $orig_home = $dupe_stories_original_home{$_->story_id}) {
	      $_->checkin; 
	      # if we checked out this story from a desk and it's no longer on that desk...
	      if ($orig_home != -1 && $_->desk_id != $orig_home &&
		  scalar(pkg('Desk')->find(desk_id => $orig_home))) {
		$_->move_to_desk($orig_home);
	      }
	    }
	  }
	  # return to edit (or new-story) screen with the error
	  add_alert('dupe_story_checked_out', id => $id, url => $dupes{$id}[0]);
	  return $self->query->param('returning_from_root') ? $self->edit : $self->new_story;
	  }
	}
      } else {
	# story is currently checked in
	$dupe_stories_original_home{$id} = $dupe_story->desk_id || -1;
	$dupe_story->checkout;
      }
    push @dupe_stories, $dupe_story;
  }
  
  # now we have everything safely in our hands, so make changes!
  foreach my $dupe_story (@dupe_stories) {
    my @all_cats  = $dupe_story->categories;
    my @dupe_urls = @{$dupes{$dupe_story->story_id}};

    # if every one of the dupe story's URLs is a dupe....
    if (@all_cats == @dupe_urls) {
      # delete it entirely
      add_message('dupe_story_deleted', id => $dupe_story->story_id);
      $dupe_story->checkin;
      $dupe_story->delete;
    } else {
      # otherwise, replace full list of cats with list of non-dupe cats
      my %dupe_cats;
      my $dupe_slug = $dupe_story->slug || '';
      foreach my $dupe_url (@dupe_urls) {
	my ($cat_url, $slug) = ($dupe_url =~ /^(.*)$dupe_slug$/);
	$dupe_cats{$cat_url} = 1;
      }
      my @safe_cats = grep { !$dupe_cats{$_->url} } @all_cats;
      $dupe_story->categories(@safe_cats);
      $dupe_story->save;
      # and, if appropriate, return story to its original location
      if (my $orig_home = $dupe_stories_original_home{$dupe_story->story_id}) {
	$dupe_story->checkin;
	if ($orig_home != -1 && $dupe_story->desk_id != $orig_home &&
	    scalar(pkg('Desk')->find(desk_id => $orig_home))) {
	  $dupe_story->move_to_desk($orig_home);
	}
      }
      add_message('dupe_story_modified', id => $dupe_story->story_id);
    }
  }  

  # at this point we're finished, so re-submit user's failed query
  my $last_query = $session{KRANG_PERSIST}{DUPE_STORIES}->{QUERY};
  foreach (keys %$last_query) { $self->query->param($_ => $last_query->{$_}) }
  delete $session{KRANG_PERSIST}{DUPE_STORIES};
  my %run_modes = $self->run_modes;                      # get full hash of runmodes => method_names
  my $rm_method = $run_modes{$self->query->param('rm')}; # get method name for runmode of last query
  $self->$rm_method;
}

=item db_save

This mode saves the story to the database and leaves the story editor,
sending control to workspace.pl.

=cut

sub db_save {
    my $self = shift;
    $self->make_sure_story_is_still_ours() || return '';

    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    # save story to the database
    my $story = $session{story};
    eval { $story->save() };

    # is it a dup?
    if ($@ and ref($@) and $@->isa('Krang::Story::DuplicateURL')) {
        $self->alert_duplicate_url(error => $@, class => $story->class);
        return $self->edit;
    } elsif ($@ and ref($@) and $@->isa('Krang::Story::MissingCategory')) {
        add_alert('missing_category_on_save');
        return $self->edit;
    } elsif ($@) {
        # rethrow
        die($@);
    }
    
    add_message('story_save', story_id => $story->story_id,
                url      => $story->url,
                version  => $story->version);

    # remove story from session
    delete $session{story};

    # return to workspace
    $self->redirect_to_workspace;    
}



=item db_save_and_stay

This mode saves the story to the database and returns to edit.

=cut

sub db_save_and_stay {
    my $self = shift;
    $self->make_sure_story_is_still_ours() || return '';

    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    # save story to the database
    my $story  = $session{story};
    my $is_new = $self->_is_newly_created($story);
    eval { $story->save() };

    # is it a dup?
    if ($@ and ref($@) and $@->isa('Krang::Story::DuplicateURL')) {
        $self->alert_duplicate_url(error => $@, class => $story->class);
        return $self->edit;
    } elsif ($@ and ref($@) and $@->isa('Krang::Story::MissingCategory')) {
        add_alert('missing_category_on_save');
        return $self->edit;
    } elsif ($@) {
        # rethrow
        die($@);
    }
    
    add_message('story_save', story_id => $story->story_id,
                url      => $story->url,
                version  => $story->version);

    # if Cancel was redirecting to New Story, now it should redirect to Workspace
    $is_new ? $self->_cancel_edit_goes_to('workspace.pl', $ENV{REMOTE_USER}) : ();
    
    # return to edit
    return $self->edit();
}

=item preview_and_stay

This mode saves the current data to the session and previews the
story in a new window. 

=cut

sub preview_and_stay {
    my $self = shift;

    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    # re-load edit window and have it launch new window for preview
    my $edit_window    = $self->edit || '';
    my $js_for_preview = qq|<script type="text/javascript">Krang.preview('story', null);</script>|;
    return ($edit_window . $js_for_preview);
}

=item save_and_jump

This mode saves the current data to the session and jumps to editing
an element within the story.

=cut

sub save_and_jump {
    my $self = shift;

    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    # get target
    my $query = $self->query;
    my $jump_to = $query->param('jump_to');
    croak("Missing jump_to on save_and_jump!") unless $jump_to;
    
    # set target and show edit screen
    $query->param(path => $jump_to);
    $query->param(bulk_edit => 0);
    return $self->edit();
}

=item save_and_add

This mode saves the current data to the session and passes control to
Krang::ElementEditor::add to add a new element.

=cut

sub save_and_add {
    my $self = shift;

    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    return $self->add();
}

=item save_and_publish

This mode saves the current data to the database and passes control to
publisher.pl to publish the story.

=cut

sub save_and_publish {
    my $self = shift;
    $self->make_sure_story_is_still_ours() || return '';
    
    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    # save story to the database
    my $story = $session{story};
    eval { $story->save() };

    # is it a dup?
    if ($@ and ref($@) and $@->isa('Krang::Story::DuplicateURL')) {
        $self->alert_duplicate_url(error => $@, class => $story->class);
        return $self->edit;
    } elsif ($@ and ref($@) and $@->isa('Krang::Story::MissingCategory')) {
        add_alert('missing_category_on_save');
        return $self->edit;
    } elsif ($@) {
        # rethrow
        die($@);
    }
    
    add_message('story_save', story_id => $story->story_id,
                url      => $story->url,
                version  => $story->version);

    # remove story from session
    delete $session{story};

    # redirect to publish
    $self->header_props(-uri => 'publisher.pl?rm=publish_story&story_id=' . $story->story_id);
    $self->header_type('redirect');
    return "";
}

=item save_and_view

This mode saves the current data to the session and passes control to
view to view a version of the story.

=cut

sub save_and_view {
    my $self = shift;
    
    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    my $query = $self->query;
    $query->param('return_script' => 'story.pl');
    $query->param('return_params' => rm => 'edit');
    return $self->view();
}

=item save_and_view_log

This mode saves the current data to the session and passes control to
view to view a version of the story.

=cut

sub save_and_view_log {
    my $self = shift;
    
    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    $self->header_props(-uri => 'history.pl?history_return_script=story.pl&history_return_params=rm&history_return_params=edit&story_id=' . $session{story}->story_id);
    $self->header_type('redirect');
    return "";
}

=item save_and_edit_schedule

This mode saves the current data to the session and passes control to
edit schedule for story.

=cut

sub save_and_edit_schedule {
    my $self = shift;
                                                                        
    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;
                                                                        
    $self->header_props(-uri => 'schedule.pl?rm=edit&object_type=story');
    $self->header_type('redirect');
    return "";
}

=item save_and_edit_contribs

This mode saves the current data to the session and passes control to
Krang::CGI::Contrib to edit contributors

=cut

sub save_and_edit_contribs {
    my $self = shift;

    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    # send to contrib editor
    $self->header_props(-uri => 'contributor.pl?rm=associate_story');
    $self->header_type('redirect');
    return "";
}

=item save_and_bulk_edit

This mode saves the current element data to the session and goes to
the bulk edit mode.

=cut

sub save_and_bulk_edit {
    my $self = shift;

    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    $self->query->param(bulk_edit => 1);
    return $self->edit();
}

=item save_and_change_bulk_edit_sep

Saves and changes the bulk edit separator, returning to edit.

=cut

sub save_and_change_bulk_edit_sep {
    my $self = shift;

    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    my $query = $self->query;
    $query->param(bulk_edit_sep => $query->param('new_bulk_edit_sep'));
    $query->delete('new_bulk_edit_sep');
    return $self->edit();
}


=item save_and_leave_bulk_edit

This mode saves the current element data to the session and goes to
the edit mode.

=cut

sub save_and_leave_bulk_edit {
    my $self = shift;

    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    $self->query->param(bulk_edit => 0);
    return $self->edit();
}


=item save_and_find_story_link

This mode saves the current element data to the session and goes to
the find_story_link mode in Krang::CGI::ElementEditor.

=cut

sub save_and_find_story_link {
    my $self = shift;

    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    # get target
    my $query = $self->query;
    my $jump_to = $query->param('jump_to');
    croak("Missing jump_to on save_and_find_story_link!") unless $jump_to;
    
    # set target and show find screen
    $query->param(path => $jump_to);
    return $self->find_story_link();
}

=item save_and_find_media_link

This mode saves the current element data to the session and goes to
the find_media_link mode in Krang::CGI::ElementEditor.

=cut

sub save_and_find_media_link {
    my $self = shift;

    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    # get target
    my $query = $self->query;
    my $jump_to = $query->param('jump_to');
    croak("Missing jump_to on save_and_find_media_link!") unless $jump_to;
    
    # set target and show find screen
    $query->param(path => $jump_to);
    return $self->find_media_link();
}

=item save_and_go_up

This mode saves the current element data to the session and jumps to
edit the parent of this element.

=cut

sub save_and_go_up {
    my $self = shift;

    # call internal _save and return output from it on error
    my $output = $self->_save();
    return $output if length $output;

    # compute target
    my $query = $self->query;
    my $path = $query->param('path');
    $path =~ s!/[^/]+$!!;

    # set target and show edit screen
    $query->param(path => $path);
    return $self->edit();
}


# underlying save routine.  returns false on success or HTML to show
# to the user on failure.
sub _save {
    my $self = shift;
    my $query = $self->query;

    my $story = $session{story};
    croak("Unable to load story from session!")
      unless $story;

    # run element editor save and return to edit mode if errors were found.
    my $elements_ok = $self->element_save(element => $story->element);
    return $self->edit() unless $elements_ok;

    # if we're saving in the root then save the story data
    my $path = $query->param('path') || '/';
    if ($path eq '/' 
        and not $query->param('bulk_edit')) {
        my $title = $query->param('title');
        my $slug = $query->param('slug') || '';
        my $cover_date = decode_datetime(name=>'cover_date', query=>$query);
        
        my @bad;
        push(@bad, 'title'),       add_alert('missing_title')
	    unless $title;
        push(@bad, 'cover_date'),  add_alert('missing_cover_date')
	    unless $cover_date;
        push(@bad, 'slug')
	    unless $self->process_slug_input(slug => $slug, 
					     story => $story,
					     categories => [$story->categories]);
	
        # return to edit mode if there were problems
        return $self->edit(bad => \@bad) if @bad;

        # make changes permanent
        $story->title($title);
        $story->slug($slug);
        $story->cover_date($cover_date);
    }
    
    # success, no output
    return '';
}

=item add_category

Adds a category to the story.  Expects a category ID in
add_category_id, which is filled in by the category chooser on the
edit screen.  Returns to edit mode on success and on failure with an
error message.

=cut

sub add_category {
    my $self = shift;
    my $query = $self->query;

    my $story = $session{story};
    croak("Unable to load story from session!")
      unless $story;

    my $category_id = $query->param('add_category_id');
    unless ($category_id) {
        add_alert("added_no_category");
        return $self->edit();
    }

    # make sure this isn't a dup
    my @categories = $story->categories();
    if (grep { $_->category_id == $category_id } @categories) {
        add_alert("duplicate_category");
        return $self->edit();
    }

    # look up category
    my ($category) = pkg('Category')->find(category_id => $category_id);
    croak("Unable to load category '$category_id'!")
      unless $category;

    # make sure it passes validation check
    my $validate = $story->class->validate_category(category => $category,
                                                    slug => $story->slug,
                                                    title => $story->title,
                                                    cover_date => $story->cover_date);
    unless ($validate == 1) {
        add_alert('bad_category', explanation => $validate || '');
        return $self->edit();
    }

    # add it to list 
    push(@categories, $category);

    # and, assuming update_categories() succeeds...
    if ($self->update_categories(query => $query,    
				 story => $story,    
				 categories => \@categories)) {
	add_message('added_category', url => $category->url);
    }
    
    return $self->edit();
}

=item set_primary_category

Sets the primary category for the story.  Expects a category ID in
primary_category_id, which is filled in by the primary radio group in
the edit screen.  Returns to edit mode on success and on failure with
an error message.

=cut

sub set_primary_category {
    my $self = shift;
    my $query = $self->query;

    my $story = $session{story};
    croak("Unable to load story from session!")
      unless $story;

    my $category_id = $query->param('primary_category_id');
    return $self->edit() unless $category_id;

    # shuffle list of categories to put new primary first
    my (@categories, $url);
    foreach my $cat ($story->categories()) {
        if ($cat->category_id == $category_id) {
            $url = $cat->url;
            unshift(@categories, $cat);
        } else {
            push(@categories, $cat);
        }
    }

    # and, assuming update_categories() succeeds...
    if ($self->update_categories(query => $query, 
				 story => $story,
				 categories => \@categories)) {
        add_message('set_primary_category', url => $url);
        $query->delete('category_to_replace_id'); # put replace button on new primary
    }

    return $self->edit();
}

=item replace_category

Replaces one category with another. Expects one category ID in
category_to_replace_id, and another in category_replacement_id.
Returns to edit mode on success and on failure with an error message.

=cut

sub replace_category {
    my $self = shift;
    my $query = $self->query;

    my $story = $session{story};
    croak("Unable to load story from session!")
      unless $story;

    my $old_category_id = $query->param('category_to_replace_id');
    my $new_category_id = $query->param('category_replacement_id');
    unless ($old_category_id && $new_category_id) {
        add_alert("replaced_no_category");
        return $self->edit();
    }

    # make sure this isn't a dup
    my @existing_categories = $story->categories();
    if (grep { $_->category_id == $new_category_id } @existing_categories) {
        add_alert("duplicate_category");
        return $self->edit();
    }

    # load both categories
    my ($old_category) = pkg('Category')->find(category_id => $old_category_id);
    croak("Unable to load category '$old_category_id'!")
      unless $old_category;

    my ($new_category) = pkg('Category')->find(category_id => $new_category_id);
    croak("Unable to load category '$new_category_id'!")
      unless $new_category;

    # make sure new one passes validation check
    my $validate = $story->class->validate_category(category => $new_category,
                                                    slug => $story->slug,
                                                    title => $story->title,
                                                    cover_date => $story->cover_date);
    unless ($validate == 1) {
        add_alert('bad_category', explanation => $validate || '');
        return $self->edit();
    }

    # perform the replacement
    my @new_categories;
    foreach my $existing_category ($story->categories) {
	if ($existing_category->category_id == $old_category_id) {
	    push @new_categories, $new_category;
	} else {
	    push @new_categories, $existing_category;
	}
    }

    # and, assuming update_categories() succeeds...
    if ($self->update_categories(query => $query, 
				 story => $story,
				 categories => \@new_categories)) {

	add_message('replaced_category', old_url => $old_category->url, new_url => $new_category->url);
	$query->param('category_to_replace_id' => $new_category->category_id); # so radio-button remains!
    } 

    return $self->edit();
}




=item delete_categories

Removes categories from the story.  Expects one or more cat_remove_$id
variables set with checkboxes.  Returns to edit mode on success and on
failure with an error message.

=cut

sub delete_categories {
    my $self = shift;
    my $query = $self->query;

    my $story = $session{story};
    croak("Unable to load story from session!")
      unless $story;

    my %delete_ids = map { s/cat_remove_//; ($_, 1) } 
                       grep { /^cat_remove/ } $query->param();

    # shuffle list of categories to remove the deleted
    my (@categories, @urls);
    foreach my $cat ($story->categories()) {
      if ($delete_ids{$cat->category_id}) {
	push(@urls, $cat->url);
	if ($query->param('category_to_replace_id') == $cat->category_id) {
	  $query->delete('category_to_replace_id'); # reset replace button
	}
      } else {
	push(@categories, $cat);
      }
    }
    
    # and, assuming update_categories() succeeds...
    if ($self->update_categories(query => $query, 
				 story => $story,
				 categories => \@categories)) {
      
      # put together a reasonable summary of what happened
      if (@urls == 0) {
  	  add_alert('deleted_no_categories');
      } elsif (@urls == 1) {
	  add_message('deleted_a_category', url => $urls[0]);
      } else {
	  add_message('deleted_categories', 
		      urls => join(', ', @urls[0..$#urls-1]).
		      ' and '.$urls[-1]);
      }
    }
    
    return $self->edit();
}


=item delete

Deletes the story permanently from the database.  Expects a story in
the session.

=cut

sub delete {
    my $self = shift;
    $self->make_sure_story_is_still_ours || return '';

    my $query = $self->query();
    my $story = $session{story};
    croak("Unable to load story from session!")
      unless $story;

    add_message('story_delete', story_id => $story->story_id,
                                url      => $story->url);

    # check to make sure a story_id exists - the UI allows you to
    # delete a story that has not been saved yet.
    if ($story->story_id) {
        $story->delete();
    }

    delete $session{story};

    $self->redirect_to_workspace;
}

=item find

List all stories which match the search criteria.  Provide links to 
edit or view each story.  Provide a link to view the log for a story.

Also, provide checkboxes next to each story through which the user may 
select a set of stories to be deleted or checked out to Workplace.

=cut

sub find {
    my $self = shift;

    my $q = $self->query();
    my $template = $self->load_tmpl('find.tmpl', associate=>$q);
    my %tmpl_data = ();

    # if the user clicked 'clear', nuke the cached params in the session.
    if (defined($q->param('clear_search_form'))) {
        delete $session{KRANG_PERSIST}{pkg('Story')};
    }

    my $show_type_and_version = $q->param('show_type_and_version');
    # if they submitted the search form then either search_filter (simple search)
    # or search_title (advanced search) will at least be defined
    if( defined $q->param('search_filter') or defined $q->param('search_title') ) {
        $session{KRANG_PERSIST}{pkg('Story')}{show_type_and_version} = $show_type_and_version;
    } else {
        $show_type_and_version = $session{KRANG_PERSIST}{pkg('Story')}{show_type_and_version};
    }

    # Search mode
    my $do_advanced_search = defined($q->param('do_advanced_search')) ?
      $q->param('do_advanced_search') : $session{KRANG_PERSIST}{pkg('Story')}{do_advanced_search};
    $template->param('do_advanced_search' => $do_advanced_search);

    # Set up persist_vars for pager
    my %persist_vars = (
                        rm => 'find',
                        do_advanced_search => $do_advanced_search,
                       );

    # Set up find_params for pager
    my %find_params = (may_see => 1, show_hidden => 1);

    if ($do_advanced_search) {
        # Set up advanced search
        my @auto_search_params = qw(
                                    title
                                    url
                                    class 
                                    below_primary_category_id 
                                    story_id
                                    contrib_simple
                                    creator_simple
                                    full_text_string
                                   );
        for (@auto_search_params) {
            my $key = $_;
            my $val = defined($q->param("search_".$_)) ? 
              $q->param("search_".$_) : $session{KRANG_PERSIST}{pkg('Story')}{"search_" . $_};
 
            $template->param("search_$key" => $val);


            # Persist parameter
            $persist_vars{"search_". $_} = $val;

            # If no data, skip parameter
            next unless (defined($val) && length($val));

            # Like search
            if (grep {$_ eq $key} (qw/title url/)) {
                $key .= '_like';
                $val =~ s/\W+/\%/g;
                $val = "\%$val\%";
            }

            # Set up search in pager
            $find_params{$key} = $val;
        }

        # Set up cover and publish date search
        for my $datetype (qw/cover publish/) {
            my $from = decode_datetime(query=>$q, name => $datetype .'_from');
            my $to =   decode_datetime(no_time_is_end => 1, query=>$q, name => $datetype .'_to');
            if ($from || $to) {
                my $key = $datetype .'_date';
                my $val = [$from, $to];
            
                # Set up search in pager
                $find_params{$key} = $val;
            }

            # Persist parameter
            for my $interval (qw/month day year hour minute ampm/) {
                my $from_pname = $datetype .'_from_'. $interval;
                my $to_pname = $datetype .'_to_'. $interval;

                # Only persist date vars if they are complete and valid
                if ($from) {
                    my $from_pname = $datetype .'_from_'. $interval;
                    $persist_vars{$from_pname} = $q->param($from_pname);
                } else {
                    # Blow away var
                    $q->delete($from_pname);
                }

                if ($to) {
                    $persist_vars{$to_pname} = $q->param($to_pname);
                } else {
                    # Blow away var
                    $q->delete($to_pname);
                }
            }

        }

        # If we're showing an advanced search, set up the form
        $tmpl_data{category_chooser} =
          category_chooser(
                           name       => 'search_below_primary_category_id',
                           query      => $q,
                           formname   => 'search_form',
                           persistkey => pkg('Story'),
                          );

        # Date choosers
        $tmpl_data{date_chooser_cover_from}   = datetime_chooser(query=>$q, name=>'cover_from', nochoice=>1);
        $tmpl_data{date_chooser_cover_to}     = datetime_chooser(query=>$q, name=>'cover_to', nochoice=>1);
        $tmpl_data{date_chooser_publish_from} = datetime_chooser(query=>$q, name=>'publish_from', nochoice=>1);
        $tmpl_data{date_chooser_publish_to}   = datetime_chooser(query=>$q, name=>'publish_to', nochoice=>1);

        # Story class
        my @classes = sort { lc $a->display_name cmp lc $b->display_name }
            map { pkg('ElementLibrary')->top_level(name => $_ ) } 
            grep { $_ ne 'category' } pkg('ElementLibrary')->top_levels;
        my %class_labels = map { $_->name => $_->display_name } @classes;
        $tmpl_data{search_class_chooser} = scalar($q->popup_menu(-name      => 'search_class',
                                                                 -default   => ($persist_vars{"search_class"} || ''),
                                                                 -values    => [ ('', map {$_->name} @classes) ],
                                                                 -labels    => \%class_labels));
    } else {
        # Set up simple search
        my $search_filter = defined($q->param('search_filter')) ?
          $q->param('search_filter') : $session{KRANG_PERSIST}{pkg('Story')}{search_filter};
        $find_params{simple_search} = $search_filter;
        $persist_vars{search_filter} = $search_filter;
        $template->param(search_filter => $search_filter);

        my $check_full_text = defined ($q->param('search_filter')) ?
          $q->param('search_filter_check_full_text') : $session{KRANG_PERSIST}{pkg('Story')}{search_filter_check_full_text};
        $find_params{simple_search_check_full_text} = $check_full_text;
        $persist_vars{search_filter_check_full_text} = $check_full_text;
        $template->param(search_filter_check_full_text => $check_full_text);
    }

    my $pager = pkg('HTMLPager')->new(
                                      cgi_query => $q,
                                      persist_vars => \%persist_vars,
                                      use_module => pkg('Story'),
                                      find_params => \%find_params,
                                      columns => [qw(
                                                     pub_status 
                                                     story_id 
                                                     title 
                                                     url 
                                                     cover_date 
                                                     commands_column 
                                                     status 
                                                     checkbox_column
                                                    )],
                                      column_labels => {
                                                        pub_status => '',
                                                        story_id => 'ID',
                                                        title => 'Title',
                                                        url => 'URL',
                                                        commands_column => '',
                                                        cover_date => 'Date',
                                                        status => 'Status',
                                                       },
                                      columns_sortable => [qw( story_id title url cover_date )],
                                      row_handler => sub { $self->find_story_row_handler(@_); },
                                      id_handler => sub { return $_[0]->story_id },
                                     );

    my $pager_tmpl = $self->load_tmpl( 'find_pager.tmpl', 
        die_on_bad_params => 0, 
        loop_context_vars => 1,
        global_vars       => 1,
        associate         => $q,
    );
    $pager->fill_template($pager_tmpl);
    $pager_tmpl->param(show_type_and_version => $show_type_and_version);

    # Set up output
    $template->param(
        %tmpl_data,
        pager_html           => $pager_tmpl->output,
        row_count            => $pager->row_count,
        show_type_and_version => $show_type_and_version,
    );

    return $template->output;
}

=item list_active

List all active stories.  Provide links to view each story.  If the
user has 'checkin all' admin abilities then checkboxes are provided to
allow the stories to be stole or checked-in.

=cut

sub list_active {
    my $self = shift;
    my $q = $self->query();

    # Set up persist_vars for pager
    my %persist_vars = (rm => 'list_active');

    # Set up find_params for pager
    my %find_params = (checked_out => 1, may_see => 1);

    # may checkin all?
    my %admin_perms = pkg('Group')->user_admin_permissions();
    my $may_checkin_all = $admin_perms{may_checkin_all};

    my $pager = pkg('HTMLPager')->new(
       cgi_query => $q,
       persist_vars => \%persist_vars,
       use_module => pkg('Story'),
       find_params => \%find_params,
       columns => [(qw(
                       story_id 
                       title 
                       url 
                       user
                       commands_column
                      )), ($may_checkin_all ? ('checkbox_column') : ())],
       column_labels => {
                         story_id => 'ID',
                         title => 'Title',
                         url => 'URL',
                         user  => 'User',
                         commands_column => '',
                        },
       columns_sortable => [qw( story_id title url )],
       row_handler => sub { $self->list_active_row_handler(@_); },
       id_handler => sub { return $_[0]->story_id },
      );

    # Set up output
    my $template = $self->load_tmpl('list_active.tmpl', associate=>$q);
    $template->param(pager_html => $pager->output());
    $template->param(row_count => $pager->row_count());
    $template->param(may_checkin_all => $may_checkin_all);

    return $template->output;
}


=item delete_selected

Delete all the stories which were checked on the find screen.

=cut

sub delete_selected {
    my $self = shift;

    my $q = $self->query();
    my @story_delete_list = ( $q->param('krang_pager_rows_checked') );
    $q->delete('krang_pager_rows_checked');

    # No selected stories?  Just return to find without any message
    return $self->find() unless (@story_delete_list);

    foreach my $story_id (@story_delete_list) {
        pkg('Story')->delete($story_id);
    }

    add_message('selected_stories_deleted');
    return $self->find();
}


=item checkout_selected

Check out to Workplace all the stories which were checked on the find screen.

=cut

sub checkout_selected {
     my $self = shift;

     my $q = $self->query();
     my @story_checkout_list = ( $q->param('krang_pager_rows_checked') );
     $q->delete('krang_pager_rows_checked');

     # No selected stories?  Just return to find without any message
     return $self->find() unless (@story_checkout_list);

     my $was_checked_out;
     foreach my $story_id (@story_checkout_list) {
         my ($s) = pkg('Story')->find(story_id=>$story_id);
         unless ($was_checked_out = $s->checked_out) {
             $s->checkout();
         }
     }

     # Do we go to the edit screen (one story) or Workspace (N stories)?
     if (scalar(@story_checkout_list) > 1) {
         add_message('selected_stories_checkout');

         # Redirect to Workplace
         return $self->redirect_to_workspace;
     } else {
         ($session{story}) = pkg('Story')->find(story_id=>$story_checkout_list[0]);
         add_message('selected_stories_checkout_one');

         # Redirect to Edit
         $self->_cancel_edit_goes_to('story.pl?rm=find', $was_checked_out && $ENV{REMOTE_USER});
         return $self->edit();
     }
}


=item checkin_selected

Checkin all the stories which were checked on the list_active screen.

=cut

sub checkin_selected {
     my $self = shift;

     my $q = $self->query();
     my @story_checkin_list = ( $q->param('krang_pager_rows_checked') );
     $q->delete('krang_pager_rows_checked');

     foreach my $story_id (@story_checkin_list) {
         my ($s) = pkg('Story')->find(story_id=>$story_id);
         $s->checkin();
     }

     if (scalar(@story_checkin_list)) {
         add_message('selected_stories_checkin');
     }

     return $self->list_active;
}


=item steal_selected

Steal all the stories which were checked on the list_active screen,
and either go to workspace of user, or - if only one story was checked -
directly to the edit screen.

=cut

sub steal_selected {
     my $self = shift;

     my $q = $self->query();
     my @story_ids = ( $q->param('krang_pager_rows_checked') );
     $q->delete('krang_pager_rows_checked');

     # loop through selected stories, checking ownership
     my (@owned_ids, @stolen_ids, %victims);
     foreach my $story_id (@story_ids) {
	 my ($s) = pkg('Story')->find(story_id => $story_id);
	 if ($s->checked_out_by ne $ENV{REMOTE_USER}) {
	     my ($victim) = pkg('User')->find(user_id => $s->checked_out_by);
	     my $victim_name = $q->escapeHTML($victim->first_name.' '.$victim->last_name);
	     $s->checkin();  # this story was checked out to someone
	     $s->checkout(); # else; steal it and keep track of victim
	     $victims{$victim_name} = $victim->user_id;
	     push @stolen_ids, $story_id;
	 } else {
	     push @owned_ids, $story_id; # this story was already ours!
	 }
     }

     # if there's only one story, grab it so we can check access
     my ($single_story) = Krang::Story->find(story_id => $story_ids[0])
       if (@story_ids) == 1;
     
     # explain our actions to user
     if ((@story_ids == 1) && $single_story->may_edit()) {
	 %victims ? 
	     add_message('one_story_stolen_and_opened', id => $story_ids[0], victim => (keys %victims)[0]) :
	     add_message('one_story_yours_and_opened',  id => $story_ids[0]);
     } elsif (@owned_ids && !@stolen_ids) {
	 add_message('all_selected_stories_yours');
     } else {
	 if (@owned_ids) {
	     (@owned_ids > 1) ? 
		 add_message('multiple_stories_yours', ids => join(' & ',@owned_ids)) :
		 add_message('one_story_yours', id => $owned_ids[0]);
	 }
	 if (@stolen_ids) {
	     (@stolen_ids > 1) ? 
		 add_message('multiple_stories_stolen', ids => join(' & ',@stolen_ids), victims => join(' & ', sort keys %victims)) :
		 add_message('one_story_stolen', id => $stolen_ids[0], victim => (keys %victims)[0]);
	 }
     }

     # if user selected one story, and it's editable....
     if ((@story_ids == 1) && ($single_story->may_edit)) {
         
         # open it (after storing cancel info)
	 ($session{story}) = $single_story;
         $self->_cancel_edit_goes_to('story.pl?rm=list_active', 
                                     %victims ? (values %victims)[0] : $ENV{REMOTE_USER});
	 return $self->edit; 

     } else { 
         # otherwise go to Workspace
         return $self->redirect_to_workspace;
     }
}

###########################
####  PRIVATE METHODS  ####
###########################


# Pager row handler for story find run-mode
sub find_story_row_handler {
    my $self = shift;
    my ($row, $story) = @_;
    my $q = $self->query;
    my $show_type_and_version = $session{KRANG_PERSIST}{pkg('Story')}{show_type_and_version};

    # Columns:
    $row->{story_id}   = $story->story_id();
    $row->{title}      = $story->title;
    $row->{pub_status} = $story->published_version ? '<b>'.localize('P').'</b>' : '&nbsp;';

    # format url to fit on the screen and to link to preview
    $row->{url} = format_url(
        url    => $story->url(),
        linkto => "javascript:Krang.preview('story','" . $row->{story_id} . "')"
    );

    # cover_date
    my $tp = $story->cover_date();
    $row->{cover_date} = (ref($tp)) ? $tp->strftime(localize('%m/%d/%Y %I:%M %p')) : localize('[n/a]');

    # command column
    $row->{commands_column} = qq|<input value="|
        . localize('View Detail')
        . qq|" onclick="view_story('|
        . $story->story_id 
        . qq|')" type="button" class="button">|
        . ' '
        . qq|<input value="|
        . localize('View Log')
        . qq|" onclick="view_story_log('| . $story->story_id 
        . qq|')" type="button" class="button">|
        . ' '
        . qq|<input value="|
        . localize('Copy')
        . qq|" onclick="copy_story('| . $story->story_id 
        . qq|')" type="button" class="button">|;

    if (($story->checked_out) and 
        ($story->checked_out_by ne $ENV{REMOTE_USER})
        or not $story->may_edit ) {
        $row->{checkbox_column} = "&nbsp;";
    } else {
        $row->{commands_column} .= qq| <input value="|
            . localize('Edit')
            . qq|" onclick="edit_story('| 
            . $story->story_id 
            . qq|')" type="button" class="button">|;
    }

    # status 
    if ($story->checked_out) {
        $row->{status} = localize('Checked out by')
            . ' <b>'
            . (pkg('User')->find(user_id => $story->checked_out_by))[0]->login
            . '</b>';
    } elsif ($story->desk_id) {
        $row->{status} = localize('On')
            . ' <b>'
            . (pkg('Desk')->find(desk_id => $story->desk_id))[0]->name
            . '</b> '
            . localize('Desk');
    } else {
        $row->{status} = '&nbsp;';
    }

    if( $show_type_and_version ) {
        # story type
        $row->{story_type}    = $story->class->display_name;
        $row->{story_version} = $story->version;
    }
}

# Pager row handler for story list active run-mode
sub list_active_row_handler {
    my $self = shift;
    my ($row, $story) = @_;
    my $q = $self->query;

    # Columns:
    #

    # story_id
    $row->{story_id} = $story->story_id();

    # format url to fit on the screen and to link to preview
    $row->{url} = format_url( url => $story->url(),
                              linkto => "javascript:Krang.preview('story','" . $row->{story_id} . "')" );

    # title
    $row->{title} = $q->escapeHTML($story->title);

    # commands column
    $row->{commands_column} = qq|<input value="|
        . localize('View Detail')
        . qq|" onclick="view_story('|
        . $story->story_id
        . qq|')" type="button" class="button">|;

    # user
    my ($user) = pkg('User')->find(user_id => $story->checked_out_by);
    $row->{user} = $q->escapeHTML($user->first_name . " " . $user->last_name);
}

sub autocomplete {
    my $self = shift;
    return autocomplete_values(
        table  => 'story',
        fields => [qw(story_id title slug)],
    );
}

sub update_categories {

    my ($self, %args)  = @_;
    my $query          = $args{query};
    my $story          = $args{story};
    my @old_cats       = $story->categories;
    my @new_cats       = @{$args{categories}};

    # find what has changed between old and new categories
    my %old_cats       = map { $_ => 1 } @old_cats;
    my @added_cats     = grep { !$old_cats{$_} } @new_cats;
    my @unchanged_cats = grep {  $old_cats{$_} } @new_cats; 

    # if user changed slug...
    my $old_slug      = $story->slug || '';
    my $new_slug      = $query->param('slug') || '';
    if ($new_slug ne $old_slug) {
      
      # is new slug valid? will it build unique URLs with the unchanged categories?
      if (!$self->process_slug_input(slug => $new_slug, 
				     story => $story,
				     categories => \@unchanged_cats)) {
	add_alert('new_slug_prevented_category_change');
	return 0;
      }
    }
    
    # slug is safe on current cats, so now let's try the new cats
    eval { $story->categories(@new_cats) };
    if (!$@) {

      # success!
      return 1;

    } else {

      # failure...
      if (ref($@) and $@->isa('Krang::Story::DuplicateURL')) {    

	$self->alert_duplicate_url(error => $@, class => $story->class, added_cats => \@added_cats);
	eval { $story->categories(@old_cats) };
	
	# if slug has changed, even the old categories may fail...
	if (@$ && ($new_slug ne $old_slug)) {
	  $story->slug($old_slug);           # revert slug just long
	  $story->categories(@old_cats);     # enough to load old URLs
	  $story->slug($new_slug);           # and return user to Edit
	}
	
	# in either case - return failure
	return 0;
      } else { 
	die ($@); 
      }
    }
}

sub process_category_input {

    my ($self, %args) = @_;
    my $type   = $args{type};
    my $class  = pkg('ElementLibrary')->top_level(name => $type);
    my $cat_id = $args{category_id};

    if ($class->category_input eq 'prohibit') {
        # this type doesn't allow manual selection for category, so auto-select
        return $class->auto_category_ids(%args);
    } elsif ($cat_id) {
        # user made a manual selection for category, so validate it
        my ($category) = pkg('Category')->find(category_id => $cat_id);
        my $validate = $class->validate_category(category => $category, %args);
        if ($validate == 1) {
            # a return code of 1 means success
            return $cat_id; 
        } else {
            # anything else is an error passed on to the user
            add_alert('bad_category', explanation => $validate || '');
            return;
        }
    } else {
        # user left category blank
        if ($class->category_input eq 'require') {
            # and this type requires manual selection
            add_alert('missing_category');
            return;
        } else {
            # and this type autoselects category when blank
            return $class->auto_category_ids(%args);
        }
    }
}


sub process_slug_input {

    my ($self, %args) = @_;

    my $slug       = $args{slug};       
    my $story      = $args{story};        
    my $type       = $args{type} || ($story && $story->class->name);
    my $cat_idx    = $args{cat_idx};    
    my @categories = $args{categories} && @{$args{categories}}; 
    
    my $slug_entry_for_type = pkg('ElementLibrary')->top_level(name => $type)->slug_use();
    my $slug_required       = ($slug_entry_for_type eq 'require');
    my $slug_optional       = (($slug_entry_for_type eq 'encourage') || ($slug_entry_for_type eq 'discourage'));

    if (length $slug && $slug !~ /^[-\w]+$/) {
	add_alert('bad_slug');
	return 0;
    } elsif ($slug_required && !$slug) {
	add_alert('missing_slug');
	return 0;
    } elsif ($slug_optional && !$slug && defined $cat_idx && !$cat_idx) { # New Story cat-idx check 
	add_alert('no_slug_no_cat_idx');
	return 0;
    } elsif ($story && ($story->slug ne $slug)) {

      # and if we've been given categories to check against new slug...
      if (@categories) {
	
	# store old slug/categories in case we need to revert
	my $old_slug = $story->slug;         
	my @old_cats = $story->categories;   
	
        # try out new slug on category list to see if it causes any dupes
	$story->slug($slug); 
        eval { $story->categories(@categories) };
        if ($@ and ref($@) and $@->isa('Krang::Story::DuplicateURL')) {
	  $self->alert_duplicate_url(error => $@, class => $story->class);
	  $story->slug($old_slug);       
	  $story->categories(@old_cats); 
	  return 0;
	} elsif ($@) {
	  die ($@);
	}
      } else {
	# even if we're not checking categories, update slug
	$story->slug($slug); 
      }
    }
    # success
    return 1; 
}

sub alert_duplicate_url {

    my ($self, %args) = @_;

    my $class      = $args{class};
    my $error      = $args{error};
    my $added_cats = $args{added_cats};

    # if we're adding a category, get its URL
    # (currently GUI only allows one add at a time)
    my $new_cat = $added_cats && $added_cats->[0]->url; 
    
    # figure out how our story builds its URL (to remind user)
    my $attribs = localize(join(', ', $class->url_attributes));
    my $url_attributes = $attribs
                       ? $attribs . localize(' and site/category')
	               : localize('site/category');

    # find clashing stories/categories, and add alert
    if ($error->stories) {

      # dupe story alerts get a special easily-readable table of IDs/URLs; we build the rows here
      my $dupes = join ('', map { sprintf(qq{<tr>  <td> %d </td>  <td> <a href="%s" target='_blank'>%s</a> </td>  </tr>},
					  $_->{id}, 'http://'.$_->{url}, $_->{url}) } @{$error->stories});
      # and we throw (using $s for plural messages, $q for quotes, $f for form)...
      my $s = @{$error->stories} > 1 ? 's' : '';
      my $f = $self->query->param('returning_from_root') ? 'edit' : 'new_story';
      add_alert('duplicate_url_table', dupe_rows => $dupes, q => '"', form => $f);
    
      # message differs slightly when dupe is caused by adding a new category 
      $new_cat ?
	 add_alert('duplicate_url_on_add_cat', cat        => $new_cat) : 
         add_alert("duplicate_url$s",          attributes => $url_attributes);

      # finally, store dupes & query in session hash in case a subsequent replace_dupes() needs them
      $session{KRANG_PERSIST}{DUPE_STORIES}->{DUPES} = $error->stories;
      $session{KRANG_PERSIST}{DUPE_STORIES}->{QUERY} = { map { $_ => $self->query->param($_) } $self->query->param };
      
    } elsif ($error->categories) {

      # a simpler, non-overwritable alert is thrown when a story URL conflicts with a category...
      $new_cat ?
        add_alert('category_has_url_on_add_cat',
		  id         => $error->categories->[0]->{id},   # adding a cat can cause at
		  url        => $error->categories->[0]->{url},  # most one new duplicate URL
  		  cat        => $new_cat) :
	add_alert('category_has_url',
		  ids        => join(' and Category ', map { $_->{id} }  @{$error->categories}),
		  urls       => join(', ', map { $_->{url} } @{$error->categories}),
		  s          => @{$error->categories} > 1  ? 's' : '',  # plural
  		  attributes => $url_attributes); 
    } else {
      croak ("DuplicateURL didn't include stories OR categories");
    }

    return 1;
}

sub make_sure_story_is_still_ours {

    my ($self) = @_;

    # grab story from session hash
    if (!$session{story}) {
       croak("Unable to load story from session!")
    } else {
       my $story_id = $session{story}->story_id;
       return 1 unless $story_id;
    
       # look up actual story in database to make sure it's still ours
       my ($story) = pkg('Story')->find(story_id => $story_id);
       if (!$story) {
   	   clear_messages(); clear_alerts(); 
	   add_alert('story_deleted_during_edit', id => $story_id);
       } elsif (!$story->checked_out) {
	   clear_messages(); clear_alerts(); 
	   add_alert('story_checked_in_during_edit', id => $story_id);
       } elsif ($story->checked_out_by ne $ENV{REMOTE_USER}) {
	   my ($thief) = pkg('User')->find(user_id => $story->checked_out_by);
	   my $thief_name = CGI->escapeHTML($thief->first_name.' '.$thief->last_name);	
	   clear_messages(); clear_alerts(); 
	   add_alert('story_stolen_during_edit', id => $story_id, thief => $thief_name);
       } elsif ($story->version > $session{story}->version) {
           clear_messages; clear_alerts();
           add_alert('story_saved_in_other_window', id => $story_id);
       } else {
           # story is still ours
	   return 1; 
       }
    }
    
    # story is no longer ours! return FALSE and go to workspace
    $self->header_props(-uri=>"workspace.pl");
    $self->header_type('redirect');
    return 0;
}

1;

=back

=cut

