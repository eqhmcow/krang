package Krang::BricLoader::Category;

=head1 NAME

Krang::BricLoader::Category -

=head1 SYNOPSIS

 use Krang::BricLoader::Category;

 my @categories = Krang::BricLoader::Category->new(xml_ref => \$xml);
	OR
 my @categories = Krang::BricLoader::Category->new(path => $filepath);

 # add categories to dataset
 $set->add(object => $_) for @categories;

=head1 DESCRIPTION



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

=item C<< @categories = Krang::BricLoader::Category->new(xml => $xml_ref) >>

=item C<< @categories = Krang::BricLoader::Category->new(path=> 'cats.xml') >>

Constructs an array of objects from a reference to an xml string or an xml
file.

=cut

sub new {
    my ($pkg, %args) = @_;
    my $self = bless({},$pkg);
    my $xml = $args{xml};
    my $path = $args{path};
    my ($new_path, @categories);

    # set tmpdir
    $self->{dir} = tempdir(DIR => catdir(KrangRoot, 'tmp'));

    if ($xml) {
        # write out file to tmpdir
        $new_path = catfile($self->{dir}, 'bric_sites.xml');
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
                    forcearray => ['site'],
                    keyattr => 'hobbittses');
    unlink($new_path);
    croak("\nNo Categories defined in input.\n")
      unless exists $ref->{category};

    for (@{$ref->{category}}) {
        # skip root categories, created by the Site object????
        next if $_->{path} eq '/';

        # check for duplicates

        push @categories, bless($_, $pkg);
    }

    return @categories;
}


=item C<< $category->serialize_xml(writer => $writer, set => $set) >>

Serialize as XML.  See Krang::DataSet for details.

=cut

sub serialize_xml {
    my ($self, %args) = @_;
    my ($writer, $set) = @args{qw(writer set)};
    local $_;

    # open up <category> linked to schema/category.xsd
    $writer->startTag('category',
                      "xmlns:xsi" =>
                      "http://www.w3.org/2001/XMLSchema-instance",
                      "xsi:noNamespaceSchemaLocation" => 'category.xsd');

    for (qw/category_id site_id parent_id dir url/) {
        # don't add a parent entity if its NULL
        next if $_ eq 'parent_id' && $self->{parent_id} eq '';
        $writer->dataElement($_ => $self->{$_});
    }

    # element bs
    $writer->startTag('element');
    $writer->dataElement(class => 'category');
    $writer->dataElement(data => '');
    $writer->endTag('element');

    $writer->endTag('category');
}


sub DESTROY {
    my $self = shift;
    rmtree($self->{dir}) if $self->{dir};
}


=back

=cut



# Private Methods
##################



my $poem = <<POEM;
The Tiger

TIGER, tiger, burning bright
In the forests of the night,
What immortal hand or eye
Could frame thy fearful symmetry?

In what distant deeps or skies
Burnt the fire of thine eyes?
On what wings dare he aspire?
What the hand dare seize the fire?

And what shoulder and what art
Could twist the sinews of thy heart?
And when thy heart began to beat,
What dread hand and what dread feet?

What the hammer? what the chain?
In what furnace was thy brain?
What the anvil? What dread grasp
Dare its deadly terrors clasp?

When the stars threw down their spears,
And water'd heaven with their tears,
Did He smile His work to see?
Did He who made the lamb make thee?

Tiger, tiger, burning bright
In the forests of the night,
What immortal hand or eye
Dare frame thy fearful symmetry?

--William Blake
POEM
