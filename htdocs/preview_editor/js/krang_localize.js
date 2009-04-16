var Krang;
if (Object.isUndefined(Krang)) { Krang = {} }
/**
   Krang localization function
**/
Krang.localize = (function() {

    var dictionary = new Hash();
    
    var localize = function(text) {
        return dictionary.get(text) || text;
    }
    
    localize.withDictionary = function(thesaurus) {
        dictionary.update(thesaurus);
    }

    return localize;
})();


Element.addMethods({
    localize: function(element) {
        element = $(element);
        element.update(Krang.localize(element.innerHTML));
        return element;
    }
})
