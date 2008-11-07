/** @fileoverview
    IO filters for PoorText in Krang context
*/

/**
   Filter correcting some html messup.
   1. compress <i>s</i><i>ix</i> to <i>six</i>
   2. chop empty markup tags
   @param {Node} node The node whose innerHTML will we corrected
   @return the node with its innerHTML corrected
   @type Node
   @private
*/
PoorText.correctMarkup = function(node) {
  var html = node.innerHTML;
  html = html.replace(/<\/([^>]+)><\1>/g   , ""  )  // compress <i>s</i><i>ix</i> to <i>six</i>
             .replace(/<([^<]+)>\s+<\/\1>/g, " " )  // chop whitespace only tags and collapse white space
             .replace(/<([^<]+)><\/\1>/g   , ""  )  // chop empty tags

             // collapse whitespace
             .replace(/(?:&nbsp;)+/g, ' ')
             .replace(/\u00A0+/g, ' ') // this is &nbsp; in unicode: WebKit prefers this
             .replace(/\s+/g, ' ')

             // remove <br> at end, while taking care of trailing closing tags and possible whitespace
             .replace(/(?:<br>\s*)+\s*((?:<\/[^>]+>)*)\s*$/, '$1')

             // trim leading and trailing whitespace
             .replace(/^\s+|\s+$/g, '')

             // trim DIV tags
            .replace(/(?:<\/?div>)+/g, '');

  node.innerHTML = html;
  return node;
};

/**
   Filter adding our '_poortext_url' attribut to links.  We don't
   want browsers to mess up the HREF attribute of links entered by
   the user.  So we remember the URL entered in a previous editing
   session and now coming from the server, and we remember it with a
   custom attribut named '_poortext_url'.  When sending the edited
   content back to the server or extracting it via {@link #getHtml},
   we'll delete '_poortext_url' after writing its content back to the
   href attribute of the link (See {@link PoorText#removeUrlProtection}).
   The same procedure is applied to ABBR and ACRONYM tags.
   @param {Node} node The node whose <a> tags will be treated
   @return the node with URL protection added.
   @type Node
   @private
*/
PoorText.addUrlProtection = function(node) {
    // Remember URL in _poortext_url attribute
    var links = node.getElementsByTagName('A');
    $A(links).each(function(link) {
        link = $(link);
	if (link.hasAttribute('href')) {
	    link.setAttribute('_poortext_url', PoorText.getHref(link));
	    link.setAttribute('_poortext_tag', 'a');
            if (Prototype.Browser.IE) {
                var ec = link.getAttribute('className');
            } else {
                var ec = link.getAttribute('class');
            }
            /*
              Don't touch the class attrib if we have it in Krang
              context, it will be filtered out at publish time only,
              because it might be contain 'pt-storylink' which must be
              preserved across IO
            */
            if (! /pt-a/.test(ec)) {
                PoorText.setClass(link, 'pt-a');
            }
	}
    });
    
    // Substitute phrase markup with custom link elements
    var isIE6 = false;
    ['abbr', 'acronym'].each(function(tag) {
	var elements = node.getElementsByTagName(tag);
	$A(elements).each(function(elm) {
            // IE6 does not support the ABBR tag: fix it
            if (!elm.innerHTML) {
                isIE6 = true;
                return;
            }
	    var link = $(document.createElement('a'));
	    link.setAttribute('title', elm.getAttribute('title'));
	    link.setAttribute('_poortext_tag', tag);
            link.setAttribute('href', '');
	    PoorText.setClass(link, 'pt-'+tag);
	    link.innerHTML = elm.innerHTML;
	    elm.parentNode.replaceChild(link, elm);
	})});

    if (isIE6) PoorText.__abbrFixIE6(node);

    return node;
};

/**
   Filter removing our '_poortext_url' attribut from links after
   writing its contents back to their HREF attribut.  This is the
   counterpart of {@link PoorText#removeUrlProtection}), which comes with
   more detailed information.
   The same procedure is applied to ABBR and ACRONYM tags.
   @param {Node} node The node whose <a> tags will be treated.
   @return The node with URL protection removed
   @type Node
   @private
*/
PoorText.removeUrlProtection = function(node) {
    var links = node.getElementsByTagName('A');
    $A(links).each(function(link) {
        link = $(link);
	if (link.hasAttribute('_poortext_url')) {
	    link.setAttribute('href', link.getAttribute('_poortext_url'));
	    link.removeAttribute('_poortext_url');
            link.removeAttribute('_poortext_tag');
            link.removeAttribute('_counted'); // IE stuff
            // Don't remove the class attrib here
	}
	else { // fake links to be turned into phrase markup
	    var tagName = link.getAttribute('_poortext_tag');
	    var tag = document.createElement(tagName);
	    tag.setAttribute('title', link.getAttribute('title'));
	    tag.innerHTML = link.innerHTML;
	    link.parentNode.replaceChild(tag, link);
	}
    });
    return node;
};

/**
   Array of filter functions for incoming HTML.  These filters are
   applied when setting {@link #editNode} with the contents of {@link
   #srcElement}.  This typically occurs in {@link #makeEditable}.
   @type Class Array
   @private
*/
PoorText.inFilters = [ PoorText.addUrlProtection ];

/**
   Array of filter function for outgoing HTML.  These filters will be
   applied when setting {@link #returnHTML} with the contents of
   {@link #editNode}.  This typically occurs {@link PoorText#onBlur}.
   @type Class Array
   @private
*/
PoorText.outFilters = [ PoorText.correctMarkup,
                        PoorText.removeUrlProtection ];

