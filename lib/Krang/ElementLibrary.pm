package Krang::ElementLibrary;
use strict;
use warnings;

=head1 NAME

Krang::ElementLibrary - the element class loader and indexer

=head1 SYNOPSIS

  use Krang::ElementLibrary;

  # load an element set by name
  Krang::ElementLibary->load_set(set => "Flex");

  # get a list of available top level elements
  @top_levels = Krang::ElementLibary->top_levels());

  # get the object for the top level called "article" from the current set
  $class = Krang::ElementLibary->top_level(name => "article");

=head1 DESCRIPTION

This module is responsible for loading the Krang Element Library and
allowing access to the classes contained within it.  Each instance is
configured with an element set:

  <Instance test>
     ElementSet Flex
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
versions of Krnag.

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

use Krang::Conf qw(ElementSet ElementLibrary KrangRoot);
use File::Spec::Functions qw(catdir catfile file_name_is_absolute);
use Config::ApacheFormat;
use Carp qw(croak);
use Krang::Log qw(debug info);

# load all Krang::ElementClass base classes, which will be used by
# element sets
use Krang::ElementClass;
use Krang::ElementClass::CheckBox;
use Krang::ElementClass::ListBox;
use Krang::ElementClass::MediaLink;
use Krang::ElementClass::PopupMenu;
use Krang::ElementClass::RadioGroup;
use Krang::ElementClass::StoryLink;
use Krang::ElementClass::Textarea;
use Krang::ElementClass::Text;
use Krang::ElementClass::Date;

=head1 INTERFACE

=over 4

=item Krang::ElementLibrary->load_set(set => $set_name)

Loads the element set with a given name.  Will die on error.  Returns
true on success.

=cut

sub load_set {
    my ($pkg, %arg) = @_;
    my ($set) = @arg{qw(set)};

    # get location of the element library, mixing in KrangRoot if non-absolute
    my $lib = file_name_is_absolute(ElementLibrary) ?
                ElementLibrary :
                catdir(KrangRoot, ElementLibrary);

    # don't load sets more than once
    our %LOADED_SET;
    unless (exists $LOADED_SET{$set}) {
        my $conf = $pkg->_load_conf($lib, $set);
        # FIX: load parentsets
        $pkg->_load_classes($lib, $set, $conf);
        $pkg->_instantiate_top_levels($set, $conf);
        info("Loaded element set '$set'");
    } 

    $LOADED_SET{$set} = 1;
    return 1;
}

# load a set.conf file
sub _load_conf {
    my ($pkg, $lib, $set) = @_;

    croak("Unable to find element set '$set' in element library '$lib'")
      unless -d catdir($lib, $set);

    # load the element set configuration file
    my $conf_file = catfile($lib, $set, "set.conf");    
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
    my ($pkg, $lib, $set, $conf) = @_;
    my $dir = catdir($lib, $set);

    # require all .pm files
    opendir(DIR, $dir) or die "Unable to open dir '$dir': $!";
    while($_ = readdir(DIR)) {
        next unless /([^\/]+).pm$/;
        eval { require(catfile($dir, $_)); };
        die "Unable to load element class $dir/$_.  Error was:\n\n$@\n"
          if $@;
    }
    closedir(DIR) or die $!;
}

# load top-level element classes for stories and categories into
# global hashes
sub _instantiate_top_levels {
    my ($pkg, $set, $conf) = @_;
    our %TOP_LEVEL;

    my @tops = $conf->get("TopLevels");
    croak("No TopLevels defined for element set '$set'.")
      unless @tops;

    # FIX: look in ParentSets too
    foreach my $top (@tops) {
        my $class_pkg = "${set}::$top";
        croak("Unable to find element class '${set}::$top' while " .
              "loading element set.")
          unless $class_pkg->can('new');
        $TOP_LEVEL{$set}{$top} = $class_pkg->new(top_level => 1);        
    }

    # check that the set has the special category element class
    #croak("Missing required 'category' top-level in element set '$set'.")
    #  unless exists $TOP_LEVEL{category};

}

=item C<< @toplevels = Krang::ElementLibrary->top_levels() >>

Returns a list of top-level class names supported by the configured
element set for the active instance.  Use the C<type> parameter to
select only story or category elements.  These names can be used in
calls to C<top_level()>.

Note that the top level element name 'Category' is special.  You must
filter out this name to use the list for possible story types.

=cut

sub top_levels {
    our %TOP_LEVEL;
    return keys %{$TOP_LEVEL{ElementSet()}};
}

=item C<< $class = Krang::ElementLibrary->top_level(name => "article") >>

Returns the class for a given type and name, as returned by
C<top_levels()>.  Will die if the given name is not a valid top-level
element.

=cut

sub top_level {
    my %args = @_[1..$#_];
    our %TOP_LEVEL;    
    return $TOP_LEVEL{ElementSet()}{$args{name}}
      if exists $TOP_LEVEL{ElementSet()}{$args{name}};
    croak("Unable to find top-level element named '$args{name}' in ".
          "element set '" . ElementSet() . "'");
}

=item C<< $class = Krang::ElementLibrary->find_class(name => "deck") >>

Finds an element class by name, looking in the configured ElementSet
for the current instance.  If the ElementSet has ParentSets
configured, will look there too.  Returns an object descended from
Krang::ElementClass.

For testing purposes, set $Krang::ElementLibrary::TESTING_SET and
find_class() will look there rather than the current ElementSet.

=cut

sub find_class {
    my ($pkg, %arg) = @_;
    my ($name) = @arg{qw(name)};
    our $TESTING_SET;

    my $set = $TESTING_SET || ElementSet();
    my $class_pkg = "${set}::$name";
    return $class_pkg->new() if $class_pkg->can('new');
    croak("Unable to load element class named '$name' in set '$set'");
}


=back

=head1 TODO

=over

=item Implement ParentSets.

=back

=cut

1;
