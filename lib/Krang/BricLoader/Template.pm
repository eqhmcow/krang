package Krang::BricLoader::Template;

=head1 NAME

Krang::BricLoader::Template -

=head1 SYNOPSIS



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
use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile splitpath);
use File::Temp qw(tempdir);
use MIME::Base64;
use Time::Piece;
use XML::Simple qw(XMLin);

# Internal Modules
###################
use Krang::Conf qw(KrangRoot);
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


=item C<< Krang::BricLoader::Template->new() >>



=cut

sub new {
    my ($pkg, %args) = @_;
    my $self = bless({},$pkg);
    my $path = $args{path};
    my $xml = $args{xml};
    my ($base, @templates, $new_path, $ref);

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
                 forcearray => ['template'],
                 keyattr => 'hobbittses');
    unlink($new_path);
    croak("\nNo Templates defined in input.\n") unless exists $ref->{template};

    for my $t(@{$ref->{template}}) {
        # skip anything except .tmpl files
        next unless $t->{file_name} =~ /\.tmpl$/;

        $t = bless($t, $pkg);

        push @templates, $t->_map;
    }

    return @templates;
}


=item C<< $template->serialize_xml() >>



=cut

sub serialize_xml {
    my ($self, %args) = @_;
    my ($writer, $set) = @args{qw(writer set)};
    local $_;

    # open up <template> linked to schema/template.xsd
    $writer->startTag('template',
                      "xmlns:xsi" =>
                      "http://www.w3.org/2001/XMLSchema-instance",
                      "xsi:noNamespaceSchemaLocation" =>
                      'template.xsd');

    $writer->dataElement(template_id => $self->{template_id});
    $writer->dataElement(filename => $self->{filename});
    $writer->dataElement(url => $self->{url});
    $writer->dataElement(category_id => $self->{category_id})
      if $self->{category_id};
    $writer->dataElement(content => $self->{content});
    $writer->dataElement(creation_date => $self->{creation_date}->datetime);
    $writer->dataElement(version => $self->{version});

    # all done
    $writer->endTag('template');
}



=back

=cut


sub DESTROY {
    my $self = shift;
    rmtree($self->{dir}) if $self->{dir};
}


# Private Methods
##################
# build template url
sub _build_url {
    my ($self, $path) = @_;
    my ($id, $url) = Krang::BricLoader::Category->get_id_url($path);
    croak("No category id and/or url found associated with Bricolage" .
          " category '$path'") unless ($id && $url);
    $self->{category_id} = $id;
    $self->{url} = join('/', $url, $self->{filename});
}

# map simple fields to Krang equivalents
sub _map {
    my ($self) = @_;

    $self->{version} = 1;
    $self->{template_id} = delete $self->{id};
    ($self->{filename} = delete $self->{file_name}) =~ s#^/##;
    $self->{content} = decode_base64 delete $self->{data};
    $self->{creation_date} = localtime;

    my $path = delete $self->{category};
    $self->_build_url($path) unless $path eq '/';

    return $self;
}



my $quip = <<QUIP;
1
QUIP
