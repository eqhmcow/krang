package Krang::HTMLPager;



=head1 NAME

Krang::HTMLPager - Web-paginate lists of records


=head1 SYNOPSIS

  use Krang::HTMLPager;

  # Instantiate new template
  my $pager = Krang::HTMLPager->new(
    name => 'contrib_pager',
    cgi_query => $q,
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

sub init {
    my $self = shift;
    my %args = ( @_ );

    $args{name} ||= 'krang_pager';

    # finish the object
    $self->hash_init(%args);

    return $self;
}





=head1 DESCRIPTION

The primary purpose of Krang::HTMLPager is to allow Krang-style
page able lists of results to be easily created.  The secondary
purpose is to enforce a standard function and appearance to these
lists.

The pager interface is designed to work specifically with the Krang
system, and to be as simple to use as possible.  It is modeled after
HTML::Pager, but is more specialized for use with Krang.  For example, it is not 



=head1 INTERFACE


=head1 AUTHOR

Jesse Erlbaum <jesse@erlbaum.net>


=head1 SEE ALSO

L<Krang>, L<Krang::CGI>


=cut






1;
