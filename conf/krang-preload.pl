#!/usr/bin/perl -w

##########################################
####  MODULES TO PRE-LOAD INTO KRANG  ####
##########################################

use Krang::Conf qw(KrangRoot);
use File::Find qw(find);

# load all Krang libs, with a few exceptions
my $skip = qr/Profiler|Test|BricLoader|Cache|FTP|DataSet|Upgrade|MethodMaker|Daemon|Script|XML/;
find({ 
      wanted => sub {
          return unless m!(Krang/.*).pm$!;
          my $path = $1;
          return if /^\.?#/; # skip emacs droppings
          return if /$skip/;

          my $pkg = join('::', (split(/\//, $path)));
          eval "use $pkg;";
          die "Problem loading $pkg:\n\n$@" if $@;
      },
      no_chdir => 1
     },
     KrangRoot . '/lib/Krang');

# load all template
print STDERR "Pre-loading HTML Templates...\n";
find(
     sub {
         return if /^\.?#/; # skip emacs droppings
         return unless /\.tmpl$/;
         HTML::Template->new(
                             filename => "$File::Find::dir/$_",
                             cache => 1,
                             loop_context_vars => 1,
                            );
     },
     KrangRoot . '/templates');


print STDERR "Krang Pre-load complete.\n";

1;
