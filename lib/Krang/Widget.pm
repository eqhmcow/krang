package Krang::Widget;
use strict;
use warnings;

use Krang::Category;
use Krang::Conf qw(KrangRoot);

use File::Spec::Functions qw(catfile);

use base 'Exporter';
our @EXPORT_OK = ('category_chooser');

=head1 NAME

Krang::Widget - interface widgets for use by Krang::CGI modules

=head1 SYNOPSIS

  use Krang::Widget qw(category_chooser);

  $chooser = category_chooser(name => 'category_id',
                              query => $query);

=head1 DESCRIPTION

This modules exports a set of generally useful CGI widgets.

=head1 INTERFACE

=over 4

=item $chooser = category_chooser(name => 'category_id', query => $query, onchange => 'add_category')

Returns a block of HTML implementing the standard Krang category
chooser.  The C<name> and C<query> parameters are required.

Optionally, an 'onchange' handler can be set to the name of a
javascript function that will be called when the user picks a
category.  Setting the 'label' variable will change the label on the
button which defaults to 'Choose'.  Finally, setting 'display' to
false will supress displaying the chosen category URL next to the
button.

The template for the category chooser is located in
F<Widget/category_chooser.tmpl>.

=cut

sub category_chooser {
    my %args = @_;
    my ($name, $query, $label, $display, $onchange) =
      @args{qw(name query label display onchange)};
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
                     display       => defined $display ? $display : 1);

    return $template->output();
}

1;

=back
