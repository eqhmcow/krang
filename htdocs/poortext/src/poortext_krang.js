

/*
                  Hook into Krang's StoryLink Interface
*/

/**
   Instance method called to go to Krang's "Select Story" screen.
 */
PoorText.prototype.addStoryLink = function() {

    // Krang element param
    var param  = PoorText.Krang.paramFor[this.id];

    // Remember the PoorText object's ID: we'll need when returning from "Select Story"
    var item = this.container.up();
    if (item.hasClassName('poortextlist_item')) {
        // Krang::ElementClass::PoorTextList
        var idx = item.previousSiblings().length;
        PoorText.Krang.id = param + '_' + idx;
    } else {
        // Krang::ElementClass::PoorText 
        PoorText.Krang.id = this.id;
    }

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
    PoorText.Krang.linkId = 'poortext_krang_storylink';
    link.setAttribute('id', PoorText.Krang.linkId);

    // Gecko seems dumb here and needs special treatment
    if (Prototype.Browser.Gecko) {
        this.selectNode(link);
        PoorText.Krang.selection = this.getSelection();
    }

    // Custom event
    if (!this.usingIFrame) {
        $(this.eventNode).fire('pt:before-find-story-link');
    }

    // Submit form: goto "Select Story" screen
    Krang.ElementEditor.run_save_hooks();
    Krang.Form.submit(
        'edit',
        {
          rm      : 'save_and_find_story_link',
          jump_to : param,
          editor_insert_storylink_function : 'PoorText.Krang.insertStoryLink'
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
    linkId     : "", // A tag id for StoryLink insertion
    id         : "", // PT field id
    paramFor   : [], // mapping PT field id to Krang element param
    
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

            // set a special CSS class
            PoorText.setClass(link, 'pt-a pt-storylink');

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
            pt.onEditNodeReady(function() {
                PoorText.Krang.doRestoreSelection(pt, link , deleteLink)
            });
            pt._makeEditable();
            pt._activateIframe();
            return;
        }

        // tail call: workaround timing issue with IFrames
        return PoorText.Krang.doRestoreSelection(pt, link, deleteLink);
    },

    doRestoreSelection : function(pt, link, deleteLink) {

        // select the link
        pt.focusEditNode();
        pt.onFocus();

        if (Prototype.Browser.Gecko) {
            pt.restoreSelection(PoorText.Krang.selection);
            if (deleteLink) {
                /**
                   For Dev: Without this apparently superfluous call
                   to pt.getLink(), FF2/3 (with IFrame or contenteditable) replaces
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

        pt.storeForPostBack();
    }
}

/*
        Postback to clean HTML on the server
 */
// override the core's onPaste method
PoorText.prototype.onPaste = function() { 
    setTimeout(function() {
        this.clean_pasted_html();
    }.bind(this), 10);
}

/**
   Instance method to clean pasted text via an Ajax call.
 */
PoorText.prototype.clean_pasted_html = function() {
    //
    // don't call storeForPostBack() to bypass IO filters
    //
    var pt = this;
    var element     = PoorText.Krang.paramFor[pt.id] || pt.id;
    var form        = $('edit');
    var url         = form.readAttribute('action').replace(/\?.*/, '');
    var params      = {rm : 'filter_element_data', filter_element : element};
    params[element] = pt.editNode.innerHTML;

    // post back for cleaning
    Krang.Ajax.request(
        { 
          url        : url,
          params     : params,
          indicator  : 'indicator',
          method     : form.readAttribute('method'),
          onComplete : function(args, transport, json) {
              // update the edit area
              pt.editNode.innerHTML = transport.responseText;

              // maybe also the return field
              if (pt.returnHTML) { pt.returnHTML.value = transport.responseText; }

              // focus it
              pt.focusEditNode;

              // and put the caret at the beginning of the edit node
              if (Prototype.Browser.IE) {
                  pt.toggleSelectAll();
                  pt.toggleSelectAll();
              } else {
                  pt.restoreSelection({sc : [0], so : 0, ec : [0], eo: 0});
              }
          }
    });
}

