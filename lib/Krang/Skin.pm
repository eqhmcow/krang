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
use Krang::HTMLTemplate;
use Image::BioChrome;
use File::Copy qw(copy);

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
       button_color
       alert_color
       invalid_color
     ));

# images processed by the skin
our @IMAGES =
  (qw( arrow.gif 
       logo.gif 
       arrow-asc.gif
       arrow-desc.gif
       left-bg.gif
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

    $self->_install_css;
    $self->_install_images;
}

sub _install_css {
    my $self = shift;
    my $conf = $self->{conf};   
    
    foreach my $css (qw(krang krang_login krang_help)) {
        # load the css template
        my $template = Krang::HTMLTemplate->new(filename => "$css.css.tmpl",
                                                die_on_bad_params => 0,
                                               );
    
        # pass in params
        $template->param({ map { ($_, $conf->get($_)) } @CSS_PARAMS });
        
        # put output in htdocs/krang.css
        open(CSS, '>', catfile(KrangRoot, 'htdocs', "$css.css"))
          or croak("Unable to open htdocs/krang.css: $!");
        print CSS $template->output;
        close CSS;
    }
}

sub _install_images {
    my $self = shift;
    my $conf = $self->{conf};

    # process each image in turn
    foreach my $image (@IMAGES) {
        my $src = catfile(KrangRoot, 'skins', $self->{name}, 'images',$image);
        my $targ = catfile(KrangRoot, 'htdocs', 'images',$image);

        # if the skin supplies this image, copy it into place
        if (-e $src) {
            copy($src, $targ);
            next;
        }

        # otherwise open up the template image and color it with
        # Image::BioChrome
        my $template = catfile(KrangRoot, 'templates', 'images', $image);
        $Image::BioChrome::VERBOSE = 0;
        $Image::BioChrome::DEBUG = 0;
        my $bio = Image::BioChrome->new($template);
        croak("Unable to load image $template.") unless $bio;

        $bio->alphas($conf->get('background_color'), 
                     $conf->get('light_color'), 
                     $conf->get('bright_color'), 
                     $conf->get('dark_color'));
    
        $bio->write_file($targ);
    }
}

1;


