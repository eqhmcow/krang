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
Krang::BricLoader::DataSet.  Other than a pseudo-stories themselves,
categories, contributors, media and sites will be created as needed to
accomodate the story.

The constructor accepts input in the form of a reference to an XML string or
the path to an XML file.  In the course of the constructor the input is parsed
and mapped and the resulting object is suitable for addition to a
Krang::BricLoader::DataSet.

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
use Carp qw(verbose croak);
use File::Path qw(mkpath rmtree);
use File::Spec::Functions qw(catdir catfile splitpath);
use File::Temp qw(tempdir);
use XML::Simple qw(XMLin);

# Internal Modules
###################
use Krang::Conf qw(KrangRoot);
use Krang::Pref;


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
resulting output is suitable for addition to a Krang::BricLoader::DataSet
object.

=cut

sub new {
    my ($pkg, %args) = @_;
    my $self = bless({},$pkg);
    my $xml = $args{xml};
    my $path = $args{path};
    my ($new_path, @stories);

    # set tmpdir
    $self->{dir} = tempdir(DIR => catdir(KrangRoot, 'tmp'));

    if ($xml) {
        # write out file to tmpdir
        $new_path = catfile($self->{dir}, 'bric_stories.xml');
        my $wh = IO::File->new(">$new_path");
        $wh->print($$xml);
        $wh->close();
    } elsif ($path) {
        croak("File '$path' not found on the system!") unless -e $path;
        my $base = (splitpath($path))[2];
        $new_path = catfile($self->{dir}, $base);
        link($path, $new_path);
    } else {
        croak("A value must be passed with either the 'path' or 'xml' arg.");
    }

    my $ref = XMLin($new_path,
                    forcearray => ['story'],
                    keyattr => 'hobbittses');
    unlink($new_path);
    croak("\nNo Stories defined in input.\n") unless exists $ref->{story};

    for (@{$ref->{story}}) {
        # check for duplicates

        # associate media

        # associate stories

        push @stories, bless($_, $pkg);
    }

    return @stories;
}


=item C<< $category->serialize_xml(writer => $writer, set => $set) >>

Serialize as XML.  See Krang::DataSet for details.

=cut

sub serialize_xml {
    my ($self, %args) = @_;
    my ($writer, $set) = @args{qw(writer set)};
    local $_;

    # open up <story> linked to schema/story.xsd
    $writer->startTag('story',
                      "xmlns:xsi" =>
                      "http://www.w3.org/2001/XMLSchema-instance",
                      "xsi:noNamespaceSchemaLocation" =>
                      'story.xsd');

    # basic fields
    $writer->dataElement(story_id   => $self->{story_id});
#?    $writer->dataElement(class      => $self->class->name);
    $writer->dataElement(title      => $self->{title});
    $writer->dataElement(slug       => $self->{slug});
    $writer->dataElement(version    => $self->{version});
    $writer->dataElement(cover_date => $self->cover_date->datetime);
    $writer->dataElement(priority   => $self->{priority});
    $writer->dataElement(notes      => $self->notes);

    # categories
    for my $category ($self->{categories}) {
        $writer->dataElement(category_id => $category->{category_id});

        $set->add(object => $category, from => $self);
    }

    # urls
    $writer->dataElement(url => $_) for $self->{urls};

    # contributors
#    my %contrib_type = Krang::Pref->get('contrib_type');
#    for my $contrib ($self->{contribs}) {
#        $writer->startTag('contrib');
#        $writer->dataElement(contrib_id => $contrib->contrib_id);
#        $writer->dataElement(contrib_type =>
#                             $contrib_type{$contrib->selected_contrib_type()});
#        $writer->endTag('contrib');

#        $set->add(object => $contrib, from => $self);
#    }

    # serialize elements
#    $self->element->serialize_xml(writer => $writer,
#                                  set    => $set);

    # all done
    $writer->endTag('story');
}


sub DESTROY {
    my $self = shift;
    rmtree($self->{dir}) if $self->{dir};
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
