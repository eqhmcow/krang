PoorText.prototype.addStoryLink = function() {

    // Get possibly existing link
    var sel = this.getLink();
    
    // No link && no selection
    if (sel.msg == 'showAlert') {
        this.notify("You have to select some text to insert a StoryLink.");
        this.focusEditNode();
        this.restoreSelection();
        return;
    } 
    
    // Create a placeholder link unless it exists
    var link = sel.elm;
    if (!link) {
        link = PoorText.focusedObj.doAddHTML('a', 'placeholder', 'placeholder',
                                             PoorText.focusedObj.selected.range);
    }

    // Give it an ID to find it when returning from "Select Story"
    PoorText.Krang.linkId = this.id+'_storyLink';
    link.setAttribute('id', PoorText.Krang.linkId);

    // Remember the PoorText object's ID: we'll need when returning from "Select Story"
    PoorText.Krang.id = this.id;

    // Gecko seems dumb here and needs special treatment
    if (Prototype.Browser.Gecko) {
        this.selectNode(link);
        PoorText.Krang.selection = this.getSelection();
    }

    // Submit form: goto "Select Story" screen
    var jumpTo = this.returnHTML.getAttribute('name');
    Krang.ElementEditor.run_save_hooks();
    Krang.Form.submit(
        'edit',
        {
          rm      : 'save_and_find_story_link',
          jump_to : jumpTo,
          story_link_is_for_editor : '1'
        },
        {
            // delete link placeholder when a save error occurs (e.g. failed element validation)
            onComplete : function(args, transport, json) {
                if (json && json.saveError) {
                    var link = document.getElementById(PoorText.Krang.linkId);
                    PoorText.Krang.restoreSelection(link, true);
                }
            }
        }
    );
};

PoorText.Krang = {
    linkId     : "",
    id         : "",

    // onComplete callback for ElementEditor's runmode 'select_story'
    insertStoryLink : function(json) {
        // the placeholder created before calling find_story_link
        var link = document.getElementById(PoorText.Krang.linkId);

        // no json means: selection has been cancelled
        var linkSpec = json ? json.storyLink : null;

        // update the placeholder link with the spec we get from "Select Story"
        if (linkSpec) {
            // no longer needed: throw away for re-usage
            link.removeAttribute('id');

            // update link attribs
            link.setAttribute('title', linkSpec.title);
            link.setAttribute('href', 'http://' + linkSpec.url);
            link.setAttribute('_poortext_url', 'http://' + linkSpec.url);

            // add the Story ID for preview handler attached to pt.editNode
            link.setAttribute('_story_id', linkSpec.id);
        }

        // process the link
        var pt = PoorText.Krang.restoreSelection(link, !linkSpec);

    },

    restoreSelection : function(link, deleteLink) {

        // get our PoorText field
        var pt = PoorText.id2obj[PoorText.Krang.id];

        // IFrame only: activate
        if (pt.usingIFrame && pt.config.deferIframeCreation) {
            pt._makeEditable();
            pt._activateIframe();
        }

        // tail call: workaround timing issue with IFrames
        return PoorText.Krang.doRestoreSelection(pt, link, deleteLink);
    },

    doRestoreSelection : function(pt, link, deleteLink) {

        // waiting for IFrame
        if (!pt.editNode) {
            setTimeout(function() {
                    PoorText.Krang.doRestoreSelection(pt, link, deleteLink);
            }, 50);
            return;
        }

        // select the link
        pt.focusEditNode();

        if (Prototype.Browser.Gecko) {
            pt.restoreSelection(PoorText.Krang.selection);
            if (deleteLink) {
                /**
                   For Dev: Without this apparently superfluous call
                   to pt.getLink(), FF2/3 (both using IFrame) replaces
                   the HTMLAnchorElement with this SPAN:

                       <span class="pt-a" _moz_dirty="">SomeString</span>

                   even when removing the CLASS attrib before deleting
                   the link
                */
                sel = pt.getLink();
                sel.elm.removeAttribute('class');
                pt.doDeleteHTML();
            }
        }

        if (Prototype.Browser.IE || Prototype.Browser.WebKit) {
            pt.selectNode(link);
            pt.storeSelection();
            if (deleteLink) {
                pt.doDeleteHTML();
                pt.updateButtonBar();
            }
        }
    }
}
