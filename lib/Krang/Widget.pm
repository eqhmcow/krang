package Krang::Widget;
use strict;
use warnings;

use Carp qw(croak);
use Krang::HTMLTemplate;
use Time::Piece qw(localtime);
use Krang::Category;
use Krang::Conf qw(KrangRoot);
use Krang::Log qw(debug);
use HTML::PopupTreeSelect;
use Text::Wrap qw(wrap);
use Krang::Message qw(add_message);
use Krang::Session qw(%session);

use File::Spec::Functions qw(catfile);

use base 'Exporter';
our @EXPORT_OK = qw(category_chooser time_chooser date_chooser datetime_chooser decode_date decode_datetime format_url);

=head1 NAME

Krang::Widget - interface widgets for use by Krang::CGI modules

=head1 SYNOPSIS

  use Krang::Widget qw(category_chooser date_chooser decode_date);

  $chooser = category_chooser(name => 'category_id',
                              query => $query);

  $date_chooser = date_chooser(name => 'cover_date',
                               date=>$date_obj);

  $date_obj = decode_date(name => 'cover_date',
                          query => $query);

  $url_html = format_url(url => 'http://my.host/some/long/url.html',
                         linkto => "javascript:preview_media('". $id ."')" );

=head1 DESCRIPTION

This modules exports a set of generally useful CGI widgets.

=head1 INTERFACE

=over 4

=item $chooser_html = category_chooser(name => 'category_id', query => $query)

Returns a block of HTML implementing the standard Krang category
chooser.

Available parameters are as follows:

  name     - (required) Unique name of the chooser.  If you have multiple
             choosers on the same page then they must have different
             names.  Must be alphanumeric.

  query    - (required) The CGI.pm query object for this request.

  field    - The form field which will be set to the category_id of the
             choosen category.  Defaults to the value set for C<name>
             if not set.

  site_id  - If specified, chooser will limit selection to only
             this site and its descendant categories.

  onchange - can be set to the name of a javascript function
             that will be called when the user picks a category.  

  label    - change the label on the button which defaults to 'Choose'. 

  display  - setting to false will supress displaying the chosen 
             category URL next to the button.

  formname - the name of the form in which the chooser appears.  If 
             not specified, will default to the first form in your 
             HTML document.

  title    - the title on the chooser window.  Defaults to 'Choose a 
             Category'.

  may_see  - Hide categories which are hidden to the current user.
             Defaults to 1.

  may_edit - Hide categoriew which are read-only to the current user.
             Defaults to 0.

  persistkey - Hash key that indicates where in the session hash to
               look for a pre-existing value.

The template for the category chooser is located in
F<Widget/category_chooser.tmpl>.

=cut

sub category_chooser {
    my %args = @_;
    my ($name, $query, $label, $display, $onchange, $formname, $site_id, 
        $field, $title, $may_see, $may_edit, $persistkey) =
      @args{qw(name query label display onchange formname site_id 
               field title may_see may_edit persistkey)};
    croak("Missing required args: name and query")
      unless $name and $query;

    # field defaults to name
    $field ||= $name;

    # may_see is on by default
    $may_see = 1 unless defined $may_see;

    my $template = Krang::HTMLTemplate->new(filename => 
                                            "Widget/category_chooser.tmpl",
                                            cache   => 1,
                                            die_on_bad_params => 1,
                                           );

    $formname = '' if not $formname;
    $name = '' if not $name;
    my $category_id =
      $query->param($field) ||
        $session{KRANG_PERSIST}{$persistkey}{'cat_chooser_id_'.$formname."_".$name} || 0;

    $session{KRANG_PERSIST}{$persistkey}{'cat_chooser_id_'.$formname."_".$name} =
      $query->param($field) if defined($query->param($field));

    # setup category loop
    my %find_params = (order_by => 'url');
    $find_params{site_id} = $site_id if ($site_id);
    $find_params{may_see} = 1 if $may_see;
    $find_params{may_edit} = 1 if $may_edit;

    # get list of all cats
    my @cats = Krang::Category->find(%find_params);

    # if there are no cats then there can't be any chooser
    unless (@cats) {
        add_message('no_categories_for_chooser');
        return "No categories are defined.";
    }

    # build up data structure used by HTML::PopupTreeSelect
    my $data = { children => [], label => "", open => 1};
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
            unshift(@cats, Krang::Category->find(category_id => $parent_id));
            $cats[0]->{_inactive} = 1;
            next;
        }
            
        push(@{$parent_node->{children}}, 
             {
              label    => ($cat->dir eq '/' ? $cat->url : $cat->dir),
              value    => $cat->category_id . "," . $cat->url,
              children => [],
              ($cat->{_inactive} ? 
               (inactive => 1) : ()),
             });
        $nodes{$cat->category_id} = $parent_node->{children}[-1];

        if ($cat->category_id == $category_id) {
            $template->param(category_id => $category_id);
            $template->param(category_url => $cat->url);
        }
    }
    
    # build the chooser
    my $chooser = HTML::PopupTreeSelect->new(name       => $name,
                                             title      => $title || 'Choose a Category',
                                             data       => $data->{children},
                                             image_path => 'images',
                                             onselect   => $name . '_choose_category',
                                             hide_root  => 1,
                                             button_label => $label||'Choose',
                                             include_css => 0,
                                             width      => 225,
                                             height     => 200,
                                             hide_textareas => 1,
                                            );

    # send data to the template
    $template->param(chooser       => $chooser->output,
                     name          => $name,
                     field         => $field,
                     display       => defined $display ? $display : 1,
                     formname      => $formname,
                     onchange      => $onchange);

    return $template->output;
}

=item $chooser_html = time_chooser(name => 'time', query => $query)

Returns a block of HTML implementing the standard Krang datetime
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

The time_chooser() implements itself in HTML via three separate query
parameters.  They are named based on the provided name, plus "_hour",
"_minute", and "_ampm" respectively. CGI query data from 

=cut

sub time_chooser {
    my %args = @_;
    my ($name, $query, $hour, $minute, $nochoice) =
      @args{qw(name query hour minute nochoice)};
    croak("Missing required args: name and query")
      unless $name and $query;

    my $current_date = localtime();

    unless ($nochoice) {
        $hour = $hour ? $hour : $current_date->hour();
        $minute = $minute ? $minute : $current_date->minute();
    }
    my @hour_values = (1..12);
    my %hour_labels = ();
                                                                                
    my @minute_values = (0..59);
    my %minute_labels = ();
    $minute_labels{0} = '00';
    for (my $count = 0; $count <= 9; $count++) {
        $minute_labels{$count} = '0'.$count;
    }
    my @ampm_values = ('AM','PM');
    my %ampm_labels = (AM => 'AM', PM => 'PM');

    # set defaults
    if ($nochoice) {
        # Hour
        unshift(@hour_values, 0);
        $hour_labels{0} = 'Hour';
                                                                                
        # Minute
        unshift(@minute_values, 'undef');
        $minute_labels{undef} = 'Minute';
                                                                                
    }

    my $hour_12;
    if ($hour) {
        $hour_12 = ($hour >= 13) ? ($hour - 12) : $hour;    
    }
                                                                                
    my $h_sel = $query->popup_menu(-name      => $name .'_hour',
                                   -default   => ($hour) ? $hour_12 : 0,
                                   -values    => \@hour_values,
                                   -labels    => \%hour_labels,
                                  );
                                                                                
    my $min_sel = $query->popup_menu(-name      => $name .'_minute',
                                   -default   => ($minute) ? $minute : 'undef',
                                   -values    => \@minute_values,
                                   -labels    => \%minute_labels,
                                  );
                                                                                
    my $ampm = 'AM';
    if ($hour) {
        $ampm = 'PM' if ($hour >= 12);
    }
                                                                                
    my $ampm_sel = $query->popup_menu(-name      => $name .'_ampm',
                                   -default   => $ampm,
                                   -values    => \@ampm_values,
                                   -labels    => \%ampm_labels,
                                  );

    return $h_sel . "&nbsp;" . $min_sel . "&nbsp;" . $ampm_sel;
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

  onchange  - set this to a javascript function to run when the user
              makes a selection in any of the dropdowns.

The date_chooser() implements itself in HTML via six separate
query parameters.  They are named based on the provided name,
plus "_month", "_day", "_year", "_hour", "_minute", and 
"_ampm" respectively. CGI query data from
date_chooser can be retrieved and converted back into a date
object via decode_date().

=cut

sub datetime_chooser {
    my %args = @_;
    my ($name, $query, $date, $nochoice, $onchange) =
      @args{qw(name query date nochoice onchange)};
    croak("Missing required args: name and query")
      unless $name and $query;

    # Set date to today if it is NOT already set, AND if we do not allow "no choice"
    $date ||= localtime() unless ($nochoice);
                                                                                
    # Set up month input
    my @month_values = (1..12);
    my %month_labels = (
                        1  => 'Jan',
                        2  => 'Feb',
                        3  => 'Mar',
                        4  => 'Apr',
                        5  => 'May',
                        6  => 'Jun',
                        7  => 'Jul',
                        8  => 'Aug',
                        9  => 'Sep',
                        10 => 'Oct',
                        11 => 'Nov',
                        12 => 'Dec'
                       );
                                                                                
    my @day_values = (1..31);
    my %day_labels = ();
                                                                                    my @year_values = ((localtime()->year() - 10) .. (localtime()->year() + 10));
    my %year_labels = ();

    my @hour_values = (1..12);
    my %hour_labels = ();

    my @minute_values = (0..59);
    my %minute_labels = ();
    $minute_labels{0} = '00';
    for (my $count = 0; $count <= 9; $count++) {
        $minute_labels{$count} = '0'.$count;
    }
    my @ampm_values = ('AM','PM');
    my %ampm_labels = (AM => 'AM', PM => 'PM');

    # Set up dummy vals if "no choice" IS allowed
    if ($nochoice) {
        # Month
        unshift(@month_values, 0);
        $month_labels{0} = 'Month';
                                                                                
        # Day
        unshift(@day_values, 0);
        $day_labels{0} = 'Day';
                                                                                
        # Year
        unshift(@year_values, 0);
        $year_labels{0} = 'Year';
        
        # Hour
        unshift(@hour_values, 0);
        $hour_labels{0} = 'Hour';

        # Minute
        unshift(@minute_values, 'undef');
        $minute_labels{undef} = 'Minute';

    }
                                                                                
    my $m_sel = $query->popup_menu(-name      => $name .'_month',
                                   -default   => ($date) ? $date->mon() : 0,
                                   -values    => \@month_values,
                                   -labels    => \%month_labels,
                                   ($onchange ? (-onChange => $onchange) : ())
                                  );
    my $d_sel = $query->popup_menu(-name      => $name .'_day',
                                   -default   => ($date) ? $date->mday() : 0,
                                   -values    => \@day_values,
                                   -labels    => \%day_labels,
                                   ($onchange ? (-onChange => $onchange) : ())
                                  );
    my $y_sel = $query->popup_menu(-name      => $name .'_year',
                                   -default   => ($date) ? $date->year() : 0,
                                   -values    => \@year_values,
                                   -labels    => \%year_labels,
                                   ($onchange ? (-onChange => $onchange) : ())
                                  );

    my $hour_12; 
    if ($date) {
        $hour_12 = ($date->hour() >= 13) ? ($date->hour() - 12) : $date->hour();
        $hour_12 = 12 if ($hour_12 == 0);
    } 

    my $h_sel = $query->popup_menu(-name      => $name .'_hour',
                                   -default   => ($date) ? $hour_12 : 0,
                                   -values    => \@hour_values,
                                   -labels    => \%hour_labels,
                                   ($onchange ? (-onChange => $onchange) : ())
                                  );

    my $min_sel = $query->popup_menu(-name      => $name .'_minute',
                                   -default   => ($date) ? $date->minute() : 'undef',
                                   -values    => \@minute_values,
                                   -labels    => \%minute_labels,
                                   ($onchange ? (-onChange => $onchange) : ())
                                  );

    my $ampm = 'AM';
    if ($date) {
        $ampm = 'PM' if ($date->hour >= 12);
    }

    my $ampm_sel = $query->popup_menu(-name      => $name .'_ampm',
                                   -default   => $ampm,
                                   -values    => \@ampm_values,
                                   -labels    => \%ampm_labels,
                                  );
                                                                                
                                                                                
    return $m_sel . "&nbsp;" . $d_sel . "&nbsp;" . $y_sel . "&nbsp;" . $h_sel . "&nbsp;" . $min_sel . "&nbsp;" . $ampm_sel;
}


=item $chooser_html = date_chooser(name => 'cover_date', query => $query)

Returns a block of HTML implementing the standard Krang date
chooser.  The C<name> and C<query> parameters are required.

Additional optional parameters are as follows:

  date      - if set to a date object (Time::Piece), chooser will
              be prepopulated with that date.  If not set to a
              date object, will default to current date (localtime)
              unless "nochoice" is true, in which case chooser
              will be set to blank.

  nochoice  - if set to a true value, blanks will be provided
              as choices in the chooser.  Used in conjunction
              with the "date" parameter, the chooser may be
              set to default to no date.

              The value "0" will be returned if a user chooses
              the "no choice" option.


The date_chooser() implements itself in HTML via three separate 
query parameters.  They are named based on the provided name, 
plus "_month", "_day", and "_year", respectively. CGI query data from 
date_chooser can be retrieved and converted back into a date 
object via decode_date().

=cut

sub date_chooser {
    my %args = @_;
    my ($name, $query, $date, $nochoice) =
      @args{qw(name query date nochoice)};
    croak("Missing required args: name and query")
      unless $name and $query;

    # Set date to today if it is NOT already set, AND if we do not allow "no choice"
    $date ||= localtime() unless ($nochoice);

    # Set up month input
    my @month_values = (1..12);
    my %month_labels = (
                        1  => 'Jan',
                        2  => 'Feb',
                        3  => 'Mar',
                        4  => 'Apr',
                        5  => 'May',
                        6  => 'Jun',
                        7  => 'Jul',
                        8  => 'Aug',
                        9  => 'Sep',
                        10 => 'Oct',
                        11 => 'Nov',
                        12 => 'Dec'
                       );

    my @day_values = (1..31);
    my %day_labels = ();

    my @year_values = ((localtime()->year() - 10)..(localtime()->year() + 10));
    my %year_labels = ();

    # Set up blanks if "no choice" IS allowed
    if ($nochoice) {
        # Month
        unshift(@month_values, 0);
        $month_labels{0} = '';

        # Day
        unshift(@day_values, 0);
        $day_labels{0} = '';

        # Year
        unshift(@year_values, 0);
        $year_labels{0} = '';
    }

    my $m_sel = $query->popup_menu(-name      => $name .'_month',
                                   -default   => ($date) ? $date->mon() : 0,
                                   -values    => \@month_values,
                                   -labels    => \%month_labels,
                                  );
    my $d_sel = $query->popup_menu(-name      => $name .'_day',
                                   -default   => ($date) ? $date->mday() : 0,
                                   -values    => \@day_values,
                                   -labels    => \%day_labels,
                                  );
    my $y_sel = $query->popup_menu(-name      => $name .'_year',
                                   -default   => ($date) ? $date->year() : 0,
                                   -values    => \@year_values,
                                   -labels    => \%year_labels,
                                  );


    return $m_sel . "&nbsp;" . $d_sel . "&nbsp;" . $y_sel;
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

    my $m = $query->param($name . '_month');
    my $d = $query->param($name . '_day');
    my $y = $query->param($name . '_year');
    my $h = $query->param($name . '_hour');
    my $min = $query->param($name . '_minute');
    my $ampm;
    my $sec = '00';
    if ( (defined $min) and ($min eq 'undef') ) {
        if ($ntie and ($h eq 0)) {
            $ampm = 'na';
            $min  = 59;
            $h    = 23;
            $sec  = '59';
        } else {
            $min = 0;
        }
    }
    $ampm = $query->param($name . '_ampm') unless $ampm;

    # deal with converting AM/PM to 24 hour time
    if (defined($h)) {
        if ($h == 12) {
            $h = 0 if ($ampm eq 'AM'); 
        } else {
            $h = $h + 12 if ((defined $ampm) and ($ampm eq 'PM'));
        }
    } else { 
        $h = 12 if ((defined $ampm) and ($ampm eq 'PM'));
    }

    return undef unless $m and $d and $y;

    return Time::Piece->strptime("$y-$m-$d $h:$min:$sec", '%Y-%m-%d %H:%M:%S');
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

    my $m = $query->param($name . '_month');
    my $d = $query->param($name . '_day');
    my $y = $query->param($name . '_year');
    return undef unless $m and $d and $y;

    return Time::Piece->strptime("$m/$d/$y", '%m/%d/%Y');
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


=cut

sub format_url {
    my %args = @_;

    # Validate calling input
    my ($url, $linkto, $length) = @args{qw/url linkto length/};
    croak ("Missing required argument 'url'") unless ($url);

    $length = 15 unless ($length);

    # wrap URL to length using Text::Wrap
    $Text::Wrap::columns = $length;

    # put spaces after /'s so that wrap() will try to wrap to them if
    # possible
    $url =~ s!/!/ !g;
    $url = wrap("","",$url);    
    $url =~ s!/ !/!g;

    # format wrapped URL in HTML
    my $format_url_html;
    my @url_lines = split("\n",$url);
    if ($linkto) {
        # URL with links
        $format_url_html = qq{<a href="$linkto">} . 
          join('<br>', @url_lines ) . qq{</a>};
    } else {
        # URL without links
        $format_url_html = join( '<br>', @url_lines );
    }

    return $format_url_html;
}







1;

=back
