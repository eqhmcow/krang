package Krang::BricLoader::ElementSet;

=head1 NAME

Krang::BricLoader::ElementSet -

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
use File::Path qw(mkpath rmtree);
use File::Spec::Functions qw(catdir catfile);
use File::Temp qw(tempdir);
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
our ($set, $set_dir, $verbose, $xml_doc);


# Lexicals
###########




=head1 INTERFACE

=over


=item C<< Krang::BricLoader::ElementSet->create(set => $name, path => $file) >>

=item C<< Krang::BricLoader::ElementSet->create(set => $name, xml => $xml) >>

Creates a new element named $name based on the XML located at $file or
contained within $xml.  This will result in a new directory
'$KrangRoot/element_lib/$name' containing a module for each element and a
configuration file listing the top-level elements.

=cut

sub create {
    my ($pkg, %args) = @_;
    my $dir = $args{dir};
    my $path = $args{path};
    my $xml = $args{xml};
    $set = $args{set};
    $verbose = $args{verbosity} || 0;

    # DEBUG
#    require Data::Dumper;
#    print STDERR Data::Dumper->Dump([\%args],['args']), "\n";

    # create dir for element set if it doesn't already exist
    $set_dir = catdir($ENV{KRANG_ROOT}, 'element_lib', $set);
    die("Element set '$set' already exists at '$set_dir'.\n".
        "Choose a new name or remove this set.\n")
      if -d $set_dir;
    eval {mkpath($set_dir)};
    die("Unable to create dir '$set_dir': $@") if $@;

    # retrieve XML and store is in global $doc
    $xml_doc = $path ? get_xml($path) : ( $dir ? cat_docs($dir) : $xml);

    build_set();
}


# create an element set from a Bricolage element tree
sub build_set {
    my $elements = parse_elements(@_);

    # add info to create an empty category element unless it's there...
    $elements->{category} = {top_level => 1, type => 'Insets'}
      unless exists $elements->{category};

    foreach my $name (keys %$elements) {
        create_class($name, $elements->{$name});
    }

    # create set.conf
    create_conf($elements);
}


# concatenate a set of xml docs into one, assuming they're all well-formed
sub cat_docs {
    my $dir = shift;
    my ($doc, @lines);

    opendir(DIR, $dir) or croak("Can't open directory '$dir': $!");
    my @files = grep /element_\d+\.xml$/i, readdir(DIR);
    closedir(DIR) or croak("Can't close directory '$dir': $!");

    croak("No files matching the regex, " . '/element_\d+\.xml/' . ", found.")
      unless @files;

    my $first = 1;
    for my $f(@files) {
        my $file = catfile($dir, $f);
        my $fh = IO::File->new("<$file") or croak("Couldn't open '$file': $!");
        while (<$fh>) {
            next if $_ =~ m#</assets>#;
            unless ($first) {
                next if $_ =~ m#<(?:assets|\?xml)#;
            }
            $doc .= $_;
        }
        $fh->close;
        $first = 0 if $first;
    }

    $doc .= '</assets>';
    return $doc;
}

# create a class module for a Bricolage container class
sub create_class {
    my ($ename, $data) = @_;

    # skip media classes, which aren't used in Krang
    return if $data->{type} eq 'Media';

    # process name for use as an identifier
    $ename = process_name($ename);

    # compute module name
    my $module = "${set}::${ename}";

#    print STDERR "Creating $module...\n" if $verbose;

    # collect list of subelement declarations in @sub
    my @sub;

    # related media or related stories need an extra field in Krang
    if ($data->{type} eq 'Related Media') {
        push(@sub, "    Krang::ElementClass::MediaLink->new(name => 'media', ".
             "min => 1, max => 1, allow_delete => 0, reorderable => 0)");
    } elsif ($data->{type} eq 'Related Stories') {
        push(@sub, "    Krang::ElementClass::StoryLink->new(name => 'story', ".
             " min => 1, max => 1, allow_delete => 0, reorderable => 0)");
    }

    # process fields
    foreach my $f (@{$data->{fields}}) {
        my $name = process_name($f->{name});

        die "No type defined for $f->{name} of $ename!"
          unless defined $f->{type};

        # setup parameters common to all classes
        my $common  = "        name         => '$name',\n";
        $common .= "        display_name => '$f->{label}',\n"
          unless $f->{label} eq display_name($name);
        $common .= "        min          => 1,\n"
          if $f->{required};
        $common .= "        max          => 1,\n"
          unless $f->{repeatable};
        $common .= "        allow_delete => 0,\n"
          if $f->{required};
        $common .= "        default      => '$f->{default}',\n"
          if defined $f->{default};

        my $sub;
        if ($f->{type} eq 'textarea') {
            $sub = "    Krang::ElementClass::Textarea->new(\n" . $common;
            $sub .=    "        rows         => $f->{rows},\n"
              if $f->{rows};
            $sub .=    "        cols         => $f->{cols},\n"
              if $f->{cols};
            $sub .= "    )";
        } elsif ($f->{type} eq 'text') {
            $sub = "    Krang::ElementClass::Text->new(\n" . $common;
            $sub .=    "        size         => $f->{size},\n"
              if $f->{size};
            $sub .=    "        maxlength    => $f->{max_size},\n"
              if $f->{max_size};
            $sub .= "    )";

        } elsif ($f->{type} eq 'radio' or $f->{type} eq 'select') {
            # break down options in to @values and %label
            my (@values, %labels);
            foreach my $row (split(/\n/, $f->{options})) {
                next unless $row;
                my ($value, $label) = split(/,/, $row);
                push(@values, $value);
                $labels{$value} = $label;
            }
            my $values = join(",", map { "'$_'" } @values);
            my $labels = join(",", map { "'$_' => '$labels{$_}'" }
                              keys %labels);

            $sub = "    Krang::ElementClass::" .
              (($f->{type} eq 'select') ? "PopupMenu" : "RadioGroup") .
                "->new(\n" . $common .
                  "        values      => [$values],\n" .
                    "        labels      => {$labels},\n    )";

        } elsif ($f->{type} eq 'checkbox') {
            $sub = "    Krang::ElementClass::CheckBox->new(\n" . $common .
              "    )";
        } elsif ($f->{type} eq 'date') {
            $sub = "    Krang::ElementClass::Date->new(\n" . $common .
              "    )";
        } else {
            die "Unknown field type '$f->{type}' named '$f->{name}' " .
              "encountered while parsing '$ename'.\n";
        }

        push(@sub, $sub);
    }

    # add references to Bricolage sub-elements
    if ($data->{subelements}) {
        foreach my $sub_name (@{$data->{subelements}}) {
            push(@sub, "    '" . process_name($sub_name) . "'");
        }
    }


    # build list of subelements
    my $sub_elements = join(",\n\n", @sub);

    my $base;
    if ($data->{type} eq 'Covers') {
        # base class for covers is Krang::ElementClass::Cover
        $base = 'Krang::ElementClass::Cover';
    } elsif ($data->{top_level}) {
        # others top-levels must be subclasses of TopLevel
        $base = 'Krang::ElementClass::TopLevel';
    } else {
        $base = 'Krang::ElementClass';
    }

    # open module for output
    open(MOD, ">", catfile($set_dir, "$ename.pm"))
      or die "Unable to open $ename.pm for output: $!";

    # print module
    print MOD <<END;
package $module;
use strict;
use warnings;
use base '$base';

sub new {
    my \$pkg  = shift;
    my \%args = ( name      => '$ename',
END

print MOD <<END;
                 children  => [
$sub_elements
                ],
                \@_);
    return \$pkg->SUPER::new(\%args);
}

1;
END

   close MOD;
}


# create set.conf for the element set
sub create_conf {
    my $elements = shift;

    print STDERR "Creating set.conf...\n" if $verbose;

    # get list of top-level elements
    my @top_levels = grep { $elements->{$_}->{type} ne 'Media' and
                              $elements->{$_}->{top_level} }
      sort keys %$elements;

    open(CONF, ">", catfile($set_dir, "set.conf"))
      or die "Unable to open set.conf: $!\n";

    print CONF "Version 1.0\n";
    print CONF "TopLevels ",
      join(' ', map { process_name($_) } @top_levels), "\n";

    close CONF;
}


# standard display_name processing
sub display_name {return join " ", map { ucfirst($_) } split /_/, shift;}


sub get_xml {
    my $xml_file = shift;
    open(XML, $xml_file) or die "Unable to open $xml_file: $!";
    my $xml = join('', <XML>);
    close XML;
    return $xml;
}


# parse the asset document and extract all useful data about elements.
# Returns a hash keyed by element name.
sub parse_elements {
    my $doc = XMLin($xml_doc,
                    keyattr    => [],
                    forcearray => ['subelement', 'field'],
                   );

    my %elements;
    foreach my $e (@{$doc->{element}}) {
        # extract meta-data
        $elements{$e->{name}} = {
                                 top_level => $e->{top_level},
                                 type      => $e->{type},
                                };

        # extract sub-elements
        $elements{$e->{name}}{subelements} = $e->{subelements}{subelement};

        # extract field data
        if ($e->{fields} and $e->{fields}{field}) {
            foreach my $field (@{$e->{fields}{field}}) {
                push(@{$elements{$e->{name}}{fields}},
                     {
                      name       => $field->{name},
                      label      => $field->{label},
                      max_size   => $field->{max_size},
                      size       => $field->{size},
                      repeatable => $field->{repeatable},
                      required   => $field->{required},
                      type       => $field->{type},
                      rows       => $field->{rows},
                      cols       => $field->{cols},
                      options    => $field->{options},
                      default    => $field->{default},
                     });
            }
        }
    }

    return \%elements;
}


# process name for use as an identifier
sub process_name {
    my $name = shift;

    $name =~ tr/A-Z/a-z/;
    $name =~ s/\s+/_/g;
    $name =~ s/-/_/g;
    $name =~ s/[^\w]/_/g;
    $name =~ s/_+/_/g;

    return $name;
}


=back

=cut



# Private Methods
##################




my $quip = <<QUIP;
1
QUIP
