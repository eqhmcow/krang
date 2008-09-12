package V3_04;
use strict;
use warnings;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => 'Upgrade';
use Krang::ClassLoader DB => 'dbh';
use Krang::ClassLoader 'ElementLibrary';
use Krang::Conf qw(KrangRoot InstanceElementSet);
use File::Spec::Functions qw(catfile catdir);

sub per_installation {
}

sub per_instance {
    my ($self, %args) = @_;
    return if $args{no_db};
    my $dbh = dbh();

    # add the 'language' preference
    $dbh->do('INSERT INTO pref (id, value) VALUES ("language", "en")');

    $self->add_elements_to_media();
}


sub add_elements_to_media {

    # 1. add column to media table
    my $dbh = dbh();
    print "\nAdding 'element_id' column to media table... ";
    my @media_columns = @{$dbh->selectcol_arrayref('SHOW columns FROM media')};
    if (grep 'element_id' eq $_, @media_columns) {
        print "already exists (skipping)\n\n";
    } else {
        $dbh->do('ALTER TABLE media ADD element_id mediumint unsigned NOT NULL');
        print "DONE\n\n";
    }
    
    # 2. check for media without elements
    print "Checking for media objects without element_ids... ";
    my $media_ids = $dbh->prepare('SELECT media_id FROM media WHERE element_id = 0');
    $media_ids->execute;
    my $media_without_elements_total = $media_ids->rows;
    if ($media_without_elements_total) {
        print "found $media_without_elements_total\n\n";
    } else {
        print "none found (skipping)\n\n";
    }
    
    # 3. determine class name for media element
    my $class = 'media';
    pkg('ElementLibrary')->load_set(set => InstanceElementSet);
    while (1) {
        print "Checking if we can create '$class' class in element library... ";
        if (my $existing_class = pkg('ElementLibrary')->find_class(name => $class)) {
            if ($existing_class->isa('Krang::ElementClass::Media')) {
                print "already created (skipping)\n";
            } else {
                print "no (already used)\n";
                $class .= '_element';
            }
        } else {
            print "yes\n";
            last;
        }
    }

    # unless the class has already been built...
    unless (pkg('ElementLibrary')->find_class(name => $class)) {
    
        # 4. locate element library
        my $set = InstanceElementSet;
        my $package = $set . '::' . $class;
        my $element_lib;
        foreach (catdir(KrangRoot, 'addons', $set, 'element_lib', $set),
                 catdir(KrangRoot, 'element_lib', $set)) {
            print "\nLooking for element library in $_... ";
            if (-d $_) {
                $element_lib = $_;
                last;
            }
        }
        if ($element_lib) {
            print "found\n\n";
        } else {
            croak ("failed - don't know where else to look!\n\n");
        }
        
        # 5. create skeletal media element
        my $path_to_module;
        my $filename = 'media';
        while (1) {
            $path_to_module = catfile($element_lib, $filename . '.pm');
            last unless -e $path_to_module;
            $filename .= '_element';
        }
        print "Creating $path_to_module... ";
        open MODULE, " > $path_to_module";
        print MODULE <<"EOF"; 
package $package;

=head1 NAME

  $package;

=head1 DESCRIPTION

Media element class for Krang.

=cut

use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => 'ElementClass::Media';

sub new {
    my \$pkg = shift;
    my \%args = (
      name => '$class',
      children => [],
      @_,
    );
    return \$pkg->SUPER::new(\%args);
}

1;
EOF
        print "done\n\n";

        # 6. add media element to set.conf
        print "Adding an entry to $element_lib/set.conf... ";
        open SET_CONF, " < $element_lib/set.conf";
        my @lines = <SET_CONF>;
        close SET_CONF;
        my $lines = join(@lines);
        if ($lines =~ /\s$class\s/) {
           print "already exists (skipping)\n\n";
        } else {  
           open SET_CONF, " > $element_lib/set.conf";
           foreach (@lines) {
             if ($_ =~ /TopLevels (.*)/i) {
               print SET_CONF "TopLevels $class $1\n";
             } else {
               print SET_CONF "$_";
             }
           }
           close SET_CONF;
           print "done\n";
        }
  }

  # unless all media objects already have element ids...
  if ($media_without_elements_total) {

      # 7. add rows to element and media tables
      print "\nAdding root element to $media_without_elements_total media rows... \r";
      my $add_element = $dbh->prepare(qq{
         INSERT INTO element (class) values ('$class')
      });

      my $multi_table_update = $dbh->prepare(q{
        UPDATE media, element SET
          media.element_id = element.element_id,
          element.root_id = element.element_id
        WHERE media.media_id = ? AND element.element_id = ?
      });

      my $written;
      while (my ($media_id) = $media_ids->fetchrow_array()) {
         $add_element->execute;
         my $element_id = $dbh->{mysql_insertid} || die 'No mysql_insert_id';
         $multi_table_update->execute($media_id, $element_id);
         print "Adding root element to $media_without_elements_total media rows... $written written\r"
            unless (++$written % 50);
      }
      print "Adding root element to $media_without_elements_total media rows... done\n";
  }

  print "\n";
}

1;
