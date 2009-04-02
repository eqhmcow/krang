/** @fileoverview ProtoPopup.Confirm is based on ProtoPopup and ads 'OK' and
    'Cancel' buttons to its base object.
*/

/** ProtoPopup.Confirm is based on ProtoPopup and ads 'OK' and
    'Cancel' buttons to its base object.
    @class Creates a ProtoPopup.Confirm object
    @constructor
    @augments ProtoPopup
    @param {STRING} id A unique string identifying a popup
    @param {OBJECT} config The configuration object {@link #.config}
    @return ProtoPopup.Confirm object
    @property {object} config The default configuration inherited from
    {@link ProtoPopup#config} augmented with:
    <div style="padding-left: 20px">
       <b>okBtnLabel:</b> The label of the "OK" button inserted
       in the popup's footer section. Defaults to 'OK'.<br/>
       <b>cancelBtnLabel:</b> The label of the "Cancel" button inserted
       in the popup's footer section. Defaults to 'Cancel'.<br/>

       <b>onOk:</b> The callback executed when the 'OK' button is
       clicked. Defaults to the empty function.<br/>

       <b>onCancel:</b> The callback executed when the 'Cancel' button
       is clicked. Defaults to the empty function.<br/>

       <b>okBtnBackgroundImage</b> {STRING} - CSS property
       'background-image' for the ok button. Defaults to
       undefined.<br/>

       <b>cancelBtnBackgroundImage</b> {STRING} - CSS property
       'background-image' for the cancel button. Defaults to
       undefined.<br/>
    </div>
*/
ProtoPopup.Confirm = Class.create(ProtoPopup, /** @lends ProtoPopup.Confirm.prototype */{
        /** @ignore */
    initialize : function($super, id, config) {
        var _config = {
            okBtnLabel     : 'OK',
            cancelBtnLabel : 'Cancel',
            onOk           : Prototype.emptyFunction,
            onCancel       : Prototype.emptyFunction,
            okBtnBackgroundImage:     undefined,
            cancelBtnBackgroundImage: undefined
        };
        Object.extend(_config, (config || {}));
        $super(id, _config);

        // make the buttons
        var cancelBtn = this.cancelBtn = this.makeButton('cancel', this.config.cancelBtnLabel);
        var okBtn     = this.okBtn     = this.makeButton('ok',     this.config.okBtnLabel);
        this.footer.insert(cancelBtn).show().insert(okBtn).show();

        // focus the OK button
        this.onShow.push(function() {okBtn.focus()});

        // attach click handler
        var onCancel = function() { this.hide(); this.config.onCancel() }.bind(this);
        Event.observe(cancelBtn, 'click', onCancel);

        var onOk  = function() { this.hide(); this.config.onOk() }.bind(this);
        Event.observe(okBtn, 'click', onOk);
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
ProtoPopup.Confirm.get = ProtoPopup.makeGetFor(function(id, config) {
    return new ProtoPopup.Confirm(id, config)
});

/**
   Class method making custom functions accepting one argument that
   will be inserted in the body section of the underlying
   ProtoPopup.Confirm object created behind the scenes.
   @function
   @param {STRING} id The ID of the popup.
   @param {OBJECT} config The {@link #config} object.
   @return A function accepting one argument to be inserted into the
   popup's body section.
   @example Make a custom info() method

      // make the method
      var info = ProtoPopup.Confirm.makeFunction('info', {
          header : 'Question'
      });

      // first use
      info('This or That');

      // second use (using the same popup, showing the same header
      info('To be or not to be');
*/
ProtoPopup.Confirm.makeFunction = ProtoPopup.makeMakeFunction(function(id, config) {
   return new ProtoPopup.Confirm(id, config);
});

