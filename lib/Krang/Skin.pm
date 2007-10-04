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
    $self->{skin_dir} = $skin_dir;

    return $self;
}

sub conf {
    my $self = shift;
    unless( $self->{conf} ) {
        # read in conf file
        my $conf = Config::ApacheFormat->new(expand_vars => 1);
        eval { $conf->read(catfile($self->{skin_dir}, 'skin.conf')) };
        die "Unable to read $self->{skin_dir}/skin.conf: $@\n" if $@;

        $self->{conf} = $conf;
    }
    return $self->{conf};
}

sub base {
    my $self = shift;
    unless( $self->{base} ) {
        my $conf = $self->conf;
        if( $conf->get('Base') ) {
            my $base = pkg('Skin')->new(name => $conf->get('Base'));
            $self->{base} = $base;
        }
    }
    return $self->{base};
}

sub merge_config {
    my $self = shift;
    my $conf = $self->conf;
    my $base = $self->base;
    my $vars = $base ? $base->merge_config : {};

    $vars->{$_} = $conf->get($_) foreach ($conf->get);
    return $vars;
}

sub install {
    my $self = shift;

    # does our skin use another skin as it's base?
    my $base = $self->base;
    $base->install if $base;
    
    $self->_install_css;
    $self->_install_images;
}

sub _install_css {
    my $self = shift;

    # make all our config vars visible to the templates
    my $vars = $self->merge_config();
    
    # by default we load any *.css.tmpl files in templates/ and we
    # also add any *.css.tmpl files in the skin's css/ dir
    my @css_tmpls = (
        pkg('File')->find_glob(catfile('templates', '*.css.tmpl')),
        pkg('File')->find_glob(catfile('skins', $self->{name}, 'css', '*.css.tmpl')),
    );

    my %processed; # to keep track of files we've already seen
    foreach my $css_tmpl (@css_tmpls) {
        my $basename = basename($css_tmpl, '.css.tmpl');
        next if $processed{$basename};
        # load the css template
        my $template = pkg('HTMLTemplate')->new(
            filename          => $css_tmpl,
            die_on_bad_params => 0,
        );

        # pass in params
        $template->param(
            %$vars,
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
    my $self     = shift;
    my $conf     = $self->conf;
    my $skin_dir = pkg('File')->find(catfile('skins', $self->{name}));

    # copy anything in images/ to htdocs/images/
    my $img_dir = catdir($skin_dir, 'images');
    my $dest_dir = catdir(KrangRoot, 'htdocs', 'images');
    if(-d $img_dir) {
        $img_dir = catdir($img_dir, '*');
        system("cp -R $img_dir $dest_dir") == 0
          or croak "Could not copy images from $img_dir to $dest_dir";
    }
}

1;
