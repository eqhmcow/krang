/*
    Krang.Messages
*/
var Krang;
if (Object.isUndefined(Krang)) { Krang = {} }

Krang.Messages = {
    _locked     : { messages: false, alerts: false },
    _stack      : { messages: [], alerts: [] },
    _slide_time : .5,
    add         : function(msg, level) {
        // default to 'messages'
        if (level === undefined) { level = 'messages'; }
        Krang.Messages._stack[level].push(msg);
        return this;
    },
    get         : function(level) {
        if( level === undefined ) { level = 'messages'; }
        console.error(Krang.Messages._stack);
        return Krang.Messages._stack[level];
    },
    clear       : function(level) {
        if( level === undefined ) { level = 'messages'; }
        Krang.Messages._stack[level] = [];
    },
    show : function(msgTimeout, level) {
        // default to 'messages'
        if (level === undefined) { level = 'messages'; }

        // if it's a "messages" level and the "alerts" are locked (being shown)
        // then just return since we don't want to show them both at the same
        // time. When "alerts" are hidden they will show "messages" so nothing
        // is ever not shown.
        if (level == 'messages' && Krang.Messages._locked['alerts']) { return; }

        var my_stack = Krang.Messages._stack[level];

        if (my_stack.length) {
            // build HTML from stack
            var content = my_stack.inject('', function(content, msg) {
                if ( msg ) { content += '<p>' + msg + '</p>'; }
                return content;
            });

            var el = $('krang_preview_editor_'+level);

            // set the content
            el.down('div.content').update(content);

            // in some cases we want to close the message after a user-specified
            // period of time
            var close_message_callback = function() {
                // we no longer want to keep this message locked
                Krang.Messages._locked[level] = false;
            };

            if (level == 'messages') {
                if (msgTimeout > 0) {
                    var close_message_callback = function() {
                        // we no longer want to keep this message locked
                        Krang.Messages._locked[level] = false;

                        // unique marker so later we know that we're trying to close
                        // the same message window that we opened.
                        var unique = new Date().valueOf();
                        $('krang_preview_editor_messages').addClassName('unique_' + unique);
                        window.setTimeout(
                            function() {
                                if ($('krang_preview_editor_messages').hasClassName('unique_' + unique)) {
                                    Krang.Messages.hide('messages');
                                }
                            },
                            msgTimeout * 1000
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
                if (!Krang.Messages._locked[level]) {
                    // lock the messages (will be unlocked by afterFinish call)
                    Krang.Messages._locked[level] = true;

                    // move the message element back up at the top just to make sure
                    // it always starts at the top
                    el.setStyle({top: '26px'});
                    
                    new Effect.SlideDown(el, {
                        duration    : Krang.Messages._slide_time,
                        afterFinish : close_message_callback
                    });
                } else {
                    if (try_count < 7) { window.setTimeout(_actually_show, 100); }
                    try_count++;
                }
            };
            _actually_show();
        }
    },
    hide : function(level, quick) {
        // default to 'messages'
        if (level === undefined) { level = 'messages'; }
        var el = $('krang_preview_editor_'+level);

        var finish_callback = function() {
            Krang.Messages._locked[level] = false;
            if (level == 'alerts') { Krang.Messages.show('messages'); }
        };

        if (el.visible()) {
            if (quick) {
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
            // remove any unique_ tags we put on the class name
            el.writeAttribute('className', 'krang_preview_editor_slider');
        }
    }
};
