package Krang::BricLoader::Story;

=head1 NAME

Krang::BricLoader::Story - Bricolage to Krang Story object mapping module

=head1 SYNOPSIS

use Krang::BricLoader::Story;

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
#use DateTime::Format::ISO8601;
use File::Path qw(mkpath rmtree);
use File::Spec::Functions qw(catdir catfile splitpath);
use File::Temp qw(tempdir);
use Time::Piece;
use XML::Simple qw(XMLin);

# Internal Modules
###################
use Krang::Conf qw(KrangRoot);
use Krang::Pref;
# BricLoader Modules
use Krang::BricLoader::Category;

#
# Package Variables
####################
# Constants
############

# Globals
##########

# Lexicals
###########
my $id = 1;



=head1 INTERFACE

=over

=item C<< $story = Krang::BricLoader->new(path => $filepath) >>

The constructor requires the following arguments:

=over

=item * path

The absolute path to file containing the XML to be parsed.

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
    my ($base, @stories, $new_path, $ref);

    # set tmpdir
    $self->{dir} = tempdir(DIR => catdir(KrangRoot, 'tmp'));

    croak("File '$path' not found on the system!") unless -e $path;
    $base = (splitpath($path))[2];
    $new_path = catfile($self->{dir}, $base);
    link($path, $new_path);

    $ref = XMLin($new_path,
                 forcearray => ['category', 'story'],
                 keyattr => 'hobbittses');
    unlink($new_path);
    croak("\nNo Stories defined in input.\n") unless exists $ref->{story};

    for my $s(@{$ref->{story}}) {
        # check for duplicates

        $s = bless($s, $pkg);

        # map simple fields
        $s->_map_simple;

        # fix categories and urls
        $s->_build_urls;

        # handle elements
        $s->{elements} = _deserialize_elements(delete $s->{elements});

        push @stories, $s;
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

    my $tmp = Time::Piece->strptime($self->{cover_date}, "%FT%TZ");
    my $t = localtime($tmp->epoch);

    # basic fields
    $writer->dataElement(story_id   => $self->{story_id});
    $writer->dataElement(class      => $self->{class});
    $writer->dataElement(title      => $self->{title});
    $writer->dataElement(slug       => $self->{slug});
    $writer->dataElement(version    => $self->{version});
    $writer->dataElement(cover_date => $t->datetime);
    $writer->dataElement(priority   => $self->{priority});
    $writer->dataElement(notes      => $self->{notes});

    # categories
    for my $c (@{$self->{categories}}) {
        $writer->dataElement(category_id => $c);

#        $set->add(object => $category, from => $self);
    }

    # urls
    $writer->dataElement(url => $_) for @{$self->{urls}};

    # contributors
    my %contrib_type = Krang::Pref->get('contrib_type');
    for my $contrib ($self->{contribs}) {
        next unless defined $contrib && $contrib->isa('Krang::Contributor');
        $writer->startTag('contrib');
        $writer->dataElement(contrib_id => $contrib->contrib_id);
        $writer->dataElement(contrib_type =>
                             $contrib_type{$contrib->selected_contrib_type()});
        $writer->endTag('contrib');

        $set->add(object => $contrib, from => $self);
    }

    # serialize elements
    $writer->startTag('element');
    $writer->dataElement(class => $self->{class});
    $writer->dataElement(data => $self->{data});
    for my $e(@{$self->{elements}}) {
        next unless ref $e;
        $self->_serialize_element($writer, $e);
    }
    $writer->endTag('element');

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
# sets category_id and url entities based on 'categories' entity
sub _build_urls {
    my $self = shift;
    my $tmp = delete $self->{categories};
    my $cats = $tmp->{category};

      for my $i(0..$#$cats) {
        my $path = $i == 0 ? $cats->[$i]->{content} : $cats->[$i];
        my ($id, $url) = Krang::BricLoader::Category->get_id_url($path);

        croak("No category id and/or url found associated with Bricolage" .
              " category '$path'") unless ($id && $url);

        if (exists $self->{slug} && $self->{slug} ne '') {
            $url = join('/', $url, $self->{slug});
            $url =~ s#/+#/#g;
            $url .= '/' if $url !~ m#/$#;
        }

        push @{$self->{categories}}, $id;
        push @{$self->{urls}}, $url;
    }
}

# fix subelements
sub _deserialize_elements {
    my $elements = shift;
    my $data = $elements->{data};
    my $obj = $elements->{container};
    my $tmp;

    if ($data) {
        $data = ref $data eq 'ARRAY' ? $data : [$data];
        for my $d(@$data) {
            my $class = lc $d->{element};
            my $data = $d->{content} || '';
            $tmp->[$d->{order}] = {class => $class, data => $data};
        }
    }

    if ($obj) {
        $obj = ref $obj eq 'ARRAY' ? $obj : [$obj];
        for my $o(@$obj) {
            next if exists $o->{related_media_id};
            my $class = lc $o->{element};
            my $data = exists $o->{related_story_id} ? $o->{related_story_id} :
              '';
            $tmp->[$o->{order}] = {class => $class, data => $data,
                                   elements => _deserialize_elements($o)};
        }
    }

    return $tmp;
}

# map bricolage fields to krang equivalents
sub _map_simple {
    my $self = shift;

    # id => story_id
    $self->{story_id} = $self->{id};

    # name becomes title
    $self->{title} = delete $self->{name};

    # element becomes class
    $self->{class} = lc delete $self->{element};

    # set version to 1
    $self->{version} = 1;
}

#
sub _serialize_element {
    my ($self, $writer, $e) = @_;
    $writer->startTag('element');
    $writer->dataElement(class => $e->{class});
    $writer->dataElement(data => $e->{data});
    if ($e->{elements}) {
        for (@{$e->{elements}}) {
            next unless exists $_->{class} && $_->{class};
            $self->_serialize_element($writer, $_);
        }
    }
    $writer->endTag('element');
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
