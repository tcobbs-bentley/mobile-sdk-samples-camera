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
   * Delete an image from the image cache.
   * @param url The URL of the image to delete.
   * @returns A void Promise that completes when the deletion has finished.
   */
  static async deleteImage(url: string): Promise<void> {
    ImageMarkerApi.deleteMarker(url);
    return Messenger.query("deleteImage", { url });
  }

  /**
   * Delete all cached images associated with a specific iModel.
   * @param iModelId The iModelId to delete the cached images from.
   * @returns A void Promise that completes when the deletion has finished.
   */
  static async deleteImages(iModelId: string | undefined): Promise<void> {
    ImageMarkerApi.deleteMarkers(iModelId);
    return Messenger.query("deleteImages", { iModelId });
  }

  /**
   * Gets the URLs of all the images cached for a specific iModel.
   * @param iModelId The iModelId to get the images for.
   * @returns A Promise that resolves to an array of strings representing all the image URLs.
   */
  static async getImages(iModelId: string | undefined): Promise<[string]> {
    return Messenger.query("getImages", { iModelId });
  }
}
