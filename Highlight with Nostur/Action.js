//
//  Action.js
//  Highlight with Nostur
//
//  Created by Fabian Lachman on 27/04/2023.
//

var Action = function() {};

Action.prototype = {
    
    run: function(arguments) {
        let title = encodeURIComponent(document.title)
        let text = encodeURIComponent(document.getSelection().toString())
        let url = encodeURIComponent(document.URL)
        let nosturURL = "nostur:highlight:" + text + ":url:" + url + ":title:" + title

        // On iOS, location.href opens the URL scheme directly via Safari.
        // On macOS, location.href doesn't work for custom schemes, so we also
        // pass the URL via completionFunction for the native handler to open.
        location.href = nosturURL
        arguments.completionFunction({ "nosturURL": nosturURL })
    },
    
    finalize: function(arguments) {
//        // This method is run after the native code completes.
//
//        // We'll see if the native code has passed us a new background style,
//        // and set it on the body.
//
//        var newBackgroundColor = arguments["newBackgroundColor"]
//        if (newBackgroundColor) {
//            // We'll set document.body.style.background, to override any
//            // existing background.
//            document.body.style.background = newBackgroundColor
//        } else {
//            // If nothing's been returned to us, we'll set the background to
//            // blue.
//            document.body.style.background= "blue"
//        }
    }
    
};
    
var ExtensionPreprocessingJS = new Action
