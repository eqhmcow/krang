/** @fileoverview ProtoPopup and its subclasses ProtoPopup.Alert and
    ProtoPopup.Confirm provide a light-weight solution for info, alert
    and confirm dialogs based on Prototype and Scriptaculous.
    @author <a href="mailto:bs@cms-schulze.de">Bodo Schulze</a>
    @version 0.1
    @license BSD-like
    @www <a href="http://dev.cms-schulze.de>ProtoPopup</a>

   <h4 style="margin-bottom:0em">1. Features</h4>

   <ul>
   <li>Multiple popups may be open at the same time.</li>

   <li>Position memory: Each popup remembers its position relative to
     the viewport across showing / hiding: The popups are draggable,
     but have position 'fixed' in FF2+, IE7+, Webkit.</li>

   <li>Content sections: Popups have three section DIVs: 'header',
     'body', 'footer'. They can be filled with content separately.</li>

   <li>Flexible content definition: The section's content can be plain
     text, HTML, a DOM element or any kind of object having a
     toString() method (internally uses Prototype's Element.update()).</li>

   <li>Append mode: Each content section may be configured as persisting
     its content from the previous call, switching the section into
     append mode.</li>

   <li>Three flavors:
     <ul>
         <li>buttonless info box (hidden via ESC) implemented in the
           ProtoPopup base class</li>

         <li>alert-like info box with 'Close' button implemented in
           ProtoPopup.Alert</li>

         <li>confirm-like prompt with 'OK' and 'Cancel' buttons
           implemented in ProtoPopup.Confirm</li>
     </ul></li>
   </ul>

*/

if (Prototype.Browser.IE) {
    Prototype.Browser.IEVersion = parseFloat(navigator.appVersion.split(';')[1].strip().split(' ')[1]);
}

/** ProtoPopup provides a button-less info box with header, body and
    footer fields.  Since it has no buttons, closing is done via the
    ESC key.
    @class
    @constructor
    @requires prototype-1.6.3.js -- the wellknown Ajax library, as well as Scriptaculous' effects.js and dragdrop.js
    @param {STRING} id A unique string identifying a popup
    @param {OBJECT} config The configuration object
    @return ProtoPopup object
    @type object



    @example
    var info = new ProtoPopup('info', {
        header     : new Element('div').update('Info header'),
        footer     : 'Info footer',
        appendBody : true
    });

    // Show the first info
    info.setHtml({body : 'Info 1'}).show();

    // Append a second info in bold
    info.setHtml({body : new Element('strong').update('Info 2')}).show();
*/
var ProtoPopup = Class.create(/** @lends ProtoPopup.prototype */{

    /** @ignore */
    initialize : function (id, config) {

        /**
           The ID of the popup's object and DIV.
         */
        this.id = id;

        /**
           The default configuration<br/>

           <div style="padding-left: 20px">

           <b>hideOnEscape</b> {BOOL} - If true hides the popup when
           pressing the ESC key. Defaults to true.<br/>

           <b>centerOnCreation</b> {BOOL} - Center the popup relative
           to the viewport when creating it. Lateron it will be placed
           where the user drags it to. The position is remembered
           across hiding/showing until a full page reload
           occurs. Defaults to true.<br/>

           <b>appendHeader</b> {BOOL} - If true, calls to {@link #setHtml}
           will append to the popup's header section.  Defaults to true.<br/>

           <b>appendBody</b> {BOOL} - If true, calls to {@link #setHtml}
           will append to the popup's body section.  Defaults to true.<br/>

           <b>appendFooter</b> {BOOL} - If true, calls to {@link #setHtml}
           will append to the popup's footer section. Defaults to true.<br/>

           <b>header</b> {STRING} - The initial value of the header
           section. Defaults to undefined.<br/>

           <b>body</b> {STRING} - The initial value of the footer
           section. Defaults to undefined.<br/>

           <b>footer</b> {STRING} - The initial value of the body
           section. Defaults to undefined.<br/>

           <b>width</b> {STRING} - The width of the popup. Defaults to
           300px.<br/>

           <b>documentRoot</b> {STRING} - The document root of the web
           application. Defaults to undefined.<br/>

           <b>zIndex</b> {NUMBER} - The z-index of the popup. Defaults
           to 0.<br/>

           </div>

        */
        this.config = {
            hideOnEscape     : true,
            centerOnCreation : true,            
            appendHeader     : false,
            appendBody       : false,
            appendFooter     : false,
            header           : undefined,
            body             : undefined,
            footer           : undefined,
            width            : '300px',
            documentRoot     : undefined,
            zIndex           : 0
        };

        // merge in the config
        Object.extend(this.config, (config || {}));

        // maybe attach keyUp handler to hide via ESC
        if (this.config.hideOnEscape) {
            Event.observe(document, 'keyup', this.hideOnEscape);
        }

        var popup = new Element('div', {id : id, 'class' : 'proto-popup'})
            .setStyle({width : this.config.width, zIndex : this.config.zIndex}).hide();
            
        /**
           The popup div having {@link #id} as its ID, 'proto-popup'
           as its class attribute.
         */
        this.popup = popup;

        // insert the cancel icon and attach click handler
        var src = this.config.documentRoot ? this.config.documentRoot + '/images/cancel.png' : 'images/cancel.png';
        popup.insert(new Element('img', {
            src     : src,
            'class' : 'proto-popup-cancel'
        }).observe('click', function(e) { popup.hide(); Event.stop(e) }));;

        /**
           Array holding the popup's section names 'header', 'body' and 'footer'.
         */
        this.sections = ['header', 'body', 'footer'];

        /**
           The popup's 'header' section is the popup's first DOM
           child. It's ID is "id+'-header'", it's class attribute
           'proto-popup-header'.   It's content is set via
           {@link #setHtml}.

           @name ProtoPopup.prototype.header

         */
        /**
           The popup's 'body' section is the popup's first DOM
           child. It's ID is "id+'-body'", it's class attribute
           'proto-popup-body'.  It's content is set via
           {@link #setHtml}.

           @name ProtoPopup.prototype.body

         */
        /**
           The popup's 'footer' section is the popup's first DOM
           child. It's ID is "id+'-footer'", it's class attribute
           'proto-popup-footer'.  It's content is set via
           {@link #setHtml}.

           @name ProtoPopup.prototype.footer

         */
        this.sections.each(function(section) {
                this[section] = new Element('div', {id : id+'-'+section, 'class' : 'proto-popup-'+section}).hide();
                popup.insert(this[section]);
        }.bind(this));

        // append to document body
        document.body.appendChild(this.popup);

        // make it draggable
        new Draggable(id);
        
        // normally it's position:fixed, but IE6- does not understand it
        if (Prototype.Browser.IEVersion < 7) {
            popup.setStyle({position: 'absolute'});
        }

        // set HTML
        this.setHtml(this.config);

        // remember us
        ProtoPopup.id2obj[id] = this;

        /**
           Array of functions that will be executed at the end of the
           popup initialization.
         */
        this.onShow = [];
    },

    /**
       Fired when the ESC key is pressed and the config option
       hideOnEscape is true (which is the default).
       @event
     */
    hideOnEscape : function(event) {
        if (event.keyCode == 27) { // KEY_ESC
            Object.keys(ProtoPopup.id2obj).each(function(pp) {
                    if (ProtoPopup.id2obj[pp].config.hideOnEscape) {
                        ProtoPopup.id2obj[pp].hide();
                    }
            });
        }

    }.bindAsEventListener(this),

    /**
       Chainable instance method to set the HTML in any of the three popup
       sections 'header', 'body' or 'footer'.

       @param config An object whose keys represent said three
       sections.  The corresponding values can be plain text, HTML, a
       DOM node or any object having a toHTML() method.

       @example
       var info = new ProtoPopup('info');
       info.setHtml({header : 'Info header', body : 'My Info'});
    */
    setHtml : function(config) {
        this.sections.each(function(section) {
                if (config && config[section] != undefined) {
                if (!this.config['append'+section.capitalize()]) {
                    this[section].innerHTML = '';
                    
                }
                this[section].insert(config[section]).show();
            }
        }.bind(this));
        return this;
    },

    /**
       Chainable instance method to show the popup.
       @example
       var info = new ProtoPopup('info', {header : 'Info header'});
       info.setHtml({body : 'My Info'}).show();
    */
    show : function() {
        this.popup.show();
        if (this.config.centerOnCreation) {
            this.centerIt();
            this.config.centerOnCreation = false;
        }
        this.onShow.each(function(f) {
            if (Object.isFunction(f)) f.defer();
        });
        return this;
    },

    /**
       Chainable instance method to hide the popup.
       @example
       var info = new ProtoPopup('info', {header : 'Info header'});
       info.setHtml({body : 'My Info'}).show();

       // hide 3 seconds later after showing it
       setTimeout(function() {pinfo.hide()}, 3000);

    */
    hide : function() {
        this.popup.hide();
        return this;
    },

    /**
       Chainable instance method to center the popup horizontally and
       vertically on the viewport.  Internally called by {@link #show}.
    */
    centerIt : function() {
        windowDim = document.viewport.getDimensions();
        popupDim  = this.popup.getDimensions();

        centerX = Math.round(windowDim.width / 2) 
            - (popupDim.width  / 2) + 'px';

        centerY = Math.round(windowDim.height/ 2) 
            - (popupDim.height / 2) + 'px';

        this.popup.setStyle({left: centerX, top: centerY});

        return this;
    },

    /**
       Non-chainable instance method to create and return a button element.
       This method is not used by ProtoPopup, but by its child classes
       {@link ProtoPopup.Alert} and {@link ProtoPopup.Confirm}.<br><br>

       It's CSS class is "'proto-popup-'+name+'-btn'".

    */
    makeButton : function(name) {
        return new Element('input', {
            type    : 'button',
            value   : this.config[name+'BtnLabel'],
            'class' : 'proto-popup-'+name+'-btn'
        });
   }
});

/**
   Class method returning get() methods for ProtoPopup and its
   derivations.
   @param newProtoPopup Function returning a constructor making ProtoPopup or
   one of derivative objects.
   @return get() method
*/
ProtoPopup.makeGetFor = function(newProtoPopup) {
    return function(id, config) {
        var pp;
        if (pp = ProtoPopup.id2obj[id]) {
            // we have it
            pp.setHtml(config);
            return pp;
        }
        // create it
        pp = newProtoPopup(id, config);
        return pp;
    }
}

/**
   Class method returning makeFunction() methods for ProtoPopup and its
   derivations.
   @param newProtoPopup Function returning a constructor making ProtoPopup or
   one of derivative objects.
   @return get() method
*/
ProtoPopup.makeMakeFunction = function(newProtoPopup) {
    return function(id, config) {
        var pp;
        if (Object.isUndefined(pp)) {
            pp = newProtoPopup(id, config);
            if (config && config.arg) {
                // attach original object
                config.arg.callee.obj = pp;
            }
        }
        return function(msg) {
            pp.setHtml({body : msg}).show();
        }
    }
}

/**
   Class method returning (maybe first create) a draggable popup DIV
   for info boxes.  Given the same id argument returns the same popup
   object, following the singleton pattern.
   @function
   @param {STRING} id The ID of the popup.
   @param {OBJECT} config The {@link #config} object.
   @return The initialized and draggable popup.
   @example Make a custom info() method serving as a convenient wrapper.

   The popup shown by info() will always have the string
   'Newest Information' in the popup's header section, while the
   argument passed to info() will be wrapped in a DIV that
   will be inserted in the popup's body section.
   
        // make the custom info function
        var info = function(msg) {
            ProtoPopup.get('info', {
                header     : 'Info header',
                body       : new Element('div').update(msg),
            });
        }

        // first use
        info('My first info');

        // second use (using the same popup, showing the same header)
        info('My second info'); 
*/
ProtoPopup.get = ProtoPopup.makeGetFor(function(id, config) {
    return new ProtoPopup(id, config)
});

/**
   Class method making custom functions accepting one argument that
   will be inserted in the body section of the underlying ProtoPopup
   object created behind the scenes.
   @function
   @param {STRING} id The ID of the popup.
   @param {OBJECT} config The {@link #config} object.
   @return A function accepting one argument to be inserted into the
   popup's body section.
   @example Make a custom info() method

      // make the method
      var info = ProtoPopup.makeFunction('info', {
          header : 'Announcement'
      });

      // first use
      info('Forget this info');

      // second use (using the same popup, showing the same header
      info('Forget this info, too');
*/
ProtoPopup.makeFunction = ProtoPopup.makeMakeFunction(function(id, config) {
    return new ProtoPopup(id, config);
});

/**
   Object mapping popup IDs to popup objects.
*/
ProtoPopup.id2obj = {};
