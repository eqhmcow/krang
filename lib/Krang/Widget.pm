package Krang::Widget;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Carp qw(croak);
use CGI;
use File::Spec::Functions qw(catfile);
use HTML::PopupTreeSelect::Dynamic;
use Krang::ClassLoader 'Category';
use Krang::ClassLoader 'HTMLTemplate';
use Krang::ClassLoader 'Info';
use Krang::ClassLoader Conf         => qw(KrangRoot BrowserSpeedBoost);
use Krang::ClassLoader DB           => qw(dbh);
use Krang::ClassLoader Log          => qw(debug info);
use Krang::ClassLoader Message      => qw(add_alert);
use Krang::ClassLoader Session      => qw(%session);
use Krang::ClassLoader Localization => qw(localize);

use Text::Wrap qw(wrap);
use Time::Piece qw(localtime);
use File::Spec::Functions qw(catdir);

use base 'Exporter';
our @EXPORT_OK = qw(
  category_chooser
  category_chooser_object
  time_chooser
  decode_time
  date_chooser
  datetime_chooser
  decode_date
  decode_datetime
  format_url
  template_chooser
  template_chooser_object
  autocomplete_values
);

=head1 NAME

Krang::Widget - interface widgets for use by Krang::CGI modules

=head1 SYNOPSIS

  use Krang::ClassLoader Widget => qw(category_chooser date_chooser decode_date);

  $chooser = category_chooser(name => 'category_id',
                              query => $query);

  $date_chooser = date_chooser(name => 'cover_date',
                               date=>$date_obj);

  $date_obj = decode_date(name => 'cover_date',
                          query => $query);

  # event handler as HTML attribute is deprecated
  $url_html = format_url(url => 'http://my.host/some/long/url.html',
                         linkto => "javascript:Krang.preview('media','" . $id . "')");

  # make DOM2 event handler instead, see the behaviors
  # 'media-preview-link' and 'story-preview-link' in
  # F<htdocs/js/krang.js>
  #
  # For media
  $url_html = format_url(url   => 'http://my.host/some/long/media.html',
                         class => 'media-preview-link',
                         name  => 'media_$id');

  # For stories
  $url_html = format_url(url   => 'http://my.host/some/long/media.html',
                         class => 'story-preview-link',
                         name  => 'story_$id');


=head1 DESCRIPTION

This modules exports a set of generally useful CGI widgets.

=head1 INTERFACE

=over 4

=item $chooser_html = category_chooser(name => 'category_id', query => $query)

=item ($chooser_interface, $chooser_html) = template_chooser(name => 'category_id', query => $query);

In scalar context returns a block of HTML implementing the standard Krang category
chooser.

In list context returns the chooser interface (show button, clear
button, display of selected element) separately.

Available parameters are as follows:

=over

=item name (required)

Unique name of the chooser.  If you have multiple
choosers on the same page then they must have different
names.  Must be alphanumeric.

=item query (required)

The CGI.pm query object for this request.

=item field   

The form field which will be set to the category_id of the
choosen category.  Defaults to the value set for C<name>
if not set.

=item site_id 

If specified, chooser will limit selection to only
this site and its descendant categories.

=item onchange

can be set to the name of a JavaScript function
that will be called when the user picks a category.  

=item label   

change the label on the button which defaults to 'Choose'. 

=item display 

setting to false will supress displaying the chosen 
category URL next to the button.

=item formname

the name of the form in which the chooser appears.  If 
not specified, will default to the first form in your 
HTML document.

=item title   

the title on the chooser window.  Defaults to 'Choose a 
Category'.

=item may_see 

Hide categories which are hidden to the current user.
Defaults to 1.

=item may_edit

Hide categories which are read-only to the current user.
Defaults to 0.

=item persistkey

Hash key that indicates where in the session hash to
look for a pre-existing value.

=item allow_clear

Shows a button labeled 'Clear' that allows a user to undo
their choice. Defaults to true.

=back

The template for the category chooser is located in
F<Widget/category_chooser.tmpl>.

=cut

sub category_chooser {
    my %args = @_;
    my ($name, $query, $display, $onchange, $formname, $field, $persistkey) =
      @args{qw(name query display onchange formname field persistkey)};
    croak("Missing required args: name and query")
      unless $name and $query;

    # field defaults to name
    $field ||= $name;

    # allow_clear defaults to true
    my $allow_clear = exists $args{allow_clear} ? $args{allow_clear} : 1;

    my $chooser = category_chooser_object(%args);

    # if we didn't get a choose it's cause there are no categories to choose from
    if (!$chooser) {
        add_alert('no_categories_for_chooser');
        return "No categories are defined.";
    }

    my $template = pkg('HTMLTemplate')->new(
        path              => [catdir('Widget', $session{language}), 'Widget'],
        filename          => 'category_chooser.tmpl',
        cache             => 1,
        die_on_bad_params => 1,
    );
    $formname   ||= '';
    $name       ||= '';
    $persistkey ||= '';

    my $category_id =
      defined $query->param($field) ? $query->param($field)
      : $persistkey
      ? $session{KRANG_PERSIST}{$persistkey}{'cat_chooser_id_' . $formname . "_" . $name}
      : 0;

    my ($cat) = pkg('Category')->find(category_id => $category_id);

    if ($cat) {
        $template->param(category_id  => $category_id);
        $template->param(category_url => $cat->url);
    }

    # send data to the template
    $template->param(
        name        => $name,
        field       => $field,
        display     => defined $display ? $display : 1,
        formname    => $formname,
        onchange    => $onchange,
        allow_clear => $allow_clear,
    );

    my ($show_button, $chooser_html) = $chooser->output();

    return wantarray
      ? ($show_button . $template->output(), $chooser_html)
      : ($show_button . $template->output() . $chooser_html);
}

=item $chooser = category_chooser_object(name => 'category_id', query => $query)

Creates and returns an L<HTML::PopupTreeSelect::Dynamic> object for
use with categories. This is used to create the HTML for the original
widget and to dynamically supply the limbs of the tree on demand in
AJAX requests.

Available parameters are as follows:

=over

=item name (required)

Unique name of the chooser.  If you have multiple
choosers on the same page then they must have different
names.  Must be alphanumeric.

=item query (required)

The CGI.pm query object for this request.

=item label   

change the label on the button which defaults to 'Choose'. 

=item field   

The form field which will be set to the category_id of the
choosen category.  Defaults to the value set for C<name>
if not set.

=item site_id 

If specified, chooser will limit selection to only
this site and its descendant categories.

=item title   

the title on the chooser window.  Defaults to 'Choose a 
Category'.

=item may_see 

Hide categories which are hidden to the current user.
Defaults to 1.

=item may_edit

Hide categories which are read-only to the current user.
Defaults to 0.

=item persistkey

Hash key that indicates where in the session hash to
look for a pre-existing value.

=back

=cut 

sub category_chooser_object {
    my %args = @_;
    my ($name, $query, $label, $formname, $site_id, $field, $title, $may_see, $may_edit,
        $persistkey) = @args{
        qw(name query label formname site_id
          field title may_see may_edit persistkey)
      };

    croak("Missing required args: query") unless $query;

    $name ||= $query->param('name');
    croak("Missing required args: name") unless $name;

    # field defaults to name
    $field ||= $name;

    # may_see is on by default
    $may_see = 1 unless defined $may_see;

    $formname   ||= '';
    $name       ||= '';
    $persistkey ||= '';

    $session{KRANG_PERSIST}{$persistkey}{'cat_chooser_id_' . $formname . "_" . $name} =
      $query->param($field)
      if defined($query->param($field));

    # setup category loop
    my %find_params = ();
    $find_params{site_id}  = $site_id if ($site_id);
    $find_params{may_see}  = 1        if $may_see;
    $find_params{may_edit} = 1        if $may_edit;

    # get list of all cats
    my @cats = pkg('Category')->find(%find_params);

    # if there are no cats then there can't be any chooser
    return unless @cats;

    # we used to sort on url in find, but the trailing slash would screw up
    # the order of directories named numerically (e.g. 7 would come after 7.10)
    @cats = sort { substr($a->url, 0, -1) cmp substr($b->url, 0, -1) } @cats;

    # build up data structure used by HTML::PopupTreeSelect::Dynamic
    my $data = {children => [], label => "", open => 1};
    my %nodes;
    while (@cats) {
        my $cat = shift @cats;

        my $parent_id = $cat->parent_id;
        my $parent_node = $parent_id ? $nodes{$parent_id} : $data;

        # maybe they don't have permissions to the parent, so it
        # wasn't returned from the initial find().  Fill it in
        # deactivated.
        unless ($parent_node) {
            unshift(@cats, $cat);
            unshift(@cats, pkg('Category')->find(category_id => $parent_id));
            $cats[0]->{_inactive} = 1;
            next;
        }

        push(
            @{$parent_node->{children}},
            {
                label => ($cat->dir eq '/' ? $cat->url : $cat->dir),
                value    => $cat->category_id . "," . $cat->url,
                children => [],
                ($cat->{_inactive} ? (inactive => 1) : ()),
            }
        );
        $nodes{$cat->category_id} = $parent_node->{children}[-1];
    }

    # build the chooser
    return HTML::PopupTreeSelect::Dynamic->new(
        name                => $name,
        title               => $title || localize('Choose a Category'),
        data                => $data->{children},
        image_path          => pkg('Widget')->_img_prefix() . 'images',
        onselect            => $name . '_choose_category',
        hide_root           => 1,
        button_label        => $label || localize('Choose'),
        include_css         => 0,
        width               => 225,
        height              => 200,
        resizable           => 1,
        dynamic_url         => $query->url(-absolute => 1),
        dynamic_params      => "rm=category_chooser_node&name=${name}",
        include_prototype   => 0,
        include_full_js     => 0,
        separate_show_bnt   => 1,
        ok_button_label     => ' ' . localize('Ok') . ' ',
        cancel_button_label => localize('Cancel'),

        # The following is just for documentation purposes
        # In our Krang installation the alert message is part
        # of htdocs/js/popup_tree_select.js
        # alert => localize('Please select an item or click Cancel to cancel selection.'),
    );
}

=item $chooser_html = time_chooser(name => 'time', query => $query)

Returns a block of HTML implementing the standard Krang time
chooser.  The C<name> and C<query> parameters are required.

Additional optional parameters are as follows:

  hour      - if set (in 24 hour format, i.e. 0-23) , chooser will
              be prepopulated with that hour.  If not set,
              will default to current hour (localtime)
              unless "nochoice" is true, in which case chooser
              will be set to blank ('Hour').

  minute    - if set, chooser will be prepopulated with that
              minute.  If not set, will default to current
              minute (from localtime) unless "nochoice" is 
              true, in which chooser will be set to blank ('Minute').

  nochoice  - if set to a true value, Hour/Minute/AM
              will be provided as default choices in the chooser.
              The value "0" will be returned if a user chooses
              the "no choice" option.

  onchange  - JavaScript code to be executed when the date is changed.

The time_chooser() implements itself in HTML via a text input with some
JavaScript popup magic. The string input from the user can be retrieved
via the CGI query object using the same name given during the creation
of the widget.

=cut

sub time_chooser {
    my %args = @_;
    my ($name, $query, $hour, $minute, $nochoice, $onchange) =
      @args{qw(name query hour minute nochoice onchange)};
    croak("Missing required args: name and query")
      unless $name and $query;

    # pull the time from the query first, then from given hour/minute and
    # finally from localtime
    my $value;
    if ($query->param($name)) {
        ($hour, $minute) = decode_time(name => $name, query => $query);
        $value = $query->param($name);
    } else {
        unless ($nochoice) {
            my $current_date = localtime();
            $hour   = $current_date->hour   unless defined $hour;
            $minute = $current_date->minute unless defined $minute;
        }
    }

    # hours running from 1-12 or 0-23
    my $use_ampm_time = localize('AMPM');

    my @hours = (1 .. 12);

    if ($use_ampm_time) {
        my $ampm = $hour && $hour >= 12 ? 'PM' : 'AM';
        $hour = $hour && $hour >= 13 ? $hour - 12 : $hour;
        $hour = 12 if defined $hour && $hour == 0;
        $value ||=
          (defined $hour && defined $minute) ? sprintf('%i:%02i %s', $hour, $minute, $ampm) : "";
    } else {
        $value ||= (defined $hour && defined $minute) ? sprintf('%i:%02i', $hour, $minute) : "";
        @hours = (0 .. 23);
    }

    # an image src prefix for caching
    my $img_prefix = pkg('Widget')->_img_prefix();

    # inform Krang.Widget about time format
    my $js_use_ampm_time = $use_ampm_time ? 'true' : 'false';

    # localize some
    my $Hour   = localize('Hour');
    my $Minute = localize('Minute');

    # setup the onchange
    $onchange ||= '';
    my $onchange_attr = $onchange ? qq/ onchange="$onchange"/ : '';
    my $html = qq|
        <input id="$name" name="$name" value="$value" size="9"$onchange_attr class="time_chooser">
        <img alt="" src="${img_prefix}images/clock.gif" id="${name}_trigger" class="clock_trigger">
        <div id="${name}_clock" class="clock_widget" style="display:none">
            <select name="${name}_hour" onchange="Krang.Widget.update_time_chooser('$name', $js_use_ampm_time); $onchange" 
                class="time_chooser" disabled>
                <option value="">$Hour</option> |
      . join(' ', map { qq|<option value="$_">$_</option>| } @hours) . qq|
            </select>
            :
            <select name="${name}_minute" onchange="Krang.Widget.update_time_chooser('$name', $js_use_ampm_time); $onchange" 
                class="time_chooser" disabled>
                <option value="">$Minute</option> |
      . join(' ',
        map { qq|<option value="$_">$_</option>| }
          ('00', '01', '02', '03', '04', '05', '06', '07', '08', '09', 10 .. 59))
      . qq|</select>|;

    if ($use_ampm_time) {
        $html .= qq|
            &nbsp;
            <select name="${name}_ampm" onchange="Krang.Widget.update_time_chooser('$name', $js_use_ampm_time); $onchange" 
                class="time_chooser" disabled>
                <option value="AM">AM</option> <option value="PM">PM</option>
            </select>|;
    }

    $html .= qq|
        </div>
        <script type="text/javascript">
        Krang.onload( function() { Krang.Widget.time_chooser( '$name', $js_use_ampm_time ); } );
        </script>
    |;

    return $html;
}

=item $date_obj = decode_time(name => 'daily_time', query => $query)

Reads CGI data submitted via a standard Krang time_chooser
and returns 2 integers representing the hour and minute
that were selected.

If decode_time() is unable to parse the time it will return 2
undef values.

Standard Krang time choosers can be created via C<time_chooser()>.

=cut

sub decode_time {
    my %args = @_;
    my ($name, $query) = @args{qw(name query)};
    croak("Missing required args: name and query")
      unless $name and $query;

    my $value = $query->param($name);
    my ($hour, $minute, $ampm);
    if ($value && $value =~ /^(\d+):(\d+)\s?(am|pm)$/i) {
        $hour   = $1;
        $minute = $2;
        $ampm   = $3 ? uc($3) : '';

        if ($hour == 12 and $ampm eq 'AM') {
            $hour = 0;
        } elsif ($hour != 12 and $ampm eq 'PM') {
            $hour += 12;
        }
    }
    return ($hour, $minute);
}

=item $chooser_html = datetime_chooser(name => 'date', query => $query)

Returns a block of HTML implementing the standard Krang datetime
chooser.  The C<name> and C<query> parameters are required.

Additional optional parameters are as follows:

  date      - if set to a date object (Time::Piece), chooser will
              be prepopulated with that datetime.  If not set to a
              date object, will default to current date (localtime)
              unless "nochoice" is true, in which case chooser
              will be set to blank. Please note that seconds are
              ALWAYS set to '00', regardless of what seconds may
              actually be.

  nochoice  - if set to a true value, Month/Day/Year/Hour/Minute/AM
              will be provided as default choices in the chooser.
              Used in conjunction with the "date" parameter, the
              chooser may be set to default to no date.
              The value "0" will be returned if a user chooses
              the "no choice" option.

  onchange  - JavaScript code to be executed when either the date
              or time values are changed.

The C<datetime_chooser()> implements via the C<date_chooser()>
and C<time_chooser()>. The values input by the user can be retrieved
via C<decode_datetime()>.

=cut

sub datetime_chooser {
    my %args = @_;
    croak("Missing required args: name and query") unless $args{name} and $args{query};

    # get the first part from the date_chooser
    my $html = date_chooser(%args);
    $html .= '&nbsp;';

    # and get the 2nd part from the time_chooser
    my $date   = $args{date};
    my $hour   = $date ? $date->hour : undef;
    my $minute = $date ? $date->minute : undef;
    $html .= time_chooser(
        %args,
        name   => $args{name} . '_time',
        hour   => $hour,
        minute => $minute,
    );
    return $html;
}

=item $chooser_html = date_chooser(name => 'cover_date')

Returns a block of HTML implementing the standard Krang date
chooser.  The C<name> and C<query> parameters are required.

Additional optional parameters are as follows:

  date      - if set to a date object (L<Time::Piece> or L<DateTime>), 
              chooser will be prepopulated with that date. If not set 
              to a date object, will default to current date (localtime) 
              unless "nochoice" is true, in which case chooser will be 
              set to blank.

  nochoice  - if set to a true value, blanks will be provided
              as choices in the chooser.  Used in conjunction
              with the "date" parameter, the chooser may be
              set to default to no date.

              The value "0" will be returned if a user chooses
              the "no choice" option.

  onchange  - JavaScript code to be executed when the date value
              is changed.


The date_chooser() implements itself in HTML via a text input
with a JavaScript popup calendar. The full string typed by the
user can be retrieved via the CGI object, or you can retrieve
a L<Time::Piece> object via C<decode_date()>.

=cut

sub date_chooser {
    my %args = @_;
    my ($name, $date, $query, $nochoice, $onchange) = @args{qw(name date query nochoice onchange)};
    croak("Missing required args: name and query") unless $name and $query;

    my $date_format = localize('%m/%d/%Y');

    # look for the date in query first
    if ($query->param($name)) {
        $date = $query->param($name);
    } else {

       # Set date to today if it is NOT already set, AND if we do not allow "no choice"
        $date ||= localtime() unless ($nochoice);
        $date = $date ? $date->strftime($date_format) : '';
    }

    # setup the default onchange value
    $onchange = $onchange ? qq/ onchange="$onchange"/ : '';

    my $img_prefix = pkg('Widget')->_img_prefix();
    return qq|
        <input id="$name" name="$name" value="$date" size="11"$onchange class="date_chooser">
        <img alt="" src="${img_prefix}images/calendar.gif" id="${name}_trigger" class="calendar_trigger">
        <script type="text/javascript">
        Krang.onload( function() { Krang.Widget.date_chooser( '$name', '$date_format' ); } );
        </script>
    |;

}

=item $datetime_object = decode_date(name => 'cover_datetime', query => $query)

Reads CGI data submitted via a standard Krang datetime chooser
and returns a datetime object (Time::Piece).  The C<name> and C<query>
parameters are required.

If decode_datetime() is unable to retrieve a date it will return undef.

Standard Krang datetime choosers can be created via datetime_chooser().

If 'no_time_is_end' is set to 1, then datetimes with no Hour/Min/Sec
will translate to date:23:59:59 (defualt is to date:00:00:00)

=cut

sub decode_datetime {
    my %args = @_;
    my ($name, $query) = @args{qw(name query)};
    my $ntie = $args{no_time_is_end} || 0;

    croak("Missing required args: name and query")
      unless $name and $query;

    my $date = $query->param($name);
    my $time = $query->param($name . '_time');
    $time = '11:59 PM' if !$time && $ntie;
    my $format = '%m/%d/%Y';

    if ($date && $time) {
        $format .= ' %I:%M %p';
        $date = "$date $time";
    }

    if ($date) {
        my $piece;
        eval { 
            $piece = Time::Piece->strptime($date, localize($format)); 
            # triggers internal methods of Time::Piece that might be broken with bad dates
            if($piece) { }; 
        };
        return $piece unless $@;
    }
    return;
}

=item $date_obj = decode_date(name => 'cover_date', query => $query)

Reads CGI data submitted via a standard Krang date chooser
and returns a date object (Time::Piece).  The C<name> and C<query> 
parameters are required.

If decode_date() is unable to retrieve a date it will return undef.

Standard Krang date choosers can be created via date_chooser().

=cut

sub decode_date {
    my %args = @_;
    my ($name, $query) = @args{qw(name query)};
    croak("Missing required args: name and query")
      unless $name and $query;

    if (my $date = $query->param($name)) {
        my $piece;
        eval { 
            $piece = Time::Piece->strptime($date, localize('%m/%d/%Y'));
            # triggers internal methods of Time::Piece that might be broken with bad dates
            if($piece) { };
        };
        return $piece unless $@;
    }
    return;
}

=item $url_html = format_url(url => 'http://my.host/url.html', linkto => 'url.html', length => 15);

Returns a block of HTML implementing the standard Krang url
display/link style.  The C<url> parameter is required.

The optional C<linkto> parameter, if provided, will be used as
the HTML "href" to which users are directed when they click 
any line in the URL.  If not specified, the URL will be 
displayed as non-linking HTML.

The optional C<length> parameter, if provided, will be used 
as number of characters after which a new line should be 
created.  If not specified, the default length of 15 will be used.

The optional C<new_window> parameter, when combined with the C<linkto>
parameter will open the link in a new window/tab.


=cut

sub format_url {
    my %args = @_;

    # Validate calling input
    my ($url, $linkto, $length, $name, $class, $new_window) =
      @args{qw/url linkto length name class new_window/};
    croak("Missing required argument 'url'") unless ($url);

    $length = 15 unless ($length);

    # wrap URL to length using Text::Wrap
    $Text::Wrap::columns = $length;

    $url =~ s/ /\0/g; # change spaces to null bytes so wrap() won't destroy them
    $url =~ s!/!/ !g; # put spaces after /'s so that wrap() can use them for breaks
    $url = wrap("", "", $url);
    $url =~ s!/ !/!g;
    $url =~ s/\0/&nbsp;/g; # translate real spaces (that are now null bytes) into &nbsp

    # format wrapped URL in HTML
    my $format_url_html;
    my @url_lines = split("\n", $url);
    my $wbr = '<wbr><span class="wbr"></span>';
    if ($linkto) {
        # URL with links
        my $target = $new_window ? ' target="_blank"' : '';
        $format_url_html = qq{<a href="$linkto"$target>} . join($wbr, @url_lines) . qq{</a>};
    } elsif ($name) {
        # DOM2 event handling
        $format_url_html = qq{<a href="" name="$name" class="$class">} . join($wbr, @url_lines) . qq{</a>};
    } else {
        # URL without links
        $format_url_html = join($wbr, @url_lines);
    }

    return $format_url_html;
}

=item $chooser_html = template_chooser(name => 'category_id', query => $query)

=item ($chooser_interface, $chooser_html) = template_chooser(name => 'category_id', query => $query);

In scalar context returns a block of HTML implementing the standard Krang template
chooser.

In list context returns the chooser interface (show button, clear
button, display of selected element) separately.

Available parameters are as follows:

=over

=item name (required)

Unique name of the chooser.  If you have multiple choosers on the same
page then they must have different names.  Must be alphanumeric.

=item query (required)

The CGI.pm query object for this request.

=item field

The form field which will be set to the template_id of the choosen
category.  Defaults to the value set for C<name> if not set.

=item onchange

Can be set to the name of a JavaScript function that will be called when
the user picks a category.

=item label

Change the label on the button which defaults to 'Choose'.

=item display

Setting to false will supress displaying the chosen template name next
to the button.

=item formname

The name of the form in which the chooser appears.  If not specified,
will default to the first form in your HTML document.

=item title

The title on the chooser window.  Defaults to 'Choose a Template'.

=item persistkey

Hash key that indicates where in the session hash to look for a
pre-existing value.

=back

The template for the category chooser is located in
F<Widget/template_chooser.tmpl>.

=cut

sub template_chooser {
    my %args = @_;
    my ($name, $query, $display, $onchange, $formname, $field, $persistkey) = @args{
        qw(name query display onchange formname
          field title persistkey)
      };

    croak("Missing required args: name and query")
      unless $name and $query;

    my $template = pkg('HTMLTemplate')->new(
        path              => [catdir('Widget', $session{language}), 'Widget'],
        filename          => 'template_chooser.tmpl',
        cache             => 1,
        die_on_bad_params => 1,
        loop_context_vars => 1,
    );

    # field defaults to name
    $field      ||= $name;
    $formname   ||= '';
    $name       ||= '';
    $persistkey ||= '';

    # pass the element name around in advanced search
    my $element_name = $query->param($field)
      || $session{KRANG_PERSIST}{$persistkey}{'tmpl_chooser_id_' . $formname . "_" . $name}
      || '';

    $session{KRANG_PERSIST}{$persistkey}{'tmpl_chooser_id_' . $formname . "_" . $name} =
      $query->param($field)
      if defined($query->param($field));

    $template->param(element_class_name => $element_name);

    # build the chooser
    my $chooser = template_chooser_object(%args);

    # send data to the template
    $template->param(
        name     => $name,
        field    => $field,
        display  => defined $display ? $display : 1,
        formname => $formname,
        onchange => $onchange
    );

    my ($show_button, $chooser_html) = $chooser->output();

    return wantarray
      ? ($show_button . $template->output(), $chooser_html)
      : ($show_button . $template->output() . $chooser_html);
}

=item $chooser = template_chooser_object(name => 'category_id', query => $query)

Creates and returns an L<HTML::PopupTreeSelect::Dynamic> object for
use with templates. This is used to create the HTML for the original
widget and to dynamically supply the limbs of the tree on demand in
AJAX requests.

Available parameters are as follows:

=over

=item name (required)

Unique name of the chooser.  If you have multiple choosers on the same
page then they must have different names.  Must be alphanumeric.

=item query (required)

The CGI.pm query object for this request.

=item label

Change the label on the button which defaults to 'Choose'.

=item title

The title on the chooser window.  Defaults to 'Choose a Template'.

=back

=cut

sub template_chooser_object {
    my %args = @_;
    my ($name, $query, $label, $title) = @args{qw(name query label title)};

    croak("Missing required arg: query") unless $query;

    $name ||= $query->param('name');
    croak("Missing required arg: name") unless $name;

    # get element names
    my @elements = map { [pkg('ElementLibrary')->top_level(name => $_) => ''] }
      reverse pkg('ElementLibrary')->top_levels;

    # get existing templates
    my %exists = map { s/\.tmpl//; $_ => 1 }
      map { $_->filename } pkg('Template')->find;

    # root node
    my $data = {children => [], label => '', open => 1};

    # build element tree
    while (@elements) {
        my ($class, $parent) = @{pop(@elements)};
        my $parent_node = $parent ? $parent : $data;
        my $element = $class->name;

        # elements for which a template already exists are colored in green
        if ($exists{$element}) {
            $element = '<span class="tmpl_chooser_has_template">' . $class->name . '</span>';
        }

        my $child = {
            label    => $element,
            value    => $class->name,
            children => [],
        };

        push @{$parent_node->{children}}, $child;

        if (my @children = $class->children) {
            push(@elements, map { [$_ => $child] } sort { $b->name cmp $a->name } @children);
        }
    }

    # build the chooser, taking care of localizing the buttons and the title
    return HTML::PopupTreeSelect::Dynamic->new(
        name                => $name,
        title               => $title || localize('Choose a Template'),
        data                => $data->{children},
        image_path          => pkg('Widget')->_img_prefix() . 'images',
        onselect            => $name . '_choose_template',
        button_label        => $label || localize('Choose'),
        include_css         => 0,
        width               => 225,
        height              => 200,
        resizable           => 1,
        dynamic_url         => $query->url(-absolute => 1),
        dynamic_params      => "rm=template_chooser_node&name=${name}",
        include_prototype   => 0,
        include_full_js     => 0,
        separate_show_btn   => 1,
        ok_button_label     => ' ' . localize('Ok') . ' ',
        cancel_button_label => localize('Cancel'),

        # The following is just for documentation purposes
        # In our installation the alert message is part
        # of htdocs/js/popup_tree_select.js
        # alert => localize('Please select an item or click Cancel to cancel selection.'),
    );
}

=item $values = autocomplete_values(%args)

Returns an arrayref of alphabetized "words" that begin with the
given C<phrase>, pulled from the specifed C<fields> of the 
given C<table>.

It takes the following named arguments:

=over

=item table

The database table to use for the lookup.
This is required.

=item fields

An array ref of field names in the database from which to fetch "words".
This is required.

=item phrase

The phrase typed by the user. If none is given it will be pulled from
the C<phrase> param of the query string.
This is optional.

=item no_split

By default after we find the matching entries we split them up 
into individual words. But sometimes it's useful to have the whole
phrase returned instead. Set this flag to true to accomplish this.
This is optional

=item no_anchor

By default we anchor the search for text that starts either at the beginning
of the string or at a word boundary. Specifiying this optional as true
will instead do something like C<"%PHRASE%"> instead.

=item dbh

The database handle to use. If none is provided it will default
to the normal Krang one for the current instance.
This is optional.

=item where

Any additional logic that will added the generated SQL's C<WHERE> clause
using C<AND>.

=item limit

A limit on the number of results to return at once. By default there is
no limit.

=back

=cut

sub autocomplete_values {
    my %args = @_;
    my ($phrase, $table, $fields, $dbh, $where, $no_split, $no_anchor, $limit) =
      @args{qw(phrase table fields dbh where no_split no_anchor limit)};
    $dbh ||= dbh();

    if (!$phrase) {
        my $cgi = CGI->new();
        $phrase = $cgi->param('phrase');
    }

    my ($pattern, $pattern_op);
    if ($no_anchor) {
        $pattern    = '%' . $phrase . '%';
        $pattern_op = 'LIKE';
    } else {
        $pattern    = '(^|[[:blank:]_.//])' . quotemeta($phrase);
        $pattern_op = 'REGEXP';
    }

    # query the db for these values
    my $sql =
        "SELECT "
      . join(', ', map { "`$_`" } @$fields)
      . " FROM `$table` WHERE ("
      . join(' OR ', map { "`$_` $pattern_op ?" } @$fields) . ')';
    $sql .= " AND $where" if $where;

    $sql .= " LIMIT $limit " if $limit;

    my $sth   = $dbh->prepare_cached($sql);
    my @binds = map { $pattern } @$fields;
    $sth->execute(@binds);

    # split into individual words and then sort
    my (@words, %seen);
    while (my $row = $sth->fetchrow_arrayref) {
        foreach my $pos (0 .. (scalar @$row - 1)) {
            my $answer = $row->[$pos];
            next unless $answer;

            if ($no_split) {
                push(@words, $answer) unless $seen{$answer};
                $seen{$answer} = 1;
            } else {

                # remove these characters
                $answer =~ s/['"\,:]//g;
                next unless $answer;

                # split on '_', \s, '/' or '.' to make words and only keep the ones that
                # start with our phrase
                foreach (split(/(?:_|\s|\/|\.)+/, $answer)) {
                    my $word    = $_;
                    if (index($word, $phrase) == 0) {
                        push(@words, $word) unless $seen{$word};
                        $seen{$word} = 1;
                    }
                }

                # if it has an '_' and no spaces, keep the whole word as well
                if ($answer =~ /_/ && $answer !~ /\s/ && (index($answer, $phrase) == 0)) {
                    push(@words, $answer) unless $seen{$answer};
                    $seen{$answer} = 1;
                }
            }
        }
    }

    my $html = '<ul>';
    foreach (sort @words) {
        s/</&lt;/g;
        s/&/&amp;/g;
        $html .= "<li>$_</li>";
    }
    return $html . '</ul>';
}

sub _img_prefix {
    return BrowserSpeedBoost
      ? '/static/' . pkg('Info')->install_id . '/'
      : '';
}

1;

=back
