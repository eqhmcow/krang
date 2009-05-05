/**
   Krang Preview Editor Module
 */
(function() {

    // Change following line to Krang.debug.on() to debug to the
    // console (requires Firebug or something providing a
    // console.debug() function).
    Krang.debug.on();

/*
                   --- CMS access data ---
*/
    try {
        var cmsData = window.name ? window.name.evalJSON() : {}
    }
    catch(er) {
        Krang.error('', 'Critical error in preview_editor.js (malformed JSON data)');
    }

    // CMS window
    var cmsWin   = top.opener;
    var cmsURL   = cmsData.cmsURL;
    var cmsWinID = cmsData.winID;

    // get story ID
    var fLabel  = $$('.krang_preview_editor_element_label').first();
    var flName  = fLabel ? fLabel.readAttribute('name') : '';
    try {
        var flObj   = flName ? flName.evalJSON() : '';
    }
    catch (er) {
        Krang.error(cmsURL, 'Critical error in preview_editor.js (malformed JSON data)');
    }
    var storyID = flObj.storyID;

    Krang.debug("CMS URL: "+cmsURL);
    Krang.debug("Window ID: "+cmsWinID);
    Krang.debug("Story ID: "+storyID);

/*
                    --- Template Finder ---
*/

    // helper function to format infos extracted from our comment
    var formatInfo = function(info, separator) {
        var html   = '';

        var script = info.type == 'template'
        ? cmsURL + "/template.pl?rm=search&do_advanced_search=1&search_template_id=" + info.id
        : cmsURL + "/media.pl?rm=find&do_advanced_search=1&search_media_id=" + info.id;

        if (separator) {html += '<hr style="margin:3px 0px" class="__skip_pinfo"/>';}

        html += info.type == 'template'
        ? '<div class="__skip_pinfo"><strong class="__skip__pinfo">Template</strong> ' + info.id
         +'<br /><strong class="__skip_pinfo">File:</strong> ' + info.filename
        : '<div class="__skip_pinfo"><strong class="__skip__pinfo">Media</strong> ' + info.id
         +'<br /><strong class="__skip_pinfo">Title:</strong> ' + info.title

        html += '<br /><strong class="__skip_pinfo">URL:</strong> <a target="_blank" href="'
               +script+'" class="krang-find-template-link __skip_pinfo">'+info.url+'</a></div>';

        return html;
    };

    // find comments up from the Krang element the user clicked on
    // checking previous siblings and then the parent, the tree
    // upwards
    var findCommentsUp = function(element, callback) {
        element = $(element);
        var node = element;
        var acc  = [];
        while (node !== null) {
            while (node !== null) {
                if (node.nodeType == 8) { // comment node
                    if (Object.isFunction(callback)) {
                        // found a comment: extract the info
                        var info = (callback(node));
                        if (info !== null) {
                            acc.push(info);
                        }
                    } else {
                        acc.push(node);
                    }
                }
                last = node;
                node = node.previousSibling;
            }        
            node = last.parentNode;
        }
        return acc;
    }

    var startRE = /KrangPreviewFinder Start/;
    var endRE   = /KrangPreviewFinder End/;
    var pinfo   = null;

    // template finder click handler, looks up the info in the special
    // comments, formats them and displays them in a popup
    var templateFinderClickHandler = function(e) {

        var element = e.element();
        var html    = '';
        var skip    = false;
        var info    = '';

        // skip our info DIV
        if (/__pinfo/.test(element.id) || element.hasClassName('__skip_pinfo')
            || element.hasClassName('krang_preview_editor_element_label')) {
            return;
        }

        // find the info comments we put in in Krang::ElementClass::find_template()
        var infos = findCommentsUp(element, function(element) {
                var comment = element.nodeValue;
                if (skip) {
                    // the previous one was an End tag: skip the corresponding start tag
                    if (startRE.test(comment)) {
                        // it's a start tag: reset skip
                        skip = false;
                    }
                    return null;
                }

                if (startRE.test(comment)) {
                    // a start tag: extract info
                    comment = comment.replace(/KrangPreviewFinder Start/, '').strip();
                    try {
                        info = comment.evalJSON();
                    }
                    catch (er) {
                        Krang.error(cmsURL, 'Critical error in preview_editor.js (malformed JSON data)');
                    }
                    return info;
                } else if (endRE.test(comment)) {
                    // an end tag: we are not interested in the corresponding start tag
                    skip = true;
                    return null;
                } else {
                    // another comment
                    return null;
                }
        });

        // format the info
        var html = '';
        infos.each(function(info, index) {
            var separator = index === 0 ? false : true;
            html += formatInfo(info, separator);
        });
        
        // maybe make info popup
        if (pinfo === null) {
            pinfo = ProtoPopup.makeFunction('__pinfo', {
                header:         '<strong>Template / Media Info</strong>',
                width:          '400px',
                cancelIconSrc : cmsURL + '/proto_popup/images/cancel.png'
            });
        }

        // finally print it to the popup
        pinfo(html);

        // and prevent the default behavior for links, unless it's our own link
        if (!element.hasClassName("krang-find-template-link")) {
            Event.stop(e);
        }
        return false;
    };

/*
                         --- Preview Editor ---

*/
    // Wrapper around Krang.XOrigin.XUpdater() - see xorigin.js
    // Usage (showing the defaults):
    // Update({method: 'post', form: undefined, params: {}, onComplete: Prototype.emptyFunction})
    var Update = function(args) {
        Krang.XOrigin.XUpdater(cmsWin, {
            cmsURL:     cmsURL,
            cmsApp:     'story.pl',
            method:     args.method     || 'post',
            form:       args.form       || undefined,
            params:     args.params     || {},
            onComplete: args.onComplete || Prototype.emptyFunction
        });
    };

    // Wrapper around Krang.XOrigin.Request() - see xorigin.js
    // Usage (showing the defaults):
    // Request({method: 'get', form: undefined, params: {}, onComplete: Prototype.emptyFunction})
    var Request = function(args) {
        Krang.XOrigin.Request(cmsWin, {
            cmsURL:     cmsURL,
            cmsApp:     'story.pl',
            method:     args.method     || 'get',
            form:       args.form       || undefined,
            params:     args.params     || {},
            onComplete: args.onComplete || Prototype.emptyFunction
        });
    };

    // Click handler for container element labels. Posts back to the
    // CMS to open the corresponding container element in the "Edit Story" UI
    var labelClickHandler = function(e) {
        var element = e.element();

        // prevent the default behavior for links, unless it's our own link
        if (!element.hasClassName("krang_preview_editor_element_label")) {
            Event.stop(e);
            return false;
        }
        
        // get info from our label
        var info    = element.readAttribute('name');
        var cms     = info.evalJSON();
        var params  = { rm: 'save_and_jump', jump_to: cms.elementXPath }
        
        var jumpToElement = function() {
            Update({
                form:   'edit', 
                params: params,
            });
        }
        
        var putOnEditScreenAndJumpToElement = function() {
            Krang.XOrigin.WinInfo(cmsWin, {
                // maybe put story on Edit Story screen
                cmsURL:   cmsURL,
                question: 'isStoryOnEditScreen',
                response: function(response) {
                    if (response == 'no') {
                        params['rm']       = 'edit';
                        params['story_id'] = storyID;
                    }
                },
                finish: jumpToElement
            });
        };
        
        var checkoutAndJumpToElement = function() {
            // check out
            Update({
                params:     { rm: 'pe_checkout_and_edit', story_id: storyID },
                onComplete: jumpToElement
            });
        };
        
        // checked-out status might have changed, so check it again
        Request({
            params: {
                rm:       'pe_get_status',
                story_id: storyID
            },
            // ...and edit the story
            onComplete: function(status) {
                if (status.checkedOutBy == 'me') {
                    putOnEditScreenAndJumpToElement();
                } else if (status.checkedOut == '0') {
                    checkoutAndJumpToElement();
                }
            }
        });
    };

    // position the labels
    var positionLabels = function() {
        var prev = {top: 0, left: 0};
        $$('.krang_preview_editor_element_label').reverse().each(function(contElm) {
            var offset = contElm.next().cumulativeOffset();
            if (offset.top == prev.top && offset.left == prev.left) offset.top -= 30;
            prev = offset;
            contElm.show().setStyle({left: offset.left - 7 + 'px', top: offset.top - 23 + 'px'})
    })};
    positionLabels();

    // reposition them when resizing the window
    Event.observe(window, 'resize', positionLabels);

/*
    
                  --- Overlay UI ---
    
*/
    // Stop click events from bubbling up above the UI container
    $('krang_preview_editor_top_overlay').observe('click', function(e) { Event.stop(e) });

    // Init overlay buttons callback
    var initOverlay = function(status, pref, config) { // status provided by Krang::CGI::Story::pe_get_status()

        //
        // Helper functions
        //

        var uiReset = function() {
            try { $('__pinfo').hide() } catch(er) {}
            $$('.krang_preview_editor_btn').invoke('removeClassName', 'krang_preview_editor_btn_pressed');            
            $$('.krang_preview_editor_element_label').invoke('hide');
            document.stopObserving('click', templateFinderClickHandler);
            document.stopObserving('click', labelClickHandler);
        };


        var editBtnHandler;

        var editBtnHandlerFactory = function(func, e) {
            uiReset();
            if (Object.isFunction(func)) { func.call(); }
            activateEditMode();
        };

        var activateEditMode = function() {
            $('krang_preview_editor_btn_edit').addClassName('krang_preview_editor_btn_pressed').show();
            $$('.krang_preview_editor_element_label').invoke('show');
            document.observe('click', labelClickHandler);
        };

        var editBtnIfOwner = function() {

            Krang.debug("Stories: "+storyID+' '+status.storyInSession);

            if (status.storyInSession == storyID) {
                // our story is already in the session, but is it also
                // on the "Edit Story" screen?
                editBtnHandler = editBtnHandlerFactory.curry(function() {
                    Krang.XOrigin.WinInfo(cmsWin, {
                        cmsURL:   cmsURL,
                        question: 'isStoryOnEditScreen',
                        response: function(response) {
                            // it's not opened in "Edit Story", so open it
                            if (response == 'no') {
                                // like clicking on "Edit" button on workspace
                                Update({
                                    form:   'edit',
                                    params: {rm: 'edit', story_id: storyID},
                })}}})});
                $('krang_preview_editor_btn_edit').show().observe('click', editBtnHandler);
            } else {
                // our story is not yet in the session, so open it on "Edit Story"
                editBtnHandler = editBtnHandlerFactory.curry(function() {
                    Update({
                        params: {rm: 'edit', story_id: storyID},
                        form:   undefined,
                    });
                });
                $('krang_preview_editor_btn_edit').show().observe('click', editBtnHandler);
            }
        };

        var editBtnIfMayEdit = function() {
            // our story is checked-in, but we may edit it
            editBtnHandler = editBtnHandlerFactory.curry(function() {
                // check it out and open it on "Edit Story"
                Update({
                    params:     { rm: 'pe_checkout_and_edit', story_id: storyID },
                    onComplete: function() {
                        // remove story check out handler
                        $('krang_preview_editor_btn_edit').stopObserving('click', editBtnHandler);
                        // attach edit handler
                        editBtnHandler = editBtnHandlerFactory.curry(Prototype.emptyFunction);
                        $('krang_preview_editor_btn_edit').show().observe('click', editBtnHandler);
                    }
                });
            });
            $('krang_preview_editor_btn_edit').show().observe('click', editBtnHandler);
        };

        var editBtnIfMaySteal = function() {
            // story is checked out by another user, but we may steal it
            var ms = $('krang_preview_editor_btn_steal');
            // show the "Steal" button instead of the "Edit" button and add the current owner to the label
            var checkOutHandler = function(e) {
                uiReset();
                // steal the story
                Update({
                    method: 'get',
                    params: {
                        rm: 'steal_selected',
                        krang_pager_rows_checked: storyID
                    },
                    onComplete: function(json, pref, conf) {
                        // Replace "Steal" button with "Edit" button
                        ms.stopObserving('click', checkOutHandler).hide();
                        editBtnHandler = editBtnHandlerFactory.curry(Prototype.emptyFunction);
                        $('krang_preview_editor_btn_edit').show().observe('click', editBtnHandler);
                        activateEditMode();
                    },
                });
            };
            ms.update(ms.innerHTML +  ' ' + status.checkedOutBy).show().observe('click', checkOutHandler);
        };

        var initEditBtn = function() {
            if (status.checkedOutBy == 'me') {
                editBtnIfOwner();
            } else if (status.checkedOut == '0' && status.mayEdit  == '1') {
                editBtnIfMayEdit();
            } else if (status.checkedOut == '1' && status.maySteal == '1') {
                editBtnIfMaySteal();
            } else if (status.checkedOut == '0' && status.mayEdit  == '0') {
                $('krang_preview_editor_forbidden').show();
            } else {
                // story is checked out and we may not steal it
                var co = $('krang_preview_editor_checked_out').show();;
                co.update(co.innerHTML + ' ' + status.checkedOutBy).show();
            }
        };

        var askSaveDialog = function(storyInSession) {
            var p = new ProtoPopup.Dialog('proto-popup-dialog', {
                body: Krang.localize('Are you sure you want to discard your unsaved changes?'),
                cancelIconSrc: false,
                buttons: [
                    {name:       'save',
                     label:      Krang.localize("Save"),
                     giveFocus:  true,
                     horizontal: 'right',
                     onClick:    function(storyInSession) {
                         Update({
                             form:   'edit',
                             params: {rm: 'db_save'},
                             onComplete: initEditBtn
                         });
                         p.hide();
                     }},
                    {name:    'discard',
                     label:   Krang.localize("Discard"),
                     onClick: function() { p.hide(); initEditBtn() }}
                    ]
            }).show();
        };

        //
        // Set button status and click handlers
        //

        // reset button status
        uiReset();

        // Init "Browse" button
        $('krang_preview_editor_btn_browse').addClassName('krang_preview_editor_btn_pressed')
            .show().observe('click', function(e) {
                uiReset();
                $('krang_preview_editor_btn_browse').addClassName('krang_preview_editor_btn_pressed');
            });

        // Init "Find Template" button
        if (status.mayReadTemplates) {
            $('krang_preview_editor_btn_find').show().observe('click', function(e) {
                uiReset();
                $('krang_preview_editor_btn_find').addClassName('krang_preview_editor_btn_pressed');
                document.observe('click', templateFinderClickHandler);
            });
        }

        // Init "Edit/Steal" button and checked out msg
        if (status.storyInSession && status.storyInSession != storyID) {
            // we were previously editing the story that exists in the
            // session, ask user if he wants to save it
            askSaveDialog(status.storyInSession);
        } else {
            initEditBtn();
        }

        // Init "Close" button
        $('krang_preview_editor_close').observe('click', function(e) {
           // Show our story in a top level window: Disables the
           // loading of the Preview Editor's JavaScript and CSS
            top.location.href = window.location.href;
        });

        // Help button
        var helpBtn = $('krang_preview_editor_help');
        var helpURL  = helpBtn.readAttribute('name');
        var showHelp = function() {
            window.open(helpURL, "kranghelp", "width=400,height=500");
        }
        helpBtn.observe('click', showHelp);
    }

    var localizeOverlay = function(status, pref, config) { 

        Krang.debug("Story status on next 3 lines: ");
        Krang.debug(status); Krang.debug(pref); Krang.debug(config);

        // localize the UI
        Krang.XOrigin.WinInfo(cmsWin, {
            cmsURL:   cmsURL,
            question: 'getDictionary',
            response: function(thesaurus) {
                console.log(pref);
                if (thesaurus || pref.language == 'en' || Object.isUndefined(pref.language)) {
                   Krang.localize.withDictionary(thesaurus);
                } else {
                    Krang.error(cmsURL, 'Couldn\'t find dictionary for language "'+pref.language+'"');
                }
            },
            finish : function() {
                // localize the top overlay UI
                $("krang_preview_editor_logo",       "krang_preview_editor_btn_browse",
                  "krang_preview_editor_btn_find",   "krang_preview_editor_btn_edit",
                  "krang_preview_editor_btn_steal",  "krang_preview_editor_checked_out",
                  "krang_preview_editor_forbidden",  "krang_preview_editor_loading",
                  "krang_preview_editor_close",      "krang_preview_editor_help"
                ).invoke('localize');
                // localize the container element labels
                $$('.krang_preview_editor_element_label').invoke('localize');
                //init UI overlay
                initOverlay(status, pref, config);
            }
        });
    };

    // get our story's checkout status...
    Request({
        params: {
            rm:       'pe_get_status',
            story_id: storyID
        },
        // ...and initialize the overlay and its buttons after localizing them
        onComplete: localizeOverlay
    });
})();
