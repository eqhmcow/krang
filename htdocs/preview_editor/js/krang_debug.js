var Krang;
if (Object.isUndefined(Krang)) { Krang = {} }

/**
   Krang.debug.on();
   Krang.debug('This debug message will be printed to the console');
   Krang.debug.off();
   Krang.debug('This debug message will not be printed to the console');
*/
(function() {

    var debugOn = false;

    Krang.debug = function(msg) {
        if (debugOn) {
            console.log(msg);
        }
    }

    Krang.debug.on  = function() { debugOn = true  };
    Krang.debug.off = function() { debugOn = false };
})();
