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

use I18N::LangTags qw(is_language_tag);
use I18N::LangTags::List;
use File::Spec::Functions qw(catfile catdir splitdir canonpath);
use File::Temp qw(tempdir tempfile);
use File::Path;
use File::Find ();
use Archive::Tar;
use File::Copy qw(copy);
use Cwd qw(fastcwd);

our @EXPORT_OK = qw(%LANG %missing localize localize_template);

use Carp qw(croak);

use base 'Exporter';

our (%LANG, %L10N, %missing);

=head1 NAME

Krang::Localization - Krang localization module

=head1 SYNOPSIS

   use Krang::ClassLoader Localization => qw(localize);
   $localized_string = localize('some string');

   # All AvailableLanguages set in conf/krang.conf
   # are available via the exported %LANG hash, with keys being the
   # RFC3066-style language tags and values being the corresponding
   # language names.
   my $lang = $LANG{en}; # yields 'English';

   # install a localization distribution
   pkg('Localization')->install(src => '/path/to/Krang-Localization-Deutsch-3.01.tar.gz');

   # uninstall a localization distribution
   pkg('Localization')->uninstall(lang => de);

=head1 DESCRIPTION

This module provides localization to Krang by exporting the functions
localize() and localize_template().  The latter is primarily used in
L<bin/krang_localize_templates> to pre-compile localized templates.
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

=cut

sub localize {
    my $key = shift;

    my $language = $session{language} || DefaultLanguage;

    # return as-is
    return $key if not $language       # krang startup
                or $language eq 'en'   # English default
                or not length($key);   # empty string

    debug("localize($key) called from " . (caller)[0]. ", line " . (caller)[2] . ".");

    # localize it
    my @localized = $L10N{$language}->get($key);

    unless (defined($localized[0])) {
	debug("Unable to find key '$key' in lang/$language/perl.dict.");
	return $key;
    }

    return wantarray ? @localized : $localized[0];
}

=item C<localize_template($textref, $language_tag)>

All strings in $textref wrapped in <tmpl_lang ...> tags are localized
for the language indicated by $language_tag. $textref should contain a
reference to a string containing a template, $language_tag is supposed
to be a valid RFC3066-style tag representing a valid entry into the
%L10N lexicon hash.

=cut

sub localize_template {
    my ($textref, $language) = @_;

    if ($language eq 'en') {

	$$textref =~ s|<tmpl_lang\s+([^>]+)>|$1|gx;

    } else {

	my $lexicon = pkg('Localization')->get_lexicon($language);

	if ($ENV{KRANG_RECORD_MISSING_LOCALIZATIONS}) {
	    debug_template_localization->($textref, $language);
	} else {
	    $$textref =~ s{<tmpl_lang\s+([^>]+)>}{$lexicon->get($1) || $1}egx;
	}
    }
}

=item C<debug_localize_template($textref, $language)>

This method is only useful for debugging and testing.  It's used when
calling L<bin/krang_localize_templates> with the C<--print_missing>
option to find strings in templates whose localization is missing in
the lexicon indicated by $language.

This method is triggered if $ENV{KRANG_RECORD_MISSING_LOCALIZATIONS} is set to a
true value.

=cut

sub debug_template_localization {
    my ($textref, $language) = @_;

    my $lexicon = pkg('Localization')->get_lexicon($language);

    while ($$textref =~ m|<tmpl_lang ([^>]+)>|g) {
	my $key = $1;
	my $pos = $-[0];
	my $translation = $lexicon->get($key);

	if (defined($translation)) {
	    pos($pos);
	    $$textref =~ s|<tmpl_lang\s+([^>]+)>|$translation|;
	} else {
	    # remember missing localizations in templates
	    $$textref =~ s|<tmpl_lang\s+([^>]+)>|$1|;
	    $missing{$language}{$key}++;
	}
    }
}

=item C<< pkg('Localization')->get_lexicon($language) >>

Returns a Krang::ConfigApacheFormat object representing a lexicon
mapping English to the language indicated the methods
argument. $language must be a valid RFC3066-style language tag.

Croaks if $language is not a valid language tag or if no lexicon for
the given language is found in the package hash %L10N.

=back

=cut

sub get_lexicon {
    my ($pkg, $lang) = @_;

    croak "'$lang' is not a valid language tag"
      unless is_language_tag($lang);

    my $lexicon = $L10N{$lang};

    return $lexicon ? $lexicon : croak("No lexicon for language '$lang'");
}

# called at compile time to load the available lexicons in %L10N
sub _load_localization {
    for my $lang (grep { $_ ne 'en'} AvailableLanguages) {

	next unless defined($lang) and length($lang);

	croak("$lang is not a RFC3066-style language tag")
	  unless is_language_tag($lang);

	# read also addon lexicons
	my @files = reverse pkg('File')->find_all(catfile('lang', $lang, 'perl.dict'));

	# read the main lexicons in memory
	my $l10n = Krang::ConfigApacheFormat->new(case_sensitive => 1);

	$l10n->read($_) for @files;

	# store the lexicon in package %L10N hash
	$L10N{$lang} = $l10n;

	# fill the exported %LANG hash
	$LANG{$lang} = I18N::LangTags::List::name($lang);
    }

    # don't forget the default language
    $LANG{en} = I18N::LangTags::List::name('en');
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
    my ($source, $verbose, $downgrade, $version) = @args{ qw(src verbose downgrade version) };

    croak("Missing src param!") unless $source;

    my $old_dir = fastcwd();

    # find addon dir, opening the tar file if needed
    my $lang = $pkg->_open_localization_dist(%args);

    # lang root
    my $lang_root = catdir(KrangRoot, 'lang', $lang);

    # install a lower version than Krang's version?
    if ($version && $version < $Krang::VERSION) {
	die "You want to install version v$version which is lower than Krang's version v$Krang::VERSION.\n"
	  . "This may result in missing lexicon entries.\n"
	  . "Specify '--downgrade' if you really want to proceed.\n" unless $downgrade;
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
}

=item C<< pkg('Localization')->uninstall(lang => LANGUAGE_TAG, verbose => 1) >>

Uninstall a localization distribution.  The C<lang> argument must be a
RFC3066-style language tag representing a localization's root
directory below F<lang/>. The C<verbose> option will
cause uninstall steps to be logged to STDERR.

=cut

sub uninstall {
    my ($pkg, %args) = @_;

    my ($lang, $verbose) = @args{ qw(lang verbose) };

    croak "Missing 'lang' argument" unless $lang;

    my $lang_root = catdir(KrangRoot, 'lang', $lang);

    die "No localization distribution installed for language '$lang'"
      unless -e $lang_root && -d _;

    print STDERR "Removing $lang_root...\n" if $verbose;
    rmtree($lang_root)
      or "Couldn't delete directory '$lang_root': $!";
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
	my @parts = splitdir($file);
	my $dir   = @parts > 1 ? catdir(@parts[0 .. $#parts - 1]) : '';
	my $target_dir = catdir($lang_root, $dir);
	my $target = catfile($target_dir, $parts[-1]);

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

    File::Find::find({
	  wanted => sub { push(@files, canonpath($_)) if -f $_ },
	  no_chdir => 1
	 },
	 '.');

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
    croak("Unable to read localization archive '$source' : ". Archive::Tar->error)
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

    return $entries[0];
}

1;
