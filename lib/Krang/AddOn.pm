package Krang::AddOn;
use strict;
use warnings;

=head1 NAME

Krang::AddOn - module to manage installed add-ons

=head1 SYNOPSIS

  use Krang::AddOn;

  # get a list of installed addons
  my @addons = Krang::AddOn->find();

  # get the name and version of an addon
  $name    = $addon->name;
  $version = $addon->version;

  # update the version and save
  $addon->version(1.01);
  $addon->save();

  # create a new addon
  $addon = Krang::AddOn->new(name    => 'Foo', 
                             version => 10.0);

  # remove an addon
  $addon->delete();

=head1 DESCRIPTION

This module is responsible for maintaining the list of addons and
their associated versions.  See the add_ons.pod document in docs/ for
a complete description of how add-ons work.

=head1 INTERFACE

=over

=item C<< $addon = Krang::AddOn->new(name => 'foo', version => 1.00) >>

Create a new addon.  Both C<name> and C<version> are required.

=item C<< $name = $addon->name >>

=item C<< $addon->name(10.00) >>

Get/set addon name.

=item C<< $version = $addon->version >>

=item C<< $addon->version(10.00) >>

Get/set addon version.

=item C<< $addon->save() >>

Save an addon.

=item C<< @addons = Krang::AddOn->find() >>

Get a list of addons.  Only one option is supported:

=over

=item name

Find an addon based on name.

=back

=back

=cut

use Carp qw(croak);
use Krang::Conf qw(KrangRoot);
use File::Spec::Functions qw(catdir catfile);
use File::Path qw(mkpath);

use Krang::MethodMaker
  new_with_init => 'new',
  new_hash_init => 'hash_init',
  get_set => [ qw(name version) ];

sub init {
    my $self = shift;
    my %args = @_;

    croak("Missing required 'name' and 'version' parameters.")
      unless exists $args{name} and exists $args{version};

    $self->hash_init(%args);
    return $self;
}

# addon data gets saved into data/addons/$name
sub save {
    my $self = shift;
    my $dir = _dir();

    open(ADDON, '>', catfile($dir, $self->name))
      or die "Unable to open " . catfile($dir, $self->name) . ": $!";
    print ADDON $self->version;
    close ADDON;
}

# remove an addon
sub delete {
    my $self = shift;
    my $dir = _dir();
    my $file = catfile($dir, $self->name);
    return unless -f $file;
    unlink($file) or croak("Unable to unlink $file: $!");
}

sub find {
    my ($pkg, %arg) = @_;
    my $dir = _dir();

    opendir(DIR, $dir) or die "Unable to open dir $dir: $!";
    my @files = grep { not /^\./ } readdir(DIR);
    closedir(DIR);

    if (exists $arg{name}) {
        @files = grep { $_ eq $arg{name} } @files;
    }
    
    my @obj;
    foreach my $file (@files) {
        open(ADDON, '<', catfile($dir, $file))
          or die "Unable to open $dir/$file: $!";
        my $version = <ADDON>;
        push @obj, $pkg->new(name    => $file,
                             version => $version);
    }
    
    return @obj;
}

# get addon dir, creating if it doesn't exist
sub _dir {
    my $dir = catdir(KrangRoot, 'data', 'addons');
    unless (-d $dir) {
        mkpath([$dir]) or die "Unable to make $dir: $!";
    }
    return $dir;
}

1;


