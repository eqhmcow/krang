package Krang::Localization;
use strict;
use warnings;

use Krang;
use Krang::ClassLoader ClassFactory => qw(pkg);
use Krang::ClassLoader Conf         => qw(KrangRoot DefaultLanguage AvailableLanguages);
use Krang::ClassLoader Log          => qw(debug);
use Krang::ClassLoader Session      => qw(%session);
use Krang::ClassLoader 'File';
use Krang::ClassLoader 'ConfigApacheFormat';

use File::Spec::Functions qw(catfile catdir splitdir canonpath);
use File::Temp qw(tempdir tempfile);
use File::Path;
use File::Find ();
use Archive::Tar;
use File::Copy qw(copy);
use Cwd qw(fastcwd);

our @EXPORT_OK = qw(%LANG %MISSING localize localize_template);

use Carp qw(croak);

use base 'Exporter';

our (%LANG, %L10N, %MISSING);

=head1 NAME

Krang::Localization - Krang localization module

=head1 SYNOPSIS

   use Krang::ClassLoader Localization => qw(localize);
   $localized_string = localize('some string');

   # All AvailableLanguages set in conf/krang.conf are available via
   # the exported %LANG hash, with keys being arbitrary language tags
   # and values being the corresponding language names.
   my $lang = $LANG{en}; # yields 'English';

   # install a localization distribution
   pkg('Localization')->install(src => '/path/to/Krang-Localization-Deutsch-3.01.tar.gz');

   # uninstall a localization distribution
   pkg('Localization')->uninstall(lang => de);

=head1 DESCRIPTION

This module provides localization to Krang by exporting the functions
localize() and localize_template().  The latter is primarily used in
L<lang/bin/krang_localize_templates> to pre-compile localized templates.
For this to work, wrap any static template strings in

   <tmpl_lang SomeSTRING>

tags.

Lexicons are Krang::ConfigApacheFormat objects accessible through the
class method

  pkg('Localization')->get_lexicon($language_tag);

Direct access to lexicons should be rarely necessary.  Use the
exported localize() function instead which honors the logged in user's
language preference.

=head1 INTERFACE

=over 4

=item C<< localize('Edit') >>

This exported method returns the localized version of its argument
according to the user's language reference.  It returns its argument
unchanged if no lexicon entry is found or if the language is set to
English.  For German, a lexicon entry may be

    "Edit Story"               "Story bearbeiten"


=item C<< localize('WEEKDAYS') >>

Returns a localized list of weekday names according to the user's
language setting. For French, the lexicon entry should read

    "Weekdays"   Dim Lun Mar Mer Jeu Ven Sam


=item C<< localize('This is number %s', $number) >>

Additional strings may be interpolated into the localized string using
sprintf()'s '%s' placeholder.  The Turkish lexicon entry for the above
mentioned example would be

    "This is number %s"  "Bu sayi %s"

=cut

sub localize {
    my ($key, @list) = @_;

    my $language = $session{language} || DefaultLanguage;

    # return as-is
    if (not $language or $language eq 'en' or not length($key)) {
        return scalar(@list) ? sprintf($key, @list) : $key;
    }

    debug("localize($key) called from " . (caller)[0] . ", line " . (caller)[2] . ".");

    # localize it
    my @localized = $L10N{$language}->get($key);

    # return as-is if translation is missing
    unless (defined($localized[0])) {
        debug("Unable to find key '$key' in lang/$language/perl.dict.");
        return scalar(@list) ? sprintf($key, @list) : $key;
    }

    # got a translation
    if( @list ) {
        if( wantarray ) {
            return map { sprintf($_, @list) } (@localized);
        } else {
            return sprintf($localized[0], @list);
        }
    } else {
        return wantarray ? @localized : $localized[0];
    }
}

=item C<< localize_template($textref, $language) >>

All strings in $textref wrapped in C<< <tmpl_lang> >> tags are localized
for the language indicated by $language_tag. $textref should contain a
reference to a string containing a template, $language_tag is supposed
to be a valid RFC3066-style tag representing a valid entry into the
%L10N lexicon hash.

There are 2 syntax flavors for C<< <tmpl_lang> >> tags. The 1st is just a simple

    <tmpl_lang String to be translated>

Where everything inside is translated as-is. The 2nd is more complicated to deal
with situations where there are words to be substituted into the the translation
that don't need translation, but the rest of the sentence does. Something like

    <tmpl_lang "Your username is %s", username>

Which will get translated and rendered into something like this (example in Spanish)

    Su Nombre de Usuario es <tmpl_var username escape=html>

If C<$ENV{KRANG_RECORD_MISSING_LOCALIZATIONS}> is set to true, then any
strings which do not have corresponding translations will be collected
in the C<%Krang::Localization::MISSING> hash (which is exportable).

=cut

sub localize_template {
    my ($textref, $lang) = @_;
    my $lexicon = $lang eq 'en' ? undef : pkg('Localization')->get_lexicon($lang);

    while ($$textref =~ m/<tmpl_lang ([^>]+)>/g) {
        my $key = $1;
        my $pos         = $-[0];
        my @subs;
        
        if( $key =~ /^"/ ) {
            $key =~ /^"([^"]+)"\s*(,.*)?$/;
            $key = $1;
            if( my $extras = $2 ) {
                $extras =~ s/^,\s*//; # remove the initial comma
                @subs = map { "<tmpl_var $_ escape=html>" } (split(/\s*,\s*/, $extras));
            }
        }
        my $translation = $lang eq 'en' ? $key : $lexicon->get($key);

        if(!defined $translation) {
            # remember missing localizations in templates
            $MISSING{$lang}{$key}++;
            $translation = $key;
        }

        $translation = sprintf($translation, @subs) if @subs;
        pos($pos);
        $$textref =~ s/<tmpl_lang\s+([^>]+)>/$translation/;
    }
}

=item C<< pkg('Localization')->get_lexicon($language) >>

Returns a Krang::ConfigApacheFormat object representing a lexicon
mapping English to the language indicated the methods
argument.

Croaks if no lexicon for the given language is found in the package
hash %L10N.

=cut

sub get_lexicon {
    my ($pkg, $lang) = @_;

    my $lexicon = $L10N{$lang};

    return $lexicon ? $lexicon : croak("No lexicon for language '$lang'");
}

# called at compile time to load the available lexicons in %L10N
sub _load_localization {
    for my $lang (grep { $_ ne 'en' } AvailableLanguages) {

        next unless defined($lang) and length($lang);

        # read also addon lexicons
        my @files = reverse pkg('File')->find_all(catfile('lang', $lang, 'perl.dict'));

        # read the main lexicons in memory
        my $l10n = Krang::ConfigApacheFormat->new(case_sensitive => 1);

        $l10n->read($_) for @files;

        # store the lexicon in package %L10N hash
        $L10N{$lang} = $l10n;

        # fill the exported %LANG hash
        $LANG{$lang} = $l10n->get('Language Name');
    }

    # don't forget the default language
    $LANG{en} = 'English';
}

BEGIN { _load_localization() }

=item C<< pkg('Localization')->install(src => $path, verbose => 1, downgrade => 1, version => $version) >>

Install a localization package.  The C<src> argument must contain the
path to an localization tarball produced by
F<lang/bin/krang_lang_dist> and readable by C<KrangUser>.

The C<verbose> option will cause install steps to be logged to STDERR.
The C<downgrade> option will allow to install a localization package whose
version is lower than $Krang::VERSION. You have to specify the
C<version> option for this to work.

=cut

sub install {
    my ($pkg, %args) = @_;
    my ($source, $verbose, $downgrade, $version) = @args{qw(src verbose downgrade version)};

    croak("Missing src param!") unless $source;

    my $old_dir = fastcwd();

    # find addon dir, opening the tar file if needed
    my $lang = $pkg->_open_localization_dist(%args);

    # lang root
    my $lang_root = catdir(KrangRoot, 'lang', $lang);

    # install a lower version than Krang's version?
    if ($version && $version < $Krang::VERSION) {
        die
          "You want to install version v$version which is lower than Krang's version v$Krang::VERSION.\n"
          . "This may result in missing lexicon entries.\n"
          . "Specify '--downgrade' if you really want to proceed.\n"
          unless $downgrade;
    }

    # cleanup before installing
    if (-e $lang_root and -d _) {
        rmtree($lang_root)
          or die "Can't remove directory 'lang/$lang/' before installing: $!";
    }

    # get files
    my $files = $pkg->_list_files();

    # copy them in place
    $pkg->_copy_files($lang_root, $files, $verbose);

    # make symlinks for files in htdocs/help/*, htdocs/js/*
    $pkg->_make_symlinks(lang => $lang, verbose => $verbose);
}

=item C<< pkg('Localization')->uninstall(lang => LANGUAGE_TAG, verbose => 1) >>

Uninstall a localization distribution.  The C<lang> argument must be a
RFC3066-style language tag representing a localization's root
directory below F<lang/>. The C<verbose> option will
cause uninstall steps to be logged to STDERR.

=back

=cut

sub uninstall {
    my ($pkg, %args) = @_;

    my ($lang, $verbose) = @args{qw(lang verbose)};

    croak "Missing 'lang' argument" unless $lang;

    my $lang_root = catdir(KrangRoot, 'lang', $lang);

    die "No localization distribution installed for language '$lang'"
      unless -e $lang_root && -d $lang_root;

    print STDERR "Removing $lang_root...\n" if $verbose;
    rmtree($lang_root)
      or croak "Couldn't delete directory '$lang_root': $!";

    # Remove symlinks for files in htdocs/help/, htdocs/js/
    $pkg->_remove_symlinks(lang => $lang, verbose => $verbose);

    # Remove localized templates in templates/*/$lang/
    $pkg->_remove_localized_templates(lang => $lang, verbose => $verbose);
}

=for Credit:
     The following private methods
         * _open_localization_dist(),
         * _list_files()
         * _copy_files()
     were largely stolen from Krang::AddOn

=cut

sub _copy_files {
    my ($pkg, $lang_root, $files, $verbose) = @_;

    for my $file (@$files) {

        # maybe make directory for $file
        my @parts      = splitdir($file);
        my $dir        = @parts > 1 ? catdir(@parts[0 .. $#parts - 1]) : '';
        my $target_dir = catdir($lang_root, $dir);
        my $target     = catfile($target_dir, $parts[-1]);

        unless (-d $target_dir) {
            print STDERR "Making directory $target_dir...\n"
              if $verbose;
            mkpath([$target_dir])
              or die "Unable to create directory '$target_dir': $!\n";
        }

        # copy the file
        print STDERR "Copying $file to $target...\n"
          if $verbose;
        my $target_file = catfile($target_dir, $parts[-1]);
        copy($file, $target_file)
          or die "Unable to copy '$file' to '$target_file': $!\n";
        chmod((stat($file))[2], $target_file)
          or die "Unable to chmod '$target_file' to match '$file': $!\n";
    }
}

sub _list_files {
    my $pkg = shift;

    # accumulator
    my @files = ();

    File::Find::find(
        {
            wanted => sub { push(@files, canonpath($_)) if -f $_ },
            no_chdir => 1
        },
        '.'
    );

    return \@files;
}

sub _open_localization_dist {
    my ($pkg, %args) = @_;
    my ($source, $verbose, $force) = @args{('src', 'verbose', 'force')};

    # don't try to chmod anything since it's counter-productive and
    # doesn't work on OSX for some damn reason
    local $Archive::Tar::CHOWN = 0;

    # open up the tar file
    my $tar = Archive::Tar->new();
    my $ok = eval { $tar->read($source); 1 };
    croak("Unable to read localization archive '$source' : $@\n")
      if $@;
    croak("Unable to read localization archive '$source' : " . Archive::Tar->error)
      if not $ok;

    # extract in temp dir
    my $dir = tempdir(
        DIR     => catdir(KrangRoot, 'tmp'),
        CLEANUP => 1
    );

    chdir($dir) or die "Unable to chdir to $dir: $!";

    $tar->extract($tar->list_files)
      or die("Unable to unpack archive '$source' : " . Archive::Tar->error);

    # if there's just a single directory here then enter it
    opendir(DIR, $dir) or die $!;
    my @entries = grep { not /^\./ } readdir(DIR);
    closedir(DIR);

    if (@entries == 1 and -d $entries[0]) {
        chdir($entries[0]) or die $!;
    }

    return $entries[0];
}

sub _make_symlinks {
    my ($pkg, %args) = @_;
    for my $slink ($pkg->_get_symlink_spec(%args)) {

        # Unlink first
        if (-l $slink->{dst}) {
            unlink $slink->{dst}
              or croak "Couldn't remove symlink '$slink->{dst}'";
        }

        # Then recreate
        if (-e $slink->{src}) {
            print STDERR "Symlinking '$slink->{src}' to '$slink->{dst}'\n" if $args{verbose};
            symlink($slink->{src}, $slink->{dst})
              or croak "Couldn't symlink $slink->{src} to $slink->{dst}";
        }
    }
}

sub _remove_symlinks {
    my ($pkg, %args) = @_;
    for my $slink ($pkg->_get_symlink_spec(%args)) {
        if (-l $slink->{dst}) {
            print STDERR "Removing symlink '$slink->{dst}'\n" if $args{verbose};
            unlink $slink->{dst}
              or croak "Couldn't remove symlink '$slink->{dst}'";
        }
    }
}

sub _get_symlink_spec {
    my ($pkg, %args) = @_;
    my $lang = $args{lang};
    return (
        {
            src => catdir(KrangRoot, 'lang',   $lang,  'help'),
            dst => catdir(KrangRoot, 'htdocs', 'help', $lang)
        },
        {
            src => catfile(KrangRoot, 'lang', $lang, 'htdocs', 'js', "calendar-$lang.js"),
            dst => catfile(KrangRoot, 'htdocs', 'js', "calendar-$lang.js")
        }
    );
}

sub _remove_localized_templates {
    my ($pkg, %args) = @_;

    my @dirs = ();

    # collect dirs to delete...
    File::Find::find(
        {
            wanted => sub {
                return unless -d;

                # only subdirs containing localized templates
                return unless (splitdir($_))[-1] eq $args{lang};

                push @dirs, $_;

            },
            no_chdir => 1,
        },
        catdir(KrangRoot, 'templates')
    );

    # ... now delete them recursively
    for my $dir (@dirs) {
        print STDERR "Removing localized templates subdir $dir\n" if $args{verbose};
        rmtree($dir)
          or die "Couldn't remove '$_': $!";
    }
}

1;
