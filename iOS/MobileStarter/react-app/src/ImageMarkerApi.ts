/*---------------------------------------------------------------------------------------------
* Copyright (c) 2020 Bentley Systems, Incorporated. All rights reserved.
*--------------------------------------------------------------------------------------------*/
import {
  Point2d,
  Point3d,
  XAndY,
  XYAndZ
} from "@bentley/geometry-core";
import {
  BeButton,
  BeButtonEvent,
  BeTouchEvent,
  Cluster,
  DecorateContext,
  Decorator,
  IModelApp,
  Marker,
  MarkerImage,
  MarkerSet
} from "@bentley/imodeljs-frontend";
import { getCssVariable, UiEvent } from "@bentley/ui-core";

/** Displays a single image Marker at a given world location. */
class ImageMarker extends Marker {
  private static readonly HEIGHT = 100;
  private _url: string;
  private _onClickCallback?: (url: string) => void;

  constructor(point: Point3d, url: string, image: HTMLImageElement, onClickCallback?: (url: string) => void) {
    // Use the same height for all the markers, but preserve the aspect ratio from the image
    const aspect = image.width / image.height;
    const size = new Point2d(aspect * ImageMarker.HEIGHT, ImageMarker.HEIGHT);
    super(point, size);

    this._url = url;
    this._onClickCallback = onClickCallback;

    this.setImage(image);

    // The scale factor adjusts the size of the image so it appears larger when close to the camera eye point.
    // Make size 75% at back of frustum and 200% at front of frustum (if camera is on)
    this.setScaleFactor({ low: .75, high: 2.0 });
  }

  get url() {
    return this._url;
  }

  public onMouseButton(ev: BeButtonEvent): boolean {
    if ((ev instanceof BeTouchEvent && ev.isSingleTap) || (ev.button === BeButton.Data && ev.isDown)) {
      this._onClickCallback?.(this._url);
    }
    return true; // Don't allow clicks to be sent to active tool
  }

  public drawDecoration(ctx: CanvasRenderingContext2D) {
    // add a shadow to the image
    ctx.shadowBlur = 10;
    ctx.shadowColor = "black";

    super.drawDecoration(ctx);

    // draw a border around the image
    ctx.shadowBlur = 0;
    const size = this.imageSize ? this.imageSize : this.size;
    const offset = new Point2d(size.x / 2, size.y / 2);
    ctx.strokeStyle = "white";
    ctx.lineWidth = 2;
    ctx.strokeRect(-offset.x, -offset.y, size.x, size.y);
  }

  protected drawHilited(ctx: CanvasRenderingContext2D) {
    // Don't draw differently if we have a click handler
    if (this._onClickCallback)
      return false;
    return super.drawHilited(ctx);
  }
}

class BadgedImageMarker extends Marker {
  private count = 0;
  private static activeColor: string;

  constructor(location: XYAndZ, size: XAndY, cluster: Cluster<Marker>, image: MarkerImage) {
    super(location, size);
    this.setImage(image);
    this.count = cluster.markers.length;
    const aspect = image.width / image.height;
    const halfHeight = size.y / 2;
    this.labelOffset = { x: -((halfHeight * aspect) - 5), y: halfHeight - 5 };
    if (!BadgedImageMarker.activeColor)
      BadgedImageMarker.activeColor = getCssVariable("--muic-active");
  }

  public override drawDecoration(ctx: CanvasRenderingContext2D): void {
    super.drawDecoration(ctx);

    if (this.count !== 0) {
      ctx.font = this.labelFont ? this.labelFont : "14px sans-serif";
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      const text = this.count.toString();
      const metrics = ctx.measureText(text);
      const x = this.labelOffset ? -this.labelOffset.x : 0;
      const y = this.labelOffset ? -this.labelOffset.y : 0;

      //draw the badge background
      const fontHeight = metrics.fontBoundingBoxAscent + metrics.fontBoundingBoxDescent;
      const actualHeight = metrics.actualBoundingBoxAscent + metrics.actualBoundingBoxDescent;
      const measuredHeight = (actualHeight > 0 ? actualHeight : fontHeight);
      const padding = measuredHeight;
      const height = measuredHeight + padding;
      const width = Math.max(height, metrics.width + padding);
      ctx.fillStyle = BadgedImageMarker.activeColor;
      this.drawPill(ctx, x, y, width, height);

      //draw the badge number
      ctx.fillStyle = this.labelColor ? this.labelColor : "white";
      ctx.fillText(text, x, y);
    }
  }

  private drawPill(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number) {
    const radius = height / 2;
    ctx.beginPath();
    if (width <= height) {
      ctx.arc(x, y, radius, 0, Math.PI * 2);
    } else {
      const diff = width - height;
      ctx.arc(x + diff, y, radius, Math.PI / 2, Math.PI * 1.5, true);
      ctx.arc(x - diff, y, radius, Math.PI * 1.5, Math.PI / 2, true);
    }
    ctx.fill();
  }
}

class ImageMarkerSet extends MarkerSet<ImageMarker> {
  // minimumClusterSize = 2;

  protected getClusterMarker(cluster: Cluster<ImageMarker>): Marker {
    return BadgedImageMarker.makeFrom(cluster.markers[0], cluster, cluster.markers[0].image);
  }

  public addMarker(point: Point3d, image: HTMLImageElement, url: string) {
    this.markers.add(new ImageMarker(point, url, image, (url: string) => ImageMarkerApi.onMarkerClick.emit(url)));
    IModelApp.viewManager.selectedView?.invalidateDecorations();
  }

  public deleteMarker(url: string) {
    for (const marker of this.markers) {
      if (marker.url === url) {
        this.markers.delete(marker);
        IModelApp.viewManager.selectedView?.invalidateDecorations();
        return;
      }
    }
  }
}

class ImageMarkerDecorator implements Decorator {
  private _markerSet?: ImageMarkerSet;

  public addMarker(point: Point3d, image: HTMLImageElement, url: string) {
    if (!this._markerSet)
      this._markerSet = new ImageMarkerSet()
    this._markerSet.addMarker(point, image, url);
  }

  public deleteMarker(url: string) {
    this._markerSet?.deleteMarker(url);
  }

  public decorate(context: DecorateContext): void {
    this._markerSet?.addDecoration(context);
  }
}

export class ImageMarkerApi {
  private static _decorator?: ImageMarkerDecorator;

  public static onMarkerClick = new UiEvent<string>();

  public static startup(enabled = true) {
    this._decorator = new ImageMarkerDecorator();
    if (enabled)
      IModelApp.viewManager.addDecorator(this._decorator);
  }

  public static shutdown() {
    this.enabled = false;
    this._decorator = undefined;
  }

  public static get enabled(): boolean {
    return !!this._decorator && IModelApp.viewManager.decorators.includes(this._decorator);
  }

  public static set enabled(value: boolean) {
    if (value === this.enabled)
      return;

    if (value) {
      if (!this._decorator)
        this.startup();
      else
        IModelApp.viewManager.addDecorator(this._decorator);
    } else if (!!this._decorator) {
      IModelApp.viewManager.dropDecorator(this._decorator);
    }
  }

  public static addMarker(point: Point3d, image: HTMLImageElement, fileUrl: string) {
    this._decorator?.addMarker(point, image, fileUrl);
  }

  public static deleteMarker(fileUrl: string) {
    this._decorator?.deleteMarker(fileUrl);
  }
}
