package Krang::CGI::Help;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

=head1 NAME

Krang::CGI::Help - Krang help screens

=head1 SYNOPSIS

  http://krang/help?topic=workspace

=head1 DESCRIPTION

Provides help screens given a topic.

=head1 INTERFACE

None.

=cut

use Krang::ClassLoader base => 'CGI';
use Krang::ClassLoader Conf => qw(
    KrangRoot
    DefaultLanguage
    InstanceHostName
    BadHelpNotify
    FromAddress
    SMTPServer
);
use File::Spec::Functions qw(catfile catdir);
use Krang::ClassLoader 'HTMLTemplate';
use Krang::ClassLoader 'File';
use Krang::ClassLoader Session => qw(%session);
use Krang::ClassLoader 'Log'   => qw(debug info);

sub setup {
    my $self = shift;
    $self->start_mode('show');
    $self->run_modes(
        show            => 'show',
        bad_help_notify => 'bad_help_notify'
    );
}

sub show {
    my $self  = shift;
    my $query = $self->query;
    my $topic = $query->param('topic') or die "Missing required topic.";
    die "Bad topic." if $topic !~ /^\w+/;

    # maybe localized help
    my $lang = $session{language} || DefaultLanguage || 'en';
    my $symlink = catdir(KrangRoot, 'htdocs', 'help', $lang);
    my $localized_help_dir = -l $symlink ? $lang : '';

    # find topic help file
    my $file = pkg('File')->find(catfile('htdocs', 'help', $localized_help_dir, "$topic.html"));
    if (not -e $file) {
        return "<h2>Unable to find help file for '$topic' topic.</h2>";
    }

    # load as template to process includes
    my $template = $self->load_tmpl(
        $file,
        path                   => ['Help'],
        search_path_on_include => 1,
        cache                  => 1
    );

    return $template->output;
}

# if the help topic is not defined send a message to the site admin
sub bad_help_notify {
    my $self = shift;
    my $query = $self->query;
    my $topic = scalar $query->param('topic') or die "Missing required topic.";

    # send an email to the BadHelpNotify email address if it exists
    if (BadHelpNotify) {
        my $email_to = $ENV{KRANG_TEST_EMAIL} || BadHelpNotify;
        my $user     = $ENV{REMOTE_USER};
        my $hostname = InstanceHostName;
        my $msg      = "User '$user' on $hostname has encountered an undefined Help topic '$topic'.";

        debug(__PACKAGE__ . "->bad_help_notify() - sending email to $email_to : $msg");
        my $sender = Mail::Sender->new(
            {
                smtp      => SMTPServer,
                from      => FromAddress,
                on_errors => 'die'
            }
        );

        $sender->MailMsg(
            {
                to      => $email_to,
                subject => "[Krang] undefined Help topic encountered",
                msg     => $msg,
            }
        );
    }

    # add_alert('bad_help_notify', topic => $topic, minutes => BadLoginWait);
    # return $self->show_form();
    return;
}

1;
