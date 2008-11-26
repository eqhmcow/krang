package V3_04;
use strict;
use warnings;
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader base => 'Upgrade';
use Krang::ClassLoader DB   => 'dbh';
use Krang::ClassLoader 'ElementLibrary';
use Krang::Conf qw(KrangUser KrangGroup KrangRoot InstanceElementSet);
use File::Spec::Functions qw(catfile catdir);

sub per_installation {
    my $self = shift;

    print "Removing deprecated files... ";

    # removed in v3.02:
    # svn diff http://svn.krangcms.com/tags/krang_v3_01_fc5 \
    #          http://svn.krangcms.com/tags/3.02 --summarize | grep '^D'
    $self->remove_files(
        qw(
          src/Imager-0.44.tar.gz
          src/Image-Info-1.15.tar.gz
          bin/smoke_test
          )
    );

    # removed in v3.03:
    # svn diff http://svn.krangcms.com/tags/3.02 \
    #          http://svn.krangcms.com/tags/3.03 --summarize | grep '^D'
    $self->remove_files(
        qw(
          src/JSON-1.07.tar.gz
          src/CGI-Application-Plugin-JSON-0.3.tar.gz
          )
    );

    # removed in v3.04:
    # svn diff http://svn.krangcms.com/tags/3.03 \
    #          http://svn.krangcms.com/trunk/krang --summarize | grep '^D'
    $self->remove_files(
        qw(
          htdocs/help/category.html
          htdocs/help/contributor.html
          htdocs/help/contributor_associate.html
          htdocs/help/desk.html
          htdocs/help/desk_admin.html
          htdocs/help/group.html
          htdocs/help/list_group.html
          htdocs/help/log.html
          htdocs/help/media_archived.html
          htdocs/help/my_alerts.html
          htdocs/help/my_pref.html
          htdocs/help/schedule.html
          htdocs/help/schedule_job.html
          htdocs/help/site.html
          htdocs/help/story_archived.html
          htdocs/help/template_archived.html
          htdocs/help/user.html
          htdocs/help/workspace.html
          src/Apache-MOD_PERL/mod_ssl-2.8.28-1.3.37.tar.gz
          src/Apache-MOD_PERL/mm-1.4.0.tar.gz
          src/Apache-MOD_PERL/apache_1.3.37.tar.gz
          src/Digest-MD5-2.23.tar.gz
          src/Pod-Simple-0.96.tar.gz
          src/HTML-Parser-3.36.tar.gz
          src/HTML-PopupTreeSelect-Dynamic-1.3.tar.gz
          src/WWW-Mechanize-1.10.tar.gz
          templates/footer.tmpl
          templates/header.tmpl
          templates/nav.tmpl
          templates/About/about.tmpl
          templates/Alert/message.tmpl
          templates/Bugzilla/edit.tmpl
          templates/Category/copy.tmpl
          templates/Category/edit.tmpl
          templates/Category/find.tmpl
          templates/Category/new.tmpl
          templates/Contrib/associate_list_view.tmpl
          templates/Contrib/edit_view.tmpl
          templates/Contrib/list_view.tmpl
          templates/Desk/desk.tmpl
          templates/DeskAdmin/edit.tmpl
          templates/ElementEditor/edit.tmpl
          templates/ElementEditor/find_media_link.tmpl
          templates/ElementEditor/find_story_link.tmpl
          templates/ElementEditor/view.tmpl
          templates/Group/edit_categories.tmpl
          templates/Group/edit_view.tmpl
          templates/Group/list_view.tmpl
          templates/HTMLPager/pager-internals.tmpl
          templates/HTMLPager/pager-pagination.tmpl
          templates/Help/help_footer.tmpl
          templates/Help/help_header.tmpl
          templates/History/show.tmpl
          templates/ListGroup/edit.tmpl
          templates/ListGroup/list_view.tmpl
          templates/Login/forgot_pw.tmpl
          templates/Login/forgot_pw_email.tmpl
          templates/Login/login.tmpl
          templates/Login/login_footer.tmpl
          templates/Login/login_header.tmpl
          templates/Login/reset_pw.tmpl
          templates/Media/BulkUpload/choose.tmpl
          templates/Media/edit_media.tmpl
          templates/Media/list_active.tmpl
          templates/Media/list_active_pager.tmpl
          templates/Media/list_retired.tmpl
          templates/Media/list_view.tmpl
          templates/Media/list_view_pager.tmpl
          templates/Media/transform_image.tmpl
          templates/Media/view_media.tmpl
          templates/MyAlerts/edit.tmpl
          templates/MyPref/edit.tmpl
          templates/Publisher/media_error.tmpl
          templates/Publisher/progress.tmpl
          templates/Publisher/publish_list.tmpl
          templates/Schedule/edit.tmpl
          templates/Schedule/edit_admin.tmpl
          templates/Schedule/list_all.tmpl
          templates/Site/edit.tmpl
          templates/Site/list_view.tmpl
          templates/Site/view.tmpl
          templates/Story/edit.tmpl
          templates/Story/find.tmpl
          templates/Story/find_pager.tmpl
          templates/Story/list_active.tmpl
          templates/Story/list_active_pager.tmpl
          templates/Story/list_retired.tmpl
          templates/Story/new.tmpl
          templates/Story/view.tmpl
          templates/Template/edit.tmpl
          templates/Template/list_active.tmpl
          templates/Template/list_active_pager.tmpl
          templates/Template/list_retired.tmpl
          templates/Template/list_view.tmpl
          templates/Template/list_view_pager.tmpl
          templates/Template/view.tmpl
          templates/Trash/trash.tmpl
          templates/User/edit_view.tmpl
          templates/User/list_view.tmpl
          templates/Widget/category_chooser.tmpl
          templates/Widget/template_chooser.tmpl
          templates/Workspace/workspace.tmpl
          )
    );
}

sub per_instance {
    my ($self, %args) = @_;
    return if $args{no_db};
    my $dbh = dbh();
    print "\nUPGRADING INSTANCE " . InstanceElementSet . "\n";

    # 1. add the 'language' preference
    print "Adding 'language' preference to pref table... ";
    if (my ($language_pref) = $dbh->selectrow_array('SELECT * FROM pref WHERE id = "language"')) {
        print "already exists (skipping)\n\n";
    } else {
        $dbh->do('REPLACE INTO pref (id, value) VALUES ("language", "en")');
        print "DONE\n\n";
    }

    # 2. add the new schedule options
    my @schedule_columns  = @{$dbh->selectcol_arrayref('SHOW columns FROM schedule')};
    my %new_schedule_cols = (
        'failure_max_tries' => 'int unsigned',
        'failure_delay_sec' => 'int unsigned',
        'failure_notify_id' => 'int unsigned',
        'success_notify_id' => 'int unsigned'
    );
    foreach my $new_col (keys %new_schedule_cols) {
        print "Adding '$new_col' column to schedule table... ";
        if (grep { $_ eq $new_col } @schedule_columns) {
            print "already exists (skipping)\n\n";
        } else {
            $dbh->do("ALTER TABLE schedule ADD $new_col " . $new_schedule_cols{$new_col});
            print "DONE\n\n";
        }
    }

    # 3. add the new alert columns
    my @alert_columns  = @{$dbh->selectcol_arrayref('SHOW columns FROM alert')};
    my %new_alert_cols = (
        object_type        => 'varchar(255)',
        object_id          => 'int unsigned',
        custom_msg_subject => 'varchar(255)',
        custom_msg_body    => 'text'
    );
    foreach my $new_col (keys %new_alert_cols) {
        print "Adding '$new_col' column to alert table... ";
        if (grep { $_ eq $new_col } @alert_columns) {
            print "already exists (skipping)\n\n";
        } else {
            $dbh->do("ALTER TABLE alert ADD $new_col " . $new_alert_cols{$new_col});
            print "DONE\n\n";
        }
    }

    # 4. add the new alert index
    my $indexes = $dbh->selectall_arrayref('SHOW INDEX FROM alert');
    print "Making alerts indexable by object_type/id... ";
    if (grep { $_->[2] eq 'object_type' } @$indexes) {
        print "already done (skipping)\n\n";
    } else {
        $dbh->do('ALTER TABLE alert ADD INDEX (object_type, object_id)');
        print "DONE\n\n";
    }

    # 5. add element support to media objects
    $self->add_elements_to_media();

    # 6. add the new published flag to media
    my @media_columns = @{$dbh->selectcol_arrayref('SHOW columns FROM media')};
    print "Adding 'published' column to media table... ";
    if (grep { $_ eq 'published' } @alert_columns) {
        print "already exists (skipping)\n\n";
    } else {
        $dbh->do('ALTER TABLE media ADD published bool NOT NULL DEFAULT 0');
        print "DONE\n\n";
    }
}

sub add_elements_to_media {
    my ($element_lib, $warn_about_new_pm, $warn_about_set_conf, $warn_about_chown_failure);

    # 1. add column to media table
    my $dbh = dbh();
    print "Adding 'element_id' column to media table... ";
    my @media_columns = @{$dbh->selectcol_arrayref('SHOW columns FROM media')};
    if (grep 'element_id' eq $_, @media_columns) {
        print "already exists (skipping)\n\n";
    } else {
        $dbh->do('ALTER TABLE media ADD element_id int unsigned NOT NULL');
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
                last;
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
        my $set     = InstanceElementSet;
        my $package = $set . '::' . $class;
        foreach (catdir(KrangRoot, 'addons', $set, 'element_lib', $set),
            catdir(KrangRoot, 'element_lib', $set))
        {
            print "\nLooking for element library in $_... ";
            if (-d $_) {
                $element_lib = $_;
                last;
            }
        }
        if ($element_lib) {
            print "found\n\n";
        } else {
            croak("failed - don't know where else to look!\n\n");
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
      \@_,
    );
    return \$pkg->SUPER::new(\%args);
}

1;
EOF
        print "done\n\n";
        $warn_about_new_pm = 1;
        eval { 
             my ($uid, $gid);
             (undef, undef, $uid, undef) = getpwnam(KrangUser);
             (undef, undef, $gid, undef) = getgrnam(KrangGroup);
             chown($uid, $gid, $path_to_module);
        };
        $warn_about_chown_failure = 1 if $@;

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
            $warn_about_set_conf = 1;
        }
    }

    # unless all media objects already have element ids...
    if ($media_without_elements_total) {

        # 7. add rows to element and media tables
        print "\nAdding root element to $media_without_elements_total media rows... \r";
        my $add_element = $dbh->prepare(
            qq{
         INSERT INTO element (class) values ('$class')
      }
        );

        my $multi_table_update = $dbh->prepare(
            q{
        UPDATE media, element SET
          media.element_id = element.element_id,
          element.root_id = element.element_id
        WHERE media.media_id = ? AND element.element_id = ?
      }
        );

        my $written;
        while (my ($media_id) = $media_ids->fetchrow_array()) {
            $add_element->execute;
            my $element_id = $dbh->{mysql_insertid} || die 'No mysql_insert_id';
            $multi_table_update->execute($media_id, $element_id);
            print
              "Adding root element to $media_without_elements_total media rows... $written written\r"
              unless (++$written % 50);
        }
        print "Adding root element to $media_without_elements_total media rows... done\n";
    }

    if ($warn_about_new_pm) {
        print
          "\n* * * WARNING * * * \t The Krang upgrade script has created a new file: $element_lib/$class.pm\n";
    }
    if ($warn_about_chown_failure) {
        print
          "\n* * * WARNING * * * \t The Krang upgrade script was unable to correct the ownership of $element_lib/$class.pm\n";
    }
    if ($warn_about_set_conf) {
        print
          "\n* * * WARNING * * * \t The Krang upgrade script has added an entry for $class to $element_lib/set.conf\n";
    }

    print "\n";
}

1;
