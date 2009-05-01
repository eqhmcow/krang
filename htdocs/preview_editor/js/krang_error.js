var Krang;
if (Object.isUndefined(Krang)) { Krang = {} }

/**
   Krang.error(cmsBaseURL, errorString);

   Modal error message for preview editor.

*/
Krang.error = function(baseURL, error) {
    // default error
    if (!error) {
        error = 'Looks like a little bug (probably an Internal Server Error)<br/>Contact your System Administrator if this problem continues.';
    }

    // default base URL
    if (!baseURL) {
        baseURL = '';
    }

    ProtoPopup.Alert.get('krang_preview_editor_error', {
        modal:  true,
        width:  '500px',
        body:   error,
        cancelIconSrc:           false,
        bodyBackgroundImage:     'url("' + baseURL + '/images/bug.gif")',
        closeBtnBackgroundImage: 'url("' + baseURL + '/images/bkg-button-mini.gif")'
    }).show();
}
