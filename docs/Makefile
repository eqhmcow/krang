# docs/Makefile - process POD format documentation into HTML.  Uses
# both pod2html and custom scripts stored in bin/

HTML = changelog.html changes.html coding.html goals.html porting.html \
       new_features.html element_system.html \
       index.html install.html building_perl_modules.html \
       configuration.html tech_spec.html writing_htmltemplate.html \
       permissions.html xml.html performance.html ops_install.html \
       customizing_publish.html ops_upgrade.html release.html \
       add_on.html addon_install.html upgrade_system.html ops_backup.html \
       skins.html cpan_inventory.html scheduler.html build_tech_spec.html \
       running.html building_element_library.html krang_on_desktop.html \
       todo.html addon_howto1.html

all   : $(HTML) modules.html scripts.html rm_modules rm_scripts

%.html : %.pod Makefile docs.css bin/*.pl
	bin/pod2html.pl $< $@

modules.pod :
	bin/lib_docs.pl

scripts.pod :
	bin/script_docs.pl

rm_modules :
	rm modules.pod

rm_scripts :
	rm scripts.pod

clean :
	- rm $(HTML)
	- rm pod2*
