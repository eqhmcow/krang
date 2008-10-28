/** @fileoverview
    Gecko specific code
*/

/**
   The opening part of the HTML string written to the iframe document
   when using iframes.  It ends right before the closing HEAD tag.
   @type Class String
*/
PoorText.iframeSrcStart = '<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.0//EN" "http://www.w3.org/TR/REC-html40/strict.dtd"><html><head><style type="text/css">body { margin:0; padding:0 }</style>';

/**
   The closing part of the HTML string written to the iframe
   document. It begins with the closing HEAD tag and ends with the
   closing HTML tag.
   @type Class String
*/
PoorText.iframeSrcEnd = '</head><body><br/></body></html>';

/**
   Array of 'framing' CSS properties we copy from the {@link
   #srcElement} to {@link #frameNode}.
   @type Class Array
   @private
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
PoorText.allowedTagsRE = /^(a|abbr|acronym|b|br|del|em|i|strike|strong|sub|sup|u)$/i;

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

// Gecko specific output filtering
/**@ignore*/
PoorText.outFilterGecko = function(node, isTest) {

    var html;

    if (isTest) {
        html = node;
    } else {
        html = node.innerHTML;
    }

    // replace <b> with <strong>
    html = html.replace(/<(\/?)b(\s|>|\/)/ig, "<$1strong$2")

               // replace <i> with <em>
               .replace(/<(\/?)i(\s|>|\/)/ig, "<$1em$2")

    node.innerHTML = html;

    return node;
};

/**@ignore*/
if (PoorText.config.useMarkupFilters) {
    PoorText.outFilters.push(PoorText.outFilterGecko);
}

/**@ignore*/
PoorText.inFilterGecko = function(node) {
    var html = node.innerHTML;

    // replace <strong> with <b>
    html = html.replace(/<(\/?)strong(\s|>|\/)/ig, "<$1b$2")

               // replace <em> with <i>
               .replace(/<(\/?)em(\s|>|\/)/ig,     "<$1i$2")

    node.innerHTML = html;

    return node;
}

/**@ignore*/
if (PoorText.config.useMarkupFilters) {
    PoorText.inFilters.push(PoorText.inFilterGecko);
}

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

        if (this.config.deferIframeCreation) {
            // Using mouse
            srcElement.addEventListener('mouseover', this._makeEditable.bindAsEventListener(this), false);
        } else {
            this._makeEditable();
        }
    },

/**@ignore*/
    _makeEditable : function (event) {
        if (event)  Event.stop(event);
        // Make sure we are only run once when called as mouseover event
        // Just removing the event listener doesn't happen soon enough
        if (this.isLoading) return;
        this.isLoading = true;

        // srcElement's styles
        this.ptStyles = window.getComputedStyle(this.srcElement, null);
        
        // make sure srcElement has non-transparent background
        if (this.srcElement.getStyle('backgroundColor').toLowerCase() == 'transparent') {
            this.srcElement.setStyle({backgroundColor : '#fff'});
        }
        
        this._prepareContainerAndCreateIframe();

        this._initIframe();
    },

/**@ignore*/
    _prepareContainerAndCreateIframe : function() {
        var ptStyles = this.ptStyles;
        // Make container for ptElement and iframe
        var container = document.createElement('div');
        container.id = this.id+'_container';
        container.style.top = ptStyles.top;
        container.style.left = ptStyles.left;
        container.style.cssFloat = ptStyles.cssFloat;
        var position      = ptStyles.position;
        container.style.position = position == 'static' ? 'relative' : position;
        var marginTop     = parseInt(ptStyles.marginTop);
        var marginRight   = parseInt(ptStyles.marginRight);
        var marginBottom  = parseInt(ptStyles.marginBottom);
        var marginLeft    = parseInt(ptStyles.marginLeft);
        var borderTop     = parseInt(ptStyles.borderTopWidth);
        var borderRight   = parseInt(ptStyles.borderRightWidth);
        var borderBottom  = parseInt(ptStyles.borderBottomWidth);
        var borderLeft    = parseInt(ptStyles.borderLeftWidth);
        var paddingTop    = parseInt(ptStyles.paddingTop);
        var paddingRight  = parseInt(ptStyles.paddingRight);
        var paddingBottom = parseInt(ptStyles.paddingBottom);
        var paddingLeft   = parseInt(ptStyles.paddingLeft);
        var width         = parseInt(ptStyles.width);
        var height        = parseInt(ptStyles.height);
        container.style.width  = (marginLeft + borderLeft + paddingLeft 
                                  + width
                                  + paddingRight + borderRight + marginRight) + 'px';
        container.style.height = (marginTop + borderTop + paddingTop
                                  + height 
                                  + paddingBottom + borderBottom + marginBottom) + 'px';
        // Put ptElement inside the container
        var srcElement = this.srcElement;
        srcElement = srcElement.parentNode.replaceChild(container, srcElement);
        container.appendChild(srcElement);
        srcElement.style.position = 'absolute';
        srcElement.style.top = '0px';
        srcElement.style.left = '0px';
        srcElement.style.width = width + 'px';
        srcElement.style.height = height + 'px';
        
        // Create Iframe
        var iframe = document.createElement('iframe');
        iframe.setAttribute('id', this.id+'_iframe');
        
        // Style it like the DIV
        iframe.style.width  = width  + paddingLeft + paddingRight  + 'px';
        iframe.style.height = height + paddingTop  + paddingBottom + 'px';
        PoorText.iframeStyles.each(function(style) {
            iframe.style[style] = ptStyles[style];
        });
        
        // Place it below the DIV
        iframe.style.position = 'absolute';
        container.insertBefore(iframe, srcElement);
        this.iframe = iframe;
    },

    /**@ignore*/
    _initIframe : function () {
        
        if (this.isLoaded) return;
        
        // Try to init the iframe until init succeeds
        try {
            this.document = this.iframe.contentDocument;
            this.window   = this.iframe.contentWindow;
            
            if (!this.document) {
                setTimeout(function() {this._initIframe()}.bind(this), 50);
                return false;
            }
        } catch (e) {
            setTimeout(function() {this._initIframe()}.bind(this), 50);
            return false;
        }
        
        this.isLoaded = true;
        
        // Write the the HTML structure
        var doc = this.document;
        doc.open();
        doc.write(PoorText.iframeSrcStart
                  +this.config.iframeHead
                  +PoorText.iframeSrcEnd
                  );
        doc.close();

        this._finishIframe();
    },
    
    /**@ignore*/
    _finishIframe : function() {
        
        if (!this.document.body || !this.document.body.replaceChild) {
                setTimeout( function() { this._finishIframe() }.bind(this), 50);
                return false;
        } else {
            // Create EditNode
            this._createEditNode();

            // Apply inFilters
            this.setHtml(this.srcElement, PoorText.inFilters);

            // make cursor visible when there's no text
            if (/^\s*$/.test(this.editNode.innerHTML)) {
                this.editNode.innerHTML = '<br>';
            }
                
            // Finally make it editable
            this.document.designMode = 'on';
                
            // The Node to style attributes enumerated in PoorText.bodyStyles
            this.styleNode = this.document.body;
                
            // The Node to style attributes enumerated in PoorText.iframeStyles
            this.frameNode = this.iframe;
                
            // The Node receiving events
            this.eventNode = this.document;
                
            // Hook in default events
            var events = PoorText.events;
            for (type in events) {
                this.observe(type, 'builtin', this[events[type]], true);
            }
                
            // Don't use SPAN tags for markup
            try {
                this.document.execCommand('styleWithCSS', false, false);
            }
            catch(e) {
                this.document.execCommand('useCSS', false, true);
            }
                
            // Style the iframe's body like the DIV
            var ptStyles = this.ptStyles;
            var body = this.document.body;
            PoorText.bodyStyles.each(function(style) {
                body.style[style] = ptStyles[style];
            });

            // Install iframe activation handlers
            if (this.config.deferIframeCreation) {
                Event.observe(this.srcElement, 'click',
                              this._activateIframe.bindAsEventListener(this), true);
            } else {
                this._activateIframe();
            }
        }
    },

    _createEditNode : function() {
        var editNode = document.createElement('div');
        var editNode = new Element('div', { id : 'pt-edit-node' });
        var body = this.document.body;
        body.replaceChild(editNode, body.firstChild);
        this.editNode = body.firstChild;
    },

    _recreateEditNode : function() {
        // create the editNode DIV as the first body child
        this._createEditNode();

        // care for text flavor fields
        if (this.config.type == 'text') this.editNode.setAttribute('class', 'pt-text-height');

        // add the break
        var br = document.createElement('br');
        this.editNode.appendChild(br);

        // When recreating, place cursor within editNode and
        // before the break
        var range = this.window.getSelection().getRangeAt(0);
        range.selectNode(br);
        range.collapse(true); // collapse to range start
    },

    /**@ignore*/
    _activateIframe : function (event) {
        if (event) Event.stop(event);
        var srcElement = this.srcElement;
        if (srcElement) {
            if (this.config.deferIframeCreation) {
                Event.stopObserving(this.srcElement, 'click');
            }
            srcElement.hide();
            this.window.focus();
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
                return {elm : elm};
            }
            else {
                return {msg : 'showAlert'};
            }
        }
        
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

    storeSelection : function(range) {
        if (!range) range = this.window.getSelection().getRangeAt(0);
        this.selection = range;
    },

    restoreSelection : function(range) {
        if (!range)  range = this.selection;
        var selection = this.window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);

    },

    // Stolen from FCKeditor
    /**@ignore*/
        doAddHTML :function (tag, url, title) {
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
        return $(elm);
    },
    
    /**@ignore*/
    doDeleteHTML :function() {
        this.document.execCommand('unlink', false, null);
        this.window.getSelection().collapseToEnd();
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
            // restore the cursor position
            this.restoreSelection(this.selectedAllSelection);

            // clean up
            this.selectedAll = false;
            this.stopObserving('click', 'toggleSelectAll');
            this.stopObserving('keypress', 'toggleSelectAll');
        }
        else {
            // store the cursor position
            this.selectedAllSelection = selection.getRangeAt(0);
            
            // select the editNode's children
            range = this.document.createRange();
            range.selectNodeContents(this.editNode);
            selection.removeAllRanges();
            selection.addRange(range);
            
            this.selectedAll = true;

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
        this.document.execCommand(cmd, false, null);
    },

    /**@ignore*/
    focusEditNode : function() {
        this.window.focus();
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
    },

    /**@ignore*/
    filterAvailableCommands : function () {
        return this.config.availableCommands.select(function(cmd) {
            return ! /cut|copy|paste/.test(cmd);
        });
    },

    insertHTML : function(html, viaButton) {
        this.document.execCommand('insertHTML', false, html);
    },

    undo : function() {
        this.document.execCommand('undo', false, null);
        var sel = this.getLink();
        if (sel.elm) {
            PoorText.setClass(sel.elm, 'pt-'+sel.elm.getAttribute('_poortext_tag'));
        }
    },

    // when pressing DOWN remove last BR when previousSibling is *not* a BR
    _down : function() {
        var lastElement = this.editNode.lastChild;
        if (lastElement
            && lastElement.nodeName.toLowerCase() == 'br'
            && lastElement.previousSibling.nodeName.toLowerCase() != 'br'
            ) {
            this.editNode.removeChild(lastElement);
        }
    },

    afterShowHideSpecialCharBar : function() {
    },

    __afterKeyDispatch : function(keyname) {
        // Clean pasted text
	if (keyname == 'ctrl_v') {
	    setTimeout(function() {
                this.applyFiltersTo(this.editNode, PoorText.pasteFilters);
	    }.bind(this), 1);
	}
        // tame the cursor at line end
        if (keyname == 'down') {
            setTimeout(function() {
                this._down();
            }.bind(this), 10);
        }
        // make sure we always have an editNode
        if (keyname == 'backspace' || keyname == 'delete') {
            if (this.styleNode.firstChild.nodeName.toLowerCase() == 'br') {
                this._recreateEditNode();
            }
        }
    },

});

/**
   Clean the pasted text: If a node is of an allowed type, leave it
   alone. If it is not allowed (pasted text comes from the outside
   world), replace it with its text content.<br>
   <br>Exceptions from this rule:</b>
   If node is a DIV, replace it with its children.<br>
   If node is a P, insert two BR before it and replace node with its children.
   @param {Node} node This is our editNode
   @return true if editNode was clean, false otherwise
   @type Boolean
   @private
*/
PoorText.blockLevelPasteFilter = function(editNode) {

    // Begin with the editNode's children
    var nodes = $A(editNode.childNodes);

    while (nodes && nodes.length) {
        var node = nodes.pop();

        // only consider HTMLElement nodes
        if (node && node.nodeType == 1) {
            var tagName = node.tagName.toLowerCase();
            
            // replace <div> with its children
            if (tagName == 'div') {
                    PoorText.replace_with_children(node, nodes);
                    continue;
            }

            // replace <p> with <br/><br/>
            if (tagName == 'p') {
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
                continue;
            }

            // consider the children
            if (node.hasChildNodes()) {
                $A(node.childNodes).each(function(n) {
                    if (n && n.nodeType == 1) nodes.push(n);
                });
            }
        }
    }

    return editNode;
};

PoorText.inlineLevelPasteFilter = function(node) {
    var html = node.innerHTML;

    // replace <del> with <strike>
    html = html.replace(/<(\/?)del(\s|>|\/)/ig, "<$1strike$2")

    node.innerHTML = html;

    return node;
}

PoorText.replace_with_children = function(node, nodes) {
    var parent = node.parentNode;
    $A(node.childNodes).each(function(child) {
        parent.insertBefore(child, node);
        nodes.push(child);
    });
    parent.removeChild(node);
}

PoorText.pasteFilters = [
    PoorText.blockLevelPasteFilter,
    PoorText.inFilterGecko,
    PoorText.inlineLevelPasteFilter,
    PoorText.addUrlProtection
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
        setTimeout(function() {
            /* When called by the keydown handler of the URL or TITLE
               field in this.addHTMLDialog(), this.closePopup
               triggers the following error in FF < 2.0 (1.8.1). 
               
               [Exception... "'Permission denied to set property
               XULElement.selectedIndex' when calling method:
               [nsIAutoCompletePopup::selectedIndex]" nsresult: "0x8057001e
               (NS_ERROR_XPC_JS_THREW_STRING)" location: ...
            */
            try { PoorText.focusedObj.window.focus() } catch(e) {} // keep Gecko happy
        }.bind(this), 50);
    }
});

PoorText.getHref = function(element) {
    return element.getAttribute('href');
}

PoorText.setClass = function(elm, className) {
    elm.setAttribute('class', className);
}

/**
   onDOMContentLoader for Mozilla/Opera
*/
if (document.addEventListener) {
    document.addEventListener(
        "DOMContentLoaded",
	PoorText.onload,
	false);
}
