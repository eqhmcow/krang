// Created by HTML::PopupTreeSelect V1.3
// Standalone JS file created by mpeters for the following reasons:
// + Safari crashes when parsing large chunks of JS out of HTML and
//   then eval()ing it
// + Allow browsers to cache the JS which doesn't change
PopupTreeSelect = Class.create();
Object.extend(PopupTreeSelect.prototype, {
    initialize : function(name, params) {
        this.name            = name;
        this.width           = params.width  || 225;
        this.height          = params.height || 200;
        this.image_path      = params.image_path     || '';
        this.dynamic_url     = params.dynamic_url    || '';
        this.dynamic_params  = params.dynamic_params || '';
        this.hide_selects    = params.hide_selects   || false;
        this.hide_textareas  = params.hide_textareas || false;
        this.selected_id     = null;
        this.selected_val    = null;
        this.mouseX          = null;
        this.mouseY          = null;
        this.offsetX         = null;
        this.offsetY         = null;
        this.locked_titlebar = null;
        this.locked_botbar   = null;
        this.titleobj        = null;
        this.innerobj        = null;
        this.bbarobj         = null;
        this.botbarobj       = null;

        // now save this object so it can be referenced by name
        PopupTreeSelect.save(name, this);

        // setup some observers for actions against this tree
        Event.observe(
            $(document), 
            'mousedown', 
            function(event) { this.lock(event) }.bindAsEventListener(this) 
        );
        Event.observe(
            $(document), 
            'mousemove', 
            function(event) { this.drag(event) }.bindAsEventListener(this) 
        );
        Event.observe(
            $(document), 
            'mouseup', 
            function(event) { this.release(event) }.bindAsEventListener(this) 
        );

        // preload our images so that they're available right when we need them
        var preload_imgs = [];
        $w('minus.png plus.png open_node.png closed_node.png L.png').each(function(file) {
            var img = new Image();
            img.src = this.image_path + file;
            preload_imgs.push(img);
        }.bind(this));
    },
    lock : function(evt) {
        evt = (evt) ? evt : event;
        this.titleobj  = document.getElementById(this.name + "-title");
        this.innerobj  = document.getElementById(this.name + "-inner");
        this.bbarobj   = document.getElementById(this.name + "-bbar");
        this.botbarobj = document.getElementById(this.name + "-botbar");
        this.set_locked(evt);
        this.update_mouse(evt);

        if (this.locked_titlebar) {
            if (evt.pageX) {
                this.offsetX = evt.pageX - ((this.locked_titlebar.offsetLeft) ? 
                            this.locked_titlebar.offsetLeft : this.locked_titlebar.left);
                this.offsetY = evt.pageY - ((this.locked_titlebar.offsetTop) ? 
                            this.locked_titlebar.offsetTop : this.locked_titlebar.top);
            } else if (evt.offsetX || evt.offsetY) {
                this.offsetX = evt.offsetX - ((evt.offsetX < -2) ? 
                            0 : document.body.scrollLeft);
                this.offsetY = evt.offsetY - ((evt.offsetY < -2) ? 
                            0 : document.body.scrollTop);
            } else if (evt.clientX) {
                this.offsetX = evt.clientX - ((this.locked_titlebar.offsetLeft) ? 
                            this.locked_titlebar.offsetLeft : 0);
                this.offsetY = evt.clientY - ((this.locked_titlebar.offsetTop) ? 
                             this.locked_titlebar.offsetTop : 0);
            }
            Event.stop(evt);
        }

        if (this.locked_botbar) {
            if (evt.pageX) {
                this.offsetX = evt.pageX;
                this.offsetY = evt.pageY;
            } else if (evt.clientX) {
                this.offsetX = evt.clientX;
                this.offsetY = evt.clientY;
            } else if (evt.offsetX || evt.offsetY) {
                this.offsetX = evt.offsetX - ((evt.offsetX < -2) ? 
                            0 : document.body.scrollLeft);
                this.offsetY = evt.offsetY - ((evt.offsetY < -2) ? 
                            0 : document.body.scrollTop);
            }            
            Event.stop(evt);
        }
        return true;
    },
    update_mouse : function(evt) {
        if (evt.pageX) {
            this.mouseX = evt.pageX;
            this.mouseY = evt.pageY;
        } else {
            this.mouseX = evt.clientX + document.documentElement.scrollLeft + document.body.scrollLeft;
            this.mouseY = evt.clientY + document.documentElement.scrollTop  + document.body.scrollTop;
        }
    },
    set_locked : function(evt) {
        var target = (evt.target) ? evt.target : evt.srcElement;
        if (target && target.className == "hpts-title") { 
            this.locked_titlebar = target.parentNode;
            return;
        } else if (target && target.className == "hpts-botbar") {
            this.locked_botbar = target.parentNode;
            return;
        }
        this.locked_titlebar = null;
        this.locked_botbar = null;
        return;
    },
    drag : function(evt) {
        evt = (evt) ? evt : event;
        this.update_mouse(evt);

        if (this.locked_titlebar) {
            this.locked_titlebar.style.left = (this.mouseX - this.offsetX) + "px";
            this.locked_titlebar.style.top  = (this.mouseY - this.offsetY) + "px";
            evt.cancelBubble = true;
            return false;
        } else if (this.locked_botbar) {           
            this.titleobj.style.width  = (this.width + this.mouseX - this.offsetX) + "px";
            this.innerobj.style.width  = (this.width + this.mouseX - this.offsetX) + "px";
            this.bbarobj.style.width   = (this.width + this.mouseX - this.offsetX) + "px";
            //this.botbarobj.style.width = (this.width + this.mouseX - this.offsetX) + "px";
            this.innerobj.style.height = (this.height + this.mouseY - this.offsetY) + "px";
            evt.cancelBubble = true;
            return false;
        }
    },
    release : function(evt) {
        this.locked_titlebar = null;
        if (this.locked_botbar){
            var widthstr  = document.getElementById(this.name + "-inner").style.width;
            var heightstr = document.getElementById(this.name + "-inner").style.height;
            this.width    = parseFloat(widthstr.substr(0,widthstr.indexOf("px")));
            this.height   = parseFloat(heightstr.substr(0,heightstr.indexOf("px")));
        }
        this.locked_botbar = null;
    },
    toggle_expand : function(id) {
        var obj  = document.getElementById(this.name + "-desc-" + id);
        var plus = document.getElementById(this.name + "-plus-" + id);
        var node = document.getElementById(this.name + "-node-" + id);
        if (obj.style.display != 'block') {
            obj.style.display = 'block';
            plus.src = this.image_path + "minus.png";
            node.src = this.image_path + "open_node.png";

            var params = this.dynamic_params;
            if( params ) {
                params = params + '&id=' + id;
            } else {
                params = 'id=' + id;
            }

            new Ajax.Updater(
                this.name + "-desc-" + id, 
                this.dynamic_url,
                { method: 'get', parameters: params, evalScripts: true }
            );
        } else {
            obj.style.display = 'none';
            obj.innerHTTML    = '';
            plus.src = this.image_path + "plus.png";
            node.src = this.image_path + "closed_node.png";
        }
    },
    /* select or unselect a node */
    toggle_select : function(id, val) {
        var selected_id = this.selected_id;
        if (selected_id != null) {
            /* turn off old selected value */
            var old = document.getElementById(this.name + "-line-" + selected_id);
            old.className = "hpts-label-unselected";
        }

        if (id == selected_id) {
            /* clicked twice, turn it off and go back to nothing selected */
            this.selected_id = null;
            $('hpts-ok-btn-'+this.name).disable().removeClassName('hpts-ok-btn-enabled');
        } else {
            /* turn on selected item */
            var new_obj = document.getElementById(this.name + "-line-" + id);
            new_obj.className = "hpts-label-selected";
            this.selected_id = id;
            this.selected_val = val;
            $('hpts-ok-btn-'+this.name).enable().addClassName('hpts-ok-btn-enabled');
        }
    },
    /* it's showtime! */
    show : function() {
        document.getElementById(this.name + "-inner").innerHTML = '';

        new Ajax.Updater(
            this.name + '-inner', 
            this.dynamic_url,
            { method: 'get', parameters: this.dynamic_params, evalScripts: true  }
        );

        var obj = document.getElementById(this.name + "-outer");
        var x = Math.floor(this.mouseX - (this.width/2));
        x = (x > 2 ? x : 2);
        var y = Math.floor(this.mouseY - (this.height/5 * 4));
        y = (y > 2 ? y : 2);

        obj.style.left = x + "px";
        obj.style.top  = y + "px";
        obj.style.display = 'block';

        // don't activate OK button until an item has been selected
        $('hpts-ok-btn-'+this.name).disable().removeClassName('hpts-ok-btn-enabled');

        if( this.hide_selects ) {
            for(var f = 0; f < document.forms.length; f++) {
                for(var x = 0; x < document.forms[f].elements.length; x++) {
                   var e = document.forms[f].elements[x];
                   if (e.options) {
                      e.style.visibility = "hidden";
                   }
                }
            }
        }

        if( this.hide_textareas ) {
            for(var f = 0; f < document.forms.length; f++) {
                for(var x = 0; x < document.forms[f].elements.length; x++) {
                   var e = document.forms[f].elements[x];
                   if (e.rows) {
                      e.style.visibility = "hidden";
                   }
                }
            }
        }
    },
    /* user clicks the ok button */
    ok : function(fieldName, formName, onselect) {
        /* fill in a form field if they spec'd one */
        if( fieldName ) {
            var form;
            if( formName )
                form = document.forms[formName];
            else
                form = document.forms[0];
            form.elements[fieldName].value = this.selected_val;
        }

        /* trigger onselect */
        if( onselect ) {
            onselect(this.selected_val);
        }

        this.close();
    },
    cancel : function() {
        this.close();
    },
    close  : function() {
        /* hide window */
        var obj = document.getElementById(this.name + "-outer");
        obj.style.display = 'none';

        /* clear selection */
        var selected_id = this.selected_id;
        if (selected_id != null) {
            this.toggle_select(selected_id);
        }

        if( this.hide_selects ) {
            for(var f = 0; f < document.forms.length; f++) {
                for(var x = 0; x < document.forms[f].elements.length; x++) {
                    var e = document.forms[f].elements[x];
                    if (e.options) {
                        e.style.visibility = "visible";
                    }
                }
            }
        }

        if( this.hide_textareas ) {
            for(var f = 0; f < document.forms.length; f++) {
                for(var x = 0; x < document.forms[f].elements.length; x++) {
                    var e = document.forms[f].elements[x];
                    if (e.rows) {
                        e.style.visibility = "visible";
                    }
                }
            }
        }
    }
});
PopupTreeSelect._saved_objects = {};
PopupTreeSelect.save = function(name, obj) {
    PopupTreeSelect._saved_objects[name] = obj;
};
PopupTreeSelect.retrieve = function(name) {
    return PopupTreeSelect._saved_objects[name];
};

