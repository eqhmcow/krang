package Krang::ConfigApacheFormat;
use Krang::ClassFactory qw(pkg);
use warnings;
use strict;

use base 'Config::ApacheFormat';
use Text::Balanced qw(extract_delimited extract_variable);
use Scalar::Util qw(weaken);
use Carp qw(croak);

use Krang::ClassLoader 'IO';

=head1 NAME

Krang::ConfigApacheFormat - Config::ApacheFormat wrapper for Krang

=head1 SYNOPSIS

See L<Config::ApacheFormat>

=head1 DESCRIPTION

This module provides the same functionality as Config::ApacheFormat,
but allows directives to be double quoted strings.

Configuration files must be encoded according to the Charset directive
in C<conf/krang.conf>

=head1 INTERFACE

See L<Config::ApacheFormat>

=cut

# read the configuration file, optionally ending at block_name
sub read {
    my ($self, $file) = @_;

    my @fstack;

    # open the file if needed and setup file stack
    my $fh;
    if (ref $file) {
        @fstack = {
            fh       => $file,
            filename => "",
            line_num => 0
        };
    } else {
        $fh = pkg('IO')->io_file($file) or croak("Unable to open file '$file': $!");
        @fstack = {
            fh       => $fh,
            filename => $file,
            line_num => 0
        };
    }

    return $self->_read(\@fstack);
}

# underlying _read, called recursively an block name for
# nested block objects
sub _read {
    my ($self, $fstack, $block_name) = @_;

    # pre-fetch for loop
    my $case_sensitive = $self->{case_sensitive};
    my $data           = $self->{_data};

    # pre-compute lookups for validation lists, if they exists
    my ($validate_blocks, %valid_blocks, $validate_directives, %valid_directives);
    if ($self->{valid_directives}) {
        %valid_directives = map { ($case_sensitive ? $_ : lc($_)), 1 } @{$self->{valid_directives}};
        $validate_directives = 1;
    }
    if ($self->{valid_blocks}) {
        %valid_blocks = map { ($case_sensitive ? $_ : lc($_)), 1 } @{$self->{valid_blocks}};
        $validate_blocks = 1;
    }

    # pre-compute a regex to recognize the include directives
    my $re = '^(?:' . join('|', @{$self->{include_directives}}) . ')$';
    my $include_re;
    if ($self->{case_sensitive}) {
        $include_re = qr/$re/;
    } else {
        $include_re = qr/$re/i;
    }

    # parse through the file, line by line
    my ($name, $values, $line, $orig);
    my ($fh, $filename) = @{$fstack->[-1]}{qw(fh filename)};
    my $line_num = \$fstack->[-1]{line_num};

  LINE:
    while (1) {

        # done with current file?
        if (eof $fh) {
            last LINE if @$fstack == 1;
            pop @$fstack;
            ($fh, $filename) = @{$fstack->[-1]}{qw(fh filename)};
            $line_num = \$fstack->[-1]{line_num};
        }

        # accumulate a full line, dealing with line-continuation
        $line = "";
        do {
            no warnings 'uninitialized';    # blank warnings
            $_ = <$fh>;
            ${$line_num}++;
            s/^\s+//;                       # strip leading space
            next LINE if /^#/;              # skip comments
            s/\s+$//;                       # strip trailing space
            $line .= $_;
        } while ($line =~ s/\\$// and not eof($fh));

        # skip blank lines
        next LINE unless length $line;

        # parse line
        if ($line =~ /^<\/(\w+)>$/) {

            # end block
            $orig = $name = $1;
            $name = lc $name unless $case_sensitive;    # lc($1) breaks on 5.6.1!

            croak(  "Error in config file $filename, line $$line_num: "
                  . "Unexpected end to block '$orig' found"
                  . (defined $block_name ? "\nI was waiting for </$block_name>\n" : ""))
              unless defined $block_name and $block_name eq $name;

            # this is our cue to return
            last LINE;

        } elsif ($line =~ /^<(\w+)\s*(.*)>$/) {

            # open block
            $orig = $name = $1;
            $values = $2;
            $name = lc $name unless $case_sensitive;

            croak(  "Error in config file $filename, line $$line_num: "
                  . "block '<$orig>' is not a valid block name")
              unless not $validate_blocks
                  or exists $valid_blocks{$name};

            my $val = [];
            $val = _parse_value_list($values) if $values;

            # create new object for block, inheriting options from
            # this object, with this object set as parent (using
            # weaken() to avoid creating a circular reference that
            # would leak memory)
            my $parent = $self;
            weaken($parent);
            my $block = ref($self)->new(
                inheritance_support  => $self->{inheritance_support},
                include_support      => $self->{include_support},
                autoload_support     => $self->{autoload_support},
                case_sensitive       => $case_sensitive,
                expand_vars          => $self->{expand_vars},
                setenv_vars          => $self->{setenv_vars},
                valid_directives     => $self->{valid_directives},
                valid_blocks         => $self->{valid_blocks},
                duplicate_directives => $self->{duplicate_directives},
                hash_directives      => $self->{hash_directives},
                fix_booleans         => $self->{fix_booleans},
                root_directive       => $self->{root_directive},
                include_directives   => $self->{include_directives},
                _parent              => $parent,
                _block_vals          => ref $val ? $val : [$val],
            );

            # tell the block to read from $fh up to the closing tag
            # for this block
            $block->_read($fstack, $name);

            # store block for get() and block()
            push @{$data->{$name}}, $block;

            # allow quoted strings
        } elsif ($line =~ /^(\w+|"[^"]+")(?:\s+(.+))?$/) {    #"

            # apache directive
            $orig   = $1;
            $values = $2;
            $orig =~ s|^"||;                                  #"
            $orig =~ s|"$||;                                  #"
            $name   = $orig;
            $values = 1 unless defined $values;
            $name   = lc $name unless $case_sensitive;

            croak(  "Error in config file $filename, line $$line_num: "
                  . "directive '$name' is not a valid directive name")
              unless not $validate_directives
                  or exists $valid_directives{$name};

            # parse out values, handling any strings or arrays
            my @val;
            eval { @val = _parse_value_list($values); };
            croak("Error in config file $filename, line $$line_num: $@")
              if $@;

            # expand_vars if set
            eval { @val = $self->_expand_vars(@val) if $self->{expand_vars}; };
            croak("Error in config file $filename, line $$line_num: $@")
              if $@;

            # and then setenv too (allowing PATH "$BASEDIR/bin")
            if ($self->{setenv_vars}) {
                if ($name =~ /^setenv$/i) {
                    croak(  "Error in config file $filename, line $$line_num: "
                          . " can't use setenv_vars "
                          . "with malformed SetEnv directive")
                      if @val != 2;
                    $ENV{"$val[0]"} = $val[1];
                } elsif ($name =~ /^unsetenv$/i) {
                    croak(  "Error in config file $filename, line $$line_num: "
                          . "can't use setenv_vars "
                          . "with malformed UnsetEnv directive")
                      unless @val;
                    delete $ENV{$_} for @val;
                }
            }

            # Include processing
            # because of the way our inheritance works, we navigate multiple files in reverse
            if ($name =~ /$include_re/) {
                for my $f (reverse @val) {

                    # if they specified a root_directive (ServerRoot) and
                    # it is defined, prefix that to relative paths
                    my $root =
                        $self->{case_sensitive}
                      ? $self->{root_directive}
                      : lc $self->{root_directive};
                    if (!File::Spec->file_name_is_absolute($f) && exists $data->{$root}) {

                        # looks odd; but only reliable method is construct UNIX-style
                        # then deconstruct
                        my @parts = File::Spec->splitpath("$data->{$root}[0]/$f");
                        $f = File::Spec->catpath(@parts);
                    }

                    # this handles directory includes (i.e. will include all files in a directory)
                    my @files;
                    if (-d $f) {
                        opendir(INCD, $f)
                          || croak("Cannot open include directory '$f' at $filename ",
                            "line $$line_num: $!");
                        @files = map { "$f/$_" } sort grep { -f "$f/$_" } readdir INCD;
                        closedir(INCD);
                    } else {
                        @files = $f;
                    }

                    for my $values (reverse @files) {

                        # just try to open it as-is
                        my $include_fh;
                        unless (open($include_fh, "<", $values)) {
                            if ($fstack->[0]{filename}) {

                                # try opening it relative to the enclosing file
                                # using File::Spec
                                my @parts = File::Spec->splitpath($filename);
                                $parts[-1] = $values;
                                open($include_fh, "<", File::Spec->catpath(@parts))
                                  or croak(
                                    "Unable to open include file '$values' ",
                                    "at $filename line $$line_num: $!"
                                  );
                            } else {
                                croak(
                                    "Unable to open include file '$values' ",
                                    "at $filename line $$line_num: $!"
                                );
                            }
                        }

                        # push a new record onto the @fstack for this file
                        push(
                            @$fstack,
                            {
                                fh       => $fh       = $include_fh,
                                filename => $filename = $values,
                                line_number => 0
                            }
                        );

                        # hook up line counter
                        $line_num = \$fstack->[-1]{line_num};
                    }
                }
                next LINE;
            }

            # for each @val, "fix" booleans if so requested
            # do this *after* include processing so "include yes.conf" works
            if ($self->{fix_booleans}) {
                for (@val) {
                    if (/^true$/i or /^on$/i or /^yes$/i) {
                        $_ = 1;
                    } elsif (/^false$/i or /^off$/i or /^no$/i) {
                        $_ = 0;
                    }
                }
            }

            # how to handle repeated values
            # this is complicated because we have to allow a semi-union of
            # the hash_directives and duplicate_directives options

            if ($self->{hash_directives}
                && _member($orig, $self->{hash_directives}, $self->{case_sensitive}))
            {
                my $k = shift @val;
                if ($self->{duplicate_directives} eq 'error') {

                    # must check for a *specific* dup
                    croak "Duplicate directive '$orig $k' at $filename line $$line_num"
                      if $data->{$name}{$k};
                    push @{$data->{$name}{$k}}, @val;
                } elsif ($self->{duplicate_directives} eq 'last') {
                    $data->{$name}{$k} = \@val;
                } else {

                    # push onto our struct to allow repeated declarations
                    push @{$data->{$name}{$k}}, @val;
                }
            } else {
                if ($self->{duplicate_directives} eq 'error') {

                    # not a hash_directive, so all dups are errors
                    croak "Duplicate directive '$orig' at $filename line $$line_num"
                      if $data->{$name};
                    push @{$data->{$name}}, @val;
                } elsif ($self->{duplicate_directives} eq 'last') {
                    $data->{$name} = \@val;
                } else {

                    # push onto our struct to allow repeated declarations
                    push @{$data->{$name}}, @val;
                }
            }

        } else {
            croak("Error in config file $filename, line $$line_num: " . "unable to parse line");
        }
    }

    return $self;
}

# given a string returns a list of tokens, allowing for quoted strings
# and otherwise splitting on whitespace
sub _parse_value_list {
    my $values = shift;

    my @val;
    if ($values !~ /['"\s]/) {

        # handle the common case of a single unquoted string
        @val = ($values);
    } elsif ($values !~ /['"]/) {

        # strings without any quote characters can be parsed with split
        @val = split /\s+/, $values;
    } else {

        # break apart line, allowing for quoted strings with
        # escaping
        while ($values) {
            my $val;
            if ($values !~ /^["']/) {

                # strip off a value and put it where it belongs
                ($val, $values) = $values =~ /^(\S+)\s*(.*)$/;
            } else {

                # starts with a quote, bring in the big guns
                $val = extract_delimited($values, q{"'});
                die "value string '$values' not properly formatted\n"
                  unless length $val;

                # remove quotes and fixup escaped characters
                $val = substr($val, 1, length($val) - 2);
                $val =~ s/\\(['"])/$1/g;

                # strip off any leftover space
                $values =~ s/^\s*//;
            }
            push(@val, $val);
        }
    }
    die "no value found for directive\n" unless @val;

    return wantarray ? @val : \@val;
}

# get a value from the config file.
*directive = \&get;

sub get {
    my ($self, $name, $srch) = @_;

    # handle empty param call
    return keys %{$self->{_data}} if @_ == 1;

    # lookup name in _data
    $name = lc $name unless $self->{case_sensitive};
    my $val = $self->{_data}{$name};

    # Search through up the tree if inheritence is on and we have a
    # parent.  Simulated recursion terminates either when $val is
    # found or when the root is reached and _parent is undef.
    if (    not defined $val
        and $self->{_parent}
        and $self->{inheritance_support})
    {
        my $ptr = $self;
        do {
            $ptr = $ptr->{_parent};
            $val = $ptr->{_data}{$name};
        } while (not defined $val and $ptr->{_parent});
    }

    # didn't find it?
    return unless defined $val;

    # for blocks, return a list of valid block identifiers
    my $type = ref $val;
    my @ret;    # tmp to avoid screwing up $val
    if ($type) {
        if ($type eq 'ARRAY'
            and ref($val->[0]) eq ref($self))
        {
            @ret = map { [$name, @{$_->{_block_vals}}] } @$val;
            $val = \@ret;
        } elsif ($type eq 'HASH') {

            # hash_directive
            if ($srch) {

                # return the specific one
                $val = $val->{$srch};
            } else {

                # return valid keys
                $val = [keys %$val];
            }

        }
    }

    # return all vals in list ctxt, or just the first in scalar
    return wantarray ? @$val : $val->[0];
}

1;
