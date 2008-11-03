/** @fileoverview
    Webkit specific code
*/

PoorText.iframeStyles = [
    'top', 'left', 'bottom', 'right', 'zIndex',
    'borderTopWidth', 'borderRightWidth', 'borderBottomWidth', 'borderLeftWidth',
    'borderTopStyle', 'borderRightStyle', 'borderBottomStyle', 'borderLeftStyle',
    'borderTopColor', 'borderRightColor', 'borderBottomColor', 'borderLeftColor',
    'marginTop',      'marginRight',      'marginBottom',      'marginLeft'
];

/**
   Array of markup CSS properties we copy from {@link #srcElement} to
   {@link #styleNode}.
   @type Class Array
   @private
*/
PoorText.bodyStyles = [
    'backgroundColor', 'color',        'width',
    'lineHeight',      'textAlign',    'textIndent',
    'letterSpacing',   'wordSpacing',  'textDecoration', 'textTransform',
    'fontFamily',      'fontSize',     'fontStyle',      'fontVariant',   'fontWeight',
    'paddingTop',      'paddingRight', 'paddingBottom',  'paddingLeft'
];

/**
   Allowed HTML tags. Used by {@link PoorText#_cleanPaste} to verify
   that external text pasted in does not mess up our HTML.
   @type Class RegExp
   @final
   @private
*/
PoorText.allowedTagsRE = /^(a|abbr|acronym|b|br|del|em|i|span|strike|strong|sub|sup|u)$/i;

/**
   Regexp matching {@link PoorText#bodyStyles} which get copied from {@link
   #srcElement} to {@link #styleNode}.
   @type RegExp
   @private
   @final
*/
PoorText.styleRE = '';
(function() {
  PoorText.styleRE = new RegExp(PoorText.bodyStyles.join('|'));
})();

PoorText.AppleSpanClassName = 'Apple-style-span';

PoorText.replaceSpan = function(node, createSpan) {

    node.select('.'+PoorText.AppleSpanClassName).each(function(oldNode) {

        // temporally put the replacement elements on a document fragment
        var docFrag = document.createDocumentFragment();
        var newNode = docFrag;
        oldNode = $(oldNode);

        // maybe create new span
        newNode = createSpan(oldNode, newNode);

        // if a new SPAN has been created...
        if (docFrag.hasChildNodes()) {
            // replace old with new, caring for its content
            newNode.innerHTML = oldNode.innerHTML;
            oldNode.parentNode.replaceChild(docFrag, oldNode);
        }

        // recurse into the substitution SPAN
        var moreSpans;
        try {
            // Prototype-1.6 does not expand docFrag with select() method!
            moreSpans = $(newNode).select('.'+PoorText.AppleSpanClassName);
        } catch(e) {}

        if (moreSpans && moreSpans.length) {
            PoorText.replaceSpan(newNode, createSpan);
        }
    });
}

// Webkit specific output filtering
/**@ignore*/
PoorText.outFilterWebKit = function(editNode) {
    return editNode.innerHTML;
    var spanReplaceMap = $A([
        // CSS rule         value           replacement element
        ['font-weight',     'bold',         'strong'],
        ['font-style',      'italic',       'em'    ],
        ['text-decoration', 'underline',    'u'     ],
        ['text-decoration', 'line-through', 'strike'],
        ['vertical-align',  'sub',          'sub'   ],
        ['vertical-align',  'super',        'sup'   ]
    ]);

    // don't alter the live node
    var cloned = $(editNode.cloneNode(true))

    // replace SPANs with markup tags
    PoorText.replaceSpan(cloned, function(oldNode, newNode) {
        spanReplaceMap.each(function(spec) {
            if (oldNode.getStyle(spec[0]) == spec[1]) {
                var n = document.createElement(spec[2]);
                newNode.appendChild(n);
                newNode = n;
            }
        });
        return newNode;
    });

    // filter out SPANs without style/class attribs
    PoorText.replaceSpan(cloned, function(oldSpan, newNode) {
        if (!oldSpan.hasAttribute('style')) {
            PoorText.replace_with_children(oldSpan);
        }
        return newNode;
    });

    // filter out remaining double tags, but let through BR (the 'b' in the char class, huh what a kludge!)
    var html = cloned.innerHTML;

    html.replace(/(<\/?[^>b]+>)\1/gi, "$1");

    node.innerHTML = html;

    return node;
};

/**@ignore*/
if (PoorText.config.useMarkupFilters) {
    PoorText.outFilters.push(PoorText.outFilterWebKit);
}

/**@ignore*/
PoorText.inFilterWebKit = function(node) {
    if (node.innerHTML == '') return node;

    // setup
    var elements       = $(node).childElements();
    var interesting    = /^(strong|b|em|i|u|del|strike|sub|sup)$/i;

    // filter map
    replaceMap = {
        strong : {fontWeight     : 'bold'},
        b      : {fontWeight     : 'bold'},
        em     : {fontStyle      : 'italic'},
        i      : {fontStyle      : 'italic'},
        u      : {textDecoration : 'underline'},
        del    : {textDecoration : 'line-through'},
        strike : {textDecoration : 'line-through'},
        sub    : {verticalAlign  : 'sub'},
        sup    : {verticalAlign  : 'super'}
    };

    // the workhorse
    function replaceNodes(orig) {
        // create the span
        var innermost = orig[orig.length-1];
        var content = innermost ? innermost.innerHTML : '';
        var span = new Element('span', {'class' : PoorText.AppleSpanClassName}).update(content);

        // set the SPAN's style
        orig.each(function(node) {
            span.setStyle(replaceMap[node.nodeName.toLowerCase()]);
        });

        // replace it
        orig[0].parentNode.replaceChild(span, orig[0]);

        return span;
    }

    // Walk the DOM, looking for parent/child markup sequences
    while (elements && elements.length) {
        var next = elements.shift();

        // parent/child/... sequences get stored in array
        if (Object.isArray(next)) {
            elm = next[next.length-1];
            acc = next;
        } else {
            elm = next;
            acc = [elm];
        }

        if (interesting.test(elm.nodeName)) {
            var firstChild = elm.firstChild;

            if (interesting.test(firstChild.nodeName)) {
                // interesting child, store in array
                acc.push(firstChild);
                // and look for the child's child
                elements.unshift(acc);
            } else {
                // no child: go ahead, replace it
                var span = replaceNodes(acc);
                // then consider its children
                elements = span.childElements().concat(elements);
            }
        } else {
            // not interesting: consider its children
            elements = elm.childElements().concat(elements);
        }
    }

    return node;
}

/**@ignore*/
if (PoorText.config.useMarkupFilters) {
    PoorText.inFilters.push(PoorText.inFilterWebKit);
}

/**
    Add onPaste event
*/
PoorText.events['paste'] = 'onPaste';

Object.extend(PoorText.prototype, {
    /**
       The element we want to make editable must be a DIV.  No text(area)
       elements allowed here.<br>
       If option deferIframeCreate is false, the iframe will be created on
       object creation.<br>
       If option deferIframeCreate is true, it will be created onMouseover
       the DIV.  In this case, the Iframe will only be activated when
       clicking the DIV.
       @param none
       @return nothing
       @private
    */
    makeEditable : function () {
        var srcElement = this.srcElement;

        srcElement.contentEditable = true;
        
        this.editNode = srcElement;
        this.eventNode = srcElement;
        this.styleNode = srcElement;
        this.frameNode = srcElement;
        this.document  = document;
        this.window    = window;
        
        // text fields should not wrap the text
        if (this.config.type == 'text') {
            var nobr = document.createElement('nobr');
            srcElement.wrap(nobr);
        }

        // Filter the input
        this.setHtml(this.srcElement, PoorText.inFilters);
        
        // Hook in default events
        var events = PoorText.events;
        for (type in events) {
            this.observe(type, 'builtin', this[events[type]], true);
        }
    },
         
    /**@ignore*/
    getStyle : function (style) {
        var node = PoorText.styleRE.test(style) ? this.styleNode : this.frameNode;
        return Element.getStyle((node || this.srcElement), style);
    },

    /**@ignore*/
    setStyle : function(css) {
        for (var attr in css) {
            attr = attr.camelize();
            if (PoorText.styleRE.test(attr)) {
                this.styleNode.style[attr] = css[attr];
            } else {
                this.frameNode.style[attr] = css[attr];
            }
        }
    },

    /**@ignore*/
    getLink : function () {
        var elm   = '';
        var sel   = this.window.getSelection();
        var range = sel.getRangeAt(0);
        
        if (sel == '') {
            // Are we placed within a unselected elm
            if (elm = this._getLinkFromInside(range.commonAncestorContainer)) {
                sel.selectAllChildren(elm);
                this.storeSelection();
                return {elm : elm};
            }
            else {
                return {msg : 'showAlert'};
            }
        }
        
        // Store selection
        this.storeSelection();

        // Try dblclick selection first (case 13)
        if (!elm) elm = this._getLinkFromOutside(sel, range.commonAncestorContainer.childNodes);
        
        // Try |<a>...|</a> (case 15, 17, 23, 24)
        if (!elm) elm = this._getLinkFromInside(range.endContainer.parentNode);
        
        // Try |<a>...</a>|, beginning in TextNode, ending in TextNode, a-tag is in between
        //                   (case 16, 18, 20, 22, 
        if (!elm) elm = this._getLinkFromOutside(sel, sel.anchorNode.parentNode.childNodes);
        
        // Try <a>|...|</a> (case 14, 19, 21)
        if (!elm) elm = this._getLinkFromInside(range.startContainer);

        return {elm : elm};
    },

    /**@ignore*/
    _getLinkFromInside : function(a) {
        while (a) {
            if (a.nodeName.toLowerCase() == 'a') return a;
            a = a.parentNode;
        }
        return null;
    },

    /**@ignore*/
    _getLinkFromOutside : function(sel, children) {
        for (i = 0; i < children.length; i++) {
            var child = children[i];
            if ((sel.containsNode(child, false)) && (child.nodeName.toLowerCase() == 'a')) {
                return child;
            }
        }
        return null;
    },

    selectNode : function(node) {
        var range = document.createRange();
        range.selectNode(node);
        var selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        return range;
    },

    getSelection : function() {
        // maybe get range object
        range = this.window.getSelection().getRangeAt(0);

        // get an index array used to find container nodes upon restoring
        var startContainer = PoorText.getRangeContainerIndices(range.startContainer, this.editNode);

        // create a bookmark
        var bookmark = {
            sc : startContainer,
            so : range.startOffset,
            ec : range.endContainer===range.startContainer
               ? startContainer
               : PoorText.getRangeContainerIndices(range.endContainer, this.editNode),
            eo : range.endOffset
        };

        return bookmark;
    },

    storeSelection : function() {
        var bookmark = this.getSelection();

        this.selection = bookmark;

        return bookmark;
    },

    restoreSelection : function(bookmark) {

        this.focusEditNode();

        if (!bookmark) {
            bookmark = this.selection;
        } else {
            this.selection = bookmark;
        }

        if (!bookmark) { return; }

        // create a range from our bookmark
        var range = document.createRange();
        range.setStart(PoorText.getRangeContainerNode(bookmark.sc, this.editNode), bookmark.so);
        range.setEnd(PoorText.getRangeContainerNode(bookmark.ec, this.editNode), bookmark.eo);

        // select the range
        var selection = this.window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        return range;
    },

    // Stolen from FCKeditor
    /**@ignore*/
    doAddHTML :function (tag, url, title) {
        // give execCommand() an object to act upon
        this.restoreSelection();

        // Delete old elm
        this.document.execCommand("unlink", false, null);
        
        // Generate a temporary name for the elm.
        var tmpUrl = 'javascript:void(0);/*' + ( new Date().getTime() ) + '*/' ;

        // Use the internal "CreateLink" command to create the link.
        this.document.execCommand('createlink', false, tmpUrl);
        
        // Retrieve the just created link using XPath.
        var elm = this.document.evaluate("//a[@href='" + tmpUrl + "']", 
                                         this.document.body, null, 9, null).singleNodeValue ;

        if (elm) {
            if (tag == 'a') {
                elm.href = url;
                elm.setAttribute('_poortext_url', url);
            }
            else {
                elm.setAttribute('href', '');
            }
            elm.setAttribute('_poortext_tag', tag);
            PoorText.setClass(elm, 'pt-' + tag);
            elm.setAttribute('title', title);
        }

        this.storeSelection();

        return elm;
    },
    
    /**@ignore*/
    doDeleteHTML :function() {
        this.restoreSelection();
        this.document.execCommand('unlink', false, null);
        this.window.getSelection().collapseToEnd();
        this.storeSelection();
    },

    /**
       Dropin replacement for execCommand('selectall').  Unlike
       'selectall', this method toggles the selection. It also implements
       some hackery to avoid that the editNode DIV gets removed, if
       toggleSelectAll() is followed by execCommand('cut').
       @returns true
       @private
    */
    toggleSelectAll : function() {
        var selection = this.window.getSelection();
        var range;
        
        if (this.selectedAll) {
            if (this.selectedAllSelection) {
                // restore the cursor position
                try {
                    // fails when deleting the selection
                    this.restoreSelection(this.selectedAllSelection);
                } catch(e) {
                    // hence restore
                    this.storeSelection();
                }

                // reset state
                this.selectedAll = false;
                this.stopObserving('click', 'toggleSelectAll');
                this.stopObserving('keypress', 'toggleSelectAll');
            }
        }
        else {
            // remember the cursor position
            this.selectedAllSelection = this.getSelection();
            this.selectedAll = true;

//            // select the editNode's children
//            range = this.document.createRange();
//            range.selectNodeContents(this.editNode);
//            selection.removeAllRanges();
//            selection.addRange(range);

            // selectall
            document.execCommand('selectall', false, null);
            
            this.observe('click', 
                         'toggleSelectAll', 
                         function() {
                this.toggleSelectAll();
            }, true);
            
            this.observe('keypress', 
                         'toggleSelectAll', 
                         function(event) {
                if (event.ctrlKey == true) return true;
                // Let the default action be taken
                setTimeout(function() {this.toggleSelectAll()}.bind(this), 1);
            }, true);
        }
        return true;
    },

    /**@ignore*/
    markup : function(cmd) {
        this.restoreSelection();
        this.document.execCommand(cmd, false, null);
        this.storeSelection();
    },

    /**@ignore*/
    focusEditNode : function() {
        this.editNode.focus();
    },

    /**@ignore*/
    selectionCollapseToEnd : function () {
        var selection = this.window.getSelection();
        if (selection) selection.collapseToEnd();
    },

    /**
       Method called onKeyUp to do browser-specific things.
       @param Object PoorText
       @return none
       @private
    */
    afterOnKeyUp : function(event) {
        this.storeSelection();
    },

    /**@ignore*/
    filterAvailableCommands : function () {
        return this.config.availableCommands.select(function(cmd) {
            return ! /cut|copy|paste/.test(cmd);
        });
    },

    insertHTML : function(html, viaButton) {
        this.document.execCommand('insertHTML', false, html);
        this.storeSelection();
    },

    undo : function() {
        this.markup('undo');
    },

    afterShowHideSpecialCharBar : function() {
        this.restoreSelection();
    },

    /**
       Handler called onPaste events
       @param {EVENT} event
       @returns nothing
       @private
    */
    onPaste : function(event) {
        setTimeout(function() {
            this.applyFiltersTo(this.editNode, PoorText.pasteFilters);
            this.restoreSelection();
        }.bind(this), 10);
    }

});

/**
   Clean the pasted text: If a node is of an allowed type, leave it
   alone. If it is not allowed (pasted text comes from the outside
   world), replace it with its text content.<br>
   <br>Exceptions from this rule:</b>
   If node is a DIV, replace it with its children.<br>
   If node is a P, insert two BR before it and replace node with its children.
   @param none
   @return true if editNode was clean, false otherwise
   @type Boolean
       @private
*/
PoorText.blockLevelPasteFilter = function(editNode) {

    // Begin with the editNode's children
    var nodes = $A(editNode.childNodes);
        
    while (nodes && nodes.length) {
        var node = nodes.shift();
            
        // only consider HTMLElement nodes
        if (node && node.nodeType == 1) {
            var nodeName = node.nodeName.toLowerCase();

            // replace <div> with its children
            if (nodeName == 'div') {
                PoorText.replace_with_children(node, nodes);
                continue;
            }

            // replace <p> with <br/><br/> plus P's children
            if (nodeName == 'p') {
                node.parentNode.insertBefore(document.createElement('br'), node);
                node.parentNode.insertBefore(document.createElement('br'), node);
                PoorText.replace_with_children(node, nodes);
                continue;
            }

            // chop all other tags
            if (! PoorText.allowedTagsRE.test(node.nodeName)) {
                // disallowed node -> replace with its textContent
                var parent = node.parentNode;

                if (parent) {
                    var text = node.textContent;
                    var textNode = document.createTextNode(text);
                    parent.replaceChild(textNode, node);
                }
                    
                clean = false;
                continue;
            } else if (nodeName == 'a') {
                // style attrib is inserted on some LINK/ABBR/ACRONYM conversions
                node.removeAttribute('style');
            }

            // consider the children
            if (node.hasChildNodes()) {
                $A(node.childNodes).each(function(n) {
                    if (n && n.nodeType == 1) nodes.unshift(n);
                });
            }
        }
    }
    return editNode;
}

PoorText.spanFilter = function(editNode) {
    // clean Apple's extra SPANs
    var spanStyles = $A([
        // CSS rule         value           
        ['font-weight',     'bold'        ],
        ['font-style',      'italic'      ],
        ['text-decoration', 'underline'   ],
        ['text-decoration', 'line-through'],
        ['vertical-align',  'sub',        ], 
        ['vertical-align',  'super',      ],
        ['font-weight',     'normal'      ]
    ]);

    $$('span').each(function(span) {
            console.log(span);
        var newStyles = 0;
        var styles = {};

        // create our own inline CSS
        spanStyles.each(function(spec) {
            if (span.getStyle(spec[0]) == spec[1]) {
                styles[spec[0].camelize()] = spec[1];
                newStyles = 1;
            }
        });

        // get rid of old inline CSS
        span.removeAttribute('style');

        // maybe set new style
        if (newStyles) {
            // set our styles
            span.setStyle(styles);
        } else {
            PoorText.replace_with_children(span);
        }
    });

    return editNode;
}

PoorText.replace_with_children = function(node, nodes) {
    var parent = node.parentNode;
    $A(node.childNodes).each(function(child) {
        parent.insertBefore(child, node);
        if (nodes) nodes.push(child);
    });
    parent.removeChild(node);
    return parent;
}

PoorText.pasteFilters = [
    PoorText.inFilterWebKit,
    PoorText.spanFilter, // does not work as intended :(
    PoorText.addUrlProtection,
    PoorText.blockLevelPasteFilter,
];


/**@ignore*/
Object.extend(PoorText.Popup, {
    positionIt : function(popup, which) {
        // With fixed position
        if (PoorText.Popup.pos[which].center) {
            // center on popup creation
            PoorText.Popup.pos[which].center = false;
            
            centerX = Math.round(window.innerWidth / 2) 
                - (popup.offsetWidth  / 2) + 'px';
            
            centerY = Math.round(window.innerHeight/ 2) 
                - (popup.offsetHeight / 2) + 'px';
            
            popup.setStyle({left: centerX, top: centerY});
        }
    },

    afterClosePopup : function() {
        if (PoorText.focusedObj) {
            PoorText.focusedObj.restoreSelection();
        }

    }
});

PoorText.getHref = function(element) {
    return element.getAttribute('href');
}

PoorText.setClass = function(elm, className) {
    elm.setAttribute('class', className);
}

PoorText.__enterKeyHandler = function(pt) {
    pt.keyHandlerFor['enter'] = function() {
        document.execCommand('insertlinebreak', false, null);
    };
}


/**
   onDOMContentLoaded for Safari
   borrowed from Dean Edwards
*/
if (/WebKit/i.test(navigator.userAgent)) { // sniff
    var _timer = setInterval(function() {
        if (/loaded|complete/.test(document.readyState)) {
            PoorText.onload(); // call the onload handler
        }
    }, 10);
}
