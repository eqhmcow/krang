package Krang::Widget;
use strict;
use warnings;

use Carp qw(croak);
use HTML::Template;
use Time::Piece qw(localtime);
use Krang::Category;
use Krang::Conf qw(KrangRoot);

use File::Spec::Functions qw(catfile);

use base 'Exporter';
our @EXPORT_OK = qw(category_chooser date_chooser decode_date format_url);

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
chooser.  The C<name> and C<query> parameters are required.

Additional optional parameters are as follows:

  onchange - can be set to the name of a javascript function
             that will be called when the user picks a category.  

  label    - change the label on the button which defaults to 'Choose'. 

  display  - setting to false will supress displaying the chosen 
             category URL next to the button.

  formname - the name of the form in which the chooser appears.  If 
             not specified, will default to the first form in your 
             HTML document.


The template for the category chooser is located in
F<Widget/category_chooser.tmpl>.

=cut

sub category_chooser {
    my %args = @_;
    my ($name, $query, $label, $display, $onchange, $formname) =
      @args{qw(name query label display onchange formname)};
    croak("Missing required args: name and query")
      unless $name and $query;

    my $template = HTML::Template->new(filename => 
                                         catfile(KrangRoot, "templates",
                                                 "Widget", 
                                                 "category_chooser.tmpl"),
                                       cache   => 1,
                                      );

    my $category_id = $query->param($name) || 0;

    # setup category loop
    my @cats = Krang::Category->find(order_by => 'url');
    my @category_loop;
    foreach my $cat (@cats) {
        if ($cat->category_id == $category_id) {
            $template->param(category_id => $category_id);
            $template->param(category_url => $cat->url);
        }

        push(@category_loop, {
                              category_id => $cat->category_id,
                              dir         => ($cat->dir eq '/' ? 
                                              $cat->url : $cat->dir),
                              url         => $cat->url,
                              parent_id   => $cat->parent_id,
                             });
    }
    $template->param(category_loop => \@category_loop,
                     name          => $name,
                     label         => $label || 'Choose',
                     display       => defined $display ? $display : 1,
                     onchange      => $onchange,
                     formname      => $formname,
                    );

    return $template->output();
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

    my @year_values = (1970..(localtime()->year() + 10));
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



  $url_html = 


=item $url_html = format_url(url => 'http://my.host/url.html', linkto => 'url.html' );

Returns a block of HTML implementing the standard Krang url
display/link style.  The C<url> parameter is required.  The 
optional C<linkto> parameter, if provided, will be used as
the HTML "href" to which users are directed when they click 
any line in the URL.

=cut

sub format_url {
    my %args = @_;

    # Validate calling input
    my ($url, $linkto) = @args{qw/url linkto/};
    croak ("Missing required argument 'url'") unless ($url);

    my @parts = split('/', $url);
    my @url_lines = (shift(@parts), "");
    for(@parts) {
        if ((length($url_lines[-1]) + length($_)) > 15) {
            push(@url_lines, "");
        }
        $url_lines[-1] .= "/" . $_;
    }
    my $format_url_html;
    if ($linkto) {
        # URL with links
        $format_url_html = join( '<br>', 
                                 map { qq{<a href="$linkto">$_</a>} } @url_lines );
    } else {
        # URL without links
        $format_url_html = join( '<br>', @url_lines );
    }

    return $format_url_html;
}







1;

=back
