package Krang::BricLoader::Category;

=head1 NAME

Krang::BricLoader::Category -

=head1 SYNOPSIS

 use Krang::BricLoader::Category;

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
use Krang::BricLoader::Site;

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
my %parent_info;




=head1 INTERFACE

=over

=item C<< @categories = Krang::BricLoader::Category->new(path=> 'cats.xml') >>

Constructs an array of objects from an xml file.

=cut

sub new {
    my ($pkg, %args) = @_;
    my $self = bless({},$pkg);
    my $path = $args{path};
    my $xml = $args{xml};
    my ($base, @categories, $new_path, $ref);

    croak("A value must be passed with either the 'path' or 'xml' arg.")
      unless $path || $xml;

    # set tmpdir
    $self->{dir} = tempdir(DIR => catdir(KrangRoot, 'tmp'));

    if ($path) {
        croak("File '$path' not found on the system!") unless -e $path;
        $base = (splitpath($path))[2];
        $new_path = catfile($self->{dir}, $base);
        link($path, $new_path);
    } elsif ($xml) {
        $new_path = $xml;
    }

    $ref = XMLin($new_path,
                 forcearray => ['category'],
                 keyattr => 'hobbittses');
    unlink($new_path);
    croak("\nNo Categories defined in input.\n")
      unless exists $ref->{category};

    for my $c(@{$ref->{category}}) {
        # skip root categories, created by the Site object????
        next if ($c->{path} eq '/' || exists $parent_info{$c->{path}});

        $c = bless($c, $pkg);
        $c->_fixup_object;
        $c->_add_info;

        push @categories, $c;
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
        next if ($_ eq 'parent_id' &&
                 (not(defined($self->{parent_id})) ||
                  $self->{parent_id} eq ''));
        $writer->dataElement($_ => $self->{$_});
    }

    # element bs
    $writer->startTag('element');
    $writer->dataElement(class => 'category');
    $writer->dataElement(data => '');
    $writer->endTag('element');

    $writer->endTag('category');
}


=item C<< ($id, $url) = Krang::BricLoader::Category->get_id_url( $path ) >>

Method that returns the 'category_id' and 'url' information associated with a
give Bricolage category path.  undef is returned if no information is found.

=cut

sub get_id_url {
    my ($self, $path) = @_;
    my $info = $parent_info{$path};
    return unless ref $info;

    my ($id, $url) = map {$info->{$_}} qw/category_id url/;
    return ($id, $url);
}


sub DESTROY {
    my $self = shift;
    rmtree($self->{dir}) if $self->{dir};
}


=back

=cut



# Private Methods
##################
sub _add_info {
    my $self = shift;
    $parent_info{$self->{_path}}->{$_} = $self->{$_}
      for (qw/category_id site_id url/);
}

sub _build_url {
    my $self = shift;
    $self->{url} = join('/', $self->{parent_path}, $self->{dir}) . '/';
    $self->{url} =~ s#/+#/#g;
}

sub _fixup_object {
    my $self = shift;
    my $path = $self->{path};

    # get id
    $self->{category_id} = $id++;

    # get dir
    $self->_set_dir;

    # is it a mapping category
    if (Krang::BricLoader::Site->is_top($path)) {
        # parent id is null
        $self->{parent_path} = Krang::BricLoader::Site->get_url($path);
        $self->{site_id} = Krang::BricLoader::Site->get_site_id($path);
    } else {
        # set parent path
        (my $lookup_path = $path) =~ s#/\Q$self->{dir}\E$##;

        # get parent_info hash
        my $info = $parent_info{$lookup_path};

        croak("No info about category with parent_path " .
              "'$self->{parent_path}'.") unless ref $info eq 'HASH';

        # set parent_id, parent_path, site_id
        $self->{parent_id} = $info->{category_id};
        $self->{parent_path} = $info->{url};
        $self->{site_id} = $info->{site_id};
    }

    # preserve old path info, future lookups are based on Bricolage category
    # paths not krang urls...
    $self->{_path} = $path;

    # subtract site mapping path
    $self->_remove_top_level if Krang::BricLoader::Site->multiple_sites;

    # build url
    $self->_build_url;
}

sub _remove_top_level {
    my $self = shift;
    my $path = $self->{path};
    my @parts = split('/', $path);
    $self->{path} = join('/', @parts[2..$#parts]);
}

sub _set_dir {
    my $self = shift;
    my $path = $self->{path};

    if (Krang::BricLoader::Site->is_top($path)) {
        $self->{dir} = '/';
    } else {
        ($self->{dir}) = ($path =~ m#([^/]+)$#);
    }
}




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
