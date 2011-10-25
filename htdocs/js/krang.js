/*
Maybe create the Krang namespace.
*/
var Krang;
if (typeof Krang == 'undefined') {
    Krang = {};
}

/**
   Krang.debug("Some debug message");

   A simple wrapper around console.debug with a switch to switch it on
   and off.

   Krang.debug.on();
   Krang.debug("bla");
   Krang.debug.off();
*/
(function() {

    var debugOn = false;

    // wrapper around console.debug
    Krang.debug = function(msg) {
        if (debugOn) {
            console.debug(msg);
        }
    }

    // switch
    Krang.debug.on  = function() { debugOn = true  };
    Krang.debug.off = function() { debugOn = false };
})();

/*
  Know IE version (stolen from http://prototype-ui.com)
*/
if (Prototype.Browser.IE) {
    Prototype.Browser.IEVersion = parseFloat(navigator.appVersion.split(';')[1].strip().split(' ')[1]);
}


/*
    Krang.preload_img('/path/to/image')

    This function simply preloads images into the browser
    so that when they are requested later they won't cause
    any "jitteriness" as the browser fetches them and loads them
*/
Krang.preload_img = function(path) {
    var img = new Image();
    img.src = path;
};

/*
    Krang.load([target])
    Applies all the loaded behaviours to the current document.
    Called at the end of each page. We avoid putting this into
    document.onload since that means it waits on pulling in
    all images, etc.

    Optionally receives a target (either id, or element object)
    for which to apply the behaviors.
*/
Krang.run_code = function(code_array) {
    var size = code_array.length;
    for(var i=0; i< size; i++) {
        var code = code_array.shift();
        if( code ) code();
    }
}
Krang.load = function(target) {
    // apply our registered behaviours
    Behaviour.apply($(target));

    // run any code from Krang.onload()
    Krang.run_code(Krang.onload_code);

    // show messages and alerts that have been added
    Krang.Messages.show('alerts');
    Krang.Messages.show();

    // apply behaviours to slide-in messages and alerts
    Behaviour.apply($('messages'));
    Behaviour.apply($('alerts'));
};

/*
    Krang.is_ie()

    Since there are lots of places where you have to work around IE
    this at least let's you check it easier.
*/
Krang.is_ie = function() {
    return Prototype.Browser.IEVersion > 0;
}

/*
    Krang.is_ie_6()

    Since there are lots of places where you have to work around IE 6
    this at least let's you check it easier.
*/
Krang.is_ie_6 = function() {
    return Prototype.Browser.IEVersion == 6;
}

/*
    Krang.is_ie_7()

    Since there are places where you have to work around IE 7
    this at least let's you check it easier.
*/
Krang.is_ie_7 = function() {
    return Prototype.Browser.IEVersion == 7;
}

/*
    Krang.onload()
    Add some code that will get executed after the DOM is loaded
    (but without having to wait on images, etc to load).
    Multiple calls will not overwrite previous calls and all code
    given will be executed in the order give.
*/
Krang.onload_code = [];
Krang.onload = function(code) {
    Krang.onload_code.push(code);
};

/*
    Krang.onunload()
    Add some code that will get executed after the page is unloaded,
    or a new AJAX request happens to replace the current '#C' content.
    Multiple calls will not overwrite previous calls and all code
    given will be executed in the order give.
*/
Krang.onunload_code = [];
Krang.onunload = function(code) {
    Krang.onunload_code.push(code);
};
Krang.unload = function() {
    // run any code from Krang.onunload()
    Krang.run_code(Krang.onunload_code);
}
var oldOnUnload = document.onunload || Prototype.emptyFunction;
document.onunload = function() {
    Krang.unload();
    oldOnUnload();
}

/*
    // Log out the current window
    Krang.Window.log_out();

*/
Krang.Window = {
    log_out : function() {
        if (!Krang.Nav.edit_mode_flag || confirm(Krang.Nav.edit_message)) {
            window.location = 'login.pl?rm=logout';
            window.name = '';
        }
    }
};

Krang.Window.pass_id = function(url) {
    if (console) console.warn("Krang.Window.pass_id is deprecated");
    return url;
};

Krang.Window.init = function() {
    if (console) console.warn("Krang.Window.init is deprecated");
    return;
};

/*
    // Set Krang instance (returns the argument)
    Krang.Instance.set('Default');

    // Get Krang instance. Returns instance set with Krang.Instance.set()
    var instance = Krang.Instance.get();

*/
(function() {
    var _instance;

    Krang.Instance = {};

    Krang.Instance.set = function(instance) {
        return _instance = instance;
    }

    Krang.Instance.get = function() {
        return _instance;
    }
})();


/*
    Krang.popup(url, { width: 400, height: 600 })
    Open the url into a new popup window consistently.
    Width and height default to 800x600
*/
Krang.popup = function(url, options) {
    if( ! options ) options = {};
    var height = options.height || 600;
    var width  = options.width  || 800;

    if (Prototype.Browser.IE) {
        // we need the referer to be sent
        // see http://webbugtrack.blogspot.com/search/label/HTTP%20Referer
        // the 'target' attribute takes arbitrary values in IE6/7 (undocumented)
        var a = new Element('a', {href : url });
        a.target = 'krangpopup';
        document.body.appendChild(a);
        a.click();
    } else {
        var win = window.open(
            url,
            'krangpopup',
            'width=' + width + ',height=' + height + ',top=25,left=50,resizable,scrollbars,status'
        );
        if ( win ) win.focus();
    }
};

/*
    // Returns the value of a specific cookie.
    Krang.Cookie.get(name)

    // Sets a cookie to a particular value.
    Krang.Cookie.set(name, value)
*/
Krang.Cookie = {
    get : function(name) {
        var value  = null;
        var cookie = document.cookie;
        var start, end;

        if (cookie.length > 0) {
            start = cookie.indexOf(name + '=');

            // if the cookie exists
            if (start != -1)  {
                start += name.length + 1; // need to account for the '='

                // set index of beginning of value
                end = cookie.indexOf(';', start);

                if (end == -1) end = cookie.length;

                value = decodeURIComponent(cookie.substring(start, end));
            }
        }
        return value;
    },
    set : function(name, value) {
    document.cookie = name + '=' + encodeURIComponent(value) + "; path=/";
    },
    json_get : function(name) {
        var json = Krang.Cookie.get(name);
        return json.evalJSON()
    }
}


/*
    Krang.my_prefs()
    Returns a hash of preferences values from the server
    (passed to use via a JSON cookie)
*/
Krang.my_prefs = function() { return Krang.Cookie.json_get('KRANG_PREFS') }

/*
    Krang.config()
    Returns a hash of config information values from the server
    (passed to use via a JSON cookie)
*/
Krang.config = function() { return Krang.Cookie.json_get('KRANG_CONFIG') }


// Krang.AJAX namespace
Krang.Ajax = {
    _encode_params : function(params) {
        // only encode to Base64 if our character set is not utf-8
        var config = Krang.config();
        if(config.charset == 'utf-8' || config.charset == 'UTF-8') return;

        for(var n in params) {
            // if it's an object/array (happens with same named elements)
            // then we need to encode each element
            if( typeof params[n] == 'object' ) {
                var list = params[n];
                for(var i=0; i<list.length; i++) {
                    list[i] = Krang.Base64.encode(list[i]);
                }
                params[n] = list;
            } else {
                params[n] = Krang.Base64.encode(params[n]);
            }
        }
        params.base64 = 1;
    },
    toQueryParams : function(str) {
        var params;
        if( str.match(/;/) ) {
            params = str.toQueryParams(';');
        } else {
            params = str.toQueryParams();
        }
        return params;
    },
    is_double_click : function(url, params) {
        var hash_key = url;
        $H(params).keys().each(function(k) {
            hash_key = hash_key + k + '=>' + params[k] + ';';
        });

        var last_time = Krang.Ajax._last_submitted[hash_key] || 0;
        var now = new Date();
        now = now.valueOf(); // now is now in milliseconds

        // if it's older than 2 seconds, then it's ok
        if( last_time + 2000 < now ) {
            Krang.Ajax._last_submitted[hash_key] = now;
            return false;
        } else {
            if( console && console.log ) {
                console.log("Preventing double click submission");
            }
            return true;
        }
    },
    // hash of last time a request was submitted so that we can prevent people
    // who don't know how web applications work from double clicking
    _last_submitted : { }
};
/*
    Krang.Ajax.request({ url: 'story.pl' })
    Creates an Ajax.Updater object with Krang's specific needs
    in mind.
    Takes the following args in it's hash:

    url       : the url of the request (required)
    method    : the HTTP method. (optional defaults to 'get')
    params    : a hash of params for the request
    indicator : the id of the image to use as an indicator (optional defaults to 'indicator')
    onComplete: a callback function to be executed after the normal processing (optional)
                Receives as arguments, the same args passed into Ajax.update() the AJAX response
                object, and any JSON object returned in the X-JSON HTTP header.
    onFailure : a callback function to be executed in case of an error. Receives as arguments
                the AJAX response object and the exception thrown. This is in addition to the
                normal error message the Krang will show to in the UI.

    Krang.Ajax.request({
        url        : '/app/some_mod/something',
        params     : {
            rm  : 'foo',
            bar : '123'
        },
        indicator  : 'add_indicator',
        onComplete : function(args, response, json) {
            // do something
        },
        onFailure  : function(response, exception) {
            // do something
        }
    });
*/
Krang.Ajax.request = function(args) {
    var url       = args['url'];
    var params    = args['params'] || {};
    var indicator = args['indicator'];
    var complete  = args['onComplete']  || Prototype.emptyFunction;
    var success   = args['onSuccess']   || Prototype.emptyFunction;
    var failure   = args['onFailure']   || Prototype.emptyFunction;
    var exception = args['onException'] || Prototype.emptyFunction;
    var method    = args['method'] || 'get';

    // stop double clicks
    if(Krang.Ajax.is_double_click(url, params)) return;

    // tell the user that we're doing something
    Krang.show_indicator(indicator);

    // encode the params so that we can remain encoding-neutral
    Krang.Ajax._encode_params(params);

    // add the ajax=1 flag to the existing query params
    params['ajax'] = 1;

    new Ajax.Request(
        url,
        {
            parameters  : params,
            method      : method,
            evalScripts : true,
            asynchronous: true,
            onSuccess   : function(response, json) { 
                // not in edit mode (can be reset by the request)
                Krang.Nav.edit_mode(false);
                // wait 12 ms so we know that the JS in our request has been evaled
                // since Prototype will wait 10 gives for the Browser to update
                // it's DOM
                setTimeout(function() {
                    // hide the indicator
                    Krang.hide_indicator(indicator);
                    // do whatever else the user wants
                    success(args, response, json);
                }, 12);
            },
            onComplete  : function(response, json) {
                // wait 12 ms so we know that the JS in our request has been evaled
                // since Prototype will wait 10 gives for the Browser to update
                // it's DOM
                setTimeout(function() {
                    // hide the indicator
                    Krang.hide_indicator(indicator);
                    // do whatever else the user wants
                    complete(args, response, json);
                }, 12);
            },
            onFailure   : function(response, e) {
                failure(response, e);
                Krang.Error.show();
                if( console && console.error ) {
                    console.error(e);
                }
            },
            onException : function(response, e) {
                exception(response, e);
                Krang.Error.show();
                if( console && console.error ) {
                    console.error(e);
                }
            }
        }
    );
};

/*
    Krang.Ajax.update({ url: 'story.pl' })
    Creates an Ajax.Updater object with Krang's specific needs
    in mind.
    Takes the following args in it's hash:

    url       : the url of the request (required)
    method    : the HTTP method to use (optional defaults to 'get')
    params    : a hash of params for the request
    target    : the id of the target element receiving the contents (optional defaults to 'C').
                this can also be a function which will be executed (with the same arguments
                as the onComplete callback) after the request is done to determine what the
                target is. This is useful if you don't know the target ahead of time.
    indicator : the id of the image to use as an indicator (optional defaults to 'indicator')
    to_top    : whether or not the page should scroll back up to the top after the update.
                Defaults to true.
                This can also be a function which will be executed (with the same arguments
                as the onComplete callback) after the request is done to determine what the
                value is. This is useful if you don't know what's appropriate ahead of time.
    onComplete: a callback function to be executed after the normal processing (optional)
                Receives as arguments, the same args passed into Ajax.update() the AJAX response
                object, and any JSON object returned in the X-JSON HTTP header.
    onSuccess : a callback function to be executed only after a successful request (optional)
                Receives as arguments, the same args passed into Ajax.update() the AJAX response
                object, and any JSON object returned in the X-JSON HTTP header.
    onFailure : a callback function to be executed in case of an error. Receives as arguments
                the AJAX response object and the exception thrown. This is in addition to the
                normal error message the Krang will show to in the UI.

    Krang.Ajax.update({
        url        : '/app/some_mod/something',
        params     : {
            rm  : 'foo',
            bar : '123'
        },
        target     : 'target_name',
        indicator  : 'add_indicator',
        onComplete : function(args, response, json) {
          // do something
        },
        onSuccess  : function(args, response, json) {
          // do something
        },
        onFailure  : function(response, exception) {
          // do something
        }
    });
*/
Krang.Ajax.update = function(args) {
    var url       = args.url;
    var method    = args.method || 'get';
    var params    = args.params || {};
    var target    = args.target;
    var indicator = args.indicator;
    var complete  = args.onComplete     || Prototype.emptyFunction;
    var success   = args.onSuccess      || Prototype.emptyFunction;
    var failure   = args.onFailure      || Prototype.emptyFunction;
    var exception = args['onException'] || Prototype.emptyFunction;
    var to_top    = args.to_top == false ? false : true; // defaults to true

    if( typeof args.to_top == 'function' ) {
        to_top = args.to_top;
    } else if( args.to_top == false ) {
        to_top = false;
    } else {
        to_top = true;
    }

    // stop double clicks
    if(Krang.Ajax.is_double_click(url, params)) return;

    // tell the user that we're doing something
    Krang.show_indicator(indicator);

    // encode the params so that we can remain encoding-neutral
    Krang.Ajax._encode_params(params);

    // add the ajax=1 flag to the existing query params
    params['ajax'] = 1;

    // the default target
    if( target == null || target == '' ) target = 'C';

    // run the unloader if we are targetting C
    if( target == 'C' ) Krang.unload();

    new Ajax.Request(
        url,
        {
            parameters  : params,
            method      : method,
            evalScripts : true,
            asynchronous: true,
            // if we're successful we're not in edit mode (can be reset by the request)
            onSuccess   : function(response, json) {
                // update the target. This is what Ajax.Updater does behind the scenes, but
                // we need to control it ourselves so we can have target be a function 
                var receiver = (typeof target) == 'function' ? target(response, json) : target;
                receiver = $(receiver);
                receiver.update(response.responseText);

                Krang.Nav.edit_mode(false);
                if(to_top) {
                    if( typeof to_top == 'function' ) {
                        if( to_top(response, json) ) {
                            Krang.to_top();
                        }
                    } else {
                        Krang.to_top();
                    }
                }
                // wait 12 ms so we know that the JS in our request has been evaled
                // since Prototype will wait 10 gives for the Browser to update
                // it's DOM
                setTimeout(function() {
                    // user callback
                    success(args, response, json);
                }, 12);

                // update the navigation if we need to
                if( json && json.krang_update_nav ) {
                    Krang.Ajax.update({ url: 'nav.pl', target: 'S', to_top: false });
                }
            },
            onComplete  : function(response, json) {
                // wait 12 ms so we know that the JS in our request has been evaled
                // since Prototype will wait 10ms to give the browser time to update
                // it's DOM. Why it's not immediate beats me.
                setTimeout(function() {
                    // reapply any dynamic bits to the target that was updated
                    var receiver = (typeof target) == 'function' ? target(response, json) : target;
                    Krang.load(receiver);
                    // user callback
                    complete(args, response, json);
                    // hide the indicator
                    Krang.hide_indicator(indicator);
                }, 12);
            },
            onFailure   : function(response, e) {
                // user callback
                failure(response, e);
                Krang.Error.show();
                if( console && console.error ) {
                    console.error(e);
                }
            },
            onException : function(response, e) {
                // user callback
                exception(response, e);
                Krang.Error.show();
                if( console && console.error ) {
                    console.error(e);
                }
            }
        }
    );
};

/*
    Krang.Form.set(form, { input: 'value'})
    Select a form (can be either the name of the form, or the form object
    itself) and set the values of its inputs

    Krang.Form.get(form, input);
    Select a form (can be either the name of the form, or the form object
    itself) and get the value of an input

    Krang.Form.get_field(form, input);
    Returns the HTML object representing the input field of the form.

    Krang.Form.get_form(form_name);
    Returns the HTML Form object given a form's name.

    Krang.Form.has_file_field(form_name)
    Returns true if the given form has a file field that has a value (and
    needs a "multipart/form-data" submission thus can't use AJAX)

    Krang.Form.study(form_name)
    This method will look at a form and make note of it's state. This combined
    with Krang.Form.has_form_changed() will let you know if a form was changed
    by the user.

    Krang.Form.has_form_changed(form_name)
    This method will return true if the a form has been changed, false otherwise
    as long as the form was first studied by Krang.Form.study_form.

    Krang.Form.submit(form, { input: 'value' }, { new_window: true })
    Select a form (can either be the name of the form, or the form object
    itself) optionally sets the values of those elements and then submits
    the form.

    You can also specify a third parameter which contains other optional
    flags that can be passed to dictate the behaviour.
    These flags include:

        to_top       : if the request will be performed using AJAX sometimes
                       you don't want to force the user to go back to the top
                       of the page. Setting this to false will do just that.
                       Defaults to true.
        target       : the id of an element for which the content is intended
                       for
        onComplete   : a callback to be executed when the request is finished
                       regardless of whether it succeeded or not
                       (only works with AJAX requests)
        onSuccess    : a callback to be executed when the request succeeds
                       (only works with AJAX requests)
        onFailure    : a callback to be executed when the request fails
                       (only works with AJAX requests)
        update       : If false, then no update of the current page will be
                       done with the response from the server. This is useful
                       if the server is returning JSON instead of HTML
        new_window   : open the request into a new window.
                       Defaults to false.

    *NOTE* - This should not be used by the onclick handler of
    an input of type 'button' if the form is not of the 'non_ajax'
    class. This is because the browser won't stop the chain of events
    when we reach form.submit(), but will instead call the form's onsubmit()
    handler and then possibly submit the form again for the 2nd time.
    In the case of inputs of type 'submit', just use Krang.Form.set()
    to set the values and let the form take care of the rest.
*/
Krang.Form = {
    get_form : function(form) {
        var form_name = form;
        form = typeof form == 'object' ? form : document.forms[form];
        if(!form) {
            alert('Krang.Form.get_form(): form "' + form_name + '" does not exist!');
            if( console ) console.trace();
            return null;
        }

        return $(form);
    },
    set : function(form, inputs) {
        form = Krang.Form.get_form(form);

        if( inputs ) {
            $H(inputs).each( function(pair) {
                var el = form.elements[pair.key];
                if(! el ) alert('Krang.Form.set() input "' + pair.key + '" does not exist in form "' + form.name + '"!');
                el.value = pair.value;
            });
        }
    },
    get_field : function(form, input) {
        form = Krang.Form.get_form(form);
        if( !form.elements[input] ) alert('Krang.Form.get(): input "' + input + '" does not exist in form "' + form.name + '"!');

        return form.elements[input];
    },
    get : function(form, input) {
        var field = Krang.Form.get_field(form, input);
        var field_count = field.length;
        if( field_count == undefined) {
            return field.value;
        } else {
            // we're looking at radio buttons or a select field, so get the one thats checked/selected
            for(var i = 0; i < field_count; i++) {
                if(field[i].checked || field[i].selected) {
                    return field[i].value;
                }
            }
        }
    },
    // "studying" a form means serializing it as a query string and keeping that around for comparisons later
    studied_forms : { },
    study : function(form) {
        form = Krang.Form.get_form(form);
        Krang.Form.studied_forms[form.name] = Form.serialize(form);
    },
    has_form_changed : function(form) {
        form = Krang.Form.get_form(form);
        var old_value = Krang.Form.studied_forms[form.name];
        if(!old_value && console && console.warn) {
            console.warn('Calling Krang.Form.has_form_changed() before Krang.Form.study()');
        }
        var new_value = Form.serialize(form);
        return old_value != new_value;
    },
    submit : function(form, inputs, options) {
        form = Krang.Form.get_form(form);
        if( inputs ) Krang.Form.set(form, inputs);

        // take care of our default options
        if(options == null ) options = {};
        if(options.update == null) options.update = true; // defaults to true

        if( options.new_window ) {
            if(Krang.Ajax.is_double_click(form.action, Form.serialize(form, true))) return false;

            // save the old target of the form so we can restore it after submission
            var old_target = form.target;
            var old_action = form.action;
            form.target = '_blank';
            form.submit();
            form.target = old_target;
            form.action = old_action;
        } else {
            Krang.show_indicator();

            // we don't use AJAX if the form specifically disallows it
            // or it has a file input
            var use_ajax = !form.hasClassName('non_ajax') && !Krang.Form.has_file_field(form);

            if( use_ajax ) {
                var url;
                if( form.action ) {
                    url = form.readAttribute('action');
                } else {
                    url = document.URL;
                    // remove any possible query bits
                    url = url.replace(/\?.*/, '');
                }

                var complete  = options['onComplete']  || Prototype.emptyFunction;
                if( options.update ) {
                    Krang.Ajax.update({
                        url        : url,
                        params     : Form.serialize(form, true),
                        method     : form.method,
                        target     : options.target,
                        to_top     : options.to_top,
                        onComplete : function(args, response, json) {
                            complete(args, response, json);
                            Krang.Form.study(form);
                        },
                        onSuccess  : options['onSuccess'],
                        onFailure  : options['onFailure']
                    });
                } else {
                    Krang.Ajax.request({
                        url        : url,
                        params     : Form.serialize(form, true),
                        method     : form.method,
                        onComplete : function(args, response, json) {
                            complete(args, response, json);
                            Krang.Form.study(form);
                        },
                        onSuccess  : options['onSuccess'],
                        onFailure  : options['onFailure']
                    });
                }
            } else {
                if(Krang.Ajax.is_double_click(form.action, Form.serialize(form, true))) {
                    Krang.hide_indicator();
                    return;
                }
                form.submit();
                Krang.hide_indicator();
            }
        }
    },
    toggle_list_btn : function(form, ckbx) {
        if (!form) { form = 'krang_pager_form' }
        form = $(form);
        if (!form) { return false }
        if (!ckbx) { ckbx = 'krang_pager_rows_checked' }
        $A([ [$('C'), 'list-btn'], [$(form), 'mini-list-btn'] ]).each(function(spec) {
            if (!spec[0]) return;
            $$('#' + spec[0].identify() + ' input.' + spec[1]).each(function(btn) {
                var submenu = btn.next('ul');
                if (Krang.row_checked(form, ckbx)) {
                    btn.addClassName(spec[1]+'-enabled');
                    btn.enable();
                    if (submenu) submenu.removeClassName('disabled');
                } else {
                    btn.removeClassName(spec[1]+'-enabled');
                    btn.disable();
                    if (submenu) submenu.addClassName('disabled');
                    var ca = spec[0].down('input#checkallbox');
                    if (ca) ca.checked = false;
                }
            })});
    },
    has_file_field : function(form) {
        form = Krang.Form.get_form(form);
        var inputs = form.elements;
        for(var i=0; i < inputs.length; i++) {
            var field = inputs[i];
            if( field.type == 'file' && field.value ) {
                return true;
            }
        }
        return false;
    }
};


/*
    Krang.show_indicator(id)
    Give the id of an element, show it. If no
    id is given, it will default to 'indicator';
*/
Krang.show_indicator = function(indicator) {
    // set the default
    if( indicator == null || indicator == '' )
        indicator = 'indicator';

    indicator = $(indicator);
    if( indicator != null )
        Element.show(indicator);
};

/*
    Krang.hide_indicator(id)
    Give the id of an element, hide it. If no
    id is given, it will default to 'indicator';
*/
Krang.hide_indicator = function(indicator) {
    // set the default
    if( indicator == null || indicator == '' )
        indicator = 'indicator';

    indicator = $(indicator);
    if( indicator != null )
        Element.hide(indicator);
};

/*
    Krang.Progress.update(count, total, label)

    Updates the progress bar (with id "progress_bar") to the correct
    width, sets the percentage counter (with id "progress_bar_percent")
    and the optionally updates a label (with id "progress_bar_label")

    Krang.Progress.reset(label);

    Resets the progress bar back to zero so that subsequent calls to Krang.Progress.update()
    will start over again.
*/
Krang.Progress = {
    update : function( count, total, label ) {
        var bar      = $('progress_bar');
        var percent  = $('progress_bar_percent');
        var progress = total > 0 ? ( count + 1 ) / total : 1;

        // can't go over 100%
        if ( progress > 1 ) progress = 1;

        var width = Math.floor( progress * 297 );

        bar.style.width   = width + 'px';

        percent.update(Math.floor( progress * 100 ) + '%');
        if ( label ) $('progress_bar_label').update(label);
    },
    reset : function(label) {
        $('progress_bar').style.width = '0px';
        $('progress_bar_percent').update('0%');
        if ( label ) $('progress_bar_label').update(label);
    }
};

/*
    Krang.Error.show()
    Shows an error to the user in the UI (an ISE)
*/
Krang.Error = {
    show : function() {
        Krang.Error.modal.open();
    },
    close : function() {
        Krang.Error.modal.close();
    },
    modal : null
};

/*
    Krang.class_suffix(element, prefix)
    Returns the portion of the class name that follows the give
    prefix and correctly handles multiple class names.

    // el is <a class="foo for_bar">
    Krang.classNameSuffix(el, 'for_'); // returns 'bar'
*/
Krang.class_suffix = function(el, prefix) {
    var suffix = '';
    var regex = new RegExp("(^|\\s)" + prefix + "([^\\s]+)($|\\s)");
    var matches = el.className.match(regex);
    if( matches != null ) suffix = matches[2];

    return suffix;
};

/*
    Krang.Nav
*/
Krang.Nav = {
    edit_mode_flag : false,
    edit_message   : Krang.L10N.loc('Are you sure you want to discard your unsaved changes?'),
    edit_mode      : function(flag) {
        // by default it's true
        if( flag === undefined ) flag = true;

        Krang.Nav.edit_mode_flag = flag;
    },
    goto_url       : function(url, ajax, ignore_edit_flag, hide_indicator) {
        if (!Krang.Nav.edit_mode_flag || ignore_edit_flag || confirm(Krang.Nav.edit_message)) {
            if( ajax ) {
                var matches = url.match(/(.*)\?(.*)/);
                var query   = matches[2] || '';
                Krang.Ajax.update({
                    url    : matches[1],
                    params : Krang.Ajax.toQueryParams(matches[2])
                });
            } else {
                if(! hide_indicator ) Krang.show_indicator();
                if (Prototype.Browser.IE) {
                    // we need the referer to be sent
                    // see http://webbugtrack.blogspot.com/search/label/HTTP%20Referer
                    var a = new Element('a', {href : url});
                    document.body.appendChild(a);
                    a.click();
                } else {
                    window.location = url;
                }
            }
            if(! ignore_edit_flag ) Krang.Nav.edit_mode_flag = false;
        }
    }
};

/*
    Krang.Help
*/
Krang.Help = {
    current_topic    : '',
    current_subtopic : '',
    set              : function(topic, subtopic) {
        Krang.Help.current_topic    = topic;
        Krang.Help.current_subtopic = subtopic;
    },
    go               : function(topic, subtopic, options) {
        var url = 'help.pl';
        if( ! options ) options = {};
        var height = options.height || 600;
        var width  = options.width  || 500;

        // use the defaults for this page unless otherwise given
        if(! topic )    topic       = Krang.Help.current_topic;
        if(! subtopic ) subtopic = Krang.Help.current_subtopic;

        // if we have something go to it
        if( topic )    url = url + '?topic=' + topic;
        if( subtopic ) url = url + '#' + subtopic;
        Krang.popup(url, { width: width, height: height});
    }
};

/*
    Krang.Messages
*/
Krang.Messages = {
    _locked     : { messages: false, alerts: false },
    _stack      : { messages: [], alerts: [] },
    _slide_time : .5,
    add         : function(msg, level) {
        // default to 'messages'
        if( level === undefined ) level = 'messages';
        Krang.Messages._stack[level].push(msg);
    },
    get         : function(level) {
        if( level === undefined ) { level = 'messages'; }
        return Krang.Messages._stack[level];
    },
    clear       : function(level) {
        if( level === undefined ) { level = 'messages'; }
        Krang.Messages._stack[level] = [];
    },
    show        : function(level) {
        // default to 'messages'
        if( level === undefined ) level = 'messages';

        // if it's a "messages" level and the "alerts" are locked (being show)
        // then just return since we don't want to show them both at the same
        // time. When "alerts" are hidden they will show "messages" so nothing
        // is ever not shown.
        if( level == 'messages' && Krang.Messages._locked['alerts'] ) return;

        var my_stack = Krang.Messages._stack[level];
        if( my_stack.length ) {
            // build HTML from stack
            var content = my_stack.inject('', function(content, msg) {
                if ( msg ) { content += '<p>' + msg + '</p>'; }
                return content;
            });

            var el = $(level);

            // set the content
            el.down('div.content').update(content);

            // in some cases we want to close the message after a user-specified
            // period of time
            var close_message_callback = function() {
                // we no longer want to keep this message locked
                Krang.Messages._locked[level] = false;
            };

            if( level == 'messages' ) {
                var prefs = Krang.my_prefs();
                var secs = prefs.message_timeout;
                if( secs > 0 ) {
                    close_message_callback = function() {
                        // we no longer want to keep this message locked
                        Krang.Messages._locked[level] = false;

                        // unique marker so later we know that we're trying to close
                        // the same message window that we opened.
                        var unique = new Date().valueOf();
                        $('messages').addClassName('unique_' + unique);
                        window.setTimeout(
                            function() {
                                if( $('messages').hasClassName('unique_' + unique) ) {
                                    Krang.Messages.hide('messages');
                                }
                            },
                            secs * 1000
                        );
                    }
                }
            }

            // quickly hide the existing messages
            Krang.Messages.hide(level, true);

            // We need to make sure that the message container isn't in the process
            // of sliding (locked). Wrap this in an anonymous function so that it can
            // be called again and again as needed by setTimeout.
            var try_count = 0;
            var _actually_show = function() {
                if( ! Krang.Messages._locked[level] ) {
                    // lock the messages (will be unlocked by afterFinish call)
                    Krang.Messages._locked[level] = true;

                    // move the message element back up at the top just to make sure
                    // it always starts at the top
                    el.setStyle({ top: '0px' });

                    if( Krang.is_ie_6() ) {
                        // in IE 6 we need to create an iframe to slide at the
                        // same time as the message's wrapper
                        var wrapper = el.down('div.wrapper');
                        Krang.Widget.HideIEControls.load(wrapper);
                        el.show();
                        // resize the iframe
                        Krang.Widget.HideIEControls.resize(wrapper);
                        close_message_callback();
                    } else {
                        new Effect.SlideDown( el, {
                            duration    : Krang.Messages._slide_time,
                            afterFinish : close_message_callback
                        });
                    }
                } else {
                    if( try_count < 7 ) window.setTimeout(_actually_show, 100);
                    try_count++;
                }
            };
            _actually_show();
        }
    },
    hide        : function(level, quick) {
        // default to 'messages'
        if( level === undefined ) level = 'messages';
        el = $(level);
        var finish_callback = function() {
            Krang.Messages._locked[level] = false;
            if( level == 'alerts' ) Krang.Messages.show('messages');
            Krang.Messages.clear(level);
        };

        if( el.visible() ) {
            if( Krang.is_ie_6() ) {
                el.hide();
                finish_callback();
                Krang.Widget.HideIEControls.unload(el.down('div.wrapper'));
            } else {
                if( quick ) {
                    el.hide();
                    finish_callback();
                } else {
                    // lock the messages (will be unlocked by afterFinish call)
                    Krang.Messages._locked[level] = true;
                    new Effect.SlideUp(el, {
                        duration    : Krang.Messages._slide_time,
                        afterFinish : finish_callback
                    });
                }
            }
            // remove any unique_ tags we put on the class name
            el.className = 'krang-slider';
        }
    },
    add_and_show : function(args) {
        if(args && args.messages) {
            Krang.Messages.clear('messages');
            $A(args.messages).each(function(msg) { Krang.Messages.add(msg) });
            Krang.Messages.show();
        }
        if(args && args.alerts) {
            Krang.Messages.clear('alerts');
            $A(args.alerts).each(function(msg) { Krang.Messages.add(msg, 'alerts') });
            Krang.Messages.show('alerts');
        }
    }
};

/*
    Krang.to_top()
    Takes the user to the top of the page.
*/
Krang.to_top = function() {
    $('H').scrollTo();
};

/*
    Krang.row_checked(form, inputName)
    Krang.pager_row_checked()
*/
Krang.row_checked = function( form, inputName ) {
    form = typeof form == 'object' ? form : document.forms[form];
    form = $(form);

    var acc;

    return $(form).getInputs('checkbox').inject(0, function(acc, ckbx) {
        if (ckbx.checked && ckbx.name.indexOf(inputName) == 0) {
            acc++;
        }
        return acc;
    });
};

Krang.pager_row_checked = function() {
  return Krang.row_checked( 'krang_pager_form', 'krang_pager_rows_checked' );
};

/*
    Krang.Pager
    Collection of methods for dealing with pager tables.

    // Tell the pager the name of the input that's used to determine
    // which form is for the pager
    Krang.Pager.input_key('some input name');

    // Go to the page in question
    Krang.Pager.goto_page(2);

    // Do a sort on the given field. Also optionally specify if it's going
    // to be ordered descendingly
    Krang.Pager.sort('id', 1);

    // Show the 'long' or 'short' view of the pager to show the number of rows
    // based on the user's preferences
    Krang.Pager.long_view();

    // Change where the pager's submission will fill (default to 'C' like all
    // other Ajax submissions)
    Krang.Pager.target = 'some_other_div';
*/
Krang.Pager = {
    _form         : null,
    target        : null,
    input_key     : function(key) {
        Krang.Pager._form = Krang.Pager._get_form(key);
    },
    init          : function() {
        Krang.Pager.target = null;
        Krang.Pager._form  = null;
    },
    goto_page     : function(num) {
        Krang.Form.submit(
            Krang.Pager._form,
            { krang_pager_curr_page_num : num },
            { to_top : false, target: Krang.Pager.target }
        );
    },
    sort          : function(field, desc) {
        Krang.Form.set(
            Krang.Pager._form,
            {
                krang_pager_sort_field      : field,
                krang_pager_sort_order_desc : desc
            }
        );
        Krang.Pager.goto_page(1);
    },
    show_big_view : function(big) {
        Krang.Form.set( Krang.Pager._form, { krang_pager_show_big_view : big });
        Krang.Pager.goto_page(1);
    },
    _get_form     : function(key) {
        var num_forms  = document.forms.length;

        for ( var i = 0; i < num_forms; i++ ) {
            var form = document.forms[ i ];

            var num_els = form.elements.length;
            for ( var j = 0; j < num_els; j++ ) {
                var el = form.elements[ j ];
                if ( el && ( el.name == key ) ) return form;
            }
        }
    }
};

/*
    Krang.check_all(checkbox, inputPrefix)
*/
Krang.check_all = function( list_checkbox, prefix ) {
    var form = list_checkbox.form;
    $(form).getInputs('checkbox').select(function(chbx) {
        return chbx.name && chbx.name.indexOf(prefix) == 0;
    }).each(function(row_ckbx) {
        row_ckbx.checked = list_checkbox.checked
        list_checkbox.checked
            ? row_ckbx.up('tr').addClassName('hilite')
            : row_ckbx.up('tr').removeClassName('hilite');
    })

    Krang.Form.toggle_list_btn(form, prefix);
}

/*
    Krang.update_order(select, prefix)

    Changes the values of a group of pull downs to reflect changes
    in their order. The given select box is the one which is assumed
    to have changed and all other inputs in the same form which have
    names that match the given prefix will also be updated.
*/
Krang.update_order = function( select, prefix ) {
    var position = select.selectedIndex;
    var inputs   = [];

    // get the list of relevant elements
    for ( var i = 0; i < select.form.elements.length; i++ ) {
        var el = select.form.elements[i];
        if ( el.options && el.name && el.name.indexOf( prefix ) == 0 ) {
            inputs.push( el );
        }
    }

    // this sort function works for sorting with an upward or downward
    // bias if there is a tie
    var sort_function = function ( a, b, upward ) {
        var val = (a.value - b.value);
        if( val == 0 ) {
            if( a.name == select.name )
                val = upward ? -1 :  1;
            else if( b.name == select.name )
                val = upward ?  1 : -1;
        }
        return val;
    }

    inputs.sort(function(a, b) { return sort_function(a, b, false) });

    // that didn't do it? reverse bias!
    if ( inputs[ position ] != select ) {
        inputs.sort(function(a, b) { return sort_function(a, b, true) });
    }

    // walk elements and assign indices
    for ( var i = 0; i < inputs.length; i++ ) {
        inputs[i].value = select.options[i].value;
    }
}

/*
    Krang.preview(type, id, edit_uuid)

    Opens up a new window to preview an element of a certain type
    (either 'story' or 'media') with a certain id or the edit_uuid
    for the object being editted.

    You must provide either an id or an edit_uuid.
*/
Krang.preview = function(type, id, edit_uuid) {
    if(!id && !edit_uuid ) {
        alert('Krang.preview() requires either an id or an edit_uuid!');
        return;
    }
    
    var url = 'publisher.pl?rm=preview_' + type
    + '&' + ( id ? type + '_id=' + id : 'edit_uuid=' + edit_uuid);

    var instance = Krang.instance;
    // remove problematic characters for use as window name (IE may otherwise choke)
    instance = instance.toLowerCase().replace( new RegExp( '[^a-z]' , 'g' ), '' );
    var new_window_name = instance + '_preview'; 

    if (Prototype.Browser.IE) {
        // we need the referer to be sent
        // see http://webbugtrack.blogspot.com/search/label/HTTP%20Referer
        // the 'target' attribute takes arbitrary values in IE6/7 (undocumented)
        var a = new Element('a', {href : url });
        a.target = new_window_name;
        document.body.appendChild(a);
        a.click();
    } else {
        var pop = window.open( url, new_window_name );
        if ( pop ) pop.focus();
    }
}

/*
    new Krang.Navigation()

    Class for creating and controlling the expandable navigation menu.
*/
Krang.Navigation = Class.create();

Object.extend( Krang.Navigation.prototype, {
    cookie_name: 'KRANG_NAV_ACCORDION_OPEN_PANELS',
    initialize: function() {
        // all elements of '#S .nav_panel' are our panels
        this.panels = $('S').select('div.nav_panel');
        // get the opened panels from our cookie
        this.opened_panels = this.opened_panels_from_cookie();

        // this is to remember which panels are being acted upon
        this.action_panels = [];

        // now cycle through each panel, open it if appropriate, close
        // it other wise. Also add the onclick handlers
        var pos = 0;
        this.panels.each(function(panel) {
            var label    = panel.childNodes[ 0 ];
            var contents = panel.childNodes[ 1 ];

            // is this panel opened?
            if ( this.opened_panels.indexOf(pos) == -1 ) {
              Element.hide( contents );
            } else {
              Element.show( contents );
            }

            // set the onclick handler to record that a panel has been
            // opened or closed, and to use Krang.Widget.BlindUpDown to
            // show or hide it.
            $(label).observe( 'click', this._label_onclick(contents, pos).bind(this));

            ++pos;
       }.bind(this));
    },
    _label_onclick : function(el, pos) {
        return function() {
            Krang.Widget.BlindUpDown(el);
            if( this.is_panel_open(pos) ) {
                this.remove_opened_panel(pos);
            } else {
                this.add_opened_panel(pos);
            }
        }
    },
    save_opened_panels: function(positions) {
        positions = $A(positions).uniq();
        Krang.Cookie.set(this.cookie_name, positions.join(','));
        this.opened_panels = positions;
    },
    remove_opened_panel: function(pos) {
        var panels = this.opened_panels;
        var index  = panels.indexOf( pos );

        // if we have it already
        if ( index != -1 ) panels.splice( index, 1 );

        this.save_opened_panels(panels);
    },
    add_opened_panel: function(pos) {
        var panels = this.opened_panels;

        // if we don't have it already
        if ( panels.indexOf(pos) == -1 ) panels.push(pos);

        this.save_opened_panels(panels);
    },
    opened_panels_from_cookie: function() {
        var value = Krang.Cookie.get(this.cookie_name);
        var panels = [];

        // if we have nav cookie, then just use what it gives us
        if ( value && value != '' ) {
            // make sure what we get are Ints not strings
            panels = $A(value.split(',')).map(function(s) { return parseInt(s) }).toArray();
        } else { // just show the first panel
            panels = [ 0 ];
        }
        return panels;
    },
    is_panel_open : function(pos) {
        return !(this.opened_panels.indexOf(pos) == -1);
    }
} );


Krang.Slug = {};

/*
    Krang.Slug.title_to_slug = function(title)
    Default auto-slug-building method. Can be overridden by ElementClass::title_to_slug
*/

Krang.Slug.title_to_slug = function(title) {
    var slug = title;
    slug = slug.replace(Krang.Slug.high_latin1_re, function(notNeeded, code_position) {
        return Krang.Slug.high_latin1_map[code_position];
    })
    .replace(/[^\s\w\-]/g,'') // remove illegal chars
    .replace(/^\s+/,'')       // remove leading whitespace
    .replace(/\s+$/,'')       // remove trailing whitespace
    .replace(/\s+/g,'_')      // replace inner spaces with underscores
    .toLowerCase(slug);       // make the whole thing lowercase
    return slug;
}

/*
    Title -> slug mappings for high latin-1 chars
*/
Krang.Slug.high_latin1_map = {
    // these are from CP1252
    // those substituted with nothing may of course be deleted
    // I put them in just for documentation purposes
  //
//  unicode    subst          CP1252 Entity   Description
//  --------------------------------------------------------------------------
    "\u20AC" : "euro",       // 0x80 &euro;   EURO SIGN
    "\u201A" : "",           // 0x82 &sbquo;  SINGLE LOW-9 QUOTATION MARK
    "\u0192" : "f",          // 0x83 &fnof;   LATIN SMALL LETTER F WITH HOOK
    "\u201E" : "",           // 0x84 &bdquo;  DOUBLE LOW-9 QUOTATION MARK
    "\u2026" : "",           // 0x85 &hellip; HORIZONTAL ELLIPSIS
    "\u2020" : "",           // 0x86 &dagger; DAGGER
    "\u2021" : "",           // 0x87 &Dagger; DOUBLE DAGGER
    "\u02C6" : "",           // 0x88 &circ;   MODIFIER LETTER CIRCUMFLEX ACCENT
    "\u2030" : "",           // 0x89 &permil; PER MILLE SIGN
    "\u0160" : "S",          // 0x8A &Scaron; LATIN CAPITAL LETTER S WITH CARON
    "\u2039" : "",           // 0x8B &lsaquo; SINGLE LEFT-POINTING ANGLE QUOTATION MARK
    "\u0152" : "OE",         // 0x8C &OElig;  LATIN CAPITAL LIGATURE OE
    "\u017D" : "Z",          // 0x8E &#381;   LATIN CAPITAL LETTER Z WITH CARON
    "\u2018" : "",           // 0x91 &lsquo;  LEFT SINGLE QUOTATION MARK
    "\u2019" : "",           // 0x92 &rsquo;  RIGHT SINGLE QUOTATION MARK
    "\u201C" : "",           // 0x93 &ldquo;  LEFT DOUBLE QUOTATION MARK
    "\u201D" : "",           // 0x94 &rdquo;  RIGHT DOUBLE QUOTATION MARK
    "\u2022" : "",           // 0x95 &bull;   BULLET
    "\u2013" : "-",          // 0x96 &ndash;  EN DASH
    "\u2014" : "-",          // 0x97 &mdash;  EM DASH
    "\u02DC" : "",           // 0x98 &tilde;  SMALL TILDE
    "\u2122" : "TM",         // 0x99 &trade;  TRADE MARK SIGN
    "\u0161" : "s",          // 0x9A &scaron; LATIN SMALL LETTER S WITH CARON
    "\u203A" : "",           // 0x9B &rsaquo; SINGLE RIGHT-POINTING ANGLE QUOTATION MARK
    "\u0153" : "oe",         // 0x9C &oelig;  LATIN SMALL LIGATURE OE
    "\u017E" : "z",          // 0x9E &#382;"  LATIN SMALL LETTER Z WITH CARON
    "\u0178" : "Y",          // 0x9F &Yuml;   LATIN CAPITAL LETTER Y WITH DIAERESIS
    // and now for real latin-1
    "\u00A0" : " ",          // 0xA0          NO-BREAK SPACE
    "\u00A1" : "",           // 0xA1          INVERTED EXCLAMATION MARK
    "\u00A2" : "cent",       // 0xA2          CENT SIGN
    "\u00A3" : "pound",      // 0xA3          POUND SIGN
    "\u00A4" : "o",          // 0xA4          CURRENCY SIGN
    "\u00A5" : "yen",        // 0xA5          YEN SIGN
    "\u00A6" : "_",          // 0xA6          BROKEN BAR
    "\u00A7" : "paragraph",  // 0xA7          SECTION SIGN
    "\u00A8" : "",           // 0xA8          DIAERESIS
    "\u00A9" : "copyright",  // 0xA9          COPYRIGHT SIGN
    "\u00AA" : "a",          // 0xAA          FEMININE ORDINAL INDICATOR
    "\u00AB" : "",           // 0xAB          LEFT-POINTING DOUBLE ANGLE QUOTATION MARK
    "\u00AC" : "not",        // 0xAC          NOT SIGN
    "\u00AD" : "-",          // 0xAD          SOFT HYPHEN
    "\u00AE" : "R",          // 0xAE          REGISTERED SIGN
    "\u00AF" : "-",          // 0xAF          MACRON
    "\u00B0" : "degree",     // 0xB0          DEGREE SIGN
    "\u00B1" : "plus_minus", // 0xB1          PLUS-MINUS SIGN
    "\u00B2" : "2",          // 0xB2          SUPERSCRIPT TWO
    "\u00B3" : "3",          // 0xB3          SUPERSCRIPT THREE
    "\u00B4" : "",           // 0xB4          ACUTE ACCENT
    "\u00B5" : "micro",      // 0xB5          MICRO SIGN
    "\u00B6" : "",           // 0xB6          PILGROW SIGN
    "\u00B7" : "",           // 0xB7          MIDDLE DOT
    "\u00B8" : "",           // 0xB8          CEDILLA
    "\u00B9" : "1",          // 0xB9          SUPERSCRIPT ONE
    "\u00BA" : "o",          // 0xBA          MASCULINE ORDINAL INDICATOR
    "\u00BB" : "",           // 0xBB          RIGHT-POINTING DOUBLE ANGLE QUOTATION MARK
    "\u00BC" : "one_quarter",// 0xBC          VULGAR FRACTION ONE QUARTER
    "\u00BD" : "one_half",   // 0xBD          VULGAR FRACTION ONE HALF
    "\u00BE" : "three_quarters",//0xBE        VULGAR FRACTION THREE QUARTERS
    "\u00BF" : "",           // 0xBF          INVERTED QUESTION MARK
    "\u00C0" : "A",          // 0xC0          LATIN CAPITAL LETTER A WITH GRAVE
    "\u00C1" : "A",          // 0xC1          LATIN CAPITAL LETTER A WITH ACUTE
    "\u00C2" : "A",          // 0xC2          LATIN CAPITAL LETTER A WITH CIRCUMFLEX
    "\u00C3" : "A",          // 0xC3          LATIN CAPITAL LETTER A WITH TILDE
    "\u00C4" : "Ae",         // 0xC4          LATIN CAPITAL LETTER A WITH DIAERESIS
    "\u00C5" : "A",          // 0xC5          LATIN CAPITAL LETTER A WITH RING ABOVE
    "\u00C6" : "AE",         // 0xC6          LATIN CAPITAL LETTER AE
    "\u00C7" : "C",          // 0xC7          LATIN CAPITAL LETTER C WITH CEDILLA
    "\u00C8" : "E",          // 0xC8          LATIN CAPITAL LETTER E WITH GRAVE
    "\u00C9" : "E",          // 0xC9          LATIN CAPITAL LETTER E WITH ACUTE
    "\u00CA" : "E",          // 0xCA          LATIN CAPITAL LETTER E WITH CIRCUMFLEX
    "\u00CB" : "E",          // 0xCB          LATIN CAPITAL LETTER E WITH DIAERESIS
    "\u00CC" : "I",          // 0xCC          LATIN CAPITAL LETTER I WITH GRAVE
    "\u00CD" : "I",          // 0xCD          LATIN CAPITAL LETTER I WITH ACUTE
    "\u00CE" : "I",          // 0xCE          LATIN CAPITAL LETTER I WITH CIRCUMFLEX
    "\u00CF" : "I",          // 0xCF          LATIN CAPITAL LETTER I WITH DIAERESIS
    "\u00D0" : "D",          // 0xD0          LATIN CAPITAL LETTER ETH
    "\u00D1" : "N",          // 0xD1          LATIN CAPITAL LETTER N WITH TILDE
    "\u00D2" : "O",          // 0xD2          LATIN CAPITAL LETTER O WITH GRAVE
    "\u00D3" : "O",          // 0xD3          LATIN CAPITAL LETTER O WITH ACUTE
    "\u00D4" : "O",          // 0xD4          LATIN CAPITAL LETTER O WITH CIRCUMFLEX
    "\u00D5" : "O",          // 0xD5          LATIN CAPITAL LETTER O WITH TILDE
    "\u00D6" : "Oe",         // 0xD6          LATIN CAPITAL LETTER O WITH DIAERESIS
    "\u00D7" : "x",          // 0xD7          MULTIPLICATION SIGN
    "\u00D8" : "O",          // 0xD8          LATIN CAPITAL LETTER O WITH STROKE
    "\u00D9" : "U",          // 0xD9          LATIN CAPITAL LETTER U WITH GRAVE
    "\u00DA" : "U",          // 0xDA          LATIN CAPITAL LETTER U WITH ACUTE
    "\u00DB" : "U",          // 0xDB          LATIN CAPITAL LETTER U WITH CIRCUMFLEX
    "\u00DC" : "Ue",         // 0xDC          LATIN CAPITAL LETTER U WITH DIAERESIS
    "\u00DD" : "Y",          // 0xDD          LATIN CAPITAL LETTER Y WITH ACUTE
    "\u00DE" : "th",         // 0xDE          LATIN CAPITAL LETTER THORN
    "\u00DF" : "ss",         // 0xDF          LATIN SMALL LETTER SHARP S
    "\u00E0" : "a",          // 0xE0          LATIN SMALL LETTER A WITH GRAVE
    "\u00E1" : "a",          // 0xE1          LATIN SMALL LETTER A WITH ACUTE
    "\u00E2" : "a",          // 0xE2          LATIN SMALL LETTER A WITH CIRCUMFLEX
    "\u00E3" : "a",          // 0xE3          LATIN SMALL LETTER A WITH TILDE
    "\u00E4" : "ae",         // 0xE4          LATIN SMALL LETTER A WITH DIAERESIS
    "\u00E5" : "a",          // 0xE5          LATIN SMALL LETTER A WITH RING ABOVE
    "\u00E6" : "ae",         // 0xE6          LATIN SMALL LETTER AE
    "\u00E7" : "c",          // 0xE7          LATIN SMALL LETTER C WITH CEDILLA
    "\u00E8" : "e",          // 0xE8          LATIN SMALL LETTER E WITH GRAVE
    "\u00E9" : "e",          // 0xE9          LATIN SMALL LETTER E WITH ACUTE
    "\u00EA" : "e",          // 0xEA          LATIN SMALL LETTER E WITH CIRCUMFLEX
    "\u00EB" : "e",          // 0xEB          LATIN SMALL LETTER E WITH DIAERESIS
    "\u00EC" : "i",          // 0xEC          LATIN SMALL LETTER I WITH GRAVE
    "\u00ED" : "i",          // 0xED          LATIN SMALL LETTER I WITH ACUTE
    "\u00EE" : "i",          // 0xEE          LATIN SMALL LETTER I WITH CIRCUMFLEX
    "\u00EF" : "i",          // 0xEF          LATIN SMALL LETTER I WITH DIAERESIS
    "\u00F0" : "eth",        // 0xF0          LATIN SMALL LETTER ETH
    "\u00F1" : "n",          // 0xF1          LATIN SMALL LETTER N WITH TILDE
    "\u00F2" : "o",          // 0xF2          LATIN SMALL LETTER O WITH GRAVE
    "\u00F3" : "o",          // 0xF3          LATIN SMALL LETTER O WITH ACUTE
    "\u00F4" : "o",          // 0xF4          LATIN SMALL LETTER O WITH CIRCUMFLEX
    "\u00F5" : "o",          // 0xF5          LATIN SMALL LETTER O WITH TILDE
    "\u00F6" : "oe",         // 0xF6          LATIN SMALL LETTER O WITH DIAERESIS
    "\u00F7" : "",           // 0xF7          DIVISION SIGN
    "\u00F8" : "o",          // 0xF8          LATIN SMALL LETTER O WITH STROKE
    "\u00F9" : "u",          // 0xF9          LATIN SMALL LETTER U WITH GRAVE
    "\u00FA" : "u",          // 0xFA          LATIN SMALL LETTER U WITH ACUTE
    "\u00FB" : "u",          // 0xFB          LATIN SMALL LETTER U WITH CIRCUMFLEX
    "\u00FC" : "ue",         // 0xFC          LATIN SMALL LETTER U WITH DIAERESIS
    "\u00FD" : "y",          // 0xFD          LATIN SMALL LETTER Y WITH ACUTE
    "\u00FE" : "th",         // 0xFE          LATIN SMALL LETTER THORN
    "\u00FF" : "y"           // 0xFF          LATIN SMALL LETTER Y WITH DIAERESIS
};

/*
    Build slug substitution regexp
*/
Krang.Slug.high_latin1_re = '';
(function() {
    var codePoints = '';
    for (codePoint in Krang.Slug.high_latin1_map) {
        codePoints += codePoint;
    }
    Krang.Slug.high_latin1_re = new RegExp('([' + codePoints + '])', 'g');
})();

Krang.Widget = {};
/*
    Krang.Widget.date_chooser(inputName)
    Primarily used by the HTML output by Krang::Widget::date_chooser()
*/
Krang.Widget.date_chooser = function(inputName, date_format) {
    // create a calendar object
    var cal = Calendar.setup({
        inputField  : inputName,
        ifFormat    : date_format,
        button      : inputName + '_trigger',
        weekNumbers : false,
        showOthers  : true,
        align       : 'BR',
        cache       : true
    });
};

/*
    Krang.Widget.time_chooser(inputName)
    Primarily used by the HTML output by Krang::Widget::time_chooser()
*/
Krang.Widget.time_chooser = function(inputName, use_ampm_time) {
    // we need to find the associated clock and make the trigger display it
    var trigger = $(inputName + '_trigger');
    var clock   = $(inputName + '_clock');
    var children = clock.childElements();
    var hour    = children[0];
    var minute  = children[1]; 
    var ampm    = null;
    if (use_ampm_time) { ampm = children[2]; } 

    var hide_clock = function() {
        clock.hide();
        // re-disable the inputs
        hour.disabled   = true;
        minute.disabled = true;
        if (use_ampm_time) { ampm.disabled = true; }
    };

    trigger.observe('click', function(event) {
        if( clock.visible() ) {
            hide_clock();

        } else {
            // position the clock to the right (30px) of the trigger
            var pos = Position.positionedOffset(trigger);
            clock.setStyle({ left: (pos[0] + 30) +'px', top: pos[1] +'px' });

            // re-enable the inputs
            hour.disabled   = false;
            minute.disabled = false;
            if (use_ampm_time) { ampm.disabled = false; }

            // parse the date in the input. If we get a valid time, then
            // set the selected values of the dropdowns
            var input = $(inputName);
            current = input.value;
            var matches = current.match(/^(\d+):(\d+)\s*(AM|PM)?$/i);
            if( matches ) {
                hour.value   = matches[1] || '';
                minute.value = matches[2] || '';
                if (use_ampm_time) { ampm.value = matches[3].toUpperCase(); }
            } else if(! current ) {
                input.value = '';
            }

            clock.show();
        }
    });

    // handle closing it if we click elsewhere
    Event.observe(document, 'mousedown', function(evt) {
        if( clock.visible() ) {
            // if we didn't click on the clock or it's trigger
            var el = Event.element(evt);
            var tag = el.tagName ? el.tagName.toUpperCase() : '';
            if( el != clock && el != hour && el != minute && el != ampm && tag != 'OPTION' && el != trigger )
                clock.hide();
        }
    });
};
Krang.Widget.update_time_chooser = function(inputName, use_ampm_time) {
    var clock  = $(inputName + '_clock');
    var hour   = clock.down('select', 0).value;
    var minute = clock.down('select', 1).value;

    var ampm   = use_ampm_time ? (clock.down('select', 2).value) : '';
    if( hour && minute && ((use_ampm_time && ampm) || true ) ) {
        $(inputName).value = hour + ':' + minute + ' ' + ampm;
    }
};

// IE 6 will place some form inputs above everything else
// This function takes an element and tries to fix this by
// inserting an <iframe> under it. This should hide the problem.
/*
    Krang.Widget.HideIEControls.load('div_id');

    // do something that changes the size of the element
    Krang.Widget.HideIEControls.resize('div_id');

    // ok, all done now
    Krang.Widget.HideIEControls.unload('div_id');

*/
Krang.Widget.HideIEControls = {
    load   : function(el) {
        el = $(el);
        var iframe = document.createElement('iframe');

        // avoid warnings about mismatching prototcols
        if( document.location.protocol == "https:" )
            iframe.src = "/stupid_ie.html";
        else if(window.opera)
            iframe.src = "javascript:false";
        else
            iframe.src = "";

        iframe.scrolling      = "no";
        iframe.frameBorder    = "0";
        iframe.style.zIndex   = "-1";
        iframe.style.position = 'absolute';
        iframe.style.height   = '0px';
        iframe.style.width    = '0px';

        // insert the iframe under the
        el.parentNode.insertBefore(iframe, el.nextSibling);

        // give it the correct size and position
        Krang.Widget.HideIEControls.resize(el, iframe);
    },
    iframe : function(el) {
        el = $(el);
        return el.next('iframe');
    },
    unload : function(el) {
        el = $(el);
        iframe = el.next('iframe');
        el.parentNode.removeChild(iframe);
    },
    resize : function(el, iframe) {
        el = $(el);
        if(! iframe ) iframe = el.next('iframe');
        Position.clone(el, iframe);
    }
};

/*
    Krang.Widget.BlindDown('element', options);

    This wraps Effect.BlindUp and Effect.BlindDown. It takes care
    of calling BlindUp or BlindDown depending on the visibility of
    the given element. It also locks the element so that subsequent
    calls won't be running at the same time (this prevents weirdness
    for example when the user double-clicks on the trigger)

    'options' can be a hash containing the following name-value pairs:

    duration    : How long should the effect last in secs.
                  The default is 0.3
    afterFinish : An optional callback to run when we're done
*/
Krang.Widget._BlindUpDown_Locked = {};
Krang.Widget.BlindUpDown = function(element, args) {
    element = $(element);
    if( ! args ) args = {};

    // if it's visible and not locked
    if( element.visible() && ! Krang.Widget._BlindUpDown_Locked[element.id] ) {
        // lock it
        Krang.Widget._BlindUpDown_Locked[element.id] = true;
        new Effect.BlindUp(
            element,
            {
                duration    : (args.duration || .3),
                afterFinish : function() {
                    // unlock the element
                    Krang.Widget._BlindUpDown_Locked[element.id] = false;
                    if( args.afterFinish ) args.afterFinish();
                }.bind(this)
            }
        );
    } else if( ! Krang.Widget._BlindUpDown_Locked[element.id] ) {
        // lock it
        Krang.Widget._BlindUpDown_Locked[element.id] = true;
        new Effect.BlindDown(
            element,
            {
                duration    : (args.duration || .3),
                afterFinish : function() {
                    // unlock the element
                    Krang.Widget._BlindUpDown_Locked[element.id] = false;
                    if( args.afterFinish ) args.afterFinish();
                }.bind(this)
            }
        );
    }
};

/*
    Krang.Base64

    Contains 2 public methods for encoding and decoding Base64 data.

    base64      = Krang.Base64.encode(some_string);
    some_string = Krang.Base64.decode(base64);
*/
Krang.Base64 = {
    chars  : "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=",

    // public method for encoding
    encode : function (input) {
        var output = "";
        var chr1, chr2, chr3, enc1, enc2, enc3, enc4;
        var i = 0;

        while (i < input.length) {
            chr1 = input.charCodeAt(i++);
            chr2 = input.charCodeAt(i++);
            chr3 = input.charCodeAt(i++);

            enc1 = chr1 >> 2;
            enc2 = ((chr1 & 3) << 4) | (chr2 >> 4);
            enc3 = ((chr2 & 15) << 2) | (chr3 >> 6);
            enc4 = chr3 & 63;

            if (isNaN(chr2)) {
                enc3 = enc4 = 64;
            } else if (isNaN(chr3)) {
                enc4 = 64;
            }

            output = output
                + this.chars.charAt(enc1) + this.chars.charAt(enc2)
                + this.chars.charAt(enc3) + this.chars.charAt(enc4);
        }

        return output;
    },

    // public method for decoding
    decode : function (input) {
        var output = "";
        var chr1, chr2, chr3;
        var enc1, enc2, enc3, enc4;
        var i = 0;

        input = input.replace(/[^A-Za-z0-9\+\/\=]/g, "");

        while (i < input.length) {
            enc1 = this.chars.indexOf(input.charAt(i++));
            enc2 = this.chars.indexOf(input.charAt(i++));
            enc3 = this.chars.indexOf(input.charAt(i++));
            enc4 = this.chars.indexOf(input.charAt(i++));

            chr1 = (enc1 << 2) | (enc2 >> 4);
            chr2 = ((enc2 & 15) << 4) | (enc3 >> 2);
            chr3 = ((enc3 & 3) << 6) | enc4;

            output = output + String.fromCharCode(chr1);

            if (enc3 != 64) {
                output = output + String.fromCharCode(chr2);
            }
            if (enc4 != 64) {
                output = output + String.fromCharCode(chr3);
            }

        }
        return output;
    }
}

Krang.ElementEditor = {
    save_hooks     : [],
    add_save_hook  : function(code) {
        Krang.ElementEditor.save_hooks.push(code);
    },
    run_save_hooks : function() {
        Krang.run_code(Krang.ElementEditor.save_hooks);
    }
};

Krang.Tooltip = {
    cursor_offset_x: 16,
    cursor_offset_y: 2,
    pointer_offset_x: 2,
    pointer_offset_y: 15,
    container_id : 'tooltip',
    pointer_id : 'tooltip-pointer'
};
Krang.Tooltip.Media = {
    img_id : 'tooltip-img',
    loading_img_src: '/images/icon-loading-small.gif',
    show : function(e, el, url) {
        var cur_pos = Position.cumulativeOffset(el);
        var curX = cur_pos[0] + el.width;
        var curY = cur_pos[1];

        var tip     = $(Krang.Tooltip.container_id);
        tip.style.left = curX + Krang.Tooltip.cursor_offset_x + 'px';
        tip.style.top  = curY + Krang.Tooltip.cursor_offset_y + 'px';

        var pointer = $(Krang.Tooltip.pointer_id);
        pointer.style.left = curX + Krang.Tooltip.pointer_offset_x + 'px';
        pointer.style.top  = curY + Krang.Tooltip.pointer_offset_y + 'px';
        $(Krang.Tooltip.Media.img_id).src = url;

        tip.style.visibility = "visible"
        pointer.style.visibility = "visible";
    },
    hide : function() {
        $(Krang.Tooltip.container_id).style.visibility = "hidden";
        $(Krang.Tooltip.pointer_id).style.visibility = "hidden";
        $(Krang.Tooltip.Media.img_id).src = Krang.Tooltip.Media.loading_img_src;
    }
};

// Krang Behavioral rules
// This is a nice convenient way to unobstrusively apply JavaScript
// behaviors to elements and is especially nice when there are multiple
// elements that need the same behaviors
// The keys are CSS selector rules and the values are functions
// which receive the element in question as an argument
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
                params    : Krang.Ajax.toQueryParams(matches[2]),
                div       : Krang.class_suffix(el, 'for_'),
                indicator : Krang.class_suffix(el, 'show_')
            });
            Event.stop(event);
        }.bindAsEventListener(el));
    },
    'a.nav_link' : function(el) {
        el.observe('click', function(event) {
            if (event.ctrlKey
                || (Prototype.Browser.IE && event.button == 4)
                || event.button == 1) {
                el.setAttribute('target', '_blank');
            } else {
                Krang.Nav.goto_url(el.getAttribute('href'));
                Event.stop(event);
            }
        }.bindAsEventListener(el));
    },
    'form' : function(el) {
        // if we have an on submit handler, then we don't want to
        // do anything automatically
        if( el.onsubmit ) return;

        // now change the submission to use Krang.Form.submit
        el.observe('submit', function(e) {
            Krang.Form.submit(el);
            Event.stop(e);
        });
    },
    // create an autocomplete widget. This involves creating a div
    // in which to place the results and creating an Ajax.Autocompleter
    // object. We only do this if the user has the "use_autocomplete"
    // preference.
    // Can specifically ignore inputs by giving them the 'non_auto' class
    // If the 'single_phrase' class is used then we won't tokenize the input on spaces
    'input.autocomplete' : function(el) {
        // ignore 'non_auto'
        if( el.hasClassName('non_auto') ) return;
        var pref = Krang.my_prefs();
        if(pref.use_autocomplete == 1) {
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
                    tokens   : el.hasClassName('single_phrase') ? [] : [' '],
                    callback : function(el, url) {
                        url = url + '&rm=autocomplete&input=' + el.name;
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
            // enable list buttons only if at least one checkbox is checked
            Krang.Form.toggle_list_btn(el.form, el.name.replace(/(.*_)[^_]+/, "$1"));
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
    // popup tooltips for thumbnails
    'img.thumbnail' : function( el ) {
        var url = el.src.replace(/\/(m|t)__/, '/');
        el.observe('mouseover', function(event) {
            Krang.Tooltip.Media.show(event, el, url);
        }.bindAsEventListener(el));
        el.observe('mouseout', function(event) {
            Krang.Tooltip.Media.hide();
        }.bindAsEventListener(el));
    },
    '.story-preview-link' : function(el) {
        el.observe('click', function(event) {
            var elm  = event.element();
            var name = elm.readAttribute('name');
            if (!name) return;
            var story_data = name.split(/_/);
            var story_id = story_data[1];
            // if it's just a number it's an id, else it's an edit_uuid
            if( story_id.match(/^\d+$/) ) {
                Krang.preview('story', story_id);
            } else {
                Krang.preview('story', null, story_id);
            }
            Event.stop(event);
        }.bindAsEventListener(el));
    },
    '.media-preview-link' : function(el) {
        el.observe('click', function(event) {
            var elm = event.findElement('a');
            var name = elm.readAttribute('name');
            if (!name) return;
            var media_id = name.split(/_/)[1];
            // if it's just a number it's an id, else it's an edit_uuid
            if( media_id.match(/^\d+$/) ) {
                Krang.preview('media', media_id);
            } else {
                Krang.preview('media', null, media_id);
            }
            Event.stop(event);
        }.bindAsEventListener(el));
    }
};

/*
  IE6- rules only
*/
if (Krang.is_ie_6()) {
    // for the big green dropdown menu buttons in the panels
    // IE needs some help here (this may not be necessary for IE7)
    Object.extend(rules,{
        '.buttonbar ul li' :  function( el ) {
            el.observe('mouseover', function(ev) {
                el.addClassName('over');
            });

            el.observe('mouseout', function(ev) {
                el.removeClassName('over');
            });
        },
        '#H .nav .menu' : function( el ) {
            el.onmouseover = el.onmouseout = function(){ this.toggleClassName( 'over' ); };
        }
    });
}
/*
  IE7 - rules only
*/
if (Krang.is_ie_7()) {
    // IE7 screws up z-index when something is absolutely positioned above a relatively position
    // element that is not the parent of the absolutely positioned element. Yeah, that's a mouthful
    // An example of this is the Edit Media screen where the category chooser is inside a table-container
    // (which handles it fine) but the other table-container's on the screen all appear above the
    // category chooser. So reset their z-index to 1 and it magically fixes everything.
    Object.extend(rules,{
        '.table-container' : function(el) {
            el.style.zIndex = 1;
        }
    });
}

Behaviour.register( rules );

/**
   Objects for Krang elementclasses
 */

/**

/**
   Krang element class namespace
*/
Krang.ElementClass = {};

/**
   Array of arrays holding the arguments (id and config) necessary to
   create a PoorText field.  This array is used in element classes
   creating PoorText fields, like Krang::ElementClass::PoorText
 */
Krang.PoorTextCreationArguments = new Array;

/*

                Preview Editor

*/

/**
   Message event listener called by previewed story's postMessage() - a HTML5
   feature implemented by Firefox 3+, Safari4+
*/
Krang.XOriginProxy = (function() {

    // helper functions

    var ifSuccessHandler = function(e, name, addToJSON, args, response, json) {
        Krang.debug("4. X-JSON header in XHR response for cb '" + name +"' on next line");
        Krang.debug(json);

        Krang.hide_indicator();
                
        // pack response message 
        var msg = name;
        
        // curry argument
        if (Object.isFunction(addToJSON)) { json = addToJSON(json) }

        // default json
        if (!json) { json = {} }

        // the XHR response object contains stuff we may
        // not access cross origin wise
        msg += "\uE000" + Object.toJSON(json)
             + "\uE000" + Krang.Cookie.get('KRANG_PREFS')
             + "\uE000" + Krang.Cookie.get('KRANG_CONFIG');
        
        // post back to sender
        e.source.postMessage(msg, e.origin);
    };
    
    var exceptionHandler = function(e, request, error) {
        Krang.debug("4. Error object in XHR exception on next line");
        Krang.debug(error);
        
        Krang.hide_indicator();
        
        var msg = "onException\uE000" + Object.toJSON(error);
        
        // post back to sender
        e.source.postMessage(msg, e.origin);
    };

    // Handle Krang.XOrigin.Request() message
    var request = function(e, options) {
        Krang.debug("3. Sending Krang.Ajax.request(url, options) for URL: "+options.cmsURL
                      +" ('options' on next line");
        Krang.debug(options);

        // post XHR
        Krang.Ajax.request({
            url:         options.cmsURL + '/' + options.cmsApp,
            params:      options.params,
            onComplete:  ifSuccessHandler.curry(e, 'onComplete', undefined),
            onFailure:   ifSuccessHandler.curry(e, 'onFailure',  undefined),
            onException: exceptionHandler.curry(e)
        });
        
    };

    // Handle Krang.XOrigin.XUpdater() message
    var xupdater = function(e, options) {
        // send XHR request for Prototype.XOrigin.XUpdater
        Krang.debug("3. Sending Krang.Ajax.update(target, url, options) for URL: "+options.cmsURL
                      +" ('options' on next line");
        Krang.debug(options);
                    
        var target = options.target || 'C';

        // onComplete handler
        var onComplete  = ifSuccessHandler.curry(e, 'onComplete', function(json) {
            if (json === null) { json = {}; }
            var alerts   = Krang.Messages.get('alerts');
            var messages = Krang.Messages.get('messages');
            if (alerts.length)   json['alerts']   = alerts;
            if (messages.length) json['messages'] = messages;
            return json;
        });

        // update form with our arguments
        Krang.ElementEditor.run_save_hooks();
        
        var form = $(options.form);
        if (form) {
            Krang.Form.set(form, options.params);
            var params = Form.serialize(form, true);
            var method = form.method;
        } else {
            var params = options.params;
            var method = options.method;
        }

        // post XHR
        Krang.Ajax.update({
            url        : options.cmsURL + '/' + options.cmsApp,
            params     : params,
            method     : method,
            target     : target,
            onComplete : onComplete,
            onFailure  : ifSuccessHandler.curry(e, 'onFailure',  undefined),
            onException: exceptionHandler.curry(e)
        });
    };

    // Handle Krang.XOrigin.WinInfo() message
    var wininfo = function(e, options) {
        if (options.question == 'isStoryOnEditScreen') {
            if (document.forms && document.forms['edit']
                               && /story/.test(document.forms['edit'].action)) {
                e.source.postMessage('response\uE000"yes"', e.origin);
            } else {
                e.source.postMessage('response\uE000"no"', e.origin);                
            }
            e.source.postMessage('finish', e.origin);
        } else if (options.question == 'getDictionary') {
            if (Krang.L10N.lexicon) {
                e.source.postMessage('response\uE000' + Object.toJSON(Krang.L10N.lexicon), e.origin);
            } else {
                e.source.postMessage('response\uE000', e.origin);
            }
            e.source.postMessage('finish', e.origin);
        }
        Krang.hide_indicator();
    };

    // dispatch to message handlers
    return function(e, authorizedOrigins) {
        if (authorizedOrigins.any(function(url) { return url == e.origin })) {
            // message from authorized origin
            var data;
            if (data = e.data) {
                // unpack the posted data
                var options     = data.evalJSON();
                
                Krang.debug("2. Received message from '" + e.origin + "' - " + data);
                
                Krang.show_indicator();

                // dispatch
                if (options.type == 'request') {
                    request(e, options);
                } else if (options.type == 'xupdater') {
                    xupdater(e, options);
                } else if (options.type == 'wininfo') {
                    wininfo(e, options);
                }
            } else {
                Krang.debug("No data in message from " + e.origin);
            }
        } else {
            throw new Error("Unauthorized cross-document message from " + e.origin);
        }
    };
})();

Krang.debug.off();

Event.observe(window, 'message', function(e) {
    // get allowed preview site URLs from 'config' cookie
    var previewURLs = Krang.Cookie.json_get('previewURLs_' + Krang.Instance.get());

    if (!Object.isArray(previewURLs)) {
        throw new Error("Message event handler (krang.js): No previewURL cookie found for instance '" + Krang.Instance.get() + '"');
    }

    // call our cross origin XHR proxy
    Krang.XOriginProxy(e, previewURLs);
});

