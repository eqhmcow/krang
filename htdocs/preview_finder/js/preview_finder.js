/**
   Krang Preview Finder Module
 */
(function() {
    // positioning of top overlay
    if (Prototype.Browser.IEVersion == 6) {
        $('krang_preview_editor_top_overlay').setStyle({position: 'absolute'});
    }

    // helper function to format infos extracted from our comment
    var formatInfo = function(info, separator) {
        var html   = '';

        var script = info.type == 'template'
        ? info.cmsRoot + "/template.pl?rm=search&do_advanced_search=1&search_template_id=" + info.id
        : info.cmsRoot + "/media.pl?rm=find&do_advanced_search=1&search_media_id=" + info.id;

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

    // find comments up from the element the user clicked on
    // checking previous siblings and then the parent, the tree upwards
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
    // comments, formats them and display them in a popup
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
                    info = comment.evalJSON();
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
        
        // finally print it to the popup
        if (pinfo === null) {
            pinfo = ProtoPopup.makeFunction('__pinfo', {
                header:         '<strong>Template / Media Info</strong>',
                width:          '400px',
                cancelIconSrc : info.cmsRoot + '/proto_popup/images/cancel.png'
            });
        }

        if (info.cmsRoot) {
            pinfo(html);
        }

        // and prevent the default behavior for links, unless it's our own link
        if (!element.hasClassName("krang-find-template-link")) {
            Event.stop(e);
        }
        return false;
    };
    document.observe('click', templateFinderClickHandler);

/*

                --- Preview Editor ---


*/

    // no overlay, no functionality
    if (! $('krang_preview_editor_toggle')) { return }

    // click handler for container element labels, posts back to the
    // CMS to open the corresponding container element in the "Edit Story" UI
    var labelClickHandler = function(e) {
        var label   = e.element();
        var info    = label.readAttribute('name');
        var cms     = info.evalJSON();
        var url     = cms.cmsRoot + '/story.pl';
        var params  = {
            window_id: cms.windowID,
            rm:        'edit',
            story_id:  cms.storyID,
            path:      cms.elementXPath
        };

        if (Object.isFunction(window.postMessage)) {
            // HTML5 feature implemented by Firefox 3, maybe by IE8 and Safari 4
            params['ajax'] = 1;
            window.opener.postMessage(url + "\uE000" + Object.toJSON(params), cms.cmsRoot);
        } else if (Prototype.Browser.IE) {
            //
            // This hack does not work for communications *back* to the CMS window
            //
            // var a = new Element('a', {href:   url + '?' + Object.toQueryString(params)});
            // a.target = "krang_window_" + cms.windowID;
            // document.body.appendChild(a);
            // a.click();
            //
            // But using a form works! (strange, both use the same 'target' property)
            //
            // pass params as form inputs and signal it to
            // Krang::Handler using with the special query param 'posted_window_id'
            var f = new Element(
                'form',
                {action: url+'?posted_window_id=1', method: 'post', target: 'krang_window_'+cms.windowID}
            );
            $H(params).keys().each(function(i) {
                    f.appendChild(new Element('input', {type: 'hidden', name: i, value: params[i]}));
            });
            document.body.appendChild(f);
            f.submit();
        } else {
            // Safari 3.1 / 3.2
            window.open(url + '?' + Object.toQueryString(params), "krang_window_" + cms.windowID);
        }
    };

    // position the labels
    var positionLabels = function() {
        $$('.krang_preview_editor_element_label').reverse().each(function(contElm) {
                var offset = contElm.next().cumulativeOffset();
                contElm.show().setStyle({left: offset.left - 7 + 'px', top: offset.top - 23 + 'px'})
    })};
    positionLabels();

    // reposition them when resizing the window
    Event.observe(window, 'resize', positionLabels);

    // make them clickable
    $$('.krang_preview_editor_element_label').reverse().each(function(contElm) {
            var id     = contElm.identify();
            contElm.show().observe('click', labelClickHandler);
    });

    // activate/deactivate the editor and the template/media finder
    var activateDeactivate = function(e) {
        if ($('krang_preview_editor_activate').visible()) {
            $('krang_preview_editor_activate').hide();
            $('krang_preview_editor_deactivate').show();
            document.observe('click', templateFinderClickHandler);
        } else {
            $('krang_preview_editor_activate').show();
            $('krang_preview_editor_deactivate').hide();
            document.stopObserving('click', templateFinderClickHandler);
        }
        $$('.krang_preview_editor_element_label').invoke('toggle');
    };
    $('krang_preview_editor_toggle').observe('click', activateDeactivate);
    
    // deactivate finder (maybe editor too) and hide the top overlay (bring it back pressing F5)
    var deactivateHide = function(e) {
        document.stopObserving('click', templateFinderClickHandler);
        Event.stopObserving(window, 'resize', positionLabels);
        $$('.krang_preview_editor_element_label').invoke('hide');
        $('krang_preview_editor_top_overlay').hide();
        $('krang_preview_editor_top_spacer').hide();
        try { $('__pinfo').hide() } catch(er) {}
        Event.stop(e);
    }
    $('krang_preview_editor_close').observe('click', deactivateHide);

    // show help
    var helpLink = $('krang_preview_editor_help');
    var helpURL  = helpLink.readAttribute('name');
    var showHelp = function() {
        window.open(helpURL, "kranghelp", "width=400,height=500");
    }
    helpLink.observe('click', showHelp);

})();
