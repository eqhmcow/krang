package CanoeKayak::category;
use strict;
use warnings;
use base 'Krang::ElementClass::TopLevel';

use Krang::Log 'info';

my ($e1, $e2, $publisher);

sub new {
    my $pkg  = shift;
    my %args = ( name      => 'category',
                 children  => [

                ],
                @_);
    return $pkg->SUPER::new(%args);
}

sub fill_template {
    my ($self, %args) = @_;

    my $element = $args{element};
    $publisher = $args{publisher};
    my $category = $element->object;
    my $story = $publisher->story;
    my $tmpl = $args{tmpl};

    my $cdir = 'homepage';
    (my $cname = $category->dir) =~ s|^/(.+)$|ucfirst $1|e;

    my ($scdir, $scname, $sscdir, $sscname);
    if ($category->parent) {
        if ($category->parent->parent) {
            if ($category->parent->parent) {
                $cdir = $category->parent->parent->dir;
                ($cname = $cdir) =~ s|^/(.+)$|ucfirst $1|e;
                $scdir = $category->parent->dir;
                ($scname = $scdir) =~ s|^/(.+)$|ucfirst $1|e;
                $scdir = $category->dir;
                ($scname = $scdir) =~ s|^/(.+)$|ucfirst $1|e;
            } else {
                $cdir = $category->parent->dir;
                ($cname = $cdir) =~ s|^/(.+)$|ucfirst $1|e;
                $scdir = $category->dir;
                ($scname = $scdir) =~ s|^/(.+)$|ucfirst $1|e;
            }
        }
    }

     my $nav_html;
    my ($lnav_story) = Krang::Story->find(class => 'left_navigation');

    if ($lnav_story) {
        for ($lnav_story->element->children) {
            $nav_html .= $_->publish(publisher => $publisher)
              if ($_->name =~ /_level_link$/);
        }
    } else {
        # if there isn't a nav story do something here
        my ($root_cat) = Krang::Category->find(site_id =>
                                               $category->site->site_id,
                                               parent_id => undef);

        my $ln = Krang::Element->new(class => "left_navigation",
                                     object => $story);
        $e1 = $ln->add_child(class => 'top_level_link');
        $e2 = $ln->add_child(class => 'second_level_link');

        for ($root_cat->children) {
            $nav_html .= $self->_populate_links($_, 1);
        }
    }

    $tmpl->param(left_nav => $nav_html);
    $tmpl->param(cdir => $cdir);
    $tmpl->param(scdir => $scdir) if $sscdir;
    $tmpl->param(sscdir => $sscdir) if $sscdir;

    $tmpl->param(cname => $cname);
    $tmpl->param(scname => $scname) if $scname;
    $tmpl->param(sscname => $sscname) if $sscname;

    $self->SUPER::fill_template(%args);
}


sub _populate_links {
    my ($self, $cat, $one_or_two) = @_;
    my $e = $one_or_two == 1 ? $e1 : $e2;
    my $retval;

    (my $text = $cat->dir) =~ s#^/(.+)$#$1#;
    for my $kid($e->children) {
        if ($kid->name =~ /_text$/) {
            $kid->data(ucfirst $text);
        } else {
            $kid->data('http://' . $_->url);
        }
    }

    $retval = $e->publish(publisher => $publisher);

    if ($one_or_two == 1) {
        for ($cat->children) {
            $retval .= $self->_populate_links($_, 2);
        }
    }

    return $retval;
}


1;
