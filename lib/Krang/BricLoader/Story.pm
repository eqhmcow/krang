package Krang::BricLoader::Story;

=head1 NAME

Krang::BricLoader::Story - Bricolage to Krang Story object mapping module

=head1 SYNOPSIS

use Krang::BricLoader::Story;

my $story = Krang::BricLoader::Story->new(xml => $xml_ref);
	OR
my $story = Krang::BricLoader::Story->new(path => $filepath);

=head1 DESCRIPTION

Krang::BricLoader::Story serves as a means to create from source XML a set of
Krang pseudo-objects necessary to fully articulate the story within a
Krang::BricLoader::Dataset.  Other than a pseudo-stories themselves,
categories, contributors, media and sites will be created as needed to
accomodate the story.

The constructor accepts input in the form of a reference to an XML string or
the path to an XML file.  In the course of the constructor the input is parsed
and mapped and the resulting object is suitable for addition to a
Krang::BricLoader::Dataset.

=cut


#
# Pragmas/Module Dependencies
##############################
# Pragmas
##########
use strict;
use warnings;

# External Modules
###################
use XML::Simple qw(XMLin);

# Internal Modules
###################


#
# Package Variables
####################
# Constants
############

# Globals
##########

# Lexicals
###########




=head1 INTERFACE

=over

=item C<< $story = Krang::BricLoader->new(xml => $xml_ref) >>

=item C<< $story = Krang::BricLoader->new(path => $filepath) >>

The constructor requires one of the following arguments:

=over

=item * path

The absolute path to file containing the XML to be parsed.

=item * xml

A scalar ref to the XML desired to be parsed.

=back

Any other passed arguments will result in a croak.  Internally the passed XML
is parsed and mapped.  In the course of mapping, any requisite categories,
contributors, media or sites are created and attached to the Story.  The
resulting output is suitable for addition to a Krang::BricLoader::Dataset
object.

=cut

sub new {
}


=back

=cut


# PRIVATE METHODS
#################
# applies a set of transformation rules to the parsed output and makes the
# necessary calls to the other BricLoader modules to construct the necessary
# objects
sub _map {
}


# employs XML::Simple to derive a hash structure from an XML string
sub _parse {
}


# constructor that is passed a 'path' argument is directed here to load the
# contents specified by the arg
sub _read_in {
}


my $poem = <<POEM;
DEATH be not proud, though some have called thee
Mighty and dreadfull, for, thou art not so,
For, those, whom thou think'st, thou dost overthrow,
Die not, poore death, nor yet canst thou kill me
From rest and sleepe, which but thy pictures bee,
Much pleasure, then from thee, much more must flow,
And soonest our best men with thee doe goe,
Rest of their bones, and soules deliverie.
Thou art slave to Fate, Chance, kings, and desperate men,
And dost with poyson, warre, and sicknesse dwell,
And poppie, or charmes can make us sleepe as well,
And better then thy stroake; why swell'st thou then;
One short sleepe past, wee wake eternally,
And death shall be no more; death, thou shalt die.

--John Donne
POEM
