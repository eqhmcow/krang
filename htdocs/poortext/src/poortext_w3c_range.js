/**
   Class method to build an array of indices suited to find the given
   Node relative to the given rootNode (inspired by Dojo).

   @param node - the startContainer of a range

   @param rootNode - the node serving as the reference for building
                     the array of indices

   @returns Object - Key 'o' is an array containing the offset of the
                     given node relatively to its parentNode and
                     recursively up the node tree until the given
                     parent is reached.
*/
PoorText.getRangeContainerIndices = function(containerNode, rootNode) {
    var offsets  = [];
    var origNode = containerNode;

    var parentNode, n;
    while(containerNode != rootNode){
        var i = 0;
        parentNode = containerNode.parentNode;
        while((n = parentNode.childNodes[i++])){
            if(n === containerNode){
                --i;
                break;
            }
        }
        if(i >= parentNode.childNodes.length){
            alert("Error finding index of a node in dijit.range.getIndex");
        }
        offsets.unshift(i);
        containerNode = parentNode;
    }

//
// This does not work with the button-driven special-char-insertion
//

    //normalized() can not be called so often to prevent
    //invalidating selection/range, so we have to detect
//    //here that any text nodes in a row
//    if(offsets.length > 0 && origNode.nodeType == 3){
//        n = origNode.previousSibling;
//
//        while(n && n.nodeType == 3){
//            offsets[offsets.length-1]--;
//            n = n.previousSibling;
//        }
//    }

    return offsets;
}

/**
   Class method to find a node based on array of indices used to drill
   down through the descendants of a root node.
   @param indices - Array of indices produced by {@link PoorText#range#getIndex}
   @param rootNode - DomNode serving as the starting point for drilling down
*/
PoorText.getRangeContainerNode = function(indices, rootNode){
    if(!Object.isArray(indices) || indices.length == 0){
        return rootNode;
    }

    var node = rootNode;

    indices.each(function(i) {
        if (i >= 0 && i < node.childNodes.length) {
            node = node.childNodes[i];
        } else {
            node = null;
//            alert('Error: can not find node with index '+i+' under rootNode node '+rootNode );
            return false;
        }
    });
    
    return node;
}

