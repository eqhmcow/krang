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
     columns => [qw( last first_middle type order delete_select )],
     row_handler => sub { return {first_middle=>$_[0]->first." ".$_[0]->middle} },
     columns_sortable => [qw( last first_middle )],
     columns_sort_map => { first_middle => 'first,middle' },
     column_labels => {
                        last => 'Last Name',
                        first_middle => 'First, Middle Name'
                      },
     javascript_presubmit => 'confirm("Are you SURE?")',
  );

  # Render template as HTML
  $template->param( pager_html => $pager->output() );

  # Set up params on custom template
  $pager->fill_template($template):

=cut


use Krang::MethodMaker (
                        new_with_init => 'new',
                        new_hash_init => 'hash_init',
                        get_set       => [ qw(name cgi_query tmpl_obj use_module) ],
                        list          => [ qw(persist_vars columns columns_sortable) ],
                        hash          => [ qw(find_params columns_sort_map column_labels) ],
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
