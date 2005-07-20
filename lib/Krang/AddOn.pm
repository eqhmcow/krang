package Krang::AddOn;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

=head1 NAME

Krang::AddOn - module to manage Krang add-ons

=head1 SYNOPSIS

  use Krang::ClassLoader 'AddOn';

  # install an addon
  pkg('AddOn')->install(src => '/path/to/Turbo-1.00.tar.gz');

  # get a list of installed addons
  my @addons = pkg('AddOn')->find();

  # find a particular addon by name
  my ($addon) = pkg('AddOn')->find(name => $name);

  # find a particular addon by conditional field in conf file set to true
  # fields supported are EnableAdminSchedulerActions and EnableObjectSchedulerActions
  my @addons = pkg('AddOn')->find(condition => 'EnableFeatureFoo')

  # get the name and version of an addon
  $name    = $addon->name;
  $version = $addon->version;

  # remove an addon
  $addon->uninstall(verbose => 0);

  # call all registered handlers of a particular name
  pkg('AddOn')->call_handler($name, @args);

=head1 DESCRIPTION

This module is responsible for managing Krang addons and their
associated versions.  See the add_ons.pod document in docs/ for a
complete description of how add-ons work.

=head1 INTERFACE

=over

=item C<< Krang::AddOn->install(src => $path, verbose => 1, force => 1) >>

Install a new addon.  The source arguement must contain the path to an
addon tarball, which must be readable by C<KrangUser>.  

The C<verbose> option will cause install steps to be logged to STDERR.
The C<force> option will allow an addon to be installed even if the
addon is already installed and version is greater than or equal to
this version.

=item C<< $addon->uninstall(verbose => 1, force => 1) >>

Uninstall an addon.  The C<verbose> option will cause install steps to
be logged to STDERR.  The C<force> option will allow an addon to be
uninstalled even if an existing addon depends on it, otherwise the
method will die().

=item C<< $name = $addon->name >>

Get the addon's name.

=item C<< $version = $addon->version >>

Get the addon's version.

=item C<< $conf = $addon->conf >>

Get the addon's configuration, a Config::ApacheFormat object.

=item C<< @addons = Krang::AddOn->find() >>

Get a list of addons sorted by their Priority.
supported:

=back

=over

=item name

Find an addon based on name.

=back

=over

=item condition

Find a set of addons based on boolean flag

=back

=over

=item C<< pkg('AddOn')->call_handler($name, @args) >>

Call all handlers named $name passing @args.  For example, the
NavigationHandler is triggered using:

   pkg('AddOn')->call_handler("NavigationHandler", $tree);

=back

=head1 Scheduler Addons

Two types of scheduler addons are supported.  They are configured with the following directives in krang_addon.conf.

=over

=item EnableAdminSchedulerActions 1

 flags scheduler to look in this addon for items to add to the admin scheduler screen

=over

=item AdminSchedulerActionList Foo Bar

 List of actions to add to admin scheduler screen 

=back

=back

=over

=item EnableObjectSchedulerActions 1

 flags scheduler to look in this addon for actions to add to the story/media scheduler screen

=over

=item ObjectSchedulerActionList Foo Bar

 List of actions to add to story/media scheduler screen 

=back

=back

=cut

use Carp qw(croak);
use Krang::ClassLoader Conf => qw(KrangRoot);
use File::Spec::Functions qw(catdir catfile canonpath splitdir);
use File::Path qw(mkpath);

use File::Copy qw(copy);
use File::Path qw(mkpath rmtree);

use File::Temp qw(tempdir tempfile);
use Archive::Tar;
use Config::ApacheFormat;
use File::Find ();
use Krang;
use File::Copy qw(copy);
use Cwd qw(fastcwd);

use Krang::ClassLoader 'File';

use Krang::ClassLoader MethodMaker => 
  new_with_init => 'new',
  new_hash_init => 'hash_init',
  get_set => [ qw(name version conf EnableAdminSchedulerActions EnableObjectSchedulerActions) ];

sub init {
    my $self = shift;
    my %args = @_;

    croak("Missing required 'name' and 'version' parameters.")
      unless exists $args{name} and exists $args{version};

    $self->hash_init(%args);
    return $self;
}

# trigger registered handlers
sub call_handler {
    my ($pkg, $name, @args) = @_;
    
    # turn NavigationHandler into navigation_handler
    (my $method_name = $name) =~ 
      s!^([A-Z][a-z]+)([A-Z][a-z]+)!lc($1) . "_" . lc($2)!e;
    
    # mix in navigation from add-ons with NavigationHandlers
    foreach my $addon (pkg('AddOn')->find()) {
        my $handler = $addon->conf->get($name) or next;
        eval "require $handler";
        croak("Failed to load $name handler class $handler for the " . $addon->name . " addon: $@") if $@;
        $handler->$method_name(@args);
    }

}

# remove an addon
sub uninstall {
    my ($self, %args) = @_;
    my $verbose = $args{verbose};
    my $force   = $args{force};

    # make sure no other addons are depending on this one
    eval {
        foreach my $addon (ref($self)->find()) {
            next if $addon->name eq $self->{name};
            my $conf = $addon->conf;        
            if (my %req = $conf->get('requireaddons')) {
                die "Cannot uninstall the $self->{name} addon while ".
                  "$addon->{name} is installed.  $addon->{name} depends " .
                    "on $self->{name}.\n"
                      if $req{$self->{name}};
            }
        }
    };
    if ($@) {
        die $@ unless $force;
        warn $@ . "(continueing anyway due to --force)\n";
    }

    my $dir = catdir(KrangRoot, 'addons', $self->name);
    
    # run the uninstall script if one is set
    if ($self->conf->get('uninstallscript')) {
        system("KRANG_ROOT=" . KrangRoot . " $^X " .
               catfile($dir, $self->conf->get('uninstallscript')))
          and die "\n\nUninstall script failed, won't uninstall!\n";
    }

    # do the deed
    print STDERR "Removing $dir...\n" if $verbose;
    rmtree($dir);
}

# find caches addons in @ADDONS until _flush_cache is called
our @ADDONS;
our $PERL_BIN = $^X;
sub find {
    my ($pkg, %arg) = @_;
    my $dir = catdir(KrangRoot, 'addons');

    unless (@ADDONS) {
        opendir(my $dh, $dir) or die "Unable to open dir $dir: $!";
        my @files = grep { not /^\./ and not /^CVS$/ } readdir($dh);
        closedir($dh);

        foreach my $addon (@files) {
            my $conf = $pkg->_addon_conf(catfile($dir, $addon, 
                                                 'krang_addon.conf'));

            push @ADDONS, $pkg->new(
                name    => $addon,
                version => $conf->get('version'),
                conf    => $conf,
                EnableAdminSchedulerActions => $conf->get('EnableAdminSchedulerActions') || '',
                EnableObjectSchedulerActions => $conf->get('EnableObjectSchedulerActions') || ''
            );
        }

        # sort by priority in reverse order
        @ADDONS = sort { ($b->conf->get('priority') || 0)  
                           <=>
                         ($a->conf->get('priority') || 0) } @ADDONS;
    }

    if ($arg{name}) {
        return grep { $_->{name} eq $arg{name} } @ADDONS;
    } elsif ($arg{condition}) {
        return grep { $_->{$arg{condition}} } @ADDONS;
    }

    return @ADDONS;
}

sub _flush_cache { @ADDONS = () }

sub install {
    my ($pkg, %args) = @_;
    my ($source, $verbose, $force) = @args{('src', 'verbose', 'force')};
    croak("Missing src param!") unless $source;

    my $old_dir = fastcwd();

    # find addon dir, opening the tar file if needed
    $pkg->_open_addon(%args);

    # parse the config
    my $conf = $pkg->_read_conf(%args);
    $args{conf} = $conf;


    # make sure that this is a positive upgrade, if the addon is already
    # installed
    my ($old) = pkg('AddOn')->find(name => $conf->get('name'));
    $args{old} = $old;
    if ($old and $old->version >= $conf->get('version') and not $force) {
        die "Unable to install version " . $conf->get('version') . " of " . 
          $conf->get('name') . ", version " . $old->version . 
           " is already installed!\n";
    }

    # handle requirekrang
    if ($conf->get('requirekrang')) {
        die "This addon required Krang version " . $conf->get('requirekrang') . " or greater, but this is only $Krang::VERSION.\n"
          if $conf->get('requirekrang') > $Krang::VERSION;
    }

    # handle requireaddons
    if ($conf->get('requireaddons')) {
        my @addons = $conf->get('requireaddons');
        while(@addons) {
            my ($req_name, $req_ver) = (shift(@addons), shift(@addons));
            my ($req) = pkg('AddOn')->find(name => $req_name);
            die "This addon requires the '$req_name' addon, ".
              "which is not installed!\n"
                unless $req;
            die "This addon requires the '$req_name' addon version '$req_ver' ".
              "or greater, but only version '" . $req->version . 
                "' is installed.\n"
                  if $req_ver > $req->version;
        }
    }

    # figure out which files to copy
    my @files = $pkg->_list_files(%args);

    # copy files
    $pkg->_copy_files(%args, files => \@files);

    # run krang_addon_build to build src/ files
    system(catfile(KrangRoot, 'bin', 'krang_addon_build') . " " .
           $conf->get('name')) 
      and die "Unable to build with krang_addon_build: $!";

    # perform upgrades if necessary
    $pkg->_upgrade(%args) if $old;

    # run the post install script if required
    system("KRANG_ROOT=" . KrangRoot . " $^X " . 
           $conf->get('postinstallscript'))
      if $conf->get('postinstallscript');

    # installing a new addon means that @INC needs updating, reload
    # Krang::lib and flush the file cache and the addon cache
    pkg('File')->flush_cache();
    $pkg->_flush_cache();
    pkg('lib')->reload();
    pkg('HTMLTemplate')->reload_paths() if @Krang::HTMLTemplate::PATH;
    pkg('ClassFactory')->reload_configuration();

    # all done, return home if possible
    chdir $old_dir;
}

#
# subroutines
#

# do upgrades if necessary
sub _upgrade {
    my ($pkg, %args) = @_;
    my ($source, $verbose, $force, $conf, $old) = 
      @args{('src', 'verbose', 'force', 'conf', 'old')};

    return unless -d 'upgrade';
    my $old_version = $old->version;
    
    # get list of potential upgrades
    opendir(UDIR, 'upgrade') or die $!;
    my @mod = grep { /^V(\d+)\_(\d+)\.pm$/ and "$1.$2" > $old_version } 
      sort readdir(UDIR);
    closedir(UDIR);

    print STDERR "Found " . scalar(@mod) . " applicable upgrade modules: " .
      join(", ", @mod) . "\n"
        if $verbose;

    # Run upgrade modules
    foreach my $mod (@mod) {
        # Get package name by trimming off ".pm"
        my $package = $mod;
        $package =~ s/\.pm$//;

        require(catfile('upgrade', $mod));
        $package->new()->upgrade();
    }
}

# figure out which files to copy
sub _list_files {
    my ($pkg, %args) = @_;
    my ($source, $verbose, $force, $conf) = 
      @args{('src', 'verbose', 'force', 'conf')};

    my %exclude;
    my @files;
    
    if ($conf->get('Files')) {
        @files = $conf->get('Files');
    } else {
        File::Find::find({ wanted => 
                           sub { push(@files, canonpath($_)) if -f $_ },
                           no_chdir => 1 },
                         '.');
    }
    
    # add exclusions from ExcludeFiles
    if ($conf->get('ExcludeFiles')) {
        $exclude{$_} = 1 for $conf->get('ExcludeFiles');
    }
    @files = grep { not exists $exclude{$_} } @files;

    # exclude upgrade files
    @files = grep { not /^upgrade\// } @files;

    return @files;
}
    
sub _copy_files {
    my ($pkg, %args) = @_;
    my ($source, $verbose, $force, $conf, $files) = 
      @args{('src', 'verbose', 'force', 'conf', 'files')};

    my $root = KrangRoot;
    my $name = $conf->get('name');
    my $addon_dir = catdir($root, 'addons', $name);

    # copy the files, creating directories as necessary
    foreach my $file (@$files) {
        # fix shebang for addon .pl and .cgi scripts.
        if ($file =~ /\.(?:pl|cgi)$/) {
            open(SOURCE, $file) or die "Unable to $file: $!";
            my $source = do { local $/; <SOURCE> };

            $source =~ s/^#![\w\/\.]+(\s*.*)$/#!$PERL_BIN$1/m or
                warn "Couldn't find shebang line in $file to replace!";

            open(SOURCE, '>', $file) or die "Unable to write $file: $!";
            print SOURCE $source;
            close SOURCE;
        }

        my @parts = splitdir($file);
        my $dir   = @parts > 1 ? catdir(@parts[0 .. $#parts - 1]) : '';
        my $target_dir = catdir($addon_dir, $dir);
        my $target = catfile($target_dir, $parts[-1]);
        unless (-d $target_dir) {
            print STDERR "Making directory $target_dir...\n"
              if $verbose;
            mkpath([$target_dir]) 
              or die "Unable to create directory '$target_dir': $!\n";
        }

        print STDERR "Copying $file to $target...\n"
          if $verbose;
        my $target_file = catfile($target_dir, $parts[-1]);
        copy($file, $target_file)
          or die "Unable to copy '$file' to '$target_file': $!\n";
        chmod((stat($file))[2], $target_file)
          or die "Unable to chmod '$target_file' to match '$file': $!\n";
    }
}



# verify that krang_addon.conf exists, and read it
sub _read_conf {
    my ($pkg, %args) = @_;
    my ($source, $verbose, $force) = @args{('src', 'verbose', 'force')};
    
    croak("Source '$source' is missing required 'krang_addon.conf'.\n")
      unless -f 'krang_addon.conf';
    
    my $conf = $pkg->_addon_conf('krang_addon.conf');

    my $name = $conf->get('Name');
    my $version = $conf->get('Version');
    die "krang_addon.conf is missing required Name directive.\n"
      unless defined $name;
    die "krang_addon.conf is missing required Version directive.\n"
      unless defined $version;

    print STDERR "Read krang_addon.conf: Name=$name Version=$version\n"
      if $verbose;
    
    return $conf;
}

sub _addon_conf {
    my ($self, $file) = @_;
    my $conf = Config::ApacheFormat->new(
                   valid_directives => [qw( name version files 
                                            excludefiles requirekrang
                                            requireaddons postinstallscript 
                                            uninstallscript
                                            navigationhandler
                                            inithandler
                                            priority
                                            EnableAdminSchedulerActions 
                                            EnableObjectSchedulerActions 
                                            AdminSchedulerActionList
                                            ObjectSchedulerActionList
                                          )],
                   valid_blocks     => []);
    eval { $conf->read($file) };
    die "Unable to read $file: $@\n" if $@;
    
    return $conf;
}

# open up the addon's dir and chdir() there
sub _open_addon {
    my ($pkg, %args) = @_;
    my ($source, $verbose, $force) = @args{('src', 'verbose', 'force')};

    # don't try to chmod anything since it's counter-productive and
    # doesn't work on OSX for some damn reason
    local $Archive::Tar::CHOWN = 0;

    # open up the tar file
    my $tar = Archive::Tar->new();
    my $ok = eval { $tar->read($source); 1 };
    croak("Unable to read addon archive '$source' : $@\n")
      if $@;
    croak("Unable to read addon archive '$source' : ". Archive::Tar->error)
      if not $ok;
    
    # extract in temp dir
    my $dir = tempdir( DIR     => catdir(KrangRoot, 'tmp'),
                       CLEANUP => 1 );
    chdir($dir) or die "Unable to chdir to $dir: $!";
    $tar->extract($tar->list_files) or
      die("Unable to unpack archive '$source' : ". Archive::Tar->error);    
    
    # if there's just a single directory here then enter it
    opendir(DIR, $dir) or die $!;
    my @entries = grep { not /^\./ } readdir(DIR);
    closedir(DIR);
    if (@entries == 1 and -d $entries[0]) {
        chdir($entries[0]) or die $!;
    }
}

1;
