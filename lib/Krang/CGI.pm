package Krang::CGI;
use strict;
use warnings;


=head1 NAME

Krang::CGI - Krang base class for CGI modules

=head1 SYNOPSIS

  package Krang::CGI::SomeSuch;
  use base 'Krang::CGI';

  sub setup {
    my $self = shift;
    $self->start_mode('status');
    $self->run_modes(status => \&status);
  }

  sub status {
    my $self = shift;
    my $query = $self->query;
    # ...
  }

=head1 DESCRIPTION

Krang::CGI is a subclass of L<CGI::Application>.  All the usual
CGI::Application features are available.

=head1 INTERFACE

See L<CGI::Application>.

=cut

use base 'CGI::Application';

use Krang::ErrorHandler;
use Data::Dumper ();

use Krang::Conf qw(KrangRoot InstanceDisplayName);
use File::Spec::Functions qw(catdir rel2abs);
use Krang::CGI::Status;
use Krang::CGI::ElementEditor;
use Krang::CGI::Login;
use Krang::Log qw(critical info debug);
use Krang::User;
use Krang::HTMLTemplate;

# Krang sessions
use Krang::Session qw/%session/;

# set this to one to see HTML errors in a popup in the UI
use constant HTMLLint => 0;

# Set up HTML_TEMPLATE_ROOT for templates
BEGIN {
    # setup instance if not running in mod_perl
    # needs to be set before import of Krang::ElementLibrary in
    # Krang::CGI::ElementEditor
    unless($ENV{MOD_PERL}) {
        my $instance = exists $ENV{KRANG_INSTANCE} ?
          $ENV{KRANG_INSTANCE} : (Krang::Conf->instances())[0];
        debug("Krang::CGI:  Setting instance to '$instance'");
        Krang::Conf->instance($instance);
    }
}

# load template and bless it into Krang::HTMLTemplate
sub load_tmpl {
    my $pkg = shift;

    # locally setup HTML_TEMPLATE_ROOT.  It can't be global because that
    # would affect Krang's publisher.
    local $ENV{HTML_TEMPLATE_ROOT} = catdir(KrangRoot, "templates");

    my $template = $pkg->SUPER::load_tmpl(@_, cache => 1);
    return bless($template, 'Krang::HTMLTemplate');
}


sub run {
    my $self = shift;
    my @args = ( @_ );

    # Load and unload session ONLY if we have a session ID set
    my $we_loaded_session = 0;
    if (my $session_id = $ENV{KRANG_SESSION_ID}) {
        # Load session if we're in CGI_MODE and we have a KRANG_SESSION_ID
        debug("Krang::CGI:  Loading Session '$session_id'");
        Krang::Session->load($session_id);
        $we_loaded_session++;
    }


    #
    # Run CGI
    #
    my $output;
    eval { $output = $self->SUPER::run(@args); };
    if (my $err = $@) {
        debug("Krang::CGI:  UN-Loading Session after error");
        Krang::Session->unload();
        die $@;
    }        


    # In debug mode append dump_html()
    if ($ENV{KRANG_DEBUG}) {
        my $dump_html = $self->dump_html();
        $output .= $dump_html;
        print $dump_html;
    }


    # Unload session if we loaded it
    if ($we_loaded_session) {
        debug("Krang::CGI:  UN-Loading Session");
        Krang::Session->unload();
    }

    return $output;
}


# Krang-specific dump_html
sub dump_html {
    my $self = shift;
    my $output = '';

    # Call standard dump
    $output .= $self->SUPER::dump_html();

    # Dump Session state
    $output .= "<P>\nSession State:<BR>\n<b><PRE>";
    $output .= Data::Dumper::Dumper(\%session);
    $output .= "</PRE></b>\n";

    return "<div style='text-align: left; margin-left: 170px'>$output</div>";
}

# check for HTML errors if HTMLLint is on
sub cgiapp_postrun {
    my ($self, $o) = @_;   
    return unless HTMLLint;

    # parse the output with HTML::Lint
    require HTML::Lint;
    my $lint = HTML::Lint->new();
    $lint->parse($$o);
    $lint->eof();

    # if there were errors put them into a javascript popup
    if ($lint->errors) {
        my $err_text = "<ul>" . join("", map { "<li>$_</li>" }
                                     map { s/&/&amp;/g;
                                           s/</&lt;/g;
                                           s/>/&gt;/g;
                                           s/\\/\\\\/g;
                                           s/"/\\"/g;
                                           $_; }
                                     map { $_->as_string } $lint->errors) .
                                       "</ul>";
    my $js = <<END;
<script language="javascript">
  var html_lint_window = window.open("", "html_lint_window", "height=300,width=600");
  html_lint_window.document.write("<html><head><title>HTML Errors Detected</title></head><body><h1>HTML Errors Detected</h1>$err_text</body></html>");
  html_lint_window.document.close();
  html_lint_window.focus(); 
</script>
END
        if ($$o =~ m!</body>!) {
            $$o =~ s!</body>!$js\n</body>!;
        } else {
            $$o .= $js;
        }
    }
}

1;
