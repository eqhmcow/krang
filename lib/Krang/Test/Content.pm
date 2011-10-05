package Krang::Test::Content;

=head1 NAME

Krang::Test::Content - a package to simplify content handling in Krang tests.

=head1 SYNOPSIS

  use Krang::ClassLoader 'Test::Content';

  my $creator = pkg('Test::Content')->new();
  
  
  # create a Krang::Site object
  my $site = $creator->create_site(preview_url => 'preview.fluffydogs.com',
                                   publish_url => 'www.fluffydogs.com',
                                   preview_path => '/tmp/preview_dogs',
                                   publish_path => '/tmp/publish_dogs');
  
  my ($root) = pkg('Category')->find(site_id => $site->site_id);
  
  # create a Krang::Category object.
  my $poodle_cat = $creator->create_category(dir    => 'poodles',
                                             parent => $root->category_id,
                                             data   => 'Fluffy Poodles of the World');
  
  # create another Krang::Category object w/ $poodle_cat as parent.
  my $french_poodle_cat = $creator->create_category(dir    => 'french',
                                                    parent => $poodle_cat,
                                                    data   => 'French Poodles Uber Alles');
  
  # create a Krang::User user.
  my $user = $creator->create_user();
  
  # get the login username if you don't know it
  my $login = $user->login();
  # get the pw
  my $password = $user->password();
  
  # create a Krang::Media object.
  my $media = $creator->create_media(category => $poodle_cat);
  
  # create a Krang::Story object under various categories, with media object.
  my $story1 = $creator->create_story(category     => [$poodle_cat, $french_poodle_cat],
                                      linked_media => [$media]);
  
  # create Story object linking to media and previous story.
  my $story2 = $creator->create_story(category     => [$poodle_cat, $french_poodle_cat],
                                      linked_story => [$story1],
                                      linked_media => [$media]);
  
  # Where to find the published story on the filesystem
  my @paths = $creator->publish_paths(story => $story);
  
  # create a Krang::Contrib object
  my $contributor = $creator->create_contrib();
  
  # create a Krang::Template object for root element of story
  my $template = $creator->create_template(element => $story->element);
  
  # create a Krang::Template associated with a specific cat
  $template = $creator->create_template(element => $story->element, category => $poodle_cat);
  
  # get a Krang::Publisher object
  my $publisher = $creator->publisher();
  
  # create and deploy test templates
  my @templates = $creator->deploy_test_templates();
  
  # undeploy test templates
  $creator->undeploy_test_templates();
  
  
  # undeploy all live templates
  $ok = $creator->undeploy_live_templates();
  
  # restore previously live templates
  $ok = $creator->redeploy_live_templates();
  
  
  # get a random word (returns UTF-8 encoded words if Charset directive is set to utf-8)
  my $word = $creator->get_word();
  
  # get a random word exclusively composed of ascii letters a-z and A-Z
  my $ascii = $creator->get_word('ascii');
  
  # delete a previously created object
  $creator->delete_item(item => $story);
  
  # clean up after the mess you made.  Leave things where you found them.
  $creator->cleanup();


=head1 DESCRIPTION

Krang::Test::Content exists to simplify the process of writing tests for the more advanced subsystems of Krang.  Most test suites depend on content existing in the system to test against, and have been rolling their own content-creating routines.  This module exists to centralize a lot of that code in one place.  Additionally, it provides cleanup functionality, deleting everything that has been created using it.

This module is designed to work with the Default and TestSet1 element sets - it may or may not work with other element sets.

NOTE - It should be clear that this module assumes that the following modules are all in working order: L<Krang::Site>, L<Krang::Category>, L<Krang::Story>, L<Krang::Media>, L<Krang::Contrib>.

=cut

use Krang::ClassFactory qw(pkg);
use strict;
use warnings;
use Carp;

use Imager;    # creating images
use File::Spec::Functions;
use File::Path;

use Krang::ClassLoader Conf => qw(KrangRoot InstanceElementSet instance);
use Krang::ClassLoader 'Pref';
use Krang::ClassLoader 'Site';
use Krang::ClassLoader 'Category';
use Krang::ClassLoader 'Story';
use Krang::ClassLoader 'Media';
use Krang::ClassLoader 'User';
use Krang::ClassLoader 'Contrib';
use Krang::ClassLoader 'Publisher';
use Krang::ClassLoader 'Template';

use Krang::ClassLoader MethodMaker => (
    new_with_init => 'new',
    new_hash_init => 'hash_init'
);

use Krang::ClassLoader Log => qw(debug info critical);
use Krang::ClassLoader DB  => qw(dbh);

use Encode qw(encode_utf8 decode_utf8);

=head1 INTERFACE

=head2 METHODS

=over

=item C<< $creator = Krang::Test::Content->new() >>

Instantiates a Krang::Test::Content object.  No arguments are needed/supported at this time.

new() will croak with an error if the InstanceElementSet is not C<Default> or C<TestSet1>.  At this time, those are the only element sets supported.

=cut

sub init {

    my $self = shift;
    my %args = @_;

    $self->hash_init(%args);

    $self->_init_words();

    return;
}

=item C<< $site = $creator->create_site() >>

Creates and returns a L<Krang::Site object>.  If unsuccessful, it will croak.

B<Arguments:>

=over

=item preview_url

The url for the preview version of the site being created.

=item publish_url

The url for the publish version of the site being created.

=item preview_path

The filesystem path that correlates with the preview_url doc root.

=item publish_path

The filesystem path that correlates with the publish_url doc root.

=back

=cut

sub create_site {

    my $self = shift;
    my %args = @_;

    foreach (qw/preview_url publish_url preview_path publish_path/) {
        croak "create_site() missing required argument '$_'\n." unless exists($args{$_});
    }

    my $site = pkg('Site')->new(
        preview_url  => $args{preview_url},
        url          => $args{publish_url},
        preview_path => $args{preview_path},
        publish_path => $args{publish_path}
    );
    $site->save();

    push @{$self->{stack}{site}}, $site;

    return $site;
}

=item C<< $category = $creator->create_category() >>

Creates and returns a L<Krang::Category> object for the directory specified, underneath the parent category described by C<parent>.  It will croak if unable to create the object.

B<Arguments:>

=over

=item parent

The parent category for this category.  This must be an integer corresponding to the ID of a valid Krang::Category object, or a Krang::Category object.

If C<parent> is not set, it will default to the root category of the first L<Krang::Site> object created by C<create_site>.


=item dir

String containing the directory to be created.  Randomly generated by default.

=item data

Content to put in the root element of the category.  Randomly generated by default.

=back

=cut

sub create_category {

    my $self = shift;
    my %args = @_;

    my $parent;
    my $dir  = $args{dir}  || $self->get_word('ascii');
    my $data = $args{data} || $self->get_word();

    if ($args{parent}) {
        $parent = $args{parent};
    } else {
        $parent = $self->_root_category();
    }

    my $parent_id;

    ref($parent) ? ($parent_id = $parent->category_id()) : ($parent_id = $parent);

    my $category = pkg('Category')->new(dir => $dir, parent_id => $parent_id);

    $category->element()->data($data);
    $category->save();

    push @{$self->{stack}{category}}, $category;

    return $category;

}

=item C<< $user = $creator->create_user() >>

Creates and returns a L<Krang::User> object.

Accepts the standard arguments passed to Krang::User, or will function
with no arguments whatsoever, in which case it will only create the
username and password.

B<NOTE:> If a username is specified, L<create_user> will croak if user
creation fails because that username is already taken.  If no username
is specified, L<create_user> will try usernames until it finds one
that does not exist.

B<NOTE2:> If group_ids are not specified, L<create_user> will create a
user with admin-level access.

=cut

sub create_user {

    my $self = shift;
    my %args = @_;

    my $user;
    my $username = $args{login} || join('_', map { $self->get_word() } (0 .. 1));
    my $password = $args{password} || $self->get_word();
    my @group_ids;

    # find a group for this user.
    if ($args{group_ids}) {
        push @group_ids, @{$args{group_ids}};
    } else {

        # find admin groups
        my @groups = pkg('Group')->find(name_like => '%admin%');
        push @group_ids, map { $_->group_id } @groups;
    }

    while (1) {
        $user = pkg('User')->new(
            %args,
            login     => $username,
            password  => $password,
            group_ids => \@group_ids
        );
        eval { $user->save(); };

        # if an error was thrown, croak if user was specified.
        if ($@) {
            croak $@ if ($args{login});
            $username = join('_', map { $self->get_word() } (0 .. 1));
        } else {
            last;
        }

    }
    push @{$self->{stack}{user}}, $user;

    return $user;

}

=item C<< $media = $creator->create_media() >>

Creates and returns a Krang::Media object underneath the category specified.  It will croak if unable to create the object.

B<Arguments:>

=over

=item category

A single Krang::Category object, to which the Media object will belong.  If not specified, it will be assigned one randomly.

=item title

Title for the image.  Randomly generated by default.

=item filename

Image filename.  Randomly generated by default.

=item caption

Image caption.  Randomly generated by default.

=item x_size

An integer specifying how wide the image will be.  By default, the image will be between 50-350 pixels wide.

=item y_size

An integer specifying how tall the image will be.  By default, the image will be between 50-350 pixels tall.

=item format

Must be one of (I<jpg, png, gif>).  Determines the format of the image.  If not specified, it will randomly choose one of the three formats.

=item contribs

An array reference containing Krang::Contrib objects.  Each Contrib
object in the array will be associated with the new story.

=back

=cut

sub create_media {

    my $self = shift;
    my %args = @_;

    my $category = $args{category} || $self->_root_category();

    my $x       = $args{x_size}   || int(rand(300) + 50);
    my $y       = $args{y_size}   || int(rand(300) + 50);
    my $fmt     = $args{format}   || (qw(jpg png gif))[int(rand(3))];
    my $title   = $args{title}    || join(' ', map { $self->get_word() } (0 .. 5));
    my $fname   = $args{filename} || $self->get_word('ascii');
    my $caption = $args{caption}  || join(' ', map { $self->get_word() } (0 .. 5));

    my $img = Imager->new(
        xsize    => $x,
        ysize    => $y,
        channels => 3,
    );

    # fill with a random color
    $img->box(
        color  => Imager::Color->new(map { int(rand(255)) } 1 .. 3),
        filled => 1
    );

    # draw some boxes and circles
    for (0 .. (int(rand(8)) + 2)) {
        if ((int(rand(2))) == 1) {
            $img->box(
                color => Imager::Color->new(map { int(rand(255)) } 1 .. 3),
                xmin => (int(rand($x - ($x / 2))) + 1),
                ymin => (int(rand($y - ($y / 2))) + 1),
                xmax   => (int(rand($x * 2)) + 1),
                ymax   => (int(rand($y * 2)) + 1),
                filled => 1
            );
        } else {
            $img->circle(
                color => Imager::Color->new(map { int(rand(255)) } 1 .. 3),
                r     => (int(rand(100)) + 1),
                x     => (int(rand($x)) + 1),
                'y'   => (int(rand($y)) + 1)
            );
        }
    }

    $img->write(file => catfile(KrangRoot, "tmp", "tmp.$fmt"));
    my $fh = IO::File->new(catfile(KrangRoot, "tmp", "tmp.$fmt"))
      or die "Unable to open tmp/tmp.$fmt: $!";

    # Pick a type
    my %media_types    = pkg('Pref')->get('media_type');
    my @media_type_ids = keys(%media_types);
    my $media_type_id  = $media_type_ids[int(rand(scalar(@media_type_ids)))];

    # create a media object
    my $media = pkg('Media')->new(
        title         => $title,
        filename      => $fname . ".$fmt",
        caption       => $caption,
        filehandle    => $fh,
        category_id   => $category->category_id,
        media_type_id => $media_type_id,
    );

    # add contrib if it exists
    if ($args{contribs}) {
        $media->contribs(@{$args{contribs}});
    }

    $media->save;

    unlink(catfile(KrangRoot, "tmp", "tmp.$fmt"));

    $media->checkin();

    push @{$self->{stack}{media}}, $media;

    return $media;
}

=item C<< $story = $creator->create_story() >>

Creates and returns a Krang::Story object, underneath the categories specified.  It will croak if unable to create the object.  The story will already be saved & checked-in.

By default, the story will be a single page, with a title, deck, header, and three paragraphs.

B<Arguments:>

=over

=item class

The class of story (e.g. article, cover).  This determines the root
element of the story object being created.

If not specified, it will default to 'article', which may or may not
work, depending on the element library being used.


=item category

An array reference containing Krang::Category objects under which the
story will appear.

If not specified, one will be assigned randomly.

=item linked_stories

An array reference containing Krang::Story objects.  Each Story object
in the array will be linked to in the new story.

=item linked_media

An array reference containing Krang::Media objects.  Each Media object
in the array will be linked to in the new story.

=item contribs

An array reference containing Krang::Contrib objects.  Each Contrib
object in the array will be associated with the new story.

=item pages

Determines how many pages will exist in the story.  Each page will
contain a header and 3 paragraphs.  By Default, one page is created.

=item paras_per_page

Determines how many paragraphs will be created on each page.  Defaults
to 3.

=item C<< title => 'Confessions of a Poodle Lover' >>

The title for the story being created.  By default, a
randomly-generated title will be used.

=item C<< deck => 'Why fluffy dogs make me happy' >>

The deck for the story being created.  By default, a
randomly-generated deck will be used.

=item C<< header => 'In the beginning' >>

The first header in the story.  By default, a randomly-generated
header will be used.

This header only applies to the first page.  If more than one page is
being created in this story, subsuquent pages will have
randomly-generated headers.

=item C<< paragraph => [$p1, $p2, $p3, $p4] >>

The paragraph content for the paragraphs on the first page.  One
paragraph will be created for each element in the list reference
passed in.  By default, three randomly-generated paragraphs will be
created.

This only applies to the first page of a story - additional pages will
have three randomly-generated paragraphs each.

=back

=cut

sub create_story {

    my $self = shift;
    my %args = @_;

    my $categories;

    if ($args{category}) {
        $categories = $args{category};
        croak "'category' argument must be a list of pkg('Category') objects'\n"
          unless ref($categories) eq 'ARRAY';
    } else {
        $categories = [$self->_root_category()];
    }

    my $class = $args{class} || 'article',
      my $title = $args{title} || join(' ', map { $self->get_word() } (0 .. 5));
    my $deck = $args{deck}   || join(' ', map { $self->get_word() } (0 .. 5));
    my $head = $args{header} || join(' ', map { $self->get_word() } (0 .. 5));
    my $paras      = $args{paragraph}      || undef;
    my $paras_page = $args{paras_per_page} || 3;
    my $page_count = $args{pages}          || 1;

    my $slug_id;
    unless ($args{slug}) {
        do {
            $slug_id = int(rand(16777216));
        } until (!exists($self->{slug_id_list}{$slug_id}));
        $self->{slug_id_list}{$slug_id} = 1;
        $args{slug} = "TEST-SLUG-" . $slug_id;
    }

    my $story = pkg('Story')->new(
        categories => $categories,
        title      => $title,
        slug       => $args{slug},
        class      => $class
    );

    # add content - first page no matter what.
    $story->element->child('deck')->data($deck);

    $self->_fill_page(
        page           => $story->element->child('page'),
        header         => $head,
        paragraph      => $paras,
        paras_per_page => $paras_page
    );

    if ($page_count > 1) {
        for (2 .. $page_count) {
            $self->_fill_page(
                page           => $story->element->add_child(class => 'page'),
                paras_per_page => $paras_page
            );
        }
    }

    # add storylink if it exists
    if ($args{linked_stories}) {
        foreach (@{$args{linked_stories}}) {
            $self->_link_story($story, $_);
        }
    }

    # add medialink if it exists
    if ($args{linked_media}) {
        foreach (@{$args{linked_media}}) {
            $self->_link_media($story, $_);
        }
    }

    # add contrib if it exists
    if ($args{contribs}) {
        $story->contribs(@{$args{contribs}});
    }

    $story->save();

    $story->checkin();

    push @{$self->{stack}{story}}, $story;

    return $story;

}

=item C<< @paths = $creator->publish_paths(story => $story) >>

Returns a list of filesystem paths where the story will be published.

Takes either C<story> or C<media> arguments.

=cut

sub publish_paths {

    my $self = shift;
    my %args = @_;

    my @paths;

    croak __PACKAGE__ . "->story_paths(): missing argument 'story' or 'media'."
      unless (exists($args{story}) || exists($args{media}));

    if ($args{story}) {
        my $story = $args{story};

        for ($story->categories) {
            push @paths, catfile($story->publish_path(category => $_), 'index.html');
        }
    }

    elsif ($args{media}) {
        my $media = $args{media};

        push @paths, $media->publish_path();
    }

    return @paths;
}

=item C<< $contributor = $creator->create_contrib() >>

Creates and returns a Krang::Contrib object.  All the parameters that can be used in creating a Krang::Contrib object can be passed in here, or will be randomly generated.

B<Arguments:>

=over

=item prefix

=item first

=item middle

=item last

=item suffix

=item email

=item phone

=item bio

=item url

=back

=cut

sub create_contrib {

    my $self = shift;
    my %args = @_;

    my %c_args;

    foreach (qw/first middle last/) {
        $c_args{$_} = $args{$_} || $self->get_word();
    }

    $c_args{prefix} = $args{prefix} || 'Mr.';
    $c_args{suffix} = $args{suffix} || 'Jr.';
    $c_args{email}  = $args{email}
      || sprintf("%s\@%s.com", $self->get_word('ascii'), $self->get_word('ascii'));
    $c_args{bio} = $args{bio} || join(' ', map { $self->get_word() } (0 .. 20));
    $c_args{url} = $args{url} || sprintf("http://www.%s.com", $self->get_word('ascii'));
    $c_args{phone} = $args{phone}
      || sprintf("(%03i) %03i-%04i", int(rand(999)), int(rand(999)), int(rand(9999)));

    my %contrib_types = pkg('Pref')->get('contrib_type');

    my $contrib = pkg('Contrib')->new(%c_args);

    # add contrib types - let's make them all 3.
    $contrib->contrib_type_ids(keys %contrib_types);

    # select the first one - must be set when associating with a story
    $contrib->selected_contrib_type((values(%contrib_types))[0]);

    $contrib->save();

    push @{$self->{stack}{contrib}}, $contrib;

    return $contrib;

}

=item C<< $template = $creator->create_template() >>

Creates a valid HTML template and Krang::Template object based on a Krang::Element object.
When called in scalar mode, returns the template. When called in array mode, returns 
the template and the text content.

The following arguments are taken:

=over

=item * C<element>

A L<Krang::Element> element.  Unless the C<content> is also supplied,
the template constructed will be based on the makeup of C<$element>.

=item * C<element_name>

The name of the element the template is being constructed for.  If
this argument is used, C<content> must be supplied as well, as the
template cannot be generated automatically in this case.

=item * C<content>

The content of the template.  If not set, the template will be built
automatically, based on the makeup of the element and its children.

=item * C<category>

Associates the template with the L<Krang::Category> object
C<$category>.  Otherwise the template will be associated with the root
category for the first L<Krang::Site> object created.

=item * C<flattened>

This is an optional argument which defaults to 0: if set to 1, the template will
be created in a flattened form (i.e. rather than each container appearing in the 
form of <tmpl_var container>, it will appear as: 
<tmpl_if container><tmp_loop element_loop><tmpl_var child_1>etc.</tmpl_loop></tmpl_if>

=item * C<predictable>

This is an optional argument which defaults to 0: if set to 1, no random content 
will be included.

=back

=cut

sub create_template {

    my $self = shift;
    my %args = @_;

    my $element      = $args{element};
    my $element_name = $args{element_name} || $element->name;
    my $content      = $args{content};

    my $flattened = $args{flattened};

    croak __PACKAGE__
      . "->create_template(): Missing required argument(s) - either 'element' or 'element_name' and 'content'."
      unless ($element || ($element_name && $content));

    my $category;

    if (exists($args{category})) {
        $category = $args{category};
    } else {

        # use root cat for first site.
        $category = $self->_root_category();
    }

    unless ($content) {

        my $bgcolor =
          $args{predictable}
          ? 'ABCDEF'
          : "#" . join('', map { (3 .. 9, 'A' .. 'F')[int(rand(13))] } (1 .. 6));

        # draw a labeled box for the element
        my $display_name = $element->display_name;
        $content = <<END;
<div style='border: 1px solid black; margin-left: 3px; margin-top: 10px; margin-right: 5px; padding-left: 3px; padding-right: 3px; padding-bottom: 3px; background-color: $bgcolor'>
  <span style='border: 1px; border-style: dashed; border-color: #AAA; padding-left: 5px; padding-right: 5px; background-color: white; text-color: whte; top: -7px; left: 5px; position: relative; width: 150px;'>$display_name</span><br>
END

        if ($element->children) {

            # container
            $content .= $self->_element_to_loop($element, $flattened);
        } elsif ($element->isa('Krang::ElementClass::MediaLink')) {

            # media link
            $content .= "<img src='<tmpl_var name='url'>'>\n";
        } elsif ($element->isa('Krang::ElementClass::StoryLink')) {

            # story link
            $content .= "<a href='<tmpl_var name='url'>/'><tmpl_var url></a>\n";
        } else {

            # data
            $content .= "<tmpl_var name='" . $element->name . "'>\n";
        }
        if ($element->name eq 'category') {
            $content .= "<tmpl_var content>";
        }

        if ($element->name eq 'page') {

            # add pagination
            $content .= <<END;
<P>Page number <tmpl_var current_page_number> of <tmpl_var total_pages>.</p>
<tmpl_unless is_first_page>
<a href="<tmpl_var previous_page_url>">Previous Page</a>&lt;&lt;
</tmpl_unless>
<tmpl_loop pagination_loop>
<tmpl_if is_current_page>
<tmpl_var page_number>
<tmpl_else>
<a href="<tmpl_var page_url>"><tmpl_var page_number></a>
</tmpl_if>
<tmpl_unless __last__>&nbsp;|&nbsp;</tmpl_unless>
</tmpl_loop>
<tmpl_unless is_last_page>
&gt;&gt;<a href="<tmpl_var next_page_url>">Next Page</a>
</tmpl_unless>
<tmpl_unless is_last_page><tmpl_var page_break></tmpl_unless>
END

        }
        $content .= "</div>";
    }

    my $tmpl = pkg('Template')->new(
        content  => $content,
        filename => $element_name . ".tmpl",
        category => $category
    );
    $tmpl->save;

    # list of generated templates
    push @{$self->{stack}{template}}, $tmpl;

    $tmpl->checkin;

    return wantarray ? ($tmpl, $content) : $tmpl;

}

# helper function - builds element_loop text from element
sub _element_to_loop {
    my ($self, $element, $flattened) = @_;
    my %already_included;

    my $content .= "<tmpl_loop element_loop>\n";
    foreach my $child ($element->children) {
        next if $already_included{$child->name}++;
        $content .= "<tmpl_if is_" . $child->name . ">";
        $content .=
          ($flattened && $child->children)
          ? "\n" . $self->_element_to_loop($child, $flattened) . "\n"
          : "<tmpl_var name='" . $child->name . "'>";
        $content .= "</tmpl_if>\n";
    }
    $content .= "</tmpl_loop>";

    return $content;
}

=item C<< $publisher = $creator->publisher() >>

Returns a Krang::Publisher object.

=cut

sub publisher {

    my $self = shift;

    return ($self->{publisher}) if (exists($self->{publisher}));

    $self->{publisher} = new pkg('Publisher');

    return $self->{publisher};

}

=item C<< @templates = $creator->deploy_test_templates() >>

Creates a set of Krang::Template templates based on the elements in TestSet1 (looking at Krang::ElementLibrary).  These templates will be generated randomly, so you cannot run tests based on the content of the templates.  These templates should be used when you need to publish Krang::Story objects generated above.

This method will check to see if L<undeploy_live_templates()> has been run beforehand.

If not, it will run it first as a safety measure, so as to not clobber live templates, or to cause random errors.

Will croak if there are problems.

Returns a list of Krang::Template templates.

=cut

sub deploy_test_templates {

    my $self = shift;
    my %args = @_;

    my @template_list;

    my $publisher = (exists($self->{publisher})) ? $self->{publisher} : $self->publisher();

    # make sure live templates have been undeployed
    $self->undeploy_live_templates() unless (exists($self->{live_templates}));

    # all templates go in root cat for first site found.
    my $site = $self->{stack}{site}[0];

    croak __PACKAGE__ . "->deploy_test_templates(): Must create site before deploying templates!\n"
      unless defined($site);

    my ($category) = pkg('Category')->find(site_id => $site->site_id, dir => '/');

    croak __PACKAGE__ . "->deploy_test_templates(): Must create site before deploying templates!\n"
      unless defined($site);

    my @estack =
      map { pkg('ElementLibrary')->top_level(name => $_) } pkg('ElementLibrary')->top_levels;
    while (@estack) {
        my $element = pop(@estack);
        push(@estack, $element->children);

        my $tmpl;

        # make sure not to create another test template if one already exists
        # for the root category.
        foreach my $t (@{$self->{stack}{template}}) {
            if (($t->filename eq $element->name() . '.tmpl')
                && $t->category_id == $category->category_id)
            {
                $tmpl = $t;
                last;
            }
        }

        $tmpl = $self->create_template(element => $element) unless ($tmpl);

        $publisher->deploy_template(template => $tmpl);

        push @template_list, $tmpl;
    }

    return @template_list;

}

=item C<< $creator->undeploy_test_templates() >>

Removes the test templates placed out on the filesystem.

=cut

sub undeploy_test_templates {

    my $self = shift;

    my $publisher = (exists($self->{publisher})) ? $self->{publisher} : $self->publisher();

    foreach my $tmpl (@{$self->{stack}{template}}) {
        $publisher->undeploy_template(template => $tmpl);
    }
}

=item C<< @templates = $creator->undeploy_live_templates() >>

A preventative measure to make sure that live templates don't cause problems, or are otherwise clobbered by test templates.

Searches the template root for potentially problematic templates, and undeploys them.

=cut

sub undeploy_live_templates {

    my $self = shift;

    my $publisher = $self->publisher();

    my @live_templates = pkg('Template')->find(deployed => 1);

    foreach my $t (@live_templates) {
        $publisher->undeploy_template(template => $t);
        push @{$self->{live_templates}}, $t;
    }

    return @live_templates;

}

=item C<< $creator->redeploy_live_templates() >>

Redeploys any live templates that were taken down previously.

=cut

sub redeploy_live_templates {

    my $self = shift;

    my $publisher = $self->publisher();

    return unless (defined($self->{live_templates}));

    while (my $t = pop @{$self->{live_templates}}) {
        $publisher->deploy_template(template => $t);
    }

}

=item C<< $word = get_word() >>

=item C<< $word = get_word('ascii') >>

This subroutine creates all the random text content for the module -
each call returns a randomly-chosen word from the source - either
F<t/dict/words.latin1> or <t/dict/words.ascii>.

Depending on the Charset directive in F<conf/krang.conf> those words
are utf-8 encoded or not.

=cut

sub get_word {
    my ($self, $type) = @_;

    croak "Unknown option for get_word()"
      if $type && $type ne "ascii";

    my $slot = $type && $type eq 'ascii' ? 'ascii_words' : 'high_char_words';

    return lc $self->{$slot}[int(rand(scalar(@{$self->{$slot}})))];
}

=item C<< $creator->delete_item(item => $krang_object) >>

Attempts to delete the item created.

Any errors thrown by the item itself will not be trapped - they will be passed on to the caller.

If the delete is unsuccessful, it will leave a critical message in the log file and croak.

=cut

sub delete_item {

    my $self = shift;
    my %args = @_;

    my $item = $args{item} || return;

    my @front;

    # remove item from the stack
    if ($item->isa('Krang::Site')) {
        while (my $site = shift @{$self->{stack}{site}}) {
            if ($site->site_id == $item->site_id) {
                last;
            }
            push @front, $site;
        }

        # attempt to delete
        eval { $item->delete(); };
        if (my $e = $@) {

            # put it back on the stack & throw the error.
            unshift @{$self->{stack}{site}}, @front, $item;
            croak($e);
        }
        unshift @{$self->{stack}{site}}, @front;

    } elsif ($item->isa('Krang::Category')) {
        while (my $cat = shift @{$self->{stack}{category}}) {
            if ($cat->category_id == $item->category_id) {
                last;
            }
            push @front, $cat;
        }

        # attempt to delete
        eval { $item->delete(); };
        if (my $e = $@) {

            # put it back on the stack & throw the error.
            unshift @{$self->{stack}{category}}, @front, $item;
            croak($e);
        }
        unshift @{$self->{stack}{category}}, @front;

    } elsif ($item->isa('Krang::Media')) {
        while (my $media = shift @{$self->{stack}{media}}) {
            if ($media->media_id == $item->media_id) {
                last;
            }
            push @front, $media;
        }

        # attempt to delete
        eval { $item->delete(); };
        if (my $e = $@) {

            # put it back on the stack & throw the error.
            unshift @{$self->{stack}{media}}, @front, $item;
            croak($e);
        }
        unshift @{$self->{stack}{media}}, @front;

    } elsif ($item->isa('Krang::Story')) {
        while (my $story = shift @{$self->{stack}{story}}) {
            if ($story->story_id == $item->story_id) {
                last;
            }
            push @front, $story;
        }

        # attempt to delete
        eval { $item->delete(); };
        if (my $e = $@) {

            # put it back on the stack & throw the error.
            unshift @{$self->{stack}{story}}, @front, $item;
            croak($e);
        }
        unshift @{$self->{stack}{story}}, @front;

    } elsif ($item->isa('Krang::Contrib')) {
        while (my $contrib = shift @{$self->{stack}{contrib}}) {
            if ($contrib->contrib_id == $item->contrib_id) {
                last;
            }
            push @front, $contrib;
        }

        # attempt to delete
        eval { $item->delete(); };
        if (my $e = $@) {

            # put it back on the stack & throw the error.
            unshift @{$self->{stack}{contrib}}, @front, $item;
            croak($e);
        }
        unshift @{$self->{stack}{contrib}}, @front;

    } elsif ($item->isa('Krang::Template')) {
        while (my $tmpl = shift @{$self->{stack}{template}}) {
            if ($tmpl->template_id == $item->template_id) {
                last;
            }
            push @front, $tmpl;
        }

        # attempt to delete
        eval { $item->delete(); };
        if (my $e = $@) {

            # put it back on the stack & throw the error.
            unshift @{$self->{stack}{template}}, @front, $item;
            croak($e);
        }
        unshift @{$self->{stack}{template}}, @front;

    }

    return;

}

=item C<< $creator->cleanup() >>

Attempts to delete everything that has been created by the Krang::Test::Content object.  A stack of everything created by the object is maintained internally, and that stack is used to determine the order in which content is destroyed (e.g. Last Hired, First Fired).

Will log a critical error message and croak if unsuccessful.

=cut

sub cleanup {
    my $self = shift;

    delete $self->{publisher} if (exists($self->{publisher}));

    foreach (qw/user contrib media story template category site/) {
        if (exists($self->{stack}{$_})) {
            while (my $obj = pop @{$self->{stack}{$_}}) {

                # user's need to delete any old_password entries related to them
                if ($_ eq 'user') {
                    dbh()->do('DELETE FROM old_password WHERE user_id = ?', {}, $obj->user_id);
                }

                debug(__PACKAGE__ . '->cleanup() deleting object: ' . ref($obj));
                $obj->delete();
            }
        }
    }

    # make sure live templates are in their place.
    $self->redeploy_live_templates();

}

=back

=head1 BUGS

Krang::Test::Content will only work against the ElementSet TestSet1.  Any other Element Sets will cause unpredictable behavior.


=head1 TODO

Flesh out the various create_ methods to support more of the test code in Krang.  Ideally, this module would also support bin/krang_floodfill, so that all test suites and dummy data are coming from the same source.

=head1 SEE ALSO

L<Krang::Category>, L<Krang::Story>, L<Krang::Media>, L<Krang::Contrib>

=cut

#
# Returns the root category for one of the Krang::Site objects created by create_site().
# If no Krang::Site objects have been created, it will croak.
#
sub _root_category {

    my $self = shift;
    my $root;

    my $site = $self->{stack}{site}[0];
    croak __PACKAGE__ . "->_root_category(): Must create site before creating categories!"
      unless defined($site);

    # set parent to root category of first site created.
    ($root) = pkg('Category')->find(site_id => $site->site_id, dir => '/');

    return $root;

}

#
# inits the words file.
#
sub _init_words {

    my $self = shift;

    for my $f (['words.ascii', 'ascii_words'], ['words.latin1', 'high_char_words'],) {
        my $dict = catfile(KrangRoot, 't', 'dict', $f->[0]);

        open(WORDS, $dict)
          or croak "Couldn't open '$dict' for reading: $!";

        while (<WORDS>) {
            chomp;
            $_ = decode_utf8(encode_utf8($_)) if pkg('Charset')->is_utf8;
            push @{$self->{$f->[1]}}, $_;
        }

        close WORDS;
    }
}

# create a storylink in $story to $dest
sub _link_story {

    my $self = shift;

    my ($story, $dest) = @_;

    my $page = $story->element->child('page');

    $page->add_child(class => "leadin", data => $dest);

}

# create a medialink in $story to $media.
sub _link_media {

    my $self = shift;

    my ($story, $media) = @_;

    my $page = $story->element->child('page');

    $page->add_child(class => "photo", data => $media);

}

#
# Fill a Krang::Story page element with content.
# Takes the following arguments, or builds random equivilants.
#
# page - page element to be filled.
# header - header text
# paragraph - array ref of paras.  Will build 3 otherwise.
#
sub _fill_page {

    my $self = shift;
    my %args = @_;

    my $page       = $args{page};
    my $head       = $args{header} || join(' ', map { $self->get_word() } (0 .. 5));
    my $para       = $args{paragraph};
    my $paras_page = $args{paras_per_page} || 3;

    $page->child('header')->data($head);
    $page->child('wide_page')->data(1);

    if (defined($para)) {
        foreach (@$para) {
            $page->add_child(class => "paragraph", data => $_);
        }
    } else {
        for (1 .. $paras_page) {
            my $paragraph = join(' ', map { $self->get_word() } (0 .. 20));
            $page->add_child(class => "paragraph", data => $paragraph);
        }
    }

}

1;
