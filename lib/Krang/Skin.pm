package Krang::Skin;
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

If you're using the CC< <ImageBioChrome> >> features of F<skin.conf>
be aware that the colors that come out of Image::BioChrome are never 
exactly right. We might be using C<alpha()> wrong or there might be a 
bug in C<Image::BioChrome>.

=cut

use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader Conf => qw(KrangRoot);
use Krang::ClassLoader 'Info';
use Krang::ClassLoader 'HTMLTemplate';
use Krang::ClassLoader 'File';

use Carp qw(croak);
use File::Spec::Functions qw(catdir catfile);
use File::Basename qw(basename);

sub new {
    my $pkg = shift;
    my $self = bless({@_}, $pkg);

    croak("Missing required 'name' parameter.")
      unless exists $self->{name};

    my $skin_dir = pkg('File')->find("skins/$self->{name}");
    croak("Unable to find skin named $self->{name}!") unless $skin_dir;

    # read in conf file
    my $conf = Config::ApacheFormat->new(
        expand_vars   => 1,
        valid_blocks  => [qw(CSS Images File)]
    );
    eval { $conf->read(catfile($skin_dir, 'skin.conf')) };
    die "Unable to read $skin_dir/skin.conf: $@\n" if $@;

    $self->{conf} = $conf;

    return $self;
}

sub install {
    my $self = shift;

    # does our skin use another skin as it's base?
    my $conf = $self->{conf};
    my $base = $self->{conf}->get('Base');
    if( $base ) {
        pkg('Skin')->new(name => $base)->install();
    }

    $self->_install_css;
    $self->_install_images;
}

sub _install_css {
    my $self = shift;
    my $conf = $self->{conf};   
    my $name = $self->{name};
    
    # look at any directives in the CSS block and add them to the css templates
    my %css_directives = map { ($_ => $conf->get($_)) } 
        grep { $_ ne 'css' and $_ ne 'images' } $conf->get;
    my $css_block;
    eval { $css_block = $conf->block('CSS') };
    if( $css_block ) {
        %css_directives = (
            %css_directives,
            map { ($_ => $css_block->get($_)) } $css_block->get()
        );
    }

    # by default we load any *.css.tmpl files in templates/ and we
    # also add any *.css.tmpl files in the skin's css/ dir
    my @css_tmpls = (
        pkg('File')->find_glob(catfile('templates', '*.css.tmpl')),
        pkg('File')->find_glob(catfile('skins', $name, 'css', '*.css.tmpl')),
    );

    my %processed; # to keep track of files we've already seen
    foreach my $css_tmpl (@css_tmpls) {
        my $basename = basename($css_tmpl, '.css.tmpl');
        next if $processed{$basename};
        # load the css template
        my $template = pkg('HTMLTemplate')->new(filename => $css_tmpl,
                                                die_on_bad_params => 0,
                                               );

        # pass in params
        $template->param(
            %css_directives,
            krang_install_id => pkg('Info')->install_id,
        );
        
        # put output in htdocs/krang.css
        my $dest_file = catfile(KrangRoot, 'htdocs', "$basename.css");
        open(CSS, '>', $dest_file)
          or croak("Unable to open $dest_file: $!");
        print CSS $template->output;
        close CSS;
        $processed{$basename} = $css_tmpl;
    }
}

sub _install_images {
    my $self = shift;
    my $conf = $self->{conf};
    my $skin_dir = pkg('File')->find(catfile('skins', $self->{name}));

    # copy anything in images/ to htdocs/images/
    my $img_dir = catdir($skin_dir, 'images');
    my $dest_dir = catdir(KrangRoot, 'htdocs', 'images');
    if( -d $img_dir ) {
        $img_dir = catdir($img_dir, '*');
        system("cp -R $img_dir $dest_dir") == 0
            or croak "Could not copy images from $img_dir to $dest_dir";
    }

    # if we have <Images> then process them too
    my $img_block;
    eval { $img_block = $conf->block('Images') };
    if( $img_block ) {
        require Image::BioChrome;
        my @files = map { $_->[1] } $img_block->get('File');
        # process each image file we're given
        foreach my $file (@files) {
            my $file_block = $img_block->block(File => $file);

            # open up the image and color it with Image::BioChrome
            my $template = pkg('File')->find(catfile('htdocs', 'images', $file));
            if( -e $template ) {
                $Image::BioChrome::VERBOSE = 0;
                $Image::BioChrome::DEBUG = 0;
                my $bio = Image::BioChrome->new($template);
                croak("Unable to load image $template.") unless $bio;

                # colorize
                $bio->alphas(
                    $self->_normalize_color($file_block->get('BioChromeBlack')),
                    $self->_normalize_color($file_block->get('BioChromeRed')),
                    $self->_normalize_color($file_block->get('BioChromeGreen')),
                    $self->_normalize_color($file_block->get('BioChromeBlue')),
                );
                
                $bio->write_file(catfile(KrangRoot, 'htdocs', 'images', $file)); 
            } else {
                warn "Could not find file matching $file!\n";
            }
        }
    }
}

# change #FFF into #FFFFFF
sub _normalize_color {
    my ($self, $color) = @_;
    if( $color =~ /^#(.)(.)(.)$/ ) {
        $color = "#$1$1$2$2$3$3";
    } elsif( $color !~ /^#(.{6})$/ ) {
        croak "Skin '$self->{name}' color $color is not a valid color!";
    }
    return $color;
}

1;


