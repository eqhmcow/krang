/** @fileoverview ProtoPopup.Alert is based on ProtoPopup and ads a 'Close' button to its
    base object.
*/

/** ProtoPopup.Alert is based on ProtoPopup and ads a 'Close' button to its
    base object.
    @class Creates a ProtoPopup.Alert object
    @constructor
    @augments ProtoPopup
    @param {STRING} id A unique string identifying a popup
    @param {OBJECT} config The configuration object {@link #.config}
    @return ProtoPopup.Alert object
    @property {object} config The default configuration inherited from
    {@link ProtoPopup#config} augmented with:
    <div style="padding-left: 20px">
       <b>closeBtnLabel:</b> The label of the "Close" button inserted
       in the popup's footer section. Defaults to 'Close'.<br/>
       <b>closeBtnBackgroundImage</b> {STRING} - CSS property
       'background-image' for the close button. Defaults to
       undefined.
    </div>
*/
ProtoPopup.Alert = Class.create(ProtoPopup, /** @lends ProtoPopup.Alert.prototype */{
    /** @ignore */
    initialize : function($super, id, config) {
        _config = {
        closeBtnLabel : 'Close',
            closeBtnBackgroundImage: undefined
        };
        Object.extend(_config, (config || {}));
        $super(id, _config);

        // insert 'Close' button
        var closeBtn = this.closeBtn = this.makeButton('close');
        this.footer.insert(this.closeBtn).show();

        // focus the Close button
        this.onShow.push(setTimeout(function() {closeBtn.focus()}, 100));

        // attach click handler to close button
        var hide = this.hide.bind(this);
        Event.observe(closeBtn, 'click', hide);
        
    }            
});

/**
   Class method returning (maybe first create) a draggable popup DIV
   for alert dialogs.  Given the same id argument returns the same
   popup object, following the singleton pattern. See the example of
   the base class' {@link ProtoPopup.get}
   @function
   @param {STRING} id The name of the popup used to build its ID.
   @param {OBJECT} config The config object, see {@link #.config}.
   @return The initialized and draggable popup.
*/
ProtoPopup.Alert.get = ProtoPopup.makeGetFor(function(id, config) {
    return new ProtoPopup.Alert(id, config)
});

/**
   Class method making custom functions accepting one argument that
   will be inserted in the body section of the underlying
   ProtoPopup.Alert object created behind the scenes.
   @function
   @param {STRING} id The ID of the popup.
   @param {OBJECT} config The {@link #config} object.
   @return A function accepting one argument to be inserted into the
   popup's body section.
   @example Make a custom info() method

      // make the method
      var info = ProtoPopup.Alert.makeFunction('info', {
          header : 'Critical Warning'
      });

      // first use
      info('Something's wrong!');

      // second use (using the same popup, showing the same header
      info('Something's really wrong!');
*/
ProtoPopup.Alert.makeFunction = ProtoPopup.makeMakeFunction(function(id, config) {
    return new ProtoPopup.Alert(id, config);
});
