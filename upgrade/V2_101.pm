package V2_101;
use strict;
use warnings;
use Krang::ClassLoader base => 'Upgrade';
use Krang::ClassLoader DB => 'dbh';

# nothing yet
sub per_installation {
}

sub per_instance {
    # new story property 'last_desk_id' to record the id
    # of the desk the story was on when checking it out
    my $dbh = dbh();
    $dbh->do(qq/
        ALTER TABLE story ADD column last_desk_id SMALLINT(5) UNSIGNED
    /);
}

1;
