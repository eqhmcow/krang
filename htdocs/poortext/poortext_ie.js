/** @fileoverview
    MSIE specific code
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

// IE specific output filtering
/**@ignore*/
PoorText.outFilterIE = function(node, isTest) {

    var html;

    if (isTest) {
        html = node;
    } else {
        html = node.innerHTML;
    }

    // do whatever you want to html

    return html;
};

/**@ignore*/
if (PoorText.config.useMarkupFilters) {
    PoorText.outFilters.push(PoorText.outFilterIE);
}

/**@ignore*/
PoorText.inFilterIE = function(node) {
    if (node.innerHTML == '') return node;

    var html = node.innerHTML;

    // do whatever you want to html

    node.innerHTML = html;

    return node;
}

/**
         Cut / Copy / Paste

   When cutting/copying PT-internal text, copy *with* markup.

   When copying from external source, copy text only.

*/
PoorText.events['cut']   = 'onCut';
PoorText.events['copy']  = 'onCopy';
PoorText.events['paste'] = 'onPaste';

/**@ignore*/
if (PoorText.config.useMarkupFilters) {
    PoorText.inFilters.push(PoorText.inFilterIE);
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

        srcElement.contentEditable = true;
        
        this.editNode  = srcElement;
        this.eventNode = srcElement;
        this.styleNode = srcElement;
        this.frameNode = srcElement;
        this.document  = document;
        this.window    = window;
        
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

        // maybe selected text
        var text = this.selection.text;
        
        // are we placed within a link?
        var elm     = this.selection.parentElement();
        var tagName = elm.tagName.toLowerCase();

        // no text selected and not within a link
        if (tagName != 'a' && text == '') {
            return {msg : "showAlert"};
        }

        // some text selected, but not (only) a link
        if (tagName != 'a') return {};

        // got an existing link: expand the selection
        this.selection.moveToElementText(elm);

        return {elm : elm};
    },

    storeSelection : function(range) {
        if (!range) range = document.selection.createRange();
        this.selection = range;
    },

    restoreSelection : function() {
        if (this.selection) this.selection.select();
    },

    // Stolen from FCKeditor
    /**@ignore*/
    doAddHTML : function (tag, url, title, range) {

        // where are we?
        this.restoreSelection();

        // Delete old elm
        this.document.execCommand("unlink", false, null);
        
        // Generate a temporary name for the elm.
        var tmpUrl = 'javascript:void(0);/*' + ( new Date().getTime() ) + '*/' ;
        
        // Use the internal "CreateLink" command to create the link.
        this.document.execCommand('createlink', false, tmpUrl);
        
        // Retrieve the just created link
        var elm =  $$('a').find(function(link) {
            return PoorText.getHref(link) == tmpUrl;
        });
        
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

        return elm;
    },

    /**@ignore*/
    doDeleteHTML : function(range) {

        // gimmi something to chew
        this.restoreSelection();

        // delete link
        document.execCommand('unlink', false, null);

        // goto end of word
        this.selection.collapse(false);
        this.restoreSelection();
    },

    /**
       Dropin replacement for execCommand('selectall').  Unlike
       'selectall', this method toggles the selection.  It also makes sure
       that the cursor position is restored when deselecting.
       @returns true
       @private
    */
    toggleSelectAll : function() {
        
        var range = document.selection.createRange();

        if (this.selectedAll) {
            // restore the cursor position
            if (this.selectedAllSelection) this.selectedAllSelection.select();

            // reset state
            this.selectedAll = false;
            this.stopObserving('click', 'toggleSelectAll');
            this.stopObserving('keydown', 'toggleSelectAll');
            
        } else {
            // remember the cursor position
            this.selectedAllSelection = document.selection.createRange();
            this.selectedAll = true;
            
            // select all
            document.execCommand('selectAll', false, null);
            
            // register handlers
            this.observe('click', 
                         'toggleSelectAll', 
                         function(event) {
                this.toggleSelectAll();
                Event.stop(event);
            }, true);
            
            this.observe('keydown', 
                         'toggleSelectAll', 
                         function(e) {
                if (e.ctrlKey == true) return;
                // gimmi the focus for edit commands
                this.editNode.focus();
                this.selectedAll = false;
                this.stopObserving('click', 'toggleSelectAll');
                this.stopObserving('keydown', 'toggleSelectAll');
            }, true);
        }
        return true;
    },

    /**@ignore*/
    markup : function(cmd) {
        // don't use the bookmark here: it messes up cut/copy selections
        this.editNode.focus();
        
        // get the selected range
        var range = document.selection.createRange();
        
        // mark it up
        this.document.execCommand(cmd, false, null);
        
        // make cursor visible again
        setTimeout(function() {
            range.select();
        },1);
        
    },

    /**@ignore*/
    selectionCollapseToEnd : function () {
        // IE collapses selections automatically onBlur.
        // That's why we do nothing here   
    },

    /**@ignore*/
    filterAvailableCommands : function () {
        return this.config.availableCommands;
    },

    /**
       Method called onKeyUp to do browser-specific things.
       @param Object PoorText
       @return none
       @private
    */
    afterOnKeyUp : function(event) {
        // store our position
        this.storeSelection();
    },

    /**@ignore*/
    focusEditNode : function() {
        this.editNode.focus();
    },

    insertHTML : function(html, viaButton) {
        var range;
        if (viaButton) {
            setTimeout(function() {
                this.editNode.focus();
                range = document.selection.createRange();
                range.pasteHTML(html);
            }.bind(this),10);
        } else {
            range = document.selection.createRange();
            range.pasteHTML(html);
        }
    },

    undo : function() {
        this.markup('undo');
    },

    afterShowHideSpecialCharBar : function() {
        this.editNode.focus();
    },

    onCut : function(event) {
        this._onCutCopy(event);
    },

    onCopy : function(event) {
        this._onCutCopy(event);
    },

    _onCutCopy : function(event) {
        // remember internal cut or copy
        var range = document.selection.createRange();
        if (range) {
            PoorText._internalPasteText = range.text;
        }
    },

    onPaste : function(event) {
        // internal paste: copy with markup
        var clipText = window.clipboardData.getData('Text');
        if (clipText == PoorText._internalPasteText) return;
        
        // extermal paste: copy text only
        var range = document.selection.createRange();
        range.pasteHTML(window.clipboardData.getData('Text'));
        Event.stop(event);
    }
});

/**@ignore*/
Object.extend(PoorText.Popup, {
    positionIt : function(popup, which) {
        // Position it absolutely
        var popup = $('pt-popup-'+which);
        
        var currPopupW = popup.offsetWidth;
        var currPopupH = popup.offsetHeight;
        
        var oldPopupW  = PoorText.Popup.pos[which].oldPopupW;
        var oldPopupH  = PoorText.Popup.pos[which].oldPopupH;
        
        //    // Center it if the popup dimensions did change (popup content changed)
        //    if (currPopupW != oldPopupW || currPopupH != oldPopupH) {
        //	PoorText.popupPos[which].deltaX = 0;
        //	PoorText.popupPos[which].deltaY = 0;
        //    }
        
        var windowDimensions  = document.viewport.getDimensions();
        var scrollOffsets     = document.viewport.getScrollOffsets();
        
        centerX = Math.round(windowDimensions.width  / 2) 
            - (currPopupW  / 2)
            + scrollOffsets.left;
        
        var realX = centerX - PoorText.Popup.pos[which].deltaX + 'px';
        
        centerY = Math.round(windowDimensions.height / 2) 
            - (currPopupH / 2)
            + scrollOffsets.top;
        
        var realY = centerY - PoorText.Popup.pos[which].deltaY + 'px';
        
        popup.setStyle({left: realX, top: realY});
        
        PoorText.Popup.pos[which].centerX   = centerX;
        PoorText.Popup.pos[which].centerY   = centerY;
        PoorText.Popup.pos[which].oldPopupW = currPopupW;
        PoorText.Popup.pos[which].oldPopupH = currPopupH;
    },

    afterClosePopup : function() {
        // restore selection
        if (PoorText.focusedObj) {
            PoorText.focusedObj.focusEditNode();
            PoorText.focusedObj.restoreSelection();
        }
    }
});

PoorText.getHref = function(element) {
    return element.getAttribute('href', 2);
}

PoorText.__abbrFixIE6 = function (node) {
    var html = node.innerHTML;

    // replace <abbr> with our special <a> tag
    html = html.replace(/<abbr title\="?([^\">]+)"?>([^<]+)<\/abbr>/ig,
                        '<a class="pt-abbr" title="$1" _poortext_tag="abbr">$2</a>');

    node.innerHTML = html;
}

PoorText.__enterKeyHandler = function(pt) {
    pt.keyHandlerFor['enter'] = function() {
        this.insertHTML('<br>');
        document.selection.createRange().select(); // move cursor to the next line
    };
}

PoorText.setClass = function(elm, className) {
    elm.setAttribute('className', className);
}

document.onreadystatechange = function() {
    if (document.readyState == 'complete') {
        PoorText.onload();
    }
}
