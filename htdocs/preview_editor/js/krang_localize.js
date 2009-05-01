var Krang;
if (Object.isUndefined(Krang)) { Krang = {} }
/**
   Krang localization function

   // Attach a thesaurus to Krang.localize()
   Krang.localize.withDictionary(thesaurus);

   // Localize usgin attached thesaurus
   Krang.localize('Edit'); 

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

/**
    Add a localize() method to all HTMLElements to allow localization of
    the elements innerHTML.
*/
Element.addMethods({
    localize: function(element) {
        element = $(element);
        element.update(Krang.localize(element.innerHTML));
        return element;
    }
})
