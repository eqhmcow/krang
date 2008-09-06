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

    # add 'retired' and 'trashed' columns to STORY
    $dbh->do('ALTER TABLE story ADD COLUMN retired BOOL NOT NULL DEFAULT 0');
    $dbh->do('ALTER TABLE story ADD COLUMN trashed  BOOL NOT NULL DEFAULT 0');

    # add 'retired' and 'trashed' columns to MEDIA
    $dbh->do('ALTER TABLE media ADD COLUMN retired BOOL NOT NULL DEFAULT 0');
    $dbh->do('ALTER TABLE media ADD COLUMN trashed  BOOL NOT NULL DEFAULT 0');

    # add 'retired' and 'trashed' columns to Template
    $dbh->do('ALTER TABLE template ADD COLUMN retired BOOL NOT NULL DEFAULT 0');
    $dbh->do('ALTER TABLE template ADD COLUMN trashed  BOOL NOT NULL DEFAULT 0');

    # add admin permission 'admin_delete' and give it to admin and editor group
    $dbh->do('Alter TABLE group_permission ADD COLUMN admin_delete BOOL NOT NULL DEFAULT 0');
    $dbh->do('Update group_permission SET admin_delete = 1 WHERE group_id = 1');
    $dbh->do('Update group_permission SET admin_delete = 1 WHERE group_id = 2');

    # add 'inactive' flag to schedule table
    $dbh->do('Alter TABLE schedule ADD COLUMN inactive BOOL NOT NULL DEFAULT 0');

    # create the trashbin table
    $dbh->do(<<SQL);
CREATE TABLE trash (
    object_type  varchar(255)      NOT NULL,
    object_id 	 int(10) unsigned  NOT NULL,
    timestamp    datetime          NOT NULL,
    INDEX (object_type, object_id)
) TYPE=MyISAM;
SQL

    # add new columns to Schedule
    $dbh->do('ALTER TABLE schedule ADD expires DATETIME AFTER next_run');
    $dbh->do('ALTER TABLE schedule ADD day_of_month INT AFTER expires');
    $dbh->do('ALTER TABLE schedule ADD day_interval INT UNSIGNED AFTER day_of_week');
    $dbh->do("ALTER TABLE schedule CHANGE COLUMN `repeat` `repeat` ENUM('never', 'hourly', 'daily', 'weekly', 'monthly', 'interval') NOT NULL");

}

1;
