package Krang::Skin;
use strict;
use warnings;

=head1 NAME

Krang::Skin - module to manipulate skins

=head1 SYNOPSIS

  use Krang::Skin;
  use Krang::Conf qw(Skin);

  # load the configured Skin
  my $skin = Krang::Skin->load(name => Skin);

  # install it into Krang
  $skin->install();

=head1 DESCRIPTION

This module loads and installs Krang skins.  It is generally called
from C<krang_load_skin>, which is used by C<krang_apachectl> when
booting Krang.

=head1 INTERFACE

=over

=item C<< $skin = Krang::Skin->new(name => 'Name') >>

Load a skin, by name.

=item C<< $skin->install() >>

Installs a skin into Krang, resulting in CSS, image and templates
which reflect the skin settings.

=back

=cut

use Carp qw(croak);
use Krang::Conf qw(KrangRoot);
use File::Spec::Functions qw(catdir catfile);
use HTML::Template;

# parameters from skin.conf that go to the CSS template
our @CSS_PARAMS = 
  (qw( background_color
       dark_color
       light_color
       bright_color
       border_color
       text_color
       light_text_color                               
       link_color
     ));

# required params in skin.conf
our @REQ = (@CSS_PARAMS);

sub new {
    my $pkg = shift;
    my $self = bless({@_}, $pkg);

    croak("Missing required 'name' parameter.")
      unless exists $self->{name};

    # read in conf file
    my $conf = Config::ApacheFormat->new(
                   valid_directives => [@REQ, 'include'],
                   valid_blocks     => []);
    eval { $conf->read(catfile(KrangRoot, 'skins', $self->{name}, 
                               'skin.conf')) };
    die "Unable to read skin.conf file for skin '$self->{name}': $@\n" if $@;

    # check reqs
    foreach my $req (@REQ) {
        die "skin.conf for '$self->{name}' is missing the '$req' directive.\n"
          unless (defined $conf->get($req));
    }
    
    $self->{conf} = $conf;

    return $self;
}

sub install {
    my $self = shift;
    my $conf = $self->{conf};

    # load the css template
    my $template = HTML::Template->new(filename => 'krang.css.tmpl',
                                       path => catdir(KrangRoot, 'templates'));
    
    # pass in params
    $template->param({ map { ($_, $conf->get($_)) } @CSS_PARAMS });
    
    # put output in htdocs/krang.css
    open(CSS, '>', catfile(KrangRoot, 'htdocs', 'krang.css'))
      or croak("Unable to open htdocs/krang.css: $!");
    print CSS $template->output;
    close CSS;
}

1;


