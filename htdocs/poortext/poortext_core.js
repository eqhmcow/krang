var PoorText;

/** @fileoverview
    Core functionality for PoorText elements
*/

/** PoorText provides basic markup and link insertion capabilities to HTMLDivElements.
    @class 
    PoorText turns DIV elements in text input fields or textarea
    elements of a special kind, allowing for what CMS systems really need:
    basic markup plus link insertion plus phrase tags.
    @constructor
    @requires prototype-1.6.0.js -- the wellknown Ajax library, as well as Scriptaculous' effects.js and dragdrop.js
    @param {STRING|HTMLDivElement} element The HTMLDivElement to turn into a PoorText element.
    @param {Object} config An element-specific configuration object
    overriding the global config in {@link PoorText#config}
    @return PoorText
*/
PoorText = function (element, config) {
    /**
       The DIV element we want to turn into a PoorText element.
       @type Node
       @private
    */
    this.srcElement = '';

    /**
       The ID of the DIV element we want to turn into a PoorText element.
       @type String
       @private
    */
    this.id = '';

    // Record element and id
    this.srcElement = $(element);
    this.id         = this.srcElement.id;

    /**
       Flag to indicate whether the element has focus
       @type Boolean
       @private
    */
    this.focused = false;


    /**
       The node whose innerHTML will be edited.
       @type Node
       @private
    */
    this.editNode = null;
    
    /**
       The hidden form field used to return content.  It will be created
       on the fly.  It's ID will be this.id+'_return'
       @type Node
       @private
    */
    this.returnHTML = null;
    
    /**
       The hidden form field used to return the indent.  It will be
       created on the fly.  It's ID will be this.id+'_indent'.
       @type Node
       @private
    */
    this.returnIndent = null;
    
    /**
       The hidden form field used to return the text alignment.  It
       will be created on the fly.  It's ID will be this.id+'_align'
       @type Node
       @private
    */
    this.returnAlign = null;
    
    /**
       The window object where editing takes place.  When using iframes
       this object differs from the main window.
       @type Window
       @private
    */
    this.window = null;
    
    /**
       The document object where editing takes place. When using iframes
       this object differs from the global document object.
       @type HTMLDocument
       @private
    */
    this.document = null;
    
    /**
       The node receiving 'body styling'.  When using iframes some
       styles are effectively the styles applied to the body of the
       iframe's document.  These styles are enumerated in the class
       array {@link PoorText#bodyStyles}.
       @type Node
       @private
    */
    this.styleNode = null;
    
    /**
       The node receiving 'frame styling'. When using iframes some
       styles are indeed the styles applied to the iframe itsself.
       These styles are enumerated in the class array {@link
       PoorText#iframeStyles}
       @type Node
       @private
    */
    this.frameNode = null;
    
    /**
       The node receiving editing events.
       @type Node
       @private
    */
    this.eventNode = null;
    
    /**
       The browser-specific selection object updated on event
       keyup. Not used when using an iframe (Firefox).
       @type Range
       @private
    */
    this.selection = null;

    /**
       The selection existing before selecting all via {@link
       toggleSelectAll()} and restored afterwards.
       @type Range
       @private
    */
    this.selectedAllSelection = null;

    /**
       Flag indicating whether the content of editNode has been selected via this.selectall();
       @type Boolean
       @private
    */
    this.selectedAll = false;

    /**
       Object holding the selected link element (key name: elm) and
       the selected range (key name: range) when modifying the
       attributes of an existing link, abbreviation or acronym.
    */
    this.selected = {};

    /** 
	Hash of key event handlers for ctrl_[alt_][shift_]x key events triggering editing commands.
	@type Object
	@private
    */
    this.keyHandlerFor = {};    

    /**
       Array of event handlers registered on this elements eventNode.
       @type Array
       @private
    */
    this.eventHandlers = new Object();

    /**
       Flag to remember whether the specialCharBar (scb) is/was/should again be visible or not
       @type Boolean
       @private
    */
    this.scbVisible = false;
    
    /**
       Instance method to initialize PoorText elements.
       @param {Object} config
       @private
    */
    this.initialize(config);
}

/**
   Default css classname of PoorText elements (used by {@link
   PoorText#generateAll} and auto-generation).  All DIV elements
   having this CSS classname will be turned into PoorText elements if
   {@link PoorText#autoload} is true.
   This class name is 'poortext'.
   @type String
   @final
*/
PoorText.cssClass = 'poortext';

/**
   If true, turn all DIVs having a CSS classname of {@link PoorText#cssClass}
   into PoorText elements -- via {@link PoorText#generateAll}.
   @type Class bool
*/
PoorText.autoload = true;

/**
   Array of all created PoorText objects.
   @type Class Array
   
*/
PoorText.objects = new Array();

/**
   Mapping {@link #id}s to corresponding PoorText objects.
   @type Class Object
*/
PoorText.id2obj = new Object();

/**
   Pointer to object of currently focused PoorText element.
   @type PoorText
*/
PoorText.focusedObj = null;

/**
   Name map of event handlers installed on editable HTMLDivElements.
   Maps 'focus' to 'onFocus' etc.
   The absence of an onBlur handler is on purpose: The class method
   {@link PoorText#onBlur} takes care or it.
   @type Object
   @final
   @private
*/
PoorText.events = 
  {
    focus    : 'onFocus',
    keydown  : 'onKeyDown',
    keyup    : 'onKeyUp',
    click    : 'onKeyUp',
    dblclick : 'onKeyUp'
  };

/**
   Stringify method for PoorText object.
   @return the name of this class
   @type String
   @private
   @final
*/
PoorText.toString = function() { return 'PoorText' }

/**
   Filter correcting some html messup.
   1. compress <i>s</i><i>ix</i> to <i>six</i>
   2. chop empty markup tags
   @param {Node} node The node whose innerHTML will we corrected
   @return the node with its innerHTML corrected
   @type Node
   @private
*/
PoorText.correctMarkup = function(node) {
  var html = node.innerHTML;
  html = html.replace(/<\/([^>]+)><\1>/g   , ""  )  // compress <i>s</i><i>ix</i> to <i>six</i>
             .replace(/<([^<]+)>\s+<\/\1>/g, " " )  // chop whitespace only tags and collapse white space
             .replace(/<([^<]+)><\/\1>/g   , ""  )  // chop empty tags

             // collapse whitespace
             .replace(/(?:&nbsp;)+/g, ' ')
             .replace(/\u00A0+/g, ' ') // this is &nbsp; in unicode: WebKit prefers this
             .replace(/\s+/g, ' ')

             // remove <br> at end, while taking care of trailing closing tags and possible whitespace
             .replace(/(?:<br>\s*)+\s*((?:<\/[^>]+>)*)\s*$/, '$1')

             // trim leading and trailing whitespace
             .replace(/^\s+|\s+$/g, '')

             // trim DIV tags
            .replace(/(?:<\/?div>)+/g, '');

  node.innerHTML = html;
  return node;
};

/**
   Filter adding our '_poortext_url' attribut to links.  We don't
   want browsers to mess up the HREF attribute of links entered by
   the user.  So we remember the URL entered in a previous editing
   session and now coming from the server, and we remember it with a
   custom attribut named '_poortext_url'.  When sending the edited
   content back to the server or extracting it via {@link #getHtml},
   we'll delete '_poortext_url' after writing its content back to the
   href attribute of the link (See {@link PoorText#removeUrlProtection}).
   The same procedure is applied to ABBR and ACRONYM tags.
   @param {Node} node The node whose <a> tags will be treated
   @return the node with URL protection added.
   @type Node
   @private
*/
PoorText.addUrlProtection = function(node) {
    // Remember URL in _poortext_url attribute
    var links = node.getElementsByTagName('A');
    $A(links).each(function(link) {
        link = $(link);
	if (link.hasAttribute('href')) {
	    link.setAttribute('_poortext_url', PoorText.getHref(link));
	    link.setAttribute('_poortext_tag', 'a');
            PoorText.setClass(link, 'pt-a');
	}
    });
    
    // Substitute phrase markup with custom link elements
    var isIE6 = false;
    ['abbr', 'acronym'].each(function(tag) {
	var elements = node.getElementsByTagName(tag);
	$A(elements).each(function(elm) {
            // IE6 does not support the ABBR tag: fix it
            if (!elm.innerHTML) {
                isIE6 = true;
                return;
            }
	    var link = $(document.createElement('a'));
	    link.setAttribute('title', elm.getAttribute('title'));
	    link.setAttribute('_poortext_tag', tag);
            link.setAttribute('href', '');
	    PoorText.setClass(link, 'pt-'+tag);
	    link.innerHTML = elm.innerHTML;
	    elm.parentNode.replaceChild(link, elm);
	})});

    if (isIE6) PoorText.__abbrFixIE6(node);

    return node;
};

/**
   Filter removing our '_poortext_url' attribut from links after
   writing its contents back to their HREF attribut.  This is the
   counterpart of {@link PoorText#removeUrlProtection}), which comes with
   more detailed information.
   The same procedure is applied to ABBR and ACRONYM tags.
   @param {Node} node The node whose <a> tags will be treated.
   @return The node with URL protection removed
   @type Node
   @private
*/
PoorText.removeUrlProtection = function(node) {
    var links = node.getElementsByTagName('A');
    $A(links).each(function(link) {
        link = $(link);
	if (link.hasAttribute('_poortext_url')) {
	    link.setAttribute('href', link.getAttribute('_poortext_url'));
	    link.removeAttribute('_poortext_url');
            link.removeAttribute('_poortext_tag');
            link.removeAttribute('class');
            link.removeAttribute('className');
            link.removeAttribute('_counted'); // IE stuff
	}
	else { // fake links to be turned into phrase markup
	    var tagName = link.getAttribute('_poortext_tag');
	    var tag = document.createElement(tagName);
	    tag.setAttribute('title', link.getAttribute('title'));
	    tag.innerHTML = link.innerHTML;
	    link.parentNode.replaceChild(tag, link);
	}
    });
    return node;
};

/**
   Array of filter functions to be applied at creation time. The
   {@link #srcElement} innerHTML is passed through these filters, the
   output being stored in {@link #returnHTML}.
   @type Class Array
   @private
*/
PoorText.returnFilters = [];

/**
   Array of filter functions for incoming HTML.  These filters are
   applied when setting {@link #editNode} with the contents of {@link
   #srcElement}.  This typically occurs in {@link #makeEditable}.
   @type Class Array
   @private
*/
PoorText.inFilters = [ PoorText.addUrlProtection ];

/**
   Array of filter function for outgoing HTML.  These filters will be
   applied when setting {@link #returnHTML} with the contents of
   {@link #editNode}.  This typically occurs {@link PoorText#onBlur}.
   @type Class Array
   @private
*/
PoorText.outFilters = [ PoorText.correctMarkup,
                        PoorText.removeUrlProtection ];

/**
   Global configuration API for PoorText users.<br> The following
   options may also be specified on a per-instance basis. In this case
   they override the global configuration provided in PoorText.config{}.

   <b>form</b> {STRING id | HTMLFormElement} - The HTML form this
       PoorText element belongs to.  May be specified as ID or
       HTMLFormElement.  If not specified, it will be derived from the
       DIV itsself by searching the document tree upwards for a parent
       FORM element.  If the DIV does not reside in any FORM and the
       form option is not specified, an error of type OutsideFormError
       will be thrown.<br/>

   <b>type</b> {STRING text|textarea} - The type of the PoorText
       element.  The type of a PoorText element maybe 'text' or
       'textarea'.  Currently, the only difference between the two
       flavours is that 'text'-type elements, like regular text input
       fields, do nothing but alert the user when she presses 'RET'.
       The type of an element may be specified<br>(a) using the
       present global config option<br>(b) via a non-standard HTML
       'type' attribute set on the DIV we want to make editable<br>(c)
       the instance config option 'type' -- precedence in this order.
       The default is 'text'.<br/>

   <b>cssClass</b> {STRING} - The CSS class of DIV elements to be
       turned into PoorText elements.  PoorText looks for DIVs having
       this CSS class elements when {@link #autoload} is true
       or when calling {@link PoorText#generateAllWithCssClass}.  The
       default is {@link PoorText#cssClass}.<br/>

   <b>deferIframeCreation</b> {BOOL} - If true, which is the default,
       the editable iframe will only be created onMouseOver.  This
       speeds up loading for pages having a lot of PoorText elements.<br/>

   <b>iframeHead</b> {STRING} - A string to insert into the HEAD
       section of the editable iframes created by PoorText. Defaults
       to the empty string.

   <b>onFocus</b> {FUNCTION} - Function to be called when focussing a
       PoorText element. The default sets the PoorText element's
       border-style to 'inset'.<br/>

   <b>onBlur</b> {FUNCTION} - Function to be called when bluring a
       PoorText element. The default sets the PoorText element's
       border-style to 'solid'.<br/>

   <b>onSubmit</b> {FUNCTION} - Function to be called when the form is
       submitted.  No default action.<br/>

   <b>availableCommands</b> {Array} - List of command names available
      on PoorText elements. The default is<br>
      'toggle_selectall', 'bold', 'italic', 'underline', 'strikethrough', 'subscript', 'superscript',<br/>
      'cut', 'copy', 'paste',<br/>
      'align_left', 'align_center', 'align_right', 'justify',<br/>
      'indent', 'outdent',<br/>
      'add_html', 'delete_html',<br/>
      'redo', 'undo',<br/>
      'specialchars' and 'help'.<br/>
      You can't specify more commands, but you can restrict the list.<br/>

   <b>specialChars</b> {OBJECT} - object mapping charnames to unicode
      codepoint strings.  These chars appear in the special char bar
      if attachSpecialCharBar is true (see below).  And you may
      provide shortcuts for them, mapping their names to shortcuts
      using the config option 'shortcutFor'.<br/>

   <b>shortcutFor</b> {OBJECT} - object mapping command names (see
      'availableCommands') and charnames (see 'specialChars') to shortcuts.<br/>
      The default is:<br>
            bold             : 'ctrl_b',<br/>
            italic           : 'ctrl_i',<br/>
            underline        : 'ctrl_u',<br/>
            subscript        : 'ctrl_d',<br/>
            superscript      : 'ctrl_s',<br/>
            strikethrough    : 'ctrl_t',<br/>
            toggle_selectall : 'ctrl_a',<br/>
            add_html         : 'ctrl_l',<br/>
            delete_html      : 'ctrl_shift_l',<br/>
            redo             : 'ctrl_y',<br/>
            undo             : 'ctrl_z',<br/>
            help             : 'ctrl_h',<br/>
            esc              : 'escape',<br/>
            enter            : 'enter',<br/>
            cut              : 'ctrl_x',<br/>
            copy             : 'ctrl_c',<br/>
            paste            : 'ctrl_v',<br/>
            specialchars     : 'ctrl_6',<br/>
            align_left       : 'ctrl_q',
            align_center     : 'ctrl_e',
            align_right      : 'ctrl_r',
            justify          : 'ctrl_w',
            indent           : 'tab',
            outdent          : 'shift_tab',
            lsquo            : 'ctrl_4',<br/>
            rsquo            : 'ctrl_5',<br/>
            ldquo            : 'ctrl_2',<br/>
            rdquo            : 'ctrl_3',<br/>
            ndash            : 'ctrl_0',<br/>

   <b>attachButtonBar</b> {BOOL} - If true, attach the button bar on top
      of the focused PoorText element. If false, the availableCommands
      are only available via their shortcuts.<br/>

   <b>attachSpecialCharBar</b> {BOOL} - If true, attach the
      specialChar bar on top of the button bar. If false, the char bar
      may be displayed via the specialchar bar button (the omega sign).<br/>

   <b>lang</b> {STRING} - A RFC3066-style language tag to localize
      PoorText strings. Lexicons reside in lang/. Defaults to English.<br/>

   <b>indentSize</b> {NUMBER} - The number of pixel the text content
       will be shifted to the right when pressing KEY_TAB. Defaults to
       20px.<br/>

   @type Class Object
*/
PoorText.config = {};

PoorText.prototype = {
    initialize : function (config) {
	this.setConfig(config);
	this.insertReturnElements();
	this.makeEditable();
	this.attachKeymap();
    },
    
    functionFor : {
        /**@ignore*/ bold             : function() {this.markup('bold'         )},
        /**@ignore*/ italic           : function() {this.markup('italic'       )},
        /**@ignore*/ underline        : function() {this.markup('underline'    )},
        /**@ignore*/ subscript        : function() {this.markup('subscript'    )},
        /**@ignore*/ superscript      : function() {this.markup('superscript'  )},
        /**@ignore*/ strikethrough    : function() {this.markup('strikethrough')},
        /**@ignore*/ toggle_selectall : function() {this.toggleSelectAll()      },
        /**@ignore*/ add_html         : function() {this.addHTML()              },
        /**@ignore*/ delete_html      : function() {this.deleteHTML()           },
        /**@ignore*/ redo             : function() {this.markup('redo')         },
        /**@ignore*/ undo             : function() {this.undo()                 },
        /**@ignore*/ help             : function() {this.showHelp()             },
        /**@ignore*/ esc              : function() {window.focus()},
        /**@ignore*/ cut              : function() {this.markup('cut'          )},
        /**@ignore*/ copy             : function() {this.markup('copy'         )},
        /**@ignore*/ paste            : function() {this.markup('paste'        )},
        /**@ignore*/ specialchars     : function() {this.toggleSpecialCharBar() },
        /**@ignore*/ align_left       : function() {this.setTextAlign('left'   )},
        /**@ignore*/ align_center     : function() {this.setTextAlign('center' )},
        /**@ignore*/ align_right      : function() {this.setTextAlign('right'  )},
        /**@ignore*/ justify          : function() {this.setTextAlign('justify')},
        /**@ignore*/ indent           : function() {this.setTextIndent()        },
        /**@ignore*/ outdent          : function() {this.setTextOutdent()       }
    },

    /**
       Configure this PoorText instance: Use the builtin defaults,
       overwrite them with the user-provided global configuration in
       {@link PoorText#config}, then overwrite them with
       instance-specific configuration.
       @param {Object} config
       @return nothing
       @private
    */
    setConfig : function (config) {
	config = (config || {});

	// Defaults
        this.shortcutFor = {
            bold             : 'ctrl_b',
            italic           : 'ctrl_i',
            underline        : 'ctrl_u',
            subscript        : 'ctrl_d',
            superscript      : 'ctrl_s',
            strikethrough    : 'ctrl_t',
            toggle_selectall : 'ctrl_a',
            add_html         : 'ctrl_l',
            delete_html      : 'ctrl_shift_l',
            redo             : 'ctrl_y',
            undo             : 'ctrl_z',
            help             : 'ctrl_h',
            esc              : 'escape',
            enter            : 'enter',
            cut              : 'ctrl_x',
            copy             : 'ctrl_c',
            paste            : 'ctrl_v',
            specialchars     : 'ctrl_6',
            align_left       : 'ctrl_q',
            align_center     : 'ctrl_e',
            align_right      : 'ctrl_r',
            justify          : 'ctrl_w',
            indent           : 'tab',
            outdent          : 'shift_tab',
            lsquo            : 'ctrl_4',
            rsquo            : 'ctrl_5',
            ldquo            : 'ctrl_2',
            rdquo            : 'ctrl_3',
            ndash            : 'ctrl_0'
        };

	this.config = {
	    type    : 'text',
	    deferIframeCreation : true,  // if true, create iframe when srcElement.mouseover()
	    iframeHead          : '',    // string to insert in the HEAD section of Gecko's iframe
	    onFocus             : function() {this.setStyle({borderStyle:'inset'})},
	    onBlur              : function() {this.setStyle({borderStyle:'solid'})},
	    availableCommands : $A([
		'toggle_selectall', 'bold', 'italic', 'underline', 'strikethrough', 'subscript',  'superscript', 
                'cut', 'copy', 'paste',
                'align_left', 'align_center', 'align_right', 'justify',
                'indent', 'outdent',
		'add_html', 'delete_html', 
                'redo', 'undo', 'specialchars', 'help'
            ]),
            specialChars : $H({
                ldquo : "\u201C",
                rdquo : "\u201D",
                lsquo : "\u2018", 
                rsquo : "\u2019",
                ndash : "\u2013"
                    }),
            attachButtonBar     : false,
            attachSpecialCharBar : false,
            lang : 'de',
            indentSize : 20
	};

	// Merge in global config shortcuts
	Object.extend(this.shortcutFor, PoorText.config.shortcutFor);

	// Merge in instance config shortcuts
	Object.extend(this.shortcutFor, config.shortcutFor);

	// Merge in global config
	Object.extend(this.config, PoorText.config);

	// Set HTML type attrib between global config merge and instance config merge!!
	var type = this.srcElement.getAttribute('type');
	if (type) this.config.type = type;
	
	// Merge in instance config
	Object.extend(this.config, config);

	// TAB and ESC commands are always available
	this.config.availableCommands.push('tab', 'esc');

	// Record the form
	var form = this.config.form;
        this.form = form ? $(form) : this.srcElement.up('form');
        if (! this.form) {
            var e = new Error();
            e.message = 'No FORM was specified on instance creation and instance "'
		+ this.id
		+ '" is not a child of any FORM tag';
            e.name = "OutsideFormError";
            throw e;
        }

	// For 'text' fields, attach empty function on 'enter' keypress
	if (this.config.type == 'text') {
	    this.config.availableCommands.push('enter');
	}
    
	// Call the element's onSubmit method when submitting the form
	Event.observe(this.form, 'submit', this.onSubmit.bindAsEventListener(this), true);

	// Some bookkeeping
	PoorText.objects.push(this);
	PoorText.id2obj[this.id] = this;
    },

    /**
       Instance method: Return true if the given command is enabled in
       PoorText. This is just a wrapper around
       document.queryCommandEnabled()
       @param {STRING} command
       @return boolean
       @private
    */ 
    queryCommandEnabled : function(cmd) {
	return PoorText.hasCommand[cmd];
    },

    /**
       Instance method: Return true if the given command is active,
       e.g. the cursor is on 'bold' text. This is just a wrapper
       around document.queryCommandState()
       @param {STRING} command
       @return boolean
       @private
    */
    queryCommandState : function(cmd) {
	if (cmd == 'selectall') return this.selectedAll;
	return this.document.queryCommandState(cmd);
    },

    /**
       Instance method to attach the configured shortcuts to their
       functions.
       @param none
       @return nothing
       @private
    */
    attachKeymap : function () {
        // keymap for commands
	this.filterAvailableCommands().each(function(cmd) {
            if (this.config.attachSpecialCharBar && cmd == 'specialchars') return;
	    this.keyHandlerFor[this.shortcutFor[cmd]] = this.functionFor[cmd];
	}.bind(this));

        // ENTER key handler depends on type
        if (this.config.type == 'text') {
            this.keyHandlerFor['enter'] = function() {
                this.notify("The 'ENTER' key you pressed is not allowed in this context!");
            }
        } else {
            if (!Prototype.Browser.Gecko) {
                PoorText.__enterKeyHandler(this);
            }
        }

        // keymap for special chars
        this.config.specialChars.each(function(special) {
            this.keyHandlerFor[this.shortcutFor[special.key]]
                = function () {this.insertHTML(special.value, false)};
        }.bind(this));
    },

    /**
       Handle keyDown events for PoorText elements.
       @param {EVENT} event
       @return nothing
       @private
    */
    onKeyDown : function(event) {
	return this.dispatchKey(event);
    },

    // Borrowed from David Flanagan
    /**@ignore*/
    dispatchKey : function(e) {

	// We start off with no modifiers and no key name
	var modifiers = ""
	var keyname = null;

	//           Gecko  ||   MSIE
	var code = (e.which || e.keyCode);

	// Ignore keydown events for Shift, Ctrl, and Alt
	if (code == 16 || code == 17 || code == 18) return;
	
	// Get the key name from our mapping
	keyname = PoorText.keyCodeToFunctionKey[code];
	
	// If this wasn't a function key, but the ctrl or alt modifiers are
	// down, we want to treat it like a function key
	if (!keyname && (e.altKey || e.ctrlKey))
	keyname = PoorText.keyCodeToPrintableChar[code];
	
	// If we found a name for this key, figure out its modifiers.
	// Otherwise just return and ignore this keydown event.
	if (keyname) {
	    if (e.altKey) modifiers += "alt_";
	    if (e.ctrlKey) modifiers += "ctrl_";
	    if (e.shiftKey) modifiers += "shift_";
	}
	else return;
	
	// Now that we've determined the modifiers and key name, we look for
	// a handler function for the key and modifier combination
	var func = this.keyHandlerFor[modifiers+keyname];

	if (func) {  // If there is a handler for this key, handle it
	    func.call(this, e);	    
            Event.stop(e);
	}

        // Gecko needs special things
        if (Prototype.Browser.Gecko) {
            this.__afterKeyDispatch(modifiers+keyname);
        }
    },

    /**
       Handle keyUp events for PoorText elements.
       @param {EVENT} event
       @return nothing
       @private
    */
    onKeyUp : function(event) {

        this.updateButtonBar(event);

        this.afterOnKeyUp(event);

        if (event) Event.stop(event);
    },

    /**
       Instance method to update the button bar (called by the onKeyUp
       handler)
       @param {Event} event
       @return nothing
       @private
    */
    updateButtonBar : function(event) {
        // no button bar, no update
        if (!$('pt-btnBar')) return;

        // On IE, markup via button automagically marks up the whole
        // word the cursor is on.  But the button bar update process
        // needs to be deferred a bit in this special case.  If the
        // word is selected no deferring is necessary.  Gecko ignores
        // this magic.
        setTimeout(function() {
            // make sure we are only called once
            if (this.keyUpHandlerIsExecuting) return;
            this.keyUpHandlerIsExecuting = true;

            // remove 'btn-pressed' CSS class from all buttons
            $$('a.pt-btnLink').invoke('removeClassName', 'pt-btn-pressed');

            // add a 'btn-pressed' CSS class for active commands
            PoorText.markupButtons.each(function(tag) {
                if (this.queryCommandState(tag)) {
                    $('pt-btn-'+tag).firstDescendant().addClassName('pt-btn-pressed');
                }
            }.bind(this));
        }.bind(this), 1);

        // reset control
        this.keyUpHandlerIsExecuting = false;
    },

    /**
       Instance method to toggle the display of the special-chars bar.
       @param {EVENT} event
       @returns nothing
       @private
    */
    toggleSpecialCharBar : function(event) {
        // toggle flag
        this.scbVisible = !this.scbVisible;

        // act upon flag state
        this.showHideSpecialCharBar();
    },

    /**
       Instance method to show/hide the special-chars bar depending on
       an internal status flag.
       @param none
       @returns nothing
       @private
    */
    showHideSpecialCharBar : function() {
        if (this.scbVisible) {
            // show special chars and replace button img
            PoorText.specialCharBar.attach(this);
            $('pt-btn-specialchars')
            .title = PoorText.cmdToDisplayName('hide_specialchars');
        } else {
            // hide special chars and replace button img
            $('pt-specialCharBar').hide();
            $('pt-btn-specialchars')
            .title = PoorText.cmdToDisplayName('show_specialchars');
        }
        this.afterShowHideSpecialCharBar();
    },

    /**
       Instance method called when a PoorText field receives focus.
       @param {EVENT} event
       @returns nothing
       @private
    */
    onFocus : function(event) {

        // maybe hide markup dialog
        if ($('pt-popup-addHTML')) $('pt-popup-addHTML').hide();

        // short-circuit
        if (this.focused) return;

        // pseudo onblur handler for previously focused object
        PoorText.onBlur();

        // execute the configured onFocus handler
	if (this.config.onFocus && typeof(this.config.onFocus) == 'function') {
            this.config.onFocus.call(this);
	}

        // remember me
	this.focused = true;
	PoorText.focusedObj = this;

        // maybe attach the button bar
        if (this.config.attachButtonBar) {
            PoorText.buttonBar.attach(this);
        }

        // maybe attach specialChar bar
        if (this.config.attachSpecialCharBar || this.scbVisible) {
            PoorText.specialCharBar.attach(this);
        }

        // update Help popup if it's visible
        if (PoorText.Popup.help && PoorText.Popup.help.visible()) {
            this.showHelp(true);
        }
    },

    /**
       onSubmit handler. Default does nothing.
       @param {EVENT} event
       @return nothing
    */
    onSubmit : function(event) {
    },

    /**
       Instance method to attach a named event handler to the current
       element.
       @param {STRING} - the name of the event (keydown, click etc.)
       @param {STRING} - an arbitrary string identifying this event handler
       @param {FUNCTION} - the event handler function
       @param {BOOL} - the useCapture flag
    */
    observe : function(type, name, handler, useCapture) {
	var func = handler.bindAsEventListener(this);
	Event.observe(this.eventNode, type, func, useCapture);
	if (!this.eventHandlers[type]) this.eventHandlers[type] = new Object();
	this.eventHandlers[type][name] = [func, useCapture];
    },

    /**
       Instance method to detach a named event handler from the
       current element
       @param {STRING} - the name of the event (keydown, click etc.)
       @param {STRING} - the identifier under which the event handler
       has been registered using {@link .observe()}
       @returns nothing
       @private
    */
    stopObserving : function(type, name) {
        try {
            var handlerSpec = this.eventHandlers[type][name];
            var func       = handlerSpec[0];
            var useCapture = handlerSpec[1];
            Event.stopObserving(this.eventNode, type, func, useCapture);
            delete this.eventHandlers[type][name];
        } catch (e) {}
    },

    /**
       Instance method to remove all event handlers installed via
       {@link .observe()}
       @param none
       @returns nothing
       @private
    */
    removeAllEventHandlers : function () {
	if (!this.eventHandlers) return;
	for (type in this.eventHandlers) {
	    for (name in this.eventHandlers[type]) {
		this.stopObserving(type, name);
	    }
	}
	this.eventHandlers = null;
    },

    /**
       Instance method to get the HTML out of the PoorText
       element. May be used in onSubmit handlers.
       @param none
       @return the HTML typed into PoorText elements
       @type String
    */
    getHtml : function() {
	return this.applyFiltersTo(this.editNode.cloneNode(true), PoorText.outFilters);
    },

    /**
       Instance method to set the innerHTML of {@link PoorText#editNode}.
       @param {Node} node the node whose HTML should be set as the innerHTML of editNode
       @param {Array} filters an array of filters applied to node before setting the editNode's innerHTML
       @return nothing
    */
    setHtml : function(node, filters) {
	this.editNode.innerHTML = this.applyFiltersTo(node, filters).innerHTML;
    },

    /**@ignore*/
    applyFiltersTo : function(node, filters) {
	filters.each(function(filter) {
	    node = filter(node);
	});
	return node;
    },

    /**@ignore*/
    notify : function(a) { alert(PoorText.L10N.localize(a)) },

    /**@ignore*/
    addHTML : function() { 

        // Get existing link
	var sel = this.selected = this.getLink();

	// No link && no selection
	if (sel.msg == 'showAlert') {
	    this.notify("You have to select some text to insert a HTML element.");
	    return;
	} 

        var oldElm = sel.elm;

	if (oldElm) {
	    if (oldElm.getAttribute('_poortext_tag') == 'link') {
		var mysavedurl = oldElm.getAttribute('_poortext_url');
		oldElm.url = mysavedurl ? mysavedurl : PoorText.getHref(oldElm);
	    }
	}


	// Create popup and hook in the dialog html
	window.focus();

	var which = 'addHTML';

	var popup = PoorText.Popup.get(which);
	popup.innerHTML = PoorText.L10N.localizeDialog(PoorText.htmlFor[which]);

	var dlgForm    = $('pt-dlg-form-'+which);
	var urlField   = dlgForm['pt-dlg-url'];
	var titleField = dlgForm['pt-dlg-tooltip'];

	if (oldElm) {
	    // Set tag
	    var tag = $A(dlgForm['tag']).find(function(tag) { 
		return tag.id == 'pt-dlg-' + oldElm.getAttribute('_poortext_tag');
	    });
	    tag.checked = true;

	    // Set title
	    var title = oldElm.getAttribute('title');
	    if (title) titleField.value = title;

	    // Set URL
	    var url = oldElm.getAttribute('_poortext_url');
	    if (tag.id == 'pt-dlg-a') {
		urlField.value = url;
		$('pt-dlg-url-row').show();
		setTimeout(function() {
		    urlField.focus();
		    urlField.select();
		},50);
	    }
	    else {
		urlField.value = 'http://';
		$('pt-dlg-url-row').hide();
		setTimeout(function() {
		    titleField.focus();
		    titleField.select();
		},50);
	    }
	} 
	else {
	    urlField.value = 'http://';
	    setTimeout(function() {
		$('pt-dlg-a').focus();
	    }, 50);
	}

	// Finally, show the dialog
        popup.show();
	PoorText.Popup.positionIt(popup, which);
    },

    /**@ignore*/
    deleteHTML : function() {
	var sel = this.getLink();

	if (sel.msg == 'showAlert') {
	    this.notify("You didn't select any HTML element to delete!");
	    return;
	}

	try { sel.elm.removeAttribute('class'); } catch(e) {}

	try {
	    this.doDeleteHTML();
	}
	catch(error) {
	    alert("Couldn't delete the link because of "+error);
	}
    },

    /**@ignore*/
    insertReturnElements : function() {
        // Hidden form element used to return the HTML
        var id  = this.id;
        var rid = id + '_return';
        var re  = $(rid);
        if (!re) {
            // We don't have it: make it
            var val = this.applyFiltersTo(this.srcElement, PoorText.returnFilters).innerHTML;
            re = new Element('input', {type: 'hidden', id: rid, name: id, value: val});
            this.form.appendChild(re);
        }
        this.returnHTML = re;

        // Hidden form elements used to return the text INDENT and ALIGN
        [['indent', this.getTextIndent()],
         ['align' , this.getTextAlign() ]].each(function(el) {
                 var rid = id + '_' + el[0];
                 var re = $(rid);
                 if (!re) {
                     re = new Element('input', {type: 'hidden', id: rid, name: rid, value: el[1]});
                     this.form.appendChild(re);
                 }
                 this["return" + el[0].capitalize()] = re;
             }.bind(this));
        
    },

    /**@ignore*/
    showHelp : function(isVisible) {

	if (!isVisible) window.focus();

	var which = 'help';

	// Build the help row html
	var tmpl = PoorText.htmlFor[which].split('HERE');
	var html = PoorText.L10N.localizeDialog(tmpl[0]);

        // add shortcut help for buttons
	this.config.availableCommands.each(function(cmd) {
	    if (/^(tab|esc|enter|help)/.test(cmd)) return;
            if (this.config.attachSpecialCharBar && cmd == 'specialchars') return;
	    html += '<tr><td>';
	    html += PoorText.cmdToDisplayName(cmd)
	    html += '</td><td>';
	    html += PoorText.cmdToDisplayShortcut(this, cmd);
	    html += '</td></tr>';
	}.bind(this));

        // add shortcut help for specialChars
        this.config.specialChars.each(function(sc) {
            html += '<tr><td>';
            html += '<img src="/poortext/images/'+sc.key+'.png">';
	    html += '</td><td>';
	    html += PoorText.cmdToDisplayShortcut(this, sc.key);
	    html += '</td></tr>';
	}.bind(this));

        // add finally add the Close button
	html += '<tr><td></td><td style="text-align:right"><input type="button" value="' + PoorText.L10N.localize('Close')+'" id="pt-dlg-close" class="pt-dlg-button"></td></tr>';
	html += tmpl[1];

	// Insert the help html into the popup
	var popup = PoorText.Popup.get(which);
	popup.innerHTML = html;

	// Show the popup and focus the 'Close' button
        popup.show();
	PoorText.Popup.positionIt(popup, which);
	if (!isVisible) setTimeout(function() {$('pt-dlg-close').focus() }, 50 );
    },

    setTextAlign : function(align) {
        this.setStyle({textAlign : align});
        if (Prototype.Browser.WebKit) {
            this.restoreSelection();
        }
    },

    getTextAlign : function() {
        return this.getStyle('textAlign');
    },

    setTextIndent : function() {
        var oldIndent = this.getTextIndent();
        var oldWidth  = parseInt(this.getStyle('width'));
        var newIndent = oldIndent + this.config.indentSize + 'px';
        var newWidth  = oldWidth - (this.config.indentSize * 2) + 'px';
        this.setStyle({paddingLeft : newIndent, paddingRight: newIndent, width: newWidth});
        if (Prototype.Browser.WebKit) {
            this.restoreSelection();
        }
    },

    setTextOutdent : function() {
        var oldIndent = this.getTextIndent();
        var oldWidth  = parseInt(this.getStyle('width'));
        var newIndent = oldIndent - this.config.indentSize;
        var newWidth  = oldWidth + (this.config.indentSize * 2) + 'px';
        if (newIndent < 0) {
            newIndent = 0;
            newWidth = oldWidth;
        }
        newIndent += 'px';
        this.setStyle({paddingLeft : newIndent, paddingRight: newIndent, width: newWidth});
        if (Prototype.Browser.WebKit) {
            this.restoreSelection();
        }
    },

    getTextIndent : function() {
        return parseInt(this.getStyle('paddingLeft'));
    },

    storeForPostBack : function() {
        try {
            this.returnHTML.value   = this.getHtml();
            this.returnIndent.value = this.getTextIndent();
            this.returnAlign.value  = this.getTextAlign();
        } catch(er) {}
    }
};


/**
   Class method to generate PoorText elements for all DIVs having a
   CSS class of {@link PoorText#config.cssClass} or the default 'poortext'.
   @param none
   @return nothing
   @private
*/
PoorText.generateAll = function() {
    PoorText.generateAllWithCssClass(PoorText.config.cssClass || 'poortext');
    PoorText.finish_init();
};


PoorText.finish_init = function() {
    // Pseudo onBlur event for PT objects
    Event.observe(document, 'click', PoorText.onBlur);

    // Make sure no PT field has focus
    window.blur(); window.focus();
}

/**
   Class method to generate PoorText elements for all DIVs having the
   given CSS class.  The generated PoorText objects are accessible via
   {@link PoorText#objects}, {@link PoorText#id2obj} and {@link
   PoorText#focusedObj}.
   @param {STRING} CSS class name
   @return nothing
*/
PoorText.generateAllWithCssClass = function(cssClass) {
    $$('.'+cssClass).each(function(pt) { new PoorText(pt) });    
};

/**
   Class method to generate PoorText elements for all configured DIVs
   if {@link PoorText#autoload} is true.
   @param none
   @return nothing
   @private
*/
var _timer;
PoorText.onload = function () {
   // quit if this function has already been called
    if (arguments.callee.done) return;
 	 
    // flag this function so we don't do the same thing twice
    arguments.callee.done = true;
 	 
    // kill the timer
    if (_timer) {
        clearInterval(_timer);
        _timer = null;
    }

    // initialize all PoorText elements
    if (PoorText.autoload == true) {
	PoorText.generateAll();
    } else {
        PoorText.init();
        PoorText.finish_init();
    }
};

PoorText.init = function() {};

/**
   Class method, i.e. a pseudo onBlur handler. It can be triggered by
   main window's click event or the focus event of PT objects. In the
   latter case it is triggered by the onFocus event of the <b>next</b>
   focused object, but acts on the <b>previously</b> focused object.
   @param None
   @return nothing
   @private
*/
PoorText.onBlur = function(event) {
    // Radiobuttons need the click event to bubble to the window, but
    // under certain circumstances we don't want the window's onClick
    // handler to be triggered
    if (PoorText.cancelClickOnWindow) {
        PoorText.cancelClickOnWindow = false;
        return;
    }

    // hide the btn bar, the special char bar and the markup popup
    if ($('pt-btnBar')) $('pt-btnBar').hide();
    if ($('pt-specialCharBar')) $('pt-specialCharBar').hide();
    if ($('pt-popup-addHTML')) $('pt-popup-addHTML').hide();
    // onBlur stuff for previously focused PT field
    if (PoorText.focusedObj) {
        PoorText.focusedObj.selectionCollapseToEnd();
        PoorText.focusedObj.storeForPostBack();
        PoorText.focusedObj.config.onBlur.call(PoorText.focusedObj);
        PoorText.focusedObj.focused = false;
        PoorText.focusedObj = null;
    }
}.bindAsEventListener({});

/**
   Object telling which markup commands are supported by PoorText
   @type Class Object command map
   @final
   @private
*/
PoorText.hasCommand = {
    bold          : 1,
    copy          : 1,
    createlink    : 1,
    cut           : 1,
    inserthtml    : 1,
    italic        : 1,
    paste         : 1,
    strikethrough : 1,
    subscript     : 1,
    superscript   : 1,
    underline     : 1,
    unlink        : 1
};

/**
   This object maps keydown keycode values to key names for printable 
   characters.  Alphanumeric characters have their ASCII code, but 
   punctuation characters do not.  Note that this may be locale-dependent
   and may not work correctly on international keyboards.
   @type Class Object
   @final
   @private
*/
PoorText.keyCodeToFunctionKey = { 
    8:"backspace", 9:"tab", 13:"enter", 19:"pause", 27:"escape", 32:"space",
    33:"pageup", 34:"pagedown", 35:"end", 36:"home", 37:"left", 38:"up",
    39:"right", 40:"down", 44:"printscreen", 45:"insert", 46:"delete",
    112:"f1", 113:"f2", 114:"f3", 115:"f4", 116:"f5", 117:"f6", 118:"f7",
    119:"f8", 120:"f9", 121:"f10", 122:"f11", 123:"f12",
    144:"numlock", 145:"scrolllock"
};

/**
   This object maps keydown keycode values to key names for printable
   characters.  Alphanumeric characters have their ASCII code, but
   punctuation characters do not.  Note that this may be
   locale-dependent and may not work correctly on international
   keyboards.
   @type Class Object
   @final
   @private
*/
PoorText.keyCodeToPrintableChar = {
    48:"0", 49:"1", 50:"2", 51:"3", 52:"4", 53:"5", 54:"6", 55:"7", 56:"8",
    57:"9", 65:"a", 66:"b", 67:"c", 68:"d", 69:"e", 70:"f", 71:"g", 72:"h", 
    73:"i", 74:"j", 75:"k", 76:"l", 77:"m", 78:"n", 79:"o", 80:"p", 81:"q", 
    82:"r", 83:"s", 84:"t", 85:"u", 86:"v", 87:"w", 88:"x", 89:"y", 90:"z"
};


PoorText.addHTML = function() {
    var dlgForm = $('pt-dlg-form-addHTML');

    var tag = $A(dlgForm['tag']).find(function(elm) {
        return elm.checked;
    }).value;
    
    var title  = (dlgForm['pt-dlg-tooltip'].value || '');
    var url    = (dlgForm['pt-dlg-url'].value   || '');
    var pt     = PoorText.focusedObj;
    var oldElm = pt.selected.elm;

    // A real link
    if (tag == 'a') {
        // A link with the default prompt -> do nothing
        if (url == 'http://') return;
        // So we_ve got a url. Modify an existing link?
        if (oldElm) {
            // A link with an empty URL -> delete the link
            if (url == '') {
                try { oldElm.removeAttribute('class'); } catch(e) {}
                try { pt.doDeleteHTML(pt.selected.range); } catch(e) {alert(e)}
                return;
            } 
            oldElm.setAttribute('href', url);
            oldElm.setAttribute('_poortext_url', url);
            if (title) {
                oldElm.setAttribute('title', title);
            }
            // We might turn an existing non-link element
            // into a link element
            PoorText.setClass(oldElm, 'pt-a');
            oldElm.setAttribute('_poortext_tag', 'a');
            return;
        } else {
            if (url == '') return;
        }
    }
    // Another tag
    else {
        // So we've got something
        if (oldElm) {
            // A acronym or other with no title string -> do nothing
            if (title == '') {
                /* Note on Gecko (FF 1.5.0.9, 1.8.0.9) If we don't
                   delete the class attribute before deleting the
                   A-tag, Gecko inserts a 
                   <span class="pt-<tagname>">...</span> after deleting
                   the A-tag.
                */
                try { oldElm.removeAttribute('class') } catch(e) {}
                try { pt.doDeleteHTML(pt.selected.range); } catch(e) {alert(e)}
                return;
            }
            // With an unchanged title -> do nothing
            if (title == oldElm.title && tag == oldElm.tag) {
                return;
            }
            // Set new title on old element
            oldElm.setAttribute('title', title);
            oldElm.setAttribute('_poortext_tag', tag);
            PoorText.setClass(oldElm, 'pt-' + tag);
            try { oldElm.removeAttribute('_poortext_url') } catch(e) {}
            oldElm.setAttribute('href', '');
            return;
        } else {
            if (title == '') return;
        }
    }
    
    pt.doAddHTML(tag, url, title, pt.selected.range);
};


/**
               Popup dialog / help
*/
PoorText.Popup = {
    /**
       Class object storing position information per popup to always
       restore it at its previous position.
       @type Class Object
       @private
    */
    pos : new Object(),

    /**
       Class method to return (maybe first create) a draggable popup DIV
       for dialogs.
       @param {STRING} which The name of the popup used to build its ID
       @return the initialized and draggable popup
       @private
    */
    get : function(which) {
    
        var popupID = 'pt-popup-'+which;

        var popup = $(popupID);

        if (!popup) {
            var popup = $(document.createElement('div'));
            popup.id = popupID;
            popup.addClassName('pt-popup');
            popup.hide();
            document.body.appendChild(popup);
            
            // IE, even IE7
            if (Prototype.Browser.IE) popup.setStyle({position: 'absolute'});

            // make it draggable
            new Draggable(popupID, {
                starteffect : function() {},
                    endeffect : function(popup) {
                        var offset = Position.cumulativeOffset(popup);
                        PoorText.Popup.pos[which].deltaX = PoorText.Popup.pos[which].centerX - offset[0];
                        PoorText.Popup.pos[which].deltaY = PoorText.Popup.pos[which].centerY - offset[1];
                    }
            });

            // All popup handlers
            Event.observe(popup, 'click',   PoorText.Popup.clickHandler);
            Event.observe(popup, 'keydown', PoorText.Popup.keyDownHandler);
            Event.observe(popup, 'keyup',   PoorText.Popup.keyUpHandler);

            // Remember us
            PoorText.Popup[which] = popup;
        }

        return popup;
    },

    clickHandler : function(event) {
        var target = $(event.element());
        var popup  = target.up('.pt-popup');

        switch (target.id) {
        case 'pt-dlg-close':
            PoorText.Popup.close(popup);
            break;
        case 'pt-dlg-cancel':
            PoorText.Popup.close(popup);
            break;
        case 'pt-dlg-ok':
            PoorText.addHTML(popup);
            PoorText.Popup.close(popup);
            break;
        case 'pt-dlg-a':
            $('pt-dlg-url-row').show();
            break;
        case 'pt-dlg-abbr':
            $('pt-dlg-url-row').hide();
            break;
        case 'pt-dlg-acronym':
            $('pt-dlg-url-row').hide();
            break;
        }

        PoorText.cancelClickOnWindow = true;
        
    }.bindAsEventListener(PoorText.Popup),

    keyDownHandler : function(event) { // stop IE from beeping
        if (event.keyCode == 13) {     // when pressing KEY_RETURN
            Event.stop(event);
        }
    }.bindAsEventListener(PoorText.Popup),

    keyUpHandler : function(event) {
        var target = $(event.element());
        var popup  = target.up('.pt-popup');

        switch (target.id) {
        case 'pt-dlg-url':
            PoorText.Popup.keyReturnHandler(event, popup);
            break;
        case 'pt-dlg-tooltip':
            PoorText.Popup.keyReturnHandler(event, popup);
            break;
        case 'pt-dlg-a':
            $('pt-dlg-url-row').show();
            break;
        case 'pt-dlg-abbr':
            $('pt-dlg-url-row').hide();
            break;
        case 'pt-dlg-acronym':
            $('pt-dlg-url-row').hide();
            break;
        case 'pt-dlg-close':
            if (event.keyCode == 13) { // KEY_RETURN
                PoorText.Popup.close(popup);
            }
            break;
        case 'pt-dlg-cancel':
            if (event.keyCode == 13) { // KEY_RETURN
                PoorText.Popup.close(popup);
            }
            break;
        case 'pt-dlg-ok':
            if (event.keyCode == 13) { // KEY_RETURN
                PoorText.addHTML(popup);
                PoorText.Popup.close(popup);
            }
            break;
        }

        if (event.keyCode == 27) { // KEY_ESC
            PoorText.Popup.close(popup);
        }

    }.bindAsEventListener(PoorText.Popup),

    close : function(popup) {
        // remove content and hide popup
        popup.innerHTML = '';
        popup.hide();
        this.afterClosePopup();
    },

    keyReturnHandler : function(event, popup) {
        if (event.keyCode == 13) { // KEY_RETURN
            PoorText.addHTML(popup);
            PoorText.Popup.close(popup);
            Event.stop(event);
        }
    }
};

/**
   Initialize popup positions
*/
(function() {
    ['addHTML', 'help'].each(function(which) {
	PoorText.Popup.pos[which] = {
	    deltaX    : 0,
	    deltaY    : 0,
	    centerX   : 0,
	    centerY   : 0,
	    oldPopupW : 0,
	    oldPopupH : 0,
            center    : true
	}
    });
})()



/**
   Utility method to transform command names in localized display
   names (for help screen and tooltips)
   @param {STRING} command name, e.g. 'bold'
   @return the display name, e.g. 'Bold' or 'Fett'
   @type String
   @private
*/
PoorText.cmdToDisplayName = function(cmd) {
    // translate it
    return PoorText.L10N.localize(cmd.split('_').invoke('capitalize').join(' '));
};

/**
   Utility method producing human readable shortcut information for
   commands
   @param {STRING} command name, e.g. 'bold'
   @return shortcut, e.g. 'Ctrl-B'
   @type String
   @private
*/
PoorText.cmdToDisplayShortcut = function (pt, cmd) {
    return $A(pt.shortcutFor[cmd].split('_')).invoke('capitalize').join('-');
};

/*
                   Button Bar
*/

/**
   The button bar is dynamically attached to a PoorText field onFocus,
   detached onBlur.  Attachement is controlled by the config flag
   'attachButtonBar' of {@link PoorText#config}.
   @type Class Object
   @private
*/
PoorText.buttonBar = {
    /**
       Flag indicating whether the button bar has already been loaded
       @type Boolean
       @private
    */
    loaded : false
};
/**
   Class method to attach the button bar to the focused PoorText
   field. Loads the button bar if it has not yet been loaded.
   @param {PoorText} Object The object representing the focused PoorText field
   @return nothing
   @addon
*/
PoorText.buttonBar.attach = function(pt) {
    // maybe load it
    if (!PoorText.buttonBar.loaded) {
        PoorText.buttonBar.load();
        PoorText.buttonBar.loaded = true;
    }

    // attach the button bar to editable field, but only show buttons
    // for per-instance available commands
    $$('li.pt-btn').each(function(btn) {
        var id = btn.id.replace('pt-btn-', '');

        // add tooltip with shortcut
        btn.writeAttribute('title', PoorText.cmdToDisplayName(id) + ': ' 
                           + PoorText.cmdToDisplayShortcut(pt, id));

        pt.filterAvailableCommands().find(function(cmd) { return id == cmd })
        ? btn.show()
        : btn.hide();
    });

    // Special tooltip for special char button
    $('pt-btn-specialchars').title = PoorText.cmdToDisplayName('show_specialchars') + ': '
       +  PoorText.cmdToDisplayShortcut(pt, 'specialchars');

    // special char bar (button) needs special consideration
    if (pt.config.attachSpecialCharBar) {
        // don't show the button if the special chars bar is visible any way
        $('pt-btn-specialchars').hide();
    } else {
        // show/hide it according to previous state
        if ($('pt-specialCharBar')) pt.showHideSpecialCharBar();
    }

    // show the button bar
    var leftTop = pt.frameNode.cumulativeOffset();
    $('pt-btnBar').setStyle({left : leftTop[0]+'px', top : leftTop[1]-22+'px'}).show();
};

/**
   Class method to load the button bar when first attaching it to some
   PoorText field.
   @param None
   @return nothing
*/
PoorText.buttonBar.load = function() {
    // Attach the btnBar HTML to the body  
    var btnBar = document.createElement('div');
    Element.extend(btnBar);
    btnBar.id = 'pt-btnBar';
    btnBar.insert({top : PoorText.htmlFor.buttonBar}).hide();
    document.body.appendChild(btnBar);

    // Install an onClick handler on the btnBar to capture button
    // click events
    Event.observe($('pt-btnBar'), 'click', function (e) {
        var target = e.target.parentNode;
        PoorText.focusedObj.functionFor[target.id.replace('pt-btn-', '')].call(PoorText.focusedObj);

        // Don't focus the PT element when we popup a dialog
        if (target.id != 'pt-btn-add_html' && target.id != 'pt-btn-help') {
            PoorText.focusedObj.focusEditNode()
            PoorText.focusedObj.updateButtonBar(e);
        }

        // Make sure the window onClick handler does not see the btn
        // click event
        Event.stop(e);
    }.bindAsEventListener(PoorText.focusedObj), true);
};

/*
                   Special Char Bar
*/

/**
   The special char bar is dynamically attached to a PoorText field
   onFocus, detached onBlur if the config flag 'attachSpecialCharBar'
   is true (see {@link PoorText#config}). If this flag is false, a
   'Show Special Char Bar' button is added to the button bar allowing
   to toggle special char bar display.
   @type Class Object
   @private
*/
PoorText.specialCharBar = {
    /**
       Flag indicating whether the specialChar bar has already been loaded
       @type BOOL
       @private
    */
    loaded : false
};

/**
   Class method to ttach the special char bar to the focused PoorText
   field. Loads the special char bar if it has not yet been loaded.
   @param {PoorText} Object The object representing the focused PoorText field
   @return nothing
   @addon
*/
PoorText.specialCharBar.attach = function(pt) {
    // maybe load it
    if (!PoorText.specialCharBar.loaded) {
        PoorText.specialCharBar.load();
        PoorText.specialCharBar.loaded = true;
    }

    // attach the button bar to editable field, but only show buttons
    // for per-instance available commands
    $$('li.pt-char').each(function(sc) {
        var id = sc.id.replace('pt-char-', '');

        // add tooltip with shortcut
        sc.writeAttribute('title', PoorText.cmdToDisplayShortcut(pt, id));

        // show/hide the char
        pt.config.specialChars.find(function(sc) { return id == sc.key })
        ? sc.show()
        : sc.hide();
    });
    
    // show it
    var leftTop = pt.frameNode.cumulativeOffset();
    var diff = pt.config.attachButtonBar ? 44 : 22;
    $('pt-specialCharBar').setStyle({left : leftTop[0]+'px', top : leftTop[1]-diff+'px'}).show();
};

/**
   Class method to load the special char bar when first attaching it
   to some PoorText field.
   @type Class method
   @param None
   @return nothing
*/
PoorText.specialCharBar.load = function() {
    // Attach the specialCharBar HTML to the body  
    var scBar = document.createElement('div');
    Element.extend(scBar);
    scBar.id = 'pt-specialCharBar';
    scBar.insert({top : PoorText.htmlFor.specialCharBar}).hide();
    document.body.appendChild(scBar);

    // Install an onClick handler on the btnBar to capture button
    // click events
    Event.observe($('pt-specialCharBar'), 'click', function (e) {
        // insert the special char
        var target = e.target.parentNode;
        PoorText.focusedObj.insertHTML(PoorText.focusedObj.config.specialChars.get(target.id.replace('pt-char-', '')),
                                        true);

        // focus the edit area again
        PoorText.focusedObj.window.focus();

        // Make sure the main window onClick handler does not see the
        // special char click event
        Event.stop(e);
        return false;
    }.bindAsEventListener(PoorText.focusedObj), true);
};

/**
   The localization object. Contains lexicons and two localization
   methods.
   @type Class Object
   @private
*/
PoorText.L10N = {};

/**
   Class method to localize strings.  If {@link PoorText#config.lang}
   is 'en' return as is.
   @param {STRING] string to be localized
   @return {STRING} localized string
   @private
*/
PoorText.L10N.localize = function(orig) {
    // short-circuit for English
    if (PoorText.config.lang == 'en') return orig;

    // translate it
    return PoorText.L10N[PoorText.config.lang][orig];
};

/**
   Class method to localize bracket-enclosed strings in dialogs
   @param {STRING} HTML dialog containing bracketed strings to be localized
   @return {STRING} HTML dialog with bracketed strings being
   localized; if {@link PoorText#config.lang} is 'en' just remove the
   brackets.
   @private
*/
PoorText.L10N.localizeDialog = function(dlg) {
    // short-circuit for English
    if (PoorText.config.lang == 'en') return dlg.replace(/\[([^\]]+)\]/g, "$1");

    // translate it
    return dlg.replace(/\[([^\]]+)\]/g, function(match, captured) {
        return PoorText.L10N.localize(captured)
    });
};

/**
   Array of basic markup tag names.
   @type Array
   @private
*/
PoorText.markupButtons = $A([
    'bold',
    'italic',
    'strikethrough',
    'subscript',
    'superscript',
    'underline'
]);

