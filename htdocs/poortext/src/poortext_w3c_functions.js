/** @fileoverview
    Some functions shared by all W3C compliant browser engines

    As long as IFrames are used in one supported browser, we can't use
    Prototype.js, unless we want't go load it in each and every
    PoorText field, which would be a big performance hit.
*/

PoorText.getHref = function(element) {
    return element.getAttribute('href');
}

PoorText.setClass = function(elm, className) {
    elm.setAttribute('class', className);
}

