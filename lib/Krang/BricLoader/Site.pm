package Krang::BricLoader::Site;

=head1 NAME

Krang::BricLoader::Site -

=head1 SYNOPSIS

 use Krang::BricLoader::Site;

 my $site = Krang::BricLoader::Site->new(xml_ref => \$xml);
	OR
 my @sites = Krang::BricLoader::Site->new(path => $filepath);

 # add set of sites to dataset or one at a time
 $set->add_site(\@sites);
 $set->add_site($site);

 # obtain Krang XML representation of the Site
 my $xml = $site->serialize_xml;

=head1 DESCRIPTION

Sites are an abstraction from top-level categories in Bricolage but are objects
in their own right within Krang.  This receives user-generated XML input that
explicity describes the relationships between 'Site's and categories so that
each set of asset types may be successfully related within a
Krang::BricLoader::DataSet.

Input should be of the following form:

<?xml version="1.0" encoding="UTF-8"?>
<sites xmlns:xsi="http://www.w3.org/2001/XMLSchema"
 xsi:noNameSpaceSchemaLocation="sites.xsd">
	<site>
		<category>bricolage_category/</category>
		<preview_path>/full/preview/path</preview_path>
		<publish_path>relative/publish/path</publish_path>
		<preview_url>preview.site.com</preview_url>
		<url>site.com</url>
	</site>
	<site>
	...
	</site>
</sites>

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
use Krang::Conf;
# BricLoader mods :)
use Krang::BricLoader::Category;
use Krang::BricLoader::DataSet;

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


=item C<< $site = Krang::BricLoader::Site->new(xml => $xml_ref) >>

=item C<< @sites = Krang::BricLoader::Site->new(path => 'sites.xml') >>

Constructs a single or set of objects from a reference to an xml string or
an xml file respectively.  XML must be of the form describe in DESCRIPTION or
an exception will be thrown.

=cut

sub new {
    my ($pkg, %args) = @_;
    my $self = bless({}, $pkg);
    my $xml = $args{xml};
    my $path = $args{path};

    if ($xml || ($path && -e $path)) {
        _validate_input(string => $xml) if $xml;
        _validate_input(file => $path) if $path;
    } else {
        croak("A value must be passed with either the 'path' or 'xml' arg.");
    }

    return $path;
}

# make sure input conforms to the xml schema
sub _validate_input {
    my ($self, %args) = @_;
}

=item C<< serialize_xml >>



=cut

sub serialize_xml {
}



=back

=cut



# Private Methods
##################

# Comments:
sub _map {
}


# Comments:
sub _parse {
}


# Comments:
sub _read_in {
}





my $poem = <<POEM;
The Emperor of Ice-Cream

Call the roller of big cigars,
The muscular one, and bid him whip
In kitchen cups concupiscent curds.
Let the wenches dawdle in such dress
As they are used to wear, and let the boys
Bring flowers in last month's newspapers.
Let be be finale of seem.
The only emperor is the emperor of ice-cream.

Take from the dresser of deal,
Lacking the three glass knobs, that sheet
On which she embroidered fantails once
And spread it so as to cover her face.
If her horny feet protrude, they come
To show how cold she is, and dumb.
Let the lamp affix its beam.
The only emperor is the emperor of ice-cream.

--Wallace Stevens
POEM
