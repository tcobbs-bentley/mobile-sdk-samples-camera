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
        queryHandler = itmMessenger.registerQueryHandler("ImagePicker", handleQuery)
    }
    
    /// Handles the "ImagePicker" query.
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
        picker.sourceType = .camera
        picker.allowsEditing = true
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
        guard let image = info[UIImagePickerController.InfoKey.originalImage] as? UIImage else {
            presentedResolver?.fulfill(nil)
            picker.dismiss(animated: true, completion: nil)
            return
        }
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd HH-mm-ss.SSS"
        // Use a timestamp for the filename.
        let filename = "\(dateFmt.string(from: Date())).jpg"
        do {
            let baseURL = ImageCache.baseURL!
            let iModelId = self.iModelId!
            // The file will be stored in <Caches>/images/<iModelId>/. All pictures for a given iModel end up in the same directory.
            let dirUrl = baseURL.appendingPathComponent(iModelId)
            // Make sure the output directory exists.
            try FileManager.default.createDirectory(at: dirUrl, withIntermediateDirectories: true, attributes: nil)
            let fileUrl = dirUrl.appendingPathComponent(filename)
            // Write the UIImage to the given filename.
            try ImageCache.writeImage(image, to: fileUrl, with: info[.mediaMetadata] as? NSDictionary)
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
    static func handleDeleteImages(params: [String: Any]) -> Promise<()> {
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
    
    /// Deletes a specific image cache image.
    /// - Parameter params: Requires a `url` property containing an image cache URL string for the image to delete.
    /// - Returns: A Promise that resolves to Void.
    static func handleDeleteImage(params: [String: Any]) -> Promise<()> {
        guard let urlString = params["url"] as? String else {
            return Promise.value(())
        }
        let cacheUrl = URL(string: urlString)
        guard let fileUrl = getFileUrl(cacheUrl) else {
            return Promise.value(())
        }
        let fm = FileManager.default
        do {
            try fm.removeItem(at: fileUrl)
        } catch {}
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
