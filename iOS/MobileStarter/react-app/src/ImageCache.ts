import { Messenger } from "@itwin/mobile-sdk-core";
import { ImageMarkerApi } from "./Exports";

/**
 * Helper class for dealing with native messages relating to the image cache.
 */
export class ImageCache {
  /**
   * Get an image, either by taking a camera picture, or picking one from the photo library.
   * @param iModelId The iModelId to associate the image with.
   * @param photoLibrary true to pick from the photo library, or false to take a new picture with the camera, default is false.
   * @returns The URL of the newly picked image.
   */
  static async pickImage(iModelId: string | undefined, photoLibrary = false): Promise<string | undefined> {
    return Messenger.query("pickImage", { iModelId, sourceType: photoLibrary ? "photoLibrary" : "camera" });
  }

  /**
   * Delete images from the image cache.
   * @param urls An array of URL's of the images to delete.
   * @returns A void Promise that completes when the deletion has finished.
   */
  static async deleteImages(urls: string[]): Promise<void> {
    urls.forEach((currUrl) => ImageMarkerApi.deleteMarker(currUrl));
    return Messenger.query("deleteImages", { url: urls });
  }

  /**
   * Delete all cached images associated with a specific iModel.
   * @param iModelId The iModelId to delete the cached images from.
   * @returns A void Promise that completes when the deletion has finished.
   */
  static async deleteAllImages(iModelId: string | undefined): Promise<void> {
    ImageMarkerApi.deleteMarkers(iModelId);
    return Messenger.query("deleteAllImages", { iModelId });
  }

  /**
   * Gets the URLs of all the images cached for a specific iModel.
   * @param iModelId The iModelId to get the images for.
   * @returns A Promise that resolves to an array of strings representing all the image URLs.
   */
  static async getImages(iModelId: string | undefined): Promise<string[]> {
    return Messenger.query("getImages", { iModelId });
  }
}
