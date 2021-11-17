/*---------------------------------------------------------------------------------------------
* Copyright (c) Bentley Systems, Incorporated. All rights reserved.
* See LICENSE.md in the project root for license terms and full copyright notice.
*--------------------------------------------------------------------------------------------*/

import PromiseKit
import UIKit
import ITwinMobile
import CoreServices
import WebKit

class ImagePickerFix: UIImagePickerController {
    override open var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }
}

class ImagePicker: ITMNativeUIComponent {
    var presentedPromise: Promise<String?>?
    var presentedResolver: Resolver<String?>?
    var iModelId: String?
    override init(viewController: UIViewController, itmMessenger: ITMMessenger) {
        super.init(viewController: viewController, itmMessenger: itmMessenger)
        queryHandler = itmMessenger.registerQueryHandler("ImagePicker", handleQuery)
    }

    private func handleQuery(params: [String: Any]) -> Promise<String?> {
        (presentedPromise, presentedResolver) = Promise<String?>.pending()
        let presentedPromise = presentedPromise!
        let presentedResolver = presentedResolver!
        guard let viewController = viewController else {
            presentedResolver.reject(ITMError())
            return presentedPromise
        }
        iModelId = params["iModelId"] as? String
        if iModelId == nil {
            presentedResolver.reject(ITMError())
            return presentedPromise
        }
        if ITMDevicePermissionsHelper.isPhotoCaptureDenied {
            ITMDevicePermissionsHelper.openPhotoCaptureAccessAccessDialog()
            presentedResolver.fulfill(nil)
            return presentedPromise
        }
        let picker = ImagePickerFix()
        picker.modalPresentationStyle = .fullScreen
        picker.sourceType = .camera
        picker.allowsEditing = true
        picker.mediaTypes = [String(kUTTypeImage)]
        picker.delegate = self
        viewController.present(picker, animated: true, completion: nil)
        return presentedPromise
    }
    
    func writeImage(_ image: UIImage, to url: URL, with metadata: NSDictionary?) -> Bool {
        guard let imageData = image.jpegData(compressionQuality: 0.85) else { return false }
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return false }
        guard let type = CGImageSourceGetType(source) else { return false }

        guard let destination: CGImageDestination = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else { return false }
        CGImageDestinationAddImageFromSource(destination, source, 0, metadata as CFDictionary?)
        return CGImageDestinationFinalize(destination)
    }
}

extension ImagePicker: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        presentedResolver?.fulfill(nil)
        picker.dismiss(animated: true, completion: nil)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        guard let image = info[UIImagePickerController.InfoKey.originalImage] as? UIImage else {
            presentedResolver?.fulfill(nil)
            picker.dismiss(animated: true, completion: nil)
            return
        }
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd-HH-mm-ss.SSS"
        let filename = "\(dateFmt.string(from: Date())).jpg"
        guard let baseURL = ImagePicker.baseURL() else {
            presentedResolver?.fulfill(nil)
            picker.dismiss(animated: true, completion: nil)
            return
        }
        let dirUrl = baseURL.appendingPathComponent(iModelId!)
        do {
            try FileManager.default.createDirectory(at: dirUrl, withIntermediateDirectories: true, attributes: nil)
            let fileUrl = dirUrl.appendingPathComponent(filename)
            if writeImage(image, to: fileUrl, with: info[.mediaMetadata] as? NSDictionary) {
                presentedResolver?.fulfill("\(ImageCacheSchemeHandler.urlScheme)://\(iModelId!)/\(filename)")
            } else {
                presentedResolver?.reject(ITMError())
            }
        } catch {
            presentedResolver?.reject(ITMError())
        }
        picker.dismiss(animated: true, completion: nil)
    }
    
    static func baseURL() -> URL? {
        guard let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).last else {
            return nil
        }
        return cachesDir.appendingPathComponent("images")
    }
}

class ImageCacheSchemeHandler: NSObject, WKURLSchemeHandler {
    static let urlScheme = "com-bentley-itms-image-cache"
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let cachePath = cachePath(from: urlSchemeTask),
              let baseURLString = ImagePicker.baseURL()?.absoluteString,
              let fileURL = URL(string: "\(baseURLString)\(cachePath)") else {
            ITMAssetHandler.cancelWithFileNotFound(urlSchemeTask: urlSchemeTask)
            return
        }
        ITMAssetHandler.respondWithDiskFile(urlSchemeTask: urlSchemeTask, fileUrl: fileURL)
    }
    
    func cachePath(from urlSchemeTask: WKURLSchemeTask) -> String? {
        guard let url = urlSchemeTask.request.url, let scheme = url.scheme else {
            return nil
        }
        return NSString(string: url.absoluteString).substring(from: scheme.count + 3)
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Nothing to do here.
    }
}

