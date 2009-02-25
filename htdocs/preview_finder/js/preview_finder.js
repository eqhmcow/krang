// get a popup
(function() {
    // helper function to format infos extracted from our comment
    var formatInfo = function(info, separator) {
        var html = '';
        
        var script = info.documentRoot + "/template.pl?rm=search&do_advanced_search=1&search_template_id=" + info.id;
        
        if (separator) {html += '<hr style="margin:3px 0px" class="__pinfo"/>';}
        html += '<div class="__pinfo"><b class="__pinfo">File:</b> '+info.filename;
        html += '<br/><b class="__pinfo">URL:</b> <a target="_blank" href="'+script+'" class="krang-find-template-link">'+info.url+'</a></div>';

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

    var startRE = /Start/;
    var pinfo   = null;

    // register a click handler
    document.observe('click', function(e) {

        var element = e.element();
        var html    = '';
        var skip    = false;
        var info    = '';

        // skip our info DIV
        if (/__pinfo/.test(element.id) || element.hasClassName('__pinfo')) {
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
                } else {
                    // an end tag: we are not interested in the corresponding start tag
                    skip = true;
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
                header: 'Template Info', width: '400px', documentRoot : info.documentRoot
            });
        }
        pinfo(html);

        // and prevent the default behavior for links, unless it's our own link
        if (!element.hasClassName("krang-find-template-link")) {
            Event.stop(e);
        }
    });
})();
