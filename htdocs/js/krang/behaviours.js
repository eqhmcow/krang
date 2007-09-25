var rules = {
    'a.popup' : function(el) {
        el.observe('click', function(event) {
            var sizes = { width: 400, height: 600 };
            if( el.hasClassName('small') ) {
                sizes.width  = 300;
                sizes.height = 300;
            }
            Krang.popup(this.readAttribute('href'), sizes);
            Event.stop(event);
        }.bindAsEventListener(el));
    },
    'a.ajax' : function(el) {
        el.observe('click', function(event) {
            var matches = this.href.match(/(.*)\?(.*)/);
            Krang.Ajax.update({
                url       : matches[1],
                params    : matches[2].toQueryParams(),
                div       : Krang.class_suffix(el, 'for_'),
                indicator : Krang.class_suffix(el, 'show_')
            });
            Event.stop(event);
        }.bindAsEventListener(el));
    },
    'form' : function(el) {
        // if we have an on submit handler, then we don't want to
        // do anything automatically
        if( el.onsubmit ) return;

        // now change the submission to use Krang.form_submit
        el.observe('submit', function(e) {
            Krang.form_submit(el);
            Event.stop(e);
        });
    },
    // create an autocomplete widget. This involves creating a div
    // in which to place the results and creating an Ajax.Autocompleter
    // object. We only do this if the use has the "use_autocomplete"
    // preference.
    // Can specifically ignore inputs by giving them the 'non_auto' class
    'input.autocomplete' : function(el) {
        // ignore 'non_auto'
        if( el.hasClassName('non_auto') ) return;
        var pref = Krang.my_prefs();
        if( pref.use_autocomplete ) {
            // add a new div of class 'autocomplete' right below this input
            var div = Builder.node('div', { className: 'autocomplete', style : 'display:none' }); 
            el.parentNode.insertBefore(div, el.nextSibling);

            // the request_url is first retrieved from the action of the form
            // and second from the url of the current document.
            var request_url = el.form.readAttribute('action')
                || document.URL;

            new Ajax.Autocompleter(
                el,
                div,
                request_url,
                { 
                    paramName: 'phrase',
                    tokens   : [' '],
                    callback : function(el, url) {
                        url = url + '&rm=autocomplete';
                        return url;
                    }
                }
            );
        }
    },
    // if a checkbox is selected in this table, then highlight
    // the row that checkbox belongs to
    'table.select_row tbody input.hilite-row' : function(el) {
        if( el.checked ) el.addClassName('hilite');
        el.observe('click', function(event) {
            var clicked = Event.element(event);
            clicked.up('tr').toggleClassName('hilite');
        }.bindAsEventListener(el));
    },
    '#error_msg_trigger' : function(el) {
        Krang.Error.modal = new Control.Modal(el, {
            opacity  : .6,
            zindex   : 999,
            position : 'absolute',
            mode     : 'named'
        });
    },
    //IE6 requires a little help with the flyout navigation menuing:
    '#H .nav .menu' : function( el ) {
        if ( Krang.is_ie_6() )
            el.onmouseover = el.onmouseout = function(){ this.toggleClassName( 'over' ); };
    }
};

Behaviour.register( rules );

