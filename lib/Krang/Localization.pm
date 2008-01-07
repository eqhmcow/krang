package Krang::Localization;
use strict;
use warnings;

use Krang::ClassLoader ClassFactory => qw(pkg);
use Krang::ClassLoader Conf         => qw(KrangRoot DefaultLanguage AvailableLanguages);
use Krang::ClassLoader Log          => qw(debug);
use Krang::ClassLoader Session      => qw(%session);
use Krang::ClassLoader 'File';
use Krang::ClassLoader 'ConfigApacheFormat';

use I18N::LangTags qw(is_language_tag);
use I18N::LangTags::List;
use File::Spec::Functions qw(catfile);

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

=head1 DESCRIPTION

This module provides localization to Krang by exporting the functions
localize() and localize_template().  The latter is primarily used in
L<bin/krang_localize_templates> to pre-compile localized templates.

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
	debug("Unable to find key '$key' in lang/perl.$language.");
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

	$$textref =~ s|<tmpl_lang ([^>]+)>|$1|gx;

    } else {

	my $lexicon = pkg('Localization')->get_lexicon($language);

	if ($ENV{KRANG_RECORD_MISSING_LOCALIZATIONS}) {
	    debug_template_localization->($textref, $language);
	} else {
	    $$textref =~ s{<tmpl_lang ([^>]+)>}{$lexicon->get($1) || $1}egx;
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
	    $$textref =~ s|<tmpl_lang ([^>]+)>|$translation|;
	} else {
	    # remember missing localizations in templates
	    $$textref =~ s|<tmpl_lang ([^>]+)>|$1|;
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

1;
