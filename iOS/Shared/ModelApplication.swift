/*---------------------------------------------------------------------------------------------
* Copyright (c) Bentley Systems, Incorporated. All rights reserved.
* See LICENSE.md in the project root for license terms and full copyright notice.
*--------------------------------------------------------------------------------------------*/

import UIKit
import WebKit
import ITwinMobile
import PromiseKit
import UniformTypeIdentifiers

/// This app's `ITMApplication` sub-class that handles the messages coming from the web view.
class ModelApplication: ITMApplication {
    /// Registers query handlers.
    required init() {
        super.init()
        ITMApplication.logger = PrintLogger()
        registerQueryHandler("didFinishLaunching") { () -> Promise<()> in
            self.itmMessenger.frontendLaunchSuceeded()
            return Promise.value(())
        }
        registerQueryHandler("loading") { () -> Promise<()> in
            self.webView.isHidden = false
            return Promise.value(())
        }
        registerQueryHandler("reload") { () -> Promise<()> in
            self.webView.reload()
            return Promise.value(())
        }
        registerQueryHandler("getBimDocuments") { () -> Promise<[String]> in
            if #available(iOS 14.0, *) {
                return Promise.value(DocumentHelper.getDocumentsWith(extension: UTType.bim_iModel.preferredFilenameExtension!))
            } else {
                return Promise.value(DocumentHelper.getDocumentsWith(extension: "bim"))
            }
        }
        registerQueryHandler("getImages", ImageCache.handleGetImages)
        registerQueryHandler("deleteImages", ImageCache.handleDeleteImages)
        registerQueryHandler("deleteImage", ImageCache.handleDeleteImage)
    }

    /// Called when the `ITMViewController` will appear.
    ///
    /// Adds our DocumentPicker component to the native UI collection.
    /// - Parameter viewController: The view controller.
    override func viewWillAppear(viewController: ITMViewController) {
        if let itmNativeUI = viewController.itmNativeUI {
            let itmMessenger = ITMViewController.application.itmMessenger
            itmNativeUI.addComponent(DocumentPicker(viewController: viewController, itmMessenger: itmMessenger))
            itmNativeUI.addComponent(ImagePicker(viewController: viewController, itmMessenger: itmMessenger))
        }
    }

    override class func updateWebViewConfiguration(_ configuration: WKWebViewConfiguration) {
        configuration.setURLSchemeHandler(ImageCacheSchemeHandler(), forURLScheme: ImageCacheSchemeHandler.urlScheme)
    }
}
