//
//  ShareViewController.swift
//  Wire-iOS Share Extension
//
//  Created by Jacob on 23/09/16.
//  Copyright © 2016 Zeta Project Germany GmbH. All rights reserved.
//

import UIKit
import Social

class ShareViewController: SLComposeServiceViewController {
    
    var conversationItem : SLComposeSheetConfigurationItem?

    override func isContentValid() -> Bool {
        // Do validation of contentText and/or NSExtensionContext attachments here
        return true
    }

    override func didSelectPost() {
        // This is called after the user selects Post. Do the upload of contentText and/or NSExtensionContext attachments.
    
        // Inform the host that we're done, so it un-blocks its UI. Note: Alternatively you could call super's -didSelectPost, which will similarly complete the extension context.
        self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
    }

    override func configurationItems() -> [Any]! {
        conversationItem = SLComposeSheetConfigurationItem()
        conversationItem!.title = NSString(string: "Share to:") as String
        conversationItem!.value = NSString(string: "None") as String
        conversationItem!.tapHandler = {
            // TBD
        }
        
        // To add configuration options via table cells at the bottom of the sheet, return an array of SLComposeSheetConfigurationItem here.
        return [conversationItem]
    }
    
}
