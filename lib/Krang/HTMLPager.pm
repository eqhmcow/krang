package Krang::HTMLPager;
use strict;
use warnings;


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
                                               name 
                                               cgi_query 
                                               tmpl_obj 
                                               use_module 
                                               persist_vars 
                                               columns 
                                               columns_sortable 
                                               find_params 
                                               columns_sort_map 
                                               column_label
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

    $args{name} ||= 'krang_pager';

    # finish the object
    $self->hash_init(%args);

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

sub fill_template {}



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

sub output {}



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
"order_by" parameter.


=item row_handler

  row_handler => \&my_row_handler

Bleh bleh bleh...


=item id_handler

  id_handler => sub { return $_[0]->contrib_id }

Bleh bleh bleh...


=back


=head2 Creating Custom Pager Templates



=head1 AUTHOR

Jesse Erlbaum <jesse@erlbaum.net>


=head1 SEE ALSO

L<Krang>, L<Krang::CGI>


=cut






1;
