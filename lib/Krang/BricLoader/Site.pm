package Krang::BricLoader::Site;

=head1 NAME

Krang::BricLoader::Site -

=head1 SYNOPSIS

 use Krang::BricLoader::Site;

 my $site = Krang::BricLoader::Site->new(xml_ref => \$xml);
	OR
 my @sites = Krang::BricLoader::Site->new(path => $filepath);

 # where $set is a Krang::BricLoader::DataSet
 $set->add(object => $site);

 # obtain Krang XML representation of the Site
 my $xml = $site->serialize_xml;

=head1 DESCRIPTION

Sites are an abstraction from top-level categories in Bricolage but are objects
in their own right within Krang.  This receives user-generated XML input that
explicity describes the relationships between 'Site's and categories so that
each set of asset types may be successfully related within a
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


=item C<< new >>



=cut

sub new {
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
