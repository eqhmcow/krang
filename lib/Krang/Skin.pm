package Krang::Skin;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

=head1 NAME

Krang::Skin - module to manipulate skins

=head1 SYNOPSIS

  use Krang::ClassLoader 'Skin';
  use Krang::ClassLoader Conf => qw(Skin);

  # load the configured Skin
  my $skin = pkg('Skin')->load(name => Skin);

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

=head1 TODO

The colors that come out of Image::BioChrome are never exactly right.
I might be using alpha() wrong or there might be a bug in
Image::BioChrome.

=cut

use Carp qw(croak);
use Krang::ClassLoader Conf => qw(KrangRoot);
use File::Spec::Functions qw(catdir catfile);
use Krang::ClassLoader 'HTMLTemplate';
use Image::BioChrome;
use File::Copy qw(copy);
use Krang::ClassLoader 'File';

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
our @REQ = (@CSS_PARAMS, 
            qw(logo_color1
               logo_color2
               logo_color3));

sub new {
    my $pkg = shift;
    my $self = bless({@_}, $pkg);

    croak("Missing required 'name' parameter.")
      unless exists $self->{name};

    my $skin_dir = pkg('File')->find("skins/$self->{name}");
    croak("Unable to find skin named $self->{name}!") unless $skin_dir;

    # read in conf file
    my $conf = Config::ApacheFormat->new(
                   valid_directives => [@REQ, 'include'],
                   valid_blocks     => []);
    eval { $conf->read(catfile($skin_dir, 'skin.conf')) };
    die "Unable to read $skin_dir/skin.conf: $@\n" if $@;

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
        my $template = pkg('HTMLTemplate')->new(filename => "$css.css.tmpl",
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
    my $skin_dir = pkg('File')->find("skins/$self->{name}");

    # process each image in turn
    foreach my $image (@IMAGES) {
        my $src = catfile($skin_dir, 'images', $image);
        my $targ = catfile(KrangRoot, 'htdocs', 'images', $image);

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
        
        if ($image eq 'logo.gif') {
            $bio->alphas(
                         $conf->get('background_color'),
                         $conf->get('logo_color1'),
                         $conf->get('logo_color2'),
                         $conf->get('logo_color3'), 
                        );
        } else {
            $bio->alphas(
                         $conf->get('background_color'),
                         $conf->get('light_color'),
                         $conf->get('bright_color'),
                         $conf->get('dark_color'), 
                        );
            
         }
        $bio->write_file($targ); 
    }
}

1;


