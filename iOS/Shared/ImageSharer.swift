/*---------------------------------------------------------------------------------------------
* Copyright (c) Bentley Systems, Incorporated. All rights reserved.
* See LICENSE.md in the project root for license terms and full copyright notice.
*--------------------------------------------------------------------------------------------*/

import PromiseKit
import UIKit
import ITwinMobile

class ImageSharer: ITMNativeUIComponent {
    override init(viewController: UIViewController, itmMessenger: ITMMessenger) {
        super.init(viewController: viewController, itmMessenger: itmMessenger)
        queryHandler = itmMessenger.registerQueryHandler("shareImages", handleQuery)
    }
    
    static func shareItems(items: [Any], vc: UIViewController, sourceRect: CGRect) {
        let shareActivity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = shareActivity.popoverPresentationController {
            popover.sourceView = vc.view
            popover.sourceRect = sourceRect
        }
        vc.present(shareActivity, animated: true, completion: nil)
    }
    
    func handleQuery(params: [String: Any]) -> Promise<()> {
        if let urls = params["urls"] as? [String],
           let vc = self.viewController {
            var rect = CGRect(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height, width: 0, height: 0)
            if let sourceRect = params["sourceRect"] as? [String: Any],
               let sourceRect: ITMRect = try? ITMDictionaryDecoder.decode(sourceRect) {
                rect = CGRect(sourceRect)
            }
            ImageSharer.shareItems(items: urls.compactMap { ImageCache.getFileUrl(URL(string: $0)) }, vc: vc, sourceRect: rect)
        }
        return Promise.value(())
    }
}
