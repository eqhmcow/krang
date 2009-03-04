/**
   Krang Preview Finder Module
 */
(function() {
    // helper function to format infos extracted from our comment
    var formatInfo = function(info, separator) {
        var html   = '';

        var script = info.type == 'template'
        ? info.documentRoot + "/template.pl?rm=search&do_advanced_search=1&search_template_id=" + info.id
        : info.documentRoot + "/media.pl?rm=find&do_advanced_search=1&search_media_id=" + info.id;

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

    // register a click handler
    document.observe('click', function(e) {

        var element = e.element();
        var html    = '';
        var skip    = false;
        var info    = '';

        // skip our info DIV
        if (/__pinfo/.test(element.id) || element.hasClassName('__skip_pinfo')) {
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
                header: '<strong>Template / Media Info</strong>', width: '400px', cancelIconSrc : info.documentRoot + '/proto_popup/images/cancel.png'
            });
        }

        /*
          IE6/7 specials, still!

          Under the tools/internet options menu, on the general tab,
          when "Check for newer versions of stored pages" is set to
          "Automatic", the following strange behavior occurs:

          After a page reload via F5 (but also via Ctrl-F5) this click
          handler, although unloaded, is somehow kept around.  A click
          on the "Preview Finder" button (that gets redisplayed
          because of the page reload) not only loads the JavaScript
          file you're reading, but also executes this clickHandler!
          Nonetheless, this stray execution fails to fill the info{}
          object, so that the pinfo() function is created without the
          cancelIconSrc being properly set. That's the convoluted
          reason for the following if-else block. [Bodo Schulze]
        */
        if (info.documentRoot) {
            pinfo(html);
        } else {
            $('__pinfo').remove();
            pinfo = null;
        }

        // and prevent the default behavior for links, unless it's our own link
        if (!element.hasClassName("krang-find-template-link")) {
            Event.stop(e);
        }
    });
})();
