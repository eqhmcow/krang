package Krang::Localization;
use strict;
use warnings;

use Krang::ClassLoader ClassFactory => qw(pkg);
use Krang::ClassLoader Conf         => qw(KrangRoot InstanceElementSet
                                          DefaultLanguage AvailableLanguages
                                         );
use Krang::ClassLoader Log          => qw(debug);
use Krang::ClassLoader Session      => qw(%session);
use Krang::ClassLoader 'File';

our @EXPORT_OK = qw(%LANG localize);

use Carp qw(croak);

use base 'Exporter';

=head1 NAME

Krang::Localization - Krang localization module

=head1 SYNOPSIS

   use Krang::ClassLoader Localization => qw(localize);
   $localized_string = localize('some string');

   # All AvailableLanguages set in addons/Localization/conf/krang.conf
   # are available via the exported %LANG hash, with keys being the
   # RFC3060-style language tags and values being the corresponding
   # language names.
   my $lang = $LANG{en}; # yields 'English';

=head1 DESCRIPTION

This module provides localization to Krang by exporting the method
localize().

=head1 INTERFACE

=over 4

=item C<< localize('Edit') >>

This exported method returns the localized version of its argument
according to the user's language setting.  It returns its argument
unchanged if no lexicon entry is found or if the language is set to
English.  For German, a lexicon entry may be

    "Edit Story"               "Story bearbeiten"

=back

=item C<< localize('WEEKDAYS') >>

Returns a localized list of weekday names according to the user's
language setting. For French, the lexicon entry has to be

    "Weekdays"   Dim Lun Mar Mer Jeu Ven Sam

=back

=cut

# localization stub
sub localize { return $_[0] }

our %LANG = ( en => 'English', 'de-DE' => 'Deutsch' );
