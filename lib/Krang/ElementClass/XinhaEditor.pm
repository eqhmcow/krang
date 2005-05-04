package Krang::ElementClass::XinhaEditor;
use strict;
use warnings;

use base 'Krang::ElementClass::Textarea';
use Carp qw(croak);

use Krang::Message qw(add_message);
use Krang::MethodMaker get_set =>
  [qw( toolbar_config toolbar_config_string rows cols )];

our %button_layouts = (
    all => q{
     [ "fontname", "space",
       "fontsize", "space",
       "formatblock",
       "linebreak",

       "bold", "italic", "underline", "separator",
       "strikethrough", "subscript", 
       "superscript", "separator",
       "copy", "cut", "paste",
       "justifyleft", "justifycenter", "justifyright", "justifyfull", 
       "linebreak",

       "insertorderedlist", "insertunorderedlist", "outdent", "indent", 
        "separator",
       "forecolor", "hilitecolor", "textindicator", 
       "inserthorizontalrule", "createlink", "insertimage", "inserttable", 
        "linebreak",

       "htmlmode", "separator",
       "popupeditor", "separator", "about", "space", "undo", "redo" ]
    },
    standard => q{
     [ "fontname", "space",
       "fontsize", "space",
       "bold", "italic", "underline", "separator", "undo", "redo","linebreak",

       "copy", "cut", "paste", "space", "separator",
       "justifyleft", "justifycenter", "justifyright", "justifyfull", 
        "separator",
       "insertorderedlist", "insertunorderedlist", "outdent", "indent", 
        "separator", "createlink" ]
    },
    minimal => q{
     [ "bold", "italic", "underline", "separator",
       "insertorderedlist", "insertunorderedlist", "createlink", "separator",
       "copy", "cut", "paste", "space", "undo", "redo" ]
    },
);

sub new {
    my $pkg  = shift;
    my %args = (
        toolbar_config => 'minimal',
        rows           => 4,
        cols           => 30,
        @_
    );

    # check args
    if ( $args{'toolbar_config'} ) {
        if ( !exists $button_layouts{ $args{'toolbar_config'} } ) {
            croak("\"$args{'buttons'}\" is not a known button layout");
        }
    }

    return $pkg->SUPER::new(%args);
}

# check for empty value, which for this widget is a single break tag.
sub validate { 
    my ($self, %arg) = @_;
    my ($query, $element) = @arg{qw(query element)};
    my ($param) = $self->param_names(element => $element);
    my $value = $query->param($param);

    if ($self->{required} and 
        (not defined $value or not length $value or
         $value =~ m!^<br\s*/>\s*$!)) {
        return (0, $self->display_name . " requires a value.");
    }
    return 1;
}

# the default span wrapping pushes the HTMLArea box into the next
# column for some reason.  A colored div works though.
sub mark_form_invalid {
    my ($self, %arg) = @_;
    my ($html) = @arg{qw(html)};
    return qq{<div style="border: 3px solid #ffffac">$html</div>};
}

sub input_form {
    my ( $self,  %arg )     = @_;
    my ( $query, $element ) = @arg{qw(query element)};
    my ($param) = $self->param_names( element => $element );
    my $html = "";

    # only add this once
    my @sibs = grep { $_->class->isa(__PACKAGE__) } 
      $element->parent()->children();
    if ( $sibs[0]->xpath() eq $element->xpath() ) {        
        my @params = map { $self->param_names( element => $_ ) } @sibs;
        my $params = join(', ', map { "'$_'" } @params);

        # I'm the first!  Insert one-time JavaScript
        $html .= <<END;
<script type="text/javascript">
    _editor_url  = "/xinha/"
    _editor_lang = "en";
</script>
<script type="text/javascript" src="/xinha/htmlarea.js"></script>
<script type="text/javascript">
    xinha_editors = null;
    xinha_init    = null;
    xinha_config  = null;
    xinha_plugins = null;

    // This contains the names of textareas we will make into Xinha editors
    xinha_init = xinha_init ? xinha_init : function()
    {
      xinha_plugins = xinha_plugins ? xinha_plugins :
      [
       'FullScreen',
      ];
      if(!HTMLArea.loadPlugins(xinha_plugins, xinha_init)) return;

      xinha_editors = xinha_editors ? xinha_editors :
      [
       $params
      ];

      xinha_config = xinha_config ? xinha_config : new HTMLArea.Config();
      xinha_config.sizeIncludesToolbar = false;
      xinha_editors   = HTMLArea.makeEditors(xinha_editors, xinha_config, xinha_plugins);
END

        # setup configuration for each editor
        foreach my $element (@sibs) {
            my ($param) = $self->param_names( element => $element );
            $html .= qq{      xinha_editors["$param"].config.toolbar = [};

            # use custom config string or pre-defined layout
            my $config = $element->class->toolbar_config_string()
              || $button_layouts{ $element->class->toolbar_config() };
            $html .= $config;

            $html .= "];\n";
        }

        $html .= <<END
      HTMLArea.startEditors(xinha_editors);    
    }

    window.onload = xinha_init;
</script>
END
    }

    # create the textarea for this editor
    $html .= $query->textarea(
        -name    => $param,
        -default => $element->data() || "",
        -rows    => $self->rows,
        -cols    => $self->cols,
        -id      => $param,
    );
    
    return $html;
}

# we override this method so that it won't escape the HTML
sub view_data {
    my ( $self, %arg ) = @_;
    my ($element) = @arg{qw(element)};
    return "" . ($element->data || '');
}

=head1 NAME

Krang::ElementClass::XinhaEditor - WYSIWYG HTML editor

=head1 SYNOPSIS

   $class = Krang::ElementClass::XinhaEditor->new(
                                       name => "body",
                                       rows => 20,
                                       cols => 30,
                                       toolbar_config => 'standard'
                                      );

=head1 DESCRIPTION

This element provides a WYSIWYG text editor for HTML by integrating
with the Xinha JavaScript text editor.

=head1 INTERFACE

All the normal L<Krang::ElementClass> attributes are available, plus:

=over 4

=item rows

The number of rows in the editor box.  Defaults to 4.

=item cols

The number of columns in the editor box.  Defaults to 40.

=item toolbar_config

This is a string corresponding to one of the preset configurations for
the editor toolbar.  The current options are 'standard', for a typical
configuration with the Krang-unfriendly buttons removed, 'minimal',
for a sparse toolbar with just the basics, and 'all' for a toolbar
with the works.  For the exact details about which buttons are
included in each, see the source code for this module.

The default is 'minimal'.

=item toolbar_config_string

Alternate configuration mechanism for the toolbar.  This allows a
string to be passed in with a configuration which will be passed
directly to the JavaScript configuration.  You must read and
understand the htmlArea documentation in order to use this.  A sample
config string would look like this:

     [
       "fontsize", "space",
       "bold", "italic", "underline", "separator",
       "copy", "cut", "paste", "space", "undo", "redo", 
       "linebreak",
       "insertorderedlist", "outdent", "indent", "separator",
       "textindicator", "separator",
       "createlink",
     ]

Note that this a string, *not* a perl data structure!

=back

=head1 SEE ALSO

Xinha is available from http://xinha.python-hosting.com/.  The source
code and license for the editor are included in the htdocs/xinha/
directory of this Krang distribution.

=cut

1;
