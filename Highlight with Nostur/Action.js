//
//  Action.js
//  Highlight with Nostur
//
//  Created by Fabian Lachman on 27/04/2023.
//

var Action = function() {};

Action.prototype = {
    
    run: function(arguments) {
        // Here, you can run code that modifies the document and/or prepares
        // things to pass to your action's native code.
        
        // We will not modify anything, but will pass the body's background
        // style to the native code.
        
        let title = encodeURIComponent(document.title)
        let text = encodeURIComponent(document.getSelection().toString())
        let url = encodeURIComponent(document.URL)
        location.href="nostur:highlight:" + text + ":url:" + url + ":title:" + title
        
//        arguments.completionFunction({ "currentBackgroundColor" : document.body.style.backgroundColor })
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
