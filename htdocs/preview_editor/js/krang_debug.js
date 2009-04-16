var Krang;
if (Object.isUndefined(Krang)) { Krang = {} }

/**
   Krang.debug('debug message');
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
