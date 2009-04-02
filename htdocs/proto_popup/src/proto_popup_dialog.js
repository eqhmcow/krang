/** @fileoverview ProtoPopup.Dialog is based on ProtoPopup and ads 'OK' and
    'Cancel' buttons to its base object.
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

       <b>name:</b> The name will be used to build the ID of the button. Give
       a popup ID 'dialog' and a button name 'save', the button's ID will be 'dialog-save-btn'<br/>

       <b>label:</b> The label of the button.<br/>

       <b>onClick:</b> The callback function executed when the button is clicked.<br/>

       <b>giveFocus:</b> A boolean specifying whether the button should be focused when the popup is displayed.<br/>

       <b>backgroundImage</b> {STRING} - CSS property
       'background-image' for the button. Defaults to
       undefined.<br/>
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
            this.footer.insert(btn).show();
            if (spec.giveFocus) { this.onShow.push(function() {btn.focus()}) }

            // attach handler
            var clickHandler = function(e) {
                this.hide();
                spec.onClick();
            }.bind(this);

            Event.observe(btn, 'click', clickHandler);

        }.bind(this));
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

