use Test::More qw(no_plan);    # tests => '11';
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'Test::Content';
use strict;
use warnings;

# Needed for Pager
use CGI;
use Krang::ClassLoader 'Script';

BEGIN { use_ok(pkg('HTMLPager')) }

my $creator = pkg('Test::Content')->new();

# Can we create a new pager?
my $pager;
eval { $pager = pkg('HTMLPager')->new() };
ok(not($@), 'new() not die');
ok(ref($pager), 'Krang::HTMLPager->new()');
isa_ok($pager, 'Krang::HTMLPager');

# Can we create a pager with parameters?
my $q           = CGI->new("search_filter=asd");
my %pager_props = (
    cgi_query    => $q,
    persist_vars => {
        rm            => 'search',
        search_filter => '',
    },
    use_module    => pkg('Contrib'),
    find_params   => {simple_search => $q->param('search_filter')},
    columns       => [qw( last first_middle type command_column checkbox_column )],
    column_labels => {
        last         => 'Last Name',
        first_middle => 'First, Middle Name'
    },
    columns_sortable        => [qw( last first_middle )],
    columns_sort_map        => {first_middle => 'first,middle'},
    default_sort_order_desc => 0,
    command_column_commands => [qw( edit_contrib )],
    command_column_labels   => {edit_contrib => 'Edit'},
    row_handler             => sub {
        my ($r, $o) = @_;
        map { $r->{$_} = "$_: " . $o->contrib_id } keys(%$r);
    },
    id_handler => sub {
        return $_[0]->contrib_id;
    },
);
eval { $pager = pkg('HTMLPager')->new(%pager_props) };
ok(not($@), 'new() not die');
ok(ref($pager), 'Krang::HTMLPager->new(%pager_props)');

# Can we retrieve those parameters?
for (keys(%pager_props)) {
    ok($pager->$_ eq $pager_props{$_}, "\$pager->$_()");
}

# Test default values
$pager = pkg('HTMLPager')->new();
my @array_props = qw(
  columns
  columns_sortable
  command_column_commands
);
for (@array_props) {
    is(ref($pager->$_()), "ARRAY", "Default $_ is ARRAY");
}

my @hash_props = qw(
  find_params
  persist_vars
  column_labels
  columns_sort_map
  command_column_labels
);
for (@hash_props) {
    is(ref($pager->$_()), "HASH", "Default $_ is HASH");
}

# Can we set parameters?
for (keys(%pager_props)) {
    my $val = "XXX $_";
    ok($pager->$_($val), "Set $_");
    is($pager->$_(), $val, "Get $_");
}

# Test validation
$pager = pkg('HTMLPager')->new();
for (keys(%pager_props)) {
    $pager->$_(undef);
}

eval { $pager->output() };
like($@, qr/No cgi_query specified/, "Validate: No CGI query");

$pager->cgi_query(CGI->new(""));
eval { $pager->output() };
like($@, qr/persist_vars is not a hash/, "Validate: persist_vars hash");

$pager->persist_vars({});
eval { $pager->output() };
like($@, qr/No use_module or use_data specified/, "Validate: No use_module");

$pager->use_module('No::Such::Module');
eval { $pager->output() };
like($@, qr/Can\'t require No::Such::Module/, "Validate: No such use_module");

$pager->use_module('');
$pager->use_data({});
eval { $pager->output() };
like($@, qr/use_data is not an array/, "Validate: use_data array");

$pager->use_module('Krang');
eval { $pager->output() };
like($@, qr/The use_module \'Krang\' has no find\(\) method/, "Validate: No find() method");

$pager->use_module(pkg('Contrib'));
eval { $pager->output() };
like($@, qr/find_params is not a hash/, "Validate: find_params hash");

$pager->find_params({});
eval { $pager->output() };
like($@, qr/columns is not an array/, "Validate: columns array");

$pager->columns([]);
eval { $pager->output() };
like($@, qr/No columns have been specified/, "Validate: columns specified");

$pager->columns([qw( last first_middle type checkbox_column )]);
eval { $pager->output() };
like($@, qr/column_labels is not a hash/, "Validate: column_labels hash");

$pager->column_labels(
    {no_such_column => 'No Column', no_such_column2 => 'No Column', no_such_column3 => 'No Column'}
);
eval { $pager->output() };
like($@, qr/column_labels contains invalid columns/, "Validate: column_labels match columns");

$pager->column_labels({last => 'Last', first_middle => 'First/Middle', type => 'Type'});
eval { $pager->output() };
like($@, qr/command_column_commands is not an array/, "Validate: command_column_commands array");

$pager->command_column_commands([qw( Edit )]);
eval { $pager->output() };
like(
    $@,
    qr/command_column_commands have been specified but columns does not contain a command_column/,
    "Validate: command_column_commands without command_column"
);

$pager->command_column_commands([]);
push(@{$pager->columns}, 'command_column');
eval { $pager->output() };
like(
    $@,
    qr/No command_column_commands have been specified/,
    "Validate: command_column without command_column_commands"
);

$pager->command_column_commands([qw( edit_contrib )]);
eval { $pager->output() };
like($@, qr/command_column_labels is not a hash/, "Validate: command_column_labels hash");

$pager->command_column_labels(
    {no_such_column => 'No Column', no_such_column2 => 'No Column', no_such_column3 => 'No Column'}
);
eval { $pager->output() };
like(
    $@,
    qr/command_column_labels contains invalid commands/,
    "Validate: command_column_labels match commands"
);

$pager->command_column_labels({edit_contrib => 'Edit'});
eval { $pager->output() };
like($@, qr/columns_sortable is not an array/, "Validate: columns_sortable array");

$pager->columns_sortable([qw( no_such_column1 no_such_column2 no_such_column3 )]);
eval { $pager->output() };
like($@, qr/columns_sortable contains invalid columns/, "Validate: columns_sortable match columns");

$pager->columns_sortable([qw( last first_middle )]);
eval { $pager->output() };
like($@, qr/columns_sort_map is not a hash/, "Validate: columns_sort_map hash");

$pager->columns_sort_map(
    {no_such_column => 'No Column', no_such_column2 => 'No Column', no_such_column3 => 'No Column'}
);
eval { $pager->output() };
like(
    $@,
    qr/columns_sort_map contains non-sortable columns/,
    "Validate: columns_sort_map match columns_sortable"
);

$pager->columns_sort_map({first_middle => 'first,middle'});
eval { $pager->output() };
like($@, qr/default_sort_order_desc not defined/, "Validate: default_sort_order_desc defined");

$pager->default_sort_order_desc(0);
eval { $pager->output() };
like($@, qr/row_handler not a subroutine reference/, "Validate: row_handler subref");

$pager->row_handler(
    sub {
        my ($r, $o) = @_;
        map { $r->{$_} = "$_: " . $o->contrib_id } keys(%$r);
    }
);
eval { $pager->output() };
like($@, qr/id_handler not a subroutine reference/, "Validate: id_handler subref");

$pager->id_handler(sub { return $_[0]->contrib_id });

$pager->cgi_query(CGI->new());
$pager->cgi_query->script_name('silence_uninitialized_warnings');

# Pager should be able to output now.
my $contrib = $creator->create_contrib;
my $output  = $pager->output();
like($output, qr/krang_pager_curr_page_num/, "Pager output looks right");
$contrib->delete;
