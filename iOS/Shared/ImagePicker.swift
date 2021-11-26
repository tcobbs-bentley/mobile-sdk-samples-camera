/*---------------------------------------------------------------------------------------------
* Copyright (c) Bentley Systems, Incorporated. All rights reserved.
* See LICENSE.md in the project root for license terms and full copyright notice.
*--------------------------------------------------------------------------------------------*/

import PromiseKit
import UIKit
import ITwinMobile
import CoreServices
import WebKit

/// A `UIImagePickerController` subclass that supports landscape.
///
/// `UIImagePickerController` does not officially support landscape mode, but it definitely works fine for
/// the camera UI at least (which is all that this sample uses). This class simply enables all interface
/// orientations other than upside down on phone.
class ImagePickerFix: UIImagePickerController {
    override open var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        }
        return .all
    }
}

/// An `ITMNativeUIComponent` subclass for taking a picture with the camera.
class ImagePicker: ITMNativeUIComponent {
    /// The promise for the active query.
    var presentedPromise: Promise<String?>?
    /// The resolver for the active query.
    var presentedResolver: Resolver<String?>?
    /// The iModelId for the active query.
    var iModelId: String?
    override init(viewController: UIViewController, itmMessenger: ITMMessenger) {
        super.init(viewController: viewController, itmMessenger: itmMessenger)
        queryHandler = itmMessenger.registerQueryHandler("pickImage", handleQuery)
    }
    
    /// Handles the "pickImage" query.
    ///
    /// This shows the camera UI and returns a promise that when fulfilled will contain a URL using a custom scheme that
    /// resolves to the image taken by the camera.
    /// - Parameter params: The input params from JavaScript. This must contain an `iModelId` string property.
    /// - Returns: A `Promise` object that when fulfilled will contain a URL to the captured image. Note that this URL
    /// uses a custom URL scheme to allow the image to be loaded from the WKWebView.
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
            // The user has previously denined camera access to this app. Show a dialog that states
            // this, and allows the user to open iOS Settings to change the setting.
            ITMDevicePermissionsHelper.openPhotoCaptureAccessAccessDialog()
            presentedResolver.fulfill(nil)
            return presentedPromise
        }
        let picker = ImagePickerFix()
        picker.modalPresentationStyle = .fullScreen
        let sourceType = params["sourceType"] as? String
        if sourceType != "photoLibrary" {
            picker.sourceType = .camera
        }
        picker.mediaTypes = [String(kUTTypeImage)]
        picker.delegate = self
        viewController.present(picker, animated: true, completion: nil)
        return presentedPromise
    }
}

/// `UIImagePickerController`'s delgate must implement these protocols.
///
/// Everything in `UINavigationControllerDelegate` is optional, and we don't need to implement any of those methods.
///
/// This extension implements the `UIImagePickerControllerDelegate` methods that handle picking and image and canceling.
extension ImagePicker: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    /// Called when the user cancels picture taking.
    ///
    /// Fulfills the `Promise` with nil.
    /// - Parameter picker: The controller object managing the image picker interface.
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        presentedResolver?.fulfill(nil)
        picker.dismiss(animated: true, completion: nil)
    }
    
    /// Called after the user takes a picture.
    ///
    /// Writes the image to the app's cache and fulfills the promise with a custom URL scheme URL referencing the file.
    ///
    /// If there is any kind of error, rejects the promise.
    /// - Parameters:
    ///   - picker: The controller object managing the image picker interface.
    ///   - info: A dictionary containing the original image and the edited image.
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let imageUrl = info[UIImagePickerController.InfoKey.imageURL] as? URL
        let image = info[UIImagePickerController.InfoKey.originalImage] as? UIImage
        if imageUrl == nil, image == nil {
            presentedResolver?.fulfill(nil)
            picker.dismiss(animated: true, completion: nil)
            return
        }
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd-HH-mm-ss.SSS"
        // Use a timestamp for the filename.
        let filename = "\(dateFmt.string(from: Date())).jpg"
        do {
            let baseURL = ImageCache.baseURL!
            let iModelId = self.iModelId!
            // The file will be stored in <Caches>/images/<iModelId>/. All pictures for a given iModel end up in the same directory.
            let dirUrl = baseURL.appendingPathComponent(iModelId)
            let fm = FileManager.default
            // Make sure the output directory exists.
            try fm.createDirectory(at: dirUrl, withIntermediateDirectories: true, attributes: nil)
            let fileUrl = dirUrl.appendingPathComponent(filename)
            // If the user picks from the photo library, we'll get a URL for a local copy of the file from the photo library.
            // If the original file in the photo library was HEIC, the URL will be for a local JPEG copy. If the original file
            // in the photo library was a PNG or JPEG, the URL will be the exact original file. If we get a URL, simply copy
            // it to our cache.
            if let imageUrl = imageUrl {
                do {
                    // It has been reported that using moveItem here doesn't work in all versions of iOS.
                    try fm.moveItem(at: imageUrl, to: fileUrl)
                } catch {
                    // If moveItem fails, fall back to copyItem. Note that if copyItem fails here, it will jump to the
                    // catch block below, which rejects the promise.
                    try fm.copyItem(at: imageUrl, to: fileUrl)
                }
            } else if let image = image {
                // Write the UIImage to the given filename.
                try ImageCache.writeImage(image, to: fileUrl, with: info[.mediaMetadata] as? NSDictionary)
            }
            // Fulfill the promise with a custom URL scheme URL of the form:
            // com.bentley.itms-image-cache://<iModelId>/<filename>
            // The custom ImageCacheSchemeHandler will convert that back into a file URL and then load that file.
            presentedResolver?.fulfill("\(ImageCacheSchemeHandler.urlScheme)://\(iModelId)/\(filename)")
        } catch {
            // If anything went wrong above, reject the promise.
            presentedResolver?.reject(error)
        }
        picker.dismiss(animated: true, completion: nil)
    }
}

/// Custom `WKURLSchemeHandler` to support loading images from cache, when `WKWebView` will not allow loading file:// URLs for security reasons.
class ImageCacheSchemeHandler: NSObject, WKURLSchemeHandler {
    /// The URL scheme for this handler. FYI, "itms" stands for iTwin Mobile Sample.
    static let urlScheme = "com.bentley.itms-image-cache"
    /// `WKURLSchemeHandler` protocol method.
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let fileURL = ImageCache.getFileUrl(urlSchemeTask.request.url) else {
            ITMAssetHandler.cancelWithFileNotFound(urlSchemeTask: urlSchemeTask)
            return
        }
        ITMAssetHandler.respondWithDiskFile(urlSchemeTask: urlSchemeTask, fileUrl: fileURL)
    }

    /// `WKURLSchemeHandler` protocol method.
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Nothing to do here.
    }
}

/// Class for interacting with the image cache.
class ImageCache {
    /// Get all the images for a given iModel
    /// - Parameter params: Requires an `iModelId` property to specify which iModel to get images for.
    /// - Returns: A Promise that resolves to an array of image cache URLs for all the images in the cache for the given iModel
    static func handleGetImages(params: [String: Any]) -> Promise<[String]> {
        guard let iModelId = params["iModelId"] as? String, let dirURL = baseURL?.appendingPathComponent(iModelId) else {
            return Promise.value([])
        }
        let fm = FileManager.default
        var results: [String] = []
        // The prefix is an image cache URL pointing to the directory for this iModel.
        let prefix = "\(ImageCacheSchemeHandler.urlScheme)://\(iModelId)/"
        if let allURLs = try? fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil) {
            for url in allURLs {
                let urlString = NSString(string: "\(url)")
                results.append("\(prefix)\(urlString.lastPathComponent)")
            }
        }
        return Promise.value(results)
    }
    
    /// Deletes all the images in the cache for the given iModel.
    /// - Parameter params: Requires an `iModelId` property to specify which iModel to delete images for.
    /// - Returns: A Promise that resolves to Void.
    static func handleDeleteAllImages(params: [String: Any]) -> Promise<()> {
        guard let iModelId = params["iModelId"] as? String, let dirURL = baseURL?.appendingPathComponent(iModelId) else {
            return Promise.value(())
        }
        // Delete all the files in the image cache directory for the given iModel.
        let fm = FileManager.default
        if let allURLs = try? fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil) {
            for url in allURLs {
                do {
                    try fm.removeItem(at: url)
                } catch {}
            }
        }
        return Promise.value(())
    }
    
    private static func deleteImage(urlString: String) {
        if let fileUrl = getFileUrl(URL(string: urlString)) {
            do {
                try FileManager.default.removeItem(at: fileUrl)
            } catch {}
        }
    }
    
    /// Deletes a specific image cache image.
    /// - Parameter params: Requires a `urls` property containing a string or array of strings with the image cache URL's to delete.
    /// - Returns: A Promise that resolves to Void.
    static func handleDeleteImages(params: [String: Any]) -> Promise<()> {
        if let urls = params["urls"] as? [String] {
            for url in urls {
                deleteImage(urlString: url)
            }
        } else if let urlString = params["urls"] as? String {
            deleteImage(urlString: urlString)
        }
        return Promise.value(())
    }
    
    /// Convert an image cache URL into a file URL.
    /// - Parameter cacheUrl: The image cache URL to convert.
    /// - Returns: Upon success, a file URL that corresponds to the file referenced by the image cache URL, otherwise nil.
    static func getFileUrl(_ cacheUrl: URL?) -> URL? {
        guard let cacheUrl = cacheUrl, let scheme = cacheUrl.scheme else {
            return nil
        }
        let urlString = cacheUrl.absoluteString
        // I hate to say it, but Swift ROYALLY messed up substrings. This is totally inexcusable
        // garbage syntax in place of the now-deprecated clean and obvious substring(from:).
        let index = urlString.index(urlString.startIndex, offsetBy: scheme.count + 3)
        let cachePath = String(urlString[index...])
        if let baseURLString = ImageCache.baseURL?.absoluteString {
            return URL(string: "\(baseURLString)\(cachePath)")
        }
        return nil
    }

    /// The baseURL to use to store images.
    static var baseURL: URL? {
        get {
            guard let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).last else {
                return nil
            }
            return cachesDir.appendingPathComponent("images")
        }
    }
    
    /// Write a `UIImage` to the the given file URL.
    /// - Parameters:
    ///   - image: The `UIImage` to write to cache.
    ///   - url: The file URL to which to write the image.
    ///   - metadata: Metadata to include in the image.
    static func writeImage(_ image: UIImage, to url: URL, with metadata: NSDictionary?) throws {
        // Generate JPEG data for the UIImage.
        guard let imageData = image.jpegData(compressionQuality: 0.85) else { throw ITMError(json: ["message": "Error converting UIImage to JPEG."]) }
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { throw ITMError(json: ["message": "Error creating image source from JPEG data."]) }
        guard let type = CGImageSourceGetType(source) else { throw ITMError(json: ["message": "Error getting type from image source."]) }

        guard let destination: CGImageDestination = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else { throw ITMError(json: ["message": "Error creating image destination."]) }
        CGImageDestinationAddImageFromSource(destination, source, 0, metadata as CFDictionary?)
        if !CGImageDestinationFinalize(destination) {
            throw ITMError(json: ["message": "Error writing JPEG data."])
        }
    }
}

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
            if let sourceRect = params["sourceRect"] as? [String: Any] {
                // TODO: expose ITMDictionaryDecoder in ITMNativeUI so it can be used here instead
                rect = CGRect(x: sourceRect["x"]  as! Int,
                                    y: sourceRect["y"] as! Int,
                                    width: sourceRect["width"] as! Int,
                                    height: sourceRect["height"] as! Int)
            }
            ImageSharer.shareItems(items: urls.compactMap { ImageCache.getFileUrl(URL(string: $0)) }, vc: vc, sourceRect: rect)
        }
        return Promise.value(())
    }
}
