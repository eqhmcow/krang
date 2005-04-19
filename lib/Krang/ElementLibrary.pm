package Krang::ElementLibrary;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

=head1 NAME

Krang::ElementLibrary - the element class loader and indexer

=head1 SYNOPSIS

  use Krang::ClassLoader 'ElementLibrary';

  # load an element set by name
  pkg('ElementLibary')->load_set(set => "Flex");

  # get a list of available top level elements
  @top_levels = pkg('ElementLibary')->top_levels());

  # get the object for the top level called "article" from the current set
  $class = pkg('ElementLibary')->top_level(name => "article");

  # find a class within the current set
  $class = pkg('ElementLibrary')->find_class(name => "deck")

  # get a list of all element names, anywhere in the element library
  @names = pkg('ElementLibrary')->element_names();

=head1 DESCRIPTION

This module is responsible for loading the Krang Element Library and
allowing access to the classes contained within it.  Each instance is
configured with an element set in F<krang.conf>:

  <Instance test>
     InstanceElementSet Flex
  </Instance>

This library is responsible for loading the configured element sets
and responding to requests to find individual element classes.

=head2 Element Sets

An element set consists of a configuration file, F<set.conf>, and a
series of Perl modules implementing the element classes.  The
configuration file is in Apache format and may contain the following
directives:

=over 4

=item C<Version> (required)

The version number of element set.  Should be a floating point number.

=item C<KrangVersion> (optional)

The version of Krang required by this element set.  This should be
incremented when features are used that are not available in all
versions of Krang.

=item C<ParentSets> (optional)

Set this option to a list of element sets to inherit from.  Parent
element sets will be searched in the listed order for element classes.
For example, to allow access to the Default set, use:

  ParentSets Default

Note that you will still need to enumerate the C<TopLevels> available
in the parent sets to make them available.  This allows you to decide
which toplevel elements to inherit from the parent set.

=item C<TopLevels> (required)

Set this option to a list of top-level elements that should be made
available for Story creation.  These must be modules in the element
set, or in one of the inherited element sets.  For example, if you
specify in F<Flex/set.conf>:

  ParentSets Default
  TopLevels article cover category_archive author_archive category

Then either F<Flex/article.pm> or F<Default/article.pm> must exist
(and so on for each item in C<TopLevels>).

=back

=cut

use Krang::ClassLoader Conf => qw(InstanceElementSet KrangRoot);
use File::Spec::Functions qw(catdir catfile file_name_is_absolute);
use Config::ApacheFormat;
use Carp qw(croak);
use Krang::ClassLoader Log => qw(debug info);
use Krang::ClassLoader 'File';

# load all Krang::ElementClass base classes, which will be used by
# element sets
use Krang::ClassLoader 'ElementClass';
use Krang::ClassLoader 'ElementClass::TopLevel';
use Krang::ClassLoader 'ElementClass::Cover';
use Krang::ClassLoader 'ElementClass::CheckBox';
use Krang::ClassLoader 'ElementClass::ListBox';
use Krang::ClassLoader 'ElementClass::ListGroup';
use Krang::ClassLoader 'ElementClass::MediaLink';
use Krang::ClassLoader 'ElementClass::PopupMenu';
use Krang::ClassLoader 'ElementClass::RadioGroup';
use Krang::ClassLoader 'ElementClass::StoryLink';
use Krang::ClassLoader 'ElementClass::CategoryLink';
use Krang::ClassLoader 'ElementClass::Textarea';
use Krang::ClassLoader 'ElementClass::Text';
use Krang::ClassLoader 'ElementClass::Date';

=head1 INTERFACE

=over 4

=item Krang::ElementLibrary->load_set(set => $set_name)

Loads the element set with a given name.  Will die on error.  Returns
true on success.

=cut

sub load_set {
    my ($pkg, %arg) = @_;
    my ($set) = @arg{qw(set)};
    local $_;

    # don't load sets more than once
    our (%LOADED_SET, %PARENT_SETS);
    unless (exists $LOADED_SET{$set}) {
        my $conf = $pkg->_load_conf($set);

        # load parent sets first
        $PARENT_SETS{$set} = [ $conf->get('ParentSets') ];
        pkg('ElementLibrary')->load_set(set => $_) 
            for (@{$PARENT_SETS{$set}});

        $pkg->_load_classes($set, $conf);
        $pkg->_instantiate_top_levels($set, $conf);
        debug("Loaded element set '$set'");
    }

    $LOADED_SET{$set} = 1;
    return 1;
}

# load a set.conf file
sub _load_conf {
    my ($pkg, $set) = @_;

    my $dir = pkg('File')->find("element_lib/$set");
    unless (-d $dir) {
        warn("\nWARNING: Missing element library '$set'.\n\n");
        exit;
    }

    # load the element set configuration file
    my $conf_file = catfile($dir, "set.conf");
    my $conf = Config::ApacheFormat->new(
           valid_directives => [ qw(version krangversion toplevels
                                    parentsets )],
           valid_blocks     => []);
    eval { $conf->read($conf_file) };
    croak("Unable to load element set '$set', error loading $conf_file:\n$@")
      if $@;

    return $conf;
}


# load classes for an element set
sub _load_classes {
    my ($pkg, $set, $conf) = @_;

    my $dir = pkg('File')->find("element_lib/$set");
    unless (-d $dir) {
        warn("\nWARNING: Missing element library '$set'.\n\n");
        exit;
    }

    # setup @INC so element sets can load successfully
    unshift(@INC, "$dir/..");

    # make sure to reset @INC before returning
    eval {         
        # require all .pm files in main set
        opendir(DIR, $dir) or die "Unable to open dir '$dir': $!";
        my @file = sort readdir(DIR);
        closedir(DIR) or die $!;

        foreach my $file (@file) {
            next if $file =~ /#/; # skip emacs backup files
            next unless $file =~ /([^\/]+).pm$/;
            my $name = $1;
            eval "use ${set}::$name;";
            die "Unable to load element class $dir/$file.  Error was:\n\n$@\n"
              if $@;
        }
    };
    shift(@INC);
    die $@ if $@;
}

# load top-level element classes for stories and categories into
# global hashes
sub _instantiate_top_levels {
    my ($pkg, $set, $conf) = @_;
    our %TOP_LEVEL;

    my @tops = $conf->get("TopLevels");
    croak("No TopLevels defined for element set '$set'.")
      unless @tops;

    foreach my $top (@tops) {
        my $class_obj = $pkg->find_class(name => $top, set => $set);
        croak("Unable to find top-level element class '${set}::$top' while loading element set.")
          unless $class_obj;
        $TOP_LEVEL{$set}{$top} = $class_obj;
    }
}

=item C<< @toplevels = Krang::ElementLibrary->top_levels() >>

Returns a list of top-level class names supported by the configured
element set for the active instance.  Use the C<type> parameter to
select only story or category elements.  These names can be used in
calls to C<top_level()>.

Note that the top level element name 'category' is special.  You must
filter out this name to use the list for possible story types.

=cut

sub top_levels {
    our %TOP_LEVEL;
    return sort keys %{$TOP_LEVEL{InstanceElementSet()}};
}

=item C<< $class = Krang::ElementLibrary->top_level(name => "article") >>

Returns the class for a given type and name, as returned by
C<top_levels()>.  Will die if the given name is not a valid top-level
element.

=cut

sub top_level {
    my %args = @_[1..$#_];
    our %TOP_LEVEL;    
    return $TOP_LEVEL{InstanceElementSet()}{$args{name}}
      if exists $TOP_LEVEL{InstanceElementSet()}{$args{name}};
    croak("Unable to find top-level element named '$args{name}' in ".
          "element set '" . InstanceElementSet() . "'");
}

=item C<< @names = Krang::ElementLibrary->element_names() >>

Returns a list of element names in the current InstanceElementSet.  This list
is uniqued (since the same name may be used in different places in the
set) and sorted.

=cut

sub element_names {
    my $pkg = shift;
    our %TOP_LEVEL;
    
    # start with the top-levels, recursing down from there
    my @stack = values %{$TOP_LEVEL{InstanceElementSet()}};

    # build list of names in %names
    my %names;
    while(@stack) {
        my $node = pop(@stack);
        $names{$node->name} = 1;
        push(@stack, $node->children);
    }

    # sort and return
    return sort keys %names;
}


=item C<< $class = Krang::ElementLibrary->find_class(name => "deck") >>

=item C<< $class = Krang::ElementLibrary->find_class(name => "deck", set => "Flex") >>

Finds an element class by name, looking in the configured InstanceElementSet
for the current instance unless as set argument is passed.  If the
InstanceElementSet has ParentSets configured, will look there too.  Returns an
object descended from Krang::ElementClass or undef on failure.

This call only finds classes that are declared as separate packages,
not those declared inline.

For testing purposes, set $Krang::ElementLibrary::TESTING_SET and
find_class() will look there rather than the current InstanceElementSet.

=cut

sub find_class {
    my ($pkg, %args) = @_;
    our ($TESTING_SET, %PARENT_SETS);
    my ($name, $set) = @args{('name', 'set')};
    $set ||= ($TESTING_SET || InstanceElementSet);
 
    # look in current set
    my $class_pkg = "${set}::$name";
    return $class_pkg->new() if $class_pkg->can('new');

    # look through parent sets, recursing depth first
    my @parent_sets = @{$PARENT_SETS{$set}};
    while(@parent_sets) {
        $set       = shift @parent_sets;
        $class_pkg = "${set}::$name";

        # if foundm return it
        return $class_pkg->new() if $class_pkg->can('new');

        # otherwise, look deeper
        unshift(@parent_sets, @{$PARENT_SETS{$set}});
    }

    # failure
    return;
}

=back

=head1 TODO

Implement KrangVersion checking.

=cut

# load all configured element sets
BEGIN {
    my $cur_instance = pkg('Conf')->instance();
    foreach my $instance (pkg('Conf')->instances()) {
        pkg('Conf')->instance($instance);
        pkg('ElementLibrary')->load_set(set => InstanceElementSet());
    }
    pkg('Conf')->instance($cur_instance);
}

1;
