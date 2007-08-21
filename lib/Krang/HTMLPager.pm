package Krang::HTMLPager;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Carp qw(croak);
use Krang::ClassLoader 'HTMLTemplate';
use Krang::ClassLoader Conf => qw(KrangRoot);
use Krang::ClassLoader 'MyPref';
use Krang::ClassLoader Session => qw(%session);
use File::Spec::Functions qw(catdir);

=head1 NAME

Krang::HTMLPager - Web-paginate lists of records


=head1 SYNOPSIS

  #### In your Krang::CGI::* module...
  #
  use Krang::ClassLoader 'HTMLPager';

  ## In a run-mode, instantiate new pager object...
  my $pager = pkg('HTMLPager')->new(
    cgi_query   => $query,
    use_module  => pkg('Contrib'),
    columns     => [ 'last', 'first', 'command_column', 'checkbox_column' ],
    columns_sortable => [ 'last', 'first' ],
    command_column_commands => [ 'edit_contrib' ],
    id_handler  => sub { return $_[0]->contrib_id },
    row_handler => sub { $_[0]->{last} = $_[1]->last(); $_[0]->{first} = $_[1]->first(); },
  );

  # Run the pager
  my $pager_html = $pager->output();
  $template->param(pager_html => $pager_html);


  #### In your HTML::Template file...
  #
  <!-- pkg('HTMLPager') Output START -->
  <tmpl_var pager_html>
  <!-- pkg('HTMLPager') Output END -->


=cut


use Krang::ClassLoader MethodMaker => (
                        new_with_init => 'new',
                        new_hash_init => 'hash_init',
                        get           => [ qw( row_count ) ],
                        get_set       => [ qw(
                                               cgi_query 
                                               persist_vars 
                                               use_module 
                                               use_data
                                               use_data_size
                                               cache_key
                                               find_params 
                                               columns 
                                               column_labels
                                               command_column_commands
                                               command_column_labels
                                               columns_sortable 
                                               columns_sort_map
                                               default_sort_order_desc
                                               row_handler
                                               id_handler
                                               max_page_links
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

Krang::HTMLPager implements the following primary methods:

=over 4



=item new()

  my $pager = pkg('HTMLPager')->new(%pager_props);

The new() method instantiates a new pager.  It takes a litany of
parameters, which are documented in full later in this POD in the
section "Krang::HTMLPager Properties".

=cut

sub init {
    my $self = shift;
    my %args = ( @_ );

    # Set up default values
    my %defaults = (
                    persist_vars => {},
                    find_params => {},
                    columns => [],
                    column_labels => {},
                    columns_sortable => [],
                    columns_sort_map => {},
                    default_sort_order_desc => 0,
                    command_column_commands => [],
                    command_column_labels => {},
                    max_page_links => 10,
                   );

    # finish the object
    $self->hash_init(%defaults, %args);

    # Set default row_count
    $self->{row_count} = undef;

    return $self;
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

    # Dynamically create template as scalar with proper columns
    my $pager_tmpl = $self->make_internal_template();

    my $t = pkg('HTMLTemplate')->new_scalar_ref(\$pager_tmpl, loop_context_vars=>1);
    $self->_fill_template($t);

    return $t->output();
}


=item fill_template()

  $pager->fill_template($template_object);

The fill_template() method is one of two ways to execute a paged view
and utilize the output.  This method is used in the context of a 
custom pager template.  The section later in this POD, "Creating Custom 
Pager Templates", more fully describes how and why you would want to 
use a custom template.

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

    $self->_fill_template($t);
}



=item row_count()

    my $row_count = $pager->row_count();

The row_count() method returns the number of rows output
by the pager.  It is expected to be called after output()
or fill_template().  Until one of those methods are called
row_count() will return undef.

This method is useful for changing the UI based on whether 
or not any results were found.


=cut

### row_count() is implemented via Krang::MethodMaker


=item make_internal_template()

  my $template = $pager->make_internal_template();

The make_internal_template() method returns a dynamically created template
for use with Krang::HTMLPager.  This method is used internally by output()
to generate a template based on your specification.

This method is made public to assist in the creation of custom pager
templates.  Using this method you can specify and create a template which can
be saved to a file and customized as needed.

=cut

sub make_internal_template {
    my $self = shift;

    # Verify that pager specification is sane before proceeding
    $self->validate_pager();

    my $q = $self->cgi_query();
    my $pager_tmpl = '';

    # Start pager form 'krang_pager_form'
    $pager_tmpl .= '<form name="krang_pager_form" method="POST">';

    # Include javascript and hidden data template elements
    $pager_tmpl .= "\n\n<tmpl_include HTMLPager/pager-internals.tmpl>\n\n";

    # Major TMPL_IF block for results, start
    $pager_tmpl .= "<tmpl_if krang_pager_rows>\n\n";

    # Result count/page status display
    $pager_tmpl .= '<div class="no-border">&nbsp;Found <tmpl_var found_count>:  Showing <tmpl_var start_row> to <tmpl_var end_row></div>';

    # Build up table and header row
    my @columns = @{$self->columns()};
    $pager_tmpl .= '<table class="form-cell" border="0" cellspacing="0" cellpadding="0" width="571"><tr class="form-head"><td class="form-head2">'
      . join("</td>\n<td class=\"form-head2\">", (map { "<tmpl_var colhead_$_><tmpl_unless colhead_$_>&nbsp;</tmpl_unless>" } @columns) ) ."</td></tr>\n\n\n";

    # Build loop for data
    my $row_tmpl = "<tr>\n<td class=\"form-cell\">"
      . join("</td>\n    <td class=\"form-cell\">", (map { "<tmpl_var $_>" } @columns)) ."</td>\n</tr>";

    $pager_tmpl .= <<EOF;
  <tmpl_loop krang_pager_rows>
    $row_tmpl
  </tmpl_loop>
 
  </table>
EOF
    # Make page jump, next/prev navigation tmpl
    $pager_tmpl .= <<EOF;
<div class="no-border"><p class="left2">&nbsp;<tmpl_if prev_page_number><a href="javascript:go_page('<tmpl_var prev_page_number>')">&lt;&lt;</a></tmpl_if>

<tmpl_loop page_numbers>
  <tmpl_if is_current_page><b><tmpl_var page_number></b>
  <tmpl_else><a href="javascript:go_page('<tmpl_var page_number>')"><tmpl_var page_number_label></a>
  </tmpl_if>
  <tmpl_unless __last__>|</tmpl_unless>
</tmpl_loop>

<tmpl_if next_page_number><a href="javascript:go_page('<tmpl_var next_page_number>')">&gt;&gt;</a></tmpl_if>

<tmpl_if show_big_view>
  <a href="javascript:show_big_view('0')">show <tmpl_var user_page_size> per page</a></p></div>
<tmpl_else>
  <tmpl_if page_numbers>
    <a href="javascript:show_big_view('1')">show <tmpl_var big_view_page_size> per page</a></p></div>
  </tmpl_if>
</tmpl_if>

<tmpl_else>
  <div class="no-border"><p class="left2"><b>&nbsp;None Found</b></p></div>
</tmpl_if>
EOF

    # Close pager form
    $pager_tmpl .= "\n</form>\n";

    return $pager_tmpl;
}



=back


=head2 Krang::HTMLPager Properties

Krang::HTMLPager expects a number of parameters to be set via the
new() method.  These parameters set properties which are used to
create a specification for your pager, such as the list of columns and
which of those columns are sortable.

Following is a list of the parameters for Krang::HTMLPager.
These parameters are also accessible via object methods.

=over 4


=item cgi_query

  cgi_query => $query

Contains the CGI.pm query object for this request.  The query object
is needed to read in the pager state parameters, such as
krang_pager_curr_page_num, krang_pager_sort_field, and krang_pager_sort_order.


=item persist_vars

  persist_vars => {
                    rm => 'search',
                    search_filter => $search_filter,
                  }

A hashref containing the names and values of CGI parameters which should be
remembered as hidden data within the pager form.  This is necessary
for maintaining web application state.  The pager expects to have its 
own form for paging through data and re-sorting results.

Values set in persist_vars will be implemented via CGI.pm's hidden() method
with "-override=>1" set.  This will ensure that the value you specify will be
set regardless of the current state of that form parameter.


=item use_module

  use_module => pkg('Contrib')

The name of the Krang object module which contains the find() method 
pager should use for retrieving data.  This module's find() method 
will be used for handling all queries, sorting, and paging (limit, 
offset).

Although it is expected that use_module will specify a Krang object
module, any module which implements a sufficiently compatible find()
method can be used.  In this case, "sufficiently compatible" means
the following parameters are supported:

  * count
  * order_by
  * order_desc
  * offset
  * limit

=item use_data

In some cases you might already have the data you want to page
and you just need HTMLPager to do the formatting. In this case
pass in an array ref to your data here instead of providing
a value for L<use_module>.

=item use_data_size

If you are using L<use_data> and what you provided was not the
entire dataset, then you can let HTMLPager know what the full
size is. This allows it to accurately build the paging links.

=item cache_key

HTMLPager uses the session cache to store some information about
a paged list to re-use that same information on future requests
for the same list. By default we use L<use_module> as the cache
key, but you may need to provide your own key if you use the
same L<use_module> in multiple places or you are using L<use_data>.

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

The first item in the list will be regarded as the B<default sort column>.
This column will be used for sort the first time the pager is invoked.
This behavior, combined with the "default_sort_order_desc"
property, allows you to control the default pager sort behavior.


=item columns_sort_map

  columns_sort_map => { first_middle => 'first,middle' }

A hashref mapping the name of a sortable column to
the string which should be passed to find() via the 
"order_by" parameter.  If a particular sortable column
is not specified, its name will be used instead.  This
is probably adequate in most cases.


=item default_sort_order_desc

  default_sort_order_desc => 1

A scalar containing a Boolean (1 or 0) value.  If true,
when the pager is first called the sort order will be
set to "descending"  If not set, this property will
default to "0" and sort order will consequently default
to "ascending".


=item row_handler

  row_handler => sub { $self->my_row_handler(@_) }

A subroutine reference pointing to a custom function to process each
row of data.  This function will receive, as arguments, a hashref into
which row data should be placed and a reference to the object to be
displayed on this row.  The job of your custom function is to convert
the object attributes into template data and set that data in the 
hashref.  For example:

  sub my_row_handler {
    my ($self, $row_hashref, $row_obj) = @_;
    $row_hashref->{first_middle} = $row_obj->first() . " " . $row_obj->middle();
    $row_hashref->{last} = $row_obj->last();
    $row_hashref->{type} = join(", ", ($row_obj->contrib_type_names()) );
  }


=item id_handler

  id_handler => sub { return $_[0]->contrib_id }

A subroutine reference pointing to a custom function to return a
unique identifier for each row of data.  This ID is needed for
creating the checkbox columns and command columns.

The referenced subroutine receives a reference to the object to be
displayed on this row.  The job of your custom function is to return
a unique identifier for this row.

=item max_page_links

  max_page_links => 10

Set this to the maximum number of page links that the pager should
display.  Any more pages outside this number will be represented by a
"..." in the output HTML.  If set to 0 all page links are shown.  The
default is 10.

=back


=head2 Creating Custom Pager Templates

It is expected that most of the time you will use the output() method
to run the pager and return a rendered block of HTML with your
interface.  The HTML which is returned is generated internally within 
Krang::HTMLPager.

In some cases, this internally-created HTML will not suffice.  You may
have to implement a screen which has a slightly different style to it.
You may have additional functionality which is not compatible with 
that provided by the stock Krang::HTMLPager output.  In these cases
you may want to create your own custom Krang::HTMLPager template
to replace the internal one.

This is not a task for the faint of heart.  Your template must be 
structured to be fully compatible with the internal template in
terms of HTML::Template structures.  The easiest way to get started
with a custom template is to have Krang::HTMLPager dynamically 
generate a template for you, which you can then customize.  This 
can be done via the make_internal_template() method:

  my $pager = pkg('HTMLPager')->new(%pager_props);
  my $template = $pager->make_internal_template();

Refer to the make_internal_template() POD in this document for more 
details.

The template which is created contains all the variables necessary
in a custom template, for the pager specification (%pager_props) 
you have provided.  Following is a summary of the variables you 
will find.

=over 4


=item <tmpl_include HTMLPager/pager-internals.tmpl>

This tmpl_include brings in a special template containing 
Javascript and CGI form elements required for all pagers.
(This should not be confused with the "internal" template.
The template name, F<pager-internals.tmpl>, is coincidental.)


=item krang_pager_rows

This variable contains the rows of data on the current screen of 
the pager.  It is expected to be called as a <TMPL_LOOP>.  It is also
used in the context of a <TMPL_IF>/<TMPL_ELSE> to provide alternate
output if there are no results -- for instance, a search for which 
there are no matching records found.


=item found_count

The number of records found as the result of a search, in total.


=item start_row

The number of the row in the total result set at which the current page
is starting its display.


=item end_row

The number of the row in the total result set at which the current page
is ending its display.


=item colhead_<column name>

It is the responsibility of Krang::HTMLPager to build the "header" row
of the results table.  For the most part, this row contains the names 
of all the columns.  Columns which are sortable are made to be links.
State information is added to sortable column headers if they are the 
currently selected sort row.  Other behaviors are articulated here, 
as documented elsewhere in this POD.

In order to implement this functionality, one <TMPL_VAR> is 
expected for each column in the pager.  These variables are named
using the column name (as defined by the "columns" pager property), 
with the prefix, "colhead_".


=item <column name>

The rows within the "krang_pager_rows" <TMPL_LOOP> are expected to 
each contain one <TMPL_VAR> for each column.  These variables are named
using the column name (as defined by the "columns" pager property).


=item prev_page_number

The pager is expected to provide a link to the previous page if the current 
page is not the first page.  The <TMPL_VAR> "prev_page_number" contains the
number of the previous page, or "0" if we're already on the first page.

The internal template uses "prev_page_number" in the context of a
<TMPL_IF> to hide the previous page button on the first page.

(N.b.: A Javascript function, "go_page()", is provided for navigation
between pages by F<pager-internals.tmpl>.  You are encouraged to use it.)


=item next_page_number

The pager is expected to provide a link to the next page if the current 
page is not the last page.  The <TMPL_VAR> "next_page_number" contains the
number of the next page, or "0" if we're already on the last page.

The internal template uses "next_page_number" in the context of a
<TMPL_IF> to hide the next page button on the last page.

(N.b.: A Javascript function, "go_page()", is provided for navigation
between pages by F<pager-internals.tmpl>.  You are encouraged to use it.)


=item page_numbers

The pager is expected to provide a list of page numbers which are
links to allow the user to jump between pages.  The <TMPL_LOOP>
"page_numbers" contains this list.  Each for in "page_numbers" is
expected to implement three variables, "page_number",
"page_number_label" and "is_current_page" which are described below.


=item page_number

Available in the context of the <TMPL_LOOP> "page_numbers", the
<TMPL_VAR> "page_number" contains the number of the page.  
This is used by the internal template as a link to jump to a 
particular page of output.

(N.b.: A Javascript function, "go_page()", is provided for navigation
between pages by F<pager-internals.tmpl>.  You are encouraged to use it.)

=item page_number_label

Available in the context of the <TMPL_LOOP> "page_numbers", the
<TMPL_VAR> "page_number_label" contains the label for a page number.  This
might be the number itself or it might be the string "...".


=item is_current_page

Available in the context of the <TMPL_LOOP> "page_numbers", the
<TMPL_VAR> "is_current_page" contains "1" if the current "page_number"
is, in fact, the current page being viewed, "0" if not.  This is used by the
internal template in the context of a <TMPL_IF>/<TMPL_ELSE> to 
conditionally disable the link to the current page.

(N.b.: A Javascript function, "go_page()", is provided for navigation
between pages by F<pager-internals.tmpl>.  You are encouraged to use it.)


=item show_big_view

Krang::HTMLPager allows the user to toggle between two page sizes: 
Custom size (set by user preference) and "Show 100 rows" (unless Custom
size is 100, then this becomes "Show 20 rows").  The
<TMPL_VAR> "show_big_view" is set to "1" if the user is in the 
"100 rows" mode, "0" otherwise.

(N.b.: A Javascript function, "show_big_view()", is provided for 
toggling between modes by F<pager-internals.tmpl>.  You are encouraged to use it.)

=item user_page_size

Krang::HTMLPager allows the user to toggle between two page sizes: 
Custom size (set by user preference) and "Show 100 rows" (unless Custom
size is 100, then this becomes "Show 20 rows").  The
<TMPL_VAR> "user_page_size" is set to the custom page size.

=item big_view_page_size

The number of items to show when C<show_big_view> is true. Normally this
is 100, but if the user's preference is for 100, then this becomes 20.

=back

=cut

sub calculate_order_by {
    my ($self, $q, $cache_key) = @_;
    my $order_by;

    # if we weren't given a cache key and we're called as an object method
    $cache_key ||= ref $self ? ($self->cache_key || $self->use_module) : '';

    if( defined $q->param('krang_pager_sort_field') ) {
        $order_by = scalar $q->param('krang_pager_sort_field');
        # store it in the session if we have a module to key it off of
        $session{"KRANG_${cache_key}_PAGER_SORT_FIELD"} = $order_by if $cache_key;
    } elsif( $cache_key && $session{"KRANG_${cache_key}_PAGER_SORT_FIELD"} ) {
        $order_by = $session{"KRANG_${cache_key}_PAGER_SORT_FIELD"};
    } elsif( ref $self ) {
        $order_by = $self->columns_sortable()->[0];  # First sort column
	$q->param(-name => 'krang_pager_sort_field', -value => $order_by);
    }

    return $order_by;
}

sub calculate_order_desc {
    my ($self, $q, $cache_key) = @_;
    my $order_desc;

    # if we weren't given a cache key and we're called as an object method
    $cache_key ||= ref $self ? ($self->cache_key || $self->use_module) : '';

    if (defined $q->param('krang_pager_sort_order_desc')) {
        $order_desc = $q->param('krang_pager_sort_order_desc');
        # store it in the session if we have a module to key it off of
        $session{"KRANG_${cache_key}_PAGER_SORT_ORDER_DESC"} = $order_desc if $cache_key;
    } elsif( $cache_key && defined $session{"KRANG_${cache_key}_PAGER_SORT_ORDER_DESC"}) {
        $order_desc = $session{"KRANG_${cache_key}_PAGER_SORT_ORDER_DESC"};
    } elsif( ref $self ) {
        $order_desc = $self->default_sort_order_desc ? '1' : '0';
    } else {
        $order_desc = 0;
    }
    return $order_desc;
}

sub calculate_limit {
    my ($self, $q, $cache_key) = @_;
    my $limit;

    # Page size is either 100, or user preferred size.
    my $show_big_view = ($q->param('krang_pager_show_big_view') || '0');
    my $user_page_size = $self->get_user_page_size();
    my $big_view_size  = $user_page_size == 100 ? 20 : 100;
    return ($show_big_view) ? ($user_page_size == 100 ? 20 : 100) : $user_page_size ;
}

sub calculate_current_page_num {
    my ($self, $q, $cache_key) = @_;
    return (scalar $q->param('krang_pager_curr_page_num') || '1');
}

###########################
####  PRIVATE METHODS  ####
###########################

# Return the user-preferred page size
sub get_user_page_size {
    my $page_size = pkg('MyPref')->get('search_page_size');
    return $page_size;
}

# Given a column name and a column label, return an HTML block containing
# the sort button, plus state (currently selected, ascending/descending)
sub make_sortable_column_html {
    my $self = shift;
    my ($col, $col_label) = @_;

    my $q = $self->cgi_query();

    my $use_module = $self->use_module() || ''; # use_data doesn't have a use_module
    $use_module =~ s/Krang:://;
    
    # Is column currently selected? If not, attempt to find in cache, or set default
    my $sort_field = $self->calculate_order_by($q);
    my $sort_order_desc = $self->calculate_order_desc($q);

    # If selected, show in bold, with arrow showing current sort order (ascending, descending)
    my $is_selected = ( $sort_field eq $col );
    if ($is_selected) {
        $col_label = "<b>$col_label</b>";
        $col_label .= '<img border="0" src="/images/arrow-'. ($sort_order_desc ? 'desc' : 'asc') .'.gif">';
    }

    # Make link to re-sort
    my $new_sort_order_desc = ($is_selected && not($sort_order_desc)) ?  '1' : '0';
    $col_label = "<a href=\"javascript:do_sort('$col', '$new_sort_order_desc')\">$col_label</a>";

    return $col_label;
}


# Actually run the pager and fill the template here
sub _fill_template {
    my $self = shift;
    my $t = shift;

    my $q = $self->cgi_query();

    # Set up get_form_obj_magic_name -- special parameter to find proper <form>
    my $get_form_obj_magic_name = "krang_pager_". scalar(time);
    $t->param(get_form_obj_magic_name => $get_form_obj_magic_name);

    # Build up hash of column headers
    my %column_header_labels = ();
    foreach my $col (@{$self->columns()}) {
        my $col_tmpl_name = "colhead_$col";
        my $col_label = $self->column_labels()->{$col};

        # Create col header for command_column
        if ( $col eq 'command_column') {
            $col_label = ( defined($col_label) ? $col_label : "" );
        }

        # Create col header for checkbox_column
        if ( $col eq 'checkbox_column' ) {
            my $checkall = '<input type="checkbox" name="checkallbox" value="1" onClick="checkall(this, \'krang_pager_rows_checked\')">';
            $col_label = ( defined($col_label) ? $col_label : $checkall );
        }

        # Copy label from column_labels or use column name
        $col_label = ( defined($col_label) ? $col_label : $col );

        # Add sorting, if we have any
        if (grep { $_ eq $col } @{$self->columns_sortable()}) {
            $col_label = $self->make_sortable_column_html($col, $col_label);
        }

        # Set the final column label HTML
        $column_header_labels{$col_tmpl_name} = $col_label;
    }
    $t->param(%column_header_labels);

    # Process pager and get rows
    my $pager_view = $self->get_pager_view();
    $t->param($pager_view);

    # Set up persist_vars
    my @pager_persist_data = ();
    my $cache_key = $self->cache_key || $self->use_module;

    while (my ($k, $v) = each(%{$self->persist_vars()})) {
        push(@pager_persist_data, $q->hidden(
                                             -name => $k,
                                             -value => $v,
                                             -override => 1
                                            ));

        $session{KRANG_PERSIST}{$cache_key}{$k} = $v;
    }
    
    $t->param(pager_persist_data => join("\n", @pager_persist_data));
}

sub get_pager_view {
    my $self = shift;

    my $q = $self->cgi_query();

    my $cache_key = $self->cache_key || $self->use_module;
    my $use_module = $self->use_module;

    my $curr_page_num = $self->calculate_current_page_num($q);
    my $sort_field = $self->calculate_order_by($q);
    my $sort_order_desc = $self->calculate_order_desc($q);
    my $limit = $self->calculate_limit($q);

    # Count used to calculate page navigation
    my %find_params = %{$self->find_params()};
    my $found_count = $use_module 
        ? $use_module->find(%find_params, count=>1)
        : $self->use_data_size 
            ? $self->use_data_size
            : scalar @{$self->use_data};
    my $total_pages = int($found_count / $limit) + (($found_count % $limit) > 0);
    $total_pages ||= 1; # For the case when 0 == $found_count.

    # Is the current page beyond the $total_pages?  Bring it back in.
    # This may be the case if a delete operation has reduced the number of pages.
    $curr_page_num = $total_pages if ($curr_page_num > $total_pages);

     # Build page-jumper
    my @page_numbers;
    my $max_page_links = $self->max_page_links;
    if ($max_page_links and $total_pages > $max_page_links) {
        # compute start and end of sequence to show
        my $start = ( int(($curr_page_num - 1) / $max_page_links) * 
                      $max_page_links ) + 1;
        my $end   = $start + $max_page_links - 1;
        $end = $total_pages if $end > $total_pages;

        # output page numbers and elipses
        push(@page_numbers, 
             { page_number => 1,
               page_number_label => "1" },
             { page_number => $start - 1,
               page_number_label => "..." }) if $start != 1;
        push(@page_numbers,
          map { { page_number      => $_, 
                  page_number_label=> $_,
                  is_current_page  => ($_ eq $curr_page_num) } }
            ($start..$end));
        push(@page_numbers, 
             { page_number => $end + 1,
               page_number_label => "..." },
             { page_number => $total_pages,
               page_number_label => $total_pages }) if $end != $total_pages;
    } else {
        if( $total_pages > 1 ) {
            @page_numbers = 
              map { { page_number      => $_, 
                      page_number_label=> $_,
                      is_current_page  => ($_ eq $curr_page_num) } }
                (1..$total_pages);
        }
    }

    # Determine row number at which display starts
    my $offset = ($curr_page_num - 1) * $limit;

    # Set up previous page nav -- show link unless we're on the first page
    my $prev_page_number = $curr_page_num - 1;
    $prev_page_number = 0 unless ($curr_page_num > 0);

    # Set up next page nav -- show link unless we're on the last page
    my $next_page_number = $curr_page_num + 1;
    $next_page_number = 0 unless ($next_page_number <= $total_pages);

    # Retrieve and build rows
    my $order_by = defined $sort_field
        ? ( $self->columns_sort_map()->{$sort_field} || $sort_field )
        : undef;
    my @found_objects;
    if( $use_module ) {
        my %all_find_params = (
                               %find_params,
                               order_by => $order_by,
                               order_desc => $sort_order_desc,
                               offset => $offset,
                               limit => $limit,
                              );
        @found_objects = $use_module->find(%all_find_params);
    } else {
        @found_objects = @{$self->use_data};
    }

    # Build TMPL_LOOP data
    my @krang_pager_rows = ();
    my $row_count = 0;
    foreach my $fobj (@found_objects) {
        my %row_data = ( map { $_=>'' } @{$self->columns} );

        # Build command_column and checkbox_column
        $self->make_dynamic_columns(\%row_data, $fobj);

        # Call row_handler
        my $row_handler = $self->row_handler();
        $row_handler->(\%row_data, $fobj);

        # Propagate to template
        push(@krang_pager_rows, \%row_data);

        $row_count++;
    }
    $self->{row_count} = $row_count;

    # Build up status/page display
    my $start_row = $offset + 1;
    my $end_row = $offset + $row_count;

    my %pager_view = (
                      curr_page_num      => $curr_page_num,
                      sort_field         => $sort_field,
                      sort_order_desc    => $sort_order_desc,
                      show_big_view      => ($q->param('krang_pager_show_big_view') || '0'),
                      user_page_size     => $self->get_user_page_size,
                      big_view_page_size => ( $self->get_user_page_size == 100 ? 20 : 100 ),
                      found_count        => $found_count,
                      start_row          => $start_row,
                      end_row            => $end_row,
                      page_numbers       => \@page_numbers,
                      prev_page_number   => $prev_page_number,
                      next_page_number   => $next_page_number,
                      krang_pager_rows   => \@krang_pager_rows,
                     );

    return \%pager_view;
}


# Build command_column and row_column
sub make_dynamic_columns {
    my $self = shift;
    my ($row_data, $fobj) = @_;

    my $id_handler = $self->id_handler();
    my $row_id = $id_handler->($fobj);

    # Build command_column
    if (exists($row_data->{command_column})) {
        my @command_column_commands = @{$self->command_column_commands()};
        my %command_column_labels = %{$self->command_column_labels()};

        # Build HTML for commands
        my @commands_html = ();
        foreach my $command (@command_column_commands) {
            my $href = "javascript:$command('$row_id')";
            my $link_text = (exists($command_column_labels{$command}) 
                             ? $command_column_labels{$command} : $command);
            my $link = "<a href=\"$href\">$link_text</a>";
            push(@commands_html, $link);
        }

        # Propagate to template
        my $command_column_html = join("&nbsp;|&nbsp;", @commands_html);
        $row_data->{command_column} = $command_column_html;
    }

    # Build checkbox_column
    if (exists($row_data->{checkbox_column})) {
        my $html = '<input type="checkbox" name="krang_pager_rows_checked" value="'. $row_id .'">';
        $row_data->{checkbox_column} = $html;
    }
}


# Verify that the pager is valid.  Croak if not.
sub validate_pager {
    my $self = shift;

    # cgi_query
    croak ("No cgi_query specified") unless (ref($self->cgi_query));

    # persist_vars
    croak ("persist_vars is not a hash") unless (ref($self->persist_vars) eq 'HASH');

    # use_module
    my $use_module = $self->use_module();
    my $use_data   = $self->use_data();
    croak ("No use_module or use_data specified") unless ($use_module || $use_data);
    if( $use_module ) {
        eval "require $use_module";
        croak ("Can't require $use_module: $@") if ($@);
        croak ("The use_module '$use_module' has no find() method") unless ($use_module->can('find'));
        # find_params
        croak ("find_params is not a hash") unless (ref($self->find_params) eq 'HASH');
    } elsif( $use_data ) {
        croak ("use_data is not an array") unless (ref $use_data eq 'ARRAY');
    }

    # make sure there's something we can use as the cache_key
    croak("You must either provide a 'cache_key' or 'use_module' value")
        unless $self->use_module or $self->cache_key;

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

    # default_sort_order_desc
    my $default_sort_order_desc = $self->default_sort_order_desc();
    croak("default_sort_order_desc not defined") unless (defined($default_sort_order_desc));

    # row_handler
    croak ("row_handler not a subroutine reference") unless (ref($self->row_handler()) eq 'CODE');

    # id_handler
    croak ("id_handler not a subroutine reference") unless (ref($self->id_handler()) eq 'CODE');

    # DONE!
}

# Hallelujah!
1;
