# docs/Makefile - process POD format documentation into HTML.  Uses
# both pod2html and custom scripts stored in bin/

HTML = changes.html objects.html coding.html goals.html rationale.html \
       cpan.html new_features.html paper_screen.html element_system.html \
       index.html install.html building_perl_modules.html requirements.html \
       configuration.html tech_spec.html writing_htmltemplate.html \
       permissions.html xml.html performance.html ops_install.html \
       customizing_publish.html ops_upgrade.html release.html \
       add_on.html addon_install.html upgrade_system.html ops_backup.html \
       skins.html cpan_inventory.html scheduler.html build_tech_spec.html

all   : $(HTML) modules.html rm_modules

%.html : %.pod Makefile docs.css bin/*.pl
	bin/pod2html.pl $< $@

modules.pod :
	bin/lib_docs.pl

rm_modules :
	rm modules.pod

clean :
	- rm $(HTML)
	- rm pod2*
