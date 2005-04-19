use Krang::ClassFactory qw(pkg);
use Test::More qw(no_plan);
use strict;
use warnings;
use Krang::ClassLoader 'Script';
use Krang::ClassLoader Conf => qw(KrangRoot);
use File::Spec::Functions qw(catfile catdir);

use_ok(pkg('XML::Validator'));

my $v = pkg('XML::Validator')->new();
isa_ok($v, 'Krang::XML::Validator');

# create a valid site XML file
my $file = catfile(KrangRoot, "tmp", "site.xml");
open(XML, '>', $file) or die $!;
print XML <<END;
<?xml version="1.0" encoding="UTF-8"?>

<site xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="site.xsd">
     <site_id>27</site_id>
     <url>equilibrium.kra</url>
     <preview_url>preview.equilibrium.kra</preview_url>
     <publish_path>/tmp/equilibrium.kra_publish</publish_path>
     <preview_path>/tmp/equilibrium.kra_preview</preview_path>
</site>
END
close(XML);

# should be ok
my ($ok, $msg) = $v->validate(path => $file);
is($ok, 1);

# create an invalid site XML file
open(XML, '>', $file) or die $!;
print XML <<END;
<?xml version="1.0" encoding="UTF-8"?>

<site xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="site.xsd">
     <url>equilibrium.kra</url>
     <preview_url>preview.equilibrium.kra</preview_url>
     <publish_path>/tmp/equilibrium.kra_publish</publish_path>
     <preview_path>/tmp/equilibrium.kra_preview</preview_path>
</site>
END
close(XML);

# should be invalid and mention something about site_id
($ok, $msg) = $v->validate(path => $file);
is($ok, 0);
like($msg, qr/site_id/);

# cleanup
unlink($file) or die $!;

