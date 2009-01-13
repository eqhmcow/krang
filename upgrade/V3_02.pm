package V3_02;
use strict;
use warnings;
use Krang::ClassLoader base => 'Upgrade';
use Krang::ClassLoader DB => 'dbh';
use Krang::Conf qw(KrangRoot);
use File::Spec::Functions qw(catfile);

sub per_installation {
    my ($self, %args) = @_;
    # remove old files
    $self->remove_files(
        qw(
          htdocs/images/closed_node.png
          htdocs/images/L.png
          htdocs/images/minus.png
          htdocs/images/open_node.png
          htdocs/images/plus.png
          lib/Krang/Test/Apache.pm
          platform/RHEL_AS3/README.RHEL_ES3
          platform/RHEL_AS4/README.RHEL_ES4
          platform/RHEL_ES4/README.RHEL_AS4
          skins/Default/images/logo.gif
          skins/Gunmetal
          skins/Mono
          skins/Red
          src/CGI.pm-2.89.tar.gz
          src/Image-BioChrome-1.16.tar.gz
          src/libapreq-1.3.tar.gz
          src/MIME-Base64-2.16.tar.gz
          src/Test-Harness-2.46.tar.gz
          src/YAML-0.58.tar.gz
          )
    );
}

sub per_instance {
    my ($self, %args) = @_;
    return if $args{no_db};
    my $dbh = dbh();

    # add 'retired' and 'trashed' columns to stories, media, and templates
    foreach my $table ('story', 'media', 'template') {
        my @existing_cols  = @{$dbh->selectcol_arrayref("SHOW columns FROM $table")};
        foreach my $column ('retired', 'trashed') {
            $dbh->do("ALTER TABLE $table ADD COLUMN $column BOOL NOT NULL DEFAULT 0")
              unless (grep { $_ eq $column } @existing_cols);
        }
    }

    # add admin permission 'admin_delete' and give it to admin and editor group
    my @existing_cols  = @{$dbh->selectcol_arrayref("SHOW columns FROM group_permission")};
    unless (grep { $_ eq "admin_delete" } @existing_cols) {
        $dbh->do('Alter TABLE group_permission ADD COLUMN admin_delete BOOL NOT NULL DEFAULT 0');
    }
    $dbh->do('Update group_permission SET admin_delete = 1 WHERE name = "Admin"');
    $dbh->do('Update group_permission SET admin_delete = 1 WHERE name = "Edit"');
    
    # create the trashbin table
    my @tables = @{$dbh->selectcol_arrayref("SHOW tables")};
    unless (grep { $_ eq 'trash' } @tables) {
        $dbh->do(<<SQL);
CREATE TABLE trash (
    object_type  varchar(255)      NOT NULL,
    object_id 	 int(10) unsigned  NOT NULL,
    timestamp    datetime          NOT NULL,
    INDEX (object_type, object_id)
) TYPE=MyISAM;
SQL

    }

    # add new columns to Schedule
    @existing_cols    = @{$dbh->selectcol_arrayref("SHOW columns FROM schedule")};
    my %existing_cols = map { $_ => 1 } @existing_cols;
    $dbh->do('ALTER TABLE schedule ADD COLUMN inactive BOOL NOT NULL DEFAULT 0')
      unless $existing_cols{'inactive'};
    $dbh->do('ALTER TABLE schedule ADD expires DATETIME AFTER next_run')
      unless $existing_cols{'expires'};
    $dbh->do('ALTER TABLE schedule ADD day_of_month INT AFTER expires')
      unless $existing_cols{'day_of_month'};
    $dbh->do('ALTER TABLE schedule ADD day_interval INT UNSIGNED AFTER day_of_week')
      unless $existing_cols{'day_interval'};
    $dbh->do("ALTER TABLE schedule CHANGE COLUMN `repeat` `repeat` ENUM('never', 'hourly', 'daily', 'weekly', 'monthly', 'interval') NOT NULL");

}

1;
