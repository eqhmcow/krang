package Krang::BricLoader::Site;

=head1 NAME

Krang::BricLoader::Site -

=head1 SYNOPSIS

 use Krang::BricLoader::Site;

 my @sites = Krang::BricLoader::Site->new(path => $filepath);

 # add set of sites to dataset or one at a time
 $set->add(object => $_) for @sites;

 # class methods
 ################
 my $path = '/bricolage-top-level-category-that-maps-to-a-site';
 my $site_id		= Krang::BricLoader::Site->get_site_id($path);
 my $url		= Krang::BricLoader::Site->get_url($path);
 my $true_or_false 	= Krang::BricLoader::Site->is_top($path);

=head1 DESCRIPTION

Sites are an abstraction from top-level categories in Bricolage but are objects
in their own right within Krang.  This receives user-generated XML input that
explicity describes the relationships between 'Site's and categories so that
each set of asset types may be successfully related within a
Krang::BricLoader::DataSet.

Input should be of the following form:

<?xml version="1.0" encoding="UTF-8"?>
<sites xmlns:xsi="http://www.w3.org/2001/XMLSchema"
 xsi:noNameSpaceSchemaLocation="bric_sites.xsd">
	<site>
		<category>/bricolage_category/</category>
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
use Carp qw(verbose croak);
use Cwd qw(fastcwd);
use File::Path qw(mkpath rmtree);
use File::Spec::Functions qw(catdir catfile splitpath);
use File::Temp qw(tempdir);
use XML::Simple qw(XMLin);

# Internal Modules
###################
use Krang::Conf qw(KrangRoot);
#use Krang::DataSet qw(_validate_file);
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
my $id = 1;
my %site_info;


=head1 INTERFACE

=over

=item C<< @sites = Krang::BricLoader::Site->new(path => 'sites.xml') >>

Constructs objects from an xml file.  XML must be of the form describe in
DESCRIPTION or an exception will be thrown.

=cut

sub new {
    my ($pkg, %args) = @_;
    my $self = bless({},$pkg);
    my $xml = $args{xml};
    my $path = $args{path};
    my ($base, $new_path, $ref, @sites);

    croak("The required 'path' arg was not passed or is NULL.") unless $path;

    # set tmpdir
    $self->{dir} = tempdir(DIR => catdir(KrangRoot, 'tmp'));

    croak("File '$path' not found on the system!") unless -e $path;
    $base = (splitpath($path))[2];
    $new_path = catfile($self->{dir}, $base);
    link($path, $new_path);

#    $self->_validate_input($new_path);
    $ref = XMLin($new_path,
                    forcearray => ['site'],
                    keyattr => 'hobbittses');
    unlink($new_path);
    croak("\nNo SITES defined in input.\n") unless exists $ref->{site};

    for (@{$ref->{site}}) {
        $_->{site_id} = $id++;
        $site_info{$_->{category}} = {site_id => $_->{site_id},
                                      url => $_->{url}};
        push @sites, bless($_, $pkg);
    }

    return @sites;
}


=item C<< $site_id = Krang::BricLoader::Site->get_site_id( $path ) >>

Returns the site_id associated with the Bricolage category path passed in $path

=cut

sub get_site_id {
    my ($self, $path) = @_;
    croak("Path '$path' is not a valid top_level Bricolage category.")
      unless $self->is_top($path);
    return $site_info{$path}->{site_id};
}


=item C<< $url = Krang::BricLoader::Site->get_url( $path ) >>

Returns the url associated with the Bricolage category path passed in $path

=cut

sub get_url {
    my ($self, $path) = @_;
    croak("Path '$path' is not a valid top_level Bricolage category.")
      unless $self->is_top($path);
    return $site_info{$path}->{url};
}


=item C<< ($true || $false) = Krang::BricLoader::Site->is_top( $path ) >>

Returns true if the passed path is one of the top-level categories that maps to
a site root category in krang

=cut

sub is_top {
    my ($self, $path) = @_;
    return exists $site_info{$path};
}


=item C<< ($true || $false) = Krang::BricLoader::Site->multiple_sites >>

Returns true if more than one site object has been created.

=cut

sub multiple_sites {
    return $id > 2;
}


=item C<< $site->serialize_xml(writer => $writer, set => $set) >>

Serialize as XML.  See Krang::DataSet for details.

=cut

sub serialize_xml {
    my ($self, %args) = @_;
    my ($writer, $set) = @args{qw(writer set)};
    local $_;

    # open up <site> linked to schema/site.xsd
    $writer->startTag('site',
                      "xmlns:xsi" =>
                      "http://www.w3.org/2001/XMLSchema-instance",
                      "xsi:noNamespaceSchemaLocation" =>
                      'site.xsd');

    $writer->dataElement($_, $self->{$_})
      for qw(site_id url preview_url publish_path preview_path);
    $writer->endTag('site');
}


=back

=cut


# Private Methods
##################
# make sure input conforms to the xml schema
sub _validate_input {
    my ($self, $path) = @_;

    # save cwd, change to tmpdir
    my $old_cwd = fastcwd;
    chdir($self->{dir}) or die("Unable to change to '$self->{dir}': $!");

    # link schema to tmpdir
    my $xsd = catfile(KrangRoot, 'schema', 'bric_sites.xsd');
    my $lnkd_xsd = catfile($self->{dir}, 'bric_sites.xsd');
    link($xsd, $lnkd_xsd);

    # validate file
    eval {$self->_validate_file($path)};
    if ($@ and ref $@ and $@->isa('Krang::DataSet::InvalidFile')) {
        my $msg = "\n'$path' failed schema validation.\n";
        Krang::DataSet::ValidationFailed->throw(errors => {$@->file, $@->err},
                                                message => $msg);
    } elsif ($@) {
        croak($@);
    }

    # unlink link
    unlink($lnkd_xsd) or die("Unable to delete '$lnkd_xsd': $!");

    # restore cwd
    chdir($old_cwd) or die("Unable to change to '$old_cwd': $!");
}


sub DESTROY {
    my $self = shift;
    rmtree($self->{dir}) if $self->{dir};
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
