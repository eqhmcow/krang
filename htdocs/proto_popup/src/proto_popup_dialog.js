/** @fileoverview ProtoPopup.Dialog is based on ProtoPopup and the capability to add arbitrary buttons to the 'header' and/or the 'footer' sections.
*/

/** ProtoPopup.Dialog is based on ProtoPopup and ads 'OK' and
    'Cancel' buttons to its base object.
    @class Creates a ProtoPopup.Dialog object
    @constructor
    @augments ProtoPopup
    @param {STRING} id A unique string identifying a popup
    @param {OBJECT} config The configuration object {@link #.config}
    @return ProtoPopup.Dialog object
    @property {object} config The default configuration inherited from
    {@link ProtoPopup#config} augmented with:
    <div style="padding-left: 20px">
       <b>buttons:</b> An array of button specs objects. The buttons are inserted
       into the footer in the order they are specified.<br/><br/>

       <b>A button spec object takes the following keys:</b><br/><br/>

       <b>name:</b> The name will be used to build the ID of the button. Given
       a popup ID 'dialog' and a button name 'save', the button's ID will be 'dialog-save-btn'<br/>

       <b>label:</b> The label of the button.<br/>

       <b>vertical:</b> Buttons may be located in the 'header' or the 'footer' sections. Defaults to 'footer'.<br/>

       <b>horizonal:</b> Buttons may be 'left' or 'right'-aligned. Defaults
       to 'left'. When multiple buttons are left-aligned, the layout follows
       the buttons array order. The same holds true for right-aligned
       buttons.<br/>

       <b>giveFocus:</b> A boolean specifying whether the button should be focused when the popup is displayed.<br/>

       <b>backgroundImage</b> {STRING} - CSS property
       'background-image' for the button. Defaults to
       undefined.<br/><br/>

       <b>Additionally</b> all button spec keys starting with <b>on</b> will be
       interpreted as having an <b>event handler</b> as their value.  E.g. <b>onclick</b>
       must be a callback function called when the button is
       clicked. Similarly for all the other events supported by
       HTMLInputElements.

    </div>
*/
ProtoPopup.Dialog = Class.create(ProtoPopup, /** @lends ProtoPopup.Dialog.prototype */{
    /** @ignore */
    initialize : function($super, id, config) {
        var _config = {
            buttons: []
        };
        Object.extend(_config, (config || {}));
        $super(id, _config);
        
        // make the buttons
        this.config.buttons.each(function(spec) {
            var btn  = this.makeButton(spec.name, spec.label);

            // insert button in header or footer?
            var where = this.getBtnParent(spec);
            where.insert(btn).show();

            // focus it?
            if (spec.giveFocus) { this.onShow.push(function() {btn.focus()}) }

            // attach handler
            $H(spec).each(function(option) {
                var oName = option.key;

                // is it an event handler?
                if (! /^on/.test(oName)) return;

                Event.observe(btn, oName.replace('on', '').toLowerCase(), option.value);
            });
        }.bind(this));
    },

    getBtnParent: function(spec) {
        var horizontal = spec.horizontal ? spec.horizontal : 'left';
        var vertical   = spec.vertical   ? spec.vertical   : 'footer';

        var section = this[vertical];
        var first   = section.firstDescendant();
        if (!(first && first.nodeName.toLowerCase() == 'table')) {
            section.insert('<table id="'+this.id+'-btn-table" border="0" cellpadding="0" cellpadding="0" class="proto-popup-btn-table"><tbody><td id="'+this.id+'-buttons-'+vertical+'-left" class="proto-popup-buttons-left"></td><td id="'+this.id+'-buttons-'+vertical+'-right" class="proto-popup-buttons-right"></td></tbody></table>');
        }

        return $(this.id+'-buttons-'+vertical+'-'+horizontal);
    }
});

/**
   Class method returning (maybe first create) a draggable popup DIV
   for confirm dialogs.   Given the same id argument returns the same popup
   object, following the singleton pattern. See the example of
   the base class' {@link ProtoPopup.get}
   @function
   @param {STRING} id The name of the popup used to build its ID.
   @param {OBJECT} config The config object, see {@link #.config}.
   @return The initialized and draggable popup.
*/
ProtoPopup.Dialog.get = ProtoPopup.makeGetFor(function(id, config) {
    return new ProtoPopup.Dialog(id, config)
});

