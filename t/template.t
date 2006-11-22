use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Krang::ClassLoader 'Script';
use Krang::ClassLoader 'Category';
use Krang::ClassLoader 'Site';
use Krang::ClassLoader 'Group';

use Data::Dumper;
use Test::More qw(no_plan);


BEGIN {use_ok(pkg('Template'));}

# set up site and category
my $site = pkg('Site')->new(preview_path => './sites/test1/preview/',
                            preview_url => 'preview.testsite1.com',
                            publish_path => './sites/test1/',
                            url => 'testsite1.com');
$site->save();
isa_ok($site, 'Krang::Site');

my ($category) = pkg('Category')->find(site_id => $site->site_id());

# constructor failure
my $tmpl;
eval {$tmpl = pkg('Template')->new(category => 'blah',
                                   content => 'blah',
                                   filename => 'A.tmpl')};
like($@, qr/'category' argument must be a 'Krang::Category'/s,
     'constructor failure');

# constructor success 1 - tests category arg
eval {$tmpl = pkg('Template')->new(category => $category,
                                   content => '<blink><tmpl_var bob></blink>',
                                   filename => 'bob.tmpl')};
is($@, '', 'contructor good :)');

# constructor success 2
$tmpl = pkg('Template')->new(category_id => $category->category_id(),
                             content => '<blink><tmpl_var bob></blink>',
                             filename => 'bob.tmpl');
isa_ok($tmpl, 'Krang::Template');
isa_ok($tmpl->creation_date, 'Time::Piece');
ok($tmpl->template_uuid);

# make sure our id_meth and uuid_meth are correct
my $method = $tmpl->id_meth;
is($tmpl->$method, $tmpl->template_id, 'id_meth() is correct');
$method = $tmpl->uuid_meth;
is($tmpl->$method, $tmpl->template_uuid, 'uuid_meth() is correct');

# test category meth
my $cat = $tmpl->category;
is($cat->dir, $category->dir, 'category() method test');

# increment version
$tmpl->save();
is($tmpl->version(), 1, 'Version Check');

# duplicate check
eval {
    my $tmplX = pkg('Template')->new(category_id => $category->category_id(),
                                     filename => 'bob.tmpl');
    $tmplX->save();
};
is($@ =~ /Duplicate URL/, 1, 'duplicate_check()');

# save description for revert test
my $content = $tmpl->content();

# check Krang::MethodMaker meth...
$tmpl->content('<tmpl_var content>');
my $content2 = $tmpl->content();
is($content2, '<tmpl_var content>', 'Getter/Setter Test');

# increment version
$tmpl->save();
is($tmpl->version(), 2, 'Version Check 2');

# revert check
$tmpl->revert(1);
is($tmpl->content(), $content, 'Revert Test');

# increment version
$tmpl->save();
is($tmpl->version(), 3, 'Version Check 3');

# verify checkin works
$tmpl->checkin();
is($tmpl->checked_out, 0, 'Checkin Test');

# verify save fails on a checked-in object
eval{$tmpl->save()};
like($@, qr/Template isn't checked out/i, 'verify_checkout() Test');

# verify checkout works
is($tmpl->checkout()->isa('Krang::Template'), 1, 'Checkout Test');

my $tmpl2 = pkg('Template')->new(category_id => $category->category_id(),
                                 content => '<html></html>',
                                 filename => 't_w_c.tmpl');

$tmpl2->save();


# test mark_as_deployed
eval { $tmpl2->mark_as_deployed(); };
if ($@) {
    diag($@);
    fail('Krang::Template->mark_as_deployed()');
} else {
    pass('Krang::Template->mark_as_deployed()');
    ok($tmpl2->deployed(), 'Krang::Template->mark_as_deployed()');
    ok($tmpl2->deployed_version() eq $tmpl2->version(), 'Krang::Template->mark_as_deployed()');
    ok($tmpl2->testing() eq 0, 'Krang::Template->mark_as_deployed()');
}

# test mark_as_undeployed
eval { $tmpl2->mark_as_undeployed(); };
if ($@) {
    diag($@);
    fail('Krang::Template->mark_as_undeployed()');
} else {
    pass('Krang::Template->mark_as_undeployed()');
    ok($tmpl2->deployed() == 0, 'Krang::Template->mark_as_undeployed()');
    ok(!defined($tmpl2->deployed_version()), 'Krang::Template->mark_as_undeployed()');
    ok(!defined($tmpl2->deploy_date()), 'Krang::Template->mark_as_undeployed()');
}


# test mark_for_testing and unmark_for_testing
is($tmpl2->testing, 0);
ok($tmpl2->mark_for_testing);
is($tmpl2->testing(), 1);
ok($tmpl2->unmark_for_testing);
is($tmpl2->testing, 0);


# find() tests
###############
# make sure find() croaks
eval {pkg('Template')->find(count => 1, ids_only => 1)};
is($@ =~ /Only one/, 1, 'Find Failure 1');

eval {pkg('Template')->find(XXX => 69)};
is($@ =~ /invalid/, 1, 'Find Failure 2');

my ($tmpl3) = pkg('Template')->find(filename_like => '%bob%');
is(ref $tmpl3, 'Krang::Template', "Find - _like 1");

my @ids = ($tmpl->template_id(), $tmpl2->template_id());

my $i = 1;
my @tmpls = pkg('Template')->find(template_id => \@ids);
ok(@tmpls);
is (ref $_, 'Krang::Template', "Find - template_id " . $i++) for @tmpls;

my $count = pkg('Template')->find(count => 1, template_id => \@ids);
is($count, scalar @ids, "Find - count");

$i = 2;
my $year = (localtime)[5] + 1900;
my @tmpls2 = pkg('Template')->find(creation_date_like => "%${year}%");
ok(@tmpls2);
is(ref $_, 'Krang::Template', "Find - _like " . $i++) for @tmpls2;

my ($tmpl4) = pkg('Template')->find(limit => 1,
                                    offset => 1,
                                    order_by => 'filename',
                                    category_id => $category->category_id);
is($tmpl4->filename(), 't_w_c.tmpl', "Find - limit, offset, order_by");

my @tmpls5 = pkg('Template')->find(order_desc => 1,
                                   creation_date_like => "%${year}%",
                                   category_id => $category->category_id);
ok(@tmpls5);
isa_ok($_, 'Krang::Template') for @tmpls5;
is($tmpls5[0]->filename(), 't_w_c.tmpl', "Find - ascend/descend");

# check category arrayref search for find().
my @cat_ids = ($category->category_id);
my @tmpls6 = pkg('Template')->find(category_id => \@cat_ids);
isa_ok($_, 'Krang::Template') for @tmpls5;


# version find
my ($tmplXYZ) = pkg('Template')->find(template_id => $tmpl->template_id,
                                      version => 2);
isa_ok($tmplXYZ, 'Krang::Template');
is($tmplXYZ->version(), 2, 'Template version test');

# clean up the mess
END {
    unlink 't_w_c.tmpl';
    is($tmpl->delete(), 1, 'Deletion Test 1');
    is($tmpl2->delete(), 1, 'Deletion Test 2');

    # delete category and site
    $site->delete();
}


# Test permissions
{
    my $uniqueness = time();

    # Create site/category hierarchy for testing purposes
    my $site = pkg('Site')->new( preview_url  => $uniqueness .'preview.com',
                                 preview_path => $uniqueness .'preview/path/',
                                 publish_path => $uniqueness .'publish/path/',
                                 url          => $uniqueness .'site.com' );
    $site->save();
    my ($root_category) = pkg('Category')->find( parent_id => undef,
                                                 site_id => $site->site_id() );
    die ("No root category for site ". $site->site_id()) unless (ref($root_category));

    # Array of test templates
    my @test_templates = ();

    # Add global template
    my $template = pkg('Template')->new( filename => "GLOBAL_$uniqueness\.tmpl" );
    $template->save();
    push(@test_templates, $template);

    # Add template to root category
    $template = pkg('Template')->new( category => $root_category,
                                         filename => "ROOT_$uniqueness\.tmpl" );
    $template->save();
    push(@test_templates, $template);


    my @cat_names = qw(A1 A2 B1 B2);
    my @test_cats = ();
    foreach my $cat_name (@cat_names) {
        my $parent_cat = ( $cat_name =~ /1$/ ) ? $root_category : $test_cats[-1] ;
        die ("No cat available for cat_name '$cat_name'") unless (ref($parent_cat));

        # Create test category
        my $newcat = pkg('Category')->new( dir => "$cat_name\_$uniqueness",
                                           parent_id => $parent_cat->category_id() );
        $newcat->save();
        push(@test_cats, $newcat);

        # Add template in this category
        my $template = pkg('Template')->new( category => $newcat,
                                             filename => "$cat_name\_$uniqueness\.tmpl" );
        $template->save();
        push(@test_templates, $template);
    }


    # Do we have permissions at all?
    is($test_templates[0]->may_edit(), "1", "Global template may_edit");
    is($test_templates[0]->may_see(), "1", "Global template may_see");

    # Test template in category for permissions
    is($test_templates[1]->may_edit(), "1", "Root cat template may_edit");
    is($test_templates[1]->may_see(), "1", "Root cat template may_see");

    # Test template in descendant category for permissions
    is($test_templates[2]->may_edit(), "1", "Root cat template may_edit");
    is($test_templates[2]->may_see(), "1", "Root cat template may_see");

    # Test template in category w/o edit access
    my ($admin_group) = pkg('Group')->find(group_id=>1);
    die ("Can't load admin group") unless (ref($admin_group));
    $admin_group->categories($test_cats[0]->category_id => "read-only");
    $admin_group->save();
    ($template) = pkg('Template')->find(category_id => $test_cats[0]->category_id);
    is($template->may_edit(), "0", "Can't edit template (". $template->template_id .") in read-only category (".$test_cats[0]->category_id .")");
    is($template->may_see(), "1", "Can see template in read-only category");
    
    # Test template in descendant category w/o edit access
    ($template) = pkg('Template')->find(category_id => $test_cats[1]->category_id);
    is($template->may_edit(), "0", "Can't edit template (". $template->template_id .") in read-only category (".$test_cats[1]->category_id .")");
    is($template->may_see(), "1", "Can see template in read-only category");

    # Test template in category w/o edit or read access ("hide")
    $admin_group->categories($test_cats[0]->category_id => "hide");
    $admin_group->save();
    ($template) = pkg('Template')->find(category_id => $test_cats[0]->category_id);
    is($template->may_edit(), "0", "Can't edit template (". $template->template_id .") in hidden category (".$test_cats[0]->category_id .")");
    is($template->may_see(), "0", "Can't see template (". $template->template_id .") in hidden category (".$test_cats[0]->category_id .")");
    # Test template in descendant category w/o edit or read access ("hide")
    ($template) = pkg('Template')->find(category_id => $test_cats[1]->category_id);
    is($template->may_edit(), "0", "Can't edit template (". $template->template_id .") in hidden category (".$test_cats[1]->category_id .")");
    is($template->may_see(), "0", "Can't see template (". $template->template_id .") in hidden category (".$test_cats[1]->category_id .")");

    # Can't save() read-only template
    eval { $template->save };
    isa_ok($@, "Krang::Template::NoEditAccess", "Save non-editable template throws exception");

    # Can't checkout() read-only template
    eval { $template->checkout };
    isa_ok($@, "Krang::Template::NoEditAccess", "Check-out non-editable template throws exception");

    # Can't checkin() read-only template
    eval { $template->checkin };
    isa_ok($@, "Krang::Template::NoEditAccess", "Check-in non-editable template throws exception");

    # Can't delete() read-only template
    eval { $template->delete };
    isa_ok($@, "Krang::Template::NoEditAccess", "Delete non-editable template throws exception");

    # Test combined permissions -- add an additional group w/read-only access
    my $new_admin_group = pkg('Group')->new( name => "group $uniqueness" );
    $new_admin_group->categories($test_cats[1]->category_id => "edit");
    $new_admin_group->save();

    my ($admin_user) = pkg('User')->find(login=>"system", hidden => 1);
    $admin_user->group_ids_push($new_admin_group->group_id());
    $admin_user->save();

    ($template) = pkg('Template')->find(category_id => $test_cats[1]->category_id);
    is($template->may_edit(), "1", "Can edit template with new group access");
    is($template->may_see(), "1", "Can see template with new group access");
    
    # Delete test group
    $admin_user->group_ids_pop();
    $admin_user->save();
    $new_admin_group->delete();

    # Test read and edit access to templates on other category branch
    ($template) = pkg('Template')->find(category_id => $test_cats[-1]->category_id);
    is($template->may_edit(), "1", "Can edit template on other category branch");
    is($template->may_see(), "1", "Can see template on other category branch");
    
    # Can't save to read-only category
    $template = pkg('Template')->new( category => $test_cats[0],
                                      filename => "noaccess\_$uniqueness\.tmpl" );
    eval { $template->save };
    isa_ok($@, "Krang::Template::NoCategoryEditAccess", "Save to non-editable category ".$test_cats[0]->category_id." throws exception");
    
    # Test "global" template for permissions
    ($template) = pkg('Template')->find(template_id => $test_templates[0]->template_id());
    is($template->may_edit(), "1", "Can edit global template");
    is($template->may_see(), "1", "Can see global template");

    # Test "global" template w/ full access, but asset_template == "read-only"
    $admin_group->asset_template("read-only");
    $admin_group->save();
    ($template) = pkg('Template')->find(template_id => $test_templates[0]->template_id());
    is($template->may_edit(), "0", "Can't edit global template (". $test_templates[0]->template_id() .") w/ asset_template == 'read-only'");
    is($template->may_see(), "1", "Can see global template (". $test_templates[0]->template_id() .") w/ asset_template == 'read-only'");

    # Test "global" template w/ full access, but asset_template == "hide"
    $admin_group->asset_template("hide");
    $admin_group->save();
    ($template) = pkg('Template')->find(template_id => $test_templates[0]->template_id());
    is($template->may_edit(), "0", "Can't edit global template (". $test_templates[0]->template_id() .") w/ asset_template == 'hide'");
    is($template->may_see(), "1", "Can still see global template (". $test_templates[0]->template_id() .") w/ asset_template == 'hide'");

    # Test template in category w/ full access, but asset_template == "read-only"
    $admin_group->asset_template("read-only");
    $admin_group->save(); 
    ($template) = pkg('Template')->find(template_id => $test_templates[1]->template_id());
    is($template->may_edit(), "0", "Can't edit template (". $test_templates[1]->template_id() .") w/ asset_template == 'read-only'");
    is($template->may_see(), "1", "Can see template (". $test_templates[1]->template_id() .") w/ asset_template == 'read-only'");

    # Test template in category w/ full access, but asset_template == "hide"
    $admin_group->asset_template("hide");
    $admin_group->save();
    ($template) = pkg('Template')->find(template_id => $test_templates[1]->template_id());
    is($template->may_edit(), "0", "Can't edit template (". $test_templates[1]->template_id() .") w/ asset_template == 'hide'");
    is($template->may_see(), "1", "Can see template (". $test_templates[1]->template_id() .") w/ asset_template == 'hide'");

    # Re-set asset_template group permissions
    $admin_group->asset_template("edit");
    $admin_group->save();

    # Delete test templates
    for (reverse(@test_templates)) {
        $_->delete();
    }

    # Delete test categories
    for (reverse(@test_cats)) {
        $_->delete();
    }

    # Delete test site
    $site->delete();
}
