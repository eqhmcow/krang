/** @fileoverview
    JS HTML strings to build popups and buttons bars.
*/

/**
   Object mapping names to HTML strings representing addHTML dialog,
   help screen and button bar
   @return the mapping object
   @type Class Object
   @private
*/
PoorText.htmlFor = {

    addHTML : 

'<div class="pt-popup-content" id="pt-popup-content-addHTML">'
  +'<form class="pt-dlg-form" id="pt-dlg-form-addHTML">'
    +'<div class="pt-fieldset">'
      +'<div class="pt-legend">[Insert]</div>'
      +'<table>'
        +'<colgroup>'
        +'<col class="pt-dlg-first-col">'
        +'<col class="pt-dlg-second-col">'
        +'</colgroup>'
        +'<thead>'
        +'</thead>'
        +'<tbody>'
	  +'<tr>'
	     +'<td><input type="radio" name="tag" class="pt-dlg-radio" id="pt-dlg-abbr" value="abbr"/></td>'
             +'<td><label for="pt-dlg-abbr">[Abbreviation]</label></td>'
	  +'</tr>'
	  +'<tr>'
	      +'<td><input type="radio" name="tag" class="pt-dlg-radio" id="pt-dlg-acronym" value="acronym"/></td>'
	      +'<td><label for="pt-dlg-acronym">[Acronym]</label></td>'
	  +'</tr>'
	  +'<tr>'
	      +'<td><input type="radio" name="tag" class="pt-dlg-radio" id="pt-dlg-a" value="a" checked="checked"/></td>'
	      +'<td><label for="pt-dlg-a">[Link]</label></td>'
	  +'</tr>'
	  +'<tr id="pt-dlg-url-row" style="height:32px">'
	      +'<td><label for="pt-dlg-url">[URL]</label></td>'
	      +'<td><div><input type="text" name="pt-dlg-url" class="pt-dlg-text" id="pt-dlg-url" size="35"/></div></td>'
	  +'</tr>'
	  +'<tr>'
	      +'<td><label for="pt-dlg-tooltip">[Title]</label></td>'
	      +'<td><div><input type="text" name="pt-dlg-tooltip" class="pt-dlg-text" id="pt-dlg-tooltip" size="35"/></div></td>'
	  +'</tr>'
	  +'<tr><td>&nbsp;</td>'
	      +'<td style="text-align: right; height: 28px; vertical-align: bottom">'
		 +'<input type="button" value="[OK]" id="pt-dlg-ok" class="pt-dlg-button">'
		 +'<input type="button" value="[Cancel]" id="pt-dlg-cancel" class="pt-dlg-button">'
	      +'</td>'
	  +'</tr>'
        +'</tbody>'
      +'</table>'
    +'</div>'
  +'</form>'
+'</div>',


    help :

'<div class="pt-popup-content" id="pt-popup-content-help">'
  +'<div class="pt-fieldset">'
    +'<div class="pt-legend">[Shortcuts]</div>'
    +'<table>'
      +'<tbody>'
        +'HERE'
      +'</tbody>'
    +'</table>'
  +'</div>'
+'</div>',


    buttonBar :

'<ul>'
   +'<li class="pt-btn" id="pt-btn-bold">'
      +'<a href="javascript:void(0)" class="pt-btnLink"></a>'
   +'</li>'
   +'<li class="pt-btn" id="pt-btn-italic">'
      +'<a href="javascript:void(0)" class="pt-btnLink"></a>'
   +'</li>'
   +'<li class="pt-btn" id="pt-btn-underline">'
      +'<a href="javascript:void(0)" class="pt-btnLink"></a>'
   +'</li>'
   +'<li class="pt-btn" id="pt-btn-strikethrough">'
      +'<a href="javascript:void(0)" class="pt-btnLink"></a>'
   +'</li>'
   +'<li class="pt-btn" id="pt-btn-subscript">'
      +'<a href="javascript:void(0)" class="pt-btnLink"></a>'
   +'</li>'
   +'<li class="pt-btn" id="pt-btn-superscript">'
      +'<a href="javascript:void(0)" class="pt-btnLink"></a>'
   +'</li>'

   +'<li class="pt-btn" id="pt-btn-align_left">'
      +'<a href="javascript:void(0)" class="pt-btnLink"></a>'
   +'</li>'
   +'<li class="pt-btn" id="pt-btn-align_center">'
      +'<a href="javascript:void(0)" class="pt-btnLink"></a>'
   +'</li>'
   +'<li class="pt-btn" id="pt-btn-align_right">'
      +'<a href="javascript:void(0)" class="pt-btnLink"></a>'
   +'</li>'
   +'<li class="pt-btn" id="pt-btn-justify">'
      +'<a href="javascript:void(0)" class="pt-btnLink"></a>'
   +'</li>'

   +'<li class="pt-btn" id="pt-btn-indent">'
      +'<a href="javascript:void(0)" class="pt-btnLink"></a>'
   +'</li>'
   +'<li class="pt-btn" id="pt-btn-outdent">'
      +'<a href="javascript:void(0)" class="pt-btnLink"></a>'
   +'</li>'

   +'<li class="pt-btn" id="pt-btn-add_html">'
      +'<a href="javascript:void(0)" class="pt-btnLink"></a>'
   +'</li>'
   +'<li class="pt-btn" id="pt-btn-delete_html">'
      +'<a href="javascript:void(0)" class="pt-btnLink"></a>'
   +'</li>'
   +'<li class="pt-btn" id="pt-btn-add_story_link">'
      +'<a href="javascript:void(0)" class="pt-btnLink"></a>'
   +'</li>'

   +'<li class="pt-btn" id="pt-btn-cut">'
      +'<a href="javascript:void(0)" class="pt-btnLink"></a>'
   +'</li>'
   +'<li class="pt-btn" id="pt-btn-copy">'
      +'<a href="javascript:void(0)" class="pt-btnLink"></a>'
   +'</li>'
   +'<li class="pt-btn" id="pt-btn-paste">'
      +'<a href="javascript:void(0)" class="pt-btnLink"></a>'
   +'</li>'

   +'<li class="pt-btn" id="pt-btn-undo">'
      +'<a href="javascript:void(0)" class="pt-btnLink"></a>'
   +'</li>'
   +'<li class="pt-btn" id="pt-btn-redo">'
      +'<a href="javascript:void(0)" class="pt-btnLink"></a>'
   +'</li>'

   +'<li class="pt-btn" id="pt-btn-specialchars">'
      +'<a href="javascript:void(0)" class="pt-btnLink"></a>'
   +'</li>'
   +'<li class="pt-btn" id="pt-btn-help">'
      +'<a href="javascript:void(0)" class="pt-btnLink"></a>'
   +'</li>'
+'<ul>',


    specialCharBar :

'<ul>'
   +'<li class="pt-char" id="pt-char-ldquo">'
      +'<a href="javascript:void(0)" class="pt-charLink"></a>'
   +'</li>'
   +'<li class="pt-char" id="pt-char-rdquo">'
      +'<a href="javascript:void(0)" class="pt-charLink"></a>'
   +'</li>'
   +'<li class="pt-char" id="pt-char-lsquo">'
      +'<a href="javascript:void(0)" class="pt-charLink"></a>'
   +'</li>'
   +'<li class="pt-char" id="pt-char-rsquo">'
      +'<a href="javascript:void(0)" class="pt-charLink"></a>'
   +'</li>'
   +'<li class="pt-char" id="pt-char-ndash">'
      +'<a href="javascript:void(0)" class="pt-charLink"></a>'
   +'</li>'
+'</ul>'

};
