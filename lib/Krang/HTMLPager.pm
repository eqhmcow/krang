package Krang::HTMLPager;
use strict;
use warnings;

use Carp qw(croak);
use HTML::Template;
use Krang::Conf qw(KrangRoot);
use File::Spec::Functions qw(catdir);


# Set up HTML_TEMPLATE_ROOT for templates
BEGIN {
    # use $KRANG_ROOT/templates for templates
    $ENV{HTML_TEMPLATE_ROOT} = catdir(KrangRoot, "templates");
}



=head1 NAME

Krang::HTMLPager - Web-paginate lists of records


=head1 SYNOPSIS

  use Krang::HTMLPager;

  # Instantiate new template
  my $pager = Krang::HTMLPager->new(
    cgi_query => $query,
    persist_vars => [ qw( rm search_filter ) ],
    use_module => 'Krang::Contrib',
    find_params => { simple_search => $q->param('search_filter') },

    # Configure columns and column display
    columns => [qw( last first_middle type command_column checkbox_column )],
    column_labels => {
                       last => 'Last Name',
                       first_middle => 'First, Middle Name'
                     },

    # Configure sorting controls
    columns_sortable => [qw( last first_middle )],
    columns_sort_map => { first_middle => 'first,middle' },

    # Configure built-in column handlers
    command_column_commands => [qw( edit_contrib )],
    command_column_labels => {
                               edit_contrib => 'Edit'
                             },

    # Sub-ref which processes every row.
    # Gets row hashref and found object as argument.
    # May specify add'l arguments to be passed to row handler method.
    row_handler => \&my_row_handler,

    # id_handler:  A sub-ref (like row_handler) which returns a unique ID for this row.
    # Only needed if you're using command_column or checkbox_column
    # Receives $row_obj as argument
    id_handler => sub { return $_[0]->contrib_id },
  );

  # Render template as HTML...
  $template->param( pager_html => $pager->output() );

  # ...OR, set up params on custom template
  $pager->fill_template($template):

  # Example my_row_handler function
  sub my_row_handler {
    my ($row_hashref, $row_obj) = @_;
    $row_hashref->{first_middle} = $row_obj->first() . " " . $row_obj->middle();
  }

=cut


use Krang::MethodMaker (
                        new_with_init => 'new',
                        new_hash_init => 'hash_init',
                        get_set       => [ qw(
                                               cgi_query 
                                               persist_vars 
                                               use_module 
                                               find_params 
                                               columns 
                                               column_labels
                                               command_column_commands
                                               command_column_labels
                                               columns_sortable 
                                               columns_sort_map
                                               row_handler
                                               id_handler
                                             ) ],
                       );



=head1 DESCRIPTION

The primary purpose of Krang::HTMLPager is to allow Krang-style
page able lists of results to be easily created.  The secondary
purpose is to enforce a standard function and appearance to these
lists.

The pager interface is designed to work specifically with the Krang
system, and to be as simple to use as possible.  It is modeled after
HTML::Pager, but is more specialized for use with Krang.  In
particular Krang::HTMLPager provides the following functions which are
unique to Krang:

  * Use of class find() methods
  * Generation of "checkbox columns"
  * Generation of "command columns"
  * Krang-style sort controls
  * Krang-style user interface

=head1 INTERFACE

Krang::HTMLPager implements three primary methods.

=over 4



=item new()

  my $pager = Krang::HTMLPager->new(%pager_props);

The new() method instantiates a new pager.  It takes a litany of
parameters, which are documented in full later in this POD in the
section "Krang::HTMLPager Properties".

=cut

sub init {
    my $self = shift;
    my %args = ( @_ );

    # Set up default values
    my %defaults = (
                    persist_vars => [],
                    find_params => {},
                    columns => [],
                    column_labels => {},
                    columns_sortable => [],
                    columns_sort_map => {},
                    command_column_commands => [],
                    command_column_labels => {},
                   );

    # finish the object
    $self->hash_init(%defaults, %args);

    return $self;
}



=item fill_template()

  $pager->fill_template($template_object);

The fill_template() method is one of two ways to execute a paged view
and utilize the output.  This method is used in the context of a 
custom pager template.  The section later in this POD, "Creating
Creating Custom Pager Templates", more fully describes how and why you 
would want to use a custom template.

The fill_template() method runs the Krang::HTMLPager and sets template 
variables in the $template_object you provide.  It is then your 
responsibility to output that $template_object.

=cut

sub fill_template {
    my $self = shift;
    my $t = shift;

    # Did we get a template object?
    croak ("No HTML::Template object specified") unless (ref($t));

    $self->validate_pager();
}



=item output()

  my $pager_html = $pager->output();

The output() method is one of two ways to execute a paged view    
and utilize the output.  This method is intended for use when 
the standard built-in pager templates are being employed, as 
opposed to a custom pager template.

The output() method runs the Krang::HTMLPager and returns a block of
HTML containing the data output.  This is expected to be used in the
context of a larger template:

  $template_object->param( pager_html => $pager->output() );

The output returned is contained in a form with the name
"krang_pager_form".  This is important to know if you have a checkbox
column on which you want to operate.  In this case you are expected 
to implement a button which calls a javascript function.  The 
javascript function would have to submit the pager form to 
get access to the checked rows.  For example:

  function delete_selected () {
    var myform = document.forms["krang_pager_form"];
    myform.rm.value = "delete_selected";
    myform.submit();
  }

This assumes that your run-mode parameter is "rm" and that you have
set "rm" to be included in the pager form via the "persist_vars"
pager property.

=cut

sub output {
    my $self = shift;

    my $t = HTML::Template->new_file("HTMLPager/pager.tmpl", cache=>1);
    $self->fill_template($t);

    return $t->output();
}



=back


=head2 Krang::HTMLPager Properties

Krang::HTMLPager expects a number of parameters to be set 
via the new() method.  Following is a list of those parameters.
These parameters are also accessible via object methods.

=over 4


=item cgi_query

  cgi_query => $query

Contains the CGI.pm query object for this request.  The query object
is needed to read in the pager state parameters, such as
krang_pager_curr_page_num, krang_pager_sort_field, and krang_pager_sort_order.


=item persist_vars

  persist_vars => [ qw( rm search_filter ) ]

An arrayref containing the names of CGI parameters which should be
remembered as hidden data within the pager form.  This is necessary
for maintaining web application state.  The pager expects to have its 
own form for paging through data and re-sorting results.


=item use_module

  use_module => 'Krang::Contrib'

The name of the Krang object module which contains the find() method 
pager should use for retrieving data.  This module's find() method 
will be used for handling all queries, sorting, and paging (limit, 
offset).

Although it is expected that use_module will specify a Krang object
module, any module which implements a sufficiently compatible find()
method can be used.


=item find_params

  find_params => { simple_search => $q->param('search_filter') }

A hashref containing the search parameters exactly as they should be 
passed to find().  This hashref will be augmented to include 
parameters related to sorting (order_by, order_desc) and paging 
(limit, offset). 



=item columns

  columns => [qw( last first_middle type command_column checkbox_column )]

An arrayref containing columns names.  This property defines two
things: The order of the columns in the table (left to right), and the
key names which will be expected in custom templates.

There are two special values which can be included in the list of
columns.  If included in the column list, these columns will be
automagically handled by pager as follows:

  "command_column"   - A list of actions, implemented as Javascript links.
  "checkbox_column"  - A series of checkboxes, one per record/row.

"command_column" is used for button links such as "Edit" or "View".
How these buttons are configured is described in more detail below
(pager parameters "command_column_commands" and
"command_column_labels").

"command_column" also sets up the column header as a blank field.
This column header functionality can be overridden via "column_labels"
below.


"checkbox_column" is used for interfaces where the user is allowed to
check a set of records for the purpose of processing them in a
particular way.  For example, "delete checked", "check out", and
"associate" are examples of functionality which use these checkboxes.

Pager will automatically create these checkboxes for you.  The
checkboxes will be implemented as CGI form inputs which all are named
"krang_pager_rows_checked".  The value of each checkbox is set by
pager to be the "ID" as returned per row by the "id_handler" pager
parameter (described below).  In HTML, a typical set of checkboxes
might look like this:

  <input type="checkbox" name="krang_pager_rows_checked" value="1">
  <input type="checkbox" name="krang_pager_rows_checked" value="2">
  <input type="checkbox" name="krang_pager_rows_checked" value="3">
  <input type="checkbox" name="krang_pager_rows_checked" value="4">

This will allow you to easily retrieve an array of checked rows via
 CGI.pm:

  my @rows_checked = $query->param('krang_pager_rows_checked');

"checkbox_column" also sets up the column header as a widget through
which "select all" and "un-select all" functions can be triggered.
This column header functionality can be overridden via "column_labels"
below.


=item column_labels

  column_labels => { last=>'Last Name', first_middle=>'First, Middle Name' }

A hashref mapping column names (as defined by the "columns" pager
parameter) to the text label which should appear in the column header
line at the top of the table.

It is not necessary to define a column label for every column.  If
not supplied, the column name will be used instead, except in the case
of magic internal column types, "command_column" and
"checkbox_column".

A "command_column" header is automatically set to be blank.  You
could use "column_labels" to change it to "Commands" or something else
intuitive.  In the case of a "checkbox_column", overriding the label
via "column_labels" is probably undesirable.  A "checkbox_column" puts
a highly functional gadget in the header, which is probably required.



=item command_column_commands

  command_column_commands => [qw( edit_contrib )]

An arrayref containing the names of the Javascript functions to 
be called when the user clicks on a particular command.  The
function will be called with the "ID" (as returned per row by 
the "id_handler" pager parameter described below) as the only
argument.  For example, following would be the HTML generated
if ID was set to "4":

  <a href="javascript:edit_contrib('4')">

It is expected that a corresponding Javascript function would be
written to implement the functionality desired when the user
clicks on the command link for a particular row.


=item command_column_labels

  command_column_labels => { edit_contrib => 'Edit' }

A hashref containing a map of command names (as defined by "command_column_commands")
to the text which should be in the link which appears to the user.
For example, the above might generate:

  <a href="javascript:edit_contrib('4')">Edit</a>

If a label is not defined for a particular command, the name will 
be used instead.


=item columns_sortable

  columns_sortable => [qw( last first_middle )]

An arrayref containing the names of the columns (as defined by
"columns") by which the user is allowed to sort.  These column
headers will be clickable Javascript links which will modify the
sorting order of the data listed.

An arrow will appear next to the current sort column.  This 
graphical arrow will identify if the current sort order is 
ascending (up arrow) or descending (down arrow).



=item columns_sort_map

  columns_sort_map => { first_middle => 'first,middle' }

A hashref mapping the name of a sortable column to
the string which should be passed to find() via the 
"order_by" parameter.  If a particular sortable column
is not specified, its name will be used instead.  This
is probably adequate in most cases.


=item row_handler

  row_handler => \&my_row_handler

A subroutine reference pointing to a custom function to process each
row of data.  This function will receive, as arguments, a hashref into
which row data should be placed and a reference to the object to be
displayed on this row.  The job of your custom function is to convert
the object attributes into template data and set that data in the 
hashref.  For example:

  sub my_row_handler {
    my ($row_hashref, $row_obj) = @_;
    $row_hashref->{first_middle} = $row_obj->first() . " " . $row_obj->middle();
    $row_hashref->{last} = $row_obj->last();
    $row_hashref->{type} = join(", ", ($row_obj->contrib_type_names()) );
  }


=item id_handler

  id_handler => sub { return $_[0]->contrib_id }

A subroutine reference pointing to a custom function to return a
unique identifier for each row of data.  This ID is needed for
creating the checkbox columns and command columns.


=back


=head2 Creating Custom Pager Templates


=cut


###########################
####  PRIVATE METHODS  ####
###########################

# Verify that the pager is valid.  Croak if not.
sub validate_pager {
    my $self = shift;

    # cgi_query
    croak ("No cgi_query specified") unless (ref($self->cgi_query));

    # use_module
    my $use_module = $self->use_module();
    croak ("No use_module specified") unless ($use_module);
    eval "require $use_module";
    croak ("Can't require $use_module: $@") if ($@);
    croak ("The use_module '$use_module' has no find() method") unless ($use_module->can('find'));

    # find_params
    croak ("find_params is not a hash") unless (ref($self->find_params) eq 'HASH');

    # columns
    my $columns = $self->columns();
    croak ("columns is not an array") unless (ref($columns) eq 'ARRAY');
    croak ("No columns have been specified") unless (scalar(@$columns));

    # column_labels
    my $column_labels = $self->column_labels();
    croak ("column_labels is not a hash") unless (ref($column_labels) eq 'HASH');
    my @invalid_columns = ();
    foreach my $col_lab (keys(%$column_labels)) {
        push(@invalid_columns, $col_lab) unless (grep { $col_lab eq $_ } @$columns);
    }
    croak ("column_labels contains invalid columns '". join("', '", @invalid_columns) ."'") 
      if (@invalid_columns);

    # command_column_commands
    my $command_column_commands = $self->command_column_commands();
    croak ("command_column_commands is not an array") unless (ref($command_column_commands) eq 'ARRAY');
    if (grep { $_ eq 'command_column' } @$columns) {
        croak ("No command_column_commands have been specified")
          unless (scalar(@$command_column_commands));
    } else {
        croak ("command_column_commands have been specified but columns does not contain a command_column") 
          if (scalar(@$command_column_commands));
    }

    # command_column_labels
    my $command_column_labels = $self->command_column_labels();
    croak ("command_column_labels is not a hash") unless (ref($command_column_labels) eq 'HASH');
    @invalid_columns = ();
    foreach my $col_lab (keys(%$command_column_labels)) {
        push(@invalid_columns, $col_lab) unless (grep { $col_lab eq $_ } @$command_column_commands);
    }
    croak ("command_column_labels contains invalid commands '". join("', '", @invalid_columns) ."'") 
      if (@invalid_columns);

    # columns_sortable
    my $columns_sortable = $self->columns_sortable();
    croak ("columns_sortable is not an array") unless (ref($columns_sortable) eq 'ARRAY');
    @invalid_columns = ();
    foreach my $col_lab (@$columns_sortable) {
        push(@invalid_columns, $col_lab) unless (grep { $col_lab eq $_ } @$columns);
    }
    croak ("columns_sortable contains invalid columns '". join("', '", @invalid_columns) ."'") 
      if (@invalid_columns);

    # columns_sort_map
    my $columns_sort_map = $self->columns_sort_map();
    croak ("columns_sort_map is not a hash") unless (ref($columns_sort_map) eq 'HASH');
    @invalid_columns = ();
    foreach my $col_lab (keys(%$columns_sort_map)) {
        push(@invalid_columns, $col_lab) unless (grep { $col_lab eq $_ } @$columns_sortable);
    }
    croak ("columns_sort_map contains non-sortable columns '". join("', '", @invalid_columns) ."'") 
      if (@invalid_columns);

    # row_handler
    croak ("row_handler not a subroutine reference") unless (ref($self->row_handler()) eq 'CODE');

    # id_handler
    croak ("id_handler not a subroutine reference") unless (ref($self->id_handler()) eq 'CODE');

    # DONE!
}




=head1 AUTHOR

Jesse Erlbaum <jesse@erlbaum.net>


=head1 SEE ALSO

L<Krang>, L<Krang::CGI>


=cut






1;
